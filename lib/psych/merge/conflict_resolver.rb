# frozen_string_literal: true

module Psych
  module Merge
    # Resolves conflicts between template and destination YAML content
    # using structural signatures and configurable preferences.
    #
    # Inherits from Ast::Merge::ConflictResolverBase using the :batch strategy,
    # which resolves all conflicts at once using signature maps.
    #
    # @example Basic usage
    #   resolver = ConflictResolver.new(template_analysis, dest_analysis)
    #   resolver.resolve(result)
    #
    # @example With recursive merge for nested structures
    #   resolver = ConflictResolver.new(
    #     template_analysis,
    #     dest_analysis,
    #     recursive: true,
    #     add_template_only_nodes: true
    #   )
    #
    # @see Ast::Merge::ConflictResolverBase
    class ConflictResolver < Ast::Merge::ConflictResolverBase
      # Creates a new ConflictResolver
      #
      # @param template_analysis [FileAnalysis] Analyzed template file
      # @param dest_analysis [FileAnalysis] Analyzed destination file
      # @param preference [Symbol, Hash] Which version to prefer when
      #   nodes have matching signatures:
      #   - :destination (default) - Keep destination version (customizations)
      #   - :template - Use template version (updates)
      # @param add_template_only_nodes [Boolean] Whether to add nodes only in template
      # @param remove_template_missing_nodes [Boolean] Whether to remove destination nodes not in template
      # @param recursive [Boolean, Integer] Whether to merge nested structures recursively
      #   - true: unlimited depth (default)
      #   - false: disabled
      #   - Integer > 0: max depth
      # @param match_refiner [#call, nil] Optional match refiner for fuzzy matching
      # @param options [Hash] Additional options for forward compatibility
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type preferences
      def initialize(template_analysis, dest_analysis, preference: :destination, add_template_only_nodes: false, remove_template_missing_nodes: false, recursive: true, match_refiner: nil, node_typing: nil, **options)
        super(
          strategy: :batch,
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          add_template_only_nodes: add_template_only_nodes,
          remove_template_missing_nodes: remove_template_missing_nodes,
          recursive: recursive,
          match_refiner: match_refiner,
          **options
        )
        @node_typing = node_typing
        @emitter = Emitter.new
      end

      protected

      # Resolve conflicts and populate the result
      #
      # @param result [MergeResult] Result object to populate
      def resolve_batch(result)
        DebugLogger.time("ConflictResolver#resolve") do
          template_nodes = @template_analysis.statements
          dest_nodes = @dest_analysis.statements

          # Clear emitter for fresh merge
          @emitter.clear

          # Build signature maps
          template_by_sig = build_signature_map(template_nodes, @template_analysis)
          dest_by_sig = build_signature_map(dest_nodes, @dest_analysis)

          # Build refined matches for nodes that don't match by signature
          @refined_matches = build_refined_matches(template_nodes, dest_nodes, template_by_sig, dest_by_sig)

          # Process nodes via emitter
          merge_nodes_to_emitter(
            template_nodes,
            dest_nodes,
            template_by_sig,
            emit_destination_postlude: true,
          )

          # Transfer emitter output to result
          emitted_content = @emitter.to_s
          unless emitted_content.empty?
            emitted_content.lines.each do |line|
              result.add_line(line.chomp, decision: MergeResult::DECISION_MERGED, source: :merged)
            end
          end

          DebugLogger.debug("Conflict resolution complete", {
            template_nodes: template_nodes.size,
            dest_nodes: dest_nodes.size,
            result_lines: result.line_count,
          })
        end
      end

      private

      # Build a map of refined matches from template node to destination node.
      # Uses the match_refiner to find additional pairings for nodes that didn't match by signature.
      #
      # @param template_nodes [Array] Template nodes
      # @param dest_nodes [Array] Destination nodes
      # @param template_by_sig [Hash] Template signature map
      # @param dest_by_sig [Hash] Destination signature map
      # @return [Hash] Map of template node to destination node
      def build_refined_matches(template_nodes, dest_nodes, template_by_sig, dest_by_sig)
        return {} unless @match_refiner

        # Find unmatched nodes
        matched_template_sigs = template_by_sig.keys & dest_by_sig.keys
        unmatched_t_nodes = template_nodes.reject do |n|
          sig = @template_analysis.generate_signature(n)
          sig && matched_template_sigs.include?(sig)
        end
        unmatched_d_nodes = dest_nodes.reject do |n|
          sig = @dest_analysis.generate_signature(n)
          sig && matched_template_sigs.include?(sig)
        end

        return {} if unmatched_t_nodes.empty? || unmatched_d_nodes.empty?

        # Call the refiner
        matches = @match_refiner.call(unmatched_t_nodes, unmatched_d_nodes, {
          template_analysis: @template_analysis,
          dest_analysis: @dest_analysis,
        })

        # Build result map: template node -> dest node
        matches.each_with_object({}) do |match, h|
          h[match.template_node] = match.dest_node
        end
      end

      def merge_nodes_to_emitter(template_nodes, dest_nodes, template_by_sig, depth: 0, emit_destination_postlude: false)
        # Build reverse lookup from dest_node to template_node for refined matches
        refined_dest_to_template = @refined_matches.invert
        next_template_by_id = build_next_node_lookup(template_nodes)
        next_dest_by_id = build_next_node_lookup(dest_nodes)

        emit_document_prelude(@dest_analysis, nodes: dest_nodes) if emit_destination_postlude

        # Track consumed individual node indices (not just signatures) so that
        # multiple nodes sharing the same signature are matched 1:1 in order
        # rather than collapsed into a single match.
        consumed_template_indices = ::Set.new
        sig_cursor = Hash.new(0)

        # Track previous node end_line to preserve inter-node blank lines.
        # Blank lines between top-level YAML sections (e.g., between `name:` and `on:`)
        # are not part of any node or comment — they are purely visual separators.
        # We preserve them from the destination to maintain readability.
        prev_end_line = nil

        # First pass: Process destination nodes and find matches
        dest_nodes.each do |dest_node|
          next_dest_node = next_dest_by_id[dest_node.object_id]
          dest_sig = @dest_analysis.generate_signature(dest_node)

          # Preserve inter-node blank lines from destination
          if prev_end_line && dest_node.respond_to?(:start_line) && dest_node.start_line
            effective_start = effective_start_line(dest_node, @dest_analysis)

            # Emit blank lines that existed between the previous node and this one
            gap_start = prev_end_line + 1
            if gap_start < effective_start
              (gap_start...effective_start).each do |line_num|
                if @dest_analysis.respond_to?(:comment_tracker) &&
                    @dest_analysis.comment_tracker.blank_line?(line_num)
                  @emitter.emit_blank_line
                end
              end
            end
          end

          # Update tracking for the current node's end line
          effective_dest_end_line = effective_end_line(dest_node, @dest_analysis, next_node: next_dest_node)
          if effective_dest_end_line
            prev_end_line = effective_dest_end_line
          elsif dest_node.respond_to?(:end_line) && dest_node.end_line
            prev_end_line = dest_node.end_line
          end

          # Freeze blocks from destination are always preserved
          if freeze_node?(dest_node)
            emit_freeze_block(dest_node)
            next
          end

          # Check for signature match first
          if dest_sig && template_by_sig[dest_sig]
            # Find the next unconsumed template node with this signature
            candidates = template_by_sig[dest_sig]
            cursor = sig_cursor[dest_sig]
            template_info = nil

            while cursor < candidates.size
              candidate = candidates[cursor]
              unless consumed_template_indices.include?(candidate[:index])
                template_info = candidate
                break
              end
              cursor += 1
            end

            if template_info
              template_node = template_info[:node]

              # Check if we should recursively merge nested structures
              if should_recurse?(depth) && can_merge_recursively?(template_node, dest_node)
                emit_recursive_merge(template_node, dest_node, depth: depth)
              else
                emit_preferred_node(
                  template_node,
                  dest_node,
                  next_template_node: next_template_by_id[template_node.object_id],
                  next_dest_node: next_dest_node,
                )
              end

              consumed_template_indices << template_info[:index]
              sig_cursor[dest_sig] = cursor + 1
            else
              # All template copies consumed — destination-only duplicate
              if @remove_template_missing_nodes
                emit_removed_destination_node_comments(dest_node, @dest_analysis)
              else
                emit_node(dest_node, @dest_analysis, next_node: next_dest_node)
              end
            end
          elsif refined_dest_to_template.key?(dest_node)
            # Found refined match
            template_node = refined_dest_to_template[dest_node]
            template_sig = @template_analysis.generate_signature(template_node)

            # Find and consume the matching template index
            if template_sig && template_by_sig[template_sig]
              template_by_sig[template_sig].each do |info|
                unless consumed_template_indices.include?(info[:index])
                  consumed_template_indices << info[:index]
                  break
                end
              end
            end

            # Check if we should recursively merge nested structures
            if should_recurse?(depth) && can_merge_recursively?(template_node, dest_node)
              emit_recursive_merge(template_node, dest_node, depth: depth)
            else
              emit_preferred_node(
                template_node,
                dest_node,
                next_template_node: next_template_by_id[template_node.object_id],
                next_dest_node: next_dest_node,
              )
            end
          else
            # Destination-only node
            # If remove_template_missing_nodes is enabled, skip this node (remove it)
            if @remove_template_missing_nodes
              emit_removed_destination_node_comments(dest_node, @dest_analysis)
            else
              emit_node(dest_node, @dest_analysis, next_node: next_dest_node)
            end
          end
        end

        # Second pass: Add template-only nodes if configured
        if @add_template_only_nodes
          template_nodes.each_with_index do |template_node, idx|
            # Skip if consumed by a match in the first pass
            next if consumed_template_indices.include?(idx)

            # Skip freeze blocks from template
            next if freeze_node?(template_node)

            # Add template-only node
            emit_node(
              template_node,
              @template_analysis,
              next_node: next_template_by_id[template_node.object_id],
            )
          end
        end

        if emit_destination_postlude
          emit_document_postlude(
            @dest_analysis,
            fallback_node: dest_nodes.last,
          )
        end
      end

      def emit_preferred_node(template_node, dest_node, next_template_node: nil, next_dest_node: nil)
        if preference_for_pair(template_node, dest_node) == :destination
          emit_node(dest_node, @dest_analysis, next_node: next_dest_node)
        else
          emit_node(
            template_node,
            @template_analysis,
            next_node: next_template_node,
            comment_source_node: dest_node,
            comment_analysis: @dest_analysis,
          )
        end
      end

      def preference_for_pair(template_node, dest_node)
        return @preference unless @preference.is_a?(Hash)

        typed_template = apply_node_typing(template_node)
        typed_dest = apply_node_typing(dest_node)

        if Ast::Merge::NodeTyping.typed_node?(typed_template)
          merge_type = Ast::Merge::NodeTyping.merge_type_for(typed_template)
          return @preference.fetch(merge_type) { default_preference } if merge_type
        end

        if Ast::Merge::NodeTyping.typed_node?(typed_dest)
          merge_type = Ast::Merge::NodeTyping.merge_type_for(typed_dest)
          return @preference.fetch(merge_type) { default_preference } if merge_type
        end

        default_preference
      end

      def apply_node_typing(node)
        return node unless @node_typing
        return node unless node

        Ast::Merge::NodeTyping.process(node, @node_typing)
      end

      # Check if two nodes can be merged recursively (both are mappings or sequences)
      #
      # @param template_node [MappingEntry, NodeWrapper] Template node
      # @param dest_node [MappingEntry, NodeWrapper] Destination node
      # @return [Boolean] Whether recursive merge is possible
      def can_merge_recursively?(template_node, dest_node)
        # Both must have nested mapping or sequence values
        return false unless template_node.respond_to?(:mapping?) && dest_node.respond_to?(:mapping?)

        if template_node.mapping? && dest_node.mapping?
          !flow_mapping?(template_node) && !flow_mapping?(dest_node)
        elsif template_node.sequence? && dest_node.sequence?
          # Flow sequences (e.g., `key: [val1, val2]`) occupy the same physical
          # line as their key.  Recursing into them would emit the key line via
          # emit_recursive_merge AND then re-emit it via emit_sequence_item,
          # producing a duplicate.  Only recurse when the value spans additional
          # lines beyond the key (block sequence).
          !flow_sequence?(template_node) && !flow_sequence?(dest_node)
        else
          false
        end
      end

      # Detect flow sequences where the value occupies the same line(s) as the key.
      # A flow sequence like `github: [pboling]` has key and value on the same
      # start_line, so emitting the key line separately would duplicate content.
      #
      # @param node [MappingEntry, NodeWrapper] Node to check
      # @return [Boolean] true when the sequence value starts on the same line as the key
      def flow_sequence?(node)
        return false unless node.respond_to?(:key) && node.respond_to?(:value)
        return false unless node.key && node.value

        key_start_line = node.key&.start_line
        value_start_line = node.value&.start_line
        return false unless key_start_line && value_start_line

        key_start_line == value_start_line
      end

      def flow_mapping?(node)
        return false unless node.respond_to?(:key) && node.respond_to?(:value)
        return false unless node.key && node.value
        return false unless node.value.respond_to?(:mapping?) && node.value.mapping?

        key_start_line = node.key&.start_line
        value_start_line = node.value&.start_line
        return false unless key_start_line && value_start_line

        key_start_line == value_start_line
      end

      # Emit a recursively merged node
      #
      # @param template_node [MappingEntry, NodeWrapper] Template node with nested structure
      # @param dest_node [MappingEntry, NodeWrapper] Destination node with nested structure
      # @param depth [Integer] Current recursion depth
      def emit_recursive_merge(template_node, dest_node, depth:)
        # Preserve the destination prelude (leading comments / blank lines) for
        # recursively merged mapping entries, then emit the key line.
        if dest_node.respond_to?(:key) && dest_node.key
          emit_mapping_entry_prelude(dest_node, @dest_analysis)
          emit_mapping_entry_key_line(dest_node, @dest_analysis)
        end

        if template_node.mapping? && dest_node.mapping?
          emit_recursive_mapping_merge(template_node, dest_node, depth: depth)
        elsif template_node.sequence? && dest_node.sequence?
          emit_recursive_sequence_merge(template_node, dest_node, depth: depth)
        end
      end

      # Recursively merge two mapping values
      #
      # @param template_node [MappingEntry, NodeWrapper] Template node with mapping value
      # @param dest_node [MappingEntry, NodeWrapper] Destination node with mapping value
      # @param depth [Integer] Current recursion depth
      def emit_recursive_mapping_merge(template_node, dest_node, depth:)
        # Get the mapping node:
        # - MappingEntry has .value which is a NodeWrapper wrapping the mapping
        # - NodeWrapper that IS a mapping should be used directly
        template_value = if template_node.respond_to?(:value) && template_node.value&.mapping?
          template_node.value
        elsif template_node.mapping?
          template_node
        end

        return unless template_value

        dest_value = if dest_node.respond_to?(:value) && dest_node.value&.mapping?
          dest_node.value
        elsif dest_node.mapping?
          dest_node
        end

        return unless dest_value

        # Get nested entries from both
        template_entries = template_value.mapping_entries(comment_tracker: @template_analysis.comment_tracker)
        dest_entries = dest_value.mapping_entries(comment_tracker: @dest_analysis.comment_tracker)

        # Convert to MappingEntry objects for consistent handling
        template_nested = template_entries.map do |key_wrapper, value_wrapper|
          MappingEntry.new(
            key: key_wrapper,
            value: value_wrapper,
            lines: @template_analysis.lines,
            comment_tracker: @template_analysis.comment_tracker,
          )
        end

        dest_nested = dest_entries.map do |key_wrapper, value_wrapper|
          MappingEntry.new(
            key: key_wrapper,
            value: value_wrapper,
            lines: @dest_analysis.lines,
            comment_tracker: @dest_analysis.comment_tracker,
          )
        end

        # Build signature maps for nested entries
        nested_template_by_sig = {}
        template_nested.each_with_index do |entry, idx|
          sig = [:mapping_entry, entry.key_name]
          nested_template_by_sig[sig] ||= []
          nested_template_by_sig[sig] << {node: entry, index: idx}
        end

        # Recursively merge nested entries
        merge_nodes_to_emitter(
          template_nested,
          dest_nested,
          nested_template_by_sig,
          depth: depth + 1,
        )
      end

      # Recursively merge two sequence values (arrays)
      # Uses union semantics: keeps all destination items, adds template-only items
      #
      # @param template_node [MappingEntry, NodeWrapper] Template node with sequence value
      # @param dest_node [MappingEntry, NodeWrapper] Destination node with sequence value
      # @param depth [Integer] Current recursion depth
      def emit_recursive_sequence_merge(template_node, dest_node, depth:)
        # Get the sequence node:
        # - MappingEntry has .value which is a NodeWrapper wrapping the sequence
        # - NodeWrapper that IS a sequence should be used directly
        template_value = if template_node.respond_to?(:value) && template_node.value&.sequence?
          template_node.value
        elsif template_node.sequence?
          template_node
        end

        dest_value = if dest_node.respond_to?(:value) && dest_node.value&.sequence?
          dest_node.value
        elsif dest_node.sequence?
          dest_node
        end

        return unless template_value && dest_value

        template_items = template_value.sequence_items(comment_tracker: @template_analysis.comment_tracker)
        dest_items = dest_value.sequence_items(comment_tracker: @dest_analysis.comment_tracker)

        template_items_by_key = build_sequence_item_match_map(template_items, @template_analysis)
        consumed_template_indices = ::Set.new
        key_cursor = Hash.new(0)

        dest_items.each do |item|
          match_key = sequence_item_match_key(item, @dest_analysis)
          template_info = next_sequence_item_match(template_items_by_key, match_key, key_cursor, consumed_template_indices)

          if template_info
            template_item = template_info[:item]

            if should_recurse?(depth) && can_merge_recursively?(template_item, item)
              emit_recursive_merge(template_item, item, depth: depth)
            elsif preference_for_pair(template_item, item) == :destination
              emit_sequence_item(item, @dest_analysis)
            else
              emit_sequence_item(
                template_item,
                @template_analysis,
                comment_source_node: item,
                comment_analysis: @dest_analysis,
              )
            end

            consumed_template_indices << template_info[:index]
          elsif @remove_template_missing_nodes
            emit_removed_sequence_item_comments(item, @dest_analysis, depth: depth)
          else
            emit_sequence_item(item, @dest_analysis)
          end
        end

        # If add_template_only_nodes, add template items not in destination
        return unless @add_template_only_nodes

        template_items.each_with_index do |item, idx|
          next if consumed_template_indices.include?(idx)

          emit_sequence_item(item, @template_analysis)
        end
      end

      # Emit a single sequence item
      #
      # @param item [NodeWrapper] Sequence item to emit
      # @param analysis [FileAnalysis] Analysis for accessing source
      def emit_sequence_item(item, analysis, comment_source_node: nil, comment_analysis: analysis)
        return unless item.start_line && item.end_line

        emit_node_prelude(item, analysis, comment_source_node: comment_source_node, comment_analysis: comment_analysis)

        lines = trimmed_sequence_item_lines(item, analysis)
        return if lines.empty?

        emit_node_first_line(lines.shift, item, analysis, comment_source_node: comment_source_node, comment_analysis: comment_analysis)
        @emitter.emit_raw_lines(lines) if lines.any?
      end

      # Emit a single node to the emitter
      # @param node [NodeWrapper, MappingEntry] Node to emit
      # @param analysis [FileAnalysis] Analysis for accessing source
      def emit_node(node, analysis, next_node: nil, comment_source_node: nil, comment_analysis: analysis)
        return if freeze_node?(node)

        if node.is_a?(MappingEntry)
          emit_mapping_entry(
            node,
            analysis,
            next_node: next_node,
            comment_source_node: comment_source_node,
            comment_analysis: comment_analysis,
          )
          return
        end

        emit_node_prelude(node, analysis, comment_source_node: comment_source_node, comment_analysis: comment_analysis)

        # Emit the node content
        if node.respond_to?(:start_line) && node.respond_to?(:end_line)
          # Regular node - emit its lines
          if node.start_line && node.end_line
            end_line = effective_end_line(node, analysis, next_node: next_node)
            lines = []
            (node.start_line..end_line).each do |line_num|
              line = analysis.line_at(line_num)
              lines << line if line
            end
            unless lines.empty?
              emit_node_first_line(lines.shift, node, analysis, comment_source_node: comment_source_node, comment_analysis: comment_analysis)
              @emitter.emit_raw_lines(lines) if lines.any?
            end
          end
        end
      end

      # Emit a mapping entry
      # @param entry [MappingEntry] The mapping entry
      # @param analysis [FileAnalysis] Analysis for accessing source
      def emit_mapping_entry(entry, analysis, next_node: nil, comment_source_node: nil, comment_analysis: analysis)
        return unless entry.respond_to?(:start_line) && entry.respond_to?(:end_line)

        emit_mapping_entry_prelude(entry, analysis, comment_source_node: comment_source_node, comment_analysis: comment_analysis)

        content_start_line = mapping_entry_content_start_line(entry)
        end_line = effective_end_line(entry, analysis, next_node: next_node)
        return unless content_start_line && end_line
        return if end_line < content_start_line

        if entry.respond_to?(:key) && entry.key&.start_line == content_start_line
          emit_mapping_entry_key_line(entry, analysis, comment_source_node: comment_source_node, comment_analysis: comment_analysis)
          content_start_line += 1
        end

        return if content_start_line > end_line

        lines = []
        (content_start_line..end_line).each do |line_num|
          line = analysis.line_at(line_num)
          lines << line if line
        end
        @emitter.emit_raw_lines(lines) if lines.any?
      end

      # Emit a freeze block
      # @param freeze_node [FreezeNode] Freeze block to emit
      def emit_freeze_block(freeze_node)
        @emitter.emit_raw_lines(freeze_node.lines)
      end

      def emit_mapping_entry_prelude(entry, analysis, comment_source_node: nil, comment_analysis: analysis)
        content_start_line = mapping_entry_content_start_line(entry)
        return unless content_start_line

        leading_region = preferred_leading_comment_region(entry, comment_source_node)
        if leading_region && !leading_region.empty?
          source_analysis = resolved_comment_analysis(analysis, comment_source_node, comment_analysis, leading_region)
          source_node = resolved_comment_node(entry, comment_source_node, leading_region)
          source_content_start_line = node_content_start_line(source_node)

          @emitter.emit_comment_region(leading_region, source_lines: source_analysis&.lines)
          emit_interstitial_blank_lines(
            (leading_region.end_line || source_content_start_line) + 1,
            source_content_start_line - 1,
            source_analysis,
          ) if source_analysis && source_content_start_line
          return
        end

        return unless entry.respond_to?(:start_line) && entry.start_line
        return unless entry.start_line < content_start_line

        lines = []
        (entry.start_line...content_start_line).each do |line_num|
          line = analysis.line_at(line_num)
          lines << line if line
        end
        @emitter.emit_raw_lines(lines) if lines.any?
      end

      def emit_node_prelude(node, analysis, comment_source_node: nil, comment_analysis: analysis)
        content_start_line = node_content_start_line(node)
        return unless content_start_line

        leading_region = preferred_leading_comment_region(node, comment_source_node)
        if leading_region && !leading_region.empty?
          source_analysis = resolved_comment_analysis(analysis, comment_source_node, comment_analysis, leading_region)
          source_node = resolved_comment_node(node, comment_source_node, leading_region)
          source_content_start_line = node_content_start_line(source_node)

          @emitter.emit_comment_region(leading_region, source_lines: source_analysis&.lines)
          emit_interstitial_blank_lines(
            (leading_region.end_line || source_content_start_line) + 1,
            source_content_start_line - 1,
            source_analysis,
          ) if source_analysis && source_content_start_line
          return
        end

        return unless node.respond_to?(:start_line) && node.start_line
        return unless analysis.respond_to?(:comment_tracker)

        leading = analysis.comment_tracker.leading_comments_before(node.start_line)
        unless leading.empty?
          leading.each do |comment|
            @emitter.emit_tracked_comment(comment)
          end
          # Preserve blank line between comments and the node if one existed
          last_comment_line = leading.last[:line]
          if node.start_line - last_comment_line > 1 &&
              analysis.comment_tracker.blank_line?(last_comment_line + 1)
            @emitter.emit_blank_line
          end
        end
      end

      def emit_mapping_entry_key_line(entry, analysis, comment_source_node: nil, comment_analysis: analysis)
        return unless entry.respond_to?(:key) && entry.key&.start_line

        key_line = analysis.line_at(entry.key.start_line)
        return unless key_line

        emit_node_first_line(key_line, entry, analysis, comment_source_node: comment_source_node, comment_analysis: comment_analysis)
      end

      def emit_node_first_line(line, node, analysis, comment_source_node: nil, comment_analysis: analysis)
        inline_region = preferred_inline_comment_region(node, comment_source_node)
        unless inline_region && !inline_region.empty?
          @emitter.emit_raw_lines([line])
          return
        end

        existing_inline_region = node_inline_comment_region(node)
        line = strip_inline_comment_from_line(line, existing_inline_region) if existing_inline_region && !existing_inline_region.empty?

        @emitter.emit_raw_lines([line])
        @emitter.emit_comment_region(
          inline_region,
          inline: true,
          source_lines: resolved_comment_analysis(analysis, comment_source_node, comment_analysis, inline_region)&.lines,
        )
      end

      def emit_removed_destination_node_comments(node, analysis)
        leading_region = node_leading_comment_region(node)
        content_start_line = node_content_start_line(node)
        if leading_region && !leading_region.empty?
          @emitter.emit_comment_region(leading_region, source_lines: analysis.lines)
          emit_interstitial_blank_lines((leading_region.end_line || content_start_line) + 1, content_start_line - 1, analysis) if content_start_line
        end

        emit_removed_destination_node_inline_comments(node, analysis)
      end

      def emit_removed_destination_node_inline_comments(node, analysis)
        inline_region = node_inline_comment_region(node)
        return unless inline_region && !inline_region.empty?

        tracked_hashes = Array(inline_region.metadata[:tracked_hashes])
        if tracked_hashes.any?
          tracked_hashes.each do |comment|
            line_num = comment[:line] || comment["line"]
            line = analysis.line_at(line_num)
            indent = line.to_s[/\A\s*/].to_s.length
            @emitter.emit_tracked_comment(comment.merge(indent: indent))
          end
        else
          @emitter.emit_comment_region(inline_region, inline: false, source_lines: analysis.lines)
        end
      end

      def emit_removed_sequence_item_comments(item, analysis, depth:)
        if should_recurse?(depth) && item.mapping?
          emit_removed_sequence_mapping_item_comments(item, analysis, depth: depth)
        elsif should_recurse?(depth) && item.sequence?
          emit_removed_nested_sequence_item_comments(item, analysis, depth: depth)
        else
          emit_removed_destination_node_comments(item, analysis)
        end
      end

      def emit_removed_sequence_mapping_item_comments(item, analysis, depth:)
        nested_entries = item.mapping_entries(comment_tracker: analysis.comment_tracker).map do |key_wrapper, value_wrapper|
          MappingEntry.new(
            key: key_wrapper,
            value: value_wrapper,
            lines: analysis.lines,
            comment_tracker: analysis.comment_tracker,
          )
        end

        merge_nodes_to_emitter([], nested_entries, {}, depth: depth + 1)
      end

      def build_sequence_item_match_map(items, analysis)
        items.each_with_index.with_object({}) do |(item, idx), map|
          match_key = sequence_item_match_key(item, analysis)
          map[match_key] ||= []
          map[match_key] << {item: item, index: idx}
        end
      end

      def next_sequence_item_match(items_by_key, match_key, key_cursor, consumed_template_indices)
        candidates = items_by_key[match_key]
        return unless candidates

        cursor = key_cursor[match_key]
        template_info = nil

        while cursor < candidates.size
          candidate = candidates[cursor]
          unless consumed_template_indices.include?(candidate[:index])
            template_info = candidate
            break
          end
          cursor += 1
        end

        key_cursor[match_key] = cursor + 1 if template_info
        template_info
      end

      def sequence_item_match_key(item, analysis)
        return [:scalar, item.value] if item.scalar?
        return [:alias, item.alias_anchor] if item.alias?

        nested_sequence_identity = sequence_nested_item_identity(item, analysis)
        return nested_sequence_identity if nested_sequence_identity

        mapping_identity = sequence_mapping_item_identity(item, analysis)
        return mapping_identity if mapping_identity

        [:fingerprint, sequence_item_fingerprint(item, analysis)]
      end

      def sequence_mapping_item_identity(item, analysis)
        return unless item.mapping?

        scalar_entries = item.mapping_entries(comment_tracker: analysis.comment_tracker).filter_map do |key_wrapper, value_wrapper|
          next unless key_wrapper&.value && value_wrapper&.scalar?

          [key_wrapper.value, value_wrapper.value]
        end
        return if scalar_entries.empty?

        %w[id name key path file pattern].each do |identity_key|
          pair = scalar_entries.find { |key, _value| key == identity_key }
          next unless pair

          stable_auxiliary_pairs = scalar_entries.reject do |key, _value|
            key == identity_key || key == "value"
          end.sort_by(&:first)

          return [:mapping_scalar_identity, identity_key, pair[1], stable_auxiliary_pairs] if stable_auxiliary_pairs.any?

          return [:mapping_scalar_identity, identity_key, pair[1]]
        end

        return [:mapping_scalar_identity, scalar_entries.first[0], scalar_entries.first[1]] if scalar_entries.one?

        nil
      end

      def sequence_nested_item_identity(item, analysis)
        return unless item.sequence?

        nested_items = item.sequence_items(comment_tracker: analysis.comment_tracker)
        return if nested_items.empty?

        first_item = nested_items.first
        [:nested_sequence_identity, sequence_item_match_key(first_item, analysis)]
      end

      def emit_removed_nested_sequence_item_comments(item, analysis, depth:)
        nested_items = item.sequence_items(comment_tracker: analysis.comment_tracker)
        merge_nodes_to_emitter([], nested_items, {}, depth: depth + 1)
      end

      def sequence_item_fingerprint(item, analysis)
        return [:scalar, item.value] if item.scalar?
        return [:fallback, item.content] unless item.respond_to?(:start_line) && item.respond_to?(:end_line)
        return [:fallback, item.content] unless item.start_line && item.end_line

        [:raw_lines, trimmed_sequence_item_lines(item, analysis)]
      end

      def trimmed_sequence_item_lines(item, analysis)
        lines = (item.start_line..item.end_line).map { |line_num| analysis.line_at(line_num) }.compact
        return lines if lines.empty?

        first_content_line = lines.find { |line| !line.strip.empty? }
        return lines unless first_content_line

        base_indent = first_content_line[/\A\s*/].to_s.length
        cutoff_index = lines.index do |line|
          next false if line.strip.empty?

          indent = line[/\A\s*/].to_s.length
          indent < base_indent
        end

        trimmed_lines = cutoff_index ? lines.take(cutoff_index) : lines
        trimmed_lines.pop while trimmed_lines.any? && trimmed_lines.last.strip.empty?
        trimmed_lines
      end

      def build_next_node_lookup(nodes)
        lookup = {}

        nodes.each_with_index do |node, idx|
          lookup[node.object_id] = nodes[idx + 1]
        end

        lookup
      end

      def effective_end_line(node, analysis, next_node: nil)
        return unless node.respond_to?(:end_line) && node.end_line

        end_line = node.end_line
        return end_line unless next_node && next_node.respond_to?(:start_line) && next_node.start_line

        boundary = next_node.start_line - 1
        if analysis.respond_to?(:comment_tracker)
          boundary -= 1 while boundary >= 1 && analysis.comment_tracker.blank_line?(boundary)
        end

        [end_line, [boundary, node_content_start_line(node)].max].min
      end

      def emit_trailing_lines_after_last_node(node, analysis)
        return unless node

        after_line = effective_end_line(node, analysis)
        return unless after_line && analysis.respond_to?(:lines)
        return if after_line >= analysis.lines.length

        lines = ((after_line + 1)..analysis.lines.length).map { |line_num| analysis.line_at(line_num) }.compact
        @emitter.emit_raw_lines(lines) if lines.any?
      end

      def emit_document_postlude(analysis, fallback_node: nil)
        augmenter = document_comment_augmenter_for(analysis)
        postlude = augmenter&.postlude_region

        if postlude && !postlude.empty?
          if fallback_node && postlude.respond_to?(:start_line) && postlude.start_line
            last_content_line = effective_end_line(fallback_node, analysis)
            emit_interstitial_blank_lines(last_content_line + 1, postlude.start_line - 1, analysis) if last_content_line
          end
          @emitter.emit_comment_region(postlude, source_lines: analysis.lines)
        else
          emit_trailing_lines_after_last_node(fallback_node, analysis)
        end
      end

      def emit_document_prelude(analysis, nodes: [])
        augmenter = document_comment_augmenter_for(analysis)
        return unless augmenter

        normalized_nodes = Array(nodes)
        regions = []
        preamble = augmenter.preamble_region
        regions << preamble if preamble && !preamble.empty?

        if normalized_nodes.empty?
          augmenter.orphan_regions.each do |region|
            regions << region if region && !region.empty?
          end
        end

        regions.each do |region|
          @emitter.emit_comment_region(region, source_lines: analysis.lines)
        end

        return if regions.empty?

        last_region_end = regions.last.end_line
        if normalized_nodes.any?
          first_node_start = effective_start_line(normalized_nodes.first, analysis)
          emit_interstitial_blank_lines(last_region_end + 1, first_node_start - 1, analysis) if last_region_end && first_node_start
        else
          emit_interstitial_blank_lines(last_region_end + 1, analysis.lines.length, analysis) if last_region_end
        end
      end

      def document_comment_augmenter_for(analysis)
        @document_comment_augmenters ||= {}
        @document_comment_augmenters[analysis.object_id] ||= analysis.comment_augmenter
      end

      def node_content_start_line(node)
        if node.respond_to?(:key) && node.key&.start_line
          node.key.start_line
        elsif node.respond_to?(:start_line) && node.start_line
          node.start_line
        else
          1
        end
      end

      def effective_start_line(node, analysis)
        return unless node

        leading_region = node_leading_comment_region(node)
        return leading_region.start_line if leading_region && leading_region.start_line
        return node.start_line unless analysis.respond_to?(:comment_tracker) && node.respond_to?(:start_line) && node.start_line

        leading = analysis.comment_tracker.leading_comments_before(node.start_line)
        leading.any? && leading.first[:line] ? leading.first[:line] : node.start_line
      end

      def mapping_entry_content_start_line(entry)
        return entry.key.start_line if entry.respond_to?(:key) && entry.key&.start_line
        return entry.start_line if entry.respond_to?(:start_line)

        nil
      end

      def node_leading_comment_region(node)
        return unless node.respond_to?(:leading_comment_region)

        node.leading_comment_region
      end

      def node_inline_comment_region(node)
        return unless node.respond_to?(:inline_comment_region)

        node.inline_comment_region
      end

      def preferred_leading_comment_region(node, comment_source_node = nil)
        source_region = node_leading_comment_region(comment_source_node) if comment_source_node
        return source_region if source_region && !source_region.empty?

        node_leading_comment_region(node)
      end

      def preferred_inline_comment_region(node, comment_source_node = nil)
        source_region = node_inline_comment_region(comment_source_node) if comment_source_node
        return source_region if source_region && !source_region.empty?

        node_inline_comment_region(node)
      end

      def resolved_comment_analysis(default_analysis, comment_source_node, comment_analysis, region)
        return default_analysis unless comment_source_node && comment_analysis

        source_leading = node_leading_comment_region(comment_source_node)
        source_inline = node_inline_comment_region(comment_source_node)
        return comment_analysis if source_leading.equal?(region) || source_inline.equal?(region)

        default_analysis
      end

      def resolved_comment_node(default_node, comment_source_node, region)
        return default_node unless comment_source_node

        source_leading = node_leading_comment_region(comment_source_node)
        source_inline = node_inline_comment_region(comment_source_node)
        return comment_source_node if source_leading.equal?(region) || source_inline.equal?(region)

        default_node
      end

      def emit_interstitial_blank_lines(start_line, end_line, analysis)
        return unless analysis
        return unless start_line && end_line && start_line <= end_line

        lines = []
        (start_line..end_line).each do |line_num|
          line = analysis.line_at(line_num)
          lines << line if line && line.strip.empty?
        end
        @emitter.emit_raw_lines(lines) if lines.any?
      end

      def strip_inline_comment_from_line(line, inline_region)
        tracked_hash = inline_region.metadata[:tracked_hashes]&.first
        indent = tracked_hash && (tracked_hash[:indent] || tracked_hash["indent"])

        stripped = if indent
          line[0...indent].to_s.rstrip
        else
          line.sub(/\s+#.*\z/, "")
        end

        stripped.empty? ? line : stripped
      end
    end
  end
end

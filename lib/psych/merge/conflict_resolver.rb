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

      def merge_nodes_to_emitter(template_nodes, dest_nodes, template_by_sig, depth: 0)
        # Build reverse lookup from dest_node to template_node for refined matches
        refined_dest_to_template = @refined_matches.invert

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
          dest_sig = @dest_analysis.generate_signature(dest_node)

          # Preserve inter-node blank lines from destination
          if prev_end_line && dest_node.respond_to?(:start_line) && dest_node.start_line
            # Determine the effective start line (before leading comments)
            effective_start = dest_node.start_line
            if @dest_analysis.respond_to?(:comment_tracker)
              leading = @dest_analysis.comment_tracker.leading_comments_before(dest_node.start_line)
              effective_start = leading.first[:line] if leading.any? && leading.first[:line]
            end

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
          if dest_node.respond_to?(:end_line) && dest_node.end_line
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
                emit_preferred_node(template_node, dest_node)
              end

              consumed_template_indices << template_info[:index]
              sig_cursor[dest_sig] = cursor + 1
            else
              # All template copies consumed — destination-only duplicate
              unless @remove_template_missing_nodes
                emit_node(dest_node, @dest_analysis)
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
              emit_preferred_node(template_node, dest_node)
            end
          else
            # Destination-only node
            # If remove_template_missing_nodes is enabled, skip this node (remove it)
            unless @remove_template_missing_nodes
              emit_node(dest_node, @dest_analysis)
            end
          end
        end

        # Second pass: Add template-only nodes if configured
        return unless @add_template_only_nodes

        template_nodes.each_with_index do |template_node, idx|
          # Skip if consumed by a match in the first pass
          next if consumed_template_indices.include?(idx)

          # Skip freeze blocks from template
          next if freeze_node?(template_node)

          # Add template-only node
          emit_node(template_node, @template_analysis)
        end
      end

      def emit_preferred_node(template_node, dest_node)
        if preference_for_pair(template_node, dest_node) == :destination
          emit_node(dest_node, @dest_analysis)
        else
          emit_node(template_node, @template_analysis)
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
          true
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

        node.key.start_line == node.value.start_line
      end

      # Emit a recursively merged node
      #
      # @param template_node [MappingEntry, NodeWrapper] Template node with nested structure
      # @param dest_node [MappingEntry, NodeWrapper] Destination node with nested structure
      # @param depth [Integer] Current recursion depth
      def emit_recursive_merge(template_node, dest_node, depth:)
        # Get the key line from destination (preserves formatting/comments)
        # MappingEntry has a key attribute, NodeWrapper does not
        if dest_node.respond_to?(:key) && dest_node.key
          key_line = @dest_analysis.line_at(dest_node.key.start_line)
          @emitter.emit_raw_lines([key_line]) if key_line
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

        # Build a set of destination scalar values for deduplication
        dest_values = ::Set.new
        dest_items.each do |item|
          dest_values << item.value if item.scalar?
        end

        # First, emit all destination items (unless remove_template_missing_nodes)
        if @remove_template_missing_nodes
          # Only emit destination items that exist in template
          template_values = ::Set.new
          template_items.each do |item|
            template_values << item.value if item.scalar?
          end

          dest_items.each do |item|
            if item.scalar?
              # Only keep if exists in template
              if template_values.include?(item.value)
                emit_sequence_item(item, @dest_analysis)
              end
            else
              # Non-scalar items: keep by default (complex matching not implemented)
              emit_sequence_item(item, @dest_analysis)
            end
          end
        else
          # Keep all destination items
          dest_items.each do |item|
            emit_sequence_item(item, @dest_analysis)
          end
        end

        # If add_template_only_nodes, add template items not in destination
        return unless @add_template_only_nodes

        template_items.each do |item|
          if item.scalar?
            # Only add if not already in destination
            unless dest_values.include?(item.value)
              emit_sequence_item(item, @template_analysis)
            end
          else
            # Non-scalar items: check by content/signature (simplified: always add)
            # TODO: More sophisticated matching for nested objects in arrays
            emit_sequence_item(item, @template_analysis)
          end
        end
      end

      # Emit a single sequence item
      #
      # @param item [NodeWrapper] Sequence item to emit
      # @param analysis [FileAnalysis] Analysis for accessing source
      def emit_sequence_item(item, analysis)
        if item.start_line && item.end_line
          lines = []
          (item.start_line..item.end_line).each do |line_num|
            line = analysis.line_at(line_num)
            lines << line if line
          end
          @emitter.emit_raw_lines(lines)
        end
      end

      # Emit a single node to the emitter
      # @param node [NodeWrapper, MappingEntry] Node to emit
      # @param analysis [FileAnalysis] Analysis for accessing source
      def emit_node(node, analysis)
        return if freeze_node?(node)

        # Emit leading comments and any blank line separator before the node
        if node.respond_to?(:start_line) && node.start_line
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

        # Emit the node content
        if node.is_a?(MappingEntry)
          # MappingEntry has specific format
          emit_mapping_entry(node, analysis)
        elsif node.respond_to?(:start_line) && node.respond_to?(:end_line)
          # Regular node - emit its lines
          if node.start_line && node.end_line
            lines = []
            (node.start_line..node.end_line).each do |line_num|
              line = analysis.line_at(line_num)
              lines << line if line
            end
            @emitter.emit_raw_lines(lines)
          end
        end
      end

      # Emit a mapping entry
      # @param entry [MappingEntry] The mapping entry
      # @param analysis [FileAnalysis] Analysis for accessing source
      def emit_mapping_entry(entry, analysis)
        # MappingEntry should have key and value
        # For now, emit as raw lines since we don't have full mapping entry structure
        if entry.respond_to?(:start_line) && entry.respond_to?(:end_line)
          lines = []
          (entry.start_line..entry.end_line).each do |line_num|
            line = analysis.line_at(line_num)
            lines << line if line
          end
          @emitter.emit_raw_lines(lines)
        end
      end

      # Emit a freeze block
      # @param freeze_node [FreezeNode] Freeze block to emit
      def emit_freeze_block(freeze_node)
        @emitter.emit_raw_lines(freeze_node.lines)
      end
    end
  end
end

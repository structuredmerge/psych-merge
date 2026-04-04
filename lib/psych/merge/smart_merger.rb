# frozen_string_literal: true

module Psych
  module Merge
    # Main entry point for intelligent YAML file merging.
    # SmartMerger orchestrates the merge process using FileAnalysis,
    # ConflictResolver, and MergeResult to merge two YAML files intelligently.
    #
    # @example Basic merge (destination customizations preserved)
    #   merger = SmartMerger.new(template_yaml, dest_yaml)
    #   result = merger.merge
    #   File.write("output.yml", result)
    #
    # @example Template updates win
    #   merger = SmartMerger.new(
    #     template_yaml,
    #     dest_yaml,
    #     preference: :template,
    #     add_template_only_nodes: true
    #   )
    #   result = merger.merge
    #
    # @example Recursive merge with template additions
    #   merger = SmartMerger.new(
    #     template_yaml,
    #     dest_yaml,
    #     recursive: true,
    #     add_template_only_nodes: true
    #   )
    #   # Nested structures are merged recursively, template-only items added
    #
    # @example With custom signature generator
    #   sig_gen = ->(node) {
    #     if node.is_a?(MappingEntry) && node.key_name == "version"
    #       [:special_version, node.key_name]
    #     else
    #       node # Fall through to default
    #     end
    #   }
    #   merger = SmartMerger.new(template, dest, signature_generator: sig_gen)
    #
    # @example With regions (embedded content)
    #   merger = SmartMerger.new(template, dest,
    #     regions: [{ detector: SomeDetector.new, merger_class: SomeMerger }])
    class SmartMerger < ::Ast::Merge::SmartMergerBase
      # Creates a new SmartMerger for intelligent YAML file merging.
      #
      # @param template_content [String] Template YAML source code
      # @param dest_content [String] Destination YAML source code
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param preference [Symbol] Which version to prefer when
      #   nodes have matching signatures:
      #   - :destination (default) - Keep destination version (customizations)
      #   - :template - Use template version (updates)
      # @param add_template_only_nodes [Boolean] Whether to add nodes only in template
      # @param remove_template_missing_nodes [Boolean] Whether to remove destination nodes not in template
      # @param recursive [Boolean, Integer] Whether to merge nested structures recursively
      #   - true: unlimited depth (default)
      #   - false: disabled
      #   - Integer > 0: max depth
      # @param freeze_token [String] Token for freeze block markers
      # @param match_refiner [#call, nil] Optional match refiner for fuzzy matching of
      #   unmatched nodes. Default: nil (fuzzy matching disabled).
      #   Set to MappingMatchRefiner.new to enable fuzzy key matching.
      # @param regions [Array<Hash>, nil] Region configurations for nested merging
      # @param region_placeholder [String, nil] Custom placeholder for regions
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type merge preferences
      # @param options [Hash] Additional options for forward compatibility
      #
      # @raise [TemplateParseError] If template has syntax errors
      # @raise [DestinationParseError] If destination has syntax errors
      def initialize(
        template_content,
        dest_content,
        signature_generator: nil,
        preference: :destination,
        add_template_only_nodes: false,
        add_template_only_sequence_items: nil,
        remove_template_missing_nodes: false,
        recursive: true,
        freeze_token: FileAnalysis::DEFAULT_FREEZE_TOKEN,
        match_refiner: nil,
        regions: nil,
        region_placeholder: nil,
        node_typing: nil,
        **options
      )
        @remove_template_missing_nodes = remove_template_missing_nodes
        @recursive = recursive
        @add_template_only_sequence_items = add_template_only_sequence_items
        super(
          template_content,
          dest_content,
          signature_generator: signature_generator,
          preference: preference,
          add_template_only_nodes: add_template_only_nodes,
          freeze_token: freeze_token,
          match_refiner: match_refiner,
          regions: regions,
          region_placeholder: region_placeholder,
          node_typing: node_typing,
          **options
        )
      end

      # @return [Boolean] Whether to remove destination nodes not in template
      attr_reader :remove_template_missing_nodes

      # @return [Boolean, Integer] Whether to merge nested structures recursively
      attr_reader :recursive

      # Perform the merge and return the result as a YAML string.
      #
      # @return [String] Merged YAML content
      def merge
        merge_result.to_yaml
      end

      # Perform the merge and return detailed results including debug info.
      #
      # @return [Hash] Hash containing :content, :statistics, :decisions
      def merge_with_debug
        content = merge

        {
          content: content,
          statistics: @result.statistics,
          decisions: @result.decision_summary,
          template_analysis: {
            valid: @template_analysis.valid?,
            statements: @template_analysis.statements.size,
            freeze_blocks: @template_analysis.freeze_blocks.size,
          },
          dest_analysis: {
            valid: @dest_analysis.valid?,
            statements: @dest_analysis.statements.size,
            freeze_blocks: @dest_analysis.freeze_blocks.size,
          },
        }
      end

      # Check if both files were parsed successfully.
      #
      # @return [Boolean]
      def valid?
        @template_analysis.valid? && @dest_analysis.valid?
      end

      # Get any parse errors from template or destination.
      #
      # @return [Array] Array of errors
      def errors
        errors = []
        errors.concat(@template_analysis.errors.map { |e| {source: :template, error: e} })
        errors.concat(@dest_analysis.errors.map { |e| {source: :destination, error: e} })
        errors
      end

      protected

      # @return [Class] The analysis class for YAML files
      def analysis_class
        FileAnalysis
      end

      # @return [String] The default freeze token for YAML
      def default_freeze_token
        FileAnalysis::DEFAULT_FREEZE_TOKEN
      end

      # @return [Class] The resolver class for YAML files
      def resolver_class
        ConflictResolver
      end

      # @return [Class] The result class for YAML files
      def result_class
        MergeResult
      end

      # Perform the YAML-specific merge
      #
      # @return [MergeResult] The merge result
      def perform_merge
        @resolver.resolve(@result)

        DebugLogger.debug("Merge complete", {
          lines: @result.line_count,
          decisions: @result.statistics,
        })

        @result
      end

      # Build the resolver with YAML-specific signature
      def build_resolver
        ConflictResolver.new(
          @template_analysis,
          @dest_analysis,
          preference: @preference,
          add_template_only_nodes: @add_template_only_nodes,
          add_template_only_sequence_items: @add_template_only_sequence_items,
          remove_template_missing_nodes: @remove_template_missing_nodes,
          recursive: @recursive,
          match_refiner: @match_refiner,
          node_typing: @node_typing,
        )
      end

      # Build the result (no-arg constructor for YAML)
      def build_result
        MergeResult.new
      end

      # @return [Class] The template parse error class for YAML
      def template_parse_error_class
        TemplateParseError
      end

      # @return [Class] The destination parse error class for YAML
      def destination_parse_error_class
        DestinationParseError
      end
    end
  end
end

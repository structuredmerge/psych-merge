# frozen_string_literal: true

module Psych
  module Merge
    # Wraps Psych::Nodes with comment associations, line information, and signatures.
    # This provides a unified interface for working with YAML nodes during merging.
    #
    # @example Basic usage
    #   ast = Psych.parse_stream(yaml)
    #   wrapper = NodeWrapper.new(ast.children.first, lines: source.lines)
    #   wrapper.signature # => [:document, ...]
    class NodeWrapper
      # @return [Psych::Nodes::Node] The wrapped Psych node
      attr_reader :node

      # @return [Array<Hash>] Leading comments associated with this node
      attr_reader :leading_comments

      # @return [Hash, nil] Inline/trailing comment on the same line
      attr_reader :inline_comment

      # @return [Integer] Start line (1-based)
      attr_reader :start_line

      # @return [Integer] End line (1-based)
      attr_reader :end_line

      # @return [String, nil] Key name for mapping entries
      attr_reader :key

      # @return [Array<String>] Source lines
      attr_reader :lines

      # @return [CommentTracker, nil] Comment tracker used to associate comments
      attr_reader :comment_tracker

      # @param node [Psych::Nodes::Node] Psych node to wrap
      # @param lines [Array<String>] Source lines for content extraction
      # @param leading_comments [Array<Hash>] Comments before this node
      # @param inline_comment [Hash, nil] Inline comment on the node's line
      # @param key [String, nil] Key name if this is a mapping value
      def initialize(node, lines:, leading_comments: [], inline_comment: nil, key: nil, comment_tracker: nil)
        @node = node
        @lines = lines
        @leading_comments = leading_comments
        @inline_comment = inline_comment
        @key = key
        @comment_tracker = comment_tracker

        # Extract line information from the Psych node.
        #
        # IMPORTANT: Psych (libyaml) line number semantics:
        # - start_line: 0-based, inclusive (first line of the node's content)
        # - end_line: 0-based, EXCLUSIVE (points to the line AFTER the last content line)
        #
        # Example for a mapping value spanning lines 4-5 (1-based):
        #   Psych reports: start_line=3, end_line=5 (0-based)
        #   - start_line=3 means line 4 (1-based) - correct
        #   - end_line=5 means "up to but not including line 5 (0-based)",
        #     i.e., last included line is 4 (0-based) = line 5 (1-based)
        #
        # Conversion to 1-based inclusive range:
        # - @start_line = node.start_line + 1  (0-based inclusive → 1-based inclusive)
        # - @end_line = node.end_line          (0-based exclusive → 1-based inclusive, since exclusive-1+1=same)
        #
        # If Psych/libyaml ever changes end_line to be inclusive, this will need adjustment.
        # See regression test: "does not duplicate keys when destination adds a new nested mapping"
        @start_line = node.start_line + 1 if node.respond_to?(:start_line) && node.start_line
        @end_line = node.end_line if node.respond_to?(:end_line) && node.end_line

        # Handle edge case where end_line might be before start_line
        @end_line = @start_line if @start_line && @end_line && @end_line < @start_line
      end

      # Generate a signature for this node for matching purposes.
      # Signatures are used to identify corresponding nodes between template and destination.
      #
      # @return [Array, nil] Signature array or nil if not signaturable
      def signature
        compute_signature(@node)
      end

      # Check if this is a freeze node
      # @return [Boolean]
      def freeze_node?
        false
      end

      # Check if this wraps a mapping node
      # @return [Boolean]
      def mapping?
        @node.is_a?(::Psych::Nodes::Mapping)
      end

      # Check if this wraps a sequence node
      # @return [Boolean]
      def sequence?
        @node.is_a?(::Psych::Nodes::Sequence)
      end

      # Check if this wraps a scalar node
      # @return [Boolean]
      def scalar?
        @node.is_a?(::Psych::Nodes::Scalar)
      end

      # Check if this wraps an alias node
      # @return [Boolean]
      def alias?
        @node.is_a?(::Psych::Nodes::Alias)
      end

      # Get the anchor name if this node has one
      # @return [String, nil]
      def anchor
        @node.anchor if @node.respond_to?(:anchor)
      end

      # Get children wrapped as NodeWrappers
      # @param comment_tracker [CommentTracker] For associating comments with children
      # @return [Array<NodeWrapper>]
      def children(comment_tracker: nil)
        return [] unless @node.respond_to?(:children) && @node.children

        wrap_children(@node.children, comment_tracker)
      end

      # Get mapping entries as key-value pairs of NodeWrappers
      # @param comment_tracker [CommentTracker] For associating comments with children
      # @return [Array<Array(NodeWrapper, NodeWrapper)>] Array of [key_wrapper, value_wrapper] pairs
      def mapping_entries(comment_tracker: nil)
        return [] unless mapping?

        entries = []
        children = @node.children
        i = 0
        while i < children.length
          key_node = children[i]
          value_node = children[i + 1]
          break unless key_node && value_node

          key_wrapper = wrap_node(key_node, comment_tracker)
          value_wrapper = wrap_node(value_node, comment_tracker, key: extract_key_name(key_node))

          entries << [key_wrapper, value_wrapper]
          i += 2
        end

        entries
      end

      # Get sequence items as NodeWrappers
      # @param comment_tracker [CommentTracker] For associating comments with children
      # @return [Array<NodeWrapper>]
      def sequence_items(comment_tracker: nil)
        return [] unless sequence?

        @node.children.map { |child| wrap_node(child, comment_tracker) }
      end

      # Get the scalar value
      # @return [String, nil]
      def value
        @node.value if scalar?
      end

      # Get the aliased anchor name
      # @return [String, nil]
      def alias_anchor
        @node.anchor if alias?
      end

      # Get the content for this node from source lines
      # @return [String]
      def content
        return "" unless @start_line && @end_line

        (@start_line..@end_line).map { |ln| @lines[ln - 1] }.join
      end

      # Get a passive shared comment attachment for this node wrapper.
      #
      # @return [Ast::Merge::Comment::Attachment]
      def comment_attachment
        @comment_attachment ||= if @comment_tracker
          @comment_tracker.comment_attachment_for(
            self,
            line_num: @start_line,
            leading_comments: @leading_comments,
            inline_comment: @inline_comment,
            key: @key,
          )
        else
          Ast::Merge::Comment::Attachment.new(
            owner: self,
            leading_region: build_comment_region(:leading, @leading_comments),
            inline_region: build_comment_region(:inline, [@inline_comment].compact),
            metadata: {key: @key},
          )
        end
      end

      # @return [Ast::Merge::Comment::Region, nil]
      def leading_comment_region
        comment_attachment.leading_region
      end

      # @return [Ast::Merge::Comment::Region, nil]
      def inline_comment_region
        comment_attachment.inline_region
      end

      # String representation of the node value.
      # For scalars, returns the value.
      # For other nodes, returns inspect.
      # @return [String]
      def to_s
        value || inspect
      end

      # String representation for debugging
      # @return [String]
      def inspect
        node_type = @node.class.name.split("::").last
        "#<#{self.class.name} type=#{node_type} lines=#{@start_line}..#{@end_line} key=#{@key.inspect}>"
      end

      private

      def compute_signature(node)
        case node
        when ::Psych::Nodes::Mapping
          # Signature based on anchor and keys
          keys = extract_mapping_keys(node)
          [:mapping, node.anchor, keys.sort]
        when ::Psych::Nodes::Sequence
          # Signature based on anchor and first few items for stability
          [:sequence, node.anchor, node.children&.length || 0]
        when ::Psych::Nodes::Scalar
          # Signature based on value and anchor
          [:scalar, node.anchor, node.value]
        when ::Psych::Nodes::Alias
          # Signature based on the anchor it references
          [:alias, node.anchor]
        when ::Psych::Nodes::Document
          # Documents are matched by their root content type
          root = node.children&.first
          root_type = root&.class&.name&.split("::")&.last
          [:document, root_type]
        when ::Psych::Nodes::Stream
          [:stream]
        end
      end

      def extract_mapping_keys(mapping_node)
        return [] unless mapping_node.children

        keys = []
        i = 0
        while i < mapping_node.children.length
          key_node = mapping_node.children[i]
          if key_node.is_a?(::Psych::Nodes::Scalar)
            keys << key_node.value
          end
          i += 2
        end
        keys
      end

      def extract_key_name(key_node)
        return unless key_node.is_a?(::Psych::Nodes::Scalar)

        key_node.value
      end

      def wrap_children(child_nodes, comment_tracker)
        child_nodes.map { |child| wrap_node(child, comment_tracker) }
      end

      def wrap_node(node, comment_tracker, key: nil)
        leading = []
        inline = nil

        if comment_tracker && node.respond_to?(:start_line) && node.start_line
          line_num = node.start_line + 1
          leading = comment_tracker.leading_comments_before(line_num)
          inline = comment_tracker.inline_comment_at(line_num)
        end

        NodeWrapper.new(
          node,
          lines: @lines,
          leading_comments: leading,
          inline_comment: inline,
          key: key,
          comment_tracker: comment_tracker,
        )
      end

      def build_comment_region(kind, comments)
        return if comments.empty?

        Ast::Merge::Comment::TrackedHashAdapter.region(
          kind: kind,
          comments: comments,
          metadata: {key: @key},
        )
      end
    end
  end
end

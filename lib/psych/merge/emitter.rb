# frozen_string_literal: true

module Psych
  module Merge
    # Custom YAML emitter that preserves comments and formatting.
    # This class provides utilities for emitting YAML while maintaining
    # the original structure, comments, and style choices.
    #
    # Inherits common emitter functionality from Ast::Merge::EmitterBase.
    #
    # @example Basic usage
    #   emitter = Emitter.new
    #   emitter.emit_mapping_entry(key, value, leading_comments: comments)
    class Emitter < Ast::Merge::EmitterBase
      # Initialize subclass-specific state
      def initialize_subclass_state(**options)
        # YAML doesn't need comma tracking like JSON
      end

      # Clear subclass-specific state
      def clear_subclass_state
        # Nothing to clear for YAML
      end

      # Emit a tracked comment from CommentTracker
      # @param comment [Hash] Comment with :text, :indent
      def emit_tracked_comment(comment)
        indent = " " * (comment[:indent] || 0)
        @lines << "#{indent}# #{comment[:text]}"
      end

      # Emit a shared Ast::Merge comment region.
      #
      # @param region [Ast::Merge::Comment::Region, nil] Comment region to emit
      # @param inline [Boolean, nil] Force inline emission mode
      # @param source_lines [Array<String>, nil] Source lines for preserving blank gaps
      def emit_comment_region(region, inline: nil, source_lines: nil)
        return unless region
        return unless region.respond_to?(:nodes)
        return if region.respond_to?(:empty?) && region.empty?

        inline = region.inline? if inline.nil? && region.respond_to?(:inline?)
        return emit_inline_comment_region(region) if inline

        previous_line = nil
        region.nodes.each do |node|
          current_line = comment_region_line_number(node)
          emit_region_gap_lines(previous_line, current_line, source_lines)
          emit_comment_node(node)
          previous_line = current_line
        end
      end

      # Emit selected regions from a shared comment attachment.
      #
      # @param attachment [Ast::Merge::Comment::Attachment, nil] Attachment to emit
      # @param leading [Boolean] Whether to emit the leading region
      # @param inline [Boolean] Whether to emit the inline region
      # @param source_lines [Array<String>, nil] Source lines for preserving blank gaps
      def emit_comment_attachment(attachment, leading: true, inline: false, source_lines: nil)
        return unless attachment
        return unless attachment.respond_to?(:leading_region) && attachment.respond_to?(:inline_region)

        emit_comment_region(attachment.leading_region, source_lines: source_lines) if leading && attachment.leading_region
        emit_comment_region(attachment.inline_region, inline: true, source_lines: source_lines) if inline && attachment.inline_region
      end

      # Emit a comment line
      #
      # @param text [String] Comment text (without #)
      # @param inline [Boolean] Whether this is an inline comment
      def emit_comment(text, inline: false)
        if inline
          # Inline comments are appended to the last line
          return if @lines.empty?

          @lines[-1] = "#{@lines[-1]} # #{text}"
        else
          @lines << "#{current_indent}# #{text}"
        end
      end

      # Emit a scalar value
      #
      # @param key [String] Key name
      # @param value [String] Value
      # @param style [Symbol] Style (:plain, :single_quoted, :double_quoted, :literal, :folded)
      # @param inline_comment [String, nil] Optional inline comment
      def emit_scalar_entry(key, value, style: :plain, inline_comment: nil)
        formatted_value = format_scalar(value, style)
        line = "#{current_indent}#{key}: #{formatted_value}"
        line += " # #{inline_comment}" if inline_comment
        @lines << line
      end

      # Emit a mapping start (for nested mappings)
      #
      # @param key [String] Key name
      # @param anchor [String, nil] Anchor name (without &)
      def emit_mapping_start(key, anchor: nil)
        anchor_str = anchor ? " &#{anchor}" : ""
        @lines << "#{current_indent}#{key}:#{anchor_str}"
        indent
      end

      # Emit a mapping end
      def emit_mapping_end
        dedent
      end

      # Emit a sequence start
      #
      # @param key [String, nil] Key name (nil for inline sequence)
      # @param anchor [String, nil] Anchor name
      def emit_sequence_start(key, anchor: nil)
        if key
          anchor_str = anchor ? " &#{anchor}" : ""
          @lines << "#{current_indent}#{key}:#{anchor_str}"
          indent
        end
      end

      # Emit a sequence item
      #
      # @param value [String] Item value
      # @param inline_comment [String, nil] Optional inline comment
      def emit_sequence_item(value, inline_comment: nil)
        line = "#{current_indent}- #{value}"
        line += " # #{inline_comment}" if inline_comment
        @lines << line
      end

      # Emit a sequence end
      def emit_sequence_end
        dedent
      end

      # Emit an alias reference
      #
      # @param key [String] Key name
      # @param anchor [String] Anchor name being referenced (without *)
      def emit_alias(key, anchor)
        @lines << "#{current_indent}#{key}: *#{anchor}"
      end

      # Emit a merge key with alias
      #
      # @param anchor [String] Anchor name to merge (without *)
      def emit_merge_key(anchor)
        @lines << "#{current_indent}<<: *#{anchor}"
      end

      # Get the output as a YAML string
      #
      # @return [String]
      def to_yaml
        to_s
      end

      private

      def emit_inline_comment_region(region)
        text = region.nodes.filter_map do |node|
          if node.respond_to?(:normalized_content)
            node.normalized_content
          else
            node.to_s
          end
        end.join(" ").strip

        return if text.empty? || @lines.empty?

        tracked_hash = region.respond_to?(:metadata) ? Array(region.metadata[:tracked_hashes]).first : nil
        indent = tracked_hash && (tracked_hash[:indent] || tracked_hash["indent"])

        unless indent
          emit_comment(text, inline: true)
          return
        end

        base = @lines[-1].to_s.rstrip
        target_column = [indent.to_i, base.length + 1].max
        comment_suffix = text.empty? ? "#" : "# #{text}"
        @lines[-1] = base.ljust(target_column) + comment_suffix
      end

      def emit_comment_node(node)
        if node.respond_to?(:slice)
          @lines << node.slice.to_s.chomp
        elsif node.respond_to?(:text)
          @lines << node.text.to_s.chomp
        else
          emit_comment(node.respond_to?(:normalized_content) ? node.normalized_content : node.to_s)
        end
      end

      def emit_region_gap_lines(previous_line, current_line, source_lines)
        return unless previous_line && current_line && current_line > previous_line + 1

        if source_lines
          gap_lines = source_lines[previous_line, current_line - previous_line - 1] || []
          blank_lines = gap_lines.select { |line| line.to_s.strip.empty? }
          emit_raw_lines(blank_lines) if blank_lines.any?
        else
          (current_line - previous_line - 1).times { emit_blank_line }
        end
      end

      def comment_region_line_number(node)
        return node.line_number if node.respond_to?(:line_number)
        return node.location.start_line if node.respond_to?(:location) && node.location

        nil
      end

      def format_scalar(value, style)
        case style
        when :single_quoted
          "'#{escape_single_quotes(value)}'"
        when :double_quoted
          "\"#{escape_double_quotes(value)}\""
        when :literal
          # Literal scalars need special handling
          "|\n#{indent_multiline(value)}"
        when :folded
          # Folded scalars need special handling
          ">\n#{indent_multiline(value)}"
        else
          # Plain style - check if quoting is needed
          needs_quoting?(value) ? "\"#{escape_double_quotes(value)}\"" : value.to_s
        end
      end

      def escape_single_quotes(value)
        value.to_s.gsub("'", "''")
      end

      def escape_double_quotes(value)
        value.to_s
          .gsub("\\", "\\\\")
          .gsub("\"", "\\\"")
          .gsub("\n", "\\n")
          .gsub("\t", "\\t")
      end

      def indent_multiline(value)
        value.to_s.lines.map { |line| "#{current_indent}  #{line.chomp}" }.join("\n")
      end

      def needs_quoting?(value)
        str = value.to_s

        # Empty string needs quotes
        return true if str.empty?

        # Check for special characters that need quoting
        return true if /^[&*!|>'"%@`]/.match?(str)
        return true if /[:#\[\]{}?,]/.match?(str)
        return true if /^\s|\s$/.match?(str)
        return true if /\n/.match?(str)

        # Check for boolean/null-like values
        return true if %w[true false yes no on off null ~].include?(str.downcase)

        # Check for numeric values that should stay as strings
        return true if str =~ /^\d+$/ && str.start_with?("0") && str.length > 1

        false
      end
    end
  end
end

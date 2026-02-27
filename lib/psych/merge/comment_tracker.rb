# frozen_string_literal: true

module Psych
  module Merge
    # Extracts and tracks comments with their line numbers from YAML source.
    # YAML comments use the same # syntax as Ruby, making freeze block detection
    # straightforward.
    #
    # @example Basic usage
    #   tracker = CommentTracker.new(yaml_source)
    #   tracker.comments # => [{line: 1, indent: 0, text: "This is a comment"}]
    #   tracker.comment_at(1) # => {line: 1, indent: 0, text: "This is a comment"}
    #
    # @example Comment types
    #   # Full-line comment
    #   key: value # Inline comment
    class CommentTracker
      # Regex to match full-line comments (line is only whitespace + comment)
      FULL_LINE_COMMENT_REGEX = /\A(\s*)#\s?(.*)\z/

      # Regex to match inline comments (comment after YAML content)
      INLINE_COMMENT_REGEX = /\s+#\s?(.*)$/

      # @return [Array<Hash>] All extracted comments with metadata
      attr_reader :comments

      # @return [Array<String>] Source lines
      attr_reader :lines

      # Initialize comment tracker by scanning the source
      #
      # @param source [String] YAML source code
      def initialize(source)
        @source = source
        @lines = source.lines.map(&:chomp)
        @comments = extract_comments
        @comments_by_line = @comments.group_by { |c| c[:line] }
      end

      # Get comment at a specific line
      #
      # @param line_num [Integer] 1-based line number
      # @return [Hash, nil] Comment info or nil
      def comment_at(line_num)
        @comments_by_line[line_num]&.first
      end

      # Get all comments in a line range
      #
      # @param range [Range] Range of 1-based line numbers
      # @return [Array<Hash>] Comments in the range
      def comments_in_range(range)
        @comments.select { |c| range.cover?(c[:line]) }
      end

      # Get leading comments before a line (comment lines above, skipping blank lines)
      #
      # @param line_num [Integer] 1-based line number
      # @return [Array<Hash>] Leading comments
      def leading_comments_before(line_num)
        leading = []
        current = line_num - 1

        # Skip blank lines between the node and its leading comments
        current -= 1 while current >= 1 && blank_line?(current)

        while current >= 1
          comment = comment_at(current)
          break unless comment && comment[:full_line]

          leading.unshift(comment)
          current -= 1

          # Skip blank lines between consecutive comments
          current -= 1 while current >= 1 && blank_line?(current)
        end

        leading
      end

      # Get trailing comment on the same line (inline comment)
      #
      # @param line_num [Integer] 1-based line number
      # @return [Hash, nil] Inline comment or nil
      def inline_comment_at(line_num)
        comment = comment_at(line_num)
        comment if comment && !comment[:full_line]
      end

      # Check if a line is a full-line comment
      #
      # @param line_num [Integer] 1-based line number
      # @return [Boolean]
      def full_line_comment?(line_num)
        comment = comment_at(line_num)
        comment&.dig(:full_line) || false
      end

      # Check if a line is blank
      #
      # @param line_num [Integer] 1-based line number
      # @return [Boolean]
      def blank_line?(line_num)
        return false if line_num < 1 || line_num > @lines.length

        @lines[line_num - 1].strip.empty?
      end

      # Get raw line content
      #
      # @param line_num [Integer] 1-based line number
      # @return [String, nil]
      def line_at(line_num)
        return if line_num < 1 || line_num > @lines.length

        @lines[line_num - 1]
      end

      private

      def extract_comments
        comments = []

        @lines.each_with_index do |line, idx|
          line_num = idx + 1

          # Check for full-line comment first
          if line =~ FULL_LINE_COMMENT_REGEX
            comments << {
              line: line_num,
              indent: ::Regexp.last_match(1).length,
              text: ::Regexp.last_match(2).rstrip,
              full_line: true,
              raw: line,
            }
          # Check for inline comment (after YAML content)
          elsif line =~ INLINE_COMMENT_REGEX
            # Make sure it's not inside a quoted string
            # Simple heuristic: count quotes before the #
            before_hash = line.split("#").first
            single_quotes = before_hash.count("'")
            double_quotes = before_hash.count('"')

            # If quotes are balanced, it's likely a real comment
            if single_quotes.even? && double_quotes.even?
              comments << {
                line: line_num,
                indent: line.index("#"),
                text: ::Regexp.last_match(1).rstrip,
                full_line: false,
                raw: line,
              }
            end
          end
        end

        comments
      end
    end
  end
end

# frozen_string_literal: true

module Psych
  module Merge
    # Extracts and tracks comments with their line numbers from YAML source.
    # YAML comments use the same # syntax as Ruby, making freeze block detection
    # straightforward.
    #
    # Inherits shared lookup, query, region-building, and attachment API from
    # +Ast::Merge::Comment::HashTrackerBase+. Only format-specific comment
    # extraction and owner resolution are overridden here.
    #
    # @example Basic usage
    #   tracker = CommentTracker.new(yaml_source)
    #   tracker.comments # => [{line: 1, indent: 0, text: "This is a comment"}]
    #   tracker.comment_at(1) # => {line: 1, indent: 0, text: "This is a comment"}
    #
    # @example Comment types
    #   # Full-line comment
    #   key: value # Inline comment
    class CommentTracker < Ast::Merge::Comment::HashTrackerBase
      # Regex to match inline comments (comment after YAML content)
      INLINE_COMMENT_REGEX = /\s+#\s?(.*)$/

      # Initialize comment tracker by scanning the source
      #
      # @param source [String] YAML source code
      def initialize(source)
        @source = source
        super(source.lines.map(&:chomp))
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

      def owner_line_num(owner)
        return owner.start_line if owner.respond_to?(:start_line) && owner.start_line
        return owner.key.start_line if owner.respond_to?(:key) && owner.key&.respond_to?(:start_line) && owner.key.start_line

        nil
      end
    end
  end
end

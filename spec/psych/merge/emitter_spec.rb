# frozen_string_literal: true

RSpec.describe Psych::Merge::Emitter do
  describe "#initialize" do
    it "starts with empty lines" do
      emitter = described_class.new
      expect(emitter.lines).to be_empty
    end

    it "accepts custom indent size" do
      emitter = described_class.new(indent_size: 4)
      expect(emitter.indent_size).to eq(4)
    end
  end

  describe "#emit_comment" do
    it "emits full-line comment" do
      emitter = described_class.new
      emitter.emit_comment("This is a comment")

      expect(emitter.lines.first).to eq("# This is a comment")
    end

    it "emits inline comment" do
      emitter = described_class.new
      emitter.emit_raw_lines(["key: value"])
      emitter.emit_comment("inline", inline: true)

      expect(emitter.lines.first).to eq("key: value # inline")
    end

    it "does nothing for inline comment when lines are empty" do
      emitter = described_class.new
      emitter.emit_comment("inline", inline: true)

      expect(emitter.lines).to be_empty
    end
  end

  describe "#emit_leading_comments" do
    it "emits multiple comments with proper indentation" do
      emitter = described_class.new
      comments = [
        {indent: 0, text: "First comment"},
        {indent: 2, text: "Indented comment"},
      ]
      emitter.emit_leading_comments(comments)

      expect(emitter.lines[0]).to eq("# First comment")
      expect(emitter.lines[1]).to eq("  # Indented comment")
    end
  end

  describe "#emit_comment_region" do
    it "emits shared leading regions and preserves blank gaps between comment lines" do
      emitter = described_class.new
      region = Ast::Merge::Comment::TrackedHashAdapter.region(
        kind: :leading,
        comments: [
          {line: 1, indent: 0, text: "First", full_line: true, raw: "# First"},
          {line: 3, indent: 0, text: "Second", full_line: true, raw: "# Second"},
        ],
      )

      emitter.emit_comment_region(region, source_lines: ["# First", "", "# Second"])

      expect(emitter.lines).to eq(["# First", "", "# Second"])
    end

    it "appends shared inline regions to the current line" do
      emitter = described_class.new
      region = Ast::Merge::Comment::TrackedHashAdapter.region(
        kind: :inline,
        comments: [
          {line: 1, indent: 11, text: "inline note", full_line: false, raw: "key: value # inline note"},
        ],
      )

      emitter.emit_raw_lines(["key: value"])
      emitter.emit_comment_region(region, inline: true)

      expect(emitter.lines).to eq(["key: value # inline note"])
    end

    it "deduplicates repeated shared region segments before emitting" do
      emitter = described_class.new
      region = Ast::Merge::Comment::TrackedHashAdapter.region(
        kind: :leading,
        comments: [
          {line: 1, indent: 0, text: "Header", full_line: true, raw: "# Header"},
          {line: 2, indent: 0, text: "Details", full_line: true, raw: "# Details"},
          {line: 1, indent: 0, text: "Header", full_line: true, raw: "# Header"},
          {line: 2, indent: 0, text: "Details", full_line: true, raw: "# Details"},
        ],
      )

      emitter.emit_comment_region(region)

      expect(emitter.lines).to eq(["# Header", "# Details"])
    end

    it "aligns inline comments to the tracked source column when metadata is available" do
      emitter = described_class.new
      region = Ast::Merge::Comment::TrackedHashAdapter.region(
        kind: :inline,
        comments: [
          {line: 1, indent: 18, text: "inline note", full_line: false, raw: "key: value      # inline note"},
        ],
      )

      emitter.emit_raw_lines(["key: value"])
      emitter.emit_comment_region(region, inline: true)

      expect(emitter.lines).to eq(["key: value        # inline note"])
    end
  end

  describe "#emit_comment_attachment" do
    it "emits selected regions from a shared attachment" do
      emitter = described_class.new
      leading_region = Ast::Merge::Comment::TrackedHashAdapter.region(
        kind: :leading,
        comments: [{line: 1, indent: 0, text: "Header", full_line: true, raw: "# Header"}],
      )
      inline_region = Ast::Merge::Comment::TrackedHashAdapter.region(
        kind: :inline,
        comments: [{line: 2, indent: 11, text: "inline", full_line: false, raw: "key: value # inline"}],
      )
      attachment = Ast::Merge::Comment::Attachment.new(
        leading_region: leading_region,
        inline_region: inline_region,
      )

      emitter.emit_comment_attachment(attachment, leading: true, source_lines: ["# Header"])
      emitter.emit_raw_lines(["key: value"])
      emitter.emit_comment_attachment(attachment, leading: false, inline: true)

      expect(emitter.lines).to eq(["# Header", "key: value # inline"])
    end
  end

  describe "#emit_blank_line" do
    it "adds an empty line" do
      emitter = described_class.new
      emitter.emit_blank_line

      expect(emitter.lines.first).to eq("")
    end
  end

  describe "#emit_scalar_entry" do
    it "emits key-value pair" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "value")

      expect(emitter.lines.first).to eq("key: value")
    end

    it "emits with single quotes" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "value", style: :single_quoted)

      expect(emitter.lines.first).to eq("key: 'value'")
    end

    it "emits with double quotes" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "value", style: :double_quoted)

      expect(emitter.lines.first).to eq('key: "value"')
    end

    it "emits with inline comment" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "value", inline_comment: "important")

      expect(emitter.lines.first).to eq("key: value # important")
    end

    it "quotes values that need it" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "true")

      expect(emitter.lines.first).to include('"true"')
    end
  end

  describe "#emit_mapping_start and #emit_mapping_end" do
    it "handles nested mappings" do
      emitter = described_class.new
      emitter.emit_mapping_start("parent")
      emitter.emit_scalar_entry("child", "value")
      emitter.emit_mapping_end

      expect(emitter.lines[0]).to eq("parent:")
      expect(emitter.lines[1]).to eq("  child: value")
    end

    it "supports anchors" do
      emitter = described_class.new
      emitter.emit_mapping_start("defaults", anchor: "defaults")

      expect(emitter.lines.first).to eq("defaults: &defaults")
    end

    it "emit_mapping_end does not go below zero indent" do
      emitter = described_class.new
      # indent_level starts at 0
      emitter.emit_mapping_end

      expect(emitter.indent_level).to eq(0)
    end
  end

  describe "#emit_sequence_item" do
    it "emits sequence item" do
      emitter = described_class.new
      emitter.emit_sequence_item("item")

      expect(emitter.lines.first).to eq("- item")
    end

    it "emits with inline comment" do
      emitter = described_class.new
      emitter.emit_sequence_item("item", inline_comment: "note")

      expect(emitter.lines.first).to eq("- item # note")
    end
  end

  describe "#emit_alias" do
    it "emits alias reference" do
      emitter = described_class.new
      emitter.emit_alias("production", "defaults")

      expect(emitter.lines.first).to eq("production: *defaults")
    end
  end

  describe "#emit_merge_key" do
    it "emits merge key" do
      emitter = described_class.new
      emitter.emit_merge_key("defaults")

      expect(emitter.lines.first).to eq("<<: *defaults")
    end
  end

  describe "#emit_raw_lines" do
    it "emits lines as-is" do
      emitter = described_class.new
      emitter.emit_raw_lines(["line1", "line2\n"])

      expect(emitter.lines).to eq(["line1", "line2"])
    end
  end

  describe "#to_yaml" do
    it "joins lines with newlines" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key1", "value1")
      emitter.emit_scalar_entry("key2", "value2")

      yaml = emitter.to_yaml
      expect(yaml).to eq("key1: value1\nkey2: value2\n")
    end

    it "adds trailing newline" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "value")

      expect(emitter.to_yaml).to end_with("\n")
    end

    it "returns empty string for empty emitter" do
      emitter = described_class.new
      expect(emitter.to_yaml).to eq("")
    end
  end

  describe "#clear" do
    it "resets the emitter" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "value")
      emitter.clear

      expect(emitter.lines).to be_empty
      expect(emitter.indent_level).to eq(0)
    end
  end

  describe "literal and folded scalar styles" do
    it "emits literal scalar style" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "line1\nline2", style: :literal)

      output = emitter.lines.join("\n")
      expect(output).to include("|")
    end

    it "emits folded scalar style" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "long text that should fold", style: :folded)

      output = emitter.lines.join("\n")
      expect(output).to include(">")
    end
  end

  describe "#emit_sequence_start and #emit_sequence_end" do
    it "handles sequence with key" do
      emitter = described_class.new
      emitter.emit_sequence_start("items")
      emitter.emit_sequence_item("item1")
      emitter.emit_sequence_item("item2")
      emitter.emit_sequence_end

      expect(emitter.lines[0]).to eq("items:")
      expect(emitter.lines[1]).to eq("  - item1")
      expect(emitter.indent_level).to eq(0)
    end

    it "handles sequence with anchor" do
      emitter = described_class.new
      emitter.emit_sequence_start("items", anchor: "my_items")

      expect(emitter.lines[0]).to eq("items: &my_items")
    end

    it "handles inline sequence (no key)" do
      emitter = described_class.new
      emitter.emit_sequence_start(nil)
      emitter.emit_sequence_item("item1")

      expect(emitter.lines[0]).to eq("- item1")
    end

    it "emit_sequence_end does not go below zero indent" do
      emitter = described_class.new
      # indent_level starts at 0
      emitter.emit_sequence_end

      expect(emitter.indent_level).to eq(0)
    end
  end

  describe "quoting edge cases" do
    it "quotes empty strings" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "")

      expect(emitter.lines.first).to include('""')
    end

    it "quotes strings starting with special characters" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key1", "&reference")
      emitter.emit_scalar_entry("key2", "*pointer")
      emitter.emit_scalar_entry("key3", "!tag")

      output = emitter.to_yaml
      expect(output).to include('"&reference"')
      expect(output).to include('"*pointer"')
      expect(output).to include('"!tag"')
    end

    it "quotes strings with colons" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "value:with:colons")

      expect(emitter.lines.first).to include('"value:with:colons"')
    end

    it "quotes strings with brackets and braces" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key1", "[array]")
      emitter.emit_scalar_entry("key2", "{hash}")

      output = emitter.to_yaml
      expect(output).to include('"[array]"')
      expect(output).to include('"{hash}"')
    end

    it "quotes leading zeros in numbers" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "007")

      expect(emitter.lines.first).to include('"007"')
    end

    it "quotes null-like values" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "null")

      expect(emitter.lines.first).to include('"null"')
    end

    it "quotes yes/no/on/off values" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key1", "yes")
      emitter.emit_scalar_entry("key2", "no")
      emitter.emit_scalar_entry("key3", "on")
      emitter.emit_scalar_entry("key4", "off")

      output = emitter.to_yaml
      expect(output).to include('"yes"')
      expect(output).to include('"no"')
      expect(output).to include('"on"')
      expect(output).to include('"off"')
    end

    it "quotes strings with leading/trailing whitespace" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", " spaced ")

      expect(emitter.lines.first).to include('" spaced "')
    end

    it "quotes strings with newlines" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "line1\nline2")

      # Default plain style should quote strings with newlines
      expect(emitter.lines.first).to include('"')
    end
  end

  describe "escaping in double quotes" do
    it "escapes backslashes" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "path\\to\\file", style: :double_quoted)

      # The emitter escapes backslashes, so \\ becomes \\\\
      # In the output string, we see "path\\to\\file"
      expect(emitter.lines.first).to include("path\\to\\file")
    end

    it "escapes tabs" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "with\ttab", style: :double_quoted)

      expect(emitter.lines.first).to include("\\t")
    end
  end

  describe "escaping in single quotes" do
    it "escapes single quotes" do
      emitter = described_class.new
      emitter.emit_scalar_entry("key", "it's a test", style: :single_quoted)

      expect(emitter.lines.first).to include("it''s a test")
    end
  end
end

# frozen_string_literal: true

RSpec.describe Psych::Merge::CommentTracker do
  describe "#initialize" do
    it "extracts full-line comments" do
      source = <<~YAML
        # This is a comment
        key: value
      YAML

      tracker = described_class.new(source)
      expect(tracker.comments.length).to eq(1)
      expect(tracker.comments.first[:text]).to eq("This is a comment")
      expect(tracker.comments.first[:full_line]).to be(true)
    end

    it "extracts inline comments" do
      source = <<~YAML
        key: value # inline comment
      YAML

      tracker = described_class.new(source)
      expect(tracker.comments.length).to eq(1)
      expect(tracker.comments.first[:text]).to eq("inline comment")
      expect(tracker.comments.first[:full_line]).to be(false)
    end

    it "handles multiple comments" do
      source = <<~YAML
        # First comment
        # Second comment
        key: value # inline
        other: value
      YAML

      tracker = described_class.new(source)
      expect(tracker.comments.length).to eq(3)
    end

    it "preserves comment indentation" do
      source = <<~YAML
        key:
          # Indented comment
          nested: value
      YAML

      tracker = described_class.new(source)
      comment = tracker.comments.first
      expect(comment[:indent]).to eq(2)
    end
  end

  describe "#comment_at" do
    it "returns comment at specific line" do
      source = <<~YAML
        # Line 1 comment
        key: value
        # Line 3 comment
      YAML

      tracker = described_class.new(source)
      expect(tracker.comment_at(1)[:text]).to eq("Line 1 comment")
      expect(tracker.comment_at(2)).to be_nil
      expect(tracker.comment_at(3)[:text]).to eq("Line 3 comment")
    end
  end

  describe "#comments_in_range" do
    it "returns all comments in range" do
      source = <<~YAML
        # Comment 1
        key: value
        # Comment 3
        # Comment 4
        other: value
      YAML

      tracker = described_class.new(source)
      comments = tracker.comments_in_range(1..4)
      expect(comments.length).to eq(3)
    end
  end

  describe "#leading_comments_before" do
    it "returns consecutive comment lines before a line" do
      source = <<~YAML
        # Comment 1
        # Comment 2
        key: value
      YAML

      tracker = described_class.new(source)
      leading = tracker.leading_comments_before(3)
      expect(leading.length).to eq(2)
      expect(leading.first[:text]).to eq("Comment 1")
      expect(leading.last[:text]).to eq("Comment 2")
    end

    it "stops at non-comment lines" do
      source = <<~YAML
        # Comment 1
        key: value
        # Comment 3
        other: value
      YAML

      tracker = described_class.new(source)
      leading = tracker.leading_comments_before(4)
      expect(leading.length).to eq(1)
      expect(leading.first[:text]).to eq("Comment 3")
    end
  end

  describe "#blank_line?" do
    it "detects blank lines" do
      source = "key: value\n\nother: value\n"
      tracker = described_class.new(source)

      expect(tracker.blank_line?(1)).to be(false)
      expect(tracker.blank_line?(2)).to be(true)
      expect(tracker.blank_line?(3)).to be(false)
    end

    it "returns false for out of range line numbers" do
      source = "key: value"
      tracker = described_class.new(source)

      expect(tracker.blank_line?(0)).to be(false)
      expect(tracker.blank_line?(100)).to be(false)
    end
  end

  describe "#line_at" do
    it "returns line content" do
      source = <<~YAML
        key: value
        other: stuff
      YAML

      tracker = described_class.new(source)
      expect(tracker.line_at(1)).to eq("key: value")
      expect(tracker.line_at(2)).to eq("other: stuff")
    end

    it "returns nil for out of range" do
      tracker = described_class.new("key: value")
      expect(tracker.line_at(0)).to be_nil
      expect(tracker.line_at(100)).to be_nil
    end
  end

  describe "#full_line_comment?" do
    it "returns true for full-line comments" do
      source = <<~YAML
        # This is a comment
        key: value
      YAML

      tracker = described_class.new(source)
      expect(tracker.full_line_comment?(1)).to be(true)
    end

    it "returns false for non-comment lines" do
      source = <<~YAML
        key: value
        other: stuff
      YAML

      tracker = described_class.new(source)
      expect(tracker.full_line_comment?(1)).to be(false)
    end

    it "returns false for inline comments" do
      source = <<~YAML
        key: value # inline comment
      YAML

      tracker = described_class.new(source)
      expect(tracker.full_line_comment?(1)).to be(false)
    end
  end

  describe "#inline_comment_at" do
    it "returns inline comment on line" do
      source = <<~YAML
        key: value # inline comment
      YAML

      tracker = described_class.new(source)
      comment = tracker.inline_comment_at(1)

      expect(comment).not_to be_nil
      expect(comment[:text]).to eq("inline comment")
      expect(comment[:full_line]).to be(false)
    end

    it "returns nil for full-line comments" do
      source = <<~YAML
        # full line comment
        key: value
      YAML

      tracker = described_class.new(source)
      expect(tracker.inline_comment_at(1)).to be_nil
    end

    it "returns nil for lines without comments" do
      source = <<~YAML
        key: value
      YAML

      tracker = described_class.new(source)
      expect(tracker.inline_comment_at(1)).to be_nil
    end
  end

  describe "handling quoted strings with hash" do
    it "does not treat hash inside double quotes as comment" do
      source = <<~YAML
        key: "value with # in it"
      YAML

      tracker = described_class.new(source)
      expect(tracker.comments).to be_empty
    end

    it "does not treat hash inside single quotes as comment" do
      source = <<~YAML
        key: 'value with # in it'
      YAML

      tracker = described_class.new(source)
      expect(tracker.comments).to be_empty
    end
  end

  describe "#leading_comments_before" do
    it "finds a comment immediately above the node" do
      source = <<~YAML
        # header comment
        key: value
      YAML

      tracker = described_class.new(source)
      leading = tracker.leading_comments_before(2)
      expect(leading.size).to eq(1)
      expect(leading.first[:text]).to eq("header comment")
    end

    it "finds a comment separated from the node by a blank line" do
      source = <<~YAML
        # These are supported funding model platforms

        buy_me_a_coffee: pboling
      YAML

      tracker = described_class.new(source)
      leading = tracker.leading_comments_before(3)
      expect(leading.size).to eq(1)
      expect(leading.first[:text]).to eq("These are supported funding model platforms")
    end

    it "finds multiple comments separated by blank lines" do
      source = <<~YAML
        # First comment

        # Second comment

        key: value
      YAML

      tracker = described_class.new(source)
      leading = tracker.leading_comments_before(5)
      expect(leading.size).to eq(2)
      expect(leading.first[:text]).to eq("First comment")
      expect(leading.last[:text]).to eq("Second comment")
    end

    it "does not cross a non-comment non-blank line" do
      source = <<~YAML
        # Orphan comment
        other_key: something

        # Relevant comment
        key: value
      YAML

      tracker = described_class.new(source)
      leading = tracker.leading_comments_before(5)
      expect(leading.size).to eq(1)
      expect(leading.first[:text]).to eq("Relevant comment")
    end
  end
end

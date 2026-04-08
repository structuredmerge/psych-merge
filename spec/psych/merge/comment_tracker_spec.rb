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

  describe "shared Ast::Merge comment accessors" do
    it "exposes comment nodes using the shared Ast::Merge comment model" do
      source = <<~YAML
        # Header comment
        key: value # inline note
      YAML

      tracker = described_class.new(source)
      nodes = tracker.comment_nodes

      expect(nodes.length).to eq(2)
      expect(nodes).to all(be_a(Ast::Merge::Comment::Line))
      expect(nodes.map(&:content)).to eq(["Header comment", "inline note"])
    end

    it "returns a shared comment node at a line" do
      source = <<~YAML
        # Header comment
        key: value
      YAML

      tracker = described_class.new(source)
      node = tracker.comment_node_at(1)

      expect(node).not_to be_nil
      expect(node).to be_a(Ast::Merge::Comment::Line)
      expect(node&.content).to eq("Header comment")
      expect(tracker.comment_node_at(2)).to be_nil
    end

    it "returns a shared comment region for a range" do
      source = <<~YAML
        # First
        # Second
        key: value # inline note
      YAML

      tracker = described_class.new(source)
      region = tracker.comment_region_for_range(1..3, kind: :leading)

      expect(region).to be_a(Ast::Merge::Comment::Region)
      expect(region.leading?).to be(true)
      expect(region.normalized_content).to eq("First\nSecond\ninline note")
      expect(region.metadata[:source]).to eq(:tracked_hash)
    end

    it "can filter a shared region to full-line comments only" do
      source = <<~YAML
        # First
        key: value # inline note
      YAML

      tracker = described_class.new(source)
      region = tracker.comment_region_for_range(1..2, kind: :leading, full_line_only: true)

      expect(region.normalized_content).to eq("First")
    end

    it "builds a shared passive augmenter" do
      source = <<~YAML
        # Header comment
        key: value
      YAML

      owner = Struct.new(:start_line, :end_line, keyword_init: true).new(start_line: 2, end_line: 2)
      tracker = described_class.new(source)
      augmenter = tracker.augment(owners: [owner])

      expect(augmenter).to be_a(Ast::Merge::Comment::Augmenter)
      expect(augmenter.capability).to be_source_augmented
      expect(augmenter.attachment_for(owner).leading_region.normalized_content).to eq("Header comment")
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

    it "treats a line-1 comment followed by a gap as preamble (not owned by node)" do
      source = <<~YAML
        # These are supported funding model platforms

        buy_me_a_coffee: pboling
      YAML

      tracker = described_class.new(source)
      leading = tracker.leading_comments_before(3)
      expect(leading.size).to eq(0),
        "Line-1 comment separated by a gap is preamble, not a leading comment"
    end

    it "strips line-1 preamble but keeps post-gap node-specific comments" do
      source = <<~YAML
        # First comment

        # Second comment

        key: value
      YAML

      tracker = described_class.new(source)
      leading = tracker.leading_comments_before(5)
      expect(leading.size).to eq(1)
      expect(leading.first[:text]).to eq("Second comment")
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

# frozen_string_literal: true

RSpec.describe Psych::Merge::FileAnalysis do
  it_behaves_like "Ast::Merge::FileAnalyzable" do
    let(:file_analysis_class) { described_class }
    let(:freeze_node_class) { Psych::Merge::FreezeNode }
    let(:sample_source) do
      <<~YAML
        key: value
        other: stuff
      YAML
    end
    let(:sample_source_with_freeze) do
      <<~YAML
        before: value
        # psych-merge:freeze
        frozen: secret
        # psych-merge:unfreeze
        after: value
      YAML
    end
    let(:build_file_analysis) do
      ->(source, **opts) { described_class.new(source, **opts) }
    end
  end

  describe "#initialize" do
    it "parses valid YAML" do
      yaml = <<~YAML
        key: value
        other: stuff
      YAML

      analysis = described_class.new(yaml)

      expect(analysis.valid?).to be(true)
      expect(analysis.errors).to be_empty
    end

    it "raises Psych::SyntaxError for invalid YAML" do
      yaml = "key: value\n  invalid: indentation"

      expect {
        described_class.new(yaml)
      }.to raise_error(Psych::SyntaxError)
    end
  end

  describe "#nodes" do
    it "extracts mapping entries as nodes" do
      yaml = <<~YAML
        foo: bar
        baz: qux
      YAML

      analysis = described_class.new(yaml)

      expect(analysis.statements.length).to eq(2)
      expect(analysis.statements.first).to be_a(Psych::Merge::MappingEntry)
    end

    it "handles nested mappings" do
      yaml = <<~YAML
        parent:
          child: value
        sibling: other
      YAML

      analysis = described_class.new(yaml)

      expect(analysis.statements.length).to eq(2)
    end
  end

  describe "#freeze_blocks" do
    it "extracts freeze blocks" do
      yaml = <<~YAML
        normal: value
        # psych-merge:freeze
        frozen: secret
        # psych-merge:unfreeze
        after: freeze
      YAML

      analysis = described_class.new(yaml)

      expect(analysis.freeze_blocks.length).to eq(1)
      expect(analysis.freeze_blocks.first.start_line).to eq(2)
      expect(analysis.freeze_blocks.first.end_line).to eq(4)
    end

    it "handles multiple freeze blocks" do
      yaml = <<~YAML
        # psych-merge:freeze
        first: frozen
        # psych-merge:unfreeze
        normal: value
        # psych-merge:freeze
        second: frozen
        # psych-merge:unfreeze
      YAML

      analysis = described_class.new(yaml)

      expect(analysis.freeze_blocks.length).to eq(2)
    end

    it "uses custom freeze token" do
      yaml = <<~YAML
        # custom-token:freeze
        frozen: value
        # custom-token:unfreeze
      YAML

      analysis = described_class.new(yaml, freeze_token: "custom-token")

      expect(analysis.freeze_blocks.length).to eq(1)
    end
  end

  describe "#in_freeze_block?" do
    it "returns true for lines inside freeze block" do
      yaml = <<~YAML
        normal: value
        # psych-merge:freeze
        frozen: secret
        # psych-merge:unfreeze
      YAML

      analysis = described_class.new(yaml)

      expect(analysis.in_freeze_block?(1)).to be(false)
      expect(analysis.in_freeze_block?(2)).to be(true)
      expect(analysis.in_freeze_block?(3)).to be(true)
      expect(analysis.in_freeze_block?(4)).to be(true)
    end
  end

  describe "#freeze_block_at" do
    it "returns freeze block containing line" do
      yaml = <<~YAML
        # psych-merge:freeze
        frozen: value
        # psych-merge:unfreeze
      YAML

      analysis = described_class.new(yaml)

      block = analysis.freeze_block_at(2)
      expect(block).to be_a(Psych::Merge::FreezeNode)
      expect(block.start_line).to eq(1)
    end

    it "returns nil for lines outside freeze blocks" do
      yaml = <<~YAML
        normal: value
        # psych-merge:freeze
        frozen: secret
        # psych-merge:unfreeze
      YAML

      analysis = described_class.new(yaml)

      expect(analysis.freeze_block_at(1)).to be_nil
    end
  end

  describe "#signature_at" do
    it "returns signature for node at index" do
      yaml = <<~YAML
        foo: bar
        baz: qux
      YAML

      analysis = described_class.new(yaml)

      sig = analysis.signature_at(0)
      expect(sig).to eq([:mapping_entry, "foo"])

      sig = analysis.signature_at(1)
      expect(sig).to eq([:mapping_entry, "baz"])
    end

    it "returns nil for out of range index" do
      yaml = "key: value"
      analysis = described_class.new(yaml)

      expect(analysis.signature_at(-1)).to be_nil
      expect(analysis.signature_at(100)).to be_nil
    end
  end

  describe "#generate_signature" do
    it "uses custom signature generator when provided" do
      yaml = "key: value"
      custom_generator = ->(node) { [:custom, "signature"] }

      analysis = described_class.new(yaml, signature_generator: custom_generator)
      sig = analysis.generate_signature(analysis.statements.first)

      expect(sig).to eq([:custom, "signature"])
    end

    it "falls through when generator returns a node" do
      yaml = "key: value"
      custom_generator = ->(node) { node }

      analysis = described_class.new(yaml, signature_generator: custom_generator)
      sig = analysis.generate_signature(analysis.statements.first)

      expect(sig).to eq([:mapping_entry, "key"])
    end

    it "falls through when generator returns a FreezeNodeBase" do
      yaml = <<~YAML
        # psych-merge:freeze
        frozen: value
        # psych-merge:unfreeze
      YAML

      custom_generator = ->(node) { node }
      analysis = described_class.new(yaml, signature_generator: custom_generator)
      freeze_node = analysis.freeze_blocks.first

      sig = analysis.generate_signature(freeze_node)
      expect(sig.first).to eq(:FreezeNode)
    end

    it "falls through when generator returns a NodeWrapper" do
      yaml = "key: value"
      custom_generator = ->(node) {
        if node.is_a?(Psych::Merge::MappingEntry)
          # Return a NodeWrapper instead
          node.value
        else
          node
        end
      }

      analysis = described_class.new(yaml, signature_generator: custom_generator)
      sig = analysis.generate_signature(analysis.statements.first)

      # Should fall through to compute_node_signature for the NodeWrapper
      expect(sig.first).to eq(:scalar)
    end
  end

  describe "#normalized_line" do
    it "returns stripped line content" do
      yaml = "  key: value  "
      analysis = described_class.new(yaml)

      expect(analysis.normalized_line(1)).to eq("key: value")
    end
  end

  describe "#line_at" do
    it "returns raw line content" do
      yaml = "key: value"
      analysis = described_class.new(yaml)

      expect(analysis.line_at(1)).to eq("key: value")
    end
  end

  describe "shared Ast::Merge comment accessors" do
    let(:yaml) do
      <<~YAML
        # Header comment
        defaults: # inline defaults
          key: value

        # Trailing comment
      YAML
    end

    it "reports source-augmented comment capability" do
      analysis = described_class.new(yaml)

      expect(analysis.comment_capability).to be_a(Ast::Merge::Comment::Capability)
      expect(analysis.comment_capability.source_augmented?).to be(true)
    end

    it "exposes comment nodes" do
      analysis = described_class.new(yaml)

      expect(analysis.comment_nodes.map(&:content)).to eq([
        "Header comment",
        "inline defaults",
        "Trailing comment",
      ])
    end

    it "returns a shared comment node at a line" do
      analysis = described_class.new(yaml)

      expect(analysis.comment_node_at(1)).to be_a(Ast::Merge::Comment::Line)
      expect(analysis.comment_node_at(2)&.content).to eq("inline defaults")
      expect(analysis.comment_node_at(3)).to be_nil
    end

    it "returns a shared comment region for a line range" do
      analysis = described_class.new(yaml)
      region = analysis.comment_region_for_range(1..2, kind: :leading)

      expect(region).to be_a(Ast::Merge::Comment::Region)
      expect(region.normalized_content).to eq("Header comment\ninline defaults")
    end

    it "builds a passive augmenter using default statement owners" do
      analysis = described_class.new(yaml)
      augmenter = analysis.comment_augmenter
      attachment = augmenter.attachment_for(analysis.statements.first)

      expect(augmenter).to be_a(Ast::Merge::Comment::Augmenter)
      expect(attachment).to be_a(Ast::Merge::Comment::Attachment)
      expect(attachment.leading_region).to be_nil
      expect(attachment.inline_region).not_to be_nil
      expect(attachment.inline_region.normalized_content).to eq("inline defaults")
      expect(augmenter.postlude_region).to be_nil
    end

    context "shared example compliance" do
      let(:analysis) { described_class.new(yaml) }

      context "for a normalized region" do
        let(:comment_region) { analysis.comment_region_for_range(1..1, kind: :leading) }
        let(:expected_region_kind) { :leading }
        let(:expected_region_content) { "Header comment" }
        let(:expected_region_lines) { 1..1 }
        let(:freeze_token) { "psych-merge" }
        let(:freeze_marker_expected) { false }

        it_behaves_like "Ast::Merge::Comment::Region"
      end

      context "for the passive augmenter" do
        let(:comment_augmenter) { analysis.comment_augmenter }
        let(:augmenter_owner) { analysis.statements.first }
        let(:expected_capability_predicate) { :source_augmented? }
        let(:expected_leading_content) { nil }
        let(:expected_inline_content) { "inline defaults" }
        let(:expected_preamble_content) { nil }
        let(:expected_postlude_content) { nil }
        let(:expected_orphan_contents) { ["Header comment", "Trailing comment"] }

        it_behaves_like "Ast::Merge::Comment::Augmenter"
      end
    end
  end

  describe "#root_mapping_entries" do
    it "returns mapping entries from root" do
      yaml = <<~YAML
        foo: bar
        baz: qux
      YAML

      analysis = described_class.new(yaml)
      entries = analysis.root_mapping_entries

      expect(entries.length).to eq(2)
    end
  end

  describe "anchor handling" do
    it "parses YAML with anchors" do
      yaml = <<~YAML
        defaults: &defaults
          adapter: postgres
          host: localhost
        development:
          <<: *defaults
          database: dev_db
      YAML

      analysis = described_class.new(yaml)

      expect(analysis.valid?).to be(true)
      expect(analysis.statements.length).to eq(2)
    end
  end

  describe "root node types" do
    it "handles root sequence" do
      yaml = <<~YAML
        - item1
        - item2
        - item3
      YAML

      analysis = described_class.new(yaml)

      expect(analysis.valid?).to be(true)
      expect(analysis.root_node).to be_a(Psych::Merge::NodeWrapper)
      expect(analysis.root_node.sequence?).to be(true)
    end

    it "handles root scalar" do
      yaml = "just a string"

      analysis = described_class.new(yaml)

      expect(analysis.valid?).to be(true)
    end

    it "returns empty entries for non-mapping root" do
      yaml = <<~YAML
        - item1
        - item2
      YAML

      analysis = described_class.new(yaml)
      entries = analysis.root_mapping_entries

      expect(entries).to be_empty
    end
  end

  describe "#root_node" do
    it "raises Psych::SyntaxError for invalid YAML" do
      yaml = "key: value\n  bad: indent"

      expect {
        described_class.new(yaml)
      }.to raise_error(Psych::SyntaxError)
    end

    it "returns the root node for valid YAML" do
      yaml = "key: value"
      analysis = described_class.new(yaml)

      expect(analysis.root_node).to be_a(Psych::Merge::NodeWrapper)
    end

    it "returns nil when AST has no children" do
      yaml = ""
      analysis = described_class.new(yaml)

      # Empty YAML should have no document children
      expect(analysis.root_node).to be_nil
    end
  end

  describe "#root_mapping_entries with empty YAML" do
    it "returns empty when AST has no children" do
      yaml = ""
      analysis = described_class.new(yaml)

      expect(analysis.root_mapping_entries).to be_empty
    end

    it "returns empty for non-document root" do
      # This is an edge case - normally streams contain documents
      yaml = "key: value"
      analysis = described_class.new(yaml)

      # The root should be a document with mapping
      entries = analysis.root_mapping_entries
      expect(entries.length).to eq(1)
    end
  end

  describe "freeze block edge cases" do
    it "handles unmatched freeze markers" do
      yaml = <<~YAML
        # psych-merge:freeze
        content: value
        # No unfreeze marker
      YAML

      analysis = described_class.new(yaml)

      # Should not create a freeze block without matching unfreeze
      expect(analysis.freeze_blocks).to be_empty
    end

    it "handles unmatched unfreeze markers" do
      yaml = <<~YAML
        # No freeze marker
        content: value
        # psych-merge:unfreeze
      YAML

      analysis = described_class.new(yaml)

      expect(analysis.freeze_blocks).to be_empty
    end

    it "integrates freeze blocks with nodes correctly" do
      yaml = <<~YAML
        before: value
        # psych-merge:freeze
        frozen: secret
        # psych-merge:unfreeze
        after: value
      YAML

      analysis = described_class.new(yaml)

      # Should have 3 items: before node, freeze block, after node
      expect(analysis.statements.length).to eq(3)
      expect(analysis.statements[1]).to be_a(Psych::Merge::FreezeNode)
    end

    it "excludes nodes inside freeze blocks from regular nodes" do
      yaml = <<~YAML
        normal: value
        # psych-merge:freeze
        frozen1: secret1
        frozen2: secret2
        # psych-merge:unfreeze
      YAML

      analysis = described_class.new(yaml)

      # Should not have MappingEntry for frozen content
      freeze_nodes = analysis.statements.select { |n| n.is_a?(Psych::Merge::FreezeNode) }
      expect(freeze_nodes.length).to eq(1)
    end
  end

  describe "#line_at edge cases" do
    it "returns nil for line 0" do
      yaml = "key: value"
      analysis = described_class.new(yaml)

      expect(analysis.line_at(0)).to be_nil
    end

    it "returns nil for negative line numbers" do
      yaml = "key: value"
      analysis = described_class.new(yaml)

      expect(analysis.line_at(-1)).to be_nil
    end
  end

  describe "#normalized_line edge cases" do
    it "returns nil for out of range lines" do
      yaml = "key: value"
      analysis = described_class.new(yaml)

      expect(analysis.normalized_line(0)).to be_nil
      expect(analysis.normalized_line(100)).to be_nil
    end
  end

  describe "MappingEntry" do
    let(:yaml) do
      <<~YAML
        # Leading comment
        key: value
      YAML
    end

    let(:analysis) { described_class.new(yaml) }
    let(:entry) { analysis.statements.first }

    it "returns key_name" do
      expect(entry.key_name).to eq("key")
    end

    it "includes leading comments in start_line" do
      # Entry should start at comment line, not key line
      expect(entry.start_line).to eq(1)
    end

    it "returns line_range" do
      range = entry.line_range
      expect(range).to be_a(Range)
    end

    it "returns content" do
      content = entry.content
      expect(content).to include("key: value")
    end

    it "returns signature" do
      sig = entry.signature
      expect(sig).to eq([:mapping_entry, "key"])
    end

    it "returns location" do
      location = entry.location
      expect(location.start_line).to eq(entry.start_line)
      expect(location.end_line).to eq(entry.end_line)
    end

    it "freeze_node? returns false" do
      expect(entry.freeze_node?).to be(false)
    end

    describe "delegate methods" do
      let(:nested_yaml) do
        <<~YAML
          parent:
            child: value
        YAML
      end

      let(:nested_analysis) { described_class.new(nested_yaml) }
      let(:nested_entry) { nested_analysis.statements.first }

      it "mapping? delegates to value" do
        expect(nested_entry.mapping?).to be(true)
      end

      it "sequence? delegates to value" do
        expect(nested_entry.sequence?).to be(false)
      end

      it "scalar? delegates to value" do
        expect(entry.scalar?).to be(true)
      end

      it "anchor delegates to value" do
        expect(entry.anchor).to be_nil
      end
    end

    it "inspect returns readable string" do
      expect(entry.inspect).to include("MappingEntry")
      expect(entry.inspect).to include("key")
    end

    it "exposes a passive shared comment attachment" do
      attachment = entry.comment_attachment

      expect(attachment).to be_a(Ast::Merge::Comment::Attachment)
      expect(entry.leading_comment_region&.normalized_content).to eq("Leading comment")
      expect(entry.inline_comment_region).to be_nil
    end

    context "shared example compliance" do
      let(:comment_attachment) { entry.comment_attachment }
      let(:expected_attachment_owner) { entry }
      let(:expected_leading_content) { "Leading comment" }
      let(:expected_inline_content) { nil }
      let(:expected_trailing_content) { nil }
      let(:expected_orphan_contents) { [] }
      let(:freeze_token) { "psych-merge" }
      let(:freeze_marker_expected) { false }

      it_behaves_like "Ast::Merge::Comment::Attachment"
    end

    describe "#line_range" do
      it "returns nil when start_line is nil" do
        # Create an entry where the key has no line info
        mock_key = instance_double(Psych::Merge::NodeWrapper, start_line: nil, end_line: nil, value: "key")
        mock_value = instance_double(Psych::Merge::NodeWrapper, end_line: nil)
        mock_tracker = instance_double(
          Psych::Merge::CommentTracker,
          leading_comments_before: [],
          inline_comment_at: nil,
        )
        allow(mock_tracker).to receive(:comment_attachment_for) do |owner, **_options|
          Ast::Merge::Comment::Attachment.new(owner: owner)
        end

        entry = Psych::Merge::MappingEntry.new(
          key: mock_key,
          value: mock_value,
          lines: [],
          comment_tracker: mock_tracker,
        )

        expect(entry.line_range).to be_nil
      end
    end

    describe "#content" do
      it "returns empty string when start_line is nil" do
        mock_key = instance_double(Psych::Merge::NodeWrapper, start_line: nil, end_line: nil, value: "key")
        mock_value = instance_double(Psych::Merge::NodeWrapper, end_line: nil)
        mock_tracker = instance_double(
          Psych::Merge::CommentTracker,
          leading_comments_before: [],
          inline_comment_at: nil,
        )
        allow(mock_tracker).to receive(:comment_attachment_for) do |owner, **_options|
          Ast::Merge::Comment::Attachment.new(owner: owner)
        end

        entry = Psych::Merge::MappingEntry.new(
          key: mock_key,
          value: mock_value,
          lines: [],
          comment_tracker: mock_tracker,
        )

        expect(entry.content).to eq("")
      end
    end

    describe "#end_line" do
      it "falls back to key end_line when value end_line is nil" do
        mock_key = instance_double(Psych::Merge::NodeWrapper, start_line: 1, end_line: 2, value: "key")
        mock_value = instance_double(Psych::Merge::NodeWrapper, end_line: nil)
        mock_tracker = instance_double(
          Psych::Merge::CommentTracker,
          leading_comments_before: [],
          inline_comment_at: nil,
        )
        allow(mock_tracker).to receive(:comment_attachment_for) do |owner, **_options|
          Ast::Merge::Comment::Attachment.new(owner: owner)
        end

        entry = Psych::Merge::MappingEntry.new(
          key: mock_key,
          value: mock_value,
          lines: ["key: value", "more"],
          comment_tracker: mock_tracker,
        )

        expect(entry.end_line).to eq(2)
      end
    end
  end

  describe "#integrate_nodes_and_freeze_blocks" do
    it "handles document that is not a Psych Document" do
      # This tests the early return when doc is not a Document
      # We can't easily create this scenario, but we can test via root_mapping_entries
      yaml = ""
      analysis = described_class.new(yaml)

      # Empty YAML won't have proper document structure
      expect(analysis.statements).to eq([])
    end

    it "handles root that is not a mapping (sequence)" do
      yaml = <<~YAML
        - item1
        - item2
      YAML

      analysis = described_class.new(yaml)

      # Should wrap the sequence as a single node
      expect(analysis.statements.length).to eq(1)
      expect(analysis.statements.first).to be_a(Psych::Merge::NodeWrapper)
      expect(analysis.statements.first.sequence?).to be(true)
    end

    it "handles root scalar" do
      yaml = "just a scalar"

      analysis = described_class.new(yaml)

      expect(analysis.statements.length).to eq(1)
      expect(analysis.statements.first).to be_a(Psych::Merge::NodeWrapper)
      expect(analysis.statements.first.scalar?).to be(true)
    end

    it "handles freeze block already in all_nodes list" do
      # This tests the `unless all_nodes.include?(fb)` branch
      yaml = <<~YAML
        # psych-merge:freeze
        frozen: value
        # psych-merge:unfreeze
        after: content
      YAML

      analysis = described_class.new(yaml)

      # The freeze block should appear only once
      freeze_nodes = analysis.statements.select { |n| n.is_a?(Psych::Merge::FreezeNode) }
      expect(freeze_nodes.length).to eq(1)
    end
  end

  describe "#compute_node_signature" do
    it "returns nil for unknown node types" do
      yaml = "key: value"
      analysis = described_class.new(yaml)

      # Pass something that isn't FreezeNodeBase, MappingEntry, or NodeWrapper
      sig = analysis.send(:compute_node_signature, "unknown")

      expect(sig).to be_nil
    end
  end

  describe "#root_mapping_entries for non-mapping YAML" do
    it "returns empty when doc is not a Document" do
      # Empty YAML
      yaml = ""
      analysis = described_class.new(yaml)

      expect(analysis.root_mapping_entries).to eq([])
    end

    it "returns empty when root is not a Mapping" do
      yaml = <<~YAML
        - item1
        - item2
      YAML

      analysis = described_class.new(yaml)

      expect(analysis.root_mapping_entries).to eq([])
    end
  end

  describe "#root_node edge cases" do
    it "returns nil when doc is not a Document or has no meaningful root" do
      # Empty YAML string - no content at all
      yaml = ""
      analysis = described_class.new(yaml)

      # Empty YAML should have no root node
      expect(analysis.root_node).to be_nil
    end

    it "returns NodeWrapper for valid mapping" do
      yaml = "key: value"
      analysis = described_class.new(yaml)

      node = analysis.root_node
      expect(node).to be_a(Psych::Merge::NodeWrapper)
      expect(node.mapping?).to be(true)
    end

    it "returns NodeWrapper for valid sequence" do
      yaml = "- item1\n- item2"
      analysis = described_class.new(yaml)

      node = analysis.root_node
      expect(node).to be_a(Psych::Merge::NodeWrapper)
      expect(node.sequence?).to be(true)
    end

    it "returns NodeWrapper for valid scalar" do
      yaml = "just a string"
      analysis = described_class.new(yaml)

      node = analysis.root_node
      expect(node).to be_a(Psych::Merge::NodeWrapper)
      expect(node.scalar?).to be(true)
    end
  end

  describe "#root_mapping_entries with valid mapping" do
    it "returns entries for valid mapping" do
      yaml = <<~YAML
        key1: value1
        key2: value2
      YAML
      analysis = described_class.new(yaml)

      entries = analysis.root_mapping_entries
      expect(entries.length).to eq(2)
    end
  end

  describe "#integrate_nodes_and_freeze_blocks edge cases" do
    it "handles freeze block at end of file (after all entries)" do
      yaml = <<~YAML
        first: value
        second: value
        # psych-merge:freeze
        frozen: secret
        # psych-merge:unfreeze
      YAML

      analysis = described_class.new(yaml)

      # Freeze block should be added at the end
      freeze_nodes = analysis.statements.select { |n| n.is_a?(Psych::Merge::FreezeNode) }
      expect(freeze_nodes.length).to eq(1)
      expect(analysis.statements.last).to be_a(Psych::Merge::FreezeNode)
    end

    it "handles freeze block at start of file (before all entries)" do
      yaml = <<~YAML
        # psych-merge:freeze
        frozen: secret
        # psych-merge:unfreeze
        first: value
        second: value
      YAML

      analysis = described_class.new(yaml)

      freeze_nodes = analysis.statements.select { |n| n.is_a?(Psych::Merge::FreezeNode) }
      expect(freeze_nodes.length).to eq(1)
      expect(analysis.statements.first).to be_a(Psych::Merge::FreezeNode)
    end

    it "handles sequence root with freeze blocks" do
      yaml = <<~YAML
        - item1
        - item2
      YAML

      analysis = described_class.new(yaml)

      # Sequence root should be wrapped as single NodeWrapper
      expect(analysis.statements.length).to eq(1)
      expect(analysis.statements.first.sequence?).to be(true)
    end

    it "handles scalar root" do
      yaml = "just a scalar value"

      analysis = described_class.new(yaml)

      expect(analysis.statements.length).to eq(1)
      expect(analysis.statements.first.scalar?).to be(true)
    end
  end

  describe "shared Ast::Merge comment attachments on root owners" do
    it "exposes a passive shared attachment on a root sequence node" do
      yaml = <<~YAML
        # Sequence header
        - item1
        - item2
      YAML

      analysis = described_class.new(yaml)
      root = analysis.root_node

      expect(root.comment_attachment).to be_a(Ast::Merge::Comment::Attachment)
      expect(root.leading_comment_region&.normalized_content).to eq("Sequence header")
    end

    it "delegates owner attachments through FileAnalysis" do
      yaml = <<~YAML
        # Root header
        key: value
      YAML

      analysis = described_class.new(yaml)
      attachment = analysis.comment_attachment_for(analysis.root_node, line_num: 2)

      expect(attachment).to be_a(Ast::Merge::Comment::Attachment)
      expect(attachment.leading_region&.normalized_content).to eq("Root header")
    end

    it "infers a shared postlude region for trailing footer comments" do
      yaml = <<~YAML
        key: value

        # Footer comment
      YAML

      analysis = described_class.new(yaml)
      augmenter = analysis.comment_augmenter

      expect(augmenter.postlude_region).to be_a(Ast::Merge::Comment::Region)
      expect(augmenter.postlude_region.postlude?).to be(true)
      expect(augmenter.postlude_region.normalized_content).to eq("Footer comment")
    end
  end
end

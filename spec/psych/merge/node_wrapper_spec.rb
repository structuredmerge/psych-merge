# frozen_string_literal: true

RSpec.describe Psych::Merge::NodeWrapper do
  let(:simple_yaml) { "key: value" }
  let(:lines) { simple_yaml.lines.map(&:chomp) }

  describe "#initialize" do
    it "wraps a Psych node" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: lines)

      expect(wrapper.node).to eq(root)
      expect(wrapper.mapping?).to be(true)
    end

    it "accepts leading comments" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first

      comments = [{line: 1, text: "comment", full_line: true}]
      wrapper = described_class.new(root, lines: lines, leading_comments: comments)

      expect(wrapper.leading_comments).to eq(comments)
    end

    it "handles node without start_line" do
      # Create a mock node without start_line
      mock_node = double("node")
      allow(mock_node).to receive(:respond_to?).with(:start_line).and_return(false)
      allow(mock_node).to receive(:respond_to?).with(:end_line).and_return(false)
      allow(mock_node).to receive(:respond_to?).with(:anchor).and_return(false)
      allow(mock_node).to receive(:respond_to?).with(:children).and_return(false)
      allow(mock_node).to receive(:is_a?).and_return(false)

      wrapper = described_class.new(mock_node, lines: lines)

      expect(wrapper.start_line).to be_nil
      expect(wrapper.end_line).to be_nil
    end

    it "accepts a comment tracker" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first
      tracker = Psych::Merge::CommentTracker.new("# comment\nkey: value\n")

      wrapper = described_class.new(root, lines: lines, comment_tracker: tracker)

      expect(wrapper.comment_tracker).to eq(tracker)
    end
  end

  describe "shared Ast::Merge comment attachments" do
    it "builds a passive attachment from raw wrapper comments" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first
      leading = [{line: 1, indent: 0, text: "Header", full_line: true, raw: "# Header"}]
      inline = {line: 2, indent: 11, text: "inline note", full_line: false, raw: "key: value # inline note"}

      wrapper = described_class.new(
        root,
        lines: ["# Header", "key: value # inline note"],
        leading_comments: leading,
        inline_comment: inline,
      )

      attachment = wrapper.comment_attachment

      expect(attachment).to be_a(Ast::Merge::Comment::Attachment)
      expect(wrapper.leading_comment_region&.normalized_content).to eq("Header")
      expect(wrapper.inline_comment_region&.normalized_content).to eq("inline note")
    end

    it "uses the comment tracker when available" do
      yaml = <<~YAML
        # Header
        key: value # inline note
      YAML
      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first
      value_node = root.children[1]
      tracker = Psych::Merge::CommentTracker.new(yaml)

      wrapper = described_class.new(value_node, lines: yaml.lines.map(&:chomp), comment_tracker: tracker)
      attachment = wrapper.comment_attachment

      expect(attachment).to be_a(Ast::Merge::Comment::Attachment)
      expect(attachment.inline_region&.normalized_content).to eq("inline note")
    end

    context "shared example compliance" do
      let(:leading) do
        [{line: 1, indent: 0, text: "Header", full_line: true, raw: "# Header"}]
      end
      let(:inline) do
        {line: 2, indent: 11, text: "inline note", full_line: false, raw: "key: value # inline note"}
      end
      let(:ast) { Psych.parse_stream(simple_yaml) }
      let(:doc) { ast.children.first }
      let(:root) { doc.children.first }
      let(:wrapper) do
        described_class.new(
          root,
          lines: ["# Header", "key: value # inline note"],
          leading_comments: leading,
          inline_comment: inline,
        )
      end

      context "for the attachment" do
        let(:comment_attachment) { wrapper.comment_attachment }
        let(:expected_attachment_owner) { wrapper }
        let(:expected_leading_content) { "Header" }
        let(:expected_inline_content) { "inline note" }
        let(:expected_trailing_content) { nil }
        let(:expected_orphan_contents) { [] }
        let(:freeze_token) { "psych-merge" }
        let(:freeze_marker_expected) { false }

        it_behaves_like "Ast::Merge::Comment::Attachment"
      end

      context "for the inline region" do
        let(:comment_region) { wrapper.inline_comment_region }
        let(:expected_region_kind) { :inline }
        let(:expected_region_content) { "inline note" }
        let(:expected_region_lines) { 2..2 }
        let(:freeze_token) { "psych-merge" }
        let(:freeze_marker_expected) { false }

        it_behaves_like "Ast::Merge::Comment::Region"
      end
    end
  end

  describe "#signature" do
    it "generates signature for mapping" do
      yaml = <<~YAML
        foo: bar
        baz: qux
      YAML

      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      sig = wrapper.signature

      expect(sig.first).to eq(:mapping)
      expect(sig.last).to include("foo", "baz")
    end

    it "generates signature for scalar" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first
      # First child of mapping is the key scalar
      key_scalar = root.children.first

      wrapper = described_class.new(key_scalar, lines: lines)
      sig = wrapper.signature

      expect(sig.first).to eq(:scalar)
      expect(sig.last).to eq("key")
    end

    it "generates signature for sequence" do
      yaml = <<~YAML
        - item1
        - item2
      YAML

      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      sig = wrapper.signature

      expect(sig.first).to eq(:sequence)
    end
  end

  describe "#mapping?" do
    it "returns true for mapping nodes" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: lines)
      expect(wrapper.mapping?).to be(true)
    end

    it "returns false for non-mapping nodes" do
      yaml = "- item"
      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      expect(wrapper.mapping?).to be(false)
    end
  end

  describe "#sequence?" do
    it "returns true for sequence nodes" do
      yaml = "- item"
      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      expect(wrapper.sequence?).to be(true)
    end
  end

  describe "#scalar?" do
    it "returns true for scalar nodes" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first
      key_scalar = root.children.first

      wrapper = described_class.new(key_scalar, lines: lines)
      expect(wrapper.scalar?).to be(true)
    end
  end

  describe "#mapping_entries" do
    it "returns key-value pairs" do
      yaml = <<~YAML
        foo: bar
        baz: qux
      YAML

      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      entries = wrapper.mapping_entries

      expect(entries.length).to eq(2)
      expect(entries.first[0].value).to eq("foo")
      expect(entries.first[1].value).to eq("bar")
    end

    it "returns empty for non-mapping" do
      yaml = <<~YAML
        - item1
        - item2
      YAML

      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      entries = wrapper.mapping_entries

      expect(entries).to be_empty
    end
  end

  describe "#anchor" do
    it "returns anchor name when present" do
      yaml = <<~YAML
        defaults: &defaults
          foo: bar
      YAML

      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first
      # The value of "defaults" is the mapping with anchor
      value_node = root.children[1]

      wrapper = described_class.new(value_node, lines: yaml.lines.map(&:chomp))
      expect(wrapper.anchor).to eq("defaults")
    end

    it "returns nil when no anchor" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: lines)
      expect(wrapper.anchor).to be_nil
    end

    it "returns nil when node does not respond to anchor" do
      mock_node = double("node")
      allow(mock_node).to receive(:respond_to?).with(:start_line).and_return(false)
      allow(mock_node).to receive(:respond_to?).with(:end_line).and_return(false)
      allow(mock_node).to receive(:respond_to?).with(:anchor).and_return(false)
      allow(mock_node).to receive(:is_a?).and_return(false)

      wrapper = described_class.new(mock_node, lines: lines)
      expect(wrapper.anchor).to be_nil
    end
  end

  describe "#freeze_node?" do
    it "returns false" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: lines)
      expect(wrapper.freeze_node?).to be(false)
    end
  end

  describe "#alias?" do
    it "returns true for alias nodes" do
      yaml = <<~YAML
        defaults: &defaults
          value: test
        reference: *defaults
      YAML

      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first
      # Get the alias node (value of "reference")
      alias_node = root.children[3]

      wrapper = described_class.new(alias_node, lines: yaml.lines.map(&:chomp))
      expect(wrapper.alias?).to be(true)
    end

    it "returns false for non-alias nodes" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: lines)
      expect(wrapper.alias?).to be(false)
    end
  end

  describe "#alias_anchor" do
    it "returns the anchor name for aliases" do
      yaml = <<~YAML
        defaults: &defaults
          value: test
        reference: *defaults
      YAML

      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first
      alias_node = root.children[3]

      wrapper = described_class.new(alias_node, lines: yaml.lines.map(&:chomp))
      expect(wrapper.alias_anchor).to eq("defaults")
    end
  end

  describe "#value" do
    it "returns scalar value" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first
      # Value scalar is second child
      value_scalar = root.children[1]

      wrapper = described_class.new(value_scalar, lines: lines)
      expect(wrapper.value).to eq("value")
    end

    it "returns nil for non-scalar nodes" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: lines)
      expect(wrapper.value).to be_nil
    end
  end

  describe "#content" do
    it "returns the content for the node" do
      yaml = <<~YAML
        key: value
        other: stuff
      YAML

      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      expect(wrapper.content).to include("key: value")
    end

    it "returns empty string when no line info" do
      ast = Psych.parse_stream(simple_yaml)
      _doc = ast.children.first

      # Create wrapper with node that doesn't have line info using stub_const
      fake_node_class = Class.new do
        def start_line = nil
        def end_line = nil

        def respond_to?(method, include_all = false)
          [:start_line, :end_line].include?(method) || super
        end
      end
      stub_const("FakeNode", fake_node_class)

      wrapper = described_class.new(FakeNode.new, lines: lines)
      expect(wrapper.content).to eq("")
    end
  end

  describe "#inspect" do
    it "returns readable representation" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: lines, key: "test_key")
      inspect_str = wrapper.inspect

      expect(inspect_str).to include("NodeWrapper")
      expect(inspect_str).to include("Mapping")
      expect(inspect_str).to include("test_key")
    end
  end

  describe "#children" do
    it "returns wrapped children" do
      yaml = <<~YAML
        parent:
          child: value
      YAML

      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      children = wrapper.children

      expect(children).to all(be_a(described_class))
    end

    it "returns empty array for nodes without children" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first
      scalar = root.children.first

      wrapper = described_class.new(scalar, lines: lines)
      expect(wrapper.children).to be_empty
    end
  end

  describe "#sequence_items" do
    it "returns wrapped sequence items" do
      yaml = <<~YAML
        - item1
        - item2
        - item3
      YAML

      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      items = wrapper.sequence_items

      expect(items.length).to eq(3)
      expect(items).to all(be_a(described_class))
    end

    it "returns empty array for non-sequences" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: lines)
      expect(wrapper.sequence_items).to be_empty
    end

    it "preserves comment attachments on wrapped sequence items" do
      yaml = <<~YAML
        # Sequence comment
        - item1 # inline note
      YAML

      tracker = Psych::Merge::CommentTracker.new(yaml)
      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp), comment_tracker: tracker)
      item = wrapper.sequence_items(comment_tracker: tracker).first

      expect(item.comment_tracker).to eq(tracker)
      expect(item.leading_comment_region&.normalized_content).to eq("Sequence comment")
      expect(item.inline_comment_region&.normalized_content).to eq("inline note")
    end
  end

  describe "#signature for different node types" do
    it "generates signature for document" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first

      wrapper = described_class.new(doc, lines: lines)
      sig = wrapper.signature

      expect(sig.first).to eq(:document)
      expect(sig.last).to eq("Mapping")
    end

    it "generates signature for stream" do
      ast = Psych.parse_stream(simple_yaml)

      wrapper = described_class.new(ast, lines: lines)
      sig = wrapper.signature

      expect(sig).to eq([:stream])
    end

    it "generates signature for alias" do
      yaml = <<~YAML
        defaults: &defaults
          value: test
        reference: *defaults
      YAML

      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first
      alias_node = root.children[3]

      wrapper = described_class.new(alias_node, lines: yaml.lines.map(&:chomp))
      sig = wrapper.signature

      expect(sig.first).to eq(:alias)
      expect(sig.last).to eq("defaults")
    end

    it "returns nil for unknown node types" do
      mock_node = double("unknown_node")
      allow(mock_node).to receive(:respond_to?).with(:start_line).and_return(false)
      allow(mock_node).to receive(:respond_to?).with(:end_line).and_return(false)
      allow(mock_node).to receive(:respond_to?).with(:anchor).and_return(false)
      allow(mock_node).to receive(:is_a?).and_return(false)

      wrapper = described_class.new(mock_node, lines: lines)
      sig = wrapper.signature

      expect(sig).to be_nil
    end
  end

  describe "with comment tracker" do
    it "associates leading comments" do
      yaml = <<~YAML
        # Leading comment
        key: value
      YAML

      tracker = Psych::Merge::CommentTracker.new(yaml)
      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      entries = wrapper.mapping_entries(comment_tracker: tracker)

      # The key wrapper should have leading comments
      expect(entries.first[0].leading_comments).not_to be_empty
    end
  end

  describe "edge cases" do
    it "handles end_line before start_line" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first

      # Mock a node with end_line < start_line
      allow(root).to receive(:end_line).and_return(0)

      wrapper = described_class.new(root, lines: lines)
      # Should adjust end_line to match start_line
      expect(wrapper.end_line).to be >= wrapper.start_line if wrapper.start_line && wrapper.end_line
    end

    it "adjusts end_line to match start_line when end is before start" do
      mock_node = double("node")
      allow(mock_node).to receive_messages(
        start_line: 5,
        end_line: 2,  # end before start
        anchor: nil,
      )
      allow(mock_node).to receive(:respond_to?).with(:start_line).and_return(true)
      allow(mock_node).to receive(:respond_to?).with(:end_line).and_return(true)
      allow(mock_node).to receive(:respond_to?).with(:anchor).and_return(false)
      allow(mock_node).to receive(:is_a?).and_return(false)

      wrapper = described_class.new(mock_node, lines: lines)
      # end_line should be adjusted to match start_line
      expect(wrapper.end_line).to eq(wrapper.start_line)
    end
  end

  describe "#mapping_entries edge cases" do
    it "breaks early when value_node is nil (odd children)" do
      # Create a mapping with odd number of children
      yaml = "key: value"
      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      # Mock having an odd number of children
      original_children = root.children.dup
      allow(root).to receive(:children).and_return(original_children + [original_children.first])

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      entries = wrapper.mapping_entries

      # Should only return complete pairs
      expect(entries.length).to eq(1)
    end
  end

  describe "#alias_anchor for non-alias nodes" do
    it "returns nil for non-alias nodes" do
      ast = Psych.parse_stream(simple_yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: lines)
      expect(wrapper.alias_anchor).to be_nil
    end
  end

  describe "#compute_signature edge cases" do
    it "handles sequence with nil children" do
      yaml = "- item"
      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      # Mock sequence with nil children
      allow(root).to receive(:children).and_return(nil)

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      sig = wrapper.signature

      expect(sig.first).to eq(:sequence)
      expect(sig.last).to eq(0)  # Should use || 0 fallback
    end

    it "handles document with nil children" do
      yaml = "key: value"
      ast = Psych.parse_stream(yaml)
      doc = ast.children.first

      # Mock document with nil children
      allow(doc).to receive(:children).and_return(nil)

      wrapper = described_class.new(doc, lines: yaml.lines.map(&:chomp))
      sig = wrapper.signature

      expect(sig.first).to eq(:document)
      expect(sig.last).to be_nil
    end

    it "handles document with empty children" do
      yaml = "---\n..."
      ast = Psych.parse_stream(yaml)
      doc = ast.children.first

      wrapper = described_class.new(doc, lines: yaml.lines.map(&:chomp))
      sig = wrapper.signature

      expect(sig.first).to eq(:document)
    end
  end

  describe "#extract_mapping_keys edge cases" do
    it "returns empty array when mapping has nil children" do
      yaml = "key: value"
      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      # Mock mapping with nil children
      allow(root).to receive(:children).and_return(nil)

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      # Calling signature will trigger extract_mapping_keys
      sig = wrapper.signature

      expect(sig).to eq([:mapping, nil, []])
    end

    it "skips non-scalar keys in mapping" do
      # Create YAML with a complex key (mapping as key)
      yaml = <<~YAML
        ? nested_key: nested_value
        : complex_value
        simple: value
      YAML

      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      sig = wrapper.signature

      # Should only extract the simple scalar key
      expect(sig.first).to eq(:mapping)
      expect(sig.last).to include("simple")
    end
  end

  describe "#extract_key_name" do
    it "returns nil for non-scalar key nodes" do
      # Create YAML with a complex key
      yaml = <<~YAML
        ? - list_item
        : value
      YAML

      ast = Psych.parse_stream(yaml)
      doc = ast.children.first
      root = doc.children.first

      wrapper = described_class.new(root, lines: yaml.lines.map(&:chomp))
      entries = wrapper.mapping_entries

      # The key wrapper should have nil value since key is a sequence
      if entries.any?
        key_wrapper = entries.first[0]
        expect(key_wrapper.value).to be_nil
      end
    end
  end
end

# frozen_string_literal: true

require "ast/merge/rspec/shared_examples"

RSpec.describe Psych::Merge::ConflictResolver do
  # Use shared examples to validate base ConflictResolverBase integration
  # Note: psych-merge uses the :batch strategy
  it_behaves_like "Ast::Merge::ConflictResolverBase" do
    let(:conflict_resolver_class) { described_class }
    let(:strategy) { :batch }
    let(:build_conflict_resolver) do
      ->(preference:, template_analysis:, dest_analysis:, **opts) {
        described_class.new(
          template_analysis,
          dest_analysis,
          preference: preference,
          add_template_only_nodes: opts.fetch(:add_template_only_nodes, false),
        )
      }
    end
    let(:build_mock_analysis) do
      -> {
        source = "key: value\n"
        Psych::Merge::FileAnalysis.new(source)
      }
    end
  end

  it_behaves_like "Ast::Merge::ConflictResolverBase batch strategy" do
    let(:conflict_resolver_class) { described_class }
    let(:build_conflict_resolver) do
      ->(preference:, template_analysis:, dest_analysis:, **opts) {
        described_class.new(
          template_analysis,
          dest_analysis,
          preference: preference,
          add_template_only_nodes: opts.fetch(:add_template_only_nodes, false),
        )
      }
    end
    let(:build_mock_analysis) do
      -> {
        source = "key: value\n"
        Psych::Merge::FileAnalysis.new(source)
      }
    end
  end

  let(:template_yaml) do
    <<~YAML
      key1: template_value1
      key2: template_value2
      key3: template_value3
    YAML
  end

  let(:dest_yaml) do
    <<~YAML
      key1: dest_value1
      key2: dest_value2
      dest_only: special_value
    YAML
  end

  let(:template_analysis) { Psych::Merge::FileAnalysis.new(template_yaml) }
  let(:dest_analysis) { Psych::Merge::FileAnalysis.new(dest_yaml) }

  describe "#initialize" do
    it "accepts analyses and options" do
      resolver = described_class.new(
        template_analysis,
        dest_analysis,
        preference: :template,
        add_template_only_nodes: true,
      )

      expect(resolver.template_analysis).to eq(template_analysis)
      expect(resolver.dest_analysis).to eq(dest_analysis)
      expect(resolver.preference).to eq(:template)
      expect(resolver.add_template_only_nodes).to be(true)
    end

    it "defaults to destination preference" do
      resolver = described_class.new(template_analysis, dest_analysis)

      expect(resolver.preference).to eq(:destination)
      expect(resolver.add_template_only_nodes).to be(false)
    end
  end

  describe "#resolve" do
    context "with destination preference" do
      it "keeps destination values for matching keys" do
        resolver = described_class.new(template_analysis, dest_analysis)
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("dest_value1")
        expect(yaml).to include("dest_value2")
        expect(yaml).not_to include("template_value")
      end

      it "keeps destination-only keys" do
        resolver = described_class.new(template_analysis, dest_analysis)
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("dest_only")
        expect(yaml).to include("special_value")
      end

      it "does not add template-only keys" do
        resolver = described_class.new(template_analysis, dest_analysis)
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).not_to include("key3")
      end
    end

    context "with template preference" do
      it "keeps template values for matching keys" do
        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("template_value1")
        expect(yaml).to include("template_value2")
      end
    end

    context "with per-node-type preference" do
      it "uses template values for typed nodes and destination for others" do
        node_typing = {
          "MappingEntry" => lambda { |node|
            if node.key_name == "key2"
              Ast::Merge::NodeTyping.with_merge_type(node, :special_key)
            else
              node
            end
          },
        }

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: {default: :destination, special_key: :template},
          node_typing: node_typing,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("key1: dest_value1")
        expect(yaml).to include("key2: template_value2")
      end
    end

    context "with add_template_only_nodes enabled" do
      it "adds template-only keys" do
        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          add_template_only_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("key3")
        expect(yaml).to include("template_value3")
      end
    end

    context "with freeze blocks" do
      let(:dest_with_freeze) do
        <<~YAML
          normal: dest_value
          # psych-merge:freeze
          frozen: secret_value
          # psych-merge:unfreeze
        YAML
      end

      let(:dest_freeze_analysis) { Psych::Merge::FileAnalysis.new(dest_with_freeze) }

      it "preserves freeze blocks from destination" do
        template = <<~YAML
          normal: template_value
          frozen: template_frozen
        YAML
        template_analysis = Psych::Merge::FileAnalysis.new(template)

        resolver = described_class.new(template_analysis, dest_freeze_analysis)
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("secret_value")
        expect(yaml).to include("psych-merge:freeze")
      end
    end

    context "with template preference and add_template_only_nodes" do
      it "adds template-only nodes with template values" do
        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("key3")
        expect(yaml).to include("template_value3")
      end
    end

    context "with nodes that have no signature" do
      let(:custom_generator) { ->(node) { nil } }

      it "handles nodes without signatures" do
        template = Psych::Merge::FileAnalysis.new(template_yaml, signature_generator: custom_generator)
        dest = Psych::Merge::FileAnalysis.new(dest_yaml, signature_generator: custom_generator)

        resolver = described_class.new(template, dest)
        result = Psych::Merge::MergeResult.new

        # Should not raise error
        expect { resolver.resolve(result) }.not_to raise_error
      end
    end

    context "with complex nested structures" do
      let(:complex_template) do
        <<~YAML
          parent:
            child1: value1
            child2: value2
          sibling: other
        YAML
      end

      let(:complex_dest) do
        <<~YAML
          parent:
            child1: customized
            child3: new_child
          sibling: modified
        YAML
      end

      it "handles nested mapping structures" do
        template = Psych::Merge::FileAnalysis.new(complex_template)
        dest = Psych::Merge::FileAnalysis.new(complex_dest)

        resolver = described_class.new(template, dest)
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("customized")
        expect(yaml).to include("child3")
      end
    end

    context "with duplicate signatures in template" do
      let(:dup_template) do
        <<~YAML
          key1: value1
          key1: value2
        YAML
      end

      let(:dup_dest) do
        <<~YAML
          key1: dest_value
        YAML
      end

      it "handles duplicate keys in template" do
        # YAML allows duplicate keys (later overwrites earlier)
        # But our signature map will have multiple entries
        template = Psych::Merge::FileAnalysis.new(dup_template)
        dest = Psych::Merge::FileAnalysis.new(dup_dest)

        resolver = described_class.new(template, dest)
        result = Psych::Merge::MergeResult.new

        expect { resolver.resolve(result) }.not_to raise_error
      end
    end

    context "with raw NodeWrapper nodes" do
      it "handles NodeWrapper directly in add_node_to_result" do
        # Create a scenario where a raw NodeWrapper is processed
        yaml = <<~YAML
          - item1
          - item2
        YAML

        template = Psych::Merge::FileAnalysis.new(yaml)
        dest = Psych::Merge::FileAnalysis.new(yaml)

        resolver = described_class.new(template, dest)
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)

        # Should not raise error and should produce output
        expect(result.to_yaml).not_to be_empty
      end
    end

    context "with template freeze blocks" do
      let(:template_with_freeze) do
        <<~YAML
          normal: value
          # psych-merge:freeze
          frozen: template_frozen
          # psych-merge:unfreeze
        YAML
      end

      it "skips freeze blocks from template when adding template-only nodes" do
        dest = <<~YAML
          other: dest_value
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template_with_freeze)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          add_template_only_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        # Should have dest content and template-only normal node
        expect(yaml).to include("other: dest_value")
        expect(yaml).to include("normal: value")
        # Should NOT include template freeze block content
        expect(yaml).not_to include("template_frozen")
      end
    end

    context "with template preference and leading comments" do
      it "includes leading comments when using template source" do
        template = <<~YAML
          # Template comment
          key: template_value
        YAML
        dest = <<~YAML
          key: dest_value
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("Template comment")
        expect(yaml).to include("template_value")
      end
    end

    context "with template preference on multiple matching keys" do
      it "uses template values for all matching keys" do
        template = <<~YAML
          first: template_first
          second: template_second
          third: template_third
        YAML
        dest = <<~YAML
          first: dest_first
          second: dest_second
          third: dest_third
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        # All values should be from template
        expect(yaml).to include("template_first")
        expect(yaml).to include("template_second")
        expect(yaml).to include("template_third")
        expect(yaml).not_to include("dest_first")
        expect(yaml).not_to include("dest_second")
        expect(yaml).not_to include("dest_third")
      end
    end

    context "with destination node that has nil signature" do
      it "keeps destination node without signature" do
        # Use a custom signature generator that returns nil for certain nodes
        custom_gen = ->(node) {
          if node.is_a?(Psych::Merge::MappingEntry) && node.key_name == "no_sig"
            nil
          else
            node # fall through to default
          end
        }

        template = <<~YAML
          key: template_value
        YAML
        dest = <<~YAML
          no_sig: dest_value
          key: dest_key
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template, signature_generator: custom_gen)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest, signature_generator: custom_gen)

        resolver = described_class.new(template_analysis, dest_analysis)
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        # Should keep the dest-only node even without signature
        expect(yaml).to include("no_sig")
        expect(yaml).to include("dest_value")
      end
    end

    context "when adding wrapper to result from destination" do
      it "uses destination analysis for line lookup" do
        template = <<~YAML
          - item1
        YAML
        dest = <<~YAML
          - dest_item1
          - dest_item2
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(template_analysis, dest_analysis)
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("dest_item1")
        expect(yaml).to include("dest_item2")
      end
    end

    context "when adding wrapper to result from template" do
      it "uses template analysis for line lookup with template preference" do
        # Both files have the same sequence structure but template has more items
        # With matching signature, template preference should pick template version
        template = <<~YAML
          items:
            - shared_item
            - template_item1
            - template_item2
        YAML
        dest = <<~YAML
          items:
            - shared_item
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        # With template preference and matching key, should use template version
        expect(yaml).to include("items")
      end
    end

    context "when template-only node has nil signature" do
      it "still adds the node but doesn't track signature" do
        custom_gen = ->(node) {
          if node.is_a?(Psych::Merge::MappingEntry) && node.key_name == "no_track"
            nil
          else
            node
          end
        }

        template = <<~YAML
          common: value
          no_track: template_only
        YAML
        dest = <<~YAML
          common: dest_value
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template, signature_generator: custom_gen)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest, signature_generator: custom_gen)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          add_template_only_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        # Should add the template-only node even without signature tracking
        expect(yaml).to include("no_track")
        expect(yaml).to include("template_only")
      end
    end

    context "with regular mapping nodes (not freeze blocks)" do
      it "processes non-freeze destination nodes through the else branch" do
        template = <<~YAML
          key1: template1
          key2: template2
        YAML
        dest = <<~YAML
          key1: dest1
          key2: dest2
          key3: dest_only
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(template_analysis, dest_analysis)
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        # All destination keys should be present
        expect(yaml).to include("key1")
        expect(yaml).to include("key2")
        expect(yaml).to include("key3")
        expect(yaml).to include("dest1")
        expect(yaml).to include("dest2")
        expect(yaml).to include("dest_only")
      end
    end

    describe "flow sequence handling" do
      it "does not duplicate entries with flow sequence values like github: [pboling]" do
        yaml = <<~YAML
          buy_me_a_coffee: pboling
          community_bridge:
          github: [pboling]
          issuehunt: pboling
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(yaml)
        dest_analysis = Psych::Merge::FileAnalysis.new(yaml)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        output = result.to_yaml

        expect(output.scan("github:").count).to eq(1),
          "Expected github: to appear once but found #{output.scan("github:").count} times:\n#{output}"
      end

      it "treats flow sequences atomically using template preference" do
        template = <<~YAML
          github: [new_user]
        YAML
        dest = <<~YAML
          github: [old_user]
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        output = result.to_yaml

        expect(output).to include("new_user")
        expect(output).not_to include("old_user")
        expect(output.scan("github:").count).to eq(1)
      end

      it "treats flow sequences atomically using destination preference" do
        template = <<~YAML
          github: [new_user]
        YAML
        dest = <<~YAML
          github: [old_user]
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :destination,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        output = result.to_yaml

        expect(output).to include("old_user")
        expect(output).not_to include("new_user")
        expect(output.scan("github:").count).to eq(1)
      end

      it "still recursively merges block sequences spanning multiple lines" do
        template = <<~YAML
          AllCops:
            Exclude:
              - vendor/**/*
              - tmp/**/*
        YAML
        dest = <<~YAML
          AllCops:
            Exclude:
              - vendor/**/*
              - node_modules/**/*
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :destination,
          add_template_only_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        output = result.to_yaml

        # Dest items preserved
        expect(output).to include("vendor/**/*")
        expect(output).to include("node_modules/**/*")
        # Template-only item added
        expect(output).to include("tmp/**/*")
      end
    end
  end
end

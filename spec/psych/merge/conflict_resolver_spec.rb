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
        expect(yaml.scan("Template comment").count).to eq(1)
        expect(yaml).to include("template_value")
      end

      it "preserves destination leading and inline comments when template content wins" do
        template = <<~YAML
          # Template comment
          key: template_value # template inline
        YAML
        dest = <<~YAML
          # Destination comment
          key: dest_value # destination inline
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

        expect(yaml).to include("# Destination comment")
        expect(yaml).to include("key: template_value # destination inline")
        expect(yaml).not_to include("# Template comment")
        expect(yaml).not_to include("template inline")
      end

      it "preserves blank-line-separated destination comment blocks for nested matched mapping entries" do
        template = <<~YAML
          parent:
            child: template_value
        YAML
        dest = <<~YAML
          parent:
            # Destination child docs
            # More child docs

            child: dest_value
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

        expect(yaml).to match(/parent:\n  # Destination child docs\n  # More child docs\n\n  child: template_value\n\z/)
      end
    end

    context "with destination preference and leading comments" do
      it "does not duplicate mapping-entry leading comments" do
        template = <<~YAML
          key: template_value
        YAML
        dest = <<~YAML
          # Destination comment
          key: dest_value
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(template_analysis, dest_analysis)
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("Destination comment")
        expect(yaml.scan("Destination comment").count).to eq(1)
        expect(yaml).to include("key: dest_value")
      end

      it "keeps destination footer comments at the true end after template-only additions" do
        template = <<~YAML
          key: template_value
          template_only: added
        YAML
        dest = <<~YAML
          key: dest_value

          # Destination footer
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          add_template_only_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("template_only: added")
        expect(yaml).to include("# Destination footer")
        expect(yaml.index("template_only: added")).to be < yaml.index("# Destination footer")
        expect(yaml.scan("Destination footer").count).to eq(1)
      end
    end

    context "with recursive merge and inline key comments" do
      it "replays the destination inline comment through the shared attachment path" do
        template = <<~YAML
          defaults:
            timeout: 30
            retries: 2
        YAML
        dest = <<~YAML
          defaults: # keep this note
            timeout: 15
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
        yaml = result.to_yaml

        expect(yaml).to include("defaults: # keep this note")
        expect(yaml.scan("keep this note").count).to eq(1)
        expect(yaml).to include("timeout: 15")
        expect(yaml).to include("retries: 2")
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

    context "with remove_template_missing_nodes and destination-only node comments" do
      it "preserves leading comments for removed destination nodes" do
        template = <<~YAML
          keep: template_value
        YAML
        dest = <<~YAML
          keep: dest_value

          # Removed node comment
          remove_me: old_value
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("keep: dest_value")
        expect(yaml).to include("# Removed node comment")
        expect(yaml).not_to include("remove_me: old_value")
      end

      it "promotes inline comments for removed destination nodes into standalone comments" do
        template = <<~YAML
          keep: template_value
        YAML
        dest = <<~YAML
          keep: dest_value
          remove_me: old_value # Removed node inline comment
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("keep: dest_value")
        expect(yaml).to include("# Removed node inline comment")
        expect(yaml).not_to include("remove_me: old_value")
      end

      it "preserves both leading and inline comments for removed destination nodes" do
        template = <<~YAML
          keep: template_value
        YAML
        dest = <<~YAML
          keep: dest_value

          # Removed node comment
          remove_me: old_value # Removed node inline comment
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("keep: dest_value")
        expect(yaml).to include("# Removed node comment")
        expect(yaml).to include("# Removed node inline comment")
        expect(yaml).not_to include("remove_me: old_value")
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

      it "preserves recursive sequence item leading and inline comments via shared attachments" do
        template = <<~YAML
          items:
            - shared
            # Template extra comment
            - template_extra # template inline
        YAML
        dest = <<~YAML
          items:
            # Destination shared comment
            - shared # keep this inline
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

        expect(output).to include("# Destination shared comment")
        expect(output.scan("Destination shared comment").count).to eq(1)
        expect(output).to include("- shared # keep this inline")
        expect(output.scan("keep this inline").count).to eq(1)
        expect(output).to include("# Template extra comment")
        expect(output).to include("- template_extra # template inline")
      end

      it "preserves leading comments for removed destination sequence items" do
        template = <<~YAML
          AllCops:
            Exclude:
              - keep_this/**/*
        YAML
        dest = <<~YAML
          AllCops:
            Exclude:
              - keep_this/**/*
              # Removed sequence item comment
              - remove_this/**/*
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :destination,
          recursive: true,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        output = result.to_yaml

        expect(output).to include("keep_this/**/*")
        expect(output).to include("# Removed sequence item comment")
        expect(output).not_to include("remove_this/**/*")
      end

      it "promotes inline comments for removed destination sequence items into standalone comments" do
        template = <<~YAML
          AllCops:
            Exclude:
              - keep_this/**/*
        YAML
        dest = <<~YAML
          AllCops:
            Exclude:
              - keep_this/**/*
              - remove_this/**/* # Removed sequence item inline comment
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :destination,
          recursive: true,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        output = result.to_yaml

        expect(output).to include("keep_this/**/*")
        expect(output).to include("# Removed sequence item inline comment")
        expect(output).not_to include("remove_this/**/*")
      end

      it "preserves both leading and inline comments for removed destination sequence items" do
        template = <<~YAML
          AllCops:
            Exclude:
              - keep_this/**/*
        YAML
        dest = <<~YAML
          AllCops:
            Exclude:
              - keep_this/**/*
              # Removed sequence item comment
              - remove_this/**/* # Removed sequence item inline comment
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :destination,
          recursive: true,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        output = result.to_yaml

        expect(output).to include("keep_this/**/*")
        expect(output).to include("# Removed sequence item comment")
        expect(output).to include("# Removed sequence item inline comment")
        expect(output).not_to include("remove_this/**/*")
      end
    end

    context "with comment variation matrix" do
      it "preserves deeper nested destination comment blocks when template content wins" do
        template = <<~YAML
          root:
            parent:
              child:
                grandchild: template_value
        YAML
        dest = <<~YAML
          root:
            parent:
              child:
                # Destination grandchild docs
                # More destination docs

                grandchild: dest_value
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

        expect(yaml).to match(/root:\n  parent:\n    child:\n      # Destination grandchild docs\n      # More destination docs\n\n      grandchild: template_value\n\z/)
      end

      it "preserves matched nested comments while promoting removed nested sibling comments" do
        template = <<~YAML
          settings:
            keep: template_value
        YAML
        dest = <<~YAML
          settings:
            # Keep docs
            keep: dest_value # keep inline

            # Remove docs
            remove_me: old_value # remove inline
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          recursive: true,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("# Keep docs")
        expect(yaml).to include("keep: template_value # keep inline")
        expect(yaml).to include("# Remove docs")
        expect(yaml).to include("# remove inline")
        expect(yaml).not_to include("remove_me: old_value")
      end

      it "handles commented flow and block hybrids in the same document" do
        template = <<~YAML
          funding:
            github: [template_user]
            ko_fi: pboling
          AllCops:
            Exclude:
              - vendor/**/*
              - tmp/**/*
        YAML
        dest = <<~YAML
          funding:
            # Funding docs
            github: [dest_user] # github note
            ko_fi: pboling
          AllCops:
            Exclude:
              # Destination exclude docs
              - vendor/**/* # keep vendor note
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          recursive: true,
          add_template_only_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("# Funding docs")
        expect(yaml).to include("github: [template_user] # github note")
        expect(yaml.scan("github:").count).to eq(1)
        expect(yaml).to include("# Destination exclude docs")
        expect(yaml).to include("- vendor/**/* # keep vendor note")
        expect(yaml).to include("- tmp/**/*")
      end

      it "preserves surviving sequence item comments while promoting removed sibling item comments" do
        template = <<~YAML
          items:
            - keep
        YAML
        dest = <<~YAML
          items:
            # Keep docs
            - keep # keep inline

            # Remove docs
            - remove # remove inline
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          recursive: true,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("# Keep docs")
        expect(yaml).to include("- keep # keep inline")
        expect(yaml).to include("# Remove docs")
        expect(yaml).to include("# remove inline")
        expect(yaml).not_to include("- remove # remove inline")
      end

      it "recursively matches sequence items that are mappings while removing destination-only siblings" do
        template = <<~YAML
          items:
            - name: keep
              value: template_value
            - name: added
              value: template_added
        YAML
        dest = <<~YAML
          items:
            # Keep item docs
            - name: keep
              value: dest_value # keep inline

            # Remove item docs
            - name: remove
              value: old_value # remove inline
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          recursive: true,
          add_template_only_nodes: true,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("# Keep item docs")
        expect(yaml).to include("value: template_value # keep inline")
        expect(yaml).to include("# Remove item docs")
        expect(yaml).to include("# remove inline")
        expect(yaml).to include("- name: added")
        expect(yaml).to include("value: template_added")
        expect(yaml).not_to include("- name: remove")
        expect(yaml.scan(/- name: keep/).size).to eq(1)
      end

      it "recursively matches outer sequence items that are nested sequences while removing destination-only siblings" do
        template = <<~YAML
          groups:
            # Keep group docs
            - - keep
              - template_inner
            - - added
              - template_added
        YAML
        dest = <<~YAML
          groups:
            # Keep group docs
            - - keep # keep inline
              - dest_inner

            # Remove group docs
            - - remove
              - dest_removed # remove inline
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          recursive: true,
          add_template_only_nodes: true,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml.scan(/# Keep group docs/).size).to eq(1)
        expect(yaml).to include("- - keep # keep inline")
        expect(yaml).to include("- template_inner")
        expect(yaml).to include("# Remove group docs")
        expect(yaml).to include("# remove inline")
        expect(yaml).to include("- - added")
        expect(yaml).to include("- template_added")
        expect(yaml).not_to include("- - remove")
      end

      it "preserves blank-line-separated nested mapping comments inside matched sequence items without spilling to siblings" do
        template = <<~YAML
          items:
            - name: keep
              config:
                keep: template_value
                add: template_added
            - name: untouched
              config:
                stable: template_stable
        YAML
        dest = <<~YAML
          items:
            - name: keep
              config:
                # Keep docs
                keep: dest_value # keep inline

                # Shared section docs
                # More shared docs

                # Remove docs
                remove: old_value # remove inline
            - name: untouched
              config:
                stable: dest_stable
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          recursive: true,
          add_template_only_nodes: true,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("# Keep docs")
        expect(yaml).to include("keep: template_value # keep inline")
        expect(yaml).to match(/# Shared section docs\n      # More shared docs\n\n      # Remove docs/)
        expect(yaml).to include("# remove inline")
        expect(yaml).to include("add: template_added")
        expect(yaml).to include("- name: untouched")
        expect(yaml).to include("stable: template_stable")
        expect(yaml.scan(/# Shared section docs/).size).to eq(1)
        expect(yaml).not_to include("remove: old_value")
      end

      it "preserves nested sequence comments inside matched sequence-item mappings without spilling to siblings" do
        template = <<~YAML
          items:
            - name: keep
              config:
                rules:
                  - keep_rule
                  - add_rule
            - name: untouched
              config:
                stable: template_stable
        YAML
        dest = <<~YAML
          items:
            - name: keep
              config:
                rules:
                  # Keep docs
                  - keep_rule # keep inline

                  # Shared section docs
                  # More shared docs

                  # Remove docs
                  - remove_rule # remove inline
            - name: untouched
              config:
                stable: dest_stable
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          recursive: true,
          add_template_only_nodes: true,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("# Keep docs")
        expect(yaml).to include("- keep_rule # keep inline")
        expect(yaml).to include("# Shared section docs")
        expect(yaml).to include("# More shared docs")
        expect(yaml).to include("# Remove docs")
        expect(yaml).to include("# remove inline")
        expect(yaml).to include("- add_rule")
        expect(yaml).to include("- name: untouched")
        expect(yaml).to include("stable: template_stable")
        expect(yaml.scan(/# Shared section docs/).size).to eq(1)
        expect(yaml).not_to include("- remove_rule")
        expect(yaml).to match(/# More shared docs\n\n        # Remove docs/)
      end

      it "preserves nested mapping-sequence comments inside matched sequence-item mappings without sibling spillover" do
        template = <<~YAML
          items:
            - name: keep
              config:
                rules:
                  - id: keep
                    value: template_value
                  - id: add
                    value: template_added
            - name: untouched
              config:
                stable: template_stable
        YAML
        dest = <<~YAML
          items:
            - name: keep
              config:
                rules:
                  # Keep rule docs
                  - id: keep
                    value: dest_value # keep inline

                  # Shared rule docs
                  # More shared rule docs

                  # Remove rule docs
                  - id: remove
                    value: old_value # remove inline
            - name: untouched
              config:
                stable: dest_stable
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          recursive: true,
          add_template_only_nodes: true,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        expect(yaml).to include("# Keep rule docs")
        expect(yaml).to include("- id: keep")
        expect(yaml).to include("value: template_value # keep inline")
        expect(yaml).to include("# Shared rule docs")
        expect(yaml).to include("# More shared rule docs")
        expect(yaml).to include("# Remove rule docs")
        expect(yaml).to include("# remove inline")
        expect(yaml).to include("- id: add")
        expect(yaml).to include("value: template_added")
        expect(yaml).to include("- name: untouched")
        expect(yaml).to include("stable: template_stable")
        expect(yaml.scan(/# Shared rule docs/).size).to eq(1)
        expect(yaml).not_to include("- id: remove")
        expect(yaml).to match(/# More shared rule docs\n\n        # Remove rule docs/)
      end

      it "keeps destination order for matched inner mapping items while appending template-only additions" do
        template = <<~YAML
          items:
            - name: keep
              config:
                rules:
                  - id: alpha
                    value: template_alpha
                  - id: beta
                    value: template_beta
                  - id: add
                    value: template_add
        YAML
        dest = <<~YAML
          items:
            - name: keep
              config:
                rules:
                  - id: beta
                    value: dest_beta # beta inline

                  # Removed rule docs
                  - id: remove
                    value: dest_remove # remove inline

                  - id: alpha
                    value: dest_alpha # alpha inline
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          recursive: true,
          add_template_only_nodes: true,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        beta_index = yaml.index("- id: beta")
        alpha_index = yaml.index("- id: alpha")
        add_index = yaml.index("- id: add")

        expect(beta_index).not_to be_nil
        expect(alpha_index).not_to be_nil
        expect(add_index).not_to be_nil
        expect(beta_index).to be < alpha_index
        expect(alpha_index).to be < add_index
        expect(yaml).to include("value: template_beta # beta inline")
        expect(yaml).to include("value: template_alpha # alpha inline")
        expect(yaml).to include("# Removed rule docs")
        expect(yaml).to include("# remove inline")
        expect(yaml.scan(/- id: alpha/).size).to eq(1)
        expect(yaml.scan(/- id: beta/).size).to eq(1)
        expect(yaml.scan(/- id: add/).size).to eq(1)
        expect(yaml).not_to include("- id: remove")
      end

      it "matches duplicate inner ids 1:1 using stable secondary discriminators" do
        template = <<~YAML
          items:
            - name: keep
              config:
                rules:
                  - id: alpha
                    scope: first
                    value: template_first
                  - id: alpha
                    scope: second
                    value: template_second
                  - id: alpha
                    scope: add
                    value: template_add
        YAML
        dest = <<~YAML
          items:
            - name: keep
              config:
                rules:
                  - id: alpha
                    scope: second
                    value: dest_second # second inline

                  # Removed duplicate docs
                  - id: alpha
                    scope: remove
                    value: dest_remove # remove inline

                  - id: alpha
                    scope: first
                    value: dest_first # first inline
        YAML

        template_analysis = Psych::Merge::FileAnalysis.new(template)
        dest_analysis = Psych::Merge::FileAnalysis.new(dest)

        resolver = described_class.new(
          template_analysis,
          dest_analysis,
          preference: :template,
          recursive: true,
          add_template_only_nodes: true,
          remove_template_missing_nodes: true,
        )
        result = Psych::Merge::MergeResult.new

        resolver.resolve(result)
        yaml = result.to_yaml

        second_index = yaml.index("scope: second")
        first_index = yaml.index("scope: first")
        add_index = yaml.index("scope: add")

        expect(second_index).not_to be_nil
        expect(first_index).not_to be_nil
        expect(add_index).not_to be_nil
        expect(second_index).to be < first_index
        expect(first_index).to be < add_index
        expect(yaml).to include("value: template_second # second inline")
        expect(yaml).to include("value: template_first # first inline")
        expect(yaml).to include("# Removed duplicate docs")
        expect(yaml).to include("# remove inline")
        expect(yaml.scan(/scope: first/).size).to eq(1)
        expect(yaml.scan(/scope: second/).size).to eq(1)
        expect(yaml.scan(/scope: add/).size).to eq(1)
        expect(yaml).not_to include("scope: remove")
      end
    end
  end
end

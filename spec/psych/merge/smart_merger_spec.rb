# frozen_string_literal: true

require "ast/merge/rspec/shared_examples"

RSpec.describe Psych::Merge::SmartMerger do
  describe "#initialize" do
    it "creates a merger with valid YAML" do
      template = "key: template_value"
      dest = "key: dest_value"

      merger = described_class.new(template, dest)

      expect(merger.valid?).to be(true)
      expect(merger.template_analysis).to be_a(Psych::Merge::FileAnalysis)
      expect(merger.dest_analysis).to be_a(Psych::Merge::FileAnalysis)
    end

    it "raises TemplateParseError for invalid template" do
      template = "key: value\n  bad: indent"
      dest = "key: value"

      expect {
        described_class.new(template, dest)
      }.to raise_error(Psych::Merge::TemplateParseError)
    end

    it "raises DestinationParseError for invalid destination" do
      template = "key: value"
      dest = "key: value\n  bad: indent"

      expect {
        described_class.new(template, dest)
      }.to raise_error(Psych::Merge::DestinationParseError)
    end

    it "accepts configuration options" do
      template = "key: value"
      dest = "key: value"

      merger = described_class.new(
        template,
        dest,
        preference: :template,
        add_template_only_nodes: true,
        freeze_token: "custom-token",
      )

      expect(merger.preference).to eq(:template)
      expect(merger.add_template_only_nodes).to be(true)
      expect(merger.freeze_token).to eq("custom-token")
    end
  end

  describe "#merge" do
    context "with destination preference (default)" do
      it "keeps destination value when keys match" do
        template = "key: template_value"
        dest = "key: dest_value"

        merger = described_class.new(template, dest)
        result = merger.merge

        expect(result).to include("dest_value")
        expect(result).not_to include("template_value")
      end

      it "keeps destination-only keys" do
        template = "common: value"
        dest = <<~YAML
          common: value
          dest_only: special
        YAML

        merger = described_class.new(template, dest)
        result = merger.merge

        expect(result).to include("dest_only")
        expect(result).to include("special")
      end

      it "does not add template-only keys by default" do
        template = <<~YAML
          common: value
          template_only: new
        YAML
        dest = "common: value"

        merger = described_class.new(template, dest)
        result = merger.merge

        expect(result).not_to include("template_only")
      end
    end

    context "with template preference" do
      it "keeps template value when keys match" do
        template = "key: template_value"
        dest = "key: dest_value"

        merger = described_class.new(
          template,
          dest,
          preference: :template,
        )
        result = merger.merge

        expect(result).to include("template_value")
        expect(result).not_to include("dest_value")
      end
    end

    context "with add_template_only_nodes enabled" do
      it "adds template-only keys" do
        template = <<~YAML
          common: value
          template_only: new_feature
        YAML
        dest = "common: value"

        merger = described_class.new(
          template,
          dest,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result).to include("template_only")
        expect(result).to include("new_feature")
      end

      it "does not duplicate identical non-scalar sequence items" do
        template = <<~YAML
          patterns:
            - path: "certs/**"
              strategy: raw_copy
        YAML
        dest = <<~YAML
          patterns:
            - path: "certs/**"
              strategy: raw_copy
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :destination,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result.scan('path: "certs/**"').size).to eq(1)
        expect(result.scan("strategy: raw_copy").size).to eq(1)
      end

      it "does not preserve a redundant duplicate destination mapping entry when template preference is used" do
        template = <<~YAML
          Layout/IndentationConsistency:
            Exclude: ['*.md']
        YAML
        dest = <<~YAML
          Layout/IndentationConsistency:
            Exclude: ['*.md']
            Exclude: ['*.md']
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result).to eq(template)
        expect(result.scan("Exclude: ['*.md']").size).to eq(1)
      end

      it "preserves a redundant duplicate destination mapping entry in skip mode" do
        template = <<~YAML
          Layout/IndentationConsistency:
            Exclude: ['*.md']
        YAML
        dest = <<~YAML
          Layout/IndentationConsistency:
            Exclude: ['*.md']
            Exclude: ['*.md']
        YAML

        result = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
          corruption_handling: :skip,
        ).merge

        expect(result.scan("Exclude: ['*.md']").size).to eq(2)
      end

      it "warns when preserving a redundant duplicate destination mapping entry in warn mode" do
        template = <<~YAML
          Layout/IndentationConsistency:
            Exclude: ['*.md']
        YAML
        dest = <<~YAML
          Layout/IndentationConsistency:
            Exclude: ['*.md']
            Exclude: ['*.md']
        YAML

        allow(Psych::Merge::DebugLogger).to receive(:debug_warning)

        result = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
          corruption_handling: :warn,
        ).merge

        expect(Psych::Merge::DebugLogger).to have_received(:debug_warning).with(
          /Suspected corruption \(duplicate_destination_mapping_entry\)/,
          hash_including(owner_type: "MappingEntry"),
        )
        expect(result.scan("Exclude: ['*.md']").size).to eq(2)
      end

      it "raises on a redundant duplicate destination mapping entry in error mode" do
        template = <<~YAML
          Layout/IndentationConsistency:
            Exclude: ['*.md']
        YAML
        dest = <<~YAML
          Layout/IndentationConsistency:
            Exclude: ['*.md']
            Exclude: ['*.md']
        YAML

        expect {
          described_class.new(
            template,
            dest,
            preference: :template,
            add_template_only_nodes: true,
            corruption_handling: :error,
          ).merge
        }.to raise_error(Psych::Merge::CorruptionDetectedError, /duplicate_destination_mapping_entry/)
      end

      it "does not preserve redundant duplicate destination sequence items when template preference is used" do
        template = <<~YAML
          workflow:
            rules:
              - if: '$CI_MERGE_REQUEST_IID'
              - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
        YAML
        dest = <<~YAML
          workflow:
            rules:
              - if: '$CI_MERGE_REQUEST_IID'
              - if: '$CI_MERGE_REQUEST_IID'
              - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result).to eq(template)
        expect(result.scan("- if: '$CI_MERGE_REQUEST_IID'").size).to eq(1)
      end

      it "preserves redundant duplicate destination sequence items in skip mode" do
        template = <<~YAML
          workflow:
            rules:
              - if: '$CI_MERGE_REQUEST_IID'
              - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
        YAML
        dest = <<~YAML
          workflow:
            rules:
              - if: '$CI_MERGE_REQUEST_IID'
              - if: '$CI_MERGE_REQUEST_IID'
              - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
        YAML

        result = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
          corruption_handling: :skip,
        ).merge

        expect(result.scan("- if: '$CI_MERGE_REQUEST_IID'").size).to eq(2)
      end

      it "warns when preserving redundant duplicate destination sequence items in warn mode" do
        template = <<~YAML
          workflow:
            rules:
              - if: '$CI_MERGE_REQUEST_IID'
              - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
        YAML
        dest = <<~YAML
          workflow:
            rules:
              - if: '$CI_MERGE_REQUEST_IID'
              - if: '$CI_MERGE_REQUEST_IID'
              - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
        YAML

        allow(Psych::Merge::DebugLogger).to receive(:debug_warning)

        result = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
          corruption_handling: :warn,
        ).merge

        expect(Psych::Merge::DebugLogger).to have_received(:debug_warning).with(
          /Suspected corruption \(duplicate_destination_sequence_item\)/,
          hash_including(owner_type: "NodeWrapper"),
        )
        expect(result.scan("- if: '$CI_MERGE_REQUEST_IID'").size).to eq(2)
      end

      it "raises on redundant duplicate destination sequence items in error mode" do
        template = <<~YAML
          workflow:
            rules:
              - if: '$CI_MERGE_REQUEST_IID'
              - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
        YAML
        dest = <<~YAML
          workflow:
            rules:
              - if: '$CI_MERGE_REQUEST_IID'
              - if: '$CI_MERGE_REQUEST_IID'
              - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
        YAML

        expect {
          described_class.new(
            template,
            dest,
            preference: :template,
            add_template_only_nodes: true,
            corruption_handling: :error,
          ).merge
        }.to raise_error(Psych::Merge::CorruptionDetectedError, /duplicate_destination_sequence_item/)
      end

      it "does not preserve redundant duplicate destination entries when destination preference is used" do
        template = <<~YAML
          patterns:
            - path: "certs/**"
              strategy: raw_copy

          files: {}
        YAML
        dest = <<~YAML
          patterns:
            - path: "certs/**"
              strategy: raw_copy
            - path: "certs/**"
              strategy: raw_copy

          files: {}
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :destination,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result).to eq(template)
        expect(result.scan('path: "certs/**"').size).to eq(1)
      end

      it "does not preserve duplicated destination comment blocks for matched keys" do
        template = <<~YAML
          patterns:
            - path: "certs/**"
              strategy: raw_copy

          # Per-file configuration (nested directory structure)
          # Only files that need overrides belong here. Everything else defaults to merge.
          files: {}

          # Self-test / templating CI threshold.
          # Set to a number from 0 to 100 to fail `rake kettle:jem:selftest` once
          min_divergence_threshold:
        YAML
        dest = <<~YAML
          patterns:
            - path: "certs/**"
              strategy: raw_copy

          # Per-file configuration (nested directory structure)
          # Only files that need overrides belong here. Everything else defaults to merge.
          # Per-file configuration (nested directory structure)
          # Only files that need overrides belong here. Everything else defaults to merge.
          files: {}

          # Self-test / templating CI threshold.
          # Set to a number from 0 to 100 to fail `rake kettle:jem:selftest` once
          # Self-test / templating CI threshold.
          # Set to a number from 0 to 100 to fail `rake kettle:jem:selftest` once
          min_divergence_threshold:
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :destination,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result.scan("# Per-file configuration (nested directory structure)").size).to eq(1)
        expect(result.scan("# Self-test / templating CI threshold.").size).to eq(1)
      end

      it "does not duplicate a trailing commented mapping section after an identical sequence item" do
        template = <<~YAML
          patterns:
            - path: "certs/**"
              strategy: raw_copy

          # Per-file configuration (nested directory structure)
          # Only files that need overrides belong here. Everything else defaults to merge.
          files: {}

          # To override specific files, add entries like:
          #
          # files:
          #   README.md:
          #     strategy: accept_template
        YAML
        dest = <<~YAML
          patterns:
            - path: "certs/**"
              strategy: raw_copy

          # Per-file configuration (nested directory structure)
          # Only files that need overrides belong here. Everything else defaults to merge.
          files: {}
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :destination,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result.scan('path: "certs/**"').size).to eq(1)
        expect(result.scan("# Per-file configuration (nested directory structure)").size).to eq(1)
      end

      it "matches sequence mapping items by unique shared scalar observations instead of hard-coded key names" do
        template = <<~YAML
          runtimes:
            - engine: ruby
              channel: current
              command: bundle exec rspec

            - engine: truffleruby
              channel: current
              command: bundle exec rspec
        YAML
        dest = <<~YAML
          runtimes:
            - engine: ruby
              channel: current
              command: bin/spec # destination inline
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result.scan("engine: ruby").size).to eq(1)
        expect(result.scan("engine: truffleruby").size).to eq(1)
        expect(result).to include("command: bundle exec rspec # destination inline")
      end

      it "preserves blank lines between recursively merged nested sequence items" do
        template = <<~YAML
          jobs:
            coverage:
              steps:
                - name: Checkout
                  uses: actions/checkout@v6

                - name: Setup Ruby
                  uses: ruby/setup-ruby@v1

                - name: Run tests
                  run: bundle exec rspec
        YAML

        merger = described_class.new(
          template,
          template,
          preference: :template,
          recursive: true,
          add_template_only_nodes: true,
        )

        expect(merger.merge).to eq(template)
      end

      it "preserves blank lines before comment-led recursively merged nested sequence items" do
        template = <<~YAML
          jobs:
            coverage:
              steps:
                - name: Attempt 1
                  run: bundle exec appraisal install
                  continue-on-error: true

                # Retry if the first install failed.
                - name: Attempt 2
                  if: ${{ failure() }}
                  run: bundle exec appraisal install
        YAML

        merger = described_class.new(
          template,
          template,
          preference: :template,
          recursive: true,
          add_template_only_nodes: true,
        )

        expect(merger.merge).to eq(template)
      end

      it "treats semantically identical mapping items as the same item even when key order differs" do
        template = <<~YAML
          plugins:
            - engine: ruby
              channel: current
              command: bundle exec rspec
        YAML
        dest = <<~YAML
          plugins:
            - command: bundle exec rspec
              channel: current
              engine: ruby
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result.scan("engine: ruby").size).to eq(1)
        expect(result.scan("channel: current").size).to eq(1)
        expect(result.scan("command: bundle exec rspec").size).to eq(1)
      end

      it "matches citation-style author entries by shared stable observations when mutable fields change" do
        template = <<~YAML
          authors:
            - given-names: "Peter H."
              family-names: "Boling"
              email: "floss@galtzo.com"
              affiliation: "galtzo.com"
              orcid: 'https://orcid.org/0009-0008-8519-441X'
        YAML
        dest = <<~YAML
          authors:
            - given-names: Peter Hurn
              family-names: Boling
              email: floss@galtzo.com
              affiliation: galtzo.com
              orcid: 'https://orcid.org/0009-0008-8519-441X'
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result.scan("given-names:").size).to eq(1)
        expect(result).to include('given-names: "Peter H."')
        expect(result).to include('email: "floss@galtzo.com"')
        expect(result).not_to include("Peter Hurn")
      end

      it "matches workflow matrix items without treating ruby as a globally special key" do
        template = <<~YAML
          matrix:
            include:
              # Ruby 3.4
              - ruby: ruby
                appraisal: current
                exec_cmd: rake test
                gemfile: Appraisal.root
                rubygems: latest
                bundler: latest

              # TruffleRuby current
              - ruby: truffleruby
                appraisal: current
                exec_cmd: rake test
                gemfile: Appraisal.root
                rubygems: default
                bundler: default
        YAML
        dest = <<~YAML
          matrix:
            include:
              # Ruby 3.4
              - ruby: ruby
                appraisal: current
                exec_cmd: rake test
                gemfile: Appraisal.root
                rubygems: latest
                bundler: latest
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result.scan(/- ruby: ruby$/).size).to eq(1)
        expect(result.scan(/- ruby: truffleruby$/).size).to eq(1)
      end

      it "does not duplicate a later sibling comment block when inserting template-only sequence items" do
        template = <<~YAML
          matrix:
            include:
              # Ruby 3.4
              - ruby: ruby
                appraisal: current

              # TruffleRuby current
              - ruby: truffleruby
                appraisal: current

              # JRuby current
              - ruby: jruby
                appraisal: current
        YAML
        dest = <<~YAML
          matrix:
            include:
              # Ruby 3.4
              - ruby: ruby
                appraisal: current
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :template,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result.scan("# TruffleRuby current").size).to eq(1)
        expect(result.scan("# JRuby current").size).to eq(1)
        expect(result.scan(/- ruby: truffleruby$/).size).to eq(1)
        expect(result.scan(/- ruby: jruby$/).size).to eq(1)
      end
    end

    context "with comments" do
      it "preserves comments from destination" do
        template = "key: value"
        dest = <<~YAML
          # Important comment
          key: value
        YAML

        merger = described_class.new(template, dest)
        result = merger.merge

        expect(result).to include("Important comment")
      end

      it "preserves destination comments when template preference wins for a matched node" do
        template = <<~YAML
          # Template comment
          key: template_value # template inline
        YAML
        dest = <<~YAML
          # Destination comment
          key: dest_value # destination inline
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :template,
        )
        result = merger.merge

        expect(result).to include("# Destination comment")
        expect(result).to include("key: template_value # destination inline")
        expect(result).not_to include("# Template comment")
        expect(result).not_to include("template inline")
      end

      it "collapses a destination-only leading gap when template preference attaches the matched docs" do
        template = <<~YAML
          keep: 1
          # floating note
          commented: 1
        YAML
        dest = <<~YAML
          keep: 1

          # floating note
          commented: old
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :template,
        )
        result = merger.merge

        expect(result).to eq(template)
      end

      it "preserves blank-line-separated destination comment blocks for nested matched mapping entries when template wins" do
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

        merger = described_class.new(
          template,
          dest,
          preference: :template,
        )
        result = merger.merge

        expect(result).to match(/parent:\n  # Destination child docs\n  # More child docs\n\n  child: template_value\n\z/)
      end

      it "preserves blank-line-separated destination comment blocks for nested matched sequence items" do
        template = <<~YAML
          parent:
            items:
              - template_value
        YAML
        dest = <<~YAML
          parent:
            items:
              # Destination item docs
              # More item docs

              - dest_value
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :template,
        )
        result = merger.merge

        expect(result).to match(/items:\n    # Destination item docs\n    # More item docs\n\n    - dest_value\n/)
      end

      it "preserves comment-only destination headers before template-only additions" do
        template = <<~YAML
          key: template_value
        YAML
        dest = <<~YAML
          # Destination header
          # More docs
        YAML

        merger = described_class.new(
          template,
          dest,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result).to include("# Destination header")
        expect(result).to include("# More docs")
        expect(result).to include("key: template_value")
        expect(result.index("# Destination header")).to be < result.index("key: template_value")
      end

      it "preserves a blank line after a comment-only destination header before template-only additions" do
        template = <<~YAML
          key: template_value
        YAML
        dest = <<~YAML
          # Destination header
          # More docs

        YAML

        merger = described_class.new(
          template,
          dest,
          add_template_only_nodes: true,
        )
        result = merger.merge

      expect(result).to match(/# More docs\n\nkey: template_value\n\z/)
    end

    it "collapses duplicated template-owned preamble prefixes in heal mode" do
      template = <<~YAML
        # Shared header

        key: template_value
      YAML
      dest = <<~YAML
        # Shared header
        # Shared header
        # Destination header
        key: dest_value
      YAML

      result = described_class.new(
        template,
        dest,
        add_template_only_nodes: true,
      ).merge

      expect(result.lines.grep("# Shared header\n").size).to eq(0)
      expect(result.lines.grep("# Destination header\n").size).to eq(1)
      expect(result).to include("key: dest_value")
    end

    it "preserves duplicated template-owned preamble prefixes in skip mode" do
      template = <<~YAML
        # Shared header

        key: template_value
      YAML
      dest = <<~YAML
        # Shared header
        # Shared header
        # Destination header
        key: dest_value
      YAML

      result = described_class.new(
        template,
        dest,
        add_template_only_nodes: true,
        corruption_handling: :skip,
      ).merge

      expect(result.lines.grep("# Shared header\n").size).to eq(2)
      expect(result.lines.grep("# Destination header\n").size).to eq(1)
    end

    it "warns when preserving duplicated template-owned preamble prefixes in warn mode" do
      template = <<~YAML
        # Shared header

        key: template_value
      YAML
      dest = <<~YAML
        # Shared header
        # Shared header
        # Destination header
        key: dest_value
      YAML

      allow(Psych::Merge::DebugLogger).to receive(:debug_warning)

      result = described_class.new(
        template,
        dest,
        add_template_only_nodes: true,
        corruption_handling: :warn,
      ).merge

      expect(Psych::Merge::DebugLogger).to have_received(:debug_warning).with(
        /Suspected corruption \(duplicate_template_preamble_prefix\)/,
        hash_including(repeated_nodes: 2, remaining_nodes: 1),
      )
      expect(result.lines.grep("# Shared header\n").size).to eq(2)
    end

    it "raises on duplicated template-owned preamble prefixes in error mode" do
      template = <<~YAML
        # Shared header

        key: template_value
      YAML
      dest = <<~YAML
        # Shared header
        # Shared header
        # Destination header
        key: dest_value
      YAML

      expect {
        described_class.new(
          template,
          dest,
          add_template_only_nodes: true,
          corruption_handling: :error,
        ).merge
      }.to raise_error(Psych::Merge::CorruptionDetectedError, /duplicate_template_preamble_prefix/)
    end

    it "preserves section-leading comments for recursively merged mappings" do
        template = <<~YAML
          # Header comment
          defaults:
            freeze_token: template-token

          # Token section comment
          tokens:
            author:
              name: "{KJ|AUTHOR:NAME}"

          # Patterns section comment
          patterns:
            - path: "certs/**"
              strategy: raw_copy

          # Files section comment
          files: {}
        YAML
        dest = <<~YAML
          # Header comment
          defaults:
            freeze_token: destination-token

          # Token section comment
          tokens:
            author:
              name: "Custom Author"

          # Patterns section comment
          patterns:
            - path: "certs/**"
              strategy: raw_copy

          # Files section comment
          files: {}
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :destination,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result).to include("# Header comment")
        expect(result).to include("# Token section comment")
        expect(result).to include("# Patterns section comment")
        expect(result).to include("# Files section comment")
        expect(result.scan("# Files section comment").size).to eq(1)
        expect(result.scan('path: "certs/**"').size).to eq(1)
        expect(result).to include("freeze_token: destination-token")
        expect(result).to include('name: "Custom Author"')
      end

      it "preserves kettle-jem style section spacing and trailing example comments" do
        template = <<~YAML
          # kettle-jem configuration file
          #
          # Header docs

          # Default merge options
          defaults:
            preference: "template"
            add_template_only_nodes: true
            freeze_token: "kettle-jem"

          # Token replacement values.
          #
          # General rules:
          tokens:
            forge:
              gh_user: ""        # GitHub username only, no @, no URL. Used for GitHub Sponsors and profile links. ENV: KJ_GH_USER
              gl_user: ""        # GitLab username only, no @, no URL. Used for profile links. ENV: KJ_GL_USER

            author:
              name: "{KJ|AUTHOR:NAME}"                 # Full display name. Example: Peter H. Boling. ENV: KJ_AUTHOR_NAME. Auto-seeded from gemspec authors.first
              given_names: "{KJ|AUTHOR:GIVEN_NAMES}"   # Given/personal names only. Example: Peter H. ENV: KJ_AUTHOR_GIVEN_NAMES. Auto-seeded when AUTHOR:NAME can be split

          # Glob patterns evaluated in order (first match wins)
          patterns:
            - path: "certs/**"
              strategy: raw_copy

          # Per-file configuration (nested directory structure)
          # Only files that need overrides belong here. Everything else defaults to merge.
          files: {}

          # To override specific files, add entries like:
          #
          # files:
          #   README.md:
          #     strategy: accept_template
        YAML
        dest = <<~YAML
          # kettle-jem configuration file
          #
          # Header docs

          # Default merge options
          defaults:
            preference: "template"
            add_template_only_nodes: true
            freeze_token: "kettle-jem"

          # Token replacement values.
          #
          # General rules:
          tokens:
            forge:
              gh_user: ""        # GitHub username only, no @, no URL. Used for GitHub Sponsors and profile links. ENV: KJ_GH_USER
              gl_user: ""        # GitLab username only, no @, no URL. Used for profile links. ENV: KJ_GL_USER

            author:
              name: "Peter H. Boling"                 # Full display name. Example: Peter H. Boling. ENV: KJ_AUTHOR_NAME. Auto-seeded from gemspec authors.first
              given_names: "Peter H."                 # Given/personal names only. Example: Peter H. ENV: KJ_AUTHOR_GIVEN_NAMES. Auto-seeded when AUTHOR:NAME can be split

          # Glob patterns evaluated in order (first match wins)
          patterns:
            - path: "certs/**"
              strategy: raw_copy

          # Per-file configuration (nested directory structure)
          # Only files that need overrides belong here. Everything else defaults to merge.
          files: {}

          # To override specific files, add entries like:
          #
          # files:
          #   README.md:
          #     strategy: accept_template
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :destination,
          add_template_only_nodes: true,
          freeze_token: "kettle-jem",
        )

        expect(merger.merge).to eq(dest)
      end

      it "does not duplicate a commented section that follows a sequence in kettle-jem config merges" do
        template = <<~YAML
          # Default merge options
          defaults:
            preference: "template"
            add_template_only_nodes: true
            freeze_token: "kettle-jem"

          # Token replacement values.
          #
          # General rules:
          tokens:
            forge:
              gh_user: ""

          # Glob patterns evaluated in order (first match wins)
          patterns:
            - path: "certs/**"
              strategy: raw_copy

          # Per-file configuration (nested directory structure)
          # Only files that need overrides belong here. Everything else defaults to merge.
          files:
            ".git-hooks":
              commit-msg:
                strategy: accept_template
                file_type: ruby
        YAML
        dest = <<~YAML
          # Default merge options
          defaults:
            preference: "template"
            add_template_only_nodes: true
            freeze_token: "kettle-jem"

          # Token replacement values.
          #
          # General rules:
          #   - Empty strings are treated as unset.
          #   - Use the bare identifier/slug/handle expected by the inline comment.
          #   - Do NOT paste full URLs unless the comment explicitly says to.
          #
          # Tip:
          #   The author fields in a newly created destination config are normally seeded
          #   from the gemspec via safe derivation. After that, destination values win.
          tokens:
            forge:
              gh_user: "pboling"

          # Glob patterns evaluated in order (first match wins)
          patterns:
            - path: "certs/**"
              strategy: raw_copy

          # Per-file configuration (nested directory structure)
          # Only files that need overrides belong here. Everything else defaults to merge.
          files:
            ".git-hooks":
              commit-msg:
                strategy: accept_template
                file_type: ruby
        YAML

        merger = described_class.new(
          template,
          dest,
          preference: :destination,
          add_template_only_nodes: true,
        )
        result = merger.merge

        expect(result.scan("# Glob patterns evaluated in order (first match wins)").size).to eq(1)
        expect(result.scan("# Per-file configuration (nested directory structure)").size).to eq(1)
        expect(result.scan('path: "certs/**"').size).to eq(1)
      end
    end
  end

  describe "#merge_with_debug" do
    let(:runtime_debug_merger) { described_class.new("key: template_value\n", "key: dest_value\n") }

    it_behaves_like "Ast::Merge::RuntimeDebugContract"

    it "returns detailed merge information" do
      template = "key: template_value"
      dest = "key: dest_value"

      merger = described_class.new(template, dest)
      debug_result = merger.merge_with_debug

      expect(debug_result).to have_key(:content)
      expect(debug_result).to have_key(:statistics)
      expect(debug_result).to have_key(:decisions)
      expect(debug_result).to have_key(:template_analysis)
      expect(debug_result).to have_key(:dest_analysis)
      expect(debug_result).to have_key(:debug)
      expect(debug_result).to have_key(:runtime)
      expect(debug_result.dig(:debug, :corruption_handling)).to eq(:heal)
    end

    it "includes statistics about the merge" do
      template = <<~YAML
        key1: value1
        key2: value2
      YAML
      dest = <<~YAML
        key1: dest_value1
        key3: value3
      YAML

      merger = described_class.new(template, dest)
      debug_result = merger.merge_with_debug

      expect(debug_result[:statistics][:total_decisions]).to be > 0
    end

    it "records a runtime session for the root YAML document" do
      merger = described_class.new("key: template_value\n", "key: dest_value\n")
      debug_result = merger.merge_with_debug

      expect(merger.runtime_session).not_to be_nil
      expect(debug_result.dig(:runtime, :summary, :operation_count)).to eq(1)
      expect(debug_result.dig(:runtime, :operation_trees, 0, :surface, :surface_kind)).to eq(:yaml_document)
      expect(debug_result.dig(:runtime, :operation_trees, 0, :delegate_name)).to eq("psych-yaml")
    end
  end

  describe "#valid?" do
    it "returns true when both files are valid" do
      merger = described_class.new("key: value", "key: value")
      expect(merger.valid?).to be(true)
    end
  end

  describe "complex scenarios" do
    it "handles nested structures" do
      template = <<~YAML
        database:
          host: localhost
          port: 5432
        cache:
          enabled: true
      YAML
      dest = <<~YAML
        database:
          host: production.example.com
          port: 5432
        cache:
          enabled: false
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("production.example.com")
      expect(result).to include("enabled: false")
    end

    it "handles sequences" do
      template = <<~YAML
        items:
          - one
          - two
      YAML
      dest = <<~YAML
        items:
          - alpha
          - beta
          - gamma
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("alpha")
      expect(result).to include("gamma")
    end

    it "handles empty files" do
      template = ""
      dest = "key: value"

      # Empty template should parse but have no nodes
      expect {
        described_class.new(template, dest)
      }.not_to raise_error
    end

    it "handles mixed content" do
      template = <<~YAML
        # Header comment
        version: "1.0"

        settings:
          debug: false
          log_level: info

        # Footer
      YAML
      dest = <<~YAML
        # Custom header
        version: "2.0"

        settings:
          debug: true
          log_level: debug
          custom_setting: enabled

        # Custom footer
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      # Should keep destination values
      expect(result).to include('version: "2.0"')
      expect(result).to include("debug: true")
      expect(result).to include("custom_setting")
    end
  end

  describe "#errors" do
    it "returns empty array for valid files" do
      merger = described_class.new("key: value", "key: value")
      expect(merger.errors).to be_empty
    end
  end

  describe "edge cases" do
    it "handles YAML with special characters in values" do
      template = <<~YAML
        url: "https://example.com?param=value&other=test"
        regex: "^[a-z]+$"
      YAML
      dest = <<~YAML
        url: "https://custom.com?param=custom"
        regex: "^[A-Z]+$"
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("custom.com")
    end

    it "handles multiline strings" do
      template = <<~YAML
        description: |
          This is a
          multiline string
      YAML
      dest = <<~YAML
        description: |
          Custom description
          with multiple lines
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("Custom description")
    end

    it "handles YAML with null values" do
      template = <<~YAML
        present: value
        absent: ~
      YAML
      dest = <<~YAML
        present: custom
        absent: ~
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("custom")
    end

    it "handles YAML with boolean values" do
      template = <<~YAML
        enabled: true
        disabled: false
      YAML
      dest = <<~YAML
        enabled: false
        disabled: true
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("enabled: false")
      expect(result).to include("disabled: true")
    end

    it "handles YAML with numeric values" do
      template = <<~YAML
        count: 100
        ratio: 0.5
      YAML
      dest = <<~YAML
        count: 200
        ratio: 0.75
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("count: 200")
      expect(result).to include("ratio: 0.75")
    end

    it "handles deeply nested freeze blocks" do
      template = <<~YAML
        level1:
          level2:
            value: template
      YAML
      dest = <<~YAML
        level1:
          # psych-merge:freeze
          level2:
            value: frozen
          # psych-merge:unfreeze
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      expect(result).to include("psych-merge:freeze")
    end
  end

  describe "custom signature generator" do
    it "uses custom signature generator" do
      custom_generator = ->(node) {
        if node.respond_to?(:key_name) && node.key_name == "special"
          [:special, "custom_sig"]
        else
          node  # Fall through to default
        end
      }

      template = <<~YAML
        normal: template_value
        special: template_special
      YAML
      dest = <<~YAML
        normal: dest_value
        special: dest_special
      YAML

      merger = described_class.new(
        template,
        dest,
        signature_generator: custom_generator,
      )
      result = merger.merge

      expect(result).to include("dest_value")
    end
  end

  describe "regression tests" do
    # Regression test for bug where destination-only keys with nested mappings
    # would cause the key to be emitted twice due to overlapping line ranges.
    # The bug was in NodeWrapper where end_line was calculated as node.end_line + 1,
    # but Psych's end_line is already exclusive, so this caused off-by-one errors.
    it "does not duplicate keys when destination adds a new nested mapping" do
      template = <<~YAML
        name: my-project
        version: 1.0.0
        database:
          host: localhost
          port: 5432
      YAML

      dest = <<~YAML
        name: my-project
        version: 1.0.0
        database:
          host: localhost
          port: 5432
        cache:
          enabled: true
          ttl: 3600
      YAML

      merger = described_class.new(template, dest)
      result = merger.merge

      # The key "cache" should appear exactly once
      expect(result.scan(/^cache:/).length).to eq(1),
        "Expected 'cache:' to appear once but got: #{result.inspect}"

      # Verify the full structure is correct
      expect(result).to include("cache:")
      expect(result).to include("enabled: true")
      expect(result).to include("ttl: 3600")
    end

    it "merge is idempotent when destination adds nested mappings" do
      template = <<~YAML
        name: my-project
        database:
          host: localhost
      YAML

      dest = <<~YAML
        name: my-project
        database:
          host: localhost
        cache:
          enabled: true
      YAML

      merger1 = described_class.new(template, dest)
      result1 = merger1.merge

      # Merge again using the result as both template and destination
      merger2 = described_class.new(result1, result1)
      result2 = merger2.merge

      expect(result2).to eq(result1),
        "Merge should be idempotent.\nFirst: #{result1.inspect}\nSecond: #{result2.inspect}"
    end
  end

  describe "recursive merge" do
    context "with recursive: true (default)" do
      it "merges nested mapping entries recursively" do
        template = <<~YAML
          AllCops:
            Exclude:
              - examples/**/*
            NewCops: enable
        YAML

        dest = <<~YAML
          AllCops:
            Exclude:
              - tmp/**/*
            TargetRubyVersion: 3.2
        YAML

        merger = described_class.new(
          template,
          dest,
          recursive: true,
          add_template_only_nodes: true,
        )
        result = merger.merge

        # Should keep destination's TargetRubyVersion
        expect(result).to include("TargetRubyVersion: 3.2")
        # Should add template's NewCops
        expect(result).to include("NewCops: enable")
        # Should have AllCops appear once
        expect(result.scan(/^AllCops:/).length).to eq(1)
      end

      it "merges sequence items with union semantics when add_template_only_nodes is true" do
        template = <<~YAML
          AllCops:
            Exclude:
              - examples/**/*
              - vendor/**/*
        YAML

        dest = <<~YAML
          AllCops:
            Exclude:
              - tmp/**/*
              - coverage/**/*
        YAML

        merger = described_class.new(
          template,
          dest,
          recursive: true,
          add_template_only_nodes: true,
        )
        result = merger.merge

        # Should have all items from both (union)
        expect(result).to include("tmp/**/*")
        expect(result).to include("coverage/**/*")
        expect(result).to include("examples/**/*")
        expect(result).to include("vendor/**/*")
      end

      it "keeps only destination sequence items when add_template_only_nodes is false" do
        template = <<~YAML
          AllCops:
            Exclude:
              - examples/**/*
              - vendor/**/*
        YAML

        dest = <<~YAML
          AllCops:
            Exclude:
              - tmp/**/*
              - coverage/**/*
        YAML

        merger = described_class.new(
          template,
          dest,
          recursive: true,
          add_template_only_nodes: false,
        )
        result = merger.merge

        # Should have only destination items
        expect(result).to include("tmp/**/*")
        expect(result).to include("coverage/**/*")
        expect(result).not_to include("examples/**/*")
        expect(result).not_to include("vendor/**/*")
      end
    end

    context "with recursive: false" do
      it "replaces entire nested structure based on preference" do
        template = <<~YAML
          AllCops:
            NewCops: enable
        YAML

        dest = <<~YAML
          AllCops:
            TargetRubyVersion: 3.2
        YAML

        merger = described_class.new(
          template,
          dest,
          recursive: false,
          preference: :destination,
        )
        result = merger.merge

        # With recursive: false and preference: destination,
        # the entire AllCops block comes from destination
        expect(result).to include("TargetRubyVersion: 3.2")
        expect(result).not_to include("NewCops")
      end
    end

    context "with recursive: Integer (depth limit)" do
      it "raises ArgumentError for recursive: 0" do
        expect {
          described_class.new("key: value", "key: value", recursive: 0)
        }.to raise_error(ArgumentError, /recursive: 0 is invalid/)
      end

      it "accepts positive integers for depth limit" do
        merger = described_class.new("key: value", "key: value", recursive: 2)
        expect(merger.recursive).to eq(2)
      end
    end
  end

  describe "remove_template_missing_nodes" do
    it "removes destination-only nodes when enabled" do
      template = <<~YAML
        keep_me: value
      YAML

      dest = <<~YAML
        keep_me: dest_value
        remove_me: should_be_gone
      YAML

      merger = described_class.new(
        template,
        dest,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to include("keep_me")
      expect(result).not_to include("remove_me")
      expect(result).not_to include("should_be_gone")
    end

    it "preserves leading comments for removed destination-only nodes" do
      template = <<~YAML
        keep_me: value
      YAML

      dest = <<~YAML
        keep_me: dest_value

        # Removed node comment
        remove_me: should_be_gone
      YAML

      merger = described_class.new(
        template,
        dest,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to include("keep_me: dest_value")
      expect(result).to include("# Removed node comment")
      expect(result).not_to include("remove_me: should_be_gone")
    end

    it "promotes inline comments for removed destination-only nodes into standalone comments" do
      template = <<~YAML
        keep_me: value
      YAML

      dest = <<~YAML
        keep_me: dest_value
        remove_me: should_be_gone # Removed node inline comment
      YAML

      merger = described_class.new(
        template,
        dest,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to include("keep_me: dest_value")
      expect(result).to include("# Removed node inline comment")
      expect(result).not_to include("remove_me: should_be_gone")
    end

    it "preserves both leading and inline comments for removed destination-only nodes" do
      template = <<~YAML
        keep_me: value
      YAML

      dest = <<~YAML
        keep_me: dest_value

        # Removed node comment
        remove_me: should_be_gone # Removed node inline comment
      YAML

      merger = described_class.new(
        template,
        dest,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to include("keep_me: dest_value")
      expect(result).to include("# Removed node comment")
      expect(result).to include("# Removed node inline comment")
      expect(result).not_to include("remove_me: should_be_gone")
    end

    it "preserves separator blank lines around promoted removed-node comments" do
      template = <<~YAML
        keep_me: value
        tail: keep
      YAML

      dest = <<~YAML
        keep_me: dest_value

        # Removed node comment
        remove_me: should_be_gone # Removed node inline comment

        # Trailing note

        tail: keep
      YAML

      merger = described_class.new(
        template,
        dest,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to eq(<<~YAML)
        keep_me: dest_value

        # Removed node comment
        # Removed node inline comment

        # Trailing note

        tail: keep
      YAML
    end

    it "keeps destination-only nodes when disabled (default)" do
      template = <<~YAML
        keep_me: value
      YAML

      dest = <<~YAML
        keep_me: dest_value
        extra: stays
      YAML

      merger = described_class.new(
        template,
        dest,
        remove_template_missing_nodes: false,
      )
      result = merger.merge

      expect(result).to include("keep_me")
      expect(result).to include("extra")
      expect(result).to include("stays")
    end

    it "removes sequence items not in template when enabled with recursive" do
      template = <<~YAML
        AllCops:
          Exclude:
            - keep_this/**/*
      YAML

      dest = <<~YAML
        AllCops:
          Exclude:
            - keep_this/**/*
            - remove_this/**/*
      YAML

      merger = described_class.new(
        template,
        dest,
        recursive: true,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to include("keep_this/**/*")
      expect(result).not_to include("remove_this/**/*")
    end

    it "preserves leading comments for removed sequence items when enabled with recursive" do
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

      merger = described_class.new(
        template,
        dest,
        recursive: true,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to include("keep_this/**/*")
      expect(result).to include("# Removed sequence item comment")
      expect(result).not_to include("remove_this/**/*")
    end

    it "promotes inline comments for removed sequence items when enabled with recursive" do
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

      merger = described_class.new(
        template,
        dest,
        recursive: true,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to include("keep_this/**/*")
      expect(result).to include("# Removed sequence item inline comment")
      expect(result).not_to include("remove_this/**/*")
    end

    it "preserves both leading and inline comments for removed sequence items when enabled with recursive" do
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

      merger = described_class.new(
        template,
        dest,
        recursive: true,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to include("keep_this/**/*")
      expect(result).to include("# Removed sequence item comment")
      expect(result).to include("# Removed sequence item inline comment")
      expect(result).not_to include("remove_this/**/*")
    end
  end

  describe "FUNDING.yml-style flow sequences" do
    it "preserves leading comments separated by a blank line" do
      funding = <<~YAML
        # These are supported funding model platforms

        buy_me_a_coffee: pboling
        github: [pboling]
      YAML

      merger = described_class.new(
        funding,
        funding,
        preference: :template,
        add_template_only_nodes: true,
      )
      result = merger.merge

      expect(result).to include("# These are supported funding model platforms"),
        "Leading comment was stripped from merge output:\n#{result}"
    end

    it "preserves the blank line between leading comment and first entry" do
      funding = <<~YAML
        # These are supported funding model platforms

        buy_me_a_coffee: pboling
      YAML

      merger = described_class.new(
        funding,
        funding,
        preference: :template,
        add_template_only_nodes: true,
      )
      result = merger.merge

      expect(result).to match(/funding model platforms\n\nbuy_me_a_coffee/),
        "Blank line between comment and first entry was not preserved:\n#{result}"
    end

    it "does not duplicate entries with flow sequence values" do
      funding = <<~YAML
        # These are supported funding model platforms

        buy_me_a_coffee: pboling
        community_bridge: # Replace with a single Community Bridge project-name e.g., cloud-foundry
        github: [pboling] # Replace with up to 4 GitHub Sponsors-enabled usernames e.g., [user1, user2]
        issuehunt: pboling # Replace with a single IssueHunt username
        ko_fi: pboling # Replace with a single Ko-fi username
        liberapay: pboling # Replace with a single Liberapay username
        open_collective: kettle-rb
        patreon: galtzo # Replace with a single Patreon username
        polar: pboling
        thanks_dev: u/gh/pboling
        tidelift: rubygems/kettle-jem
      YAML

      merger = described_class.new(
        funding,
        funding,
        preference: :template,
        add_template_only_nodes: true,
      )
      result = merger.merge

      expect(result.scan("github:").count).to eq(1),
        "Expected github: to appear once but found #{result.scan("github:").count} times:\n#{result}"
      expect(result.scan("buy_me_a_coffee:").count).to eq(1)
      expect(result.scan("tidelift:").count).to eq(1)
    end

    it "uses template value for flow sequences with preference: :template" do
      template = <<~YAML
        github: [new_maintainer]
        ko_fi: pboling
      YAML
      dest = <<~YAML
        github: [old_maintainer]
        ko_fi: pboling
      YAML

      merger = described_class.new(
        template,
        dest,
        preference: :template,
      )
      result = merger.merge

      expect(result).to include("new_maintainer")
      expect(result).not_to include("old_maintainer")
      expect(result.scan("github:").count).to eq(1)
    end

    it "uses destination value for flow sequences with preference: :destination" do
      template = <<~YAML
        github: [new_maintainer]
        ko_fi: pboling
      YAML
      dest = <<~YAML
        github: [old_maintainer]
        ko_fi: pboling
      YAML

      merger = described_class.new(
        template,
        dest,
        preference: :destination,
      )
      result = merger.merge

      expect(result).to include("old_maintainer")
      expect(result).not_to include("new_maintainer")
      expect(result.scan("github:").count).to eq(1)
    end

    it "handles mixed flow and block sequences in the same file" do
      template = <<~YAML
        github: [pboling]
        AllCops:
          Exclude:
            - vendor/**/*
            - tmp/**/*
      YAML
      dest = <<~YAML
        github: [pboling]
        AllCops:
          Exclude:
            - vendor/**/*
      YAML

      merger = described_class.new(
        template,
        dest,
        preference: :destination,
        add_template_only_nodes: true,
      )
      result = merger.merge

      expect(result.scan("github:").count).to eq(1)
      expect(result).to include("vendor/**/*")
      expect(result).to include("tmp/**/*")
    end
  end

  describe "comment variation matrix" do
    it "preserves deeper nested blank-line-separated destination comment blocks when template wins" do
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

      merger = described_class.new(
        template,
        dest,
        preference: :template,
      )
      result = merger.merge

      expect(result).to match(/root:\n  parent:\n    child:\n      # Destination grandchild docs\n      # More destination docs\n\n      grandchild: template_value\n\z/)
    end

    it "preserves matched nested comments while promoting removed nested sibling comments in the same parent" do
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

      merger = described_class.new(
        template,
        dest,
        preference: :template,
        recursive: true,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to include("# Keep docs")
      expect(result).to include("keep: template_value # keep inline")
      expect(result).to include("# Remove docs")
      expect(result).to include("# remove inline")
      expect(result).not_to include("remove_me: old_value")
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

      merger = described_class.new(
        template,
        dest,
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
      )
      result = merger.merge

      expect(result).to include("# Funding docs")
      expect(result).to include("github: [template_user] # github note")
      expect(result.scan("github:").count).to eq(1)
      expect(result).to include("# Destination exclude docs")
      expect(result).to include("- vendor/**/* # keep vendor note")
      expect(result).to include("- tmp/**/*")
    end

    it "preserves multiple blank lines after nested destination comment-only sections before recursive content" do
      template = <<~YAML
        parent:
          child: template_value
          added: template_added
      YAML
      dest = <<~YAML
        parent:
          # Section docs
          # More section docs


          child: dest_value
      YAML

      merger = described_class.new(
        template,
        dest,
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
      )
      result = merger.merge

      expect(result).to match(/# More section docs\n\n\n  child: template_value\n  added: template_added\n\z/)
    end

    it "preserves blank-line-separated nested comment-only sections when a sibling is removed and another is added" do
      template = <<~YAML
        settings:
          keep: template_value
          added: template_added
      YAML
      dest = <<~YAML
        settings:
          # Keep docs
          keep: dest_value # keep inline

          # Shared section docs
          # More shared docs


          # Remove docs
          remove_me: old_value # remove inline
      YAML

      merger = described_class.new(
        template,
        dest,
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to match(/keep: template_value # keep inline\n\n  # Shared section docs\n  # More shared docs\n\n\n  # Remove docs\n  # remove inline\n  added: template_added\n\z/)
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

      merger = described_class.new(
        template,
        dest,
        recursive: true,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to include("# Keep docs")
      expect(result).to include("- keep # keep inline")
      expect(result).to include("# Remove docs")
      expect(result).to include("# remove inline")
      expect(result).not_to include("- remove # remove inline")
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

      merger = described_class.new(
        template,
        dest,
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to include("# Keep item docs")
      expect(result).to include("value: template_value # keep inline")
      expect(result).to include("# Remove item docs")
      expect(result).to include("# remove inline")
      expect(result).to include("- name: added")
      expect(result).to include("value: template_added")
      expect(result).not_to include("- name: remove")
      expect(result.scan("- name: keep").size).to eq(1)
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

      merger = described_class.new(
        template,
        dest,
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result.scan("# Keep group docs").size).to eq(1)
      expect(result).to include("- - keep # keep inline")
      expect(result).to include("- template_inner")
      expect(result).to include("# Remove group docs")
      expect(result).to include("# remove inline")
      expect(result).to include("- - added")
      expect(result).to include("- template_added")
      expect(result).not_to include("- - remove")
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

      merger = described_class.new(
        template,
        dest,
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to include("# Keep docs")
      expect(result).to include("keep: template_value # keep inline")
      expect(result).to match(/# Shared section docs\n      # More shared docs\n\n      # Remove docs/)
      expect(result).to include("# remove inline")
      expect(result).to include("add: template_added")
      expect(result).to include("- name: untouched")
      expect(result).to include("stable: template_stable")
      expect(result.scan("# Shared section docs").size).to eq(1)
      expect(result).not_to include("remove: old_value")
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

      merger = described_class.new(
        template,
        dest,
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to include("# Keep docs")
      expect(result).to include("- keep_rule # keep inline")
      expect(result).to include("# Shared section docs")
      expect(result).to include("# More shared docs")
      expect(result).to include("# Remove docs")
      expect(result).to include("# remove inline")
      expect(result).to include("- add_rule")
      expect(result).to include("- name: untouched")
      expect(result).to include("stable: template_stable")
      expect(result.scan("# Shared section docs").size).to eq(1)
      expect(result).not_to include("- remove_rule")
      expect(result).to match(/# More shared docs\n\n        # Remove docs/)
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

      merger = described_class.new(
        template,
        dest,
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      expect(result).to include("# Keep rule docs")
      expect(result).to include("- id: keep")
      expect(result).to include("value: template_value # keep inline")
      expect(result).to include("# Shared rule docs")
      expect(result).to include("# More shared rule docs")
      expect(result).to include("# Remove rule docs")
      expect(result).to include("# remove inline")
      expect(result).to include("- id: add")
      expect(result).to include("value: template_added")
      expect(result).to include("- name: untouched")
      expect(result).to include("stable: template_stable")
      expect(result.scan("# Shared rule docs").size).to eq(1)
      expect(result).not_to include("- id: remove")
      expect(result).to match(/# More shared rule docs\n\n        # Remove rule docs/)
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

      merger = described_class.new(
        template,
        dest,
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      beta_index = result.index("- id: beta")
      alpha_index = result.index("- id: alpha")
      add_index = result.index("- id: add")

      expect(beta_index).not_to be_nil
      expect(alpha_index).not_to be_nil
      expect(add_index).not_to be_nil
      expect(beta_index).to be < alpha_index
      expect(alpha_index).to be < add_index
      expect(result).to include("value: template_beta # beta inline")
      expect(result).to include("value: template_alpha # alpha inline")
      expect(result).to include("# Removed rule docs")
      expect(result).to include("# remove inline")
      expect(result.scan("- id: alpha").size).to eq(1)
      expect(result.scan("- id: beta").size).to eq(1)
      expect(result.scan("- id: add").size).to eq(1)
      expect(result).not_to include("- id: remove")
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

      merger = described_class.new(
        template,
        dest,
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      )
      result = merger.merge

      second_index = result.index("scope: second")
      first_index = result.index("scope: first")
      add_index = result.index("scope: add")

      expect(second_index).not_to be_nil
      expect(first_index).not_to be_nil
      expect(add_index).not_to be_nil
      expect(second_index).to be < first_index
      expect(first_index).to be < add_index
      expect(result).to include("value: template_second # second inline")
      expect(result).to include("value: template_first # first inline")
      expect(result).to include("# Removed duplicate docs")
      expect(result).to include("# remove inline")
      expect(result.scan("scope: first").size).to eq(1)
      expect(result.scan("scope: second").size).to eq(1)
      expect(result.scan("scope: add").size).to eq(1)
      expect(result).not_to include("scope: remove")
    end
  end

  describe "add_template_only_sequence_items option" do
    let(:template_block) do
      <<~YAML
        licenses:
          - MIT
          - Apache-2.0
          - PolyForm-Small-Business-1.0.0
      YAML
    end

    let(:dest_block_one) do
      <<~YAML
        licenses:
          - ISC
      YAML
    end

    let(:template_flow) do
      <<~YAML
        licenses: [MIT, Apache-2.0, PolyForm-Small-Business-1.0.0]
      YAML
    end

    let(:dest_flow_one) do
      <<~YAML
        licenses: [ISC]
      YAML
    end

    context "with add_template_only_nodes: true (default sequence behavior)" do
      it "adds template-only items to a dest block sequence" do
        merger = described_class.new(
          template_block,
          dest_block_one,
          preference: :destination,
          add_template_only_nodes: true,
        )
        result = merger.merge
        expect(result).to include("ISC")
        expect(result).to include("Apache-2.0")
        expect(result).to include("PolyForm-Small-Business-1.0.0")
      end
    end

    context "with add_template_only_sequence_items: false (user-locked sequences)" do
      it "does NOT add template-only items to a dest block sequence" do
        merger = described_class.new(
          template_block,
          dest_block_one,
          preference: :destination,
          add_template_only_nodes: true,
          add_template_only_sequence_items: false,
        )
        result = merger.merge
        expect(result).to include("ISC")
        expect(result).not_to include("Apache-2.0")
        expect(result).not_to include("PolyForm-Small-Business-1.0.0")
      end

      it "does NOT add template-only items to a dest flow sequence" do
        merger = described_class.new(
          template_flow,
          dest_flow_one,
          preference: :destination,
          add_template_only_nodes: true,
          add_template_only_sequence_items: false,
        )
        result = merger.merge
        expect(result).to include("ISC")
        expect(result).not_to include("Apache-2.0")
        expect(result).not_to include("PolyForm-Small-Business-1.0.0")
      end

      it "still adds template-only mapping nodes when add_template_only_nodes is true" do
        template = <<~YAML
          name: project
          licenses:
            - MIT
          new_key: added_by_template
        YAML
        dest = <<~YAML
          name: project
          licenses:
            - ISC
        YAML
        merger = described_class.new(
          template,
          dest,
          preference: :destination,
          add_template_only_nodes: true,
          add_template_only_sequence_items: false,
        )
        result = merger.merge
        expect(result).to include("new_key: added_by_template")
        expect(result).to include("ISC")
        expect(result).not_to include("- MIT")
      end
    end

    describe "multi-byte character (emoji) handling" do
      it "does not duplicate keys when destination contains emoji values" do
        template = "name: default"
        dest = "emoji: \"🪙\"\nname: custom"
        merger = described_class.new(
          template,
          dest,
          preference: :destination,
          add_template_only_nodes: true,
        )
        result = merger.merge
        expect(result.scan("name:").length).to eq(1)
      end

      it "preserves emoji values in destination" do
        template = "key: template"
        dest = "key: \"🍲 special\""
        merger = described_class.new(
          template,
          dest,
          preference: :destination,
        )
        result = merger.merge
        expect(result).to include("🍲 special")
      end

      it "handles multiple emoji without duplicating keys" do
        template = "x: \"1\"\ny: \"2\""
        dest = "e1: \"🍲\"\ne2: \"🪙\"\nx: a\ny: b"
        merger = described_class.new(
          template,
          dest,
          preference: :destination,
          add_template_only_nodes: true,
        )
        result = merger.merge
        expect(result.scan("x:").length).to eq(1)
        expect(result.scan("y:").length).to eq(1)
      end

      it "handles CJK characters without duplicating keys" do
        template = "lang: en"
        dest = "greeting: \"こんにちは\"\nlang: ja"
        merger = described_class.new(
          template,
          dest,
          preference: :destination,
          add_template_only_nodes: true,
        )
        result = merger.merge
        expect(result.scan("lang:").length).to eq(1)
      end
    end
  end
end

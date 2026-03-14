# frozen_string_literal: true

RSpec.describe Psych::Merge::SmartMerger do
  it_behaves_like "Ast::Merge::RemovalModeCompliance" do
    let(:merger_class) { described_class }

    let(:removal_mode_leading_comments_case) do
      {
        template: <<~YAML,
          keep_me: value
        YAML
        destination: <<~YAML,
          keep_me: dest_value

          # Removed node comment
          remove_me: should_be_gone
        YAML
        expected: <<~YAML,
          keep_me: dest_value

          # Removed node comment
        YAML
      }
    end

    let(:removal_mode_inline_comments_case) do
      {
        template: <<~YAML,
          keep_me: value
        YAML
        destination: <<~YAML,
          keep_me: dest_value
          remove_me: should_be_gone # Removed node inline comment
        YAML
        expected: <<~YAML,
          keep_me: dest_value
          # Removed node inline comment
        YAML
      }
    end

    let(:removal_mode_separator_blank_line_case) do
      {
        template: <<~YAML,
          keep_me: value
          tail: keep
        YAML
        destination: <<~YAML,
          keep_me: dest_value

          # Removed node comment
          remove_me: should_be_gone # Removed node inline comment

          # Trailing note

          tail: keep
        YAML
        expected: <<~YAML,
          keep_me: dest_value

          # Removed node comment
          # Removed node inline comment

          # Trailing note

          tail: keep
        YAML
      }
    end

    let(:removal_mode_recursive_case) do
      fixture_dir = File.expand_path("../../fixtures/reproducible/07_recursive_sequence_mapping_items_comment_promotion_blank_lines", __dir__)

      {
        template: File.read(File.join(fixture_dir, "template.yml")),
        destination: File.read(File.join(fixture_dir, "destination.yml")),
        expected: File.read(File.join(fixture_dir, "result.yml")),
        options: {
          preference: :template,
          recursive: true,
          add_template_only_nodes: true,
        },
      }
    end
  end
end

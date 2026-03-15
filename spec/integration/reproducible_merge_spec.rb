# frozen_string_literal: true

require "psych/merge"
require "ast/merge/rspec/shared_examples"

RSpec.describe "Psych reproducible merge" do
  let(:fixtures_path) { File.expand_path("../fixtures/reproducible", __dir__) }
  let(:merger_class) { Psych::Merge::SmartMerger }
  let(:file_extension) { "yml" }

  describe "basic merge scenarios (destination wins by default)" do
    context "when a key is removed in destination" do
      it_behaves_like "a reproducible merge", "01_key_removed"
    end

    context "when a key is added in destination" do
      it_behaves_like "a reproducible merge", "02_key_added"
    end

    context "when a value is changed in destination" do
      it_behaves_like "a reproducible merge", "03_value_changed"
    end
  end

  describe "comment-heavy recursive scenarios" do
    context "when deep nested destination docs are preserved while template content wins" do
      it_behaves_like "a reproducible merge", "05_deep_nested_comment_block_template_preference", {
        preference: :template,
      }
    end

    context "when recursive siblings mix keep/remove/add with blank-line-separated destination docs" do
      it_behaves_like "a reproducible merge", "06_recursive_mixed_siblings_comment_only_section_blank_lines", {
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      }
    end

    context "when recursive sequence mapping items mix keep/remove/add with promoted comments" do
      it_behaves_like "a reproducible merge", "07_recursive_sequence_mapping_items_comment_promotion_blank_lines", {
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      }
    end

    context "when recursive nested sequence groups mix keep/remove/add with promoted comments" do
      it_behaves_like "a reproducible merge", "08_recursive_nested_sequence_groups_comment_promotion", {
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      }
    end

    context "when matched sequence items carry nested mapping comment sections without sibling spillover" do
      it_behaves_like "a reproducible merge", "09_sequence_item_nested_mapping_comment_sections", {
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      }
    end

    context "when matched sequence items carry nested mapping plus nested sequence comments without sibling spillover" do
      it_behaves_like "a reproducible merge", "10_sequence_item_nested_mapping_nested_sequence_comments", {
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      }
    end

    context "when matched sequence items carry nested mapping plus nested sequence mapping comments without sibling spillover" do
      it_behaves_like "a reproducible merge", "11_sequence_item_nested_mapping_nested_sequence_mapping_comments", {
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      }
    end

    context "when matched inner mapping items keep destination order while template-only additions append" do
      it_behaves_like "a reproducible merge", "12_sequence_item_nested_mapping_nested_sequence_multiple_keeps_removed_comments_stable_identity", {
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      }
    end

    context "when repeated inner ids require stable secondary discrimination to preserve comment association" do
      it_behaves_like "a reproducible merge", "13_sequence_item_nested_mapping_nested_sequence_duplicate_inner_id_comments_order_stability", {
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      }
    end

    context "when sequence mapping items rely on globally unique keys like orcid, email, or value" do
      it_behaves_like "a reproducible merge", "14_sequence_mapping_items_match_on_orcid_email_and_value", {
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      }
    end

    context "when template-only document boundary comments surround matched top-level mappings" do
      it_behaves_like "a reproducible merge", "15_preferred_document_boundary_comments_are_preserved", {
        preference: :template,
        recursive: true,
        add_template_only_nodes: true,
        remove_template_missing_nodes: true,
      }
    end
  end
end

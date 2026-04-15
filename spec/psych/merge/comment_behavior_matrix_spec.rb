# frozen_string_literal: true

require "spec_helper"
require "ast/merge/rspec/shared_examples"

RSpec.describe Psych::Merge::SmartMerger, "comment behavior matrix", :yaml_parsing do
  extend Ast::Merge::RSpec::CommentBehaviorMatrixAdapters

  it_behaves_like "Ast::Merge::CommentBehaviorMatrix" do
    hash_comment_line_based_comment_matrix_adapter(
      analysis_class: Psych::Merge::FileAnalysis,
      merger_class: Psych::Merge::SmartMerger,
      structural_owners_reader: ->(analysis) { analysis.statements.grep(Psych::Merge::MappingEntry) },
      owner_value_reader: ->(owner) { owner.value.value.inspect },
      line_builder: lambda do |name, value, inline: nil|
        line = "#{name}: #{value}"
        inline ? "#{line} # #{inline}" : line
      end,
      capabilities: {
        matched_inline_comment_preference: "destination inline comments remain authoritative on matched YAML entries",
        cross_source_preamble_ownership_dedup: "Psych document preamble vs first-owner ownership remains unsupported",
        cross_source_preamble_spacing_dedup: "Psych equivalent preamble blocks with different blank-line ownership remain unsupported",
      },
    )
  end
end

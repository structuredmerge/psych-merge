# frozen_string_literal: true

require "spec_helper"
require "ast/merge/rspec/shared_examples"

RSpec.describe "psych comment behavior matrix", :yaml_parsing do
  extend Ast::Merge::RSpec::CommentBehaviorMatrixAdapters

  include_examples "Ast::Merge::CommentBehaviorMatrix" do
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
      },
    )
  end
end

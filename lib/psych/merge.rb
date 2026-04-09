# frozen_string_literal: true

# External gems
require "psych"
require "tree_haver"
require "version_gem"
require "set"

# Shared merge infrastructure
require "ast/merge"

# This gem
require_relative "merge/version"

# Psych::Merge provides a generic YAML file smart merge system using Psych AST analysis.
# It intelligently merges template and destination YAML files by identifying matching
# keys and resolving differences using structural signatures.
#
# @example Basic usage
#   template = File.read("template.yml")
#   destination = File.read("destination.yml")
#   merger = Psych::Merge::SmartMerger.new(template, destination)
#   result = merger.merge
#
# @example With debug information
#   merger = Psych::Merge::SmartMerger.new(template, destination)
#   debug_result = merger.merge_with_debug
#   puts debug_result[:content]
#   puts debug_result[:statistics]
module Psych
  # Smart merge system for YAML files using Psych AST analysis.
  # Provides intelligent merging by understanding YAML structure
  # rather than treating files as plain text.
  #
  # @see SmartMerger Main entry point for merge operations
  # @see FileAnalysis Analyzes YAML structure
  # @see ConflictResolver Resolves content conflicts
  module Merge
    # Base error class for Psych::Merge
    # Inherits from Ast::Merge::Error for consistency across merge gems.
    class Error < Ast::Merge::Error; end

    # Raised when a YAML file has parsing errors.
    # Inherits from Ast::Merge::ParseError for consistency across merge gems.
    #
    # @example Handling parse errors
    #   begin
    #     analysis = FileAnalysis.new(yaml_content)
    #   rescue ParseError => e
    #     puts "YAML syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error}" }
    #   end
    class ParseError < Ast::Merge::ParseError
      # @param message [String, nil] Error message (auto-generated if nil)
      # @param content [String, nil] The YAML source that failed to parse
      # @param errors [Array] Parse errors from Psych
      def initialize(message = nil, content: nil, errors: [])
        super(message, errors: errors, content: content)
      end
    end

    # Raised when the template file has syntax errors.
    #
    # @example Handling template parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue TemplateParseError => e
    #     puts "Template syntax error: #{e.message}"
    #     e.errors.each do |error|
    #       puts "  #{error.message}"
    #     end
    #   end
    class TemplateParseError < ParseError; end

    # Raised when the destination file has syntax errors.
    #
    # @example Handling destination parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue DestinationParseError => e
    #     puts "Destination syntax error: #{e.message}"
    #     e.errors.each do |error|
    #       puts "  #{error.message}"
    #     end
    #   end
    class DestinationParseError < ParseError; end

    autoload :CommentTracker, "psych/merge/comment_tracker"
    autoload :DebugLogger, "psych/merge/debug_logger"
    autoload :DiffMapper, "psych/merge/diff_mapper"
    autoload :Emitter, "psych/merge/emitter"
    autoload :FreezeNode, "psych/merge/freeze_node"
    autoload :FileAnalysis, "psych/merge/file_analysis"
    autoload :MappingEntry, "psych/merge/file_analysis"
    autoload :MergeResult, "psych/merge/merge_result"
    autoload :NodeTypeNormalizer, "psych/merge/node_type_normalizer"
    autoload :NodeWrapper, "psych/merge/node_wrapper"
    autoload :ConflictResolver, "psych/merge/conflict_resolver"
    autoload :PartialTemplateMerger, "psych/merge/partial_template_merger"
    autoload :SmartMerger, "psych/merge/smart_merger"
    autoload :MappingMatchRefiner, "psych/merge/mapping_match_refiner"
  end
end

# Register with ast-merge's MergeGemRegistry for RSpec dependency tags
# Only register if MergeGemRegistry is loaded (i.e., in test environment)
if defined?(Ast::Merge::RSpec::MergeGemRegistry)
  Ast::Merge::RSpec::MergeGemRegistry.register(
    :psych_merge,
    require_path: "psych/merge",
    merger_class: "Psych::Merge::SmartMerger",
    test_source: "key: value",
    category: :config,
  )
end

Psych::Merge::Version.class_eval do
  extend VersionGem::Basic
end

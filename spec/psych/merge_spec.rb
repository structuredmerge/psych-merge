# frozen_string_literal: true

RSpec.describe Psych::Merge do
  it "has a version number" do
    expect(Psych::Merge::VERSION).not_to be_nil
  end

  it "has the expected version format" do
    expect(Psych::Merge::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  describe "module structure" do
    it "defines Error class inheriting from Ast::Merge::Error" do
      expect(Psych::Merge::Error).to be < Ast::Merge::Error
    end

    it "defines ParseError class inheriting from Ast::Merge::ParseError" do
      expect(Psych::Merge::ParseError).to be < Ast::Merge::ParseError
    end

    it "defines TemplateParseError class" do
      expect(Psych::Merge::TemplateParseError).to be < Psych::Merge::ParseError
    end

    it "defines DestinationParseError class" do
      expect(Psych::Merge::DestinationParseError).to be < Psych::Merge::ParseError
    end
  end

  describe "autoloaded classes" do
    it "autoloads CommentTracker" do
      expect(Psych::Merge::CommentTracker).to be_a(Class)
    end

    it "autoloads DebugLogger" do
      expect(Psych::Merge::DebugLogger).to be_a(Module)
    end

    it "autoloads Emitter" do
      expect(Psych::Merge::Emitter).to be_a(Class)
    end

    it "autoloads FreezeNode" do
      expect(Psych::Merge::FreezeNode).to be_a(Class)
    end

    it "autoloads FileAnalysis" do
      expect(Psych::Merge::FileAnalysis).to be_a(Class)
    end

    it "autoloads MergeResult" do
      expect(Psych::Merge::MergeResult).to be_a(Class)
    end

    it "autoloads NodeWrapper" do
      expect(Psych::Merge::NodeWrapper).to be_a(Class)
    end

    it "autoloads ConflictResolver" do
      expect(Psych::Merge::ConflictResolver).to be_a(Class)
    end

    it "autoloads SmartMerger" do
      expect(Psych::Merge::SmartMerger).to be_a(Class)
    end
  end

  describe ".register_backend!" do
    it "registers yaml with TreeHaver" do
      registrations = TreeHaver.registered_language(:yaml)

      expect(registrations).to be_a(Hash)
      expect(registrations.keys).to include(:psych)
    end
  end
end

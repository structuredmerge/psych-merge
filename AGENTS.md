# AGENTS.md - Development Guide

## 🎯 Project Overview

`psych-merge` is a **format-specific implementation of the `*-merge` gem family** for YAML files. It provides intelligent YAML file merging using AST analysis via Ruby's standard library Psych parser.

```ruby
# kettle-jem:freeze
# ... custom code preserved across template runs ...
# kettle-jem:unfreeze
```

### Modular Gemfile Architecture

Gemfiles are split into modular components under `gemfiles/modular/`. Each component handles a specific concern (coverage, style, debug, etc.). The main `Gemfile` loads these modular components via `eval_gemfile`.

### Forward Compatibility with `**options`

**CRITICAL**: All constructors and public API methods that accept keyword arguments MUST include `**options` as the final parameter for forward compatibility.

**Repository**: https://github.com/kettle-rb/psych-merge
**Current Version**: 1.0.0
**Required Ruby**: >= 3.2.0 (currently developed against Ruby 4.0.1)

## ⚠️ AI Agent Terminal Limitations

### Terminal Output Is Available, but Each Command Is Isolated

**Minimum Supported Ruby**: See the gemspec `required_ruby_version` constraint.
**Local Development Ruby**: See `.tool-versions` for the version used in local development (typically the latest stable Ruby).

### Use `mise` for Project Environment

**CRITICAL**: The canonical project environment lives in `mise.toml`, with local overrides in `.env.local` loaded via `dotenvy`.

⚠️ **Watch for trust prompts**: After editing `mise.toml` or `.env.local`, `mise` may require trust to be refreshed before commands can load the project environment. Until that trust step is handled, commands can appear hung or produce no output, which can look like terminal access is broken.

**Recovery rule**: If a `mise exec` command goes silent or appears hung, assume `mise trust` is the first thing to check. Recover by running:

```bash
mise trust -C /home/pboling/src/kettle-rb/psych-merge
mise exec -C /home/pboling/src/kettle-rb/psych-merge -- bundle exec rspec
```

```bash
mise trust -C /path/to/project
mise exec -C /path/to/project -- bundle exec rspec
```

Do this before spending time on unrelated debugging; in this workspace pattern, silent `mise` commands are usually a trust problem first.

```bash
mise trust -C /home/pboling/src/kettle-rb/psych-merge
```

```bash
mise exec -C /path/to/project -- bundle exec rspec
```

✅ **CORRECT** — If you need shell syntax first, load the environment in the same command:

```bash
mise exec -C /home/pboling/src/kettle-rb/psych-merge -- bundle exec rspec
```

✅ **CORRECT**:
```bash
eval "$(mise env -C /home/pboling/src/kettle-rb/psych-merge -s bash)" && bundle exec rspec
```

❌ **WRONG**:
```bash
cd /home/pboling/src/kettle-rb/psych-merge
bundle exec rspec
```

❌ **WRONG**:
```bash
cd /home/pboling/src/kettle-rb/psych-merge && bundle exec rspec
```

```bash
cd /path/to/project
bundle exec rspec
```

❌ **WRONG** — A chained `cd` does not give directory-change hooks time to update the environment:

```bash
cd /path/to/project && bundle exec rspec
```

### Prefer Internal Tools Over Terminal

Full suite spec runs:

```bash
mise exec -C /path/to/project -- bundle exec rspec
```

For single file, targeted, or partial spec runs the coverage threshold **must** be disabled.
Use the `K_SOUP_COV_MIN_HARD=false` environment variable to disable hard failure:

### Workspace layout

## 🏗️ Architecture

### Toolchain Dependencies

This gem is part of the **kettle-rb** ecosystem. Key development tools:

### NEVER Pipe Test Commands Through head/tail

When you do run tests, keep the full output visible so you can inspect failures completely.

## 🏗️ Architecture: Format-Specific Implementation

### What psych-merge Provides

- **`Psych::Merge::SmartMerger`** – YAML-specific SmartMerger implementation
- **`Psych::Merge::FileAnalysis`** – YAML file analysis with mapping/sequence extraction
- **`Psych::Merge::NodeWrapper`** – Wrapper for Psych AST nodes (mappings, sequences, scalars)
- **`Psych::Merge::MappingEntry`** – Key-value pair representation
- **`Psych::Merge::MergeResult`** – YAML-specific merge result
- **`Psych::Merge::ConflictResolver`** – YAML conflict resolution
- **`Psych::Merge::FreezeNode`** – YAML freeze block support
- **`Psych::Merge::DebugLogger`** – Psych-specific debug logging

### Key Dependencies

| Gem | Role |
|-----|------|
| `ast-merge` (~> 4.0) | Base classes and shared infrastructure |
| `tree_haver` (~> 5.0) | Unified parser adapter (wraps Psych) |
| `psych` (stdlib) | Ruby's built-in YAML parser |
| `version_gem` (~> 1.1) | Version management |

### Parser Backend

psych-merge uses Ruby's standard library `Psych` parser exclusively via TreeHaver's `:psych_backend`:

| Backend | Parser | Platform | Notes |
|---------|--------|----------|-------|
| `:psych_backend` | Psych (stdlib) | All Ruby platforms | Built into Ruby, no external dependencies |

| Tool | Purpose |
|------|---------|
| `kettle-dev` | Development dependency: Rake tasks, release tooling, CI helpers |
| `kettle-test` | Test infrastructure: RSpec helpers, stubbed_env, timecop |
| `kettle-jem` | Template management and gem scaffolding |

### Executables (from kettle-dev)

| Executable | Purpose |
|-----------|---------|
| `kettle-release` | Full gem release workflow |
| `kettle-pre-release` | Pre-release validation |
| `kettle-changelog` | Changelog generation |
| `kettle-dvcs` | DVCS (git) workflow automation |
| `kettle-commit-msg` | Commit message validation |
| `kettle-check-eof` | EOF newline validation |

## 📁 Project Structure

```
lib/psych/merge/
├── smart_merger.rb          # Main SmartMerger implementation
├── file_analysis.rb         # YAML file analysis (mappings, sequences)
├── node_wrapper.rb          # AST node wrapper for Psych nodes
├── mapping_entry.rb         # Key-value pair representation
├── merge_result.rb          # Merge result object
├── conflict_resolver.rb     # Conflict resolution
├── freeze_node.rb           # Freeze block support
├── debug_logger.rb          # Debug logging
└── version.rb

spec/psych/merge/
├── smart_merger_spec.rb
├── file_analysis_spec.rb
├── node_wrapper_spec.rb
├── mapping_entry_spec.rb
└── integration/
```

```
lib/
├── <gem_namespace>/           # Main library code
│   └── version.rb             # Version constant (managed by kettle-release)
spec/
├── fixtures/                  # Test fixture files (NOT auto-loaded)
├── support/
│   ├── classes/               # Helper classes for specs
│   └── shared_contexts/       # Shared RSpec contexts
├── spec_helper.rb             # RSpec configuration (loaded by .rspec)
gemfiles/
├── modular/                   # Modular Gemfile components
│   ├── coverage.gemfile       # SimpleCov dependencies
│   ├── debug.gemfile          # Debugging tools
│   ├── documentation.gemfile  # YARD/documentation
│   ├── optional.gemfile       # Optional dependencies
│   ├── rspec.gemfile          # RSpec testing
│   ├── style.gemfile          # RuboCop/linting
│   └── x_std_libs.gemfile     # Extracted stdlib gems
├── ruby_*.gemfile             # Per-Ruby-version Appraisal Gemfiles
└── Appraisal.root.gemfile     # Root Gemfile for Appraisal builds
.git-hooks/
├── commit-msg                 # Commit message validation hook
├── prepare-commit-msg         # Commit message preparation
├── commit-subjects-goalie.txt # Commit subject prefix filters
└── footer-template.erb.txt    # Commit footer ERB template
```

## 🔧 Development Workflows

### Running Tests

```bash
# Full suite (required for coverage thresholds)
mise exec -C /home/pboling/src/kettle-rb/psych-merge -- bundle exec rspec

# Single file (disable coverage threshold check)
mise exec -C /home/pboling/src/kettle-rb/psych-merge -- env K_SOUP_COV_MIN_HARD=false bundle exec rspec spec/psych/merge/smart_merger_spec.rb
```

### Running Commands

Always make commands self-contained. Use `mise exec -C /home/pboling/src/kettle-rb/prism-merge -- ...` so the command gets the project environment in the same invocation.
If the command is complicated write a script in local tmp/ and then run the script.

```bash
mise exec -C /path/to/project -- env K_SOUP_COV_MIN_HARD=false bundle exec rspec spec/path/to/spec.rb
```

### Coverage Reports

```bash
mise exec -C /home/pboling/src/kettle-rb/psych-merge -- bin/rake coverage
mise exec -C /home/pboling/src/kettle-rb/psych-merge -- bin/kettle-soup-cover -d
```

```bash
mise exec -C /path/to/project -- bin/rake coverage
mise exec -C /path/to/project -- bin/kettle-soup-cover -d
```

**Key ENV variables** (set in `mise.toml`, with local overrides in `.env.local`):
❌ **AVOID** when possible:

- `run_in_terminal` for information gathering

Only use terminal for:

- Running tests (`bundle exec rspec`)
- Installing dependencies (`bundle install`)
- Simple commands that do not require much shell escaping
- Running scripts (prefer writing a script over a complicated command with shell escaping)

### Code Quality

```bash
bundle exec rake reek
bundle exec rake rubocop_gradual
```

```bash
mise exec -C /path/to/project -- bundle exec rake reek
mise exec -C /path/to/project -- bundle exec rubocop-gradual
```

### Releasing

```bash
bin/kettle-pre-release    # Validate everything before release
bin/kettle-release        # Full release workflow
```

## 📝 Project Conventions

### API Conventions

#### SmartMerger API

### Test Infrastructure

- Uses `kettle-test` for RSpec helpers (stubbed_env, block_is_expected, silent_stream, timecop)
- Uses `Dir.mktmpdir` for isolated filesystem tests
- Spec helper is loaded by `.rspec` — never add `require "spec_helper"` to spec files

#### YAML-Specific Features

**Mapping Merging**:
```ruby
merger = Psych::Merge::SmartMerger.new(template_yaml, dest_yaml)
result = merger.merge
```

### Freeze Block Preservation

Template updates preserve custom code wrapped in freeze blocks:

```yaml
database:
  # psych-merge:freeze
  password: custom_secret  # Don't override this
  # psych-merge:unfreeze
  host: localhost
```

**Anchor/Alias Support**:
```yaml
defaults: &defaults
  timeout: 30
  retries: 3

production:
  <<: *defaults
  host: prod.example.com
```

### kettle-dev Tooling

This project is a **RubyGem** managed with the [kettle-rb](https://github.com/kettle-rb) toolchain.

- **Rakefile**: Sourced from kettle-dev template
- **CI Workflows**: GitHub Actions and GitLab CI managed via kettle-dev
- **Releases**: Use `kettle-release` for automated release process

### Version Requirements

- `K_SOUP_COV_DO=true` – Enable coverage
- `K_SOUP_COV_MIN_LINE` – Line coverage threshold
- `K_SOUP_COV_MIN_BRANCH` – Branch coverage threshold
- `K_SOUP_COV_MIN_HARD=true` – Fail if thresholds not met

## 🧪 Testing Patterns

### TreeHaver Dependency Tags

### Environment Variable Helpers

```ruby
before do
  stub_env("MY_ENV_VAR" => "value")
end

before do
  hide_env("HOME", "USER")
end
```

### Dependency Tags

Use dependency tags to conditionally skip tests when optional dependencies are not available:

**Available tags**:
- `:psych_backend` – Requires Psych backend (always available in Ruby)
- `:yaml_parsing` – Requires YAML parser (always available)

✅ **CORRECT** — Run self-contained commands with `mise exec`:

```ruby
RSpec.describe Psych::Merge::SmartMerger, :psych_backend do
  # Standard pattern even though Psych is always available
end

it "parses YAML", :yaml_parsing do
  # Consistent with other *-merge gems
end
```

```bash
eval "$(mise env -C /path/to/project -s bash)" && bundle exec rspec
```

❌ **WRONG** — Do not rely on a previous command changing directories:

```ruby
before do
  skip "Requires Psych" unless defined?(Psych)  # DO NOT DO THIS
end
```

### Shared Examples

psych-merge uses shared examples from `ast-merge`:

```ruby
it_behaves_like "Ast::Merge::FileAnalyzable"
it_behaves_like "Ast::Merge::ConflictResolverBase"
it_behaves_like "a reproducible merge", "scenario_name", { preference: :template }
```

## 🔍 Critical Files

| File | Purpose |
|------|---------|
| `lib/psych/merge/smart_merger.rb` | Main YAML SmartMerger implementation |
| `lib/psych/merge/file_analysis.rb` | YAML file analysis and mapping extraction |
| `lib/psych/merge/node_wrapper.rb` | Psych node wrapper with YAML-specific methods |
| `lib/psych/merge/mapping_entry.rb` | Key-value pair abstraction |
| `lib/psych/merge/debug_logger.rb` | Psych-specific debug logging |
| `spec/spec_helper.rb` | Test suite entry point |
| `mise.toml` | Shared development environment defaults |

## 🚀 Common Tasks

```bash
# Run all specs with coverage
bundle exec rake spec

# Generate coverage report
bundle exec rake coverage

# Check code quality
bundle exec rake reek
bundle exec rake rubocop_gradual

# Prepare and release
kettle-changelog && kettle-release
```

## 🌊 Integration Points

✅ **PREFERRED** — Use internal tools:

- `grep_search` instead of `grep` command
- `file_search` instead of `find` command
- `read_file` instead of `cat` command
- `list_dir` instead of `ls` command
- `replace_string_in_file` or `create_file` instead of `sed` / manual editing

## 💡 Key Insights

1. **Psych is always available**: It's part of Ruby stdlib, but we still use TreeHaver for consistency
2. **MappingEntry abstraction**: YAML key-value pairs are wrapped for easier manipulation
3. **Anchor/alias preservation**: Psych AST includes anchors and aliases; we preserve them during merge
4. **Comment tracking**: Comments are associated with nodes via `CommentTracker`
5. **Freeze blocks use `# psych-merge:freeze`**: Language-specific comment syntax
6. **Document vs Stream**: Psych parses into Stream → Document → Node hierarchy; we handle all levels
7. **Scalar quoting**: Psych provides raw scalar values; quoting style is preserved in source

```ruby
RSpec.describe SomeClass, :prism_merge do
  # Skipped if prism-merge is not available
end
```

## 🚫 Common Pitfalls

1. **NEVER assume all YAML is valid**: Use `FileAnalysis#valid?` to check parse success
2. **NEVER use manual skip checks** – Use dependency tags (`:psych_backend`, `:yaml_parsing`)
3. **Do NOT forget nil checks**: YAML allows null values; handle them explicitly
4. **Do NOT load vendor gems** – They are not part of this project; they do not exist in CI
5. **Use `tmp/` for temporary files** – Never use `/tmp` or other system directories
6. **Do NOT expect `cd` to persist** – Every terminal command is isolated; use a self-contained `mise exec -C ... -- ...` invocation.
7. **Do NOT rely on prior shell state** – Previous `cd`, `export`, aliases, and functions are not available to the next command.

## 🔧 YAML-Specific Notes

### Node Types in Psych

```ruby
Psych::Nodes::Stream     # Top-level container
Psych::Nodes::Document   # YAML document (can have multiple per stream)
Psych::Nodes::Mapping    # Key-value pairs (hashes)
Psych::Nodes::Sequence   # Arrays/lists
Psych::Nodes::Scalar     # Strings, numbers, booleans
Psych::Nodes::Alias      # Reference to an anchor
```

### Merge Behavior

- **Mappings**: Matched by key name; deeply nested mappings are traversed
- **Sequences**: Can be merged or replaced based on preference
- **Scalars**: Leaf values; matched by context (parent key)
- **Anchors**: Preserved; aliases remain valid after merge
- **Comments**: Preserved when attached to mappings/sequences
- **Freeze blocks**: Protect customizations from template updates

### MappingEntry Structure

```ruby
entry = Psych::Merge::MappingEntry.new(
  key: key_wrapper,      # NodeWrapper for key
  value: value_wrapper,  # NodeWrapper for value
  lines: lines,
  comment_tracker: tracker
)

entry.key_name         # String key name
entry.value_node       # Access wrapped value node
entry.start_line       # Line number in source
```

1. **NEVER pipe test output through `head`/`tail`** — Run tests without truncation so you can inspect the full output.

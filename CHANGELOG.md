# Changelog

[![SemVer 2.0.0][📌semver-img]][📌semver] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog]

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][📗keep-changelog],
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and [yes][📌major-versions-not-sacred], platform and engine support are part of the [public API][📌semver-breaking].
Please file a bug if you notice a violation of semantic versioning.

[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-FFDD67.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-FFDD67.svg?style=flat

## [Unreleased]

### Added

- Added shared `Ast::Merge::Comment` region, attachment, and augmenter adoption over Psych comment tracking, including normalized analysis and wrapper attachment APIs plus shared-example compliance coverage

### Changed

- **BREAKING**: `ConflictResolver#merge_nodes_to_emitter` signature simplified to
  `merge_nodes_to_emitter(template_nodes, dest_nodes, template_by_sig, depth: 0)`.
  Removed `processed_template_sigs`, `processed_dest_sigs`, and `dest_by_sig`
  parameters. Signature matching now uses cursor-based positional matching
  (consumed indices + per-signature cursor) internally, ensuring multiple nodes
  with the same signature are matched 1:1 in order rather than collapsed.
  The `nested_dest_by_sig` build in `emit_recursive_mapping_merge` was also
  removed as dead code.
- Preserved normalized comment regions and attachments through YAML emission and merge paths while keeping document boundaries, recursive comment-heavy fixtures, and destination-leading / inline ownership stable under template preference
- Clarified the YAML removal-mode baseline so `remove_template_missing_nodes: true` preserves or promotes comment regions for removed destination-only mappings instead of silently dropping them
- Adopted `Ast::Merge::TrailingGroups::DestIterate` plus shared deferred-flush ordering for mappings and sequence items so template-only YAML additions keep their template-relative position even when destination keys or list items are reordered

### Fixed

- `ConflictResolver#merge_nodes_to_emitter` now preserves inter-node blank lines
  from the destination, so visual spacing between YAML sections (e.g., between
  `name:` and `on:` in GitHub Actions workflows) is maintained after merge
- Fix recursive sequence item matching for mapping entries identified by
  globally unique scalar keys such as `value` and `orcid`, preferring stable
  identities over mutable fields like `email` so citation-style YAML sequences
  merge 1:1 instead of duplicating author entries
- Fix template-preference document boundary emission so top-level YAML prelude /
  postlude comment regions and matched mapping-entry preludes are emitted from
  the template side instead of being dropped or replaced by destination-only
  boundaries in `.kettle-jem.yml`-style files
- Fix flow sequence duplication in recursive merge. YAML entries with flow sequence
  values (e.g., `github: [pboling]`) were duplicated because `can_merge_recursively?`
  returned `true` for sequences, causing `emit_recursive_merge` to emit the key line,
  then `emit_sequence_item` to re-emit the same physical line. Flow sequences (where
  the value occupies the same line as the key) are now treated atomically.
- Fix leading comment association when blank lines separate comments from the
  first mapping entry. `CommentTracker#leading_comments_before` now skips blank lines
  when searching upward for comments. `emit_node` now emits the blank line separator
  between comments and the node when one existed in the original source.
  Reported via kettle-jem self-test against `.github/FUNDING.yml`.
- Fix recursive sequence emission so a template or destination item no longer
  swallows the next sibling's leading comment block from its physical line
  range, preventing duplicated workflow-style section comments when inserting
  template-only items.
- Fix observation-based recursive sequence matching for composite items such as
  nested sequences, allowing stable inner scalars to match outer siblings 1:1
  so comment ownership and removal-mode promotion stay attached to the correct
  item.
- Fix document-level comment-only destination headers so, when the preferred
  document has no nodes, the header is emitted once as a prelude instead of
  being duplicated again as a trailing postlude after template-only additions.
- Fix wrapped mapping / sequence value line ranges so a node no longer claims a
  following sibling's leading comment block in `.kettle-jem.yml`-style files,
  preventing duplicated commented sections when `patterns:` is followed by a
  commented `files:` section.

### Deprecated

### Removed

### Security

## [1.0.0] - 2026-02-19

- TAG: [v1.0.0][1.0.0t]
- COVERAGE: 91.92% -- 921/1002 lines in 14 files
- BRANCH COVERAGE: 73.00% -- 311/426 branches in 14 files
- 97.39% documented

### Added

- AGENTS.md
- `Psych::Merge::DiffMapper` - Maps unified git diffs to YAML AST key paths
  - Inherits from `Ast::Merge::DiffMapperBase`
  - `#map_hunk_to_paths` - Maps diff hunks to YAML key paths (e.g., `["AllCops", "Exclude"]`)
  - `#create_analysis` - Creates `FileAnalysis` for YAML content
  - Tracks nested paths via indentation and MappingEntry location data
  - Groups consecutive changed lines by their containing YAML node
- `Psych::Merge::PartialTemplateMerger` - Merges partial YAML templates into specific key paths
  - Navigate to specific key paths (e.g., `["AllCops", "Exclude"]`) in destination
  - Merge template content at that location while preserving rest of document
  - `key_path:` - Array of keys/indices to navigate to target location
  - `add_missing:` - Whether to add template items not in destination (default: `true`)
  - `remove_missing:` - Whether to remove destination items not in template (default: `false`)
  - `when_missing:` - Behavior when key path not found (`:skip` or `:add`, default: `:skip`)
  - `recursive:` - Whether to recursively merge nested structures (default: `true`)
  - Returns `Result` object with `content`, `has_key_path`, `changed`, `stats`, `message`
- `Psych::Merge::SmartMerger` - New options for advanced merge control:
  - `recursive: true | false | Integer` - Control recursive merging of nested structures
    - `true` (default): Merge nested mappings/sequences recursively instead of replacing wholesale
    - `false`: Replace entire matched nodes (original behavior)
    - `Integer > 0`: Maximum recursion depth
  - `remove_template_missing_nodes: false` - When `true`, removes destination nodes not present in template
- `Psych::Merge::ConflictResolver` - Recursive merge implementation:
  - `#emit_recursive_merge` - Recursively merge matched nodes
  - `#emit_recursive_mapping_merge` - Merge nested mapping entries
  - `#emit_recursive_sequence_merge` - Merge sequences with union semantics
  - `#can_merge_recursively?` - Check if two nodes can be recursively merged
  - Handles both `MappingEntry` and raw `NodeWrapper` nodes
- `node_typing` parameter for per-node-type merge preferences
  - Enables `preference: { default: :destination, special_type: :template }` pattern
  - Works with custom merge_types assigned via node_typing lambdas
- `regions` and `region_placeholder` parameters for nested content merging
- Initial release

### Changed

- appraisal2 v3.0.6
- kettle-test v1.0.10
- stone_checksums v1.0.3
- [ast-merge v4.0.6](https://github.com/kettle-rb/ast-merge/releases/tag/v4.0.6)
- [tree_haver v5.0.5](https://github.com/kettle-rb/tree_haver/releases/tag/v5.0.5)
- tree_stump v0.2.0
  - fork no longer required, updates all applied upstream
- Updated documentation on hostile takeover of RubyGems
  - https://dev.to/galtzo/hostile-takeover-of-rubygems-my-thoughts-5hlo
- **SmartMerger**: Added `**options` for forward compatibility
  - Accepts additional options that may be added to base class in future
  - Passes all options through to `SmartMergerBase`
- **ConflictResolver**: Added `**options` for forward compatibility
  - Now passes `match_refiner` to base class instead of storing locally
- **MergeResult**: Added `**options` for forward compatibility
- Updated documentation on hostile takeover of RubyGems
  - https://dev.to/galtzo/hostile-takeover-of-rubygems-my-thoughts-5hlo

### Fixed

- ConflictResolver now applies Hash-based per-node-type preferences via `node_typing`.

### Security

[Unreleased]: https://github.com/kettle-rb/psych-merge/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/kettle-rb/psych-merge/compare/3330d3309d6962a4e676aa1c43e4ca90dfd21dc4...v1.0.0
[1.0.0t]: https://github.com/kettle-rb/psych-merge/tags/v1.0.0

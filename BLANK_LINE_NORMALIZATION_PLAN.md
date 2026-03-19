# Blank Line Normalization Plan for `psych-merge`

_Date: 2026-03-19_

## Role in the family refactor

`psych-merge` is the structured YAML adopter for the shared blank-line normalization effort.

It is a strong source-augmented merge path and should validate that the shared layout model works even when comment ownership is not purely native-parser-driven.

## Current evidence files

Implementation files:

- `lib/psych/merge/smart_merger.rb`
- `lib/psych/merge/conflict_resolver.rb`
- `lib/psych/merge/file_analysis.rb`
- emitter/result files under `lib/psych/merge/`

Relevant specs:

- `spec/psych/merge/smart_merger_spec.rb`
- `spec/integration/reproducible_merge_spec.rb`
- `spec/psych/merge/removal_mode_compliance_spec.rb`

## Current pressure points

`psych-merge` already cares about spacing around:

- leading comments for keys and mappings
- promoted inline comments when removed nodes disappear
- recursive nested structures
- stable separator blank lines after removal-mode promotion

## Migration targets

### 1. Adopt shared layout-gap attachment concepts

YAML ownership already uses shared comment concepts; blank-line ownership should follow the same pattern.

### 2. Replace string-level blank-line fixes where shared gap logic is sufficient

Repo-local spacing normalization should be reduced when the shared layout model can preserve or normalize gaps correctly.

### 3. Keep recursive semantics aligned with the shared contract

Nested mappings and sequences should use the same blank-line rules as top-level merges wherever the format semantics permit.

## Workstreams

- inventory existing blank-line-sensitive YAML specs
- map where gaps are implicit in resolver/emitter behavior
- adopt shared `ast-merge` layout abstractions once available
- extend focused regressions for recursive separator preservation and idempotence

## Exit criteria

- YAML blank-line behavior is expressed via shared layout semantics instead of bespoke fixes where possible
- recursive behavior remains consistent with top-level behavior
- promoted comments keep intended separator blank lines without duplication or swallowing

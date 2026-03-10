# PLAN.md

## Goal
Keep `psych-merge` as the reference implementation for the shared Comment AST & Merge capability and use it to guide the rollout across the rest of the merge-gem family.

This gem is the baseline for shared comment regions, attachments, document prelude/postlude handling, matched-node comment fallback, removed-node comment promotion, and recursive comment-preserving merge behavior.

## Current Status
- `psych-merge` is the most advanced shared-comment integration in the family.
- It already has focused resolver and smart-merger coverage for comment-heavy recursive YAML scenarios.
- Reproducible fixtures now cover deep nested mappings, recursive sequences, nested sequence mappings, and duplicate-inner-id stability.
- The current role of this gem is to stay stable while the other merge gems adopt the same shared capability shape.

## Ongoing Priorities
1. Keep the current YAML comment-preservation behavior stable as the rest of the family adopts the same ideas.
2. Use `psych-merge` as the reference when extracting or refining shared comment APIs in `ast-merge`.
3. Continue adding reproducible fixtures whenever a new high-value comment-preservation edge case is discovered.
4. Avoid regressions in recursive merge ordering, comment-only sections, and removed-node promotion behavior.

## First Files To Inspect When Resuming
- `lib/psych/merge/file_analysis.rb`
- `lib/psych/merge/conflict_resolver.rb`
- `lib/psych/merge/smart_merger.rb`
- `lib/psych/merge/comment_tracker.rb`
- `spec/psych/merge/`
- `spec/integration/reproducible_merge_spec.rb`

## Tests To Keep Strong
- focused resolver regressions for matched / removed / recursive comment cases
- smart merger end-to-end specs for destination comment preservation
- reproducible fixture scenarios for recursive comment-heavy YAML
- any new regressions found while porting the shared capability to other gems

## Risks
- Recursive comment ownership is easy to regress while generalizing shared APIs.
- Sequence identity and duplicate-key matching logic must stay stable.
- Blank-line-separated comment regions can be lost if coordinate systems mix.
- `psych-merge` should not become so specialized that other gems cannot follow its public shape.

## Success Criteria
- `psych-merge` remains green and stable while the family rollout proceeds.
- Shared APIs extracted from this gem remain general enough for other formats.
- New regressions are captured with focused specs and reproducible fixtures.
- This gem continues to serve as the implementation and behavior reference for the family.

## Rollout Phase
- Reference baseline / keep-green track.
- This gem is not the next feature target unless family rollout work exposes a shared API gap or a regression.

## Execution Backlog

### Slice 1 — Keep the baseline stable
- Keep focused resolver and smart-merger comment regressions green.
- Keep reproducible integration scenarios green, especially recursive comment-heavy cases.
- Add a new fixture immediately whenever another gem rollout uncovers a reusable YAML comment-preservation edge case.

### Slice 2 — Extract only proven shared APIs
- Move behavior into shared `ast-merge` comment abstractions only after it has been proven in `psych-merge` and needed by another gem.
- Prefer small, format-agnostic extractions over YAML-specific helpers.
- Re-check that extracted APIs still support duplicate-identity sequence matching, removed-node promotion, and blank-line comment sections.

### Slice 3 — Guard the family rollout
- Use `psych-merge` as the comparison target when another gem adopts prelude/postlude handling, matched-node comment fallback, and removed-node comment promotion.
- Add new focused specs whenever family-wide API changes threaten recursive ordering or comment ownership.
- Keep the reproducible fixture suite growing only with high-value scenarios.

## Dependencies / Resume Notes
- Inspect `lib/psych/merge/conflict_resolver.rb` first for any shared behavior questions.
- Inspect `spec/integration/reproducible_merge_spec.rb` first when checking whether a newly discovered shape is already pinned.
- Treat this gem as the behavior oracle for `jsonc-merge`, `dotenv-merge`, `toml-merge`, and any source-augmented comment merger.

## Exit Gate For This Plan
- The family rollout can rely on stable shared comment APIs without repeatedly changing `psych-merge` semantics.
- New work in this gem is mostly regression coverage, not foundational redesign.

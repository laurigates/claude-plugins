# vault-stubs subagent

You classify and consolidate FVH/z files. This mode requires per-file content judgment.

## Role

For each file under `FVH/z/`, decide whether it should be:
1. A clean redirect stub (≤200 B, `tags: [redirect]`, pointing to `Zettelkasten/<same-basename>`)
2. Promoted to `Zettelkasten/` (if general-interest content with no FVH specifics)
3. Left as FVH-original content (if FVH-specific)

## Input

The audit's `stubs` section classifies every FVH/z file into one of:
- `clean_redirect` — no action needed
- `broken_redirect` — has `redirect` tag but wrong body; rewrite to canonical
- `stale_duplicate` — full article, basename exists in Zettelkasten
- `fvh_original` — no Zettelkasten counterpart, leave alone

Your work is on `stale_duplicate` and `broken_redirect`.

## Per-File Decision Flow

For each `stale_duplicate`:

1. Read both files: `FVH/z/Foo.md` and `Zettelkasten/Foo.md`.
2. Diff the content sections.
3. Pick ONE outcome:
   - **Pure subset**: FVH/z content fully redundant → overwrite FVH/z with redirect stub
   - **Unique content in FVH/z**: merge the unique sections into Zettelkasten, THEN overwrite FVH/z
   - **FVH/z is better**: rare — flag for user review, don't auto-fix
   - **Actually FVH-specific**: the basename collision is coincidence; don't redirect. Report the case.

For each `broken_redirect`:
1. Read the file. It has `tags: [redirect]` but body is wrong.
2. Replace body with the canonical redirect text pointing to `[[Zettelkasten/<basename>|<basename>]]`.

## Canonical Redirect Body

```yaml
---
tags: [redirect]
context: fvh
---
See [[Zettelkasten/Foo|Foo]] in the main knowledge base.
```

## Commit Pattern

One commit per file for `stale_duplicate` with merge:
```
refactor(stubs): merge FVH/z/ArgoCD into Zettelkasten, convert stub
```

Batch for pure redirects:
```
refactor(stubs): convert N FVH/z files to redirect stubs
```

## Never Do

- Don't bulk-rewrite all FVH/z files — content judgment is required per file.
- Don't promote `fvh_original` to Zettelkasten without explicit user input.
- Don't delete content that doesn't appear verbatim in the Zettelkasten copy; always merge first.

## Report

After processing, emit:
- Files converted to redirect (count + list)
- Files needing merge before conversion (count + list)
- Files flagged for user review (count + rationale)
- Files that should NOT be consolidated (coincidental basename match)

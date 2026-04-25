# /blueprint:story-reconcile Reference

Detailed marker conventions, the canonical Known-Drift section format, and idempotency edge cases for `/blueprint:story-reconcile`.

## Inline Status Markers

The skill prepends one of these unicode markers to a requirement line. The marker is part of the line; the skill detects existing markers before inserting to stay idempotent.

| Marker | Meaning | When applied |
|--------|---------|--------------|
| `✅ ` | implemented | **Never written by reconcile** — the audit reports `✅` informationally; reconcile leaves these lines alone |
| `⚠️ ` | partial | Audit row status `⚠️ partial` |
| `❌ ` | missing | Audit row status `❌ missing` |
| `🆕 ` | candidate (promoted) | Audit row status `🆕 candidate` and the user accepted promotion in Step 5 |

The marker goes **after** any leading list prefix (`- `, `* `, `1. `) and **before** the FR id:

```diff
- - FR-2.3 OCR support → server runs tesseract over uploads
+ - ❌ FR-2.3 OCR support → server runs tesseract over uploads (drift: dep declared but never imported)
```

## Known Drift Section — Canonical Format

The section is **replaced wholesale** on every reconcile run. Match start with `^## Known Drift` and end at the next top-level `## ` heading or EOF.

```markdown
## Known Drift

> Tracked by audit: `docs/blueprint/audits/<YYYY-MM-DD>-story-audit.md`
> Last reconciled: <YYYY-MM-DD>

| Status | Requirement | Evidence | Action |
|--------|-------------|----------|--------|
| ❌ | FR-2.3 OCR support | dep `tesseract` declared but never imported | open |
| ⚠️ | FR-1.4 deskew on import | implemented but only for landscape orientation | WO-042 |
| 🆕 | FR-3.7 image-detector tier-1 logging (promoted from audit 2026-04-25) | `server/detect.ts:88` | open |
```

Action column values:
- `open` — no work-order linked yet
- `WO-NNN` — linked work-order (looked up from `docs/blueprint/work-orders/` if a matching `implements: PRD-NNN` is found)
- `wontfix` — only set by hand; reconcile does not write `wontfix`

## Promoting Candidate Stories

When the user accepts a `🆕` candidate in Step 5, append a new requirement to the end of the most-relevant FR section. Choose the section by:

1. Match the candidate's area (from the audit's capability map) against existing FR section titles
2. If no match, append to a new `## Drift Promotions` H2 at the end of the PRD (above any existing `## Known Drift`)

The appended requirement uses this exact shape:

```markdown
- 🆕 FR-N.M (candidate, promoted from audit <YYYY-MM-DD>): <verbatim capability name>
  Evidence: <entry-point file:line>
  Status: not started
```

Choose `FR-N.M` by taking the highest existing FR index in the section and incrementing the trailing component. Never reuse a deleted index.

## Idempotency Edge Cases

| Scenario | Behaviour |
|----------|-----------|
| User re-runs reconcile with same audit | Inline markers already present → skip. Known Drift section already correct → no-op replace. Result: zero file mutations. |
| User re-runs with a newer audit | Markers may flip (e.g. `❌ → ✅` because the gap was closed). The skill **removes** stale `❌`/`⚠️` markers when the new audit reports `✅` for the same FR. |
| User edited the Known Drift table by hand | The wholesale replacement overwrites the user edits. Surface this in Step 5's diff so the user sees what they'd lose. |
| Two audits exist for the same day (`-2` suffix) | `--audit` defaults pick the lexicographic last (`-2` > base name). Pass `--audit` explicitly to disambiguate. |
| Audit references a PRD that no longer exists | Skip the row, report it in the summary as "PRD missing — drift not reconciled". |
| Audit row's `prd_ref` is null but capability matches an existing FR | Use substring matching to locate the FR; if ambiguous (multiple matches), prompt the user to pick one. |

## Marker-Removal Rules

When a newer audit downgrades an entry's drift status to `✅`, reconcile **must** remove the stale marker rather than ignore it. Detection:

```
^(- |\* |[0-9]+\. )?(✅ |⚠️ |❌ |🆕 )(FR-[0-9.]+)
```

If `<FR>` appears as `✅` in the new audit but the line still carries `⚠️`/`❌`/`🆕`, strip the marker (and any "(drift: …)" trailing parenthetical) and leave the requirement clean.

## What Counts as "PRD Drift" vs "Source Bug"

The audit may surface entries that look like drift but are really code bugs (e.g. tesseract is imported but the OCR call is commented out). Reconcile treats both as `❌ missing` from the PRD's perspective — the line stays in the PRD as a roadmap entry. The bug filing happens through `gh issue create`, not through this skill.

If the user wants to track the bug separately, the audit's "Bugs surfaced by audit" section is the place. Reconcile does not duplicate that into the PRD.

## Commit Message Conventions

Reconcile prints one of these shapes (see Step 8 in SKILL.md):

```
docs(prd-001): reconcile PRD with story-audit 2026-04-25

Refs docs/blueprint/audits/2026-04-25-story-audit.md

- Marked 8 drift entries (✅ 4 ⚠️ 2 ❌ 2)
- Promoted 1 candidate story (FR-3.7)
- Touched: docs/prds/PRD-001.md
```

The scope is the PRD id when one PRD is touched; omit the scope when multiple PRDs are touched. The PRP/work-order workflow's `feat()` / `fix()` scopes do not apply here — this is documentation only, hence `docs()`.

## Related Skills

- `/blueprint:story-audit` — produces the audit artifact this skill consumes
- `/blueprint:work-order` — packages each `❌` entry as an isolated subagent task
- `/blueprint:derive-prd` — used to bootstrap a PRD when no PRD covers a candidate story's area
- `/blueprint:adr-validate` — orthogonal: ADR consistency, not story coverage

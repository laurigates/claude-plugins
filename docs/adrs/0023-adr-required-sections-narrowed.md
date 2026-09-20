---
id: ADR-0023
date: 2026-09-20
created: 2026-09-20
modified: 2026-09-20
status: Accepted
deciders: claude-plugins team
domain: architecture
relates-to:
  - ADR-0005  # blueprint development methodology (the document hierarchy the ADR template serves)
  - ADR-0011  # blueprint state in docs/ (where this corpus lives)
  - ADR-0016  # deterministic script extraction (the schema is the deterministic substrate the hook calls)
github-issues:
  - 2446  # 20 of 22 ADRs lack the template sections the schema requires
  - 2440  # schema/hook SSOT reconciliation that first made the gap visible
---

# ADR-0023: Narrow the ADR Schema's Required Sections to Context, Decision, Consequences

## Context

`blueprint-plugin/schemas/adr.schema.json` declared five required `## `
sections: `Context`, `Decision`, `Consequences`, `Options Considered`, and
`Related ADRs`. Until #2440 that list was unenforced text — the schema was
referenced by no code, and the PreToolUse hook that actually validated ADRs
carried its own separate, drifted field list. #2440 made the schema the single
source of truth, which is the first time anything measured the corpus against
it.

The measurement (22 ADRs under `docs/adrs/`, validator run per file):

| Section | Missing in |
|---|---|
| `Context` | 0 of 22 |
| `Decision` | 4 of 22 |
| `Consequences` | 1 of 22 |
| `Options Considered` | 20 of 22 |
| `Related ADRs` | 20 of 22 |

That is **45 section warnings** across the corpus (46 total warnings; the
forty-sixth is ADR-0014's missing `superseded-by`, unrelated to sections).
Only `0014-reusable-workflows-in-repository.md` and
`0020-blueprint-autonomy-levels.md` carry all five sections.

Two facts make the last two rows different in kind from the first three:

1. **They are not load-bearing.** An ADR without `Context`, `Decision`, or
   `Consequences` is not an ADR — it fails to record what was decided, why the
   question arose, or what the decision costs. An ADR without
   `Options Considered` is still a complete record of a decision; it just does
   not enumerate roads not taken. `Related ADRs` is navigational metadata that
   `relates-to` frontmatter already carries in machine-readable form, and which
   `/blueprint:adr-relationships` derives independently.

2. **They cannot be back-filled honestly.** The four ADRs missing `Decision`
   and the one missing `Consequences` are fixable: the decision and its
   consequences are *in* those documents, under differently-named headings, and
   moving them under the canonical heading is formatting. Writing
   `Options Considered` for 20 ADRs authored months ago is not formatting — it
   is composing a deliberation record after the fact, from the ADR's own
   conclusion. Whatever that produces is not evidence that the alternatives
   were weighed.

A warning that no one can clear without fabricating content is a warning that
gets ignored, and an ignored warning channel degrades the signal of every other
warning in it. The validator deliberately WARNs rather than blocks
(`.claude/rules/hook-block-vs-nudge.md`), so nothing was broken — but 45
permanent warnings is a broken *instrument*, and #2446 was filed to force the
choice rather than let it stay invisible.

## Decision

**`blueprint-plugin/schemas/adr.schema.json` requires exactly three ADR
sections: `Context`, `Decision`, `Consequences`.** `Options Considered` and
`Related ADRs` become optional.

The change is confined to the `sections.required` array in that one file. It
does **not** touch:

- **Frontmatter requirements.** `id`, `status`, `created`, `modified` stay
  required, and the `superseded-by` and legacy-`date` conditional warnings are
  unchanged.
- **Severity.** Missing sections still WARN, never block. Narrowing the set
  is not an argument for hardening what remains.
- **The hook or the validator.** `hooks/validate-adr-frontmatter.sh` is a thin
  `exec` into `validate-frontmatter.sh` and declares no field list;
  `scripts/check-schema.py` reads `sections.required` from the schema. Neither
  carries a copy of the section list, so neither changes. That property is what
  makes this a one-line decision rather than a three-file sweep, and it is the
  property #2440 bought.
- **The ADR template.** `/blueprint:adr-validate` and the authoring template
  still ask for all five sections. The schema is the floor an existing document
  must meet; the template is the ceiling a new one should aim at. This ADR
  itself carries all five.

The five ADRs still missing `Decision` (4) or `Consequences` (1) remain WARN,
correctly: those are real, fixable gaps and the warning should keep pointing at
them until someone moves the content under the canonical heading.

## Options Considered

### Option 1: Back-write the missing sections (rejected)

Research each of the 20 ADRs — its PR, its issue thread, the discussion around
it — and write a genuine `Options Considered` from that evidence.

**Pros:** Preserves the richer template as an enforced standard. Where the
deliberation really is recoverable, recovering it has standalone value.

**Cons:** This is 40 sections of historical research, not a formatting sweep,
and the evidence is thin or absent for most of the corpus. The realistic
outcome — reverse-engineering "alternatives" from each ADR's own conclusion —
manufactures a deliberation record that documents nothing that happened. A
fabricated `Options Considered` is strictly worse than an absent one: it
asserts that alternatives were weighed, and a future reader has no way to tell
the invented ones from the real. Rejected on honesty grounds, which is also why
#2440 declined to do it as a drive-by.

### Option 2: Narrow the required set (chosen)

Require only what an ADR cannot be without.

**Pros:** One-line diff. Takes section warnings from 45 to 5 and leaves those 5
pointing at genuinely fixable gaps. Aligns the enforced floor with what the
corpus demonstrably sustains, so the warning channel stays credible.

**Cons:** Removes schema pressure toward documenting alternatives. Mitigated by
keeping both sections in the template and in `/blueprint:adr-validate`, which
is the gate that can insist for *new* ADRs where the deliberation is live and
writing it costs nothing.

### Option 3: Suppress the warnings without changing the schema (rejected)

Filter `Options Considered` / `Related ADRs` out of the validator's output, or
add a per-file opt-out.

**Pros:** Same warning-count result with the declared standard untouched.

**Cons:** Reintroduces exactly the split #2440 closed — a rule stated in the
schema and silently contradicted in the code that reads it. The next person to
read `sections.required` would be misled, and
`.claude/rules/offload-to-deterministic-substrate.md` puts the rule in the
substrate precisely so it cannot be contradicted elsewhere. Rejected.

### Option 4: Grandfather by date (rejected)

Require all five for ADRs created after some cutoff, three for older ones.

**Pros:** Keeps the strong standard for new work while forgiving the corpus.

**Cons:** JSON Schema has no clean way to express "required depends on a
frontmatter date", so this lands as conditional `allOf` logic that every reader
has to decode, to encode a policy the template already conveys at zero cost.
The complexity is real and the benefit is redundant with Option 2's mitigation.

## Consequences

### Positive

- Section warnings across `docs/adrs/` drop from **45 to 5** (total warnings
  46 → 6), and the remaining five name real, fixable gaps.
- The warning channel is credible again: a WARN from the ADR validator now
  means something a human can act on.
- The enforced floor matches practice, so `/blueprint:adr-validate` and the
  PreToolUse hook stop generating noise on every ADR edit.
- No code changes. The schema stayed the single source of truth through a
  change to its own rules — the SSOT property from #2440 paid for itself on
  first use.

### Negative

- Less schema pressure toward recording alternatives. New ADRs can now omit
  `Options Considered` without a warning, and the template is only a
  convention.
- **There is no enforced ceiling.** `Options Considered` and `Related ADRs` are
  now recommended by convention only. `/blueprint:adr-validate` checks
  relationships, reference integrity, numbering and index drift — it has never
  checked sections — and the repo carries no five-section authoring template
  (`docs/adrs/README.md` §ADR Format documents the three-section Nygard shape).
  So this ADR removes the floor's lower two rungs without any surface picking
  them up. Building that ceiling — a section check in `blueprint-adr-validate`,
  or a real template — is deliberately left as separate work, because adding a
  new gate is a different decision from narrowing this one.

### Mitigations

| Issue | Mitigation |
|-------|------------|
| Weaker pressure on new ADRs | Unmitigated by design, and stated plainly above rather than papered over: no surface enforces the two optional sections today. This ADR models the full five-section shape as the convention to imitate |
| Two-surface standard | The schema's `sections` description says which sections it polices and which it deliberately does not, so a reader of the schema alone is not misled |
| Stale prose | Fixed in the same commit: `blueprint-plugin/README.md`'s schema table and WARN rationale, `blueprint-plugin/docs/hook-design-decisions.md`'s section table (which listed all five as "P0 - Blocking" — wrong on both counts), and `docs/adrs/README.md`'s index and category lists |

## Related ADRs

- [ADR-0005: Blueprint Development Methodology](0005-blueprint-development-methodology.md) — establishes the ADR/PRD/PRP hierarchy whose ADR template this constrains
- [ADR-0011: Blueprint State in docs/ Directory](0011-blueprint-state-in-docs-directory.md) — places the ADR corpus that supplied the measurement
- [ADR-0016: Extract Deterministic Skill Procedure into Structured-Output Scripts](0016-deterministic-script-extraction-for-token-efficiency.md) — the deterministic-substrate principle that keeps the section list in the schema and out of the hook

## References

- [Issue #2446](https://github.com/laurigates/claude-plugins/issues/2446) — the corpus measurement and the two honest options
- [Issue #2440](https://github.com/laurigates/claude-plugins/issues/2440) — schema/hook SSOT reconciliation that made the gap measurable
- `.claude/rules/hook-block-vs-nudge.md` — why missing sections WARN rather than block
- `.claude/rules/offload-to-deterministic-substrate.md` — why the rule lives in the schema

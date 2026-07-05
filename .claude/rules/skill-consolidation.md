---
created: 2026-05-29
modified: 2026-06-10
reviewed: 2026-07-04
paths:
  - "**/SKILL.md"
  - "**/skill.md"
  - "**/skills/**"
---

# Consolidating, Merging, and Deleting Skills

When trimming a skill cluster — folding two skills into one, deduping an
overlapping pair, or deleting a redundant skill — three failure modes recur.
This rule is the checklist that avoids them. Companion to
`skill-development.md` (creating skills), `skill-quality.md` (size/description),
and `skill-naming.md` (namespacing).

## 1. Verify the consolidation premise against the code first

A consolidation plan written in a *planning* session ("X is already a strict
superset of Y", "collapse these 8 scanners to 3") frequently does **not**
survive contact with the actual files. Before deleting anything, confirm the
premise by reading the skills and mapping their real coupling.

| Planned claim | What actually bit (W2/W3 consolidation, 2026-05) |
|---|---|
| "`derive-plans` is a strict superset of `derive-prd`/`derive-adr`" | False literally — `derive-plans` was *smaller* than each. Its REFERENCE already held the templates, and `adr-relationships`/`adr-validate` already owned the ADR conflict logic, but `derive-prd` had unique stakeholder-matrix / clarifying-question / GitHub-issue flows that had to be **migrated before** the delete. |
| "code-quality scanners collapse to 3" | Over-reach — the 8 scanners cover distinct concerns (dep-audit/security vs docs-quality vs complexity). Only one genuinely-adjacent pair merged (8→7). Forcing unrelated scanners together hurts auto-invocation discoverability. |

**Practice:**

- Read the candidate skills *and* their REFERENCE/supporting files. Line counts
  lie — a 195-line skill is not a superset of a 400-line one just because it
  names the same artifact.
- For a skill wired into routing / a manifest / sibling cross-references, map
  the **functional** coupling before deleting. A read-only `Explore` agent is
  the right tool: "which mentions are routing/registry that break vs prose that
  just needs a text update?"
- If the premise is wrong, **push back** — surface the gap (`AskUserQuestion`)
  and propose the defensible scope (partial merge, name-reference, or skip)
  rather than executing a lossy delete. This is the `verify-before-patching`
  and "don't blindly accept the plan" discipline applied to refactors.

## 2. Cross-plugin dedupe: reference by `plugin:skill` name, never a shared file

Two skills in **different plugins** cannot share a `REFERENCE.md`. A
`REFERENCE.md` is reached by a **relative file path**, which resolves only when
that plugin is installed — so a link from plugin A's skill into plugin B's
`REFERENCE.md` is dead whenever a user installs A without B.

| Same plugin | Cross plugin |
|---|---|
| Shared `REFERENCE.md` is fine — both skills live in the same install unit. | Designate **one canonical owner** skill that keeps the shared content; the other skill keeps only its distinct view and points at the owner **by `plugin:skill` name** (the reference form that survives independent install). |

Skills already cross-reference each other by name (`agent-patterns-plugin:wave-based-dispatch`) — that is the pattern that survives; a file path is not. If a planning note says "extract a shared REFERENCE.md" across plugins, treat it as "dedupe by skill name" instead.

## 3. Skill merge / delete checklist

What is skill-scoped (update on merge/delete) vs what is **not**:

| Update | Do NOT touch |
|---|---|
| Sibling skills' cross-references (`When to Use` rows, "see X" pointers) | `marketplace.json` — it lists **plugins**, not skills |
| The plugin `README.md` skills table + usage examples | `release-please-config.json` / `.release-please-manifest.json` — **plugin**-level |
| Flow / sequence diagrams (`docs/flow.md`, sequence `.md`) — merge nodes, keep Mermaid valid | Generator **output** (e.g. `git-repo-agent/**/generated/**`) — regenerates itself; leave it |
| Manifest `task_registry` entries + routing prose that name the deleted skill (incl. this repo's dogfooding `docs/blueprint/manifest.json`) | `CHANGELOG.md` — release-please-managed |
| `CLAUDE.md` / dogfooding tables that enumerate the skill | |

Skills are **not** individually registered anywhere a plugin is — adding or
deleting a skill needs no `marketplace.json` / release-config edit. (A
subagent's generic "deletion checklist" got this wrong; verify against the
actual `Plugin Lifecycle` section of `CLAUDE.md`, which is plugin-scoped.)

Mechanics:

- **Preserve the survivor's supporting files** with `git mv <olddir> <newdir>`
  (moves the whole tree — `REFERENCE-*.md`, `scripts/`, `fixtures/`), then fold
  the smaller skill's content in. Don't hand-recreate the ecosystem.
- **Migrate unique content before the delete**, not after — once the file is
  gone, the methodology is only in git history.
- **Trim the merged description to ≤200 chars** (it broadened to cover both
  skills' triggers and will trip the listing-budget WARN otherwise — see
  `skill-quality.md`).
- After editing, `grep -rn "<old-skill-name>" --include="*.md" .` and confirm
  the only survivors are intentional provenance notes + out-of-scope generator
  output.
- Land it as a conventional-commit `refactor(<plugin>): …` — merges/deletes are
  behaviour-preserving restructures, so no version bump.

### Cross-plugin moves: split the commits along plugin paths

release-please attributes commits **by the paths they touch**, not by the
commit scope — a single commit moving a skill from plugin A to plugin B
counts toward *both* packages, with the message's type/`!` applied to
both. Removing a user-facing skill from A is breaking (`feat(A)!:` →
major bump), but one mixed move commit would leak that major bump into
the receiving plugin too.

Split the move (precedent: PR #1561, `project-distill` →
`session-plugin:session-distill`):

1. `feat(B): …` — adds the skill at its new home (plus root metadata);
   touches only B + root paths.
2. `feat(A)!: remove <skill> (moved to B)` — deletions and A-side edits
   only, with a `BREAKING CHANGE:` footer naming the new invocation.

The rename loses git's R-detection across the commit split; the PR
description carries the traceability instead.

## Related

- `skill-development.md` — creating skills, granularity decision
- `skill-quality.md` — size limits, description length band (≤200)
- `skill-naming.md` — `plugin:skill` namespacing (the cross-plugin reference form)
- `verify-upstream-before-patching` (user rule) / repo debugging discipline — the "verify the premise before acting" principle this rule applies to refactors
- `CLAUDE.md` § Plugin Lifecycle — the **plugin**-level add/delete checklist (distinct from skill-level)

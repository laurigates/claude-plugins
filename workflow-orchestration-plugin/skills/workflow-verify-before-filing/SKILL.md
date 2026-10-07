---
name: workflow-verify-before-filing
description: Verify accumulated bug claims at upstream HEAD and dedup against trackers before filing issues. Use when filing upstream reports from backlogs, audit docs, or git-history findings.
allowed-tools: Agent, Read, Write, Edit, Bash(bash *), Bash(glab *), Bash(gh *), TodoWrite
model: opus
created: 2026-06-11
modified: 2026-09-26
reviewed: 2026-08-08
---

# Verify Before Filing

> Operational scaffolding ships beside this file, not inside it: Phases 1–2 as
> [`workflows/verify-before-filing.workflow.js`](workflows/verify-before-filing.workflow.js)
> (agent prompts, schemas, gate logic), Phase 3 as the executable
> [`scripts/file-wave.sh`](scripts/file-wave.sh). The rationale for both — why each
> constant is what it is — plus the worked example is in [REFERENCE.md](REFERENCE.md).
> This file is the decision layer.

A backlog of upstream bug candidates — audit docs, "file this later" notes,
workaround commits — is a list of **hypotheses dated to when they were
observed**, not a filing queue. Upstream moved since: versions shipped, files
restructured, other deployers reported the same thing, and some of your own
diagnoses were wrong. Filing the backlog as-is produces duplicate and
already-fixed reports — exactly the noise that makes maintainers stop reading
your issues. **Verify every claim at upstream HEAD, dedup against the
trackers (including your own earlier reports), and only file what survives.**

Measured base rate (FVH → SIMPL-Open, 2026-06-11): of 24 accumulated
candidates, **only 12 were real-and-current** — 7 claims were invalid on
inspection, 3 were already fixed upstream, 1 was obsolete, 1 duplicated our
own earlier report's by-catch. Half the backlog would have been noise.

## When to Use This Skill

| Use this skill when... | Skip when... |
|---|---|
| Filing N accumulated candidates from docs/backlogs/git history | You just hit the bug minutes ago against current HEAD |
| The observations are days-to-months old | Single trivially-checkable item — verify inline, then file |
| Claims came from audit docs nobody re-checked | |
| You've filed on this upstream before (self-dup risk) | |

## The Pipeline

Phases 1–2 also ship as a bundled harness — see
[Workflow harness (template)](#workflow-harness-template) below.

### Phase 0 — Consolidate a candidate manifest

Merge every source into one manifest — one entry per candidate with a precise,
falsifiable claim — before Phase 1. Entry shape and fields:
[references/candidate-manifest.md](references/candidate-manifest.md).

### Phase 1 — Verify + dedup (two agents per candidate, parallel)

**Verify agent** (read-only against upstream): fetch the implicated files at
default-branch HEAD *and* the latest tag; quote the current content; return a
verdict from a closed vocabulary:

```
still-present | partially-fixed | fixed-upstream | obsolete-version
| claim-invalid | could-not-verify
```

plus `targetProject`, quoted `evidence`, `checkedRefs`, and `notes` (files
moved, versions drifted, framing corrections). Hard rule: **agents are
read-only upstream** — GET requests only; nothing writes until the filing
phase. State that rule verbatim in every agent prompt.

Both prompts, with the forge-tooling block and the schemas, are the
`VERIFY_PROMPT` / `SEARCH_PROMPT` constants in
[`workflows/verify-before-filing.workflow.js`](workflows/verify-before-filing.workflow.js) —
adapt those rather than retyping them.

**Gate precedence**: any duplicate kills the filing regardless of verdict;
`could-not-verify` never files (record a human follow-up task instead).

**Search agent**: tracker search (issues + MRs, all states, several
phrasings including exact error strings) on the target project and group-wide
— **plus fetch the full bodies of your own prior reports** and check overlap
including their by-catch findings. Self-duplicates are the embarrassing kind.

**Gate**: only `still-present`/`partially-fixed` with no duplicate proceeds.
Everything else gets a recorded disposition — that record is a deliverable,
not waste (see Phase 4).

### Phase 2 — Draft to a house template

Draft each survivor to the house issue template, then gate every draft through
`agent-patterns-plugin:cold-read-gate` before filing. The template, the
no-internal-references rule, and the revise-round limit are in
[references/draft-template.md](references/draft-template.md).

### Phase 3 — Paced filing

Issue-creation endpoints rate-limit aggressively (observed: a GitLab instance
returning 429 after a **single** create). Never loop `gh`/`glab issue create`
by hand — write the Phase 1+2 result array to a JSON file and run the script,
which owns the pacing, the retries, and the URL manifest:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/file-wave.sh" --results /abs/path/results.json --dry-run
bash "${CLAUDE_SKILL_DIR}/scripts/file-wave.sh" --results /abs/path/results.json --forge glab --host <instance>
```

Run the real invocation with Bash `run_in_background: true` — at 70 s per
create a wave outlives a foreground call. Dry-run first: it resolves every
title and target project and creates nothing.

The script files only `disposition: "file"` entries, exits 0 on an empty set,
appends every URL **and** every failure to `filed-urls.txt`, and continues past
a failure rather than aborting the batch. Forge dispatch is deterministic:
`--forge gh|glab` > `$FILE_WAVE_FORGE` > a set `GITLAB_HOST` (implies `glab`) >
`gh`. `--help` documents every flag; the pacing *rationale* and the invariants
its tests pin are in [REFERENCE.md](REFERENCE.md). Cross-link related new
issues afterwards (also paced). Created GitLab issues may surface as
`/-/work_items/` URLs.

### Phase 4 — Bookkeeping (the dispositions are deliverables)

- Annotate the **source docs** the candidates came from: filed URL,
  fixed-upstream (version), duplicate-of, obsolete, or claim-retracted — the
  audit trail keeps stale claims from being re-filed next quarter.
- **Fixed-upstream discoveries usually imply local action**: a fork you can
  retire, a pin you can advance, a workaround you can delete. Record each as
  a follow-up task.
- Post the disposition table to your tracking issue; close it if nothing
  known remains unfiled.

## Workflow harness (template)

`workflows/verify-before-filing.workflow.js` ships beside this skill. **It is a TEMPLATE to
adapt, not a script to run verbatim.** Read it, then rewrite it for the work in front of you.
It covers Phases 1–2 only; Phase 3 is [`scripts/file-wave.sh`](scripts/file-wave.sh), whose
input contract is the harness's return value.

**Adapt freely:** the agent prompts and their forge-tooling block (the shipped one is GitLab),
the wave width, the house draft template, the effort tiers, and the search phrasings.

**Preserve across any adaptation:** (a) the loop bound comes from the candidate manifest passed
in as `args`, never from a prose "for each" — including the ≤5 read wave, which paces reads the
way `file-wave.sh` paces writes; (b) the closed verdict vocabulary and the gate
`['still-present','partially-fixed'].includes(verdict) && duplicateFound === 'no'`, **in that
precedence** — a duplicate kills the filing regardless of verdict, and `could-not-verify` never
files; (c) two barriers — the intra-candidate `parallel([verify, search])`, because the gate
reads *both*, and the batch-dedup pass, which compares survivors to **each other** rather than
only to the tracker. Also structural: the cold-read agent is **never** the drafter (that
independence is the gate), exactly one revise round, and `DRAFT_SCHEMA` carries the issue
**body** — a workflow script has no filesystem, so dedup cannot merge on a path.

**Agent budget:** 1 + 6 x candidates — up to six agents per candidate (verify,
search, draft, cold-read, revise, re-cold-read) plus one batch dedup. The scale guard asks before every run, because the list comes from the
caller at runtime.

**Skip the harness when:** the manifest holds one or two candidates — that is a linear pass and
the harness is pure overhead (the template aborts below three). A 24-candidate run is roughly
100–140 agents. The steps above remain the authoritative description of *what* each stage must
produce; the harness only fixes *how* the work is split.

Two clauses this template carries. The second is unconditional here — this skill's entire
output is a forge mutation:

> Never `Workflow({resumeFromRunId})` to retry a few failed worktree agents — a resume re-runs
> agents that already succeeded and opens duplicate PRs (#1868). Re-dispatch the failed units
> fresh and sequentially after checking
> `gh pr list --head <branch> --state all --json number,state`.

> Push, PR creation, and GitHub mutations happen **only** in the single sequential finalise
> stage, never inside a fanned-out agent. Here that stage is Phase 3
> (`scripts/file-wave.sh`): every agent in the harness is read-only upstream, and the harness
> returns data for the script to file.

## Verdict Vocabulary Notes

What each verdict means and its typical doc annotation:
[references/verdicts.md](references/verdicts.md).

## Common Mistakes

Mistake → correct-approach table: [references/common-mistakes.md](references/common-mistakes.md).

## Related

- `agent-patterns-plugin:cold-read-gate` — the pre-publish legibility gate
  (Phase 2)
- `agent-patterns-plugin:verify-before-plan` — same epistemics one level up:
  premises decay; check before acting on them
- [`workflow-preflight`](../workflow-preflight/SKILL.md) — remote-state
  verification before implementation work, the in-repo sibling
- User rule `verify-upstream-before-patching` (where present) — the
  single-item inline form of Phase 1

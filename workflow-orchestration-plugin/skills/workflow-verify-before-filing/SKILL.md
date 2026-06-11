---
name: workflow-verify-before-filing
description: Verify accumulated bug claims against upstream HEAD and dedup against trackers before filing issues - verify, draft, cold-read, paced filing, bookkeeping. Use when filing upstream reports from backlogs, audit docs, or git-history findings.
allowed-tools: Agent, Read, Write, Edit, Bash(glab *), Bash(gh *), TodoWrite
model: opus
created: 2026-06-11
modified: 2026-06-11
reviewed: 2026-06-11
---

# Verify Before Filing

> Operational scaffolding — the complete Workflow script skeleton (agent
> prompts, schemas, gate logic), the paced filing script, and the data flow —
> lives in [REFERENCE.md](REFERENCE.md). This file is the decision layer.

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

### Phase 0 — Consolidate a candidate manifest

One JSON/table entry per candidate: id, the **claim** (precise, falsifiable),
target upstream project, version observed, source refs (your commits/PRs that
hold real error output), and known-filed prior reports to dedup against.
Merge all sources first — audit docs, strategy docs, and git sweeps usually
overlap. Shape:

```json
{
  "id": "W2-13",
  "slug": "notification-smtp-ec-defaults",
  "claim": "Chart defaults SMTP to dev@simpl-europe.eu via ssl0.ovh.net (vendor dev infra) as live default values; should be placeholder/required.",
  "targets": ["group/subgroup/notification-service"],
  "observed_version": "2.1.1 (Apr 2026)",
  "sources": ["audit-doc item 6"],
  "evidence_prs": [1826]
}
```

Keep prior-filed report URLs (with issue iids) in the same manifest so search
agents can fetch their bodies.

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

Verify-agent prompt essentials (condensed):

```
You verify a candidate upstream bug against <forge>. READ-ONLY — GET only;
never create/edit/comment upstream.
Tooling: GITLAB_HOST=<instance> glab api "projects/<id>" (.default_branch),
".../repository/files/<URL-ENCODED-PATH>/raw?ref=<ref>", ".../repository/tags",
".../packages" for chart/package versions.
Baseline: observed at <version, date>. Determine whether the flaw is STILL
PRESENT at default-branch HEAD and the latest tag. Quote exact current
content. Superseded version line => obsolete-version. Claim wrong on
inspection => claim-invalid. Output is raw data for a machine (schema above).
```

Search-agent prompt adds: issue+MR search (state=all, several phrasings
including exact error strings), group-wide search fallback, and "fetch the
full bodies of our prior reports <list> and judge overlap including their
by-catch findings".

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

Per surviving candidate, one markdown file per issue:

```markdown
# <symptom-first title — becomes the issue title>
<!-- target: <project path>  (stripped by the filing script) -->

## Summary
<claim, with evidence as blob links PINNED to the verified refs
(https://<forge>/<path>/-/blob/<ref>/<file>#L<n>) — not bare paths,
not `main` if HEAD drifts>

<real error signature mined from your own incident PRs/logs>

## Suggested fix
<EXACTLY ONE recommended fix; alternatives get one trailing sentence;
"happy to open the MR" only when trivial>

---
Observed while <one-line deployment context>; verified against <refs> on <date>.
```

Never leak internal PR numbers or repo paths into the body — use them only to
mine evidence. Then gate every draft through
`agent-patterns-plugin:cold-read-gate` (isolated haiku maintainer cold-read;
one revise round, re-gate only if the verdict was `needs-revision`).

### Phase 3 — Paced filing

Issue-creation endpoints rate-limit aggressively (observed: a GitLab
instance returning 429 after a single create; treat the numbers below as a
starting point, not a spec). File from a script with ≥70 s pacing between
creates and, on failure, up to 4 retries with ~130 s backoff each; append
every created URL to a `filed-urls.txt` manifest, and record `FAILED` lines
for anything that exhausts retries — continue past failures and report them
at the end rather than aborting the batch. Cross-link related new issues
afterwards (also paced).
`GITLAB_HOST=<instance> glab issue create -R <project> ...` for GitLab
instances; `gh` for GitHub. Created GitLab issues may surface as
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

## Verdict Vocabulary Notes

| Verdict | Meaning | Typical doc annotation |
|---|---|---|
| `still-present` | Reproduced at HEAD + latest tag | filed URL |
| `partially-fixed` | Upstream fixed some instances; file the remainder, cite their own fix as the pattern | filed URL (narrowed) |
| `fixed-upstream` | Shipped in a release — note which | version + local follow-up |
| `obsolete-version` | The affected line is superseded/retired | superseded note |
| `claim-invalid` | The original diagnosis was wrong | retraction + what was actually true |
| `could-not-verify` | Evidence unreachable | human follow-up task |

`claim-invalid` is not failure — it's the workflow catching your own docs
drifting from reality. Correct the doc in the same pass.

## Common Mistakes

| Mistake | Correct approach |
|---|---|
| Filing the backlog as written ("the audit already verified it") | The audit verified it *then*; verify at HEAD *now* |
| Dedup against the tracker but not your own issues | Your earlier reports' by-catch findings are duplicates too |
| Quoting your old observed version in the issue | Quote HEAD/latest-tag content; cite the refs you checked |
| Bulk-creating issues in a loop with no pacing | 429 after the first create; ≥70 s pacing + backoff |
| Discarding gated-out candidates silently | Dispositions update docs, retire forks, close tracking issues |
| Letting verify agents have write access upstream | Read-only until the dedicated, paced filing step |

## Related

- `agent-patterns-plugin:cold-read-gate` — the pre-publish legibility gate
  (Phase 2)
- `agent-patterns-plugin:verify-before-plan` — same epistemics one level up:
  premises decay; check before acting on them
- [`workflow-preflight`](../workflow-preflight/SKILL.md) — remote-state
  verification before implementation work, the in-repo sibling
- User rule `verify-upstream-before-patching` (where present) — the
  single-item inline form of Phase 1

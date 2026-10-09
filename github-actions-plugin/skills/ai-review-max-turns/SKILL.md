---
name: ai-review-max-turns
description: "Triage a red Claude-powered CI review check. Use when an AI review job fails or flakes: tell a real unpublished finding from turn-budget or ceiling overruns and infra reruns via subtype + is_error."
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
created: 2026-09-02
modified: 2026-10-09
reviewed: 2026-09-23
---

# A Red AI-Review CI Check Has Five Very Different Causes — Separate Them Before Acting

A growing class of CI checks are **Claude-powered reviewers** — a workflow
that runs the Claude Code action over the PR diff and reports findings as a
pass/fail check. They are usually a family of `reusable-quality-*`,
`reusable-security-*`, and `reusable-a11y-*` workflows, surfaced on the PR as
checks named `typescript / analyze`, `secrets / scan`, `owasp / scan`,
`aria / analyze`, `wcag / analyze`, and the like.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| The red check is Claude-powered (`owasp / scan`, `secrets / scan`, `aria`/`wcag`, …) | A deterministic check failed and you need its error → `github-actions-inspection` |
| Deciding whether that red is a finding or noise | The failure is real and needs a code fix pushed → `git-plugin:git-fix-pr` |
| The AI review stays green but re-runs on every push — see [REFERENCE.md](REFERENCE.md) | |

## The five causes

They go red for five reasons that demand **opposite** responses. Reading one
as another is the whole hazard:

| Cause | Tell | Response |
|---|---|---|
| **Budget exhaustion** — the run died mid-flight | `error_max_turns` in the log; `is_error: true` | Ignore the failure; it says nothing about the code |
| **Turn-ceiling overrun** — the run *finished*, the wrapper failed the job | `is_error: false`, `subtype: "success"`, **no** `Found N` line, and `##[error]Claude reported a successful result after N turns, exceeding the configured maximum of M` | Ignore the failure; the scan completed and found nothing |
| **A real finding it could not publish** | `is_error: false`, `subtype: "success"`, a `::error::Found N …` line, **and no PR comment** | Investigate the code by hand — the check found something |
| **Result flagged errored despite completing** | `subtype: "success"` **and** `is_error: true`, low `num_turns`, 0 denials, no `Found N` line, no `result` string | Rerun the identical commit once; a pass means it was infra |
| **Bot-actor refusal** — the action refused to start Claude | No execution file, no `is_error`, no `num_turns`; the log says `non-human actor: <name> (type: Bot)`; `run_attempt` ≥ 2 with `actor` ≠ `triggering_actor` | Ignore the failure; fix the workflow with `allowed_bots`, or push with a PAT or App token |

> **The law: the red X is never the discriminator, and neither is `is_error`
> on its own.** The discriminator applies only once Claude ran: a run the action
> refused before starting (Cause 5) has no `subtype`, `is_error` or turn count to
> read, so rule out the `non-human actor` line first. Then read `subtype` and
> `is_error` together. `error_max_turns` means
> the run died mid-flight. `subtype: "success"` means it finished, and a
> finished run can still report `is_error: true` (Cause 4), so
> `is_error` alone does not separate a run that died from one that finished.
> Among finished runs reading `is_error: false`, the **finding count** decides:
> a `Found N` line means the check is trying to tell you something through a
> blocked channel; its absence alongside a turn-count error means the wrapper
> failed a scan that had nothing to say.

Read `subtype` and `is_error` first, then the finding count. Stopping at
`is_error` sends a turn-ceiling overrun to the hand-audit response, and files
Cause 4 under budget exhaustion, whose upstream fix (raise `max_turns`) cannot
help a five-turn run.

Read the subtype before forming any theory:

```sh
url=$(gh pr checks <pr> -R <owner>/<repo> --json name,link \
  --jq '.[]|select(.name=="<check>")|.link')
runid=$(echo "$url" | sed -E 's#.*/runs/([0-9]+)/.*#\1#')
gh run view "$runid" --log-failed 2>&1 | grep -iE '"is_error"|"subtype"|error_max_turns|num_turns|non-human actor'
```

**Cause 1 (budget exhaustion)** — when the log shows `error_max_turns`, open [references/budget-exhaustion.md](references/budget-exhaustion.md) for the rotating-failure tell, why not to blind-rerun, the `mergeStateStatus` check, and the upstream fix.

**Cause 2 (turn-ceiling overrun)** — when a `subtype: "success"` run logs `exceeding the configured maximum`, open [references/turn-ceiling-overrun.md](references/turn-ceiling-overrun.md) for the grep, the evidence, and the upstream fix. It also shows where the turns went: list the tool calls in the run's `claude-execution-output.json`, and on a PR that edits `.claude/` or `CLAUDE.md`, expect the action to have restored those paths from the base branch, with the PR's copies parked in `.claude-pr/`.

**Cause 4 (errored despite completing)** — when `subtype: "success"` and `is_error: true` appear together, open [references/errored-despite-completing.md](references/errored-despite-completing.md) for the full signature, the grep, and the rerun-once rule.

**Cause 5 (bot-actor refusal)** — when the step fails with no execution file and the log says `non-human actor`, open [references/bot-actor-refusal.md](references/bot-actor-refusal.md) for the approval-hold mechanism, the `allowed_bots` fix, and a scan that counts these refusals across a repo's failed runs.

## Cause 3 — a real finding the check cannot publish

These workflows are told `Leave a PR comment with findings` but are granted no
comment tool, so every attempt is denied and the prose is discarded — while
`fail-on-critical` still fails the build off the count in `structured_output`.
The result is a gate that **blocks a merge on a finding nobody can read.**

```sh
gh run view --job <job-id> --log | grep -E '"is_error"|"subtype"|permission_denials_count|critical security'
gh pr view <n> --json comments --jq '.comments | length'    # 0 = it could not publish
gh api repos/<o>/<r>/check-runs/<job-id> --jq .output        # all null = nothing to read
```

`permission_denials_count` in double digits is the signature: the model retries
the blocked call, which also burns budget.

**Do not treat an unreadable finding as a false positive.** Read the analyzed
files yourself against the check's own category list. The finding is often in
*pre-existing* code the scan read alongside the diff — but not always.

> Evidence (2026-08, pal-mcp-server#76): three `owasp / scan` runs reported
> 1, then **2**, then 1 criticals — the middle one on a byte-identical commit —
> with 8/6/13 denials, $5.44 total, and zero comments. The finding was real:
> `estimate_file_tokens` stat'd caller-supplied paths with no validation, and a
> change in that same PR had just started reporting per-file sizes in the
> rejection — turning it into an existence-and-size oracle for the files
> `is_dangerous_path` protects (`/etc/passwd` read back as 2,669 tokens).
> Found only by reading the code. Fixed in laurigates/.github#47/#48.

**The count is not stable.** Same commit, different answer. Never treat a
delta between runs as evidence a fix worked.

## The trap under all five: a check that never ran looks exactly like a pass

Before using a sibling PR as a "it's green there" control, check the
**duration**. These workflows carry `file-patterns` filters, so a PR touching
no matching files completes in **4–6 seconds** having analyzed nothing — and
reports `pass`.

```sh
gh pr checks <n> | grep -E "owasp|code-smell"            # 4s pass = skipped, not clean
gh run list --workflow security.yml --branch main -L 5   # empty = PR-triggered only, no main baseline
```

A green tick from a skipped run is not a control. This is
`never-fabricate-test-identifiers.md`'s known-good control applied to CI: if
the "passing" comparison never executed, you have no baseline, and
`pr-merge-hazards.md`'s merge-over-red test ("same check already fails on
`main`") cannot be satisfied.

### No history at all: the workflow has ≤1 historical run

The control above presumes some earlier run exists. A newly added workflow may
have none, and its only run can be the failing one:

```sh
gh run list --workflow <file>.yml -L 12   # only the failing run, or nothing
```

When the workflow has ≤1 historical run, state it in the triage: no baseline exists,
so "is this normal for this check?" cannot be answered from history. An empty
`gh run list` reads as *nothing to see*; it means there is nothing to compare
against. Rerunning the identical commit then becomes the primary discriminator
rather than a follow-up (a deterministic failure repeats, a flake does not),
alongside reading the changed files against the check's own criteria.

> Evidence (2026-09-22, thelma#1524): `a11y-wcag.yml` had exactly one run in
> its history, the failing one. The rerun passed, and the changed components
> already carried `aria-label`, `aria-hidden` and `sr-only`, so a genuine
> Level A finding was implausible.

## When it bites

- Any PR large enough that a per-file AI reviewer can't finish in its turn
  budget — refactors, new-feature slices, multi-file guards (the rotating-failure
  example in [references/budget-exhaustion.md](references/budget-exhaustion.md) was 16 files).
- Repos that later mark these AI checks **required** — there, the flake
  *does* wedge the merge, which makes raising `max_turns` urgent rather than
  cosmetic.
- Any security-category scan whose red you are tempted to wave through on the
  strength of green deterministic gates. Cause 3 looks identical from the
  outside and is exactly where that reflex is most expensive.

## Rationale

A red check on valid code is worse than no check: it reads as a real finding,
so it pulls a reviewer into chasing a non-existent defect and erodes trust in
the AI-review signal. But the inverse error is worse still — treating every
AI-review red as flakiness waves through the findings that are real and merely
unpublishable. Ruling out the bot-actor refusal, then reading `subtype`,
`is_error` and the finding count together, separates all five. Same instinct as
`github-actions-plugin:multirepo-ci-cd`: diagnose against what CI actually
did (read the run), not against the surface red.

## Related

- [REFERENCE.md](REFERENCE.md) — the *green* runaway: a `synchronize`-triggered review loop with no round counter, why draft does not stop it, the kill switches and their blast radius, and where the per-run cost actually lives
- `.claude/rules/pr-merge-hazards.md` §4 — `UNSTABLE` vs `BLOCKED`, and the two
  checks required before merging over red
- `laurigates/.claude/rules/ci-cd-workflows.md` — the three *green*-but-inert
  modes of these same workflows (empty secret, workflow anti-tampering, skipped
  by filter); this skill covers the *red* modes
- `~/.claude/rules/diagnose-at-the-failure-point.md` — measure at the failure
  point rather than accepting the framing the error hands you
- `github-actions-plugin:multirepo-ci-cd` — portfolio-wide CI diagnosis discipline

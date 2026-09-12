---
name: ai-review-max-turns
description: "A Claude-powered CI review check reports red. Use when triaging it, to separate a genuine finding the check could not publish from turn-budget exhaustion — read is_error first, never the red X."
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
created: 2026-09-02
modified: 2026-09-12
reviewed: 2026-09-12
---

# A Red AI-Review CI Check Has Three Very Different Causes — Separate Them Before Acting

A growing class of CI checks are **Claude-powered reviewers** — a workflow
that runs the Claude Code action over the PR diff and reports findings as a
pass/fail check. They are usually a family of `reusable-quality-*`,
`reusable-security-*`, and `reusable-a11y-*` workflows, surfaced on the PR as
checks named `typescript / analyze`, `secrets / scan`, `owasp / scan`,
`aria / analyze`, `wcag / analyze`, and the like.

They go red for three reasons that demand **opposite** responses. Reading one
as another is the whole hazard:

| Cause | Tell | Response |
|---|---|---|
| **Budget exhaustion** — the run died mid-flight | `error_max_turns` in the log; `is_error: true` | Ignore the failure; it says nothing about the code |
| **Turn-ceiling overrun** — the run *finished*, the wrapper failed the job | `is_error: false`, `subtype: "success"`, **no** `Found N` line, and `##[error]Claude reported a successful result after N turns, exceeding the configured maximum of M` | Ignore the failure; the scan completed and found nothing |
| **A real finding it could not publish** | `is_error: false`, `subtype: "success"`, a `::error::Found N …` line, **and no PR comment** | Investigate the code by hand — the check found something |

> **The law: the red X is never the discriminator.** `is_error` separates a run
> that *died* from one that *finished*, but it does not separate the two
> finished cases — both read `is_error: false`, `subtype: "success"`. Between
> those, the **finding count** decides: a `Found N` line means the check is
> trying to tell you something through a blocked channel; its absence alongside
> a turn-count error means the wrapper failed a scan that had nothing to say.

Read `is_error` first, then the finding count. Stopping at `is_error` sends a
turn-ceiling overrun to the hand-audit response, which is the same wasted
investigation this skill exists to prevent.

Read the subtype before forming any theory:

```sh
url=$(gh pr checks <pr> -R <owner>/<repo> --json name,link \
  --jq '.[]|select(.name=="<check>")|.link')
runid=$(echo "$url" | sed -E 's#.*/runs/([0-9]+)/.*#\1#')
gh run view "$runid" --log-failed 2>&1 | grep -iE '"is_error"|"subtype"|error_max_turns|num_turns'
```

## Cause 1 — budget exhaustion (`error_max_turns`)

On a large diff these jobs exhaust their per-run **turn budget** and fail with
`subtype: error_max_turns` / `is_error: true` — a red ❌ that is infra
flakiness, not a real finding.

### The tell: the failing set *rotates* across re-runs

The defining signature — and the thing that distinguishes budget exhaustion
from a genuine defect — is that **re-running the same commit fails a
*different subset* of the AI jobs each time**:

> Measured 2026-08 on a 16-file / ~1150-line PR, two runs of the *same*
> commit: run 1 failed only `aria / analyze`; run 2 passed `aria` but
> failed `typescript`, `secrets`, and `owasp`. All four logs showed
> `error_max_turns` at `num_turns` 6–7. Deterministic gates (biome, knip,
> conventional-commits, deps/audit, and the real `wcag / analyze`) passed
> every run; the PR's full local test suite + build were green throughout.

A real code defect fails the *same* check deterministically. A rotating
failure set across re-runs is budget exhaustion — the scheduler gets through a
different subset of the AI jobs before the turn cap each time.

### What to do (and not do)

- **Do not blind-rerun.** A re-run re-trips with a *different* rotating
  subset — it never converges, and it just burns AI-action cost. One rerun to
  observe the rotation is enough to diagnose; after that, stop.
- **Do not chase the "finding."** There is none — the job died before
  finishing. Reading the partial log for "what it flagged" is wasted effort.
- **Check whether it actually blocks — read `mergeStateStatus`, don't assume.**
  `gh pr view <n> --json mergeable,mergeStateStatus`: `UNSTABLE` means the
  failing check is present but **not required**, so a plain `gh pr merge`
  works; `BLOCKED` means it is required and the merge is refused. Where it is
  `UNSTABLE`, merge on the strength of the deterministic gates + local
  verification (see `git-plugin:git-merge-hazards` for the two checks a
  merge-over-red needs).
- **Fix the root cause upstream, once.** The budget is too low for large
  diffs. Raise `max_turns` on the reusable workflow (or expose it as an input
  and bump callers — `reusable-claude.yml` already defaults to 30), narrow
  `file-patterns`, gate on `max-diff-lines`, or have `error_max_turns` post a
  neutral continuation status instead of a hard fail. Tracked in
  `ForumViriumHelsinki/.github#79`.

## Cause 2 — turn-ceiling overrun on a run that succeeded

Distinct from Cause 1: nothing died. The model returned a normal successful
result, and the *action wrapper* then failed the job because the turn count
exceeded `--max-turns`. The scan's own verdict is discarded along with it.

```sh
gh run view --job <job-id> -R <o>/<r> --log | grep -E '"is_error"|"subtype"|"num_turns"|exceeding the configured maximum'
```

```
"subtype": "success",
"is_error": false,
"num_turns": 53,
##[error]Claude reported a successful result after 53 turns, exceeding the configured maximum of 50
```

Nondeterministic in exactly the way Cause 1 is — same check, same tree,
different turn count. Do not read a pass on the next run as evidence a change
fixed anything.

> Evidence (2026-08-28, pal-mcp-server#87): `secrets-scan / scan` passed, then
> failed after a rebase that changed no scanned content, at `num_turns: 53`
> against a max of 50 with `permission_denials_count: 6` and no finding. It
> passed again on the next push. The diff was comment-only edits to
> `.env.example`; the scan had nothing to report either time.

The `permission_denials_count` interaction from Cause 3 applies here too: denied
tool calls get retried, and the retries are what push a scan over the ceiling.
So a high denial count is a cause of this failure, not a signal about the code.

**Fix it upstream**, not in your PR — raise `--max-turns`, or grant the tool the
scan keeps being denied. Re-running just re-rolls the count.

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

## The trap under all three: a check that never ran looks exactly like a pass

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

## When it bites

- Any PR large enough that a per-file AI reviewer can't finish in its turn
  budget — refactors, new-feature slices, multi-file guards (the rotating-failure
  example above was 16 files).
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
unpublishable. One `grep` for `is_error` and the finding count separates all
three. Same instinct as
`github-actions-plugin:multirepo-ci-cd`: diagnose against what CI actually
did (read the run), not against the surface red.

## Related

- `.claude/rules/pr-merge-hazards.md` §4 — `UNSTABLE` vs `BLOCKED`, and the two
  checks required before merging over red
- `laurigates/.claude/rules/ci-cd-workflows.md` — the three *green*-but-inert
  modes of these same workflows (empty secret, workflow anti-tampering, skipped
  by filter); this skill covers the *red* modes
- `~/.claude/rules/diagnose-at-the-failure-point.md` — measure at the failure
  point rather than accepting the framing the error hands you
- `github-actions-plugin:multirepo-ci-cd` — portfolio-wide CI diagnosis discipline

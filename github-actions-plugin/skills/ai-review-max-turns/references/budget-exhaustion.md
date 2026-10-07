# AI Review — Cause 1: Budget Exhaustion

Detail for the first row of the four-causes table in [SKILL.md](../SKILL.md).

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

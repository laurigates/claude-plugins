# Blueprint Autonomy Level 3 — Reference

Detailed reference for `/blueprint:autonomy-level3`. Design source:
[`docs/adrs/0020-blueprint-autonomy-levels.md`](../../../docs/adrs/0020-blueprint-autonomy-levels.md)
(Options Considered #3). Tracking issue: laurigates/claude-plugins#2005.

## The level model (recap)

| Level | Runs automatically | Rail |
|-------|--------------------|------|
| 0 | nothing | — |
| 1 | deterministic due tasks; on-change syncs | SessionStart/PostToolUse hooks + `blueprint-autorun.sh` |
| 2 | + agent-judgment due tasks in-session; auto-draft WO proposals | `/blueprint:autopilot` |
| **3** | **+ out-of-band cron runs; approved-WO execution → PRs** | **GitHub Actions + `claude-code-action`** |

Level 3 is the only rung that runs with **no session open**. It is opt-in per
repo because headless execution quality, the loop-integrity machinery, and the
run budgets all only make sense once a repo genuinely wants unattended
execution — this repo dogfoods at level 1 and cannot exercise it.

## Managed files

| Installed path | Source (plugin) | Role |
|----------------|-----------------|------|
| `.github/workflows/blueprint-autorun.yml` | `templates/blueprint-autorun.workflow.yml` | Daily scheduled pipeline |
| `.github/workflows/blueprint-wo-execute.yml` | `templates/blueprint-wo-execute.workflow.yml` | Approved-WO executor |
| `.github/blueprint/blueprint-wo-guard.sh` | `scripts/blueprint-wo-guard.sh` | Level-3 gate + budget + stuck ceiling |
| `.github/blueprint/blueprint-wo-packet.sh` | `scripts/blueprint-wo-packet.sh` | Untrusted-issue-body WO packet parser |
| `.github/blueprint/blueprint-autorun.sh` | `scripts/blueprint-autorun.sh` | Deterministic due-task runner (level 1 script, reused) |
| `.github/blueprint/get-automation-config.sh` | `scripts/get-automation-config.sh` | Manifest automation-block reader |

The scripts are the source of truth in the plugin; a re-run of the skill
re-syncs any drift (`--check` reports it). Per `scaffold-fix-backport`, fix a
bug in the plugin script/template, not in a consumer's copy.

## The manifest gate + budgets

Additive fields under `automation` in `docs/blueprint/manifest.json` (format
3.4.0+). Everything defaults off / conservative, so a level-1 repo is unaffected.

```json
{
  "automation": {
    "autonomy_level": 3,
    "work_orders": {
      "auto_execute": true,
      "max_per_day": 3,
      "max_cycles": 3
    }
  }
}
```

| Field | Default | Gates |
|-------|---------|-------|
| `automation.autonomy_level >= 3` | `0` | both workflows (autorun + executor) |
| `automation.work_orders.auto_execute` | `false` | the executor only |
| `automation.work_orders.max_per_day` | `3` | orders executed per calendar day |
| `automation.work_orders.max_cycles` | `3` | attempts on ONE order before "stuck → human" |

`blueprint-wo-guard.sh` emits a deterministic `PROCEED=true|false` + `REASON=`
(`autonomy_level_below_3`, `auto_execute_disabled`, `daily_budget_exhausted`,
`stuck_max_cycles_reached`, …). The dynamic counts (`--ran-today`, `--attempts`)
are computed in-workflow via `gh` from `blueprint/wo-*` PR head branches (by
`startswith`, and **fail-closed**: an unreadable PR history HALTs rather than
defaulting the budget to 0), so no extra state store is needed.

### Required: default-branch protection

The `execute` job runs a model with broad `Bash` + `contents: write` — it must,
to run the consumer's arbitrary test suite and push its work branch — and
GitHub's built-in token cannot be ref-scoped to `blueprint/wo-*`. So the
"human PR review is the final gate" guarantee is **not** self-enforcing; it
depends on the consumer protecting the default branch (require PR review,
restrict pushes, disallow force-push/self-merge). `/blueprint:autonomy-level3`
prints this as a REQUIRED activation step. The workflow adds defense-in-depth
(a provenance gate refusing non-pipeline issues; a prompt prohibition on
pushing to / merging into the default branch), but branch protection is the
load-bearing control.

## Loop integrity (`.claude/rules/loop-integrity.md`)

| Pillar | How level 3 meets it |
|--------|----------------------|
| **Independent stop condition** | The executing agent never certifies "done". Two independent judges: the PR's **CI suite** (mechanical) and the `verify` job — a **fresh** `claude-code-action` invocation that did not write the code and is briefed to ground each success criterion in execution evidence. |
| **Compact state packet each iteration** | The executor posts an issue comment per iteration carrying: **objective / ref (branch+base) / files in scope / exit condition / verifier result (last test run) / changed-since**. A context-free successor (or human) can resume from it. |
| **Bounded runaway** | `max_per_run` / `max_per_day` caps + the `max_cycles` stuck ceiling ("same order attempted N× → surface to human"). |

## Security baseline (`.claude/rules/github-actions-security.md`)

| Item | How |
|------|-----|
| Least-privilege `GITHUB_TOKEN` | Top-level `permissions: contents: read`; each job escalates only what it needs (`issues: write`, `pull-requests: write`, `contents: write`). No `id-token: write` — auth is the static `CLAUDE_CODE_OAUTH_TOKEN` (no OIDC), so it is not granted. |
| Script-injection indirection | The **untrusted** issue body is bound to `env: WO_ISSUE_BODY`, written to `wo-body.md`, and parsed by `blueprint-wo-packet.sh` — never interpolated `${{ … }}` into a `run:` line. |
| Prompt-injection defense | `blueprint-wo-packet.sh` emits only booleans/counts/a sanitized `WO-NNN` id — never raw body text — so a body cannot inject `KEY=VALUE`/`PROCEED=` lines a downstream shell would misparse. The executing agent reads `wo-packet.md` as **task data** and is told not to merge/push-to-default-branch. Because it still holds broad write, the real containment is the **provenance gate** (non-pipeline issues refused) + **human approval** + **default-branch protection** (see above), not the "task data" instruction alone. |
| Pinned actions | `actions/checkout@v6`, `anthropics/claude-code-action@v1` — the same pins this repo's own workflows use. |
| Model / effort | Every `claude-code-action` invocation pins `--model opus` + explicit `--effort` (`medium` for autorun/verify, `high` for execution) per `.claude/rules/workflow-model-effort.md`. |

## The two workflows at a glance

**`Blueprint: Autorun`** (schedule + `workflow_dispatch`): `gate` (HALT below
level 3) → `deterministic` (run `blueprint-autorun.sh`, open a PR for the
manifest writeback — never push to the default branch) + `agent-tasks` (a fresh
`claude-code-action` runs due agent-judgment tasks and drafts `work-order-draft`
proposal issues, deduped and capped, promotion stays the human
`/blueprint:work-order --from-issue N` act).

**`Blueprint: Execute approved work order`** (`issues: labeled`,
`work-order-approved`): `gate` (label + level-3 + `auto_execute` + budget +
stuck ceiling) → `execute` (parse the untrusted issue body, implement TDD-style
on `blueprint/wo-<N>`, open a PR `Fixes #N`, post state-packet comments) →
`verify` (the independent fresh-reviewer job). Human PR review is the final gate.

## Related

- `.claude/rules/loop-integrity.md` — the independent-verifier + state-packet contract
- `.claude/rules/github-actions-security.md` — the least-privilege + injection baseline
- `.claude/rules/workflow-model-effort.md` — the `--model opus` + explicit `--effort` standard
- `blueprint-plugin:blueprint-autopilot` — the level-2 in-session executor this extends
- `blueprint-plugin:blueprint-work-order` — the human-only WO promotion (`--from-issue N`)

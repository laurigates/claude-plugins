---
name: blueprint-autonomy-level3
description: "Install blueprint autonomy level 3 (ADR-0020): scheduled-autorun + approved-work-order-execution GitHub workflows. Use when enabling out-of-band blueprint automation in a repo."
args: "[--check]"
argument-hint: "--check to audit an already-scaffolded repo for drift"
allowed-tools: Bash(bash *), Bash(cp *), Bash(mkdir *), Bash(diff *), Bash(gh label *), Read, Write, Glob, Grep, TodoWrite
created: 2026-07-18
modified: 2026-07-18
reviewed: 2026-07-18
---

# /blueprint:autonomy-level3

Scaffold the ADR-0020 **autonomy level 3** pipeline — the highest rung of the
blueprint automation model — into a consumer repo: two GitHub Actions workflows
plus the deterministic scripts they call. Level 3 runs blueprint **out of band**
(scheduled cron + a label-triggered executor), where levels 1–2 only run
in-session. This repo (claude-plugins) dogfoods at level 1 and cannot exercise
level 3 itself; a consumer repo opts in.

## When to Use This Skill

| Use this skill when... | Use instead when... |
|------------------------|---------------------|
| A repo wants blueprint bookkeeping + work-order proposals to run on a schedule (no session open) | The in-session ambient pass is enough → `/blueprint:autopilot` (level 2) |
| A repo wants human-approved work orders executed into PRs automatically | You want to create/execute a work order by hand → `/blueprint:work-order`, `/blueprint:prp-execute` |
| Auditing whether an already-scaffolded level-3 repo has drifted from the current templates (`--check`) | Setting the autonomy level itself → edit `docs/blueprint/manifest.json` |

## Context

- Automation config: !`bash ${CLAUDE_SKILL_DIR}/../../scripts/get-automation-config.sh`
- Blueprint present: !`find . -maxdepth 3 -path '*/docs/blueprint/manifest.json'`
- Autorun workflow already installed: !`find . -maxdepth 3 -path '*/.github/workflows/blueprint-autorun.yml'`
- WO-execute workflow already installed: !`find . -maxdepth 3 -path '*/.github/workflows/blueprint-wo-execute.yml'`

## Parameters

Parse `$ARGUMENTS`:

- `--check`: audit-only. Diff the installed workflows/scripts against the plugin
  templates and report `PRESENT` / `DRIFT` / `ABSENT` per file. Make no changes.
- _(no args)_: scaffold/install (idempotent — overwrites the managed files with
  the current template versions, re-syncing any drift).

## Execution

Execute this level-3 scaffold.

### Step 1: Verify preconditions

If the Context shows no `docs/blueprint/manifest.json`, stop with:
`Blueprint not initialized — run /blueprint:init first.` Nothing else.

Read `AUTONOMY_LEVEL` and `WO_AUTO_EXECUTE` from the Context automation config —
these are the activation gate, reported in Step 4. Scaffolding does **not** flip
them; the workflows stay dormant (the `blueprint-wo-guard.sh` gate HALTs) until
the human sets them.

### Step 2 (`--check` mode): audit drift, then stop

For each managed file, `diff` the installed copy against the plugin source and
report one line each:

```bash
for pair in \
  ".github/workflows/blueprint-autorun.yml|${CLAUDE_SKILL_DIR}/../../templates/blueprint-autorun.workflow.yml" \
  ".github/workflows/blueprint-wo-execute.yml|${CLAUDE_SKILL_DIR}/../../templates/blueprint-wo-execute.workflow.yml" \
  ".github/blueprint/blueprint-wo-guard.sh|${CLAUDE_SKILL_DIR}/../../scripts/blueprint-wo-guard.sh" \
  ".github/blueprint/blueprint-wo-packet.sh|${CLAUDE_SKILL_DIR}/../../scripts/blueprint-wo-packet.sh" \
  ".github/blueprint/blueprint-autorun.sh|${CLAUDE_SKILL_DIR}/../../scripts/blueprint-autorun.sh" \
  ".github/blueprint/get-automation-config.sh|${CLAUDE_SKILL_DIR}/../../scripts/get-automation-config.sh"; do
  dst="${pair%%|*}"; src="${pair##*|}"
  if [ ! -f "$dst" ]; then echo "ABSENT  $dst"
  elif diff -q "$src" "$dst" >/dev/null 2>&1; then echo "PRESENT $dst"
  else echo "DRIFT   $dst"; fi
done
```

Report the table and stop. `DRIFT`/`ABSENT` → advise re-running without
`--check` to re-sync (the templates are the source of truth; per
`scaffold-fix-backport`, a fix to the plugin template re-lands here on re-run).

### Step 3 (install mode): copy templates + scripts

```bash
mkdir -p .github/workflows .github/blueprint
cp "${CLAUDE_SKILL_DIR}/../../templates/blueprint-autorun.workflow.yml"   .github/workflows/blueprint-autorun.yml
cp "${CLAUDE_SKILL_DIR}/../../templates/blueprint-wo-execute.workflow.yml" .github/workflows/blueprint-wo-execute.yml
cp "${CLAUDE_SKILL_DIR}/../../scripts/blueprint-wo-guard.sh"    .github/blueprint/blueprint-wo-guard.sh
cp "${CLAUDE_SKILL_DIR}/../../scripts/blueprint-wo-packet.sh"   .github/blueprint/blueprint-wo-packet.sh
cp "${CLAUDE_SKILL_DIR}/../../scripts/blueprint-autorun.sh"     .github/blueprint/blueprint-autorun.sh
cp "${CLAUDE_SKILL_DIR}/../../scripts/get-automation-config.sh" .github/blueprint/get-automation-config.sh
```

The workflows call the deterministic scripts from `.github/blueprint/` (they are
blueprint-plugin scripts, not present on a bare CI runner otherwise). The
agent-judgment halves invoke `anthropics/claude-code-action` with the
claude-plugins marketplace + `blueprint-plugin` enabled.

### Step 4: Report activation requirements (do not perform them)

Print a receipt listing exactly what the human must do to activate — scaffolding
alone leaves everything dormant:

1. **Manifest gate** — set in `docs/blueprint/manifest.json`:
   - `automation.autonomy_level: 3` (both workflows), and
   - `automation.work_orders.auto_execute: true` (executor only).
   Report the *current* values (from Context) and whether the gate is met.
   Optional budget caps default to `max_per_run 1` / `max_per_day 3` /
   `max_cycles 3` — see [REFERENCE.md](REFERENCE.md).
2. **Secret** — `CLAUDE_CODE_OAUTH_TOKEN` in the repo's Actions secrets.
3. **Labels** — `work-order-draft` (proposals) and `work-order-approved` (the
   human relabel that triggers execution). Offer to create the approval label:
   `gh label create work-order-approved --description "Blueprint level-3: execute this approved work order (ADR-0020)" --color 0E8A16`.
4. **Enable the plugin in CI** — the caller repo needs `blueprint-plugin`
   available to `claude-code-action` (marketplace + `.claude/settings.json`).

### Step 5: Summarize the safety model

State the guarantees in the receipt so the human understands what they are
enabling (full detail in [REFERENCE.md](REFERENCE.md)):

- **Gating** — `blueprint-wo-guard.sh` HALTs every run unless
  `autonomy_level >= 3` (autorun) and additionally `auto_execute: true`
  (executor). Both default off.
- **Human approval stays required** — a work order executes only after a human
  relabels its proposal issue to `work-order-approved`; the PR is the final gate.
- **Budgets + stuck ceiling** — per-run/per-day caps and "same order attempted
  `max_cycles`× → stuck → surface to human" (loop-integrity).
- **Independent verifier** — the executing agent never certifies its own work;
  the PR's CI suite plus a **fresh** reviewer agent (the `verify` job) judge
  "done", and each iteration writes a state-packet issue comment.
- **Untrusted-input safe** — the issue body is the WO carrier and is untrusted;
  it is bound to an env var, written to a file, and parsed by
  `blueprint-wo-packet.sh` — never interpolated into a shell command.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Gate + level check | `bash <plugin>/scripts/get-automation-config.sh` |
| Drift audit (already installed) | `/blueprint:autonomy-level3 --check` |
| Verify a packet locally | `bash <plugin>/scripts/blueprint-wo-packet.sh --body-file <issue-body>` |
| Dry-run the gate | `bash <plugin>/scripts/blueprint-wo-guard.sh --mode wo-execute --ran-today N --attempts N` |

For the full workflow templates, the manifest gate/budget schema, the
state-packet fields, and the security rationale, see [REFERENCE.md](REFERENCE.md).

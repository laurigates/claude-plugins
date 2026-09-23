---
created: 2026-02-26
modified: 2026-09-23
reviewed: 2026-09-23
paths:
  - "**/skills/**"
  - "scripts/**"
---

# Regression Testing for Script Checks

When you fix a skill quality issue, a context command bug, or a skill body corruption problem, you **MUST** add a regression check to prevent the same issue from recurring.

## Rule

> **Every bug fix to a SKILL.md file must be accompanied by a new regression check in the appropriate script.**

This ensures the CI catches the same class of problem in any future skill, not just the one you just fixed.

## Semantic vs. syntactic gates

A regression check has two layers, and both matter:

| Gate | Asks | Catches | Misses |
|------|------|---------|--------|
| **Syntactic** | Does the file parse? Is the YAML schema valid? Does the frontmatter have the required fields? | Truncated files, broken YAML, missing fields | A description that parses but no longer triggers auto-invocation; an error enum that compiles but drops a user-facing code; a response shape that validates but omits a contract field |
| **Semantic** | Does the artefact still carry the **intent** it was designed for — the trigger phrase, the contract field, the invariant the consumer depends on? | Bulk-edit drift where an agent "tightens" prose and silently breaks downstream matchers | Pure parse failures (covered by the syntactic gate) |

Syntactic-only gates are easy to write and feel like coverage, but bulk-edit agents reliably produce syntactically-valid output that violates semantic invariants. The auto-invocation matcher does not care that the YAML parses; it cares that the literal trigger phrase is present.

**Canonical example (issue #1278):** `scripts/audit-skill-descriptions.py --strict-all` is a semantic gate — it checks that auto-invokable descriptions contain the literal `Use when` substring (the matcher's only trigger). In a 68-skill bulk edit, four of six refactor subagents replaced `Use when...` with `Use to...` / `Use for...`. Every output was YAML-valid; agent self-reports said "done"; pre-edit reviews approved the diffs. The semantic gate fired:

> `68 auto-invokable skills need description fixes / Audited 706 skills across 41 plugins`

Without it, all 68 unmatchable descriptions would have shipped silently.

### Required pattern

When you author a regression script for a class of bulk-edit risk (descriptions, error enums, exit codes, response shapes, format versions), the script **MUST** encode the *semantic invariant*, not just the *syntactic shell*. A frontmatter parser is not enough; a `Use when` substring check is.

### Script-design checklist

Your regression script should answer:

| Question | Why |
|----------|-----|
| (a) Does the artefact still parse? | Syntactic floor — necessary, not sufficient |
| (b) Does it still carry the trigger / contract / invariant it was designed for? | The semantic question that bulk-edit agents reliably break |
| (c) Is the failure message actionable enough that an agent can self-repair? | A pre-commit failure that emits `--json` lets a follow-up agent enumerate paths, repair, and re-run without human relay |

The audit script in this repo is the canonical example — it pairs a human report with `--json` output for scriptable repair. PR #1314 bakes that same audit into `agents-plugin/agents/refactor.md` as a mandatory post-pass, so the refactor agent self-verifies before reporting completion.

## Where to Add the Check

| Problem Type | Add Check To |
|-------------|-------------|
| Context command antipattern (API calls, shell operators) | `scripts/lint-context-commands.sh` |
| Skill body structure corruption (spurious headings, leaked frontmatter) | `scripts/plugin-compliance-check.sh` → `check_skill_body()` |
| Frontmatter field missing or malformed | `scripts/plugin-compliance-check.sh` → `check_skill_frontmatter()` |
| Description fails auto-invocation matching (missing/empty, or no "Use when..." trigger) | `scripts/plugin-compliance-check.sh` → `check_skill_descriptions()` (delegates to `scripts/audit-skill-descriptions.py`) |
| Skill size exceeding limit | `scripts/plugin-compliance-check.sh` → `check_skill_size()` |
| Blueprint upgrade target drift (migrations added without updating `blueprint-upgrade`) | `scripts/check-blueprint-upgrade-target.sh` |
| Hyphenated taskwarrior tag names in plugin docs (parser silently swallows them) | `scripts/lint-taskwarrior-tags.sh` |
| Plugin agent body missing `## Tool Selection` section (agents re-discover hook-blocked idioms) | `scripts/check-agent-tool-selection.sh` |
| A looping skill loses its independent stop condition or compact-state-packet fields (checkpoint plan drops `Verifier result`/`Changed since last run`/`Exit condition`/the independent-verifier step, or a sibling skill loses its `loop-integrity.md` cross-reference) | `scripts/check-loop-integrity.sh --strict` (+ `scripts/tests/test-check-loop-integrity.sh`); wired into `.pre-commit-config.yaml` and `plugin-pr-checks.yml` (self-test + run). See `.claude/rules/loop-integrity.md` |
| Plugin agent `model:` drifts off `opus` (a weaker delegate's output re-enters the main loop and degrades downstream work; `effort`, not `model`, is the cost lever) | `scripts/check-agent-model.sh` |
| Agent-dispatch skills lose the loud-failure contract (dispatched agents may surrender with one-word summaries) | `scripts/check-agent-failure-contract.sh` |
| A skill body names a `subagent_type` that resolves to no agent (stale rename, invented name), so every dispatch it instructs fails at "Agent type not found" | `scripts/check-subagent-types.sh` (+ `scripts/tests/test-check-subagent-types.sh`); extend `BUILTIN_SUBAGENT_TYPES` for a new harness-provided type, or `SUBAGENT_TYPE_EXCEPTIONS` for a genuinely illustrative non-dispatch |
| Skill description exceeds listing-budget length band (>200 WARN, >300 ERROR) | `scripts/plugin-compliance-check.sh` → `check_skill_descriptions()` (length axis); `audit-skill-descriptions.py --strict-length` in pre-commit + CI |
| Skill body or `allowed-tools` references an MCP tool name that the server doesn't actually expose | `scripts/lint-mcp-tool-references.sh` — extend the `denylist=()` array with the unavailable tool name and the suggested fix |
| Skill body documents an install/import for a package name that doesn't exist on its registry (npm/PyPI/crates/RubyGems/Go) — a dependency-confusion hazard | `scripts/lint-package-references.sh` — extend the `denylist=()` array with the `(ecosystem, wrong-name, fix)` triple |
| A `## Context` backtick command aborts the skill in a fresh project (writes stderr / exits non-zero on a missing file, dir, remote, or git state) — the whole class behind the regex rules above | `scripts/check-context-command-execution.sh` (semantic backstop: actually EXECUTES every published skill's Context command in a bare one-commit sandbox; `--strict` fails on any non-zero exit / non-empty stderr). No new rule needed per variant — it catches the class. Regression test: `scripts/tests/test-check-context-command-execution.sh` |
| Skill markdown ships a version pin (`uses:`/`FROM`/`image:`/`rev:`) in a shape Renovate's customManagers can't see, so it silently rots | `scripts/check-version-pin-coverage.sh` — extend the managed-form predicates **and** the matching `renovate.json` customManager together (see `.claude/rules/version-pinning.md`) |
| `.claude/settings.json` `enabledPlugins` drifts from the plugins published in `.claude-plugin/marketplace.json` (a plugin is added to the marketplace but never enabled, or a removed plugin is left enabled) | `scripts/check-enabled-plugins-drift.sh --strict` (+ `scripts/tests/test-check-enabled-plugins-drift.sh`); wired into `.pre-commit-config.yaml` and the `Plugin: Enablement drift` workflow |
| A test/hook shell script builds a throwaway repo with `VAR=$(mktemp -d)` then `git -C "$VAR"` / `git init --bare "$VAR"` / `git clone … "$VAR"` without guarding the dir — if `mktemp` fails, `$VAR` is empty and `git -C ""` falls back to the CWD, corrupting the real repo in a shared checkout (issue #1692) | `scripts/check-git-sandbox-guards.sh --strict` (+ `scripts/tests/test-check-git-sandbox-guards.sh`); file-level gate requiring every `mktemp -d` in a repo-targeting-git script to carry a guard. Python is exempt (`mkdtemp`/`tmp_path` raise, never return empty). Wired into `.pre-commit-config.yaml` |
| A `.github/workflows/*.yml` Claude invocation drifts off `--model opus`, or sets opus without an explicit `--effort` (opus defaults to `high`, forfeiting the cost savings; haiku/sonnet are weaker per the cost-economics in `.claude/rules/workflow-model-effort.md`) | `scripts/check-workflow-model.sh` (+ `scripts/tests/test-check-workflow-model.sh`); classifies invoking vs reusable-only vs no-invocation workflows and asserts opus + valid explicit effort. Wired into `.pre-commit-config.yaml` and `plugin-pr-checks.yml` |
| `session-distill` loses its deterministic substrate — the `distill-survey.sh` collector invocation, or the `--process` / `.claude/skills/` process-routing tokens | `scripts/plugin-compliance-check.sh` → `check_skill_body()` (session-distill block asserts all three tokens survive); the collector's own coverage is `session-plugin/scripts/tests/test-distill-survey.sh` |
| Blueprint level-3 workflow templates (`blueprint-plugin/templates/*.workflow.yml`, ADR-0020 / #2005) lose their model/effort, script-injection-safety, or loop-integrity invariants — they live OUTSIDE `.github/workflows/` so `check-workflow-model.sh` + `actionlint` never scan them | `scripts/check-blueprint-level3-templates.sh` (+ `scripts/tests/test-check-blueprint-level3-templates.sh`); asserts `--model opus` + explicit `--effort` per invocation, the untrusted issue body referenced exactly once (env binding), the independent `verify:` job + state-packet fields, and runs `actionlint`. The scaffold SKILL body is guarded by `plugin-compliance-check.sh` `check_skill_body()`; the gate/parser scripts by `blueprint-plugin/scripts/tests/test-blueprint-wo-{guard,packet}.sh`. Wired into `.pre-commit-config.yaml` and `plugin-pr-checks.yml` |
| The blueprint `feature-tracker.json` diverges from itself (the `statistics` block is a **cache** of the features collection) or from doc frontmatter | `blueprint-plugin/scripts/blueprint-tracker-check.sh` (+ `blueprint-plugin/scripts/tests/test-blueprint-tracker-check.sh`); recomputes `statistics`, validates the feature-status enum against `schemas/feature-tracker.schema.json`, cross-checks `tasks.*[]` membership, finds FR ids cited in `docs/**` but never minted, compares doc frontmatter status, and flags dead buckets / duplicate timestamp fields. Repo conventions come from the manifest `validation` block via `scripts/get-validation-config.sh`. Wired into `blueprint-feature-tracker-sync` + `-status` (pinned by `plugin-compliance-check.sh`) |
| The ADR collision guard misses a claimant because the number is in **frontmatter** rather than the filename, or lives in a **second** ADR directory | `blueprint-plugin/skills/blueprint-adr-validate/scripts/check-adr-numbers.sh` (widened) + `generate-adr-index.sh` (+ their `scripts/tests/`); ADR directory set comes from the manifest `validation.adr_dirs` via `get-validation-config.sh` — **not** a second config mechanism |
| A plugin agent body instructs ancestry-based branch **deletion** (`git branch --merged` piped into `git branch -d`/`-D`) — ancestry misses every squash-merged branch, so a fully-landed branch reads as unmerged and the delete runs on a known-wrong signal (the defect already fixed for `deadbranch`, #1869) | `scripts/check-agent-tool-selection.sh` — per-line shape denylist: a `git branch … --merged` command at line start, or `--merged` composed with a `branch -d`/`-D` on one line. Prose that merely *names* the command is not flagged (that is how the hazard gets taught). `BRANCH_CLEANUP_ALLOWLIST` is seeded with `experiments/claude-probe/`, which uses the broken idiom deliberately as a trap fixture; test seam `CHECK_AGENT_TOOL_SELECTION_ALLOWLIST` |
| A skill grants a bare `Bash` in `allowed-tools` but runs no shell at all — pure permission surface advertising a capability it never exercises. (The *inverse*, a bare `Bash` in a skill that does run shell, is the ratified standard and is deliberately NOT linted — see `.claude/rules/agentic-permissions.md`.) | `scripts/check-unused-bash-grant.sh` (+ `scripts/tests/test-check-unused-bash-grant.sh`). "Runs shell" = a shell-language **or unlabeled** fence with a known command (incl. `./`, `.venv/`, `<placeholder>/`, `$VAR/` prefixes), a known command in inline backticks, a sibling `scripts/` dir, a `` !`…` `` Context command, or any of those in a bundled sidecar. Markdown structure comes from `scripts/lib/extract-md-elements.py`, never a hand-rolled fence toggle (#2009). **Blocking (`--strict`) as of #2255** at both call sites; gate held at the flip (`SKILLS_SCANNED=408`, `BASH_GRANTEES=186`, `ISSUE_COUNT=0`, allowlist EMPTY), so the ratchet locks in a clean state rather than a suppressed one |
| A workflow RUNS a repo script that its own `pull_request` `paths:` filter does not match, so a PR changing only that script never runs it in CI — the guard has no CI signal for its own regressions | `scripts/check-workflow-script-triggers.sh --strict` (+ `scripts/tests/test-check-workflow-script-triggers.sh`); a workflow with no `paths:` filter is never flagged. Wired into `.pre-commit-config.yaml` and `plugin-pr-checks.yml` |
| A guard reports `STATUS=OK` / exit 0 having scanned **zero** files, because a `*/.claude/worktrees/*` prune against an absolute base matched the scan root itself (the root IS an agent worktree) | Run discovery from inside the root against **relative** paths (`cd "$proj_dir"` + `find .`), per `scripts/check-subagent-types.sh`. Then make zero-scan distinguishable: `STATUS=ERROR` + `TYPE=nothing_scanned` when the corpus should be non-empty, `SCANNED_EMPTY=true` when it is legitimately empty. Class test: `scripts/tests/test-guard-worktree-root-discovery.sh` |
| A skill body ships Mustache/Jinja/Handlebars template conditionals (`{{ if X }}` / `{{ endif }}` / `{{#if}}` / `{{/if}}`) that **nothing renders** — Claude Code has no template engine in the skill-invocation path, so every branch reaches the agent verbatim with the condition variable never bound | `scripts/check-unrendered-templates.sh` (+ `scripts/tests/test-check-unrendered-templates.sh`). Exempt structurally: Go/Helm chart templates (`{{-` / `-}}` trim markers, bare `{{ end }}`, a condition rooted at `.Values` / `$.`) and the `{{ if ... }}` ellipsis prose form. Exempt by **declaration**: a file containing the phrase `markers after substitution` is a generator template the skill instructs the agent to render and strip. Wired into `.pre-commit-config.yaml` |
| A skill grants a bare `Bash` in `allowed-tools` but runs no shell at all — pure permission surface advertising a capability it never exercises. (The *inverse*, a bare `Bash` in a skill that does run shell, is the ratified standard and is deliberately NOT linted — see `.claude/rules/agentic-permissions.md`.) | `scripts/check-unused-bash-grant.sh` (+ `scripts/tests/test-check-unused-bash-grant.sh`). "Runs shell" = a shell-language **or unlabeled** fence with a known command (incl. `./`, `.venv/`, `<placeholder>/`, `$VAR/` prefixes), a known command in inline backticks, a sibling `scripts/` dir, a `` !`…` `` Context command, or any of those in a bundled sidecar. Markdown structure comes from `scripts/lib/extract-md-elements.py`, never a hand-rolled fence toggle (#2009). Advisory on landing; `--strict` flips it to blocking once the allowlist stays empty |
| The `TaskCompleted` **agent-hook prompt** loses a verification behaviour — committed work stops counting as evidence, the base ref stops being the DEFAULT branch (`@{u}` resolves to the branch's own remote counterpart, so `BASE..HEAD` is empty on any pushed branch), the working-tree fallback disappears, scope reverts to raw `git status`, or the no-evidence block is dropped | `scripts/check-taskcompleted-verification.sh --strict` (+ `scripts/tests/test-check-taskcompleted-verification.sh`). The artefact is a prompt **string inside `plugin.json`**, not a SKILL.md, so `plugin-compliance-check.sh` `check_skill_body()` cannot reach it. Each rule is a CONCEPT with several accepted spellings, so a reword passes and a revert fails. `base_ref_hardcoded` forbids only an **unconditional** base (a bare `<branch>..HEAD` range, or `BASE=<branch>`) — a documented `git rev-parse --verify --quiet` probe of `origin/main`/`origin/master` is the correct fallback and must NOT fire (that over-match blocked the #2301 repair itself) |
| `git-stash-reminder.sh` / `git-stash-session-init.sh` lose a namespace, age-bound, or write-once invariant — a repo entered mid-session or reached through a linked worktree stops reporting genuine session stashes, or a SessionStart re-fire un-reports an already-flagged one — **or** the hook's block stops being *satisfiable*: a stash whose tree equals the working tree is reported anyway, an already-surfaced stash re-blocks forever, an `auto-checkpoint` entry is prescribed `git stash pop`, a `git stash push -u` stash's untracked payload is silently declared redundant, or `CLAUDE_HOOKS_DISABLE_GIT_STASH_REMINDER=1` stops disabling the hook (#2686) | `hooks-plugin/hooks/test-git-stash-reminder.sh` (auto-discovered via `*/hooks/test-*.sh`). Hermetic: sandboxed with `CLAUDE_STASH_BASELINE_DIR`, full `GIT_DIR` family unset per #1745, stash dates pinned to git's raw `@<epoch> <tz>` form so GNU/BSD `date` cannot diverge. Every invariant is **paired** — a false-positive case beside a true-positive one — so the suite fails both an over-reporting hook and a permanently-silent one |
| A skill's `${CLAUDE_SKILL_DIR}` / `${CLAUDE_SESSION_ID}` reaches pi's `bash` tool unset (pi substitutes nothing, so `bash "${CLAUDE_SKILL_DIR}/../../scripts/x.sh"` runs as `bash "/../../scripts/x.sh"`), or `claude-${CLAUDE_SESSION_ID:0:8}` collides between pi sessions started in the same minute because the raw UUIDv7 timestamp prefix was exported | `adapters/tests/pi-binding.test.ts` (`claude-env helpers` + the factory `tool_call` dispatch tests); run by `just adapters-test`. Resolution tiers, ambiguity and unresolved blocks, quoting, and the session-id prefix are unit-tested on `adapters/pi/claude-env.ts`; the dispatch tests fail if the `tool_call` registration is removed (mutation-checked on landing) |
| A `.github/workflows` Claude prompt tells Claude to run a Bash command that its own step's `--allowedTools` cannot reach — either no `Bash(...)` grant matches at all, or the call is granted-in-principle but cannot PREFIX match because it begins with a `for`/`while` loop, chains with `;`/`&&`/`\|\|`, or opens with a `VAR=$(...)` assignment. Each denial still burns a turn, so the two classes compound into a `--max-turns` overrun (#2493: 4 denials then RED at 42/40 turns on `workflow-model-audit`; 6 denials at 59/60 on `golden-set-evaluation`) | `scripts/check-workflow-tool-grants.sh` (+ `scripts/tests/test-check-workflow-tool-grants.sh`, whose fixtures replay the ten observed denial shapes); wired into `.pre-commit-config.yaml`, self-test auto-discovered by `test-skill-scripts.yml`. Heredoc bodies and non-shell fences are skipped — case I is the load-bearing counter-case, since the real `gh issue create --body "$(cat <<'EOF' … EOF )"` call site ships in three workflows |

## Known Regressions (Documented Bugs)

The ledger of fixed bugs and the checks that now guard them lives in
[`docs/regression-ledger.md`](../../docs/regression-ledger.md). **Append one row
at the end of its table** for every fix you guard; the file is `merge=union`, so
parallel appends merge without conflicts.

It is kept out of this rule on purpose. This rule is path-scoped to
`**/skills/**` and `scripts/**`, so it loads whole into every agent that touches
a skill or a script — and the ledger, at 513 KB, pushed eval subagents past
their context window (issue #2667). `scripts/check-context-engineering.py
--strict` now fails any rule over its per-rule size ceiling, whatever its
scoping, so this file cannot silently regrow a ledger.

## How to Add a Regression Check

### For `lint-context-commands.sh`

Add a `check_pattern` call with a descriptive rule name, a grep regex anchored to context command lines (`^- .*!\``), and a fix description. Include a regression comment referencing the PR:

```bash
# <Description of what this catches>
# Regression: <skill-name> had <description of bug> (PR #NNN)
check_pattern WARN \
  "rule-name" \
  '^- .*!`[^`]*pattern[^`]*`' \
  "fix description here"
```

Use `ERROR` for patterns that always break, `WARN` for patterns that break in some environments.

Update the comment block at the top of the file to include the new regression number.

### For `plugin-compliance-check.sh`

Add detection logic inside the appropriate `check_*` function (or create a new one). Include a regression comment:

```bash
# Detect <pattern description>
# Regression: <skill-name> had <description of bug> (PR #NNN)
```

If adding a new check function:
1. Define the function following the existing naming pattern (`check_skill_*`)
2. Add a `results_*=()` array in the status tracking section
3. Wire it into the main loop: `new_status=0; check_skill_new "$plugin" || new_status=$?`
4. Add `results_new+=("$(to_symbol $new_status)")` and `results_new+=("❌")` for missing dirs
5. Add the new column to the output table header and row
6. Add `$new_status` to the overall status loop

## Checklist for Bug Fixes

When fixing a skill-related bug:

- [ ] The original bug is fixed in the SKILL.md file
- [ ] A regression check is added to the appropriate script
- [ ] The check includes a comment referencing the PR number
- [ ] A row is appended at the end of the table in `docs/regression-ledger.md`
- [ ] The fix commit follows conventional commit format: `fix(plugin): description`

---
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
| Skill description exceeds listing-budget length band (>200 WARN, >300 ERROR) | `scripts/plugin-compliance-check.sh` → `check_skill_descriptions()` (length axis); `audit-skill-descriptions.py --strict-length` in pre-commit + CI |

## Known Regressions (Documented Bugs)

| Issue | Root Cause | Check Added | Fixed In |
|-------|-----------|-------------|----------|
| `gh repo view` in context command fails with TLS/x509 error | Uses GitHub GraphQL API; fails in proxy/offline/cert-error environments | `lint-context-commands.sh` rule `gh-api-in-context` | PR #799 |
| `name: fieldname` + `---` in skill body renders as accidental H2 heading | YAML frontmatter key leaked into markdown body; `key\n---` is a setext heading | `plugin-compliance-check.sh` `check_skill_body()` | PR #799 |
| `model: haiku` with `AskUserQuestion` causes empty silent prompts | Haiku model doesn't reliably format AskUserQuestion tool calls; prompts return empty | `plugin-compliance-check.sh` `check_skill_frontmatter()` | PR #879 |
| `model: haiku` for any skill — quality risk vs Sonnet not justified | Cost savings vs Sonnet are modest while quality risk applies to non-interactive skills too. Sonnet is the floor; Opus reserved for deep reasoning. | `plugin-compliance-check.sh` `check_skill_frontmatter()` (broadened beyond AskUserQuestion) | PR #TBD (model-parameter restoration) |
| `test -f path && echo "EXISTS" \|\| echo "MISSING"` in context command fails | `test -f` requires Bash permission; `&&`/`\|\|` are blocked shell operators; `2>/dev/null` and pipes are blocked | `lint-context-commands.sh` rules `test-in-context`, `shell-operator-and`, `shell-operator-or`, `redirection-operator`, `pipe-operator` | issue #899 |
| `grep ... package.json pyproject.toml requirements.txt` fails when files missing | grep writes to stderr when hardcoded filenames don't exist; non-JS/Python projects lack these files | `lint-context-commands.sh` rule `grep-hardcoded-multi-file` | PR #TBD |
| `find ~/.claude/plugins ...` blocked by sandbox security | `find` on home-directory paths (`~/`, `$HOME`) is outside allowed working directories | `lint-context-commands.sh` rule `home-dir-in-context` | PR #TBD |
| `jq ... .claude/settings.json` fails when file missing | jq writes to stderr when target file doesn't exist; `2>/dev/null` is blocked in context commands | `lint-context-commands.sh` rule `jq-on-optional-settings` | PR #TBD |
| `Bash(test *), Bash(jq *)` etc. causes ~20 approval prompts | Shell utility patterns in `allowed-tools` force inline bash that can't be allowlisted; each compound command needs individual approval | `plugin-compliance-check.sh` `check_bash_patterns()` | PR #TBD |
| `blueprint-{generate,derive}-rules` writes hardcoded `.claude/rules/` and clobbers hand-authored rules | SKILL.md hardcoded the output directory; no `structure.generated_rules_path` field | `plugin-compliance-check.sh` `check_skill_body()` (blueprint rules-path check) | issue #1043 |
| `/blueprint:upgrade` reports v3.2.0 as latest after v3.3 migration was added | `blueprint-upgrade/SKILL.md` hardcodes target version; PR #1026 added `migrations/v3.2-to-v3.3.md` without updating the upgrade skill | `check-blueprint-upgrade-target.sh` compares highest migration target to `blueprint-upgrade/SKILL.md` | PR #TBD |
| Skills with capability-list descriptions ("Check and configure X") never auto-invoke | Claude matches `description` against user intent; without "Use when..." and trigger phrases the matcher never fires. 133/325 skills were affected at baseline. | `plugin-compliance-check.sh` `check_skill_descriptions()` (warns on NO_TRIGGER for auto-invokable skills; errors on MISSING/EMPTY); `audit-skill-descriptions.py --strict` in pre-commit | PR #TBD |
| Skill descriptions drift past the listing-budget target band, eating context-window share that's capped at `skillListingBudgetFraction × context` (default 1%) per Claude Code 2.1.129+. The May 2026 tightening pass brought every description below 250 chars — without an automated gate the band silently re-inflates as new skills land. | The audit tool only checked trigger-phrase presence; description **length** was never linted. 12 skills sat in the 201-250 char WARN band post-tightening (1 plugin at 205, git-plugin × 6, typescript-plugin × 5). | `plugin-compliance-check.sh` `check_skill_descriptions()` extended with a length axis (WARN 201-300 → recommendation, ERROR >300 → block); `audit-skill-descriptions.py --strict-length` (default fails on >300; `--warn-on-200` flag fails on >200) wired into `.pre-commit-config.yaml` and `.github/workflows/lint-context-commands.yml` | PR #TBD |
| `/feedback-session` fails in a repo without a git remote with "Shell command failed ... no git remotes found" | `gh issue list` / `gh pr list` without `-R` require a configured remote; stderr from a context backtick aborts skill invocation. 5 user-invocable skills (`feedback-session`, `workflow-dev`, `git-commit-push-pr`, `git-issue-manage`, `git-issue`) had this pattern. | `lint-context-commands.sh` rule `gh-list-needs-remote` (skips matches that already pass `-R owner/repo`) | PR #TBD |
| `friction-learner` auto-prescribes "Avoid plan mode for conceptual Q&A" rule from any `plan:entered-plan-mode` cluster | `friction_cluster.py` hardcoded a rule body for the cluster regardless of evidence; ignored the much-larger `reject:exitplanmode` signal entirely. Issue #1110 showed the proposal didn't match the 34:3 rejection-vs-entry ratio. | `feedback-plugin/scripts/tests/test_friction_cluster.py` asserts plan-mode and `reject:exitplanmode` clusters produce `kind: classify-required` with empty `path` and no auto-prescribed rule body | issue #1110 |
| `command -v <tool>` in Context section triggers permission-approval prompt and aborts skill | `command` is a shell builtin not covered by `Bash(<tool> *)` permission patterns; harness rejects with "Shell command permission check failed". Affected `task-status`, `task-add`, `task-done`, `task-coordinate`, `configure-load-tests`, `configure-skaffold`. | `lint-context-commands.sh` rule `command-v-in-context` | issue #1205, PR #1210 |
| `git config --get <key>` in Context section aborts skill on repos without the key set | `git config --get` exits 1 when the requested key is unset (e.g. `remote.origin.url` on a remote-less repo); the non-zero exit aborts the skill before its body runs — ironic for the canonical taskwarrior-native scenario (offline / local-only queues). Affected `task-status`, `task-add`, `task-done`. Re-reported on still-buggy / cached checkouts as #1214 and #1220 (both verified fixed at 294bd08a). | `lint-context-commands.sh` rule `git-config-get-in-context` | issue #1206, PR #1210 |
| `git-repo-agent` `blueprint:onboard` writes blueprints with `format_version: 1.0.0` instead of the current `3.3.0` | `prompts/compiler.py` strips SKILL.md sections whose heading text is in `DROP_HEADINGS` (`when to use this skill`, `context`, `parameters`, `flags`, etc.). Five blueprint skills (`blueprint-init`, `blueprint-status`, `blueprint-feature-tracker-status`, `blueprint-sync`, `blueprint-generate-rules`) placed all their actionable steps directly under `## When to Use This Skill` with `**Steps**:` as bold-text faux-headings. The compiler dropped the entire body — `blueprint-init` compiled to 49 chars (just the intro line) — and the model invented an outdated manifest schema from training data. | `git-repo-agent/tests/test_blueprint_driver.py::test_all_phases_compile_to_substantive_content` (asserts ≥500 chars per compiled phase skill) and `test_blueprint_init_advertises_current_format_version` | PR #TBD |
| Skills autocomplete with the namespace prefix (`/git-plugin:git-issue`) instead of the short form (`/git-pr`), and the description column shows the body's first heading ("Context", "When to Use This Skill") | Unquoted `args:` / `argument-hint:` values whose content is YAML-significant break frontmatter parsing. Multiple `[...]` flow sequences raise "expected block end, but found '['"; values with embedded `:` raise "mapping values are not allowed here"; a single `[foo]` parses to a list, not a string. When parsing fails, Claude Code falls back to body content for the description and renders the namespaced form. 20 skills affected before fix. | `plugin-compliance-check.sh` `check_skill_frontmatter()` parses each frontmatter with PyYAML and rejects parse errors plus non-string `args` / `argument-hint` values | PR #TBD |
| `taskwarrior-plugin` documents hyphenated tags (`+blocked-on-merge`, `+pr-ready`, `+needs-review`, `+bulk-task`) that taskwarrior silently fails to parse | Taskwarrior treats `-` mid-token as exclude-filter syntax even inside a `+tag` argument: `+blocked-on-merge` parses as `+blocked` AND `-on-merge`, the tag never lands, and the literal string ends up appended to the description (urgency does not tick up). Quoting does not help — parser quirk. Affected `task-add`, `task-status`, `task-coordinate`, and the plugin README. | `scripts/lint-taskwarrior-tags.sh` scans `taskwarrior-plugin/**/*.md` for `+word-word` patterns outside blockquotes (the gotcha callouts intentionally cite the broken form) | issue #1237 |
| Agents spawned via the `Agent` tool re-emit hook-blocked bash idioms (`find`, `grep`, `cat`, `git add . && git commit`, `Edit` before `Read`) — 200+ weekly hook reminders. Agent threads do not reliably load `~/.claude/rules/*.md`, so user-level rules don't ride along into the agent's system prompt. | All 21 plugin agent `.md` bodies lacked an in-prompt "Tool Selection" block, so each spawned thread had to re-discover the bash hooks that the user had already documented. | `scripts/check-agent-tool-selection.sh` verifies every `*-plugin/agents/*.md` includes a `## Tool Selection` heading and references both `Glob` and `Grep` (catches stub headings) | issue #1109 |
| SKILL.md bodies grow past Anthropic's 200-line ideal and the local 500-line ceiling, accumulating reference material that should live in `REFERENCE.md` / `scripts/`. Description trimming (PR #1265) addressed the system-prompt surface; this addresses the on-invocation surface. | No size lint existed — bodies could grow to 500+ without surfacing during review. Four skills had crossed 500 (`blueprint-feature-tracker-sync` 557, `blueprint-upgrade` 528, `project-discovery` 526, `git-branch-pr-workflow` 502) when the lint was added. | `plugin-compliance-check.sh` `check_skill_size()` — WARN at 251–500, ERROR at >500 (matches `.claude/rules/skill-quality.md`) | PR #TBD |
| `Agent(isolation: "worktree")` briefly leaks an untracked file into the parent checkout at the same relative path as a file the child wrote in its worktree; orphan vanishes after the child commits. A naive parent session would stash, restore, or commit the orphan onto the wrong branch. | `detect-coworkers.sh` had no signal that knew to look across worktrees, so a leaked file presented as ordinary user drift. The harness's worktree isolation is not perfectly sealed during a write→commit window. | `git-plugin/skills/git-coworker-check/scripts/tests/test_worktree_leak.sh` — fifth signal in `detect-coworkers.sh` cross-checks each untracked parent file against every linked worktree (`git worktree list --porcelain`) and raises `worktree_leak_suspected` when a match is found | issue #1319 |
| `configure-claude-plugins` SKILL documents two visually-similar but semantically-distinct marketplace suffix forms (`@claude-plugins` for `enabledPlugins`, `@laurigates-claude-plugins` for workflow `plugins:`); a reader copy-pasting between adjacent sections silently produced a non-functional config because the explanation lived ~50 lines away in "Important Notes". Wrong suffix in `enabledPlugins` → entry silently ignored; wrong suffix in workflow `plugins:` → action rejects the run. | The two suffix forms appeared without inline annotations — only a single far-away footnote distinguished them. The semantic invariant is that BOTH forms must carry an inline marker near each use, not just a bottom-of-file note. | `plugin-compliance-check.sh` `check_skill_body()` — for `configure-claude-plugins` specifically, asserts the SKILL.md body contains the literal strings `extraKnownMarketplaces key` AND `marketplace \`name\` in marketplace.json` (proves both suffix forms are annotated inline) | issue #1337 |
| `taskwarrior-plugin` skills (`task-status`, `task-add`, `task-claim`, `task-coordinate`, `task-done`, `task-release`) put `git rev-parse --show-toplevel` / `git remote` / `git branch --show-current` in Context blocks. These probes write to stderr ("fatal: not a git repository") when invoked outside a git repo. Stderr from a Context backtick aborts the skill before its body runs, and `2>/dev/null` / `\|\|` are blocked in Context commands — so there is no fallback form that survives the no-git case. PR #1210 (closing #1206) only fixed `git config --get`; the sibling probes regressed. Taskwarrior's canonical use case is no-git cwds (offline / local-only queues), so this turns the skills into hard aborts for the primary scenario. | The `lint-context-commands.sh` regression for #1206 (`git-config-get-in-context`) caught only `git config --get`; it didn't generalize to other stderr-emitting git probes. | `lint-context-commands.sh` rules `git-rev-parse-in-context`, `git-remote-in-context`, `git-branch-in-context` — scoped to `taskwarrior-plugin/` (other plugins are inherently git-scoped and Context probes are reasonable there) | issue #1351 |
| `hooks-plugin/hooks/bash-antipatterns.sh` block messages for `find`, `grep`/`rg`, `cat`, `head`/`tail` used advisory prose ("REMINDER: Use the X tool instead of Y") rather than a concrete substitution. W21 friction analysis (`~/.claude/rules/friction/2026-W21-frictions.md`) measured the `grep`/`rg` same-session repeat-block rate at 29% (up from 21% the prior week) even after the `bash-tool-replacements.md` rule landed — meaning the rule's existence isn't what teaches the agent, the block message itself is. The successful counter-example is W20's `gh-json-fields.md` rule, which named the exact substitution (`state == "MERGED"`) and drove that friction class from 10/10 sessions to 0/0 in one week. | The block messages told the agent which tool to use but not how to call it. An agent receiving "Use the Grep tool instead" still has to derive the call shape from memory; an agent receiving `Grep(pattern="pattern", path="src", -r=true, -n=true)` can substitute literally. | `hooks-plugin/hooks/test-bash-antipatterns.sh` "substitution-format block messages" block asserts each block message contains the literal substitution form (`Glob(pattern=...)`, `Grep(pattern=..., path=..., -r=true, -n=true)`, `Read(file_path=...)`, `Read(file_path=..., limit=50)`, `Read(file_path=..., offset=..., limit=50)`) and points at `.claude/rules/bash-tool-replacements.md` for the full table. Prevents future bulk edits from silently reverting to advisory prose. | issue #1377 |
| `git-plugin/hooks/check-pr-metadata-on-push.sh` re-blocked pushes after every `git rebase` even when PR metadata had been reconciled — because the retry-aware bypass added in #1041 compared `PR.updatedAt` against HEAD's **committer** date (`%cI`), which `git rebase` refreshes to "now" even when no content changes. The agent's only escape was a content-different `gh pr edit`, but `gh pr edit --body-file <file>` no-ops on GitHub when the new body matches the old, so the agent ended up trapped in a re-block loop (observed in PR #1388 drain: 5 wasted round-trips after a single rebase). | The bypass used committer time, which jumps on every rebase. Author time (`%aI`) is preserved across rebases — it reflects when the work was originally written, which is what "has the PR been updated since this commit was written" actually asks. | `git-plugin/hooks/test-check-pr-metadata-on-push.sh` "author-date bypass (rebase preserves author date)" block creates a commit with `GIT_AUTHOR_DATE` 2h in the past and default committer date = now (simulating a rebased commit), then asserts the bypass fires when `PR.updatedAt` is 1h ago (between author and committer times) and still blocks when `PR.updatedAt` is 3h ago (before author wrote). | issue #1400 |
| `hooks-plugin/hooks/branch-protection.sh` denied legitimate writes when the orchestrator's cwd was on `main` and the command targeted a feature-branch worktree via `git -C <path>`. The hook ran `git branch --show-current` in its own cwd (the orchestrator's), so a Wave dispatch driving 7 isolated worktrees from a main-branch checkout hit false-positive denies 3+ times in a single session for staging and pushing. The workaround required either an explicit-refspec push or SendMessage-ing into the worktree to commit from inside. | `git branch --show-current 2>/dev/null` doesn't honor `-C <path>` flags that appear in the command string — it reads from cwd unconditionally. The hook had no `-C` parser, so the protected-branch check ran against the wrong working tree. | `hooks-plugin/hooks/test-branch-protection.sh` "git -C <worktree> branch detection (#1389)" block creates a feature/probe worktree and a master worktree under TEST_REPO (which stays on main), then asserts `git -C $FEATURE_WT commit/add/push` are allowed while `git -C $MASTER_WT commit/push` is still denied — proving the parser routes to the worktree's branch, not the cwd's, without becoming a blanket bypass. | issue #1389 |
| `git-plugin/hooks/check-pr-metadata-on-push.sh` read commits and the retry-aware bypass timestamp from the running shell's `HEAD` instead of the branch being pushed. When the orchestrator's checkout was on `fix/B` and the command pushed `fix/A` (the default situation under `git-pr-feedback --all`, which drives multiple worktrees from a main-branch checkout), the block message showed wrong commits and the bypass compared `PR.updatedAt` against the wrong author time — trapping the agent in a re-block loop when the running shell's HEAD had more recent author time than the pushed branch. The only escape was a content-different `gh pr edit` (the same trap #1400 fixed for the same-branch case). | The hook hardcoded `HEAD` in `git merge-base HEAD origin/HEAD`, `git log .. HEAD`, and `git log -1 --format=%aI HEAD`. The branch being pushed was already correctly resolved into `PUSH_BRANCH` but never used. | `git-plugin/hooks/test-check-pr-metadata-on-push.sh` "cross-branch push reads pushed branch ref (#1419)" block creates an `older-target` branch authored 3h ago and a `newer-current` branch authored 1m ago, then from the `newer-current` checkout pushes `older-target` and asserts the bypass fires when `PR.updatedAt` is 1h ago (between the two author dates). Counter-tests confirm a genuinely-stale PR still blocks and that pushing a brand-new branch whose local ref doesn't yet exist falls back to HEAD without erroring. | issue #1419 |

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
- [ ] The "Known Regressions" table in this file is updated
- [ ] The fix commit follows conventional commit format: `fix(plugin): description`

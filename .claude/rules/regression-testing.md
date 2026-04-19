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

## Where to Add the Check

| Problem Type | Add Check To |
|-------------|-------------|
| Context command antipattern (API calls, shell operators) | `scripts/lint-context-commands.sh` |
| Skill body structure corruption (spurious headings, leaked frontmatter) | `scripts/plugin-compliance-check.sh` → `check_skill_body()` |
| Frontmatter field missing or malformed | `scripts/plugin-compliance-check.sh` → `check_skill_frontmatter()` |
| Description fails auto-invocation matching (missing/empty, or no "Use when..." trigger) | `scripts/plugin-compliance-check.sh` → `check_skill_descriptions()` (delegates to `scripts/audit-skill-descriptions.py`) |
| Skill size exceeding limit | `scripts/plugin-compliance-check.sh` → `check_skill_size()` |
| Blueprint upgrade target drift (migrations added without updating `blueprint-upgrade`) | `scripts/check-blueprint-upgrade-target.sh` |

## Known Regressions (Documented Bugs)

| Issue | Root Cause | Check Added | Fixed In |
|-------|-----------|-------------|----------|
| `gh repo view` in context command fails with TLS/x509 error | Uses GitHub GraphQL API; fails in proxy/offline/cert-error environments | `lint-context-commands.sh` rule `gh-api-in-context` | PR #799 |
| `name: fieldname` + `---` in skill body renders as accidental H2 heading | YAML frontmatter key leaked into markdown body; `key\n---` is a setext heading | `plugin-compliance-check.sh` `check_skill_body()` | PR #799 |
| `model: haiku` with `AskUserQuestion` causes empty silent prompts | Haiku model doesn't reliably format AskUserQuestion tool calls; prompts return empty | `plugin-compliance-check.sh` `check_skill_frontmatter()` | PR #879 |
| `test -f path && echo "EXISTS" \|\| echo "MISSING"` in context command fails | `test -f` requires Bash permission; `&&`/`\|\|` are blocked shell operators; `2>/dev/null` and pipes are blocked | `lint-context-commands.sh` rules `test-in-context`, `shell-operator-and`, `shell-operator-or`, `redirection-operator`, `pipe-operator` | issue #899 |
| `grep ... package.json pyproject.toml requirements.txt` fails when files missing | grep writes to stderr when hardcoded filenames don't exist; non-JS/Python projects lack these files | `lint-context-commands.sh` rule `grep-hardcoded-multi-file` | PR #TBD |
| `find ~/.claude/plugins ...` blocked by sandbox security | `find` on home-directory paths (`~/`, `$HOME`) is outside allowed working directories | `lint-context-commands.sh` rule `home-dir-in-context` | PR #TBD |
| `jq ... .claude/settings.json` fails when file missing | jq writes to stderr when target file doesn't exist; `2>/dev/null` is blocked in context commands | `lint-context-commands.sh` rule `jq-on-optional-settings` | PR #TBD |
| `Bash(test *), Bash(jq *)` etc. causes ~20 approval prompts | Shell utility patterns in `allowed-tools` force inline bash that can't be allowlisted; each compound command needs individual approval | `plugin-compliance-check.sh` `check_bash_patterns()` | PR #TBD |
| `blueprint-{generate,derive}-rules` writes hardcoded `.claude/rules/` and clobbers hand-authored rules | SKILL.md hardcoded the output directory; no `structure.generated_rules_path` field | `plugin-compliance-check.sh` `check_skill_body()` (blueprint rules-path check) | issue #1043 |
| `/blueprint:upgrade` reports v3.2.0 as latest after v3.3 migration was added | `blueprint-upgrade/SKILL.md` hardcodes target version; PR #1026 added `migrations/v3.2-to-v3.3.md` without updating the upgrade skill | `check-blueprint-upgrade-target.sh` compares highest migration target to `blueprint-upgrade/SKILL.md` | PR #TBD |
| Skills with capability-list descriptions ("Check and configure X") never auto-invoke | Claude matches `description` against user intent; without "Use when..." and trigger phrases the matcher never fires. 133/325 skills were affected at baseline. | `plugin-compliance-check.sh` `check_skill_descriptions()` (warns on NO_TRIGGER for auto-invokable skills; errors on MISSING/EMPTY); `audit-skill-descriptions.py --strict` in pre-commit | PR #TBD |

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

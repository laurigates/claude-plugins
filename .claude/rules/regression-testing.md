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
| Skill size exceeding limit | `scripts/plugin-compliance-check.sh` → `check_skill_size()` |

## Known Regressions (Documented Bugs)

| Issue | Root Cause | Check Added | Fixed In |
|-------|-----------|-------------|----------|
| `gh repo view` in context command fails with TLS/x509 error | Uses GitHub GraphQL API; fails in proxy/offline/cert-error environments | `lint-context-commands.sh` rule `gh-api-in-context` | PR #799 |
| `name: fieldname` + `---` in skill body renders as accidental H2 heading | YAML frontmatter key leaked into markdown body; `key\n---` is a setext heading | `plugin-compliance-check.sh` `check_skill_body()` | PR #799 |
| `model: haiku` with `AskUserQuestion` causes empty silent prompts | Haiku model doesn't reliably format AskUserQuestion tool calls; prompts return empty | `plugin-compliance-check.sh` `check_skill_frontmatter()` | PR #879 |
| `test -f path && echo "EXISTS" \|\| echo "MISSING"` in context command fails | `test -f` requires Bash permission; `&&`/`\|\|` are blocked shell operators; `2>/dev/null` and pipes are blocked | `lint-context-commands.sh` rules `test-in-context`, `shell-operator-and`, `shell-operator-or`, `redirection-operator`, `pipe-operator` | issue #899 |

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

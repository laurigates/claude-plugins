# upstream-pr-plugin

Heavy-divergence fork-to-upstream PR workflow for Claude Code.

When a fork has substantially diverged from upstream, direct rebase is not viable. This plugin codifies the patterns that make a clean upstream PR possible anyway: **eligibility checks** via patch-id matching, **cherry-pick with re-derive fallback** when conflicts get dense, **commit-message scrubbing** to strip fork-local context, and **pre-flight regression verification** against the upstream baseline.

## When to use this plugin vs `git-plugin:git-upstream-pr`

| `upstream-pr-plugin` (this plugin) | `git-plugin:git-upstream-pr` |
|------------------------------------|------------------------------|
| Heavy fork divergence | Low fork divergence |
| Patch-id eligibility check (catches re-applied content) | Skips patch-id check |
| Re-derive fallback when cherry-pick fails | Cherry-pick + abort |
| Commit-message scrubbing | No scrubbing |
| Pre-flight regression check vs upstream | No regression check |

Both plugins coexist intentionally. Use the simpler `git-upstream-pr` first; if the cherry-pick flounders or you discover the change has already been applied upstream under a different SHA, switch to `upstream-pr`.

## Skills

| Skill | Description |
|-------|-------------|
| `/upstream-pr:upstream-pr` | Submit a single fork commit upstream as a clean PR |

## Configuration

Per-project configuration lives at `.claude/upstream-pr.local.md`:

```markdown
---
upstream_remote: upstream
upstream_repo: owner/repo
branch_prefix: pr-upstream/
linter_cmd: uv run ruff check
test_cmd: uv run pytest -q
pr_body_template_path: docs/UPSTREAM_PR_TEMPLATE.md
---
```

All fields are optional — sensible defaults are derived from `git remote get-url upstream`. Add `.claude/*.local.md` to `.gitignore`.

## Workflow

```
git log --oneline                                  # pick the SHA to send upstream
bash skills/upstream-pr/scripts/check-eligibility.sh <sha>
bash skills/upstream-pr/scripts/prepare-branch.sh <topic> <sha>
# resolve conflicts, or abort + re-derive
bash skills/upstream-pr/scripts/scrub-commit.sh --check
bash skills/upstream-pr/scripts/scrub-commit.sh    # if --check failed
git push origin <branch>
gh pr create --repo <upstream_repo> --base main --head <fork-owner>:<branch> ...
```

See [skills/upstream-pr/SKILL.md](skills/upstream-pr/SKILL.md) for the full workflow.

## Origin

Generalized from the in-repo skill at [`laurigates/kicad-mcp:.claude/skills/upstream-pr/`](https://github.com/laurigates/kicad-mcp/blob/main/.claude/skills/upstream-pr/SKILL.md), which was driven by a series of upstream PRs to `lamaalrajih/kicad-mcp` ([#53](https://github.com/lamaalrajih/kicad-mcp/pull/53), [#54](https://github.com/lamaalrajih/kicad-mcp/pull/54), [#55](https://github.com/lamaalrajih/kicad-mcp/pull/55)). See [issue #1201](https://github.com/laurigates/claude-plugins/issues/1201) for the proposal that motivated this plugin.

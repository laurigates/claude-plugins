# feedback-session: design notes and known limitations

## Known Limitations

**IaC-managed labels**: Some repositories manage GitHub labels declaratively via Terraform, Pulumi, or similar tools. In these repos, `gh label create` will either be forbidden or cause drift that the IaC tool destroys on the next apply. This skill detects this case and offers a graceful fallback (see Step 1).

**Default target repo**: By default, this skill files issues against the repository in the current working directory. If you are giving feedback about a plugin skill itself rather than the application code in the session, use `--target-repo <owner/repo>` to point at the plugin source repo.

**Dominant-source mismatch**: When the cwd has a git remote but the session's tool calls were dominated by a *different* plugin/source repo, this skill detects the mismatch and asks you to confirm which repo to file against — the cwd repo or the plugin source. See Step 1a for the full four-combination decision table.

## Context

Git remote and target-repo detection happens during Step 1a (execution), not
in this Context block. `git remote -v` and `gh repo view` both write to
stderr when invoked outside a git repository — and stderr from a Context
backtick aborts the skill before its body runs. `2>/dev/null` and `||` are
also blocked in Context commands (see `.claude/rules/agentic-permissions.md`),
so there is no fallback form that survives the no-git case. Step 1a's
dominant-source scan runs for both the cwd-with-remote and the no-remote
cases, and surfaces a mismatch-confirmation prompt when the session's plugin
activity points to a different repo than the cwd remote.

Open feedback issues are fetched during Step 3 (deduplication), scoped to the
resolved `$TARGET_REPO`. They are not pre-fetched in context because
`gh issue list` without `-R` requires a configured remote and fails with
"no git remotes found" in repos that lack one.

# GitHub Actions Workflows

This directory contains GitHub Actions workflows for the claude-plugins repository.

## Naming Convention

All workflows use the `name:` pattern `<Domain>: <Action> [<target>]` so the Actions UI sidebar groups related workflows alphabetically.

- **Domain** — Title Case noun. Matches the workflow's category, not necessarily its filename.
- **Colon + space** as separator (mirrors conventional-commit scope style).
- **Action** — sentence case, short imperative or noun phrase. No trailing punctuation.
- **Target** — kebab-case identifier (script, plugin, target name) when relevant.
- **Quotes required** — colons must be quoted in YAML scalars: `name: "Plugin: Lint skills"`.

When adding a workflow, pick the existing domain that fits or extend the table below with a new one — don't introduce a one-off prefix.

### Domains in use

| Domain | Used for |
|--------|----------|
| `Claude:` | Claude Code-driven workflows (PR reviews, @-mentions, scheduled reviews) |
| `Plugin:` | Plugin infrastructure — PR checks, config validation, skill operations, scheduled audits |
| `Release:` | release-please ecosystem — version bumps, changelog, release-PR doc audit, conflict repair |
| `PR:` | Cross-cutting PR governance — conflict resolution, conventional-commit enforcement |
| `Auto-fix:` | Autonomous CI failure remediation triggered by `workflow_run` |
| _(none)_ | One-off standalones with no obvious domain peer (e.g. `Renovate`) |

### Sorted name list

```
Auto-fix: CI failures
Claude: @mentions
Claude: Changelog review
Claude: PR review
PR: Auto-resolve conflicts
PR: Enforce conventional commits
Plugin: Lint skills
Plugin: Obsidian CLI changelog review
Plugin: PR checks
Plugin: Scheduled audits
Plugin: Skill splitter
Plugin: Validate configs
Release: Fix release-please conflicts
Release: PR documentation audit
Release: release-please
Renovate
```

## Cross-workflow references

When a workflow references another by display name (e.g. `on.workflow_run.workflows`), update the reference whenever the target's `name:` changes. The current cross-references live in `github-workflow-auto-fix.yml`.

# GitHub Actions Workflow Naming

A `<Domain>: <Action> [<target>]` convention for the `name:` field of every GitHub Actions workflow this repo authors — and for the example snippets in any skill that scaffolds workflows.

The motivation is the GitHub Actions sidebar: it sorts alphabetically by workflow display name, so a consistent prefix groups related workflows visually. The convention mirrors conventional-commit scope style: a Title Case domain noun, a colon, and a sentence-case action.

## Rule

Every workflow's `name:` follows:

```
<Domain>: <Action> [<target>]
```

- **Domain** — Title Case noun. Pick from the table below; add a new domain only when none fits.
- **Colon + space** as separator.
- **Action** — sentence case, short imperative or noun phrase. No trailing punctuation.
- **Target** — kebab-case identifier (script, plugin, target name) when relevant.
- **Quote the value** — colons must be quoted in YAML scalars: `name: "Plugin: Lint skills"`.

A genuinely standalone workflow with no domain peers (e.g. `Renovate`) may go un-prefixed. Bias toward picking a domain — a one-off becomes a peer the moment a sibling workflow lands.

## Domains in this repo

| Domain | Used for |
|--------|----------|
| `Claude:` | Claude Code-driven workflows (PR reviews, @-mentions, scheduled reviews) |
| `Plugin:` | Plugin infrastructure — PR checks, config validation, skill operations, scheduled audits |
| `Release:` | release-please ecosystem — version bumps, changelog, release-PR doc audit, conflict repair |
| `PR:` | Cross-cutting PR governance — conflict resolution, conventional-commit enforcement |
| `Auto-fix:` | Autonomous CI failure remediation triggered by `workflow_run` |
| _(none)_ | Standalones with no obvious domain peer (e.g. `Renovate`) |

The canonical list of current names lives in `.github/workflows/README.md`. Update both that file and any affected `workflow_run.workflows` references when a `name:` changes.

## Cross-workflow references

When a workflow lists another workflow's display name (e.g. `on.workflow_run.workflows`), the listed string must match the target's `name:` exactly. Renaming a workflow is a same-PR job:

1. Update the workflow's `name:` line.
2. Grep for the old display name across `.github/workflows/` and update every reference.
3. Update the sorted name list in `.github/workflows/README.md`.

## Skills that scaffold workflows

Any skill that emits a workflow YAML snippet must follow this convention in its examples. The affected skills today:

| Skill | Where it generates `name:` |
|-------|----------------------------|
| `configure-plugin:ci-workflows` | Canonical workflow shapes (container build, tests, release, auto-fix) |
| `configure-plugin:configure-workflows` | Interactive workflow scaffolder |
| `configure-plugin:configure-reusable-workflows` | Reusable-workflow caller files |
| `github-actions-plugin:claude-code-github-workflows` | Claude Code workflow design patterns |
| `github-actions-plugin:github-workflow-auto-fix` | `Auto-fix: CI failures` template |
| `github-actions-plugin:ci-autofix-reusable` | Reusable CI auto-fix workflow |
| `agents-plugin/agents/ci.md` | CI agent's "Common Workflows" examples |

When you add a new skill that scaffolds a workflow, register it here.

## Example mapping

| Before | After |
|--------|-------|
| `name: Plugin PR Checks` | `name: "Plugin: PR checks"` |
| `name: Auto-fix Workflow Failures` | `name: "Auto-fix: CI failures"` |
| `name: Release Please` | `name: "Release: release-please"` |
| `name: Tests` | `name: "Test: Suite"` (or keep standalone if there is only one) |
| `name: Build Container` | `name: "Container: Build"` |

## Related

- `.github/workflows/README.md` — current name list and per-domain rationale
- `.claude/rules/conventional-commits.md` — analogous Domain-style scope rule for commits and PR titles

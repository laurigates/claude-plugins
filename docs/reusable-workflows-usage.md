# Reusable GitHub Workflows

The reusable Claude review workflows (`reusable-security-*.yml`,
`reusable-quality-*.yml`, `reusable-a11y-*.yml`) live in
[`laurigates/.github`](https://github.com/laurigates/.github), not in this
repository. Their inputs, defaults and usage are documented there:

- Workflow files: [`laurigates/.github/.github/workflows/`](https://github.com/laurigates/.github/tree/main/.github/workflows)
- Catalogue and setup: the [`laurigates/.github` README](https://github.com/laurigates/.github#readme)

To add the callers to a repository, use the
`configure-plugin:configure-reusable-workflows` skill.

This file used to hold a full usage guide. It drifted from the live workflows
(wrong `max-turns` defaults, undocumented inputs, a version tag that does not
exist) and was reduced to this pointer in #2840.

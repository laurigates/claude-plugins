# Claude Plugins

> Experimental testing harness lives under experiments/claude-probe/.

A curated collection of 44 Claude Code plugins providing 400+ skills and 21 agents for development workflows.

The same skills, subagents and safety hooks also run in **OpenCode** and **pi**.
Skills are read in place from a checkout of this repo, so a skill edit reaches
every harness without a copy step; subagents and hooks are exported to each
tool's own format. Browse everything in the [plugin catalog](docs/CATALOG.md).

## Supported harnesses

| Harness | Skills | Subagents | Safety hooks |
|---------|--------|-----------|--------------|
| [Claude Code](#claude-code) | Native plugin marketplace | Native | Native |
| [OpenCode](#opencode) | Skill adapter: a `search_skills` tool plus the top 5 matches injected each turn | Exported to OpenCode's agent format | Exported as OpenCode JS plugins |
| [pi](#pi) | Skill adapter (same as OpenCode) | Exported for `@tintinweb/pi-subagents` | Run by a generated pi extension |

OpenCode and pi both read `SKILL.md` unmodified, but neither budgets its skill
listing: listing 382 skills natively measured ~34,000 tokens of context on
every turn (2026-08-24). The adapter
([ADR-0022](docs/adrs/0022-adapter-over-export-for-foreign-harnesses.md),
[`adapters/`](adapters/README.md)) reaches all of them for ~600.

### Claude Code

Add the marketplace, then install the plugins you want:

```bash
claude plugin marketplace add laurigates/claude-plugins
claude plugin install git-plugin@laurigates-claude-plugins
claude plugin install python-plugin@laurigates-claude-plugins
```

Inside a session, `/plugin` browses and installs the same plugins.

### OpenCode

Needs a clone of this repo, [bun](https://bun.sh) and [just](https://just.systems):

```bash
git clone https://github.com/laurigates/claude-plugins && cd claude-plugins
(cd adapters && bun install)
just setup-opencode
```

`setup-opencode` installs the subagents and hook plugins into
`~/.config/opencode` and writes an `opencode.json` that registers the adapter
for a local MLX model. An existing `opencode.json` is kept (a sample is written
beside it); wire the adapter into it with `just oc-adapter-register`. Details:
[docs/opencode-export.md](docs/opencode-export.md).

### pi

Needs a clone of this repo, [bun](https://bun.sh) and [just](https://just.systems):

```bash
git clone https://github.com/laurigates/claude-plugins && cd claude-plugins
(cd adapters && bun install)
just setup-pi
```

`setup-pi` registers the adapter in `~/.pi/agent/settings.json`, installs the
subagents and the safety-hook extension, and prints the steps to serve a local
model. `just pi-adapter-unregister` reverses the registration. Details:
[docs/pi-export.md](docs/pi-export.md).

## Getting Started

1. **Install** the plugins for your harness, above
2. **Run a health check** — `/health-plugin:health-check` then `/health-plugin:health-audit` to diagnose your setup and get plugin recommendations for your stack
3. **Follow the tiered setup** — The [Plugin Map](docs/PLUGIN-MAP.md) provides a recommended install order (Tier 0 foundation through Tier 3+ stack-specific), decision trees, and project presets

For MCP servers, `/configure-plugin:configure-mcp` sets them up interactively.

## Design Principles

The methodology behind these plugins — what a probabilistic agent should decide
versus what a deterministic substrate should verify and remember. See
[**docs/PRINCIPLES.md**](docs/PRINCIPLES.md) for the full set, each grounded in
the rules, skills, and hooks that embody it.

## Prerequisites

- **Bash 5+** — Required for shell scripts. macOS ships Bash 3.2; install via `brew install bash`.

## Questions and Ideas

[Discussions](https://github.com/laurigates/claude-plugins/discussions) is the place to ask things in the open:

| Category | For |
|----------|-----|
| [Q&A](https://github.com/laurigates/claude-plugins/discussions/categories/q-a) | How do I do X, why does a skill behave this way, is Z supported |
| [Ideas](https://github.com/laurigates/claude-plugins/discussions/categories/ideas) | A plugin or skill you would like to exist, before it is a concrete request |
| [Show and tell](https://github.com/laurigates/claude-plugins/discussions/categories/show-and-tell) | What you built with these plugins |

Use [issues](https://github.com/laurigates/claude-plugins/issues) for a defect or a concrete feature request, and please do not open a pull request just to ask a question.

## Development

Plugins use [release-please](https://github.com/googleapis/release-please) for automated versioning. Use conventional commits to trigger releases:

```bash
feat(git-plugin): add worktree support    # minor bump
fix(python-plugin): handle empty venv     # patch bump
```

See `CLAUDE.md` for detailed development instructions.

## License

MIT

# vault-agent

Claude Agent SDK application for Obsidian vault maintenance — tag consolidation, broken-link repair, stub classification, and MOC curation. Modeled on [`git-repo-agent`](../git-repo-agent/).

## Quick start

```bash
uv tool install -e ./vault-agent

# Read-only audit — no LLM, no writes
vault-agent analyze ~/Documents/MyVault
vault-agent health  ~/Documents/MyVault
vault-agent report  ~/Documents/MyVault --format=md

# Deterministic fixes — pure Python, still no LLM
vault-agent lint    ~/Documents/MyVault --fix
vault-agent links   ~/Documents/MyVault --fix
vault-agent stubs   ~/Documents/MyVault --fix

# MOC analysis — read-only (proposing new MOCs needs LLM)
vault-agent mocs    ~/Documents/MyVault

# Run multiple modes in a single worktree
vault-agent maintain ~/Documents/MyVault --fix --modes=lint,links,stubs
```

## What it does

1. **Pre-computes a structural audit** (tags, wikilinks, orphans, stubs, MOCs) in pure Python.
2. **Applies deterministic fixes** via the fixer modules (strip `id:`, normalize tags, rewrite known-broken wikilinks, etc.).
3. **Delegates judgment-heavy work** to SDK-backed subagents (stub content merging, new-MOC proposals, orphan linkage).
4. **Isolates writes** in a git worktree on a `vault-agent/<timestamp>` branch; each fix category is a separate conventional commit.
5. **Leaves the branch for manual merge** — no PR creation (vaults typically don't have GitHub remotes).

## Architecture

```
vault-agent/                          ← Python CLI (Typer + claude-agent-sdk)
├── src/vault_agent/
│   ├── main.py                       CLI entry: analyze | lint | links | stubs | mocs | maintain | health | report
│   ├── analyzers/                    Pure-Python audit (vault_index → frontmatter/links/graph/stubs/mocs/duplicates/health)
│   ├── fixers/                       Pure-Python deterministic edits (id_stripper, tag_normalizer, templater_cleaner, link_patcher, stub_rewriter)
│   ├── prompts/                      Orchestrator + mode prompts + skill compiler
│   │   └── compiler.py               Loads SKILL.md from obsidian-plugin, strips metadata, assembles subagent prompts
│   ├── agents/                       AgentDefinition per subagent (vault-lint/links/stubs/mocs)
│   ├── hooks/safety.py               PreToolUse validator — blocks .obsidian/, .claude/, .git/, Files/, rm -rf outside allowlist
│   ├── worktree.py                   Git worktree lifecycle, advisory lock
│   ├── non_interactive.py            Exit codes + config for scheduled runs
│   ├── orchestrator.py               SDK session setup, system-prompt assembly, review-banner formatting
│   ├── lint.py / links_mode.py / stubs_mode.py / mocs_mode.py / maintain.py
│   └── reporting.py                  Terminal / JSON / markdown render
├── tests/                            pytest unit tests (90+)
└── docs/adr/                         Architecture decision records
```

Skill prompts live in [`../obsidian-plugin/skills/vault-*`](../obsidian-plugin/skills/) — seven SKILL.md files covering the knowledge the subagents need.

## Modes

| Mode | Determines | LLM needed? |
|------|-----------|-------------|
| `analyze` | Full audit dump | No |
| `health` | 0–100 health score | No |
| `report` | Formatted audit | No |
| `lint` | Bare 📝/🌱 tags, legacy `id:`, Templater leakage, `🗺️ → 📝/moc`, null tags | No |
| `links` | Rule-table rewrites (e.g. `[[AnsibleFVH]] → [[Ansible]]`), `[[Kanban/X]] → [[X]]` | No |
| `stubs` | Rewrite `broken_redirect` stubs; report `stale_duplicate` for user review | Partially — merging requires LLM |
| `mocs` | Inventory, coverage, missing-MOC candidates | Proposing new MOCs requires LLM |
| `maintain` | Runs all deterministic modes in one worktree | No for deterministic path |

## Subagent tiers

| Subagent | Model | When invoked |
|----------|-------|--------------|
| vault-lint | haiku | Edge cases the deterministic fixer can't handle |
| vault-links | sonnet | Ambiguous link targets, low-leverage broken links with obvious fixes |
| vault-stubs | sonnet | Stale-duplicate content merging |
| vault-mocs | opus | New-MOC proposals, orphan linkage |

See [ADR-0003](docs/adr/0003-model-tier-per-mode.md).

## Review workflow

After any write mode:

```
✓ branch vault-agent/2026-04-17T14-00 ready (3 commits, 931 files changed)
  review:  git -C ~/Documents/MyVault diff main vault-agent/2026-04-17T14-00
  merge:   git -C ~/Documents/MyVault merge --ff-only vault-agent/2026-04-17T14-00
```

Review the diff in your normal tooling. When satisfied, run the merge command.

## Safety

- Writes to `.obsidian/`, `.claude/`, `.git/`, `Files/`, `node_modules/`, `_site/` are blocked by `hooks/safety.py`.
- `git push`, `git reset --hard`, `git checkout -- .` are blocked.
- `rm -rf` is blocked outside `tmp/`, `__pycache__/`, `Inbox/ChatExport_*/processed/`.
- All writes happen in an isolated worktree; the main checkout is untouched until the user merges manually.

See [ADR-0004](docs/adr/0004-safety-hooks-vault-paths.md).

## Development

```bash
uv sync
uv run pytest
```

Full audit against a real vault:

```bash
uv run vault-agent analyze ~/Documents/LakuVault
```

## Status

See [ADR-0001](docs/adr/0001-precompute-vault-graph.md), [ADR-0002](docs/adr/0002-worktree-without-pr.md), [ADR-0005](docs/adr/0005-skill-source-obsidian-plugin.md) for the core decisions.

Working today:
- Full audit + health scoring
- Deterministic lint / links / stubs fixes
- MOC analysis reporting
- Worktree + safety hooks + conventional commits

Deferred (requires SDK auth + further work):
- SDK-backed subagent runs for judgment cases
- Stale-duplicate content merge
- New-MOC proposal and creation

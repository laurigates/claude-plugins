# health-plugin

Diagnose and fix Claude Code configuration issues including plugin registry, settings, hooks, and MCP servers.

## Installation

```bash
/plugin install health-plugin@laurigates-claude-plugins
```

## Skills

| Skill | Description |
|-------|-------------|
| `/health:check` | **Single entry point.** Diagnose (and optionally fix) Claude Code environment, plugin registry, project-stack fit, and skill agentic-optimisation — routed by `--scope`. |
| `/health:skill-audit` | Audit the plugin skill tree for skill-to-skill overlap, split-pressure inside a SKILL.md, and consolidation candidates. Writes four reports to `tmp/skill-audit/`. |
| `plugin-registry` | Reference skill: Claude Code's plugin registry, scopes, and troubleshooting |
| `settings-configuration` | Reference skill: settings file hierarchy, permission wildcards, and patterns |

### Internal scopes (routed by `/health:check --scope=...`)

| Scope | Covers | Internal skill |
|-------|--------|----------------|
| `registry` | Orphaned `projectPath` entries, stale `enabledPlugins` keys (addresses [#14202](https://github.com/anthropics/claude-code/issues/14202)) | `health-plugins` |
| `stack` | Enabled plugins vs project tech stack | `health-audit` |
| `agentic` | Skill/command/agent agentic-optimisation compliance | `health-agentic-audit` |
| `runtime` | `~/.claude.json` bloat (dead projects/githubRepoPaths, orphaned MCP). Read-only | `check-runtime.sh` |
| `usage` | Never-fired and dormant skills *and* plugin agents mined from session telemetry. Read-only, local-leaning ([ADR-0018](../docs/adrs/0018-health-usage-scope-from-session-telemetry.md)) | `check-usage.sh` |
| `all` | All of the above (default) | — |

These internal skills are auto-discoverable but not user-invocable — use `/health:check` instead.

## Scripts

| Script | Description |
|--------|-------------|
| `prune-claude-config.py` | Remove orphaned projects and cached data from `~/.claude.json` |
| `config-drift.py` | Audit the rules/skills corpus itself for duplication, broken pointer stubs, review staleness, and always-loaded budget |
| `lib/probe.py` | The finding / waiver / delta / render contract the drift probes share |

### `config-drift.py`

Answers a question the other health checks do not: **is the configuration
corpus self-consistent?** It compares rules against each other and against the
skill corpus, rather than validating any one file in isolation.

| Check | Severity | Catches |
|---|---|---|
| `broken_pointer_stub` | ERROR | A "Promoted to a skill: invoke `x`" rule whose target no longer exists |
| `duplicate_rule_lexical` | WARN | Byte-identical or near-identical rules across scopes |
| `semantic_overlap_*` | WARN | Differently-worded rules or skills covering one topic |
| `rule_covered_by_skill` | INFO | A resident rule whose content a skill already carries |
| `always_loaded_budget` | WARN | The every-turn surface creeping past its ceiling |
| `review_staleness` | WARN | An artifact changed after its declared `reviewed:` date |

Two cost tiers, because a SessionStart probe cannot pay for a model:

```
config-drift.py --fast --no-embed --format=json    # 0.05s, pure stdlib, no git spawn
config-drift.py --format=report                    # + embeddings, scheduled use
```

`--fast` reads cached last-change dates only; the cache is keyed by **content
hash**, never mtime, so it cannot go stale and cannot be invalidated by a
checkout that rewrites timestamps.

**Waivers.** Deliberate duplication is suppressed via
`~/.claude/config-drift-waivers.json`, keyed by both sides' content hashes — so
a waiver expires the moment either file is edited. Without that, a recurring
report re-lists its known-accepted findings until you stop reading it.

**Semantic threshold.** The embedding pass is calibrated to cosine ≥ 0.91 with
same-name and structural pairs excluded. This is not a default worth changing
casually: at 0.86 on a real 884-document corpus it emitted 491 findings, of
which 290 were same-name pairs the cheap tier already owns. Everything here is
one genre of document, so baseline similarity is high.

### `lib/probe.py`

`config-drift.py` owns the **checks** (what counts as drift); `lib/probe.py`
owns the **shape**, so a second probe does not re-derive it:

| Piece | What it covers |
|---|---|
| `finding(severity, kind, summary, **extra)` | The one constructor for every finding, validating the shape and pinning key order |
| `load_waivers()` / `waived()` | Path-parameterised waiver lookup, both orientations, expiring when either side's content hash changes |
| `fingerprint()` / `fingerprints()` / `delta()` | A finding's stable identity — `kind` + sorted paths — and a previous-run set comparison ([#2319](https://github.com/laurigates/claude-plugins/issues/2319)) |
| `emit_status` / `emit_probe` / `emit_report` / `emit_json`, `render()` | The three renderers plus the JSON dump, behind one `--format` dispatch |
| `EXIT_CLEAN` / `EXIT_WARN` / `EXIT_ERROR` / `EXIT_INTERNAL`, `exit_code()` | `0 clean, 1 warn, 2 error (--gate), 3 internal` |

`fingerprint()` is deliberately **not** wired into `config-drift.py`'s output
yet — it exists so [#2319](https://github.com/laurigates/claude-plugins/issues/2319)
has something to build on.

Two constraints on the module, both load-bearing:

- **Import it as `from lib.probe import …`, never `import probe`.**
  `sys.path[0]` is the *script's* directory, not `lib/`, so the flat form
  raises `ModuleNotFoundError`. What resolves it is a PEP 420 implicit
  namespace package — hence **no `__init__.py`**. Verified under both bare
  `python3` and `uv run --script`, from an unrelated cwd.
- **Stdlib only, and no PEP-723 dependency block.** Both real callers
  (`hooks/config-drift-probe.sh`, `scripts/tests/test-config-drift.sh`) invoke
  bare `python3`, bypassing the `uv run --script` shebang — so a dependency
  block would resolve only on the path nobody takes.

Getting either wrong fails *silently*: `config-drift-probe.sh` reads empty
analyzer output as "no findings", so an `ImportError` traceback is
indistinguishable from a clean corpus. `tests/test-config-drift.sh` executes
the import path from an unrelated cwd for exactly that reason.

## Use Cases

### Plugin Shows "Installed" But Doesn't Work

This is a known issue ([#14202](https://github.com/anthropics/claude-code/issues/14202)) where project-scoped plugins incorrectly appear as globally installed.

```bash
# Diagnose the issue
/health:check --scope=registry

# Fix automatically
/health:check --scope=registry --fix
```

### Full Environment Health Check

```bash
# Run all diagnostics
/health:check

# With verbose output
/health:check --verbose
```

### Audit Plugin Relevance

Ensure only relevant plugins are enabled for your project:

```bash
# See what plugins are relevant to this project
/health:check --scope=stack

# Preview changes without applying
/health:check --scope=stack --fix --dry-run

# Apply recommended changes
/health:check --scope=stack --fix
```

This analyzes your project's tech stack (package.json, Cargo.toml, Dockerfile, etc.) and recommends:
- Removing plugins that don't apply (e.g., kubernetes-plugin if no K8s manifests)
- Adding plugins that match detected technologies (e.g., container-plugin if Dockerfile exists)

### Find Unused Skills (Usage Telemetry)

Surface skills you have enabled but rarely or never invoke, mined from local
session transcripts (`~/.claude/projects/*/*.jsonl`):

```bash
# Never-fired + dormant (last invoked 30+ days ago) skills and plugin agents
/health:check --scope=usage

# List the offending skill/agent names, custom dormancy window
bash health-plugin/skills/health-check/scripts/check-usage.sh \
  --home-dir "$HOME" --project-dir "$(pwd)" --window-days 60 --verbose
```

Findings are **advisory review candidates** (a skill can be correct yet rarely
needed), feeding skill-consolidation and description-quality reviews. The audit
is read-only and **local-leaning**: it needs a long-running local install and
emits `STATUS=SKIP` in a fresh/remote checkout where there is no history. See
[ADR-0018](../docs/adrs/0018-health-usage-scope-from-session-telemetry.md).

### Permission Debugging

When tools are blocked unexpectedly, use the settings-configuration skill to understand:
- Settings file hierarchy (user → project → local)
- Permission wildcard patterns
- Shell operator protections

### Prune Config File

Clean up your `~/.claude.json` by removing orphaned projects and cached data:

```bash
# Preview what would be removed
python health-plugin/scripts/prune-claude-config.py --dry-run

# Interactive mode (confirm before changes)
python health-plugin/scripts/prune-claude-config.py --interactive

# Run immediately (creates backup automatically)
python health-plugin/scripts/prune-claude-config.py
```

The script removes:
- **Orphaned projects**: Entries for directories that no longer exist
- **Cached data**: `cachedChangelog`, `cachedStatsigGates`, `cachedDynamicConfigs`

Your settings, MCP servers, and tips history are preserved.

## Quick Reference

### Plugin Registry Location
```
~/.claude/plugins/installed_plugins.json
```

### Settings File Locations
| Scope | Path |
|-------|------|
| User | `~/.claude/settings.json` |
| Project | `.claude/settings.json` |
| Local | `.claude/settings.local.json` |

### Common Issues

| Symptom | Likely Cause | Command |
|---------|--------------|---------|
| Plugin not working | Wrong projectPath in registry | `/health:check --scope=registry --fix` |
| Irrelevant plugins enabled | No relevance audit done | `/health:check --scope=stack --fix` |
| Permission denied | Missing allow pattern | Check settings-configuration skill |
| Settings ignored | Invalid JSON | `/health:check` |
| Large ~/.claude.json | Orphaned projects/caches | `prune-claude-config.py` |

## Related

- [Claude Code Issue #14202](https://github.com/anthropics/claude-code/issues/14202) - Project-scoped plugin bug
- `configure-plugin` - Project infrastructure setup
- `hooks-plugin` - Hook configuration and automation

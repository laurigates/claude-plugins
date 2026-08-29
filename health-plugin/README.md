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
| `probe-delta.py` | Report only what is NEW since a probe's last run — reads any probe's `--format=json` on stdin against a recorded baseline |
| `lib/probe.py` | The finding / waiver / delta contract both of the above share. Stdlib only, imported as `from lib.probe import …` |

### `lib/probe.py` — the shared contract

What a probe must agree with other probes about, and nothing else: the
`Finding` shape, `fingerprint` (identity across runs), `Waivers` (pair-keyed,
self-expiring), `Baseline`/`Delta`, and the `STATUS=`/`ISSUE_COUNT=` renderers.
Thresholds, the corpus walk and the `check_*` functions deliberately stay in
`config-drift.py` — those are one probe's opinion, and a second probe adopting
them would be adopting a bug rather than a contract.

Two properties are load-bearing and easy to break:

- **`fingerprint` folds a singular `path` into the path set.** `config-drift.py`
  no longer emits `path` — every construction site passes `paths=[...]` — but
  `probe-delta.py` builds `Finding`s from an arbitrary JSON document, so the
  singular spelling still arrives from outside this repo: a saved report, a
  baseline recorded before the normalisation, an older installed plugin. Read as
  "`paths` only", every such finding collapses to one fingerprint per kind and
  the second of them is invisible in every delta report forever. Folding both
  spellings is also what made the normalisation itself baseline-neutral.
- **`Baseline` records the root it was taken at.** Fingerprints are built from
  absolute paths, so a baseline recorded at one root and compared at another
  yields a disjoint set — every finding new *and* every old one resolved. A root
  or schema mismatch loads as `None`, so the caller records a fresh baseline and
  stays silent.

### `probe-delta.py`

```
config-drift.py --format=json | probe-delta.py --probe config-drift --root <abs> --record
```

First run records the baseline and says nothing. Later runs report only new
findings; an empty or unparseable input is `STATUS=ERROR TYPE=analyzer_failed`,
never a clean sweep.

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

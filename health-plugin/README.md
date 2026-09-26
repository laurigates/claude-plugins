# health-plugin

Diagnose and fix Claude Code configuration issues including plugin registry, settings, hooks, and MCP servers.

## Installation

```bash
/plugin install health-plugin@laurigates-claude-plugins
```

## Skills

| Skill | Description |
|-------|-------------|
| `/health:check` | **Single entry point** when the broken layer is unknown. Diagnose (and optionally fix) Claude Code environment, plugin registry, project-stack fit, and skill agentic-optimisation — routed by `--scope`. |
| `/health:skill-audit` | Skill-overlap report for the plugin repo: skills that could answer the same request, split-pressure inside a SKILL.md, and merge candidates. Writes four reports to `tmp/skill-audit/`. |
| `plugin-registry` | Reference skill: Claude Code's plugin registry, install scopes, why a project can load an older plugin version than the rest of the machine, a capability declared in the marketplace but missing from the installed copy, and troubleshooting |
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
`Finding` shape, `fingerprint` (identity across runs), `Waivers` (pair and
single-path, content-hash-keyed, self-expiring), `Baseline`/`Delta`, and the
`STATUS=`/`ISSUE_COUNT=` renderers.
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

`--expect-baseline` is for a scheduled caller that knows it is **not** on its
first run, such as a workflow keeping the baseline in an evictable cache. There a
missing or untrusted baseline is a loss: every finding is re-reported beside a
`TYPE=baseline_lost` finding that names the cause (missing file vs. one recorded
at another root or schema), `FIRST_RUN=false BASELINE_LOST=true`, and the
baseline is re-recorded. Without the flag the same condition stays a silent
first run, which would swallow whatever appeared while the baseline was gone.

### `config-drift.py`

Answers a question the other health checks do not: **is the configuration
corpus self-consistent?** It compares documents against each other and against
the skill corpus, rather than validating any one file in isolation.

The corpus is four kinds — `.claude/rules/*.md` (plus `~/.claude/rules`),
`*/skills/*/SKILL.md`, `*-plugin/agents/*.md`, and `CLAUDE.md`. All four share
one document shape, and each check names the kinds it applies to explicitly:

| Check | Severity | Kinds | Catches |
|---|---|---|---|
| `broken_pointer_stub` | ERROR | rule | A "Promoted to a skill: invoke `x`" rule whose target no longer exists |
| `duplicate_rule_lexical` | WARN | rule | Byte-identical or near-identical rules across scopes |
| `duplicate_agent_lexical` | WARN | agent | Two agent prompts that have converged |
| `duplicate_claude_md_lexical` | INFO | claude_md | Two CLAUDE.md carrying the same guidance |
| `agent_discovery_misfire` | ERROR | agent | `*-plugin/agents` directories present but zero agent files — discovery is broken, not the tree clean |
| `semantic_overlap_*` | WARN | rule, skill | Differently-worded rules or skills covering one topic |
| `rule_covered_by_skill` | INFO | rule | A resident rule whose content a skill already carries |
| `promotion_candidate` | INFO | rule, claude_md | The same guidance at two scopes with no declared parent — a candidate for `/agent-patterns:meta-promote`. **Semantic tier only** |
| `always_loaded_budget` | WARN | rule, claude_md | The every-turn surface creeping past its ceiling |
| `review_staleness` | WARN | all four | An artifact changed after its declared `reviewed:` date |
| `frontmatter_coverage` | INFO | rule | Rules with no `reviewed:` date, so staleness cannot be tracked |

`duplicate_claude_md_lexical` is INFO rather than WARN because a CLAUDE.md pair
is very often duplication that is *correct* — a vendored clone and its upstream,
or one package copied into two places — and the analyzer cannot tell that from a
divergence. Two `.claude/rules/` scopes, and two `*-plugin/agents/*.md` in one
marketplace, are both live and both loaded, so duplication there really is drift.

**`promotion_candidate` and the threshold that cannot do the job alone.**
`T_PROMOTE = 0.88` sits below `T_SEMANTIC = 0.91` because at 0.91 this root
yields zero findings — shipping at the drift threshold would ship the verdict
inert. But the score is not what makes it precise: the declared hierarchy
(`offload-to-deterministic-substrate` at two scopes, 0.8994) outscores the
genuine candidate (`auto-mode` ← `claude-code-auto-mode`, 0.8990) by 0.0004. No
cut separates them; `structural_pair` does. Two further constraints carry more
weight than the number — an **ancestor** test, because `scope_rank` is depth and
would otherwise pair unrelated repos (69 → 22 pairs at `~/repos`), and a
**500-char floor**, because near-empty redirect stubs score 0.88–0.98 against
each other (22 → 12).

Known limitation: a hierarchy declared in a **third** document is invisible —
`structural_pair` reads only the two documents in the pair. The six
`ForumViriumHelsinki/.github` pairs are exactly this shape, declared in that
workspace's own `CLAUDE.md`. Closing it needs a third-document signal with its
own calibration. Run the expensive tier with `just config-drift-semantic`.

Agents are discovered through the same **recursive pruned walk** as every other
kind (`*-plugin/agents`), not a depth-anchored glob: the SessionStart probe scans
the session cwd, and a portfolio root sits one or two levels above where plugins
live. `AGENT_DIRS=` is the denominator that makes `AGENTS=0` legible — beside a
nonzero `AGENT_DIRS` it is a misfire, beside `AGENT_DIRS=0` it is a clean tree.

The lexical comparison is **partitioned by kind** — each kind is compared only
against itself. A high Jaccard between an agent prompt and a rule is not a
duplicate rule, and pooling costs 9x the partitioned run on this corpus.
`LEXICAL_PAIRS=` in the status block reports how many pairs were compared, so
the partition is assertable rather than implicit.

A `CLAUDE.md` holding **generator template** payload is excluded — it is content
for a repo that does not exist yet, not configuration that loads anywhere. Two
signals *declare* a template and are sufficient alone: an unrendered path
component (`{{cookiecutter.project_slug}}/`), or a generator manifest
(`cargo-generate.toml` / `cookiecutter.json` / `copier.y{a,}ml` / `cruft.json`)
at a **strict ancestor**. Two more only *suggest* it and need each other: a
`template`/`templates` path component, and either a manifest sitting beside the
document or an npm `create-*` parent. A bare `templates/` component is never
enough on its own — a Flask or Django `app/templates/` is a Jinja directory whose
CLAUDE.md is live configuration. The root's own `CLAUDE.md` is never excluded.
`CLAUDE_MD_TEMPLATES_EXCLUDED=` is emitted even at 0.

Two cost tiers, because a SessionStart probe cannot pay for a model:

```
config-drift.py --fast --no-embed --format=json    # 0.33s, pure stdlib, no git spawn
config-drift.py --format=report                    # + embeddings, scheduled use
```

`--fast` reads cached last-change dates only; the cache is keyed by **content
hash**, never mtime, so it cannot go stale and cannot be invalidated by a
checkout that rewrites timestamps.

**Waivers.** A finding judged not to be a defect is suppressed by a waiver that
records the content hash of every file it vouches for, so it expires the moment
one of them is edited. Without that, a recurring report re-lists its
known-accepted findings until you stop reading it. `--waivers` defaults to the
operator-local `~/.claude/config-drift-waivers.json`; this repo's own corpus has
a committed, reviewed file at `health-plugin/config-drift-waivers.json`, which
`just config-drift-semantic` reads. Two entry forms share one file:

| Form | Keys | Suppresses |
|---|---|---|
| pair | `a`, `b`, `a_hash`, `b_hash`, `reason` | every pairwise kind over that pair: the lexical and semantic duplicates, `rule_covered_by_skill`, `promotion_candidate` |
| single-path | `kind`, `path`, `hash`, `reason` | that one kind on that one file: `review_staleness`, `broken_pointer_stub` |

A relative path resolves against `--root`, which is what makes the committed
file mean the same thing on a CI runner; absolute and `~/` paths are unchanged.
Six kinds are aggregates or probe-health signals with no file to hash, and are
declared unwaivable in `WAIVER_EXEMPT_KINDS` with their reasons.

Hashes are never written by hand. `--format=waivers` prints a draft entry, hash
filled in, for every waivable finding the run reports (so against an existing
file, exactly the new and revived findings); keep the entries you judge
non-defects and write each `reason`. `WAIVERS_ACTIVE` / `WAIVERS_MATCHED` /
`WAIVERS_SKIPPED` read together: `MATCHED` below `ACTIVE` means a waived file
was edited or removed (in the cheap tier the semantic-pair waivers cannot match
by construction), and `SKIPPED` counts malformed entries, each named on stderr.

**Semantic threshold.** The embedding pass is calibrated to cosine ≥ 0.91 with
same-name and structural pairs excluded. This is not a default worth changing
casually: at 0.86 on a real 884-document corpus it emitted 491 findings, of
which 290 were same-name pairs the cheap tier already owns. Everything here is
one genre of document, so baseline similarity is high.

### Scheduled CI audit

`.github/workflows/config-drift-audit.yml` (**Plugin: Config drift audit**) runs
the semantic tier over this repository's own corpus on Mondays and Thursdays and
comments only what is new into one rolling issue labelled `config-drift`. No
Claude model runs; the cost is Actions minutes. The decisions live in
`scripts/config-drift-audit.sh` and are tested by
`scripts/tests/test-config-drift-audit.sh`.

It complements the portfolio run tracked in #2319 rather than replacing it:

| | CI audit | Portfolio run (#2319) |
|---|---|---|
| Corpus | this checkout: rules, skills, agents, `CLAUDE.md` in git | `~/repos` and `~/.claude/rules`, the fleet `T_PROMOTE` was calibrated on |
| Waivers | committed `health-plugin/config-drift-waivers.json` | operator-local `~/.claude/config-drift-waivers.json` |
| A finding is | fixable by a PR to this repo | often in another repo or in home config |

- **State.** The baseline and both caches share one `actions/cache` entry, saved
  under a fresh key each run and restored by prefix; the model has its own. An
  entry not read for 7 days is evicted, so a weekly schedule would lose the
  baseline whenever a run started late. That is why the audit runs twice a week.
- **First run vs. lost baseline.** The first completed run records silently.
  After that, a missing baseline is a loss: `probe-delta.py --expect-baseline`
  re-reports every finding beside a `baseline_lost` row instead of re-recording
  in silence.
- **Exit codes.** Analyzer exit 0 and 1 are completed runs, and so is exit 2
  under `--gate` (next item). Any other code, or empty output, posts an error
  comment, fails the job, and leaves the baseline untouched. A run whose model
  failed to load is reported but does not roll the baseline forward.
- **Red state.** The analyzer runs with `--gate`, so an error-severity finding
  (`broken_pointer_stub`, `agent_discovery_misfire`, `coverage_metric_broken`)
  makes it exit 2. That run still completes: the finding is commented once and
  recorded like any other. The job then fails on every run for as long as the
  finding persists, including the first run. Warn and info findings never fail
  the job; they only reach the rolling issue.
- **Control.** Dispatch with `plant_control: true` to check the delta logic end
  to end. The run plants two unrelated rules one scope apart, injects a 0.95
  similarity through `--sim-fixture`, and fails unless exactly that pair comes
  back as one new `promotion_candidate`.

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

# ADR-009: Standalone-Install Prompt Fallback

- **Status:** Accepted
- **Date:** 2026-05-07
- **Deciders:** @laurigates

## Context

`git-repo-agent` lives inside the `claude-plugins` monorepo. At runtime
its prompt compiler (`prompts/compiler.py`) reads SKILL.md files from
sibling plugins (e.g. `blueprint-plugin/skills/blueprint-init/SKILL.md`)
to build subagent system prompts and per-phase blueprint prompts.

Issue #1017 proposes extracting `git-repo-agent` into its own repository
so it can be installed via `uv tool install git-repo-agent` /
`uvx git-repo-agent`. The blocker is the runtime dependency on sibling
plugin checkouts: a standalone install has no `claude-plugins/` parent
directory and no `*-plugin/skills/` siblings.

## Decision

Add a fallback path to the compiler so the package can run in two modes:

1. **Monorepo (dev) mode.** Sibling plugin sources exist under
   `_PLUGINS_ROOT`. Live-compile from `SKILL.md` for both subagent
   prompts and per-phase blueprint skills.

2. **Standalone (installed) mode.** Sibling sources are absent. Read
   pre-compiled artifacts from `prompts/generated/`:
   - Subagent prompts: `prompts/generated/<subagent>_skills.md`
   - Blueprint per-phase skills:
     `prompts/generated/skills/<plugin>/<skill-name>.md`

Mode selection happens per skill: `_plugin_skill_available()` probes
`_PLUGINS_ROOT / skill_relpath`, so a partial-monorepo checkout still
falls back to the generated artifact for any missing skill.

The build script (`scripts/compile_prompts.py`) writes both artifact
trees and exposes a `--check` mode for CI to detect drift between
sources and pre-compiled output.

## Why pre-compilation, not alternatives

| Option | Why not |
|---|---|
| Git submodule pulling in `claude-plugins` | Heavy (many MB) for ~328 KB of derived markdown |
| Separate PyPI package for prompts | Over-engineered for static markdown |
| Runtime download from GitHub | Adds network dependency and offline failure modes |

Pre-compiled markdown is small (~328 KB), version-pinned with the
package, and lets `uv tool install` work from PyPI alone.

## Implications

- Cross-repo regeneration: when extraction lands, the monorepo CI must
  push regenerated `generated/` files into the standalone repo
  whenever upstream `SKILL.md` files change. Per-skill granularity
  keeps the regeneration footprint small.
- Test coverage: `tests/test_compiler_standalone.py` simulates
  standalone mode by repointing `_PLUGINS_ROOT` at an empty directory
  and verifies every subagent and every blueprint-driver-referenced
  skill has a fallback.
- The compiler does **not** distinguish silently between live and
  fallback output; both go through the same caching and rendering path.

## Status

Lays the groundwork for #1017 (repo extraction). Subsequent steps
(creating `laurigates/git-repo-agent`, cross-repo workflow, monorepo
cleanup) are tracked separately.

# ADR-0006: Standalone-Install Prompt Fallback

- Status: Accepted
- Date: 2026-07-10

## Context

`vault-agent` lives inside the `claude-plugins` monorepo. At runtime its
prompt compiler (`prompts/compiler.py`) reads SKILL.md files from the
sibling `obsidian-plugin` (e.g.
`obsidian-plugin/skills/vault-frontmatter/SKILL.md`, per ADR-0005) to
build the four maintenance subagents' system prompts.

Issue [#1973](https://github.com/laurigates/claude-plugins/issues/1973)
proposes extracting `vault-agent` into its own repository so it can be
installed via `uv tool install vault-agent` / `uvx vault-agent`. The
blocker is the runtime dependency on the sibling plugin checkout: a
standalone install has no `claude-plugins/` parent directory and no
`obsidian-plugin/skills/` sibling, so `get_compiled_prompt()` would
compile empty prompts.

This mirrors the problem `git-repo-agent` already solved in its ADR-009.

## Decision

Add a fallback path to the compiler so the package can run in two modes:

1. **Monorepo (dev) mode.** Sibling plugin sources exist under
   `_PLUGINS_ROOT`. Live-compile from `SKILL.md` for both subagent
   prompts and per-skill fragments. Behaviour is unchanged from before.

2. **Standalone (installed) mode.** Sibling sources are absent. Read
   pre-compiled artifacts from `prompts/generated/`:
   - Subagent prompts: `prompts/generated/<subagent>_skills.md`
   - Per-skill fragments:
     `prompts/generated/skills/<plugin>/<skill-name>.md`

`_plugin_skill_available()` probes `_PLUGINS_ROOT / skill_relpath`.
`get_compiled_prompt()` live-compiles when any of a subagent's skills is
present and falls back to the pre-compiled bundle otherwise;
`get_compiled_skill()` falls back per skill, raising `FileNotFoundError`
only when neither the source nor a generated artifact exists.

The build script (`scripts/compile_prompts.py`) writes both artifact
trees and exposes a `--check` mode for CI to detect drift between
sources and pre-compiled output. Unlike `git-repo-agent`'s script it does
**not** statically parse a blueprint driver — `vault-agent` has no
blueprint state machine, so the per-skill artifacts are exactly the union
of the skills the `SUBAGENT_SKILLS` bundles reference.

## Why pre-compilation, not alternatives

| Option | Why not |
|---|---|
| Git submodule pulling in `claude-plugins` | Heavy (many MB) for a handful of derived markdown files |
| Separate PyPI package for prompts | Over-engineered for static markdown |
| Runtime download from GitHub | Adds a network dependency and offline failure modes |

Pre-compiled markdown is small, version-pinned with the package, and lets
`uv tool install` work from PyPI alone.

## Implications

- Cross-repo regeneration: when extraction lands (later phases of #1973),
  the monorepo CI must push regenerated `generated/` files into the
  standalone repo whenever upstream `SKILL.md` files change. Per-skill
  granularity keeps the regeneration footprint small.
- Test coverage: `tests/test_compiler_standalone.py` simulates standalone
  mode by repointing `_PLUGINS_ROOT` at an empty directory and verifies
  every subagent and every referenced skill has a fallback (the regression
  guard for this fix).
- The compiler does **not** distinguish silently between live and fallback
  output; both go through the same caching and rendering path.

## Status

This is Phase 0 of #1973 — the standalone-install prerequisite. Subsequent
phases (creating `laurigates/vault-agent`, PyPI publish, cross-repo sync
workflow, monorepo cleanup) are tracked separately and require manual
owner actions.

## Related

- ADR-0005 (skill-source-obsidian-plugin) — where the source SKILL.md
  files live and why.
- `git-repo-agent`'s ADR-009 (standalone-install-prompt-fallback) — the
  proven template this mirrors.

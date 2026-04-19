# ADR-007: `git-repo-agent new` — Pre-Claude-Session Genesis Orchestrator

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** @laurigates

## Context

Before this decision, `git-repo-agent` operated only on existing repositories:
`onboard`, `maintain`, `diagnose`, `route`. To start a new project the user
had to manually run `mkdir`, `git init`, populate `.gitignore` / README /
initial PRD, write `.claude/settings.json` (or rely on `claude` later running
`/configure:claude-plugins`), then `gh repo create`, then finally `claude`.
Every step was a chance for inconsistency and lost intent.

The desired workflow is a single shell command:

```sh
git-repo-agent new "Telegram chat bot that replies to user messages"
# → creates repo, scaffolds it, enrolls marketplace + stack-appropriate
#   plugins, pushes to GitHub, and leaves the user one `cd` + `claude`
#   away from an interactive-ready session.
```

The friction point that motivated this ADR: **by the time the user runs
`claude`, the marketplace and plugin list must already be configured.**
A workflow that requires running `claude` once just to execute
`/configure:claude-plugins` and then reloading is strictly worse than no
workflow.

## Decision

Add a top-level `new` command to `git-repo-agent` that orchestrates the
full pre-Claude-session pipeline in a single process.

### Pipeline

| Phase | Module | Side effects | Failure mode |
|-------|--------|--------------|--------------|
| 1. Intent parsing | `intent.py` | SDK one-shot; no filesystem changes | Hard-fail (exit 1). No fallback. |
| 2. Local genesis | `creator.py` | `mkdir`, `git init -b main`, templates, `.claude/settings.json`, initial commit | Hard-fail (exit 2). |
| 3. Blueprint init | `blueprint_driver.py` (NEW_PHASES) | SDK session; creates `docs/blueprint/*`, second commit | Soft-fail — warn, continue. |
| 4. GitHub push | `creator.gh_repo_create` | `gh repo create --source=. --push` | Hard-fail if `--no-remote` wasn't passed. |

Each phase is optional via its own flag (`--name`/`--language` skip Phase 1;
`--skip-blueprint` skips Phase 3; `--no-remote` skips Phase 4). `--dry-run`
short-circuits all filesystem and network side effects after reporting the plan.

### Plugin enrollment happens *before* any Claude Code session

`.claude/settings.json` is written in Phase 2 (pure Python — no SDK). It
includes:

- `extraKnownMarketplaces.claude-plugins` → enrolls the
  `laurigates/claude-plugins` marketplace so the first `claude` session
  sees it.
- `enabledPlugins` → stack-appropriate plugins from
  `plugin_enroller.STACK_PLUGINS`.
- `permissions.allow` → common baseline + stack-specific Bash patterns.

The `STACK_PLUGINS` mapping mirrors the "Recommended Plugins" table in
`configure-plugin/skills/configure-claude-plugins/SKILL.md`, with a drift
test (`tests/test_plugin_enroller.py::TestSkillMdDrift`) that fails CI if
either side is updated without the other.

### Why `BlueprintDriver(NEW_PHASES)` instead of the full onboard pipeline

The existing `ONBOARD_PHASES` runs `blueprint-init` followed by
`derive-prd`, `derive-adr`, `derive-rules`, `derive-tests`, `sync-ids`,
`adr-validate`, and `feature-tracker-sync`. All the derive-* phases mine
existing source material (git history, docs, code) that a brand-new repo
does not have. Running them on a fresh repo would at best produce empty
artifacts and at worst hallucinate plausible-looking content.

`NEW_PHASES` runs only `blueprint-init` — the one phase that is actually
useful for a new repo. The seed PRD written in Phase 2
(`docs/prds/0001-project-goal.md`) registers itself in the blueprint manifest
during this phase.

Users who want the full derive-* pipeline can run `git-repo-agent onboard`
on the new repo later. That's intentionally not part of `new` because it
requires the human to iterate on the seed PRD first.

### Why genesis goes on `main` directly (no worktree)

`run_onboard` uses a worktree on `setup/onboard` so changes stay isolated
from the user's working state until a PR is merged. That model doesn't
apply to a fresh repo: there is no prior state to protect, no base branch
to fast-forward, no PR to open before the repo even has a remote. Genesis
commits directly to `main`, and subsequent phases (blueprint-init) land as
their own follow-up commits on the same branch.

This is why `new` deliberately does **not** reuse `run_onboard` — the
worktree machinery is unnecessary overhead for a fresh repo, and forcing
`run_onboard` to branch on "is this a new repo" would muddle its contract.

### Why intent parsing hard-fails on SDK unreachability

The primary value of `new` over `mkdir && git init && ...` is
stack-appropriate plugin enrollment. Without intent parsing the tool would
either (a) require the user to provide `--name` + `--language` explicitly
(which defeats the "single command" UX), or (b) produce a default scaffold
with only the always-on plugins (which is strictly worse than letting the
user try again later).

The user can still bypass intent parsing by passing `--name` explicitly —
that's the escape hatch for offline / air-gapped environments.

## Consequences

### Positive

- **One command** from idea to interactive-ready repo.
- **Plugin enrollment happens pre-session** — the user's first `claude`
  invocation already sees the right marketplace and plugins.
- **Each phase is independently testable**: the drift test covers plugin
  selection, unit tests cover genesis, and the integration test (`cd
  <repo> && claude`) covers the contract.
- **Existing commands untouched.** `onboard`, `maintain`, `diagnose`,
  `route` continue to operate on existing repos exactly as before.

### Negative

- Intent parsing adds a Claude API dependency to a shell command. Users
  can opt out with `--name` / `--language`.
- `new` is not idempotent — running it twice against the same `<parent>/<slug>`
  fails with `FileExistsError`. That's by design; we don't want to
  silently "resume" an interrupted genesis when the user can diagnose
  and retry themselves.

### Neutral

- `NEW_PHASES` is a separate registry key under `PHASE_REGISTRIES["new"]`,
  so the `blueprint` CLI subcommand could expose it later (`git-repo-agent
  blueprint new <path>`) without extra wiring. No current plans to do so.

## Related

- **ADR-001** — pre-computed context pattern, reused in Phase 3.
- **ADR-003** — `ClaudeSDKClient` multi-turn pattern, reused in Phase 1.
- **ADR-006** — `BlueprintDriver` state machine, reused in Phase 3.
- `configure-plugin/skills/configure-claude-plugins/SKILL.md` — the
  source-of-truth plugin mapping that `plugin_enroller.STACK_PLUGINS`
  mirrors.

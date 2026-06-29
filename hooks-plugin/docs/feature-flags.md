# Feature Flags Catalog

A single index of the **environment variables that toggle or tune plugin
behavior** across this marketplace. Without it, the flags are discoverable only
by grepping the hook sources — exactly the drift `documentation-authoring.md`
warns against.

Each row points at its **source file**, which is the authoritative definition
(default value + logic). This catalog is a signpost, not a second copy of the
logic — when a flag's behavior is in question, read the source.

Three shapes:

- **Opt-in** — the feature is **off** until you set the flag. New experimental /
  teaching behaviors default off so they don't surprise.
- **Opt-out** — the feature is **on** until you set the flag. Guardrails default
  on, with the flag as an escape hatch.
- **Tunable** — a value (path, timeout, threshold), not a boolean on/off.

> Scope: only plugin-defined flags are cataloged. Claude Code **harness** flags
> (`CLAUDE_CODE_*`, `ENABLE_TOOL_SEARCH`, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`,
> …) are documented by Claude Code, not here.

## Opt-in (OFF by default → `export <FLAG>=1` to enable)

| Flag | Enables | Plugin · source |
|---|---|---|
| `CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH` | PostToolUse "teach" hook — augments tool output with a non-blocking nudge instead of blocking (carries the `find→Glob` and other soft nudges) | hooks · `hooks/bash-antipatterns-teach.sh` |
| `CLAUDE_HOOKS_ENABLE_CALENDAR_ESTIMATES` | Stop hook nudging the agent to restate estimates in tokens / effort tiers instead of calendar time | hooks · `hooks/no-calendar-estimates.sh` |
| `CLAUDE_HOOKS_ENABLE_EVENT_LOGGER` | Dev/debug hook logging every hook event to a file | hooks · `hooks/event-logger.sh` |

**Non-env opt-in:** the taskwarrior **native hooks** (`on-modify`, `on-exit`
ghsync queue) are installed by running `/taskwarrior:install-native-hooks` — an
explicit action, not an env flag. Their own opt-out knobs are listed below.

## Opt-out (ON by default → `export <FLAG>=1` to disable)

### hooks-plugin

| Flag | Disables | Source |
|---|---|---|
| `CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION` | Blocking access to secret files / env-var exposure | `hooks/secret-protection.sh` |
| `CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION` | Blocking writes on `main`/`master` (**human-operator only** — inline prefixes are ignored so agents can't self-serve) | `hooks/branch-protection.sh` |
| `CLAUDE_HOOKS_DISABLE_AUTO_CHECKPOINT` | Auto-stash checkpoint before destructive git/`rm -rf` ops | `hooks/auto-checkpoint.sh` |
| `CLAUDE_HOOKS_DISABLE_PERMISSION_AUTO` | Auto-approve/deny of safe/dangerous ops at PermissionRequest | `hooks/permission-auto-approve.sh` |
| `CLAUDE_HOOKS_DISABLE_PERMISSION_REQUEST` | The permission-request hook | `skills/hooks-permission-request-hook/` |
| `CLAUDE_HOOKS_DISABLE_TASK_COMPLETENESS` | Stop-hook heuristics for incomplete work (TODO/conflict markers/debug artifacts) | `hooks/task-completeness.sh` |
| `CLAUDE_HOOKS_DISABLE_TEST_VERIFICATION` | Stop-hook reminder to run tests when code changed | `hooks/test-verification.sh` |
| `CLAUDE_HOOKS_DISABLE_DRIFT_NUDGE` | The consolidated drift-aggregator SessionStart nudge | `hooks/drift-aggregator.sh` |

### git-plugin

| Flag | Disables | Source |
|---|---|---|
| `CLAUDE_HOOKS_DISABLE_BRANCH_SYNC` | PreToolUse nudge when a PR branch is behind / merged before commit/push | `git-plugin/hooks/check-branch-sync-on-push.sh` |

### taskwarrior-plugin

| Flag | Disables | Source |
|---|---|---|
| `CLAUDE_TASKWARRIOR_DRIFT_NO_RECONCILE` | The reconcile dry-run portion of the drift probe | `hooks/taskwarrior-drift-probe.sh` |
| `CLAUDE_TASKWARRIOR_DRIFT_NO_STALE_CLAIMS` | The stale-`+ACTIVE`-claim portion of the drift probe | `hooks/taskwarrior-drift-probe.sh` |
| `CLAUDE_TASKWARRIOR_NO_GHSYNC_QUEUE` | Draining the on-exit ghsync queue in the probe | `hooks/taskwarrior-drift-probe.sh` |
| `CLAUDE_TASKWARRIOR_NO_SCHEDULED_RECONCILE` | The scheduled (LaunchAgent) reconcile run | `scripts/scheduled-reconcile.sh` |
| `CLAUDE_TASKWARRIOR_RECONCILE_NO_DESKTOP` | Desktop notification from scheduled reconcile | `scripts/scheduled-reconcile.sh` |
| `CLAUDE_TASKWARRIOR_RECONCILE_NO_TELEGRAM` | Telegram notification from scheduled reconcile | `scripts/scheduled-reconcile.sh` |
| `CLAUDE_TASKWARRIOR_NO_MARKER_UPKEEP` | Session-marker upkeep in the native `on-exit` hook | `skills/install-native-hooks/templates/on-exit-taskwarrior-plugin` |
| `CLAUDE_TASKWARRIOR_NO_CLAIM_EXPIRY` | Claim-expiry handling in the native `on-modify` hook | `skills/install-native-hooks/templates/on-modify-taskwarrior-plugin` |

## Tunables (a value, not on/off)

| Flag | Default | Controls | Source |
|---|---|---|---|
| `CLAUDE_HOOKS_EVENT_LOG` | `~/.claude/hook-events.log` | Event-logger output path | `hooks/event-logger.sh` |
| `CLAUDE_HOOKS_EVENT_LOGGER_VERBOSE` | off | Log full JSON input (vs one-line summary) | `hooks/event-logger.sh` |
| `CLAUDE_HOOKS_TEST_TIMEOUT` | `45` (s) | Test-verification timeout | `hooks/test-verification.sh` |
| `CLAUDE_HOOKS_BRANCH_SYNC_TTL` | `300` (s) | Per-session+branch sync-check cache TTL | `git-plugin/hooks/check-branch-sync-on-push.sh` |
| `CLAUDE_TASKWARRIOR_DRIFT_STALE_TTL` | `14400` (s) | Age before a `+ACTIVE` claim counts as stale | `hooks/taskwarrior-drift-probe.sh` |
| `CLAUDE_TASKWARRIOR_DRIFT_STALE_LIMIT` | `50` | Max stale claims reported | `hooks/taskwarrior-drift-probe.sh` |
| `CLAUDE_TASKWARRIOR_DRIFT_CACHE_DIR` | `$TMPDIR/claude-taskwarrior-drift` | Drift-probe cache location | `scripts/drain-ghsync-queue.sh` |
| `CLAUDE_TASKWARRIOR_GHSYNC_QUEUE` | (unset) | ghsync queue file path | `scripts/drain-ghsync-queue.sh` |
| `CLAUDE_TASKWARRIOR_CLAIM_TTL_HOURS` | see source | Native-hook claim TTL | `skills/install-native-hooks/templates/on-modify-taskwarrior-plugin` |

## Keeping this current

This table is a hand-maintained index, so it can drift from the sources. To
re-derive the full flag set (the authoritative truth) and spot anything missing:

```
rg -oN --no-filename 'CLAUDE_HOOKS_[A-Z_]+|CLAUDE_TASKWARRIOR_[A-Z_]+' -g '*.sh' -g 'templates/*' */ | sort -u
```

Any flag that one-liner prints which is absent from the tables above is a gap to
backfill. (A pre-commit coverage guard that fails when a source flag is missing
from this catalog would make the drift deterministic rather than relying on the
grep — a reasonable follow-up.)

## Related

- `hooks-plugin/README.md` — per-hook behavior tables (the deep detail each row here points at)
- `hooks-plugin/docs/teach-mode-experiment.md` — rationale for the opt-in teach hook
- `.claude/rules/bash-tool-replacements.md` — what the teach hook nudges toward
- `.claude/rules/pr-branch-sync.md` — the branch-sync guard family
- `.claude/rules/drift-detection-triggering.md` — the taskwarrior drift-probe design

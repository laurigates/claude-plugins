# Behavioral Cue Registry

Hand-maintained audit table of all hook-based behavioral cues in the
repository, mandated by ADR-0017 (Risks table: "Registry doc lists all
cues, events, dedup keys for audit"). Update this table whenever a new
cue hook is added, modified, or removed.

A future generator could produce this from `*/hooks.json` files by
scanning for hooks whose scripts match `*-cue.sh` or `*-nudge.sh`; for
now this file is hand-maintained.

## Cue Registry

| Hook script | Plugin | Event | Matcher | Channel | Dedup key | Trigger summary |
|---|---|---|---|---|---|---|
| `blueprint-plugin/hooks/blueprint-structural-cue.sh` | `blueprint-plugin` | `PostToolUse` | `Edit\|Write` | `updatedToolOutput` | `~/.cache/blueprint-structural-cue/<session_id>` | Manifest edit (`plugin.json`, `marketplace.json`), public-symbol/export line, TS `export interface/type`, exported Go/Rust types, route registration, or schema/IDL files (`*.proto`, `*.graphql`, `openapi*`) — widened by #1616. Excludes `docs/adrs/**` and `docs/prds/**`. Bypass: `BLUEPRINT_SKIP_HOOKS=1`. |
| `codebase-attributes-plugin/hooks/attributes-health-cue.sh` | `codebase-attributes-plugin` | `SessionStart` | `""` (all) | `additionalContext` | `~/.cache/attributes-health-cue/<session_id>` | `.claude/attributes.json` present in project root. _(PR #1619, pending merge.)_ |
| `session-plugin/hooks/session-end-nudge.sh` | `session-plugin` | `Stop` | _(none)_ | `decision:block` | `~/.cache/claude-session-end-nudge/<session_id>` | ≥6 genuine user turns + wind-down phrase in last 3 user messages + distillable surface (taskwarrior or `.claude/rules/`/justfile). Skips when session-wrap/end/distill skill already in transcript. Appends taskwarrior state-sync cue when open tasks exist (#1618). |
| `code-quality-plugin/hooks/code-quality-preflight-cue.sh` | `code-quality-plugin` | `PostToolUse` | `Edit\|Write` | `decision:block` + `continueOnBlock` | `~/.cache/code-quality-preflight-cue/<session_id>` | Large or structurally significant edit. _(PR #1623, pending merge.)_ |
| `session-plugin/hooks/session-spinup-nudge.sh` | `session-plugin` | `SessionStart` | `""` (`startup\|resume` only) | `additionalContext` | `~/.cache/claude-session-spinup-nudge/<session_id>` | Uncommitted changes, unpushed commits, or open taskwarrior tasks for the project at session start. Pre-ADR-0017; included for completeness. |
| `hooks-plugin/hooks/bash-antipatterns-teach.sh` | `hooks-plugin` | `PostToolUse` | `Bash` | `updatedToolOutput` | `${TMPDIR}/claude-bash-teach-seen/<session_id>` | Soft-teach antipatterns: `cat file`→Read; `head`/`tail file`→Read with offset/limit; `find -name` without discovery flags→Glob; standalone `grep`/`rg`→Grep; `ls *glob*`→Glob. Opt-in: no-ops unless `CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1`. Pre-ADR-0017; included for completeness. |

## Collision Audit

Two rows fire on `PostToolUse` with matcher `Edit|Write`:

| Cue | Detection focus |
|-----|----------------|
| `blueprint-structural-cue.sh` | Manifests and public-symbol export lines |
| `code-quality-preflight-cue.sh` _(#1623, pending)_ | Large or structurally significant edits |

Both hooks may fire on the same edit event. Mitigations:

- **Disjoint per-session dedup keys** — each hook maintains its own marker
  file under a different cache path; firing one never suppresses the other.
- **Idempotent fire-once markers** — each cue fires at most once per session
  regardless of how many overlapping edits occur.
- **Different channels** — `blueprint-structural-cue.sh` uses
  `updatedToolOutput`; `code-quality-preflight-cue.sh` uses
  `decision:block + continueOnBlock`. They do not interfere at the harness level.
- **Cross-plugin hook order is not guaranteed** — the harness may run the two
  hooks in any order; neither assumes the other has or has not fired.

If both cues fire on the same edit, the model receives two independent signals
in the same turn — acceptable but worth monitoring for cue fatigue. If overlap
grows, consider merging the hooks or adding an explicit mutual-exclusion guard.
Authors of future `Edit|Write` PostToolUse cues should document their detection
logic here before merge.

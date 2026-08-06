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
| `blueprint-plugin/hooks/blueprint-structural-cue.sh` | `blueprint-plugin` | `PostToolUse` | `Edit\|Write` | `decision:block` + `continueOnBlock` | `~/.cache/blueprint-structural-cue/<session_id>` | Manifest edit (`plugin.json`, `marketplace.json`), public-symbol/export line, TS `export interface/type`, exported Go/Rust types, route registration, or schema/IDL files (`*.proto`, `*.graphql`, `openapi*`) — widened by #1616. Excludes `docs/adrs/**` and `docs/prds/**`. Bypass: `BLUEPRINT_SKIP_HOOKS=1`. |
| `codebase-attributes-plugin/hooks/attributes-health-cue.sh` | `codebase-attributes-plugin` | `SessionStart` | `""` (all) | `additionalContext` | `~/.cache/attributes-health-cue/<session_id>` | `.claude/attributes.json` present in project root. |
| `session-plugin/hooks/session-end-nudge.sh` | `session-plugin` | `Stop` | _(none)_ | `decision:block` | `~/.cache/claude-session-end-nudge/<session_id>` | ≥6 genuine user turns + wind-down phrase in last 3 user messages + distillable surface (taskwarrior or `.claude/rules/`/justfile). Skips when session-wrap/end/distill skill already in transcript. Appends taskwarrior state-sync cue when open tasks exist (#1618). |
| `code-quality-plugin/hooks/code-quality-preflight-cue.sh` | `code-quality-plugin` | `PostToolUse` | `Edit\|Write` | `decision:block` + `continueOnBlock` | `~/.cache/code-quality-preflight-cue/<session_id>` | Public-symbol line, manifest (`plugin.json`, `marketplace.json`, `package.json`, `Cargo.toml`, `pyproject.toml`), or payload ≥50 lines; excludes docs/tests/lockfiles. |
| `session-plugin/hooks/session-spinup-nudge.sh` | `session-plugin` | `SessionStart` | `""` (`startup\|resume` only) | `additionalContext` | `~/.cache/claude-session-spinup-nudge/<session_id>` | Uncommitted changes, unpushed commits, or open taskwarrior tasks for the project at session start. Pre-ADR-0017; included for completeness. |
| `hooks-plugin/hooks/bash-antipatterns-teach.sh` | `hooks-plugin` | `PostToolUse` | `Bash` | `updatedToolOutput` (object, merged into `.stdout` — #2275) | `${TMPDIR}/claude-bash-teach-seen/<session_id>` | Soft-teach antipatterns: `cat file`→Read; `head`/`tail file`→Read with offset/limit; `find -name` without discovery flags→Glob; standalone `grep`/`rg`→Grep; `ls *glob*`→Glob. Opt-in: no-ops unless `CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1`. Pre-ADR-0017; included for completeness. |

## Collision Audit

Two rows fire on `PostToolUse` with matcher `Edit|Write`:

| Cue | Detection focus |
|-----|----------------|
| `blueprint-structural-cue.sh` | Manifests and public-symbol export lines |
| `code-quality-preflight-cue.sh` | Large or structurally significant edits |

Both hooks may fire on the same edit event. Mitigations:

- **Disjoint per-session dedup keys** — each hook maintains its own marker
  file under a different cache path; firing one never suppresses the other.
- **Idempotent fire-once markers** — each cue fires at most once per session
  regardless of how many overlapping edits occur.
- **Same channel, independent state** — as of issue #2275 **both** hooks emit
  `decision:block` + `continueOnBlock`. (`blueprint-structural-cue.sh` formerly
  used `updatedToolOutput`, which is validated against the tool's own output
  shape; Write/Edit has no free-text field there, so the cue was silently
  discarded and the hook was a no-op.) The earlier "different channels, they do
  not interfere" argument no longer holds and is **not** what makes co-existence
  safe. What does: the two hooks share no state — separate cache paths, separate
  fire-once markers — and each carries `continueOnBlock: true`, so neither ends
  the turn and neither can suppress or be suppressed by the other.
- **Cross-plugin hook order is not guaranteed** — the harness may run the two
  hooks in any order; neither assumes the other has or has not fired.

**The cost of the channel change, stated plainly:** a single `Edit`/`Write` that
touches a manifest can now produce **two** `decision:block` cues in one turn,
once each per session. Both continue the turn, and both are hard-capped at one
firing per session, so the worst case for a whole session is two cue messages.
But this channel reads to users as an alarming "blocking error" on a routine
write — the friction behind #1730 and #1825 — so doubling up on one edit is a
real UX change, not a neutral refactor. Watch for cue fatigue; if it materialises,
merge the hooks or add an explicit mutual-exclusion guard (a shared marker one
hook checks before firing).
Authors of future `Edit|Write` PostToolUse cues should document their detection
logic here before merge.

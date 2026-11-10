---
id: ADR-0027
date: 2026-11-10
created: 2026-11-10
modified: 2026-11-10
status: Accepted
deciders: claude-plugins team
domain: automation
relates-to:
  - ADR-0011
  - ADR-0020
github-issues:
  - 3545
  - 3544
  - 3169
  - 3548
  - 3549
  - 3550
  - 3551
  - 3552
  - 3553
  - 3554
---

# ADR-0027: One Engine for the Blueprint ID Registry; Deterministic Tasks Keep No Run State

## Context

Three components maintain `id_registry` in `docs/blueprint/manifest.json`:

| Component | Trigger | Reads frontmatter with | Writes |
|---|---|---|---|
| `hooks/auto-sync-id-registry.sh` | PostToolUse, once per changed `docs/**` path (via `blueprint-doc-change.sh`) | per-file `awk` (line 1 must be `---`), then `grep -m1 '^key:'` per field | add or update one entry; cross-refs and counters on first registration only |
| `run_sync_ids` in `scripts/blueprint-autorun.sh` | SessionStart probe, autonomy ≥ 1 | one batched `awk` pass (line 1 must be `---` since #3544) | add or update every entry; cross-refs never |
| `skills/blueprint-sync-ids/scripts/blueprint-sync-ids.sh` | `/blueprint:sync-ids` | `head -50 \| grep -m1 '^id:'`, no line-1 rule | nothing (audit) |

#3544 fixed the sweep after the hook had already been fixed for the same fenced-template case. #3545 asked four questions about the design behind that gap. A read-only review on 2026-11-10 (three readers, three designers with different lenses, a judge, and two adversarial verifiers, run on copies of `fa6605366`) established the following.

**The parsers disagree.** The hook and the sweep both store an inline YAML comment, quotes and trailing whitespace verbatim, including in the registry key: `id: ADR-9004  # assigned` registers as that whole string. Both skip a CRLF document whose first line is `---\r`, which the audit reads and reports as unregistered. The audit reads a fenced template within its first 50 lines as an ADR; `docs/adrs/README.md` escapes only because its `id: ADR-NNNN` is on line 95. The hook defaults `created` to a date and the sweep to a timestamp. The hook fills `relates_to`/`github_issues` once and never updates them, while the sweep writes `[]`. ADR-0020 lists five `relates-to` entries, and its registry entry has `[]`.

**The registry only grows.** The sweep's `jq` reduce only assigns (`blueprint-autorun.sh:239-251`), and neither the skill nor any script removes an entry. After a document was re-id'd, both keys pointed at one file, and the audit reported no mismatch because `by_path` keeps one id per path (`blueprint-sync-ids.sh:301-303`). With a junk `ADR-NNNN` entry planted, the audit returned `STATUS=OK`.

**Session start dirties fresh clones.** On a due run, `record_task_result` writes `last_completed_at`, `last_result` and `stats.runs` even when `CHANGED=false` (`blueprint-autorun.sh:340`). That contradicts the comment at `:337-338`. A fresh copy of `fa6605366` (sync-ids `weekly`) ended its first autorun with the manifest modified. This repo is the only manifest on `weekly`: `blueprint-init` gives consumers `on-change` (`manifest-template.md:102`), which reconciles every session and writes only when the registry differs. #3547 moves this repo to `on-change`.

**Both triggers are needed.** PRD/PRP/TRP numbers are assigned from `last_*+1` in the manifest (`blueprint-prp-create/SKILL.md:86-87`, `document-linking/SKILL.md:104-112`), so a document written mid-session must register before the next assignment. Some documents reach no hook: `bashEditDiff` is best-effort and omits git-ignored files (`hooks/lib/doc-paths.sh:9-13`), terminal git operations fire no hook, and level-3 CI runs no hooks. Measured: the whole autorun takes about 175 ms on 33 documents and 529 ms on 2033; one no-op hook call takes about 148 ms. Replaying the hook per file is what #3169 measured at 6.3 s for 88 documents, against the probe's 5 s budget.

**Constraints.**

- Level 3 vendors `blueprint-autorun.sh` as a single file (`blueprint-autonomy-level3/SKILL.md:65-71`, `:86-92`).
- A deleted ADR's registry entry is the only thing reserving its number: `check-adr-numbers.sh` Check 3 (`:339-385`) arbitrates collisions from the registry, and there is no ADR counter.
- Work-order files are git-ignored (`.gitignore:42`), but their entries are tracked.
- Agent-task `last_completed_at` is read across clones, by `--report` in the level-3 workflow (`templates/blueprint-autorun.workflow.yml:91`) and by `blueprint-status` and `blueprint-execute`.
- `blueprint-execute` computes due-ness itself and writes run state for any task it runs (`SKILL.md:90-99`, `:184-190`).

## Decision

### Q1: One frontmatter parser, inside `blueprint-autorun.sh`

The batched `awk` in `run_sync_ids` becomes the single parser. It is exposed as `blueprint-autorun.sh --frontmatter-rows <file>...` and called by the sweep, the hook and the audit. It follows `check-schema.py`'s `split_frontmatter` plus the YAML scalar subset:

- CR is stripped first.
- Frontmatter counts only when line 1 is `---`.
- The first key wins.
- An unquoted ` #` starts a comment.
- Matching quotes are removed and trailing whitespace is trimmed.
- Block and flow lists are read.
- The file list is sorted before parsing.

A differential test pins the rows to `split_frontmatter` + `yaml.safe_load`. It runs where `uv` is present; `uv` is never needed at runtime.

Rejected:

- **Fixing each of the three copies.** That is how #3544 happened.
- **A separate `scripts/lib/frontmatter.awk`.** Level 3 would need a second vendored file that has to stay in sync.
- **PyYAML at runtime.** A cold `uv run` took 3.45–6.03 s against the 5 s budget.
- **Stripping comments only from `id`/`status`.** That leaves a fourth dialect beside the validator's.

Titles containing an unquoted ` #` now register truncated, as `check-schema.py` already parses them. Quoting the title fixes it.

### Q2: Prune what the checkout proves; never prune a missing path automatically

An entry whose own path exists, but whose frontmatter at that path does not carry the entry's id, is pruned on every reconcile (P1). Ids are compared after normalising case and zero padding. P1 covers the junk `ADR-NNNN`, the old key of a re-id'd document, and an id that was removed. Every clone of a commit computes the same P1 result.

An entry whose path is missing (P2) is never removed automatically. A path can be absent from one clone and present in another: git-ignored work orders, sparse checkouts. The audit reports P2 entries. `/blueprint:sync-ids` gains a reviewed removal step for documents git records as deleted. That step never removes an ADR entry, because the entry reserves the ADR number.

Counters become max(existing, ids on disk, registry keys before pruning) and never decrease. The reverse index is rebuilt so documented shapes survive, such as a work order listing its PRP.

Rejected:

- **Report only.** The probe never runs the audit, so contradicted entries persist in unattended environments.
- **Prune everything not derivable from disk.** Every fresh clone would delete the work-order entries and the deleted-ADR guards.
- **Tombstones.** Counters and retained ADR entries already reserve numbers.

### Q3: Deterministic tasks keep no run state; agent tasks keep `last_completed_at` and `last_result`

The runner treats a `daily`/`weekly` schedule on a deterministic task (today only `sync-ids`) as `reconcile`. It never records run state for one: not on a no-change run, not on a changed run, not on error.

- `blueprint-execute` treats deterministic tasks as never due.
- The sync-ids skill drops its writeback.
- The sweep never creates an empty `id_registry`.
- The SessionStart probe reports a registry write or a task error as a finding, instead of the manifest recording it.

Agent-judgment tasks keep `last_completed_at` and `last_result` in the tracked manifest, written only after an explicit run, never at session start. They are cross-clone facts that level-3 CI and the status skills read. `stats.runs`/`stats.runs_total` stop being incremented: no reader decides from them.

Rejected:

- **Write nothing only when a due run changed nothing.** Every registry correction and every error would still stamp a wall-clock timestamp, so two clones correcting the same stale registry write different bytes.
- **A git-ignored state file.** Every consumer would need a `.gitignore` migration, and fresh clones and CI would forget agent-task due-ness.
- **State under `.git/`.** It is not shared across clones, cloud containers or CI, which are the readers that need it.

### Q4: Keep both triggers; give them one engine

`blueprint-autorun.sh --registry-reconcile [--check]` parses the whole tree with the Q1 parser in one pass and applies the Q2 rules:

- **Fields.** Path, status, title and cross-refs are derived from frontmatter and merged into the existing entry, so keys frontmatter does not carry survive. `created` comes from frontmatter, else the existing value, never the clock.
- **Determinism.** Input is sorted. Duplicate ids resolve to the registered path if it still carries the id, else the lexically first path, and are reported.
- **Write.** Only when `id_registry` differs, under a lock. The new registry is applied to the manifest re-read under the lock, so a concurrent `task_registry` write survives.
- **Callers.** The PostToolUse dispatcher calls the engine once per tool call when any changed path, deleted ones included, falls under `docs/{prds,adrs,prps,trps}` or `docs/blueprint/work-orders`. In that role it runs at every autonomy level and honours `BLUEPRINT_SKIP_HOOKS`, as the hook does today. The SessionStart sweep calls it behind the existing autonomy ≥ 1 gate. The audit calls it with `--check`.
- **Removed.** `auto-sync-id-registry.sh`'s registration body and its shared `${MANIFEST}.tmp` writes go away. Concurrent hook calls through that file truncated the manifest to 0 bytes in a scratch race.

The engine PR bumps `format_version`, so an older plugin's drift probe (`blueprint-drift-probe.sh:70-75`) reports the skew instead of old and new parsers rewriting each other's output. `blueprint-upgrade` re-copies the vendored runner at level 3.

Rejected:

- **Dropping the sweep.** Documents that arrive with no hook would never register.
- **Dropping the hook.** A document created mid-session would not register before the next number assignment, behind a probe TTL of up to 3600 s.
- **Sharing the parser but keeping two registration paths.** The prune, counter and cross-ref rules would each exist twice: the drift class #3544 came from.
- **A partial reconcile of only the changed paths.** It cannot see deletions or junk elsewhere.

## Consequences

- **Fresh clones.** A fresh clone of this repo with nothing changed since the last commit starts clean once #3547 lands; it was checked on a copy (three apply-mode runs, `CHANGED=false`, empty `git status`). #3548 removes the remaining run-state writes, so the property also holds for a `weekly` or `daily` deterministic task in a consumer repo. After #3550 the engine's output has no clock-derived field and never prunes a missing path, so a session-start write happens only when the committed registry is stale against committed documents. That write is byte-identical across clones, and #3551 tells the session why the file changed.
- **One-time diff.** When the engine lands, each existing manifest gets one diff, identical in every clone of a commit: cross-refs back-filled, comments and quotes normalised, P1 junk pruned, counters raised over retained keys. This repo commits its diff in the engine PR. A `--registry-reconcile --check` in pre-commit or CI keeps the committed registry equal to what the engine derives.
- **Level 3.** Consumers get the new behaviour when they re-vendor `blueprint-autorun.sh`; the `format_version` bump prompts it. Runtime dependencies stay bash, awk and jq.
- **Unchanged.** Level-3 writeback PRs are still not deduplicated. The `docs/blueprint/.manifest.json` fallback is honoured by the runner but not by the hook, the audit or the probe.

| Issue | Change | Question | Blocked by |
|---|---|---|---|
| #3547 | This repo's `sync-ids` schedule `weekly` → `on-change` (stopgap) | Q3 | — |
| #3548 | Deterministic tasks keep no run state; `blueprint-execute` exemption; no empty `id_registry` | Q3 | — |
| #3549 | One batched frontmatter parser for hook, sweep and audit | Q1 | — |
| #3550 | One registry engine for hook and sweep; P1 prune; counters; lock; `format_version` bump | Q2, Q4 | #3549 |
| #3551 | SessionStart probe reports registry writes and task errors | Q3, Q4 | — |
| #3552 | Audit reports engine drift; reviewed removal that keeps ADR entries | Q2 | #3550 |
| #3553 | Stop incrementing `stats` counters; document who writes agent-task state | Q3 | #3548 |
| #3554 | Assign new numbers from max(counter, ids on disk) | Q4 | #3549 |

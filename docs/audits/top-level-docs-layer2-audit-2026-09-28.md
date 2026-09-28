# Top-level docs, Layer-2 content-health audit — 2026-09-28

First Layer-2 pass of the top-level documentation audit decided in #1460, run
per the cadence in [`README.md`](README.md). Four read-only reviewers, one per
cluster, each returned findings with `file:line` evidence; the high-severity
ones were then re-checked against the repo and upstream docs before being
recorded here. Remediation is tracked in one follow-up issue per cluster; this
file records the state at `41edbbc5` and makes no fixes.

| Cluster | Scope | Findings (H/M/L) | Follow-up |
|---|---|---|---|
| A — front door & maps | `README.md`, `CLAUDE.md`, `docs/PLUGIN-MAP.md`, `docs/PRINCIPLES.md` | 15 (5/6/4) | #2838 |
| B — rules coherence | `.claude/rules/*.md` (44) | 17 (5/8/4) | #2839 |
| C — legacy docs | non-blueprint `docs/*.md`, `docs/plans/`, `docs/audits/README.md` | 13 (2/6/5) | #2840 |
| D — blueprint & decisions | `docs/blueprint/`, `docs/adrs/`, `docs/prds/`, `docs/prps/` | 14 (4/6/4) | #2841 |

## Layer-1 baseline

`bash scripts/check-docs-index.sh` at `41edbbc5`: `STATUS=OK`, `ISSUE_COUNT=0`
(44 rules on disk and indexed, 44 plugins, 438 skills, 21 agents). Two Layer-2
findings passed this gate because it greps rather than parses structure:
A-5 (index rows outside the Rules table still count) and A-6 (README category
rows are sampled, so a missing `foundryvtt-plugin` row goes unnoticed).

## Cross-cutting observations

- **Hard-coded counts drift in prose the gate does not read.** "16 ADRs",
  "18 hand-written rules" (CLAUDE.md, blueprint README, manifest), "191 of 408
  SKILL.md files" (`agentic-permissions.md`). Each is already wrong; the fix is
  to drop the number, not refresh it.
- **Duplicated guidance is where contradictions grew.** The permission cluster
  (B-1…B-3, B-10, B-11), the model-selection tables (B-6, B-7) and the Git
  Workflow section vs `conventional-commits.md` (A-12) all diverged after being
  restated in more than one file.
- **Shipped work left its decision records pending.** ADR-0010/0017/0018/0021,
  PRD-001, PRP-001 and PRP-005 still read as Proposed/Draft/in-progress for work
  that landed or was dropped months ago (D-3…D-7, D-13).
- **The newcomer path is the least accurate.** README install commands and MCP
  recipes do not run (A-1, A-2), PLUGIN-MAP names four commands that do not
  exist (A-3), and nothing maps how hooks, check scripts, pre-commit, CI, ADRs
  and rules fit together (A-7).

## Cluster A — front door & maps

| # | Sev | file:line | Finding |
|---|---|---|---|
| 1 | H | `README.md:11-13,22,28-30` | Install commands use wrong syntax: `claude plugin install laurigates/claude-plugins` and `laurigates-claude-plugins/<plugin>`. The CLI takes `marketplace add <repo>` then `install <plugin>@laurigates-claude-plugins`. |
| 2 | H | `README.md:41-51` | `just claude-setup`, `just mcp-github`, `mcp-playwright`, `mcp-context7` are not recipes in this repo's justfile (dotfiles `just -g` recipes). |
| 3 | H | `docs/PLUGIN-MAP.md:225,229,231,232` | Key Entry Points lists `/lint-check`, `/workflow:auto-fix`, `/workflow:parallel-issues`, `/workflow:ci-fix` — no such skills. |
| 4 | H | `docs/PLUGIN-MAP.md:10,13,221,243-253` | Describes `/blueprint:init` as per-feature PRD creation and `/blueprint:execute` as implement-test-PR; `init` is one-time bootstrap, `execute` is a one-action router, PRP execution is `/blueprint:prp-execute`. |
| 5 | H | `CLAUDE.md:178-179` | Two Rules-table rows (`drift-detection-triggering`, `offload-to-deterministic-substrate`) appended after the Conventions list with placeholder descriptions; they render as text, not table rows. |
| 6 | M | `README.md:66-164` | `foundryvtt-plugin` absent from every README category table. |
| 7 | M | `CLAUDE.md`, `README.md` | No big-picture section: hooks (14 plugins), 49 `scripts/check-*.sh`, pre-commit, CI, ADRs, `PRINCIPLES.md`, `PLUGIN-MAP.md` are not linked from CLAUDE.md. |
| 8 | M | `.claude/skills/docs-refresh/SKILL.md:22,67` | Points at "CLAUDE.md § Plugin Lifecycle", which moved to `/plugin-authoring` (#2140). |
| 9 | M | `docs/PRINCIPLES.md:29-33,70-74,84-85,95` | Cites rules that exist nowhere (`squash-merge-orphans-post-merge-commits`, `textual-merge-duplicates-identical-additions`) or only in user-global / `~/repos` scope, unlabelled. |
| 10 | M | `CLAUDE.md:153,155,157` | Stale "16 ADRs"/"18 rules"; claims every disabled task has a `disabled_reason`, but `curate-docs` has an empty `context`. |
| 11 | M | `README.md:266-272` | "Regenerating the Plugin List" snippet emits rows that fit no README table; the real tool is `/docs-refresh`. |
| 12 | L | `CLAUDE.md:98-132` | Git Workflow duplicates `conventional-commits.md` and has drifted (omits `revert`, scope guidance contradicts "plugin directory name"). |
| 13 | L | `README.md:166-181` vs `CLAUDE.md:13-24` | Plugin-tree diagram duplicated and already diverged; neither shows `hooks/`/`scripts/`. |
| 14 | L | `docs/PRINCIPLES.md:96-98` | Misstates the `parallel-safe-queries` mechanism (it prevents an empty result reading as failure). |
| 15 | L | `README.md:3`; `CLAUDE.md:2-4` | Banner names one of three experiments; CLAUDE.md `modified/reviewed` dates are 2026-04-21 though the file changed 2026-09-24. |

## Cluster B — rules coherence

No dead references: every `<plugin>:<skill>`, `scripts/check-*.sh` and
`.claude/rules/*.md` a rule names resolves. The findings are substantive.

| # | Sev | file:line | Finding |
|---|---|---|---|
| 1 | H | `agentic-permissions.md:66` | States skill `allowed-tools` "can only subtract … never add". The Claude Code skills reference defines it as "Tools Claude can use without asking permission during the turn that invokes this skill" — a grant, not a restriction (verified against `code.claude.com/docs/en/skills.md`). The bare-`Bash` standard at :58-81 rests on the inverted premise. |
| 2 | H | `auto-mode.md:107,166,172,175` vs `agentic-permissions.md:60,64,81` | One says keep narrow `Bash(<cmd> *)` in skill `allowed-tools`; the other says narrow patterns belong only in `settings.json`. |
| 3 | H | `agentic-permissions.md:13,215-236,265-279,315-343,517-523` | Contradicts its own §58-81: intro, Safe Patterns, Design Principle 1 and the five Standard Permission Sets all prescribe narrow skill patterns; checklist :517 and :518 conflict. Corpus is split 200 bare / 189 narrow of 438. |
| 4 | H | `skill-development.md:110,128`; `skill-quality.md:169-171` | Define `disable-model-invocation` as "content is the complete prompt"; it prevents the model from invoking the skill (docs; `pr-branch-sync.md:49`). |
| 5 | H | `release-please.md:30-35,55-58,85-86` | Claims `separate-pull-requests: true` (config: `false`), scope-routed bumps (contradicts `conventional-commits.md`), a wrong `extra-files` shape, and a `MY_RELEASE_PLEASE_TOKEN` secret (workflow uses an App token). |
| 6 | M | `skill-fork-context.md:61,96` vs `agent-development.md:181,550` | "Sonnet is the floor" for forked skills vs "avoid sonnet/haiku for subagents". |
| 7 | M | `skill-development.md:179` vs `skill-quality.md:180-181` | Two Model Selection tables disagree (`model: sonnet` for CLI wrappers vs `effort: low`, model unset); each defers to the other. |
| 8 | M | `agentic-optimization.md:101`; `skill-quality.md:34,47,244,246` | `context-engineering.md` demotions only partly propagated ("Always include an Agentic Optimizations table", "Required Sections"). |
| 9 | M | `hook-block-vs-nudge.md:44-46` vs `bash-tool-replacements.md:70,109` | Disagree on whether the `cat` read block is safety or style (predates #2148). |
| 10 | M | `agentic-permissions.md:27-42`; `auto-mode.md:123-138` | `bypassPermissions` protected-path history duplicated near-verbatim. |
| 11 | M | `agentic-permissions.md`, `skill-development.md`, `auto-mode.md` | "Broad Bash dropped in auto mode" restated 6+ times; `Skill()` prefix note duplicated. The duplication is how B-2/B-3 drifted. |
| 12 | M | `CLAUDE.md:178-179` | Same as A-5. |
| 13 | M | `agent-coworker-detection.md` (18.8 KB), `terminology.md`, `docs-currency.md` | Unscoped (always-loaded) with no stated reason, against `context-engineering.md:68-72`; `docs-currency.md` is a redirect stub. |
| 14 | L | `agent-coworker-detection.md:98,217` | "three signals" / "four-signal verdict" vs "these seven" at :19. |
| 15 | L | `agentic-permissions.md:71` | Hard count "191 of 408" is now 200 of 438. |
| 16 | L | `skill-fork-context.md:93` | Checklist says `Task`; renamed `Agent` in 2.1.63. |
| 17 | L | whole directory | No cluster map; six rules have only the CLAUDE.md index as inbound link; no named owner per shared fact. |

## Cluster C — legacy docs

Accurate and current: `pi-export.md`, `opencode-export.md`,
`dynamic-workflow-registration.md`, `docs/routines/*`, `regression-ledger.md`,
and the Layer-1 description in `docs/audits/README.md`.

| # | Sev | file:line | Finding |
|---|---|---|---|
| 1 | H | `docs/reusable-workflows-usage.md:69…360` | Every `max-turns` default is 5/6/8; all eight `laurigates/.github` reusable workflows default to 50 (verified via `gh api`). `file-patterns` defaults shown in the wrong form. Untouched since #908. |
| 2 | H | same, every Inputs table | Seven inputs undocumented (`model`, `allowed-bots`, `use-sticky-comment`, `max-budget-usd`, `timeout-minutes`, `file-limit`, `max-diff-lines`); diffs over 3000 lines silently skip analysis. |
| 3 | M | same, `:17-38,384-451` | Five of eight workflows default `model: sonnet`; snippets never set `model`, against the intent of `workflow-model-effort.md`. Owning repo for the fix to decide. |
| 4 | M | same, `:3,13` | Calls the workflows "in this repository"; zero inbound links; owning repo's README already catalogues them. #1940's keep decision deferred the check that now fails. |
| 5 | M | same, `:506-510` | Recommends `@v2.0.0`; `laurigates/.github` has no tags. |
| 6 | M | same, `:472` | `contains(github.event.pull_request.changed_files, …)` — `changed_files` is an integer. |
| 7 | M | `docs/plans/dynamic-workflow-migration.md:3` | Says "nothing implemented"; 8 of 9 recommended harnesses shipped. Cited by section from four files, so update in place. |
| 8 | M | `docs/plans/repo-maintenance-automation.md` | Superseded by `check-docs-index.sh`, `/docs-refresh`, `/plugin-authoring`; its planned scripts/skills never existed. Archive. |
| 9 | L | `docs/plans/git-repo-agent-plan.md:3-8` | Self-described historical; code extracted (#1017). Archive. |
| 10 | L | `docs/plans/session-end-proposal-records.md:1-5` | Live design with no status line or link to #2360. |
| 11 | L | `docs/diagrams/two-speed-feedback.d2:16-34` | `/session:end` fan-out omits taskwarrior-sync and tracker-sync. |
| 12 | L | `docs/audits/README.md:7-8` | "the one artifact already here" — there are now four. |
| 13 | L | `docs/audits/README.md:77` | Cluster D scope names `docs/blueprint/` only; ADRs/PRDs/PRPs live in sibling dirs. |

## Cluster D — blueprint & decisions

| # | Sev | file:line | Finding |
|---|---|---|---|
| 1 | H | `docs/blueprint/manifest.json:72`; `docs/blueprint/README.md:10,28` | `generate-rules` disabled pending a configurable output path "tracked in #1043"; #1043 closed completed (#1046, #1047). The blocker is gone; whether to re-enable is a decision, not a fix. |
| 2 | H | `CLAUDE.md:153,155`; `docs/blueprint/README.md:13,21,27,63,66`; `manifest.json:61` | "16 ADRs", "0001–0015", "18 hand-written rules"; disk has 23 ADRs and 44 rules. |
| 3 | H | `docs/adrs/README.md:36` | Index lists ADR-0020 Proposed; the ADR says Accepted. |
| 4 | H | ADR-0010:3; PRD-001; PRP-001 | Proposed/Draft for document detection, which shipped 2026-01-09. |
| 5 | M | ADR-0010:72-75,146; ADR-0005:56 | Name agents ADR-0009 deleted (`requirements-documentation`, `architecture-decisions`, `prp-preparation`). |
| 6 | M | ADR-0018:6; index :34 | Proposed; `--scope=usage` and `check-usage.sh` shipped. |
| 7 | M | PRP-005 `agent-teams-migration.md:3,15,111-122` | Still "Executing"; phases 1/3 done, phase 5 moot; phase-2 haiku/sonnet table contradicts always-Opus. |
| 8 | M | PRD-002 `reusable-github-workflows.md:5,22,29` | Draft, in-repo, haiku; ADR-0014 superseded (#908). |
| 9 | M | ADR-0007; ADR-0003:39-43,59-60 | Describe `commands/` directories removed by the commands→skills migration (#423); no ADR records that migration. |
| 10 | M | ADR-0014:6,16 | Superseded with no `superseded-by` and no recorded reason (only in #908). |
| 11 | L | ADR-0022:197 | #2093 row not marked done (landed in #2404). |
| 12 | L | ADR-0005:45-65; ADR-0008:50 | No "amended by ADR-0011" note; still describe `blueprints/.manifest.json` and removed commands. |
| 13 | L | ADR-0017:6; ADR-0021:6 | Proposed although in effect. |
| 14 | L | `docs/adrs/README.md:80-101` | Template section predates ADR-0023; ADRs 0001–0013 lack `domain:`. |

## Next pass

Due by 2026-12-28 (quarterly), or earlier on a Claude Code major version or at
54 plugins. Re-check first whether the four follow-ups closed their findings,
and whether `check-docs-index.sh` gained the structural checks A-5 and A-6 call
for.

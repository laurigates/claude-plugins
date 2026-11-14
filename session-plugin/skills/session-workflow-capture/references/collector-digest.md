# session-workflow-capture — collector digest

`scripts/workflow-capture-survey.sh` is read-only. It extracts and counts; the
skill decides what is reusable and where it belongs.

## Where the data comes from (Claude Code 2.1.325)

| Path under `~/.claude/projects/<slug>/` | Holds |
|---|---|
| `<session-id>.jsonl` | The main transcript. A `Workflow` tool_use carries `script`, `scriptPath` or `name` (plus `resumeFromRunId`); its tool result carries `runId`, `scriptPath`, `workflowName`, `status` |
| `<session-id>/workflows/scripts/<slug>-<runId>.js` | Every script the harness ran, persisted per run. The collector treats these files as the list of runs |
| `<session-id>/subagents/workflows/<runId>/journal.jsonl` | One `{"type":"started"}` line per agent spawned and one `{"type":"result"}` line per agent that returned |

The harness names a saved workflow by its `meta.name`, never by its filename,
and loads any `*.js` from `.claude/workflows/` (project) and
`~/.claude/workflows/` (user). Plugin workflows load from a plugin-root
`workflows/` directory or a `plugin.json` `workflows` field, named
`<plugin>:<meta.name>`.

## Session mode sections

| Section | Key | Meaning |
|---|---|---|
| `WORKFLOW CAPTURE SURVEY` | `TRANSCRIPT_AVAILABLE` | `false` with `SKIP_REASON` when the session was not found; judge from the conversation |
| | `CALLING_REPO` | `owner/name` of the `origin` remote (or the first remote when there is no `origin`), only when its host is github.com or `GH_HOST`; `unknown` otherwise, because `gh issue create -R` would resolve the name on GitHub |
| | `CALLING_REPO_HOST` | The remote's host, or `none` |
| | `PLUGINS_REPO`, `PLUGINS_REPO_SOURCE` | The tracker for generic patterns: `workflow_capture_repo:` from `.claude/session-plugin.local.md` (`settings-project`, `settings-user`) or the `repository` in session-plugin's own `plugin.json` (`manifest`) |
| `SESSION RUNS` | `RUN_n_NAME` | `meta.name`, or `unnamed-<hash prefix>` for a script without one |
| | `RUN_n_MODE` | `inline`, `scriptPath` (a re-run of a persisted file), `name` (a saved or plugin workflow), or `unknown` when the transcript has no record |
| | `RUN_n_AGENTS_SPAWNED`, `RUN_n_AGENTS_RETURNED` | From the run's journal. A gap means agents were killed, failed or skipped |
| | `RUN_n_MATCH` | `verbatim\|<scope>:<name>` (same bytes, or run by name), `adapted\|<scope>:<name>` (same `meta.name`, different bytes), `none\|-`. Scopes are tried in the order project, plugin, bundled, user, so a user-scope copy of a plugin template matches the plugin's original |
| `SESSION WORKFLOWS` | `WORKFLOW_n_ORIGIN` | `authored` (no run matched a known workflow), `verbatim` (every run did), `adapted` (otherwise) |
| | `WORKFLOW_n_MATCH_REPO` | The repository that ships the matched workflow: the owning plugin's `plugin.json` `repository`, the calling repo for a project-saved workflow, `none` for user scope |
| | `WORKFLOW_n_SIGNALS` | `reran` (more than one run), `unfinished_agents`, `resumed`, `adapted_known`; `none` otherwise |
| | `WORKFLOW_n_AGENT_SITES`, `WORKFLOW_n_PHASE_CALLS` | `agent(` and `phase(` call sites in the latest script |
| `KNOWN WORKFLOWS` | `KNOWN_n` | `scope\|meta.name\|owning repo\|path`. Scopes: `project`, `user`, `plugin` (plugin-root `workflows/`), `bundled` (`*/skills/*/workflows/*.js`, plugin cache or the project tree) |
| `SUMMARY` | `CAPTURE_CANDIDATE_COUNT` | Workflows whose origin is `authored` or `adapted` |
| | `FRICTION_SIGNAL_COUNT` | Workflows with at least one signal |

`--summary` prints only the survey header and `SUMMARY`, which is what
`session-plugin:session-end` reads to decide whether the pass qualifies.

## Usage mode

`--usage` scans the newest `--window-sessions` (default 50) main transcripts
of the current project, or of every project with `--all-projects`.

| Key | Meaning |
|---|---|
| `SESSIONS_SCANNED`, `SESSIONS_WITH_WORKFLOW` | Transcripts read, and how many contain a Workflow call |
| `WORKFLOW_CALLS` | Workflow tool_use count |
| `CALLS_INLINE`, `CALLS_SCRIPT_PATH`, `CALLS_BY_NAME`, `CALLS_RESUME` | The split by invocation mode; `CALLS_BY_NAME` is the count of saved or plugin workflows actually run by name |
| `NAMED_n` | `<name>\|<count>` per name passed to `Workflow({name})` |
| `RUN_NAME_n` | `<meta.name>\|<count>` per run, any mode |
| `RUNS_MATCHING_KNOWN_NAME` | Runs whose `meta.name` equals a known saved or bundled workflow |

Transcripts expire under the harness's retention policy, so a zero is a floor
for the window scanned, not a verdict on all time.

## Other harnesses

pi and OpenCode have no Workflow tool and keep no `~/.claude/projects`
transcript for the session, so the collector reports `STATUS=SKIP` there and
the pass is judged from the conversation, which normally means it does not
qualify.

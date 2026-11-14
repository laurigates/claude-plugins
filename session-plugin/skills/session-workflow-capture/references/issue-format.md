# session-workflow-capture — issue format

## Labels

| Finding | Labels |
|---|---|
| Pattern, or friction in a workflow saved in the calling repo | `workflow-capture` |
| Friction in a plugin-bundled or plugin-registered workflow | `session-feedback` plus `bug` or `enhancement`, the labels `feedback-plugin:feedback-session` uses, so the weekly friction review and that skill's dedup both see the issue |

`workflow-capture` marks every capture, so a maintainer can list them; the
`[Workflow]` title prefix still groups them in search when the label is absent.

1. `gh label list -R <repo> --json name,description --limit 500` (or the
   GitHub MCP `get_label` tool) — use a label that exists.
2. If one is missing and no label description mentions terraform, IaC or
   "managed by" (and the repo has no `labels.tf` / `labels.yaml`), create it:
   `gh label create workflow-capture -R <repo> --description "Captured from a Workflow-tool session" --color 5319e7`
   (`session-feedback`: `--description "Feedback from session analysis" --color d876e3`).
3. With labels managed as code, file without it and report the missing label
   so it can be added to that definition.

## Titles

| Finding | Title |
|---|---|
| Pattern | `[Workflow] <capability>: <shape in a few words>` — e.g. `[Workflow] issue triage: per-file fan-out with one verifier per finding` |
| Friction in a workflow saved in the calling repo | `[Workflow] <workflow meta.name>: <what went wrong>` — e.g. `[Workflow] nightly-audit: budget line disagrees with the scale estimate` |
| Friction in a plugin-shipped workflow | `feedback(<plugin>): <workflow meta.name> — <what went wrong>` — feedback-session's title shape |

## Pattern body

````markdown
## What

<The reusable shape in two or three sentences: what fans out, where N comes
from, what verifies, what the run returns.>

## Why

<What it achieved in the session that a single agent or an existing workflow
did not: agent count, what it caught, what it cost. No project names in a
public draft.>

## Shape

| Question | Answer |
|---|---|
| Fan-out width comes from | <file list, script rows, caller args> |
| Barrier | <none, or which stage needs every earlier result, and why> |
| Loop bound | <the script or constant that bounds it> |
| Agent budget | <N, or C + k x items> |

<details><summary>Skeleton</summary>

```js
// meta, phases, schemas and the fan-out structure. Placeholders for
// prompts, paths and project terms in a public draft.
```

</details>

## Proposed home

<project: save as .claude/workflows/<name>.js so it runs by name.
public: a bundled template beside the skill whose domain it serves, or a
plugin-registered workflow when it runs unchanged from its args.>

## Processing

- **Processed by:** whoever triages this tracker. They decide whether to save or template the workflow.
- **Completed means:** a PR adding the workflow (or a template change) has merged, or the issue was closed with a stated reason.
- **Closes:** when that PR merges (`Fixes #N`).
````

## Friction body

```markdown
## Workflow

`<meta.name>` (<saved project | saved user | bundled in <plugin>/skills/<skill>/workflows/<file> | plugin-registered>)

## What happened

<The observed failure or cost: reruns, unfinished agents, a resume, a schema
rejection, a scale-guard prompt, an instruction in the framing section that
was wrong.>

## Evidence

<Collector signals (RUNS, AGENTS_SPAWNED vs AGENTS_RETURNED, SIGNALS) and the
error text, with session paths and ids removed.>

## Suggested change

<The edit to the script or its framing section, and what must stay as it is.>

## Processing

- **Processed by:** whoever triages this tracker; the fix lands as an ordinary PR. A `session-feedback` issue is also read by the weekly friction review as corroboration.
- **Completed means:** a PR that fixes it has merged, or it was closed with a stated reason.
- **Closes:** when that PR merges (`Fixes #N`).
```

## Public drafts

A `public` draft is written for a reader who has never seen the project:

| Replace | With |
|---|---|
| Paths, checkout names, the calling repo | `<repo>`, `<path>`, a description of what the file holds |
| Domain terms, customer or product names | The generic role ("the data loader", "the deploy target") |
| The persisted script | A skeleton: `meta`, phase list, schemas, the fan-out loop, prompts reduced to one line saying what each agent does |
| Session ids, run ids, timestamps | Nothing; they mean nothing outside the session |

`check-issue-draft.sh` is the backstop, not the method: rewrite first, then
scan.

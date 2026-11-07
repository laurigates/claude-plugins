# The issue-triage workflow template

`workflows/issue-triage.workflow.js` is a `Workflow` template for a backlog
sweep that spans more issues, or more repositories, than one session should
read in sequence. The framing (what to adapt, what to preserve, the agent
budget) is the `## Workflow harness (template)` section of
[SKILL.md](../SKILL.md).

## Inputs

| Field | Shape | Default |
|-------|-------|---------|
| `repos` | `[{ repo: 'owner/name', root: '/absolute/clone/path', alias?: 'short' }]` | required |
| `issues` | `[{ repo, number }]`, `['owner/name#12', 'short#34']`, or one space-separated string of the same | required |
| `base` | ref the cited evidence is re-verified at | `origin/main` |
| `classes` | `{ <verdict>: '<definition>' }`, replacing a verdict's default definition | the four defaults |
| `limits` | one paragraph on what an agent in this environment can and cannot do | a generic paragraph |

Every issue's repository needs a `repos` entry with a clone. The agent reads
files at `base` from that clone with `git -C <root> show` and `git -C <root>
grep`, and never switches its branch, because other sessions may be using it.

The run aborts before spawning any agent when an issue reference does not
parse, a repository has no clone, `classes` names a verdict outside the four,
or the list has fewer than 2 or more than `MAX_ISSUES` (40) issues. Above the
cap, split the list into several runs.

## Verdicts

| Verdict | Field it fills |
|---------|----------------|
| `actionable` | `scope`: files to change and the acceptance check |
| `needs_decision` | `question_for_user`: the decision, answerable in one line |
| `blocked_on_event` | `waiting_on`: the secret, run, release or other issue it waits for |
| `close_candidate` | `reason`: the commit, file or PR showing it is fixed or obsolete |

Every row also carries `open_pr`, `size` and `group_with` (other issues in the
run to implement together). `args.limits` is where the environment's real
constraints go: API endpoints that fail there, machines the agent cannot
reach, repositories it may push to. The verdict between `actionable` and
`blocked_on_event` depends on it.

## Return value

`{ triaged, missing }`. `triaged` holds one row per issue that got a verdict,
keyed by the input issue (a row whose agent echoed a different number is
re-keyed and logged). `missing` lists every input issue with no verdict, as
`owner/name#N`; re-run those, never read them as closed.

## Relation to git-issue's template

`git-plugin:git-issue` ships `workflows/issue-triage.workflow.js` too. That one
assesses batches in one repository and adds a barrier stage that slices the
`autonomous` issues into conflict-free implementation units for
`workflow-orchestration-plugin:workflow-implement-verify`. This one has no
barrier and no slicing: it returns a verdict per issue across repositories, for
a person to act on. Feed its `actionable` rows to the git-issue template, or
straight to implement-verify as units, when implementation follows.

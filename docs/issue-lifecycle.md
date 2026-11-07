# Issue lifecycle: machine-filed and feedback issues

Workflows and the `feedback-session` skill file issues on a schedule. Each one
needs a consumer and a close rule, or it stays open and the daily
issue-resolving Routine either skips it or asks about it (#3346). This page is
the single statement of who processes each type, what "completed" means, and
when it closes. Every generator writes the same three facts into the issue it
files, under `## Processing`.

The labels below are the exempt list in
[`scripts/issue-grouping-exempt.txt`](../scripts/issue-grouping-exempt.txt):
each issue stands alone, so none is grouped under an epic.

## Types

| Type (label) | Generator | Processed by | Completed means | Closes |
|---|---|---|---|---|
| `session-feedback` | `feedback-session` ([issue format](../feedback-plugin/skills/feedback-session/references/issue-format.md)) | `friction-learner` reads it weekly as corroboration; the fix comes from the daily Routine or Lauri | A PR that fixes it has merged, or it was closed with a stated reason | When that PR merges (`Fixes #N`) |
| `positive-feedback` | `feedback-session` | `friction-learner` Step 0 ([agent](../feedback-plugin/agents/friction-learner.md)) | A weekly `friction-learner` PR cites it under `## Fast-loop signal` | `friction-learner` closes it after citing it. It keeps reading positive issues in any state from the last 6 months, so a closed one still guards the behaviour it praises |
| `research-radar` | [`research-radar.yml`](../.github/workflows/research-radar.yml) (weekly) | The daily Routine or Lauri | Every candidate has a verdict comment (adopt, or reject with a one-line reason), and every adopted candidate is merged, one PR per target file | When the last adopted candidate merges. Radars are not superseded: each week lists different papers |
| `agentic-audit`, `infra-compliance`, `blueprint-health`, `audit-liveness`, `docs-index` | [`scheduled-audits.yml`](../.github/workflows/scheduled-audits.yml) (monthly) | Lauri, or an agent asked to act on it | Superseded by the next month's report | The generator closes it when the next month's report opens, and that report carries forward the items still open. A next run that finds nothing closes it too |
| `golden-set-eval` | [`golden-set-evaluation.yml`](../.github/workflows/golden-set-evaluation.yml) (monthly) | Lauri | Superseded by the next month's sweep | As above |
| `workflow-model-audit` | [`workflow-model-audit.yml`](../.github/workflows/workflow-model-audit.yml) (monthly) | Lauri | Superseded by the next month's audit | As above |
| `stranded-work` | [`stranded-work-audit.yml`](../.github/workflows/stranded-work-audit.yml) (weekly) | Lauri | Every listed branch has been landed, deleted, or kept on purpose | By hand once processed. The audit files no new report while this one is open |
| `fleet-drift` | [`fleet-drift-audit.yml`](../.github/workflows/fleet-drift-audit.yml) (weekly) | Lauri | Every listed divergence has been fixed or accepted as intended | By hand once processed. The audit files no new report while this one is open |
| `changelog-review` | [`changelog-review.yml`](../.github/workflows/changelog-review.yml), body written by `laurigates/.github` `reusable-changelog-review.yml` | Lauri | Every listed action has been applied, filed or dismissed | By hand once processed |
| `config-drift` | [`config-drift-audit.yml`](../.github/workflows/config-drift-audit.yml) (twice weekly) | Lauri reads each run's comment | Each finding is fixed or waived (`health-plugin/README.md`) | Never: it is a rolling issue. If it is closed, the next run with findings opens a new one |
| Dependency Dashboard (title) | Renovate | Renovate | Not applicable | Never; Renovate owns it |

"Monthly report" means a dated report from a monthly schedule. The supersede
rule is Lauri's decision on #3346 (2026-11-01, decision 2, option A); the
`positive-feedback` rule is decision 1 on the same issue.

## How the supersede rule runs

A monthly report that waited for a person blocked every later month: the
duplicate guard skipped a run while any earlier report was open. Supersede mode
turns that around.

| Step | Mechanism |
|---|---|
| Only this period's report blocks the run | `scripts/script-to-issue-guard.sh --current-title`, through the composite's `supersede: 'true'` input or the workflow's own guard |
| Script-built reports carry forward by recomputation | The audit script re-detects whatever is still wrong, so an unfixed item reappears in the new report |
| Claude-written reports carry forward explicitly | The workflow writes the previous report to `previous-report.md`, and the prompt lists its still-open recommendations under `### Carried forward from #N` |
| Earlier reports close after the new one is filed | `scripts/close-superseded-reports.sh`, which closes nothing if the new report is missing, and closes them with `--clean` when the run found nothing |

A finding that needs more than a month of work belongs in its own issue, filed
from the report, so it does not depend on being carried forward.

## Open questions

- The weekly reports (`stranded-work`, `fleet-drift`, `changelog-review`) keep
  the close-by-hand rule. Whether the supersede rule also applies to them is
  not decided.
- The `changelog-review` body is written in `laurigates/.github`, so its
  `## Processing` section has to be added there; this repository cannot change
  it.

## Enforcement

`scripts/check-issue-processing.sh` fails when a generator's issue-body
template has no `## Processing` section, when a workflow that files issues is
neither checked nor exempted with a reason, or when a label on the exempt list
is missing from the table above.

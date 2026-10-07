# story-audit — Workflow Harness Constraints

Read before adapting `workflows/blueprint-story-audit.workflow.js`.

Two constraints the template encodes because they are structure, not style:

- **The capability lane is always ONE agent.** You cannot partition work by a partition the work
  itself discovers — Agent 1's brief is literally "group by area", so the areas do not exist until
  it has run. Only the per-PRD and per-test-root splits are enumerable up front.
- **Steps 2 and 4 stay agent stages, never JS.** Step 2 mandates "verify with a quick file-level
  read where ambiguous" and a workflow script has no filesystem; Step 4's core/non-core cutoff is
  explicitly heuristic.

The template also carries this skill's own row caps unchanged — `ROW_LIMIT = 200` from Step 1's
Agent 1 brief and `AREA_ROW_LIMIT = 15` from the artifact template in
[REFERENCE.md](../REFERENCE.md). They are **not** divided across lanes: the capability lane is a
single agent, so there is nothing to divide, and the PRD and test lanes are exhaustive extractions
("Don't infer — only extract", "List every test file") where a derived per-lane budget would
silently drop the stories and tests the audit exists to surface.

## Step 8 has no orchestrated form

This step **stays in the skill** — a workflow cannot `AskUserQuestion`, so it has no orchestrated form. `--report-only` is the path an orchestrator (or the harness) takes.

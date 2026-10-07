# story-audit — Step 1 Agent Briefs

The three Explore-agent briefs Step 1 dispatches in parallel.

Agent 1 — **Capability map**:

> Survey this codebase and list every user-facing capability. Group by area
> (auth, billing, search, …). For each capability emit one row:
> `<area> | <capability> | <entry-point file:line> | <kind>` where kind is
> `route`, `cli`, `event-handler`, `component`, `cron`, or `worker`.
> Flag dependencies that look declared-but-unused (imported library that
> never has its main API called). Cap output at 200 rows; if a project is
> larger, summarize tail areas as "+ N more in <area>". Read-only.

Agent 2 — **Story extraction**:

> Read every PRD under {PRD paths from --prd or auto-detected}. Emit one
> row per stated user story or functional requirement:
> `<PRD-id> | <story-id-or-section> | <verbatim user-visible behaviour>
> | <linked deps if any>`. Also list any "Known Drift" or status-marked
> entries verbatim. Don't infer — only extract. Read-only.

Agent 3 — **Test inventory**:

> List every test file under {test directories from Context}. For each
> file emit: `<file> | <describe-or-suite> | <test-count> | <skipped-or-todo-count>`.
> When a file has a top-level comment or describe block citing a story
> ID (PRD-NNN, FR-N.N, story-name), include it. Read-only.

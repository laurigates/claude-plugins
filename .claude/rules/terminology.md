# Development Terminology

A working glossary of terms with strong intent used in this repo and the workflows its plugins encode. Each entry is a positive definition — "what the term *is* and when it *applies*" — so a reader can pick the right word without negation prompts (positive framing is the model-recommended pattern; see `.claude/rules/conventional-commits.md` for the analogous principle in commit subjects).

The list is descriptive of current practice, not prescriptive: extend it as the vocabulary matures. Plugin-specific terms live in that plugin's own rules and may cite this file as the canonical cross-reference.

## How to read an entry

| Field | Meaning |
|-------|---------|
| Term | The word or phrase as it appears in conversation, commits, PR titles |
| Definition | One-line positive statement of what the term means |
| Use when | The condition that selects this term over its near-neighbours |

When two terms sit close together (e.g. `hoist` / `lift`, `rescope` / `descope`), the *Use when* column does the disambiguation — each definition stands on its own, and the contrast falls out of the pair.

## Scoping & planning

| Term | Definition | Use when |
|------|------------|----------|
| Triage | Sort items by urgency and decide what gets attention now | Many incoming items, limited attention to allocate |
| Rescope the plan | Adjust the boundaries of the work — expand, contract, or shift | Boundaries change but the goal remains |
| Descope | Drop work from the plan to ship the essential | Cutting non-essential items entirely |
| Cut scope | Same as descope, used interchangeably | Informal contexts where "descope" feels heavy |
| Sequence the work | Order tasks by dependency so each unblocks the next | Tasks have real ordering, not just coexistence |
| Spike | Timeboxed exploration to learn enough to commit | Uncertainty too high to plan, but cheap to probe |
| Decompose | Break a task into tractable, independently shippable units | The task is too large to land in one increment |
| Land in increments | Ship the work in small, individually reviewable steps | Coordinating risk over time matters more than speed |
| Define done | Make acceptance criteria explicit before starting | "Done" is ambiguous and the team needs alignment |
| Set the seam | Name the boundary where this change stops and the next begins | Adjacent work tempts scope creep |

## Review & verification

| Term | Definition | Use when |
|------|------------|----------|
| Adversarial review | A review aimed at finding faults, not validating intent | The default review missed something and stakes are high |
| Red-team | Actively try to break the proposed approach | Pre-commit to an architecture or design |
| Sanity-check | Quick correctness pass to catch obvious mistakes | Cheap pre-flight before a longer review |
| Stress-test the assumptions | Probe what the plan rests on by varying inputs | The plan looks sound but the foundation is unverified |
| Dry-run | Simulate the change without side effects | The action is hard to reverse and you want a preview |
| Trace through | Follow the execution path by hand, step by step | A bug or behaviour is suspected but not localized |
| Audit | Systematic check against a standard or checklist | Periodic or compliance-driven review, full coverage required |

## Parallelism & delegation

| Term | Definition | Use when |
|------|------------|----------|
| Fan-out agents | Dispatch parallel subagents on independent work | Tasks are independent and benefit from concurrency |
| Parallelize | Run independent work concurrently (tool calls, agents, jobs) | The work has no order dependency |
| Spin up a subagent | Delegate a bounded task to a subagent | The work is large enough to protect main context |
| Gather / collect | Merge fan-out results back into one place | Parallel branches return and need to be reconciled |
| Checkpoint | Capture state before a risky step so you can resume | About to take an irreversible or expensive action |

See also `agent-patterns-plugin:parallel-agent-dispatch` and `.claude/rules/parallel-safe-queries.md`.

## Work state

| Term | Definition | Use when |
|------|------------|----------|
| In-flight work | Tasks currently in progress, not yet shipped | Distinguishing "started" from "planned" or "done" |
| Resume | Continue from the exact point work stopped | Context is intact and the next step is obvious |
| Pick up where we left off | Resume with looser continuity — reload the gist and proceed | Time has passed; some re-grounding is needed |
| Park | Defer with intent to return, capturing enough state to resume | Higher-priority work pre-empts current task |
| Unblock | Clear the dependency that is holding work | The blocker is identified and resolvable |
| Hand off | Transfer the work with enough context for someone else to continue | A different actor (human or agent) takes the next step |
| Stage | Prepare the change without committing it | The change is ready locally but not yet a shipped artifact |

## Code operations

| Term | Definition | Use when |
|------|------------|----------|
| Hoist | Move a declaration to an outer scope so more callers can reach it | Scope of access is the reason for moving |
| Lift | Move a value or definition up a level in the call structure | General "raise" — often interchangeable with hoist |
| Reconcile | Bring two diverged states into agreement | Branches, models, or caches have drifted apart |
| Conform | Make something match a standard, schema, or shape | The target shape is fixed; the source needs adjustment |
| Incorporate | Fold new content into existing work, preserving structure | Adding a contribution without overwriting |
| Extract | Pull logic out into its own unit (function, module, file) | A block has earned a name or wants reuse |
| Inline | Fold a unit back into its caller | The abstraction is paid for once and adds noise |
| Thread through | Pass a value down a call chain explicitly | The value is needed deep without a global or context |
| Refactor in place | Restructure code while preserving observable behaviour | Internal shape needs work; external contract is fine |
| Backfill | Add the missing tests, docs, or types after the fact | Shipped without coverage and now closing the gap |
| Normalize | Bring varied forms to one shape | Multiple representations exist; one is canonical |
| Consolidate | Merge duplicates into a single source of truth | Drift between copies is causing or risking bugs |

## Requirements framing

| Term | Definition | Use when |
|------|------------|----------|
| User story | A feature framed from a user's need ("As an X, I want Y so that Z") | Connecting work to the human outcome it serves |
| User journey | The end-to-end path a user takes across multiple steps or surfaces | Scoping a flow that crosses feature boundaries |
| Acceptance criteria | Concrete pass/fail conditions that mark the work complete | "Done" needs to be checkable, not opinion |
| Edge cases | Boundary inputs and conditions the implementation must handle | Designing for the unusual as well as the common |
| Happy path | The nominal flow when nothing goes wrong | Establishing the baseline behaviour first |
| Failure path | The flow when an error occurs and the system must respond | Designing recovery, retries, or user-facing errors |
| Invariants | Conditions that must always hold across all states | Reasoning about correctness, especially in concurrent code |

## Extending the glossary

When a new term earns its place in the team's vocabulary:

1. Add it under the category that fits, or open a new category if none does.
2. Write the definition positively — what the term *is*, not what it isn't.
3. Fill in *Use when* with the disambiguating condition. If you can't, the term may not be carrying enough weight to glossary.
4. If the term is plugin-specific (e.g. blueprint's `ADR`, `PRD`, `PRP`), keep it in that plugin's rules and cross-link instead.

## Related

- `.claude/rules/conventional-commits.md` — type vocabulary (`feat`, `fix`, `refactor`, etc.) overlaps with the *Code operations* section
- `.claude/rules/agent-development.md` — formal definitions of subagent, worktree isolation, team
- `agent-patterns-plugin` — patterns and terminology for multi-agent orchestration
- `blueprint-plugin/docs/blueprint/` — ADR / PRD / PRP vocabulary specific to that workflow

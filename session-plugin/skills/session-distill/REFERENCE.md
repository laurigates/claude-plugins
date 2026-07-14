# project-distill Reference

## Update Over Add Decision Table

| Question | If yes... |
|----------|-----------|
| Does this replace an existing rule/recipe/skill? | Remove the old one, add the new |
| Does this improve an existing one? | Update in place |
| Does an existing one already cover this? | Skip it |
| Is this genuinely new and reusable? | Add it |
| Is this reusable **beyond this repo** / would other repos benefit? | `[PROMOTE]` it to the owning plugin (PR), don't bury it in one repo's `.claude/` |
| Is this a one-off that won't be needed again? | Skip it |

## Evaluation Criteria

### Rules Worth Capturing

| Capture when... | Skip when... |
|-----------------|--------------|
| Pattern applies across sessions | One-time fix |
| Convention that prevents mistakes | Obvious best practice |
| Project-specific constraint discovered | Generic advice |
| Tool behavior that's non-obvious | Well-documented behavior |

### Recipes Worth Capturing

Within-session repeat count is **not** the signal — it rewards TDD/debug thrash
(`pytest -x` ×8), not durable workflows (a deploy sequence run once). The
`distill-survey.sh` `RECIPE_CANDIDATES` section already encodes the real
criteria; capture from it.

| Capture when (a `RECIPE_CANDIDATE`)… | Skip when… |
|-----------------|--------------|
| The normalized command **recurred across ≥2 separate sessions** (`_SESSIONS ≥ 2`) | It appears only this session and isn't commit-bracketed |
| It is **commit-bracketed** — in an interval terminated by `git commit` (a completed unit of work) | It is churn (`status`/`diff`/`log`/`test`/`build`/`ls`/`cd`/`pwd`/`cat`) — excluded by the collector |
| It is **novel** — not already covered by `just --dump` | It is already a `just` recipe (the collector drops these) |
| Refine the collector's `_FIRST` example (normalization is lossy) | Common well-known flags with no project specifics |

### Process / Methodology Worth Capturing (`--process`)

A multi-step workflow the session invented that is worth repeating has no home
in a single rule or recipe. Route it by whether it needs judgment:

| Capture when… | Destination |
|-----------------|--------------|
| A **deterministic** multi-step sequence (no decision points) — you can name it from `COMMIT_INTERVALS` | `scripts/<name>.sh` + a thin `just` recipe (offload to a deterministic substrate) |
| A **multi-step process with decision points**, project-local | a project-local `.claude/skills/<name>/SKILL.md` (auto-loaded — no marketplace entry) |
| The same process would help **other repos** | `[PROMOTE]` to a marketplace plugin (PR) |

Name the sequence yourself — the collector emits the grouping
(`COMMIT_INTERVALS` / `COMMAND_DIGEST`), never the name (sequence inference is
judgment, which stays in the skill).

### Skill Improvements Worth Proposing

| Propose when... | Skip when... |
|-----------------|--------------|
| Discovered better command flags | Minor style preference |
| Found a pattern the skill doesn't cover | Edge case unlikely to recur |
| Existing guidance was misleading | Niche use case |
| New tool version changed behavior | Temporary workaround |

### Promotion Candidates ([PROMOTE] — additive, cross-repo)

These do not require anything to have gone wrong; a smooth session is a valid
source. Distinct from "Skill Improvements" because the target is a **named
plugin in another repo**, applied as a PR.

| Promote when... | Skip when... |
|-----------------|--------------|
| Session invented a reusable technique with **no home skill** anywhere | Pattern is specific to this repo -> local `[NEW]` rule instead |
| A **named plugin's skill is missing** a capability the session needed | The skill already covers it (just under-discovered) -> no change |
| The same technique would help **other repos**, not just this one | One-off, won't recur -> skip |
| A focusing fix: "this belongs in `<plugin>/skills/<skill>`" | You can't identify a plausible owner and it isn't clearly reusable |

## Routing Decision Table

Most-specific destination first. No new artifact type — a project-local process
reuses `.claude/skills/`.

| Learning | Destination | Tag |
|---|---|---|
| Convention/constraint | `.claude/rules/<name>.md` | `[UPDATE]` / `[NEW]` |
| Recurring single command | `just` recipe | `[UPDATE]` / `[NEW]` |
| Deterministic multi-step workflow | `scripts/<name>.sh` + `just` recipe | `[NEW]` |
| Multi-step process w/ decision points, project-local | `.claude/skills/<name>/SKILL.md` | `[NEW]` |
| Reusable beyond this repo | marketplace plugin (PR) | `[PROMOTE]` |

## Proposal Format Examples

```
[UPDATE] `.claude/rules/X.md` - Reason for update (description of change)
[SKIP] Considered rule Y, but Z already covers it
[UPDATE] `plugin/skills/skill-name/SKILL.md` - Pattern discovered
[NEW] `just deploy-canary` - RECIPE_CANDIDATE recurred across 3 sessions, novel vs `just --dump`
[NEW] `.claude/skills/canary-rollout/SKILL.md` - multi-step-with-judgment process named from COMMIT_INTERVALS (project-local)
[NEW] `scripts/regen-fixtures.sh` + `just regen-fixtures` - deterministic multi-step workflow
[REDUNDANT] `old-recipe` - Superseded by new approach
[PROMOTE] -> rust-plugin/skills/cargo-worktree-builds (new) - shared CARGO_TARGET_DIR across worktree agents; reusable beyond this repo, no home skill -> PR
[PROMOTE] -> git-plugin/skills/git-pr (edit) - stacked-PR --onto squash cleanup the skill is missing -> PR
```

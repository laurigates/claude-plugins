# session-distill — Routing a learning to a destination

Each surviving insight goes to exactly one home. Pick most-specific first — a
new artifact type was deliberately **not** added (no `.claude/runbooks/`); a
project-local process reuses the `.claude/skills/` convention CLAUDE.md
documents as a first-class, auto-loaded home.

| The learning is… | Destination | Proposal tag |
|---|---|---|
| A convention/constraint that prevents mistakes | `.claude/rules/<name>.md` | `[UPDATE]` / `[NEW]` |
| A recurring single command with fixed flags (a `RECIPE_CANDIDATE`) | a `just` recipe | `[UPDATE]` / `[NEW]` |
| A **deterministic** multi-step workflow (no decision points) | `scripts/<name>.sh` + a thin `just` recipe wrapping it | `[NEW]` |
| A **multi-step process with decision points**, project-local | a project-local `.claude/skills/<name>/SKILL.md` (auto-loaded, no marketplace entry — see the repo's CLAUDE.md) | `[NEW]` |
| Reusable **beyond this repo** | a marketplace plugin/skill via PR | `[PROMOTE]` |

The `--process` category covers the two multi-step rows: a deterministic
workflow becomes `scripts/*.sh` + a recipe (offload to a deterministic
substrate); a judgment-bearing one becomes a project-local skill. Name the
sequence yourself from `COMMIT_INTERVALS` / `COMMAND_DIGEST` — the collector
gives you the grouping, not the name.

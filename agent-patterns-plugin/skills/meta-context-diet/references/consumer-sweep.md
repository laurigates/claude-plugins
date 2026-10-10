# meta-context-diet — Consumer Sweep

Open at Step 1 (inventory) and again at Step 5 (execute) of [SKILL.md](../SKILL.md).
An inbound-link check is not enough: indexers, agent entry points, and code
comments read a rule's path without linking to it, so a Promote, Consolidate,
Drop, or `docs/` move that only repoints markdown links silently breaks them.

## When the sweep runs

| Step | What it does | Why there |
|---|---|---|
| Step 1 — inventory | Run the full sweep once per candidate and record its path consumers | The consumers decide the disposition (Promote vs a `docs/` move), and the disposition is what the user approves at Step 4 — so they must be known before classification |
| Step 5 — execute | Re-run the `Grep` for each candidate about to be Promoted, Consolidated, Dropped, or moved, then repoint every hit in the same change | The tree can change between inventory and execution; the re-run catches consumers added since |

## The sweep

1. **`Grep` the rule's file name** — with and without `.md` — across the whole
   tree, hidden paths included and `.git` excluded. Search everywhere, not only
   `.claude/` and docs: code comments in `.tf`, `.yaml`, or `.js` files cite rule
   paths too. For a `CLAUDE.md` `##` section candidate there is no file name
   to grep: grep the heading text, its anchor slug (e.g. `#git-workflow`), and
   `CLAUDE.md § <heading>` / `CLAUDE.md §<heading>` citations instead.
2. **Check for indexers and non-Claude agent entry points**: `AGENTS.md`,
   `.github/copilot-instructions.md`, and any script, bot, or config that globs
   `.claude/rules` — for example a curriculum or search indexer built from
   `.claude/rules/*.md` and `docs/*.md` but not skill directories.
3. **Record the hits per candidate** (Step 1) or **repoint every hit in the same
   change** (Step 5).

## How a consumer changes the disposition

**Prefer moving to `docs/` over Promote when the sweep finds a path consumer.**
A promoted skill drops out of an indexer that never scans skill directories, and
a non-Claude agent pointed at the rule by `AGENTS.md` cannot load a skill.
Moving the body to `docs/<topic>.md` keeps it indexed and readable. Make that
call at Step 2 from the Step 1 sweep, so the user approves the `docs/` move
itself at Step 4.

The `docs/` move has two shapes, and they confirm differently:

| Shape | What stays in the rule | Confirmation |
|---|---|---|
| Lean to the invariant + link to `docs/<topic>.md` | The one-sentence invariant | Non-destructive — batchable with the other Keep-but-lean candidates |
| Lean to a one-line pointer at `docs/<topic>.md` | Nothing but the pointer | **Destructive** — the body leaves the every-turn surface, so it takes one candidate, one question, like Promote |

## A Step 5 hit that changes the approved disposition

When the Step 5 re-run finds a consumer the Step 1 sweep did not, and that
consumer makes the approved disposition wrong (a Promote-approved rule now cited
by `AGENTS.md`, say), **stop and re-confirm that candidate** with a
single-candidate `AskUserQuestion` before acting — present the new consumer, the
originally approved disposition, and the recommended replacement. Never switch
an approved disposition on the strength of the sweep alone: the user approved a
specific action, and a different one is an action they did not choose.

A hit that only needs repointing (a code comment, a doc link) does not change
the disposition — repoint it in the same change and carry on.

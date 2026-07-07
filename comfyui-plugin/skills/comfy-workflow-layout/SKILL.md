---
created: 2026-07-07
modified: 2026-07-07
reviewed: 2026-07-07
name: comfy-workflow-layout
description: >-
  Auto-layout a ComfyUI workflow JSON with a layered DAG algorithm. Use when a workflow's nodes overlap, are messy or cramped, or were imported and need tidying before use.
allowed-tools: Bash, Read, Grep, Glob
---

# ComfyUI workflow auto-layout

`scripts/layout_workflow.py` runs a layered (Sugiyama-style) DAG layout
over the nodes in a workflow JSON: median layering (each node sits at
the midpoint between its earliest and latest possible depth, so source
and sink nodes spread across columns instead of piling up at the edges),
a barycenter sweep within each layer to reduce edge crossings, and a
group-cohesion post-pass that clusters members of the same authored
group contiguously within each column. Group bounding boxes are re-fit
around their final members. Pure stdlib, no deps. Visual goal is "the
editor is readable again with comparable density to a hand-tuned
layout" — link routing is left to ComfyUI.

In practice on Wan 2.2 workflows in this install, output bounding-box
area ranges from −13% to +23% of a hand-arranged layout (typically
within ±10%), with 0 node overlaps. Without median layering it would
be 2× larger.

## When to Use This Skill

| Use this skill when... | Use instead when... |
|---|---|
| A workflow's nodes overlap, are messy/cramped, or were imported and need tidying | Editing the graph's wiring/links -> `comfy-workflow-json` |

## Pipeline (default mode)

1. **Detect group membership** by which nodes' centers sit in each
   group's authored bounding box. Tie-break to the smallest group.
2. **Absorb leaf singletons** — ungrouped nodes whose neighbors are
   ≥2/3 in one group join that group's membership for layout
   purposes. Single-pass; central hub nodes (whose connections fan out
   across many groups) stay as singletons.
3. **Median layering** — each node's column index is the average of
   its longest-path-from-sources and longest-path-from-sinks depth.
   Source nodes whose only consumer is at depth 8 land near depth 7,
   not 0. Sink nodes whose only producer is at depth 1 land near 1.
4. **Barycenter sweep** within each layer to minimize edge crossings.
5. **Group-cohesion clustering** — within each layer, re-permute so
   nodes sharing a group sit contiguously. Cluster order within a
   layer follows each cluster's median barycenter index.
6. **Vertically center** each column around the layer band's
   midpoint so short columns float to center rather than top-align.
7. **Recompute group bounding boxes** to wrap the final positions
   (skip with `--no-groups`).

`--strict-groups` switches to a two-level mode where each group becomes
its own bounded super-node region with a separate outer DAG between
groups. Looser packing (typically +30-50% area) but stronger visual
separation between groups; reach for it when the user prefers visible
group containers over compactness.

## When to reach for this

- User pulled a workflow from somewhere and the nodes overlap.
- A workflow grew organically and is now unreadable in the editor.
- After bulk-editing a graph (added a Phantom tail, swapped sampler
  versions, refactored loaders) and the layout no longer reflects flow.
- User says "auto-arrange", "lay out", "clean up positions", or
  references the script by name.

Skip this for ~5–8 node workflows — hand-arrange is faster and the
result will be tidier than what a layered algorithm produces on a tiny
graph.

## Default invocation (safe A/B)

From the install root, run the script via the venv on the target file:

```
.venv/bin/python scripts/layout_workflow.py user/default/workflows/2026-05/<file>.json
```

This writes `<file>-laidout.json` next to the original. Open **both** in
ComfyUI side-by-side (or load one, eyeball, then load the other) and
confirm the laid-out version is actually better before committing to
overwrite. ComfyUI picks up the new file on page reload — no service
restart needed.

The script prints a one-line summary on completion
(`42 nodes (cohesion, 3 absorbed), 13 layers, 7 groups recomputed -> ...`).
Pass `--quiet` to suppress it. In `--strict-groups` mode the summary
shape is different (`42 nodes in 8 supers (7 group + 1 singleton (3
absorbed)), 5 outer layers, ...`).

## Tune the spacing

Defaults are `--col-gap 40` (pixels between layers) and `--row-gap 20`
(pixels between nodes within a layer). If the output looks cramped,
raise the gaps. If sparse, lower them.

```
.venv/bin/python scripts/layout_workflow.py --col-gap 60 --row-gap 30 \
  user/default/workflows/2026-05/<file>.json
```

Useful starting points: 30/15 for tight, 40/20 default, 60/30 for roomy,
80/40 for very large workflows where the user wants whitespace. In
`--strict-groups` mode the inner gap uses these values; the outer
between-groups gap is fixed at 60×80 (source constants `SUPER_COL_GAP`
/ `SUPER_ROW_GAP`).

## Mode flags

```
.venv/bin/python scripts/layout_workflow.py --strict-groups <file>.json
```

Two-level group-aware layout: each group renders as its own bounded
region in a separate outer DAG. Looser packing, stronger group
separation. Use when the user wants visible group containers more than
compactness.

```
.venv/bin/python scripts/layout_workflow.py --no-cohesion <file>.json
```

Skip the group-cohesion pass — group members may scatter across the
layer based purely on barycenter. Useful when a workflow has groups
that fight DAG topology (e.g. one logical "group" spans many depths).

```
.venv/bin/python scripts/layout_workflow.py --no-absorb <file>.json
```

Don't absorb ungrouped leaf nodes into adjacent groups. Useful when
the user has deliberately placed nodes outside a group and wants the
layout to honor that.

```
.venv/bin/python scripts/layout_workflow.py --no-groups <file>.json
```

Skip the group bounding-box recompute. Positions still shift, so the
old bounding boxes will end up wrong — only useful for debugging.

## Commit the result

After confirming the laid-out version looks good, two paths:

```
mv user/default/workflows/2026-05/<file>-laidout.json \
   user/default/workflows/2026-05/<file>.json
```

Or re-run with `--in-place` to overwrite directly (no A/B copy
produced):

```
.venv/bin/python scripts/layout_workflow.py --in-place \
  user/default/workflows/2026-05/<file>.json
```

`--in-place` and `-o / --output` are mutually exclusive.

Per project `CLAUDE.md`, do not commit workflow JSONs unless asked —
workflows under `user/default/workflows/` are user data, intentionally
untracked.

## Batch a directory

Once the user confirms one workflow lays out cleanly, the rest in the
same bucket usually follow. Batch with `--in-place`:

```
for f in user/default/workflows/nsfw/2026-05/*.json; do
  case "$f" in *-laidout.json) continue ;; esac
  .venv/bin/python scripts/layout_workflow.py --in-place --verify "$f"
done
```

The `case` skips already-laid-out outputs left over from earlier A/B
runs. `--verify` aborts on overlap, which is cheap and reasonable for
batch jobs. **Always run on one workflow first**, eyeball it, then
batch — unwinding 30 simultaneously-broken layouts is painful.

## What gets preserved vs rewritten

| Preserved | Rewritten |
|---|---|
| `id`, `revision`, `last_node_id`, `last_link_id` | `nodes[*].pos` |
| `links`, `config`, `extra`, `version` | `groups[*].bounding` |
| `nodes[*].size`, `.order`, `.widgets_values` | |
| `nodes[*].inputs`, `.outputs` | |
| `nodes[*].title`, `.properties`, `.flags` | |
| `nodes[*].mode`, `.color`, `.bgcolor` | |
| `groups[*].title`, `.color` | |

Only positions move. Wiring, widget values, sizes, group identities,
and colors all carry through unchanged. Group **membership** is
detected from the original bounding boxes; the new bounding box is
rewritten to wrap the same members in their final positions.

Pass `--verify` to assert no node overlaps in the output before
writing. Cheap; reach for it when batching or when iterating on gap
values.

## Known limitations

1. **Reroute nodes** consume a full layer's column width even though
   they're tiny. Acceptable cost; don't try to special-case them.
2. **Note placement** is "above the nearest old neighbor" using
   original positions. If multiple Notes share a buddy they stack and
   may collide with the layer above. Hand-fix in the editor if it
   bothers you.
3. **Cycles in the underlying node DAG** abort the script with an
   error. A valid ComfyUI workflow shouldn't have any; if you hit one,
   the workflow itself is broken. Cycles in the *super* graph
   (`--strict-groups` mode, groups feeding each other through
   different members) are silently broken with a DFS feedback-arc-set
   pass; the dropped edges only affect outer-layer assignment, not the
   final node positions or wiring.
4. **Hand-tuned layouts that overlap groups deliberately** (e.g. two
   groups sharing a horizontal column with one above the other) won't
   be reproduced — the algorithm doesn't pack groups in 2D. The
   default mode comes within ±10% of hand-tuned area on average; the
   `--strict-groups` mode is typically +30-50% larger because each
   group claims its own outer cell.
5. **Workflows where most nodes are ungrouped** still benefit from
   median layering and cohesion, but the absorption step has nothing
   to absorb so the singleton spread is whatever it is. Authoring
   groups around the leaf clusters before running the script gives
   noticeably better output.

## When NOT to use this

- Small workflows (~5–8 nodes). Hand-arrange is faster.
- The user deliberately designed a non-DAG layout for visual reasons —
  e.g. parallel branches arranged top-to-bottom for clarity, or a
  "before / after" comparison stacked vertically. Auto-layout will
  collapse parallel branches according to their depth.
- The workflow uses `Note` nodes as section labels with hand-placed
  positioning. They survive but the placement won't match the user's
  intent.

## After running

Surface the output path so the user can navigate to it directly. After
overwriting in place, remind the user to **reload the page** in ComfyUI
to pick up the new positions — no service restart needed (and don't
restart, per project `CLAUDE.md` that would kill any running
generation). After producing `<stem>-laidout.json`, offer to `mv` it
over the original once the user confirms the new layout looks good.

# task-add — Verifying a Project Slug

Open this before trusting that a `project:` slug exists — when reusing a documented slug, consolidating projects, or filing into a project for the first time.

## `project:` is a PREFIX match — a populated result does not prove the slug

`task project:comfyui list` returns every task in `comfyui-nodes`,
`comfyui-touch-connect`, and any other project starting with that string.
Nothing in the output says so. A slug you just invented therefore *looks*
verified the moment a sibling shares its prefix, which is the whole trap:
the confirming evidence and a false positive are byte-identical.

> Observed twice (2026-08-08, comfyui-nodes). A commit titled "point the
> backlog at `project:comfyui`, **the slug that exists**" moved the documented
> slug to the one project that was nearly empty — 60 tasks sat under
> `comfyui-nodes`, 1 under `comfyui` — because `task project:comfyui list`
> showed all 60. A later session read that doc, filed four follow-ups into the
> near-empty sibling, and only caught it when a survey script printed the
> per-project counts side by side.

**To check a slug is real, read the exact value — never a filter that matches
its own prefix:**

```sh
task export | jq -r '[.[].project] | group_by(.) | map({p:.[0], n:length}) | sort_by(-.n)[]'
```

Corollaries: prefer `task <uuid> modify project:<slug>` when consolidating
(numeric ids shift); and a *new* project slug is silently created on first
`add`, so a typo never errors — it just starts a parallel backlog that the
prefix match then hides.

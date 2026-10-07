---
created: 2026-06-04
modified: 2026-07-29
reviewed: 2026-07-29
model: opus
name: comfy-node
description: >-
  Orchestrate a ComfyUI node pack from idea to registry: scaffold, create + seed
  the repo, open the gitops adoption PR. Use when releasing or spinning up a new
  comfyui node pack.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite, AskUserQuestion
---

# comfy-node

Take a ComfyUI custom-node **idea** and drive it through every step from empty
to publish-ready, collapsing the manual repo-creation + gitops wiring into one
orchestrated pass with a single human approval gate.

This is the orchestrator around the `comfyui-node-scaffold` skill (which only
generates the local repo). Use `comfyui-node-scaffold` alone if you just want
the files; use **this** when you want the GitHub repo created, pushed, and
adopted into gitops too.

> **Canonical owner of the gitops repo-adoption procedure.** Phases 3–5 below
> (seed `main` → open the gitops PR → human gate → remove the import block),
> the branch-protection hook note, and the generic failure-mode rows are the
> single source of truth for **every** laurigates repo class, not just ComfyUI
> packs. `foundryvtt-plugin:foundryvtt-module` carries only its own deltas and
> defers here. If you arrived from another skill, read
> [Adapting Phases 3–5 to another repo class](references/gitops-adoption.md#adapting-phases-35-to-another-repo-class)
> first — it names every value you substitute.

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| The user gives an idea and wants the whole pipeline stood up — repo created, seeded, and gitops-adopted | You only want the local files → `comfyui-node-scaffold` |
| Spinning up a `project:comfyui-nodes` taskwarrior backlog idea end to end | Adding a node to an *existing* pack → edit that repo directly |

Do **not** use it to add a node to an existing pack, or to publish a release
(release-please + `publish.yml` already automate that once the repo exists).

## The shape it automates

idea → `scaffold.py` → `gh repo create` + seed `main` → gitops PR → **human merges the gitops PR** → tofu-apply on release → remove the import block → implement + release. There is no scaffold PR, and the gate is never merged on the user's behalf. Diagram: [references/pipeline-overview.md](references/pipeline-overview.md).

## Preconditions

- Run from the workspace root `repos/laurigates/` (new repo lands as a sibling
  of the reference packs; modal-variant primitive copy resolves there).
- `gh auth status` is a **personal** account that can create repos. The gitops
  GitHub App *cannot* create repos on user accounts — that is exactly why the
  repo is created out-of-band here and then imported into Terraform state.
- The gitops repo is clean (no uncommitted `repositories.tf` / `main.tf`
  changes) so the orchestrator's gitops PR is isolated.

## Phase 0 — Derive and confirm the spec

From the idea, derive and **show the user** before creating anything external:

| Field | How to derive | Example |
|-------|---------------|---------|
| `--name` | `comfyui-<kebab>`; reuse the family prefix (`touch-…` for touch UX). | `comfyui-touch-resize` |
| `--display` | Title-case. | `Touch Resize` |
| `--desc` | One line, registry-facing. | `Selection-gated pinch-to-resize for ComfyUI nodes and groups on touch devices.` |
| `--variant` | `gesture` for canvas interactions (resize/move/region); `frontend` for a per-widget modal; `backend` only if it reads disk / serves data. | `gesture` |
| `--widgets` | CSV of target widget names (modal variants only; omit for `gesture`). | — |
| topics | `["comfyui","comfyui-nodes",…]` + facet tags. | `…,"mobile","touch","resize"` |

Confirm the name and variant with the user — these are hard to change after the
repo exists. If the idea matches a `project:comfyui-nodes` task, mark it
in_progress:

```sh
task project:comfyui-nodes export | jq -r '.[] | select(.description | test("resize"; "i")) | .uuid'
```

## Phase 1 — Preflight (fail fast if the name is taken)

```sh
test ! -e comfyui-touch-resize && echo "local: free" || echo "local: EXISTS"
```

```sh
grep -q '"comfyui-touch-resize"' gitops/repositories.tf && echo "gitops: EXISTS" || echo "gitops: free"
```

```sh
gh repo view laurigates/comfyui-touch-resize >/dev/null 2>&1 && echo "github: EXISTS" || echo "github: free"
```

All three must report free. Stop and surface any collision.

## Phase 2 — Scaffold + local green check

```sh
python3 ${CLAUDE_SKILL_DIR}/../comfyui-node-scaffold/scaffold.py --name comfyui-touch-resize --display "Touch Resize" --desc "Selection-gated pinch-to-resize for ComfyUI nodes and groups on touch devices." --variant gesture
```

Then bring the pack to green locally (the scaffold prints these too):

```sh
cd comfyui-touch-resize
```

```sh
uv sync --group dev
```

```sh
npm install --no-audit --no-fund
```

```sh
just check
```

`just check` must pass before anything is pushed. If it fails, fix locally and
re-run — do not create the remote repo on a red pack.

The scaffold prints a **finishing-pass audit** (issue #1877): it emits the
registry icon/banner SVGs + `Icon`/`Banner` wiring and the renovate /
registry-health / clear-autorelease workflows, and grades the follow-ups it can't
do itself. Before the first release, run `just assets` (rasterizes `icon.svg` /
`banner.svg` → the PNGs the registry serves; needs `rsvg-convert`) and commit the
PNGs. The screenshot pipeline stays deferred to the `comfyui-screenshot-pipeline`
skill (`just screenshots`) — surface it as a Phase 6 follow-up.

Treat the audit's ERROR rows as blocking, not as notes: `Icon`/`Banner` already
point at PNG URLs, so a pack that skips `just assets` publishes a 404 icon. The
pack's own `tests/test_publish_hygiene.py` fails CI on exactly that, and Phase 6
re-checks it before hand-back.

## Phase 3 — Create the GitHub repo and seed `main`

Seed `main` **directly** as the first commit — no scaffold branch, no PR. The
repo has no branch protection yet (gitops adds it on adoption in Phase 5), so
this is allowed, and it avoids the branch juggling you'd otherwise hit: if the
first push were a feature branch, `main` would be missing on origin, forcing a
later rename + default-branch change + base-branch fixups. Pushing `main` first
sidesteps all of it. Implementation work afterward goes through feature-branch
PRs as normal (protection is live by then).

```sh
git init -b main
```

```sh
git add -A
```

```sh
git commit -m "feat: scaffold comfyui-touch-resize (gesture pack)"
```

```sh
gh repo create laurigates/comfyui-touch-resize --public --source . --remote origin --push
```

> **Branch-protection hook note (expect this):** in a Claude Code session the
> `branch-protection` hook **will** block the agent from `git add`/`commit` on
> `main` (confirmed on the first real run). For a brand-new, not-yet-protected
> repo this is a false positive. Hand the whole seed to the user as one
> paste-safe line to run with the `! ` prefix, e.g.:
>
> ```
> cd <repo> && git add -A && git commit -m "feat: scaffold <name> (gesture pack)" && gh repo create laurigates/<name> --public --source . --remote origin --push
> ```
>
> (`git add -A` and `&&`-chaining are fine in the *user's* shell — those hooks
> are agent-side.) Do **not** work around it by seeding a feature branch — that
> reintroduces the missing-`main`/rename juggling this phase exists to avoid.
> Don't fight the hook with quoting tricks either.

The `--push` makes the seeded `main` the default branch.

## Phases 4–5 — gitops adoption PR, human gate, cleanup

Open the gitops PR (`repositories.tf` entry + transient `import` block), hand
the user the URLs, and **let the user merge it** — never merge it for them.
After the apply lands, verify the wiring and remove the import block. For the
HCL, commands, and the cross-repo-class substitution table, see
[references/gitops-adoption.md](references/gitops-adoption.md).

## Phase 6 — Verify the finishing pass, then hand back

**Run the gate before declaring done** — do not close on a self-authored summary:

```sh
python3 ${CLAUDE_SKILL_DIR}/../comfyui-node-scaffold/scaffold.py --verify comfyui-touch-resize
```

Read `STATUS=`; the exit code is 1 on ERROR.

| `STATUS=` | Action |
|-----------|--------|
| `ERROR` | **Not done.** Finish it now — the ERROR rows are publish-blocking (missing `icon.png`/`banner.png`, or surviving `PLACEHOLDER-GLYPH`). `just assets`, commit the PNGs, re-run. |
| `WARN` | Deferrable. Log each WARN to `project:comfyui-nodes` in taskwarrior (the queue that outlives this session) and say so in the hand-back. |
| `OK` | Hand back. |

An ERROR is never a follow-up item. It shipped that way three times —
`comfyui-touch-manager` (`Icon = ""`, weeks), `comfyui-output-swap` (31 hours),
`comfyui-touch-shim` — each recorded in the closing report as "tracked, not
blocking" and each caught only when the user noticed.

The pipeline is now live: conventional-commit feature PRs → merge → release-please
PR → merge → tag → `publish.yml` publishes to registry.comfy.org. Tell the user
what's left:

- Implement the pack logic (for `gesture`: tune `web/js/<short>.js` — groups
  support, affordance hint, the anisotropic-scale TODO).
- First merged `feat:`/`fix:` commits drive the first release-please PR.

Log durable follow-ups (groups support, browser smoke matrix, the jsdom modal
DOM test gap) to `project:comfyui-nodes` per `taskwarrior-cross-session`.

## Failure modes & guards

When a phase fails — `publish.yml` `--token` error, empty release-please `app-id`, `403` on repo create, a tofu plan showing *create* instead of *import*, red `just check` in gitops — look up the symptom in [references/failure-modes.md](references/failure-modes.md).

## Notes

The orchestrator never runs `tofu apply`. For apply routing and what the
scaffold does not emit, see
[references/scope-notes.md](references/scope-notes.md).

---
created: 2026-06-04
modified: 2026-06-04
reviewed: 2026-06-04
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

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| The user gives an idea and wants the whole pipeline stood up — repo created, seeded, and gitops-adopted | You only want the local files → `comfyui-node-scaffold` |
| Spinning up a `project:comfyui-nodes` taskwarrior backlog idea end to end | Adding a node to an *existing* pack → edit that repo directly |

Do **not** use it to add a node to an existing pack, or to publish a release
(release-please + `publish.yml` already automate that once the repo exists).

## The shape it automates

```mermaid
flowchart LR
  idea["idea"] --> sc["scaffold.py"] --> gh["gh repo create<br/>+ seed main"] --> gop["gitops PR<br/>(entry + import block)"]
  gop --> gate["👤 merge gitops PR"] --> apply["Scalr apply:<br/>adopt + secrets + protection"] --> rm["remove import block"] --> impl["implement + release"]
  classDef g fill:#1b4332,stroke:#2d6a4f,color:#fff
  classDef m fill:#6a040f,stroke:#9d0208,color:#fff
  class sc,gh,gop,apply,rm g
  class gate,impl m
```

Everything left of the gate is one orchestrated pass. There is **no scaffold
PR** — the seed goes straight to `main` (see Phase 3 for why). The single gate
(merging the gitops PR) is intentionally human — it triggers an infra `apply`
on shared state. Never merge it on the user's behalf.

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
python3 .claude/skills/comfyui-node-scaffold/scaffold.py --name comfyui-touch-resize --display "Touch Resize" --desc "Selection-gated pinch-to-resize for ComfyUI nodes and groups on touch devices." --variant gesture
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

## Phase 4 — Open the gitops PR (entry + transient import block)

Two edits in the `gitops/` repo, on a dedicated branch.

**`gitops/repositories.tf`** — add to the active repositories `locals` block,
next to the other `comfyui-*` entries (mirror `comfyui-touch-connect`):

```hcl
    "comfyui-touch-resize" = {
      description    = "Selection-gated pinch-to-resize for ComfyUI nodes and groups on touch devices"
      visibility     = "public"
      release_please = true
      comfy_registry = true
      topics         = ["comfyui", "comfyui-nodes", "mobile", "touch", "resize"]
    }
```

**`gitops/main.tf`** — add a transient `import` block alongside the existing
ones at the top of the file:

```hcl
import {
  to = github_repository.this["comfyui-touch-resize"]
  id = "comfyui-touch-resize"
}
```

Validate, branch, commit, push, open the PR (run inside `gitops/`):

```sh
just check
```

```sh
git -C gitops switch -c feat/adopt-comfyui-touch-resize
```

```sh
git -C gitops add repositories.tf main.tf
```

```sh
git -C gitops commit -m "feat: adopt comfyui-touch-resize (comfy_registry)"
```

```sh
git -C gitops push -u origin feat/adopt-comfyui-touch-resize
```

```sh
gh pr create -R laurigates/gitops -a laurigates -l chore -l opentofu --title "feat: adopt comfyui-touch-resize (comfy_registry)" --body-file /tmp/gitops-pr-body.md
```

Write a short body (to `/tmp/gitops-pr-body.md`) rather than `--fill` — it's an
infra PR that triggers an apply, so spell out what merge does: imports the repo,
pushes `REGISTRY_ACCESS_TOKEN` + release-please credentials, applies the
branch-protection ruleset, and that a follow-up PR removes the import block. Use
labels `chore` + `opentofu` (both exist in the gitops repo; check
`gh label list -R laurigates/gitops` if unsure).

Set metadata per `github-metadata-hygiene` (assignee `laurigates`; skip
self-reviewer — the author is the running user). Scalr posts a `plan` check on
the PR; the expected plan **imports** the repo and **creates** the
`REGISTRY_ACCESS_TOKEN` secret + release-please var/secret + branch-protection
ruleset.

## Phase 5 — Human gate, then finish

Hand the user the new repo URL and the **gitops PR** URL. **The user merges the
gitops PR** — that is the Scalr `apply` trigger on shared infra state. Do not
merge it for them.

After the user confirms the Scalr apply landed, verify the wiring and remove the
now-dead import block:

```sh
gh secret list -R laurigates/comfyui-touch-resize
```

```sh
gh api repos/laurigates/comfyui-touch-resize/actions/variables/RELEASE_PLEASE_APP_ID --jq .name
```

`REGISTRY_ACCESS_TOKEN` should be listed; the variable lookup should return its
name. Then open the import-block-removal follow-up PR (it is a one-time
adoption artifact — leaving it is harmless but untidy):

```sh
git -C gitops switch -c chore/remove-comfyui-touch-resize-import
```

Remove the `import { … "comfyui-touch-resize" … }` block from `main.tf`, then:

```sh
git -C gitops commit -am "chore: remove one-time import block for comfyui-touch-resize"
```

```sh
git -C gitops push -u origin chore/remove-comfyui-touch-resize-import
```

```sh
gh pr create -R laurigates/gitops -a laurigates -l chore --fill --title "chore: remove comfyui-touch-resize import block"
```

## Phase 6 — Hand back to implementation

The pipeline is now live: conventional-commit feature PRs → merge → release-please
PR → merge → tag → `publish.yml` publishes to registry.comfy.org. Tell the user
what's left:

- Implement the pack logic (for `gesture`: tune `web/js/<short>.js` — groups
  support, affordance hint, the anisotropic-scale TODO).
- First merged `feat:`/`fix:` commits drive the first release-please PR.

Log durable follow-ups (groups support, browser smoke matrix, the jsdom modal
DOM test gap) to `project:comfyui-nodes` per `taskwarrior-cross-session`.

## Failure modes & guards

| Symptom | Cause | Fix |
|---------|-------|-----|
| `publish.yml` fails `Option '--token' requires an argument` | `comfy_registry` flag not yet applied | Confirm the Scalr apply landed; `gh secret list` shows `REGISTRY_ACCESS_TOKEN`; re-run `gh workflow run publish.yml -R laurigates/<name>` |
| release-please job fails on empty `app-id` | `release_please` credentials not applied, or repo on the legacy PAT workflow | The scaffold ships the App-token `release-please.yml`; confirm apply landed, re-run via `workflow_dispatch` |
| `403 Resource not accessible by integration` on repo create | Tried to create via the gitops App, not a personal token | Create with personal `gh auth`; the App only adopts via import |
| Scalr plan shows a *create* (not *import*) for the repo | Import block missing or `id` wrong | The `id` is the bare repo name, not `owner/name`; add/fix the import block |
| `just check` red in gitops | `tofu fmt`/`validate` failure | `just format` then re-check before pushing |

## Notes

- The orchestrator never runs `tofu apply` — all applies go through Scalr on
  merge (see `gitops/CLAUDE.md`). Local gitops work is `plan`/`validate` only.
- Screenshots pipeline + `docs/blueprint/` PRD/ADR set are not scaffolded; add
  them later from a reference pack if the pack warrants them.

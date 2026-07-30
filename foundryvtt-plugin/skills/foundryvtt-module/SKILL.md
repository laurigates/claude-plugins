---
created: 2026-06-26
modified: 2026-07-30
reviewed: 2026-07-30
name: foundryvtt-module
description: >-
  FoundryVTT module idea to gitops-adopted repo: scaffold, create + seed the
  repo, open the gitops adoption PR. Use when releasing or spinning up a new
  foundry module.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite, AskUserQuestion
---

# foundryvtt-module

Drives a FoundryVTT **module idea** to a release-ready, gitops-adopted GitHub
repository in one pass, pausing at exactly one human approval.

Reach for `foundryvtt-module-scaffold` on its own when all you want is the local
file tree. Reach for **this** skill when the remote repo should also exist, be
seeded, and be under Terraform management by the time you stop.

## Delegated: the gitops repo-adoption procedure

The second half of this pipeline — creating and seeding the GitHub repo, opening
the gitops adoption PR, the human merge gate, and the import-block-removal
follow-up — is **not duplicated here**. It is identical for every laurigates repo
class and is owned by:

> **`comfyui-plugin:comfy-node`, Phases 3 → 5** (plus its branch-protection hook
> note and its generic failure-mode rows).

That skill's *Adapting Phases 3–5 to another repo class* section names every
value to substitute. Run Phases 0 → 2 here, apply the deltas in
[FoundryVTT deltas](#foundryvtt-deltas), then execute Phases 3 → 5 there.

Two consequences of that procedure worth stating up front, because they shape
what you do in Phase 2 below:

- The seed commit lands on `main` with no intervening branch or PR — read the
  owner's Phase 3 for *why* that ordering is load-bearing, not just convenient.
- A Claude Code session will hit a `branch-protection` hook block on that seed.
  The owner's note explains the hand-off; do not invent a workaround.

## When to Use This Skill

| Reach for this skill | Reach elsewhere |
|---|---|
| An idea needs to become a live repo — files, remote, gitops entry, release pipeline | Only local files are wanted → `foundryvtt-module-scaffold` |
| Nothing exists yet under that module name | The module already exists → work in its repo |
| Someone asks to "spin up" or "stand up" a Foundry module | A release is due → release-please and the release workflow already handle it |

## Preconditions

- Work from the FoundryVTT workspace (`repos/laurigates/foundryvtt-dev/`), so the
  new checkout sits beside `foundryvtt-mcp` / `foundryvtt-mediasoup-webrtc`. The
  gitops clone is therefore at `../gitops`.
- The remaining preconditions (a **personal** `gh auth` that may create repos, and
  an uncommitted-change-free gitops clone) are stated once in the owner skill —
  satisfy them before Phase 3.

## Phase 0 — Derive and confirm the spec

From the idea, derive and **show the user** before creating anything external:

| Field | How to derive | Example |
|-------|---------------|---------|
| `--name` | `foundryvtt-<kebab>` (the GitHub repo). | `foundryvtt-initiative-tweaks` |
| `--id` | Foundry module id; default = `--name` minus `foundryvtt-`. | `initiative-tweaks` |
| `--display` | Title-case. | `Initiative Tweaks` |
| `--desc` | One line, manifest-facing. | `Small quality-of-life tweaks to the combat initiative tracker.` |
| `--variant` | `app` for a UI window; `libwrapper` to patch a core method; else `basic`. | `basic` |
| `--fvtt-verified` | The major Foundry version the harness pins. | `13` |
| topics | `["foundryvtt", "module", …]` + facet tags. | `…,"combat","initiative"` |

Get explicit user sign-off on **name, id, and variant** — renaming any of the
three after the repo exists is expensive.

## Phase 1 — Preflight

Three lookups; every one must come back free before you continue. Any collision
is a full stop — report it and wait.

```sh
test ! -e foundryvtt-initiative-tweaks && echo "local: free" || echo "local: EXISTS"
```

```sh
grep -q '"foundryvtt-initiative-tweaks"' ../gitops/repositories.tf && echo "gitops: EXISTS" || echo "gitops: free"
```

```sh
gh repo view laurigates/foundryvtt-initiative-tweaks >/dev/null 2>&1 && echo "github: EXISTS" || echo "github: free"
```

(`../gitops` assumes the foundryvtt-dev layout; point it at wherever the gitops
clone actually lives.)

## Phase 2 — Scaffold, init, and get to green

```sh
python3 ${CLAUDE_SKILL_DIR}/../foundryvtt-module-scaffold/scaffold.py --name foundryvtt-initiative-tweaks --display "Initiative Tweaks" --desc "Small quality-of-life tweaks to the combat initiative tracker." --variant basic
```

```sh
cd foundryvtt-initiative-tweaks
```

```sh
git init -b main
```

```sh
bun install
```

```sh
just check
```

Notes specific to this stack:

- **`git init -b main` precedes `bun install`** — the install step wires git
  tooling and expects a repository to already be present.
- **`bun.lock` belongs in the seed commit.** `bun install` writes it and CI runs
  `--frozen-lockfile`; a seed without it fails on the first workflow run.
- `just check` is typecheck + build + lint + test. A red module never reaches
  GitHub — repair it here and re-run.

## FoundryVTT deltas

Substitutions to apply while executing `comfyui-plugin:comfy-node` Phases 3 → 5.
Everything the owner skill states that is not listed here applies verbatim.

| Owner's step | FoundryVTT value |
|---|---|
| Repo name | `foundryvtt-initiative-tweaks` |
| gitops clone path | `../gitops` — so `git -C ../gitops …` throughout, and `grep … ../gitops/repositories.tf` |
| Seed commit subject | `feat: scaffold foundryvtt-initiative-tweaks (basic module)` |
| `repositories.tf` entry | `release_please = true` and **no registry flag** — see below |
| PR title | `feat: adopt foundryvtt-initiative-tweaks` |
| What merging the PR pushes | The release-please App credentials only (no registry token) |
| Phase 5 verification | `gh api repos/laurigates/foundryvtt-initiative-tweaks/actions/variables/RELEASE_PLEASE_APP_ID --jq .name` — it should echo the variable name. Skip the owner's `gh secret list` probe; there is no registry secret to find. |

The entry to add under the active repositories `locals` block, beside the other
`foundryvtt-*` entries (mirror `foundryvtt-mcp`):

```hcl
    "foundryvtt-initiative-tweaks" = {
      description    = "Small quality-of-life tweaks to the combat initiative tracker"
      visibility     = "public"
      release_please = true
      topics         = ["foundryvtt", "module", "combat", "initiative"]
    }
```

**Why no registry flag:** Foundry modules are distributed as GitHub release
assets, not through a package registry, so there is no analogue of a ComfyUI
pack's `comfy_registry`. `release_please = true` is the whole adoption surface.

## Phase 6 — Verify the finishing pass, then hand back

**Run the gate before declaring done** — do not close on a self-authored summary:

```sh
python3 ${CLAUDE_SKILL_DIR}/../foundryvtt-module-scaffold/scaffold.py --verify foundryvtt-initiative-tweaks
```

Read `STATUS=`; the exit code is 1 on ERROR.

| `STATUS=` | Action |
|-----------|--------|
| `ERROR` | **Not done.** The ERROR rows are install-blocking — the module id disagrees across `module.json`/`vite.config.ts`/`src/constants.ts`, `esmodules` names a file the build never emits, or an install URL resolves to a release asset that does not exist. Fix and re-run. |
| `WARN` | Deferrable. Log each WARN to `project:foundryvtt` in taskwarrior and say so in the hand-back. |
| `OK` | Hand back. |

An ERROR is never a follow-up item: every one of them ships a module Foundry
either refuses to install or loads to nothing, with no error anywhere in CI. The
same invariants run in the module's own `test` job (`tests/manifest.test.ts`), so
a later drift fails a PR rather than a user's install.

Once the apply lands, the delivery chain is live: conventional-commit PRs →
release-please PR → tag → the release workflow builds, zips `dist/`, and attaches
`<id>.zip` plus `module.json` (the manifest URL) to the GitHub release.

Remaining work to hand over:

- Write the module logic — `basic`: `src/module.ts` + `src/settings.ts`; `app`:
  `src/app.ts` + `templates/app.hbs`; `libwrapper`: swap the `Token._draw`
  example in `src/patches.ts` for the real patch.
- Exercise it against the local `foundryvtt-harness` (`bun run dev`, or build and
  symlink `dist/` into `Data/modules/<id>`). Keep `module.json` `compatibility`
  aligned with the Foundry version the harness pins.
- The first `feat:`/`fix:` merge triggers the first release-please PR.

Record durable follow-ups in the user's FoundryVTT taskwarrior project per
`taskwarrior-cross-session`.

## Failure modes specific to FoundryVTT

The gitops-side failures (empty release-please `app-id`, `403 Resource not
accessible by integration`, a plan that *creates* instead of *imports*, a red
`just check` in gitops) are diagnosed in the owner skill's table. Foundry adds
one of its own:

| Symptom | Cause | Fix |
|---------|-------|-----|
| Module fails to load in Foundry | `esmodules` path ≠ Vite output, or `id` ≠ install folder | The scaffold pins both; confirm `dist/<id>.mjs` exists and the installed folder is named `<id>` |
| CI fails on the very first run with a lockfile error | `bun.lock` missing from the seed commit | Commit it — `--frozen-lockfile` has nothing to check against |

## Notes

- Playwright integration tests against the harness, and a Quench in-Foundry
  suite, are deliberately not scaffolded. Add them when the module earns them.
- Local gitops work stays read-only (`plan` / `validate`); the owner skill
  explains why applies only ever run through `tofu-apply.yml`.

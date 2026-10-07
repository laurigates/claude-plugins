# comfy-node - gitops adoption (Phases 4–5)

The gitops PR, the human merge gate, post-apply verification, the import-block removal, and how to adapt Phases 3–5 to another repo class.

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
self-reviewer — the author is the running user). The `tofu-plan.yml` workflow
posts the plan as a comment on the PR; the expected plan **imports** the repo
and **creates** the
`REGISTRY_ACCESS_TOKEN` secret + release-please var/secret + branch-protection
ruleset.

## Phase 5 — Human gate, then finish

Hand the user the new repo URL and the **gitops PR** URL. **The user merges the
gitops PR** — that starts the apply chain on shared infra state (release-please
cuts a gitops release PR; merging that publishes a release, which triggers
`tofu-apply.yml`). Do not merge it for them.

After the user confirms the tofu apply landed, verify the wiring and remove the
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

## Adapting Phases 3–5 to another repo class

Phases 3–5 are repo-class-agnostic: the seed-`main`-first rationale, the
branch-protection hook workaround, the `import`-block mechanics, the human gate,
and the import-block-removal follow-up are identical for a ComfyUI pack, a
FoundryVTT module, or anything else gitops adopts. Only these values change —
substitute them and the phases read verbatim:

| Substitute | ComfyUI pack (the examples above) | How to find yours |
|---|---|---|
| Repo name | `comfyui-touch-resize` | The caller skill's Phase 0 spec |
| Workspace → gitops path | `gitops/` (run from `repos/laurigates/`) | `gitops/` if the clone is a sibling; `../gitops/` from a nested workspace |
| `repositories.tf` adoption flags | `release_please = true` + `comfy_registry = true` | `release_please = true` is universal; extra flags are per-repo-class |
| Seed commit subject | `feat: scaffold <name> (gesture pack)` | `feat: scaffold <name> (<variant> <noun>)` |
| Phase 5 verification | `gh secret list` (`REGISTRY_ACCESS_TOKEN`) **and** the `RELEASE_PLEASE_APP_ID` variable lookup | Check one probe per flag you set; `release_please` always means the `RELEASE_PLEASE_APP_ID` variable |

Everything else — the commands, the PR-body guidance, the labels, the metadata
hygiene, the failure-mode rows in [failure-modes.md](failure-modes.md) — applies unchanged.

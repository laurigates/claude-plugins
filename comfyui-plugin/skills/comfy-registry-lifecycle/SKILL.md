---
created: 2026-07-07
modified: 2026-08-14
reviewed: 2026-07-07
name: comfy-registry-lifecycle
description: >-
  Comfy Registry release pipeline: release-please + lockfile drift traps, the empty-web/dist publish bug, version status states, phantom versions, icon/banner generation. Use when debugging a pack's publish pipeline.
allowed-tools: Bash, Read, Grep, Glob, Write, Edit
---

# comfy-registry-lifecycle

A ComfyUI custom-node pack's release flow: conventional commits →
release-please bumps `pyproject.toml` + `CHANGELOG.md` → merge the release
PR → the published GitHub release triggers `publish.yml` →
`Comfy-Org/publish-node-action` publishes to registry.comfy.org. The
failures below live in this flow (or the CI that gates it) and are easy to
ship without noticing, because the pipeline reports green while the
registry artifact is broken.

## When to Use This Skill

| Use this skill when... | Use instead when... |
|---|---|
| Setting up or debugging a pack's release-please -> publish.yml -> registry pipeline | Writing the pack's frontend/backend code itself -> `comfyui-node-authoring` |
| A published node's frontend or artwork isn't showing up correctly | Smoke-testing the pack in a running instance -> `comfyui-pack-live-smoke` |

## 1. `uv.lock` self-version drifts — release-please has no native uv.lock support

release-please bumps `pyproject.toml` but not the pack's own version in `uv.lock`. Before merging a release PR, or when scaffolding or auditing a pack, apply the `toml` `extra-files` updater and pre-release check in [references/uv-lock-and-changelog.md](references/uv-lock-and-changelog.md).

## 2. The registry "Updates" changelog — use native `COMFY_NODE_CHANGELOG`, not a post-publish PUT

Empty "Updates" section or a red post-publish changelog step (`tomllib`): export `COMFY_NODE_CHANGELOG` before publishing — step in [references/uv-lock-and-changelog.md](references/uv-lock-and-changelog.md).

## 3. Bumping a shared frontend-kit dependency: regenerate the lockfile *and* the built bundle together

Bumping a shared TS package a pack inlines at build time: regenerate `bun.lock` **and** rebuild `web/dist` in the same commit. CI symptoms and a pack-set consistency loop: [references/shared-kit-bump.md](references/shared-kit-bump.md).

## The empty-`web/dist` publish trap

For TS-built packs, the registry tarball is supposed to force-ship the
built frontend via `[tool.comfy] includes = ["web/dist"]`. The trap: a
published tarball can contain `web/dist/` as an **empty directory** — no
`index.js` — while `publish.yml` reports green.

Root cause is the publish action, not the include:

- `Comfy-Org/publish-node-action@v1` (and tags `1.0.0` / `1.0.1`) run an
  **unconditional `actions/checkout@v4`** that wipes the git-ignored
  `web/dist` a prior `bun run build` step produced. **None of the tagged
  releases have a `skip_checkout` input.**
- `skip_checkout` exists **only on the action's `main` branch** (added
  2025-05-03, commit `c742414d`; no tagged release carries it).
- `comfy node publish` then packs git-tracked files + `includes`; its
  `zip_files` walks an included dir's contents **only if the dir exists at
  pack time** — if absent it writes an empty-dir entry. A wiped `web/dist`
  → empty `web/dist/` in the tarball.

**Fix** — pin the action to the commit that gates checkout on
`skip_checkout` (no tag has it yet):

```yaml
      - name: Publish Custom Node
        # @v1/1.0.x lack skip_checkout and wipe the built web/dist. Pin
        # the main commit that gates checkout on skip_checkout (no tag has it).
        uses: Comfy-Org/publish-node-action@d2366e7abb6ab16f3bb03e3520ae25c8cf749bc9  # v1.0.2-dev (main HEAD; skip_checkout not yet tagged)
        with:
          personal_access_token: ${{ secrets.REGISTRY_ACCESS_TOKEN }}
          skip_checkout: 'true'
```

`skip_checkout: 'true'` is **silently ignored** by `@v1` — passing it
without repinning does nothing, which is exactly what lets this hide for
weeks.

### Verify a publish actually shipped the frontend

Never trust a green `publish.yml` run — it succeeds even when the tarball
is empty. Download the real artifact and inspect it:

```sh
python3 - <<'PY'
import json, urllib.request, zipfile, io
nid, ver = "<node-id>", "<version>"
d = json.load(urllib.request.urlopen(f"https://api.comfy.org/nodes/{nid}/versions"))
v = next(x for x in d if x["version"] == ver)
z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(v["downloadUrl"]).read()))
print([n for n in z.namelist() if n.startswith("web/dist/") and n.endswith((".js",".css"))])
PY
```

Empty list ⇒ broken tarball. The `downloadUrl`
(`cdn.comfy.org/<owner>/<id>/<ver>/node.zip`) is in each version object.

## Version status: Pending vs Flagged vs Active

`api.comfy.org/nodes/<id>/versions` returns every version with a `status`:

| Status | Meaning | Action |
|---|---|---|
| `NodeVersionStatusPending` | held while the automated security scan runs | **auto-transitions** to Active, usually < a few hours — just wait |
| `NodeVersionStatusActive` | scan passed; installable | none |
| `NodeVersionStatusFlagged` | scan flagged it | **stuck** — does NOT auto-clear. Still installable; drops out of the Active-only listing (`/nodes/<id>` `latest_version`). Full reasons: `GET /nodes/<id>/versions?include_status_reason=true` (undocumented public param — see the security-scan section below). Republishing re-runs the scan; appeal via Comfy-Org if a false positive |
| `NodeVersionStatusBanned` | moderation banned it | **not installable** — `/install` skips it and falls back to the newest non-banned version, which can be old and itself `deprecated` |

ComfyUI-Manager (and so `comfy node install`) resolves through
`GET /nodes/<id>/install`, which returns the newest **non-Banned** version —
Flagged included. Measured 2026-08-27 (laurigates/comfyui-image-browser#111):
a Flagged 0.1.32 resolved to 0.1.32, a Banned 0.1.30 resolved to 0.1.7. While
a fixed version is Pending, installs still serve an older one. `comfy node registry-install` can fetch a Pending
version directly.

Flag false-positives are real: an identical commit can flag one pack but
not a structurally-identical sibling. Don't assume your code is the
problem — get the scan reasons (email) first.

## The security scan: what flags, what the reasons mean, how to shrink the surface

Any finding flags a version, whatever its severity. When a version is `Flagged`, read [references/security-scan.md](references/security-scan.md) for reading the reasons, the known issue classes, shrinking the shipped surface, and the appeal path.

## Phantom versions (higher semver, ahead of git)

A version published once from a stale local copy can sit in the registry
**ahead of git** (e.g. `0.2.0` Active while git is at `0.1.7`). Because
install resolves to highest-semver Active, that phantom becomes the
clean-install target and **outranks every later fix** below it. Two ways
out:

1. Release a version **> the phantom** (`Release-As`, below) — the fix must
   outrank it.
2. **Remove the phantom** from the registry dashboard — then the next
   Active version wins.

## `Release-As` is stripped by squash-merge

To force release-please to a specific version (e.g. to leapfrog a
phantom), a commit needs a `Release-As: X.Y.Z` **trailer**. The trap:
**GitHub squash-merge rebuilds the commit body from the PR description**,
so the trailer only survives if it's a clean line in the *PR description*
— a trailer that lives only in the branch commit, or sits inside backticks
or mid-sentence, is dropped and release-please falls back to a plain patch
bump. Reliable options:

- **"Rebase and merge"** the trigger PR — preserves the commit message
  verbatim, trailer intact.
- Or put `Release-As: X.Y.Z` as a plain last line of the **PR description**
  (no backticks) for squash.

Do **not** hand-edit `.release-please-manifest.json` / `CHANGELOG.md` to
force a version — it conflicts with the automation.

## Standing feedback: the `registry-health` workflow

A `.github/workflows/registry-health.yml` (runs after publish, daily, and
on demand) that looks up the `pyproject.toml` version in the registry and
**fails + opens a `registry-health` issue** when that version is Flagged,
Banned, stuck Pending, missing, or outranked by a phantom — auto-closing when
healthy — is the early-warning the publish pipeline lacks on its own.
On Flagged or Banned it queries `?include_status_reason=true` and writes the
scan findings (issue type / scanner / file / description) into the issue body,
so the security-scan verdict is readable without Discord, and it names the
version `/install` actually resolves to — the number that says whether
anyone's install is broken (Flagged: no; Banned: yes). Worth adding to
any new pack (the scaffold emits it).

## Backport to the scaffold

If `publish.yml` is generated by a scaffold template (as it is for
`comfyui-node-scaffold` → `scaffold.py`), fix the template in the same
sweep as any live packs, or every newly-scaffolded pack inherits the same
broken step.

## Icons & banners

Without `[tool.comfy] Icon`, the registry shows a generic placeholder. When creating or auditing pack art, follow [references/icons-and-banners.md](references/icons-and-banners.md): icon spec + `identify` framing gate, cairosvg (not ImageMagick), the banner pipeline (`scripts/registry_banner_*.py`), `Icon`/`Banner` URLs, and the release flow.

## Agentic Optimizations

| Context | Command |
|---|---|
| Read scan verdicts | `curl -s "https://api.comfy.org/nodes/<id>/versions?include_status_reason=true" \| jq -c '.[] \| select(.status == "NodeVersionStatusFlagged") \| {version, status_reason}'` |

## Verify

**#1/#2/lockfile issues**: static-checkable (YAML + actionlint; `uv lock`
diff is one line), but the changelog path is only exercised at real
publish time. Definitive proof = the **next release's publish job goes
green with a populated Updates section**.

**publish action pin**: the pack-set consistency check above returning
`range == locked` for every consumer, plus a downloaded-tarball inspection
showing a non-empty `web/dist/`.

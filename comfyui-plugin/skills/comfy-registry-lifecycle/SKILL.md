---
created: 2026-07-07
modified: 2026-07-07
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

The lockfile records the **workspace package's own version** in its
`[[package]]` entry. release-please's `python` release-type bumps
`pyproject.toml` but **not** `uv.lock`
([googleapis/release-please#2561](https://github.com/googleapis/release-please/issues/2561)),
so the lock's self-version silently trails `pyproject.toml` across releases.
There is **no uv/`pyproject.toml` setting** to omit the project's own
version from the lock, so the lock must be kept in sync explicitly.

**Fix — a structured `toml` `extra-files` updater** in
`release-please-config.json` (the declarative equivalent of
`uv lock --upgrade-package`, not a hand-edit):

```json
"extra-files": [
  {
    "type": "toml",
    "path": "uv.lock",
    "jsonpath": "$.package[?(@.name.value=='<pack-name>')].version"
  }
]
```

`<pack-name>` is the directory/package name. The `toml` updater parses the
lock and sets only the matched `version` value at the JSONPath — everything
else stays byte-stable. Note `.name.value` (release-please's TOML AST wraps
scalar values).

To repair an already-drifted lock once: `uv lock` regenerates it to match
`pyproject.toml` (the only diff is the self-version line, plus occasional uv
specifier normalization like `>=1.40` → `>=1.40.0`).

**Sweeps miss packs — check before the first release, not after.** A pack
created after a fix sweep can silently lack the updater. Before merging any
pack's release PR — and when scaffolding or auditing a pack — confirm
`grep -c extra-files release-please-config.json` ≥ 1 and that the release
PR's changed files include `uv.lock`. Adding the updater to `main` while a
release PR is open regenerates that PR to include the lock bump.

## 2. The registry "Updates" changelog — use native `COMFY_NODE_CHANGELOG`, not a post-publish PUT

`comfy node publish` sets the per-version changelog **natively** via the
`COMFY_NODE_CHANGELOG` env var
([Comfy-Org/comfy-cli#467](https://github.com/Comfy-Org/comfy-cli/issues/467),
released in comfy-cli 1.11+), populating the registry's "Updates" section
atomically at publish time.

**Do not** hand-roll a post-publish step that resolves the version UUID and
`PUT`s to `https://api.comfy.org/publishers/.../versions/{id}`. A
hand-rolled step that extracts `node_id`/`version` via `python3 -c 'import
tomllib'` fails on every release with `ModuleNotFoundError: No module named
'tomllib'`, because `Comfy-Org/publish-node-action` pins **Python 3.10**
and `tomllib` is 3.11+ stdlib. Under `bash -e` it dies before any `|| exit
0` guard — the node still publishes, but the Updates section is empty and
the job shows red, which is easy to miss.

**Correct shape**: a step *before* the publish-node-action step that
flattens the release notes to plain text (the registry renders Updates as
plain text) and exports it, so the action's `comfy node publish` reads it
from the job environment:

```yaml
- name: Compute registry changelog from release notes
  if: github.event_name == 'release' && github.event.release.body != ''
  env:
    RELEASE_BODY: ${{ github.event.release.body }}   # via env, not inline interpolation
  run: |
    changelog=$(python3 <<'PY'
    # pure-`re` markdown→plaintext flatten (no tomllib); prints the changelog
    PY
    )
    {
      echo "COMFY_NODE_CHANGELOG<<__CHANGELOG_EOF__"
      echo "$changelog"
      echo "__CHANGELOG_EOF__"
    } >> "$GITHUB_ENV"
```

`$GITHUB_ENV` exports the var to all later steps in the job, including the
composite `publish-node-action` run. No PUT, no UUID lookup, no `tomllib`.

## 3. Bumping a shared frontend-kit dependency: regenerate the lockfile *and* the built bundle together

For a TS-built pack that consumes a shared TypeScript package inlined at
build time (`bun build` bundles the import into `web/dist`), bumping the
version range in `package.json` looks like a one-line change but silently
desyncs **two** other committed artifacts, and CI catches each with a
different, non-obvious error:

- **`bun.lock` goes stale** — its pinned resolution still satisfies the
  *old* range, so it isn't touched by hand-editing `package.json`. CI runs
  `bun install --frozen-lockfile`, which fails with `error: No version
  matching "^X.Y.0" found for specifier "<pkg>" (but package exists)` — a
  confusing message, since the version genuinely is published; the real
  problem is the *lockfile's stale resolution*.
- **`web/dist` goes stale** — the committed bundle still contains the old
  inlined code. A "verify committed `web/dist` is up to date" CI gate (a
  `git diff --exit-code -- web/dist` after a fresh build) fails.

Both gates are correct — the footgun is that the fix requires **two**
commands, and the second failure only surfaces *after* the first is fixed
(the frozen-lockfile failure blocks the build step that would otherwise
reveal the dist-drift):

```sh
bun install   # regenerates bun.lock to resolve the new range
bun run build # rebuilds web/dist against the new dependency version
git add bun.lock web/dist/index.js
```

Commit both in the same commit as the `package.json` bump — don't split
them, and don't stop after fixing the lockfile install failure without also
rebuilding `web/dist`.

Across a whole pack set, check for consistency (range equals locked version
in every consumer):

```sh
for repo in <pack-glob>; do
  [ -f "$repo/package.json" ] || continue
  range=$(grep -o '"<shared-pkg>": *"[^"]*"' "$repo/package.json" | grep -o '\^[0-9.]*')
  locked=$(grep -o '<shared-pkg>@[0-9.]*' "$repo/bun.lock" 2>/dev/null | head -1)
  echo "$repo | range=$range | $locked"
done
```

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
| `NodeVersionStatusFlagged` | scan flagged it | **stuck** — does NOT auto-clear. Reason is only on `registry.comfy.org` (the public API exposes none). Republishing re-runs the scan; appeal via Comfy-Org if a false positive |

`comfy node install` resolves to the **highest-semver Active** version. So
while a fixed version is Pending, installs still serve the older (possibly
broken) Active one. `comfy node registry-install` can fetch a Pending
version directly.

Flag false-positives are real: an identical commit can flag one pack but
not a structurally-identical sibling. Don't assume your code is the
problem — check the dashboard reason first.

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
stuck Pending, missing, or outranked by a phantom — auto-closing when
healthy — is the early-warning the publish pipeline lacks on its own.
Worth adding to any new pack.

## Backport to the scaffold

If `publish.yml` is generated by a scaffold template (as it is for
`comfyui-node-scaffold` → `scaffold.py`), fix the template in the same
sweep as any live packs, or every newly-scaffolded pack inherits the same
broken step.

## Icons & banners

Without `[tool.comfy] Icon`, the registry shows a generic placeholder.

### Icon design system

- **400×400 SVG**, dark squircle tile (`#12121a`→`#1f1f2a` gradient,
  `rx≈76`), ~56 px inner padding, one bespoke glyph centred.
- **Glyph colour encodes the sub-family** so a set of packs reads as a
  family (e.g. amber for one facet, blue for another). Keep tile, corner
  radius, and stroke weight uniform across packs.

### Rasterize SVG with cairosvg — NOT ImageMagick

ImageMagick's internal MSVG renderer **silently drops `stroke`,
`fill="none"`, and gradients** — only *filled* shapes render, so
stroke-based glyphs come out half-missing and a gradient tile goes flat
black. Use cairosvg:

```sh
uvx --from cairosvg cairosvg icon.svg -o icon.png -W 400 -H 400
```

`magick`/ImageMagick is fine for PNG compositing/montages — just never for
SVG→PNG of stroke art. If neither `rsvg-convert` nor `inkscape`/`resvg` is
available, cairosvg via `uvx` is the reliable fallback path.

### Banners (21:9) — AI background + composited branding

Diffusion is the right tool for the *background*, the wrong tool for
*icons* and *text*. Generate a clean background, then composite crisp
branding on top. `scripts/registry_banner_bg.py` and
`registry_banner_compose.py` (this skill's `scripts/`) implement this
two-step pipeline against a running ComfyUI instance:

```sh
python3 scripts/registry_banner_bg.py \
  --accent "warm amber and orange" --seed 101 --out bg.png \
  --host "${COMFYUI_HOST:-127.0.0.1:8188}"
```

Generates a 1344×576 (exact 21:9) abstract on-brand texture with **no
text/letters/logo/symbols** requested in the prompt.

```sh
python3 scripts/registry_banner_compose.py \
  --bg bg.png --icon icon.png --name "Display Name" \
  --tagline "Short tagline" --accent '#ffb02e' --out banner.png
```

Composites the icon + name wordmark + tagline with ImageMagick. Text stays
sharp and correctly spelled this way — never trust a diffusion model to
render pack names.

### Wiring into the registry (`pyproject.toml` `[tool.comfy]`)

- `Icon` / `Banner` are **URLs**, not tarball paths. Use
  raw.githubusercontent off the default branch:
  `Icon = "https://raw.githubusercontent.com/<owner>/<repo>/main/icon.png"`
- They 404 on the PR branch and resolve the instant the PR merges to
  `main` (icon + version land together). Keep the art files and the
  metadata change in the **same PR**.
- Leave `[tool.comfy] includes` unchanged — the icon is fetched from the
  URL, not shipped in the publish tarball.

### release-please owns the version — never hand-bump

Add Icon/Banner + art with a conventional-commit PR (`fix:` → patch,
`feat:` → minor). **Do not touch `version`.** Squash-merge → release-please
opens a release PR with the bump → merge that → it cuts the GitHub Release
(which publishes).

### `publish.yml` — trigger on the release event, not the pyproject path

A publish workflow triggering on `push: paths: [pyproject.toml]` re-fires
on *any* pyproject edit and 400s with `"node version already exists"`. Fix
it to fire once per real release:

```yaml
on:
  workflow_dispatch:
  release:
    types: [published]
```

release-please emits a *published* Release when its release PR merges →
publish runs exactly once with the bumped version. Bonus: merging the icon
PR itself no longer triggers a spurious publish.

### Verify after merge

```sh
curl -sI https://raw.githubusercontent.com/<owner>/<repo>/main/icon.png   # 200 image/png
gh run list -R <owner>/<repo> --workflow=publish.yml -L1                  # release/success
curl -s https://api.comfy.org/nodes/<id>/versions                        # new version present
```

## Verify

**#1/#2/lockfile issues**: static-checkable (YAML + actionlint; `uv lock`
diff is one line), but the changelog path is only exercised at real
publish time. Definitive proof = the **next release's publish job goes
green with a populated Updates section**.

**publish action pin**: the pack-set consistency check above returning
`range == locked` for every consumer, plus a downloaded-tarball inspection
showing a non-empty `web/dist/`.

# comfy-registry-lifecycle — Icons and Banners

The pack-family icon spec and framing gate, SVG rasterization, the 21:9 banner pipeline, `[tool.comfy]` wiring, and releasing the art. Entry point: [`../SKILL.md`](../SKILL.md) § Icons & banners.

## Icons & banners

Without `[tool.comfy] Icon`, the registry shows a generic placeholder.

### Icon design system

The exact spec every pack shares (canonical — the scaffold's `icon.svg`
placeholder and every hand-drawn glyph target this):

- **400×400 canvas**, `viewBox 0 0 400 400`.
- **Dark inset tile**, verbatim:
  `<rect x="28" y="28" width="344" height="344" rx="76" fill="url(#tile)" stroke="#2a2a36" stroke-width="2"/>`
  where `#tile` is a **vertical** gradient `#1f1f2a`→`#12121a`
  (`x1=0 y1=0 x2=0 y2=1`). The 28 px inset is the family margin — not
  full-bleed.
- **One bespoke pictographic glyph**, centred, filling the tile. **No
  letters** in final art — every sibling uses a pictogram; a letter is a
  placeholder only.
- **Glyph colour encodes the sub-family**: **`#ffb02e` (orange)** for
  touch/interaction packs, **`#6ba6ff` (blue)** for info/gallery packs.
  Secondary accents (`#ffd866`, `#6bff8e`) appear sparingly. Keep tile,
  radius, stroke, and gradient **identical** across packs.

**Framing gate (the consistency check).** Because the tile is the outermost
drawn element, a correctly-framed icon *always* trims to the same box —
run it on every pack:

```sh
identify -format '%wx%h / %@\n' icon.png    # MUST be: 400x400 / 346x346+27+27
```

A `512x512 / 512x512+0+0` result is the classic drift: a full-bleed tile on
the wrong canvas, which renders visibly larger and off-palette on the
registry grid. This is exactly how `comfyui-touch-shim` shipped the raw
512×512 green-letter scaffold placeholder while the other 10 packs matched —
the trim box is the one-line audit that catches it across the fleet:

```sh
for d in comfyui-*/; do printf '%-28s %s\n' "$d" "$(identify -format '%wx%h/%@' "$d/icon.png" 2>/dev/null)"; done
```

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

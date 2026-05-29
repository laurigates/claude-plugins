---
created: 2026-05-29
modified: 2026-05-29
reviewed: 2026-05-29
name: odiff-image-diffing
description: "odiff pixel-by-pixel image diffing. Use when comparing screenshots, detecting visual regressions, diffing before/after PNGs, asserting golden images."
user-invocable: false
allowed-tools: Bash(odiff *), Read, Glob, TodoWrite
model: sonnet
---

# odiff Image Diffing

[odiff](https://github.com/dmtrKovalenko/odiff) is a native, SIMD-accelerated, pixel-by-pixel image comparator. It is the fastest popular image-diff tool in its class (~10-100x faster than `pixelmatch` / `resemble.js`), supports PNG/JPEG/WebP/TIFF/BMP, writes a diff artifact to disk, and exits with structured codes that make it CI-friendly.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|----------------------------------|
| Comparing two PNG/JPEG screenshots on disk | Asserting Playwright snapshots in a test suite (use playwright-testing) |
| Detecting visual regressions between before/after renders | Configuring a Playwright snapshot workflow from scratch (use configure-ux-testing) |
| Diffing rendered output against a golden file | Transforming, resizing, or converting images (use imagemagick-conversion) |
| Validating that a CSS or template change is visually neutral | Generating a new image from a prompt (use generate-image) |
| Failing CI on pixel drift with a machine-readable exit code | Producing the screenshot itself (use playwright-cli) |

## Installation

```bash
# Recommended: npm package ships the native binary
npm install -g odiff-bin

# Project-local
npm install --save-dev odiff-bin

# Verify
odiff --version
```

The npm package is `odiff-bin`; the installed command is `odiff`. Native binaries are also available from [GitHub Releases](https://github.com/dmtrKovalenko/odiff/releases) for sandboxes without npm registry access.

## Core Usage

```bash
odiff <base_image> <comp_image> [diff_output] [options]
```

- `base_image` and `comp_image` are the two images to compare. Any of PNG, JPEG, WebP, TIFF, BMP. Cross-format compares are fine.
- `diff_output` is an optional PNG path. When supplied, odiff writes a visual diff highlighting the changed pixels in `#cd2cc9` magenta.
- Exit code carries the verdict — read it instead of parsing prose stdout.

```bash
odiff before.png after.png diff.png
```

## Exit Codes

odiff is exit-code-first by design. Branch on the exit code, not on stdout text:

| Code | Meaning |
|------|---------|
| `0` | Images match within threshold |
| `21` | Layout difference (only when `--fail-on-layout` is set; otherwise treated as pixel diff) |
| `22` | Pixel differences found |
| `1`  | Usage / file error (e.g. base image could not be loaded) |

CI pattern:

```bash
if odiff before.png after.png diff.png --parsable-stdout; then
  echo "visual match"
else
  code=$?
  echo "visual drift (exit $code) — see diff.png"
  exit $code
fi
```

## Machine-Readable Output

`--parsable-stdout` swaps the human report for a single line that's trivial to parse:

| Result | stdout |
|--------|--------|
| Match | `0` |
| Pixel diff | `<changed_pixels>;<percentage>` (e.g. `1681;16.81`) |
| Layout diff (with `--fail-on-layout`) | `layout` |

Pair with the exit code for a complete verdict; the line itself is the metric to log or post as a CI annotation.

## Composition Recipes

### 1. Before/After diff with `playwright-cli`

`playwright-cli` saves PNG screenshots to `.playwright-cli/`. Pair the two ends of a change with odiff to confirm the visual delta is what you expected.

```bash
# Baseline
playwright-cli goto https://app.example.com/dashboard
playwright-cli screenshot --filename=baseline.png

# Make the code change, then re-screenshot
playwright-cli goto https://app.example.com/dashboard
playwright-cli screenshot --filename=current.png

# Diff — exit 0 = visually unchanged, exit 22 = drift
odiff .playwright-cli/baseline.png .playwright-cli/current.png \
  .playwright-cli/diff.png --parsable-stdout --antialiasing
```

`--antialiasing` ignores antialiased pixels, which suppresses noise from font-rendering jitter across runs.

### 2. Batch directory compare

For a baseline directory (golden files) and a current directory (fresh renders), iterate matched filenames:

```bash
baseline_dir=tests/__snapshots__
current_dir=tests/__current__
mkdir -p tests/__diff__

fail=0
for img in "$baseline_dir"/*.png; do
  name=$(basename "$img")
  current="$current_dir/$name"
  diff="tests/__diff__/$name"

  if odiff "$img" "$current" "$diff" --parsable-stdout --antialiasing; then
    echo "OK    $name"
  else
    echo "DRIFT $name"
    fail=1
  fi
done

exit $fail
```

### 3. CI exit-code pattern with layout protection

Treat layout changes as a distinct failure mode from pixel drift — a layout shift usually wants human attention, while a pixel diff may be tolerable under a small threshold.

```bash
odiff before.png after.png diff.png \
  --fail-on-layout \
  --threshold 0.05 \
  --antialiasing \
  --parsable-stdout
case $? in
  0)  echo "::notice::visual unchanged" ;;
  21) echo "::error::layout shifted — review diff.png"; exit 1 ;;
  22) echo "::warning::pixel drift — review diff.png"; exit 1 ;;
  *)  echo "::error::odiff failure"; exit 1 ;;
esac
```

## Advanced Options

| Flag | When to use |
|------|-------------|
| `--threshold <0.0-1.0>` | Raise from default `0.1` to be stricter; lower to tolerate more colour noise |
| `--antialiasing` (`--aa`) | Suppress antialiased-pixel noise — recommended for any rendered-text comparison |
| `--fail-on-layout` | Exit `21` (distinct from pixel diff `22`) when dimensions differ |
| `--diff-mask` | Diff output is just the changed pixels over a transparent background (compositing-friendly) |
| `--diff-overlay` | White-shaded overlay on the unchanged regions — easier human review |
| `--diff-color <hex>` | Override the default `#cd2cc9` highlight colour |
| `-i, --ignore <regions>` | Skip rectangular regions: `x1:y1-x2:y2,x3:y3-x4:y4` — useful for timestamps, ads, avatars |
| `--reduce-ram-usage` | Trade speed for memory on very large images |
| `--enable-asm` | AVX-512 fast path on x86_64 CPUs that support it |
| `--server` | Long-running daemon reading JSON jobs from stdin — for batch processors |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick pass/fail | `odiff a.png b.png --parsable-stdout` |
| Pass/fail with diff artifact | `odiff a.png b.png diff.png --parsable-stdout` |
| Suppress font-rendering noise | `odiff a.png b.png diff.png --aa --parsable-stdout` |
| Treat layout shift as distinct failure | `odiff a.png b.png diff.png --fail-on-layout --parsable-stdout` |
| Ignore dynamic regions | `odiff a.png b.png diff.png -i 0:0-200:40 --parsable-stdout` |
| Strict threshold for golden files | `odiff a.png b.png diff.png -t 0.02 --aa --parsable-stdout` |
| Composite-friendly diff | `odiff a.png b.png diff.png --diff-mask --parsable-stdout` |

## Quick Reference

| Flag | Default | Description |
|------|---------|-------------|
| `-t`, `--threshold <value>` | `0.1` | Per-pixel colour-difference tolerance (0.0–1.0) |
| `--aa`, `--antialiasing` | off | Ignore antialiased pixels |
| `--fail-on-layout` | off | Exit `21` when dimensions differ |
| `--parsable-stdout` | off | Emit `0` / `<pixels>;<pct>` / `layout` |
| `--diff-color <hex>` | `#cd2cc9` | Highlight colour in diff PNG |
| `--diff-mask` | off | Diff = only changed pixels on transparent bg |
| `--diff-overlay [value?]` | off | White shaded overlay on unchanged areas |
| `--output-diff-lines` | off | Print line numbers of differences |
| `-i`, `--ignore <regions>` | none | Rect list: `x1:y1-x2:y2,...` |
| `--reduce-ram-usage` | off | Slower, lower-memory mode |
| `--enable-asm` | off | AVX-512 path (x86_64) |
| `--server` | off | JSON-over-stdin server mode |

## See Also

- **playwright-cli** — produces the `.playwright-cli/*.png` screenshots that odiff consumes
- **playwright-testing** — Playwright's own `toHaveScreenshot()` snapshot assertions for in-test diffing
- **imagemagick-conversion** — pre-process images (resize, normalize format) before diffing
- **configure-ux-testing** — set up a full visual-regression pipeline with snapshot directories
- Official site: https://odiff.opa.dev
- Repository: https://github.com/dmtrKovalenko/odiff
- npm: https://www.npmjs.com/package/odiff-bin

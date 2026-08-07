# comfyui-node-scaffold — Registry Readiness

The path from a CI-green pack to a published, registry-ready one: the artwork
gate, the finishing-pass audit that grades it, and the registry facts that
decide what the published tarball may contain. Entry point:
[`../SKILL.md`](../SKILL.md) § "After scaffolding".

## The placeholder glyph is gated, not just commented

`icon.svg`/`banner.svg` ship a letter-initial glyph so they're valid from commit
one, but `pyproject.toml` already points `Icon`/`Banner` at the PNGs, so a
forgotten placeholder publishes a generic letter tile to registry.comfy.org.
**`just assets` refuses to rasterize** while the `PLACEHOLDER-GLYPH` marker
comment is present — draw the bespoke pictogram (family spec: `#ffb02e` line-art
on the dark tile), delete the marker, then run it.

## The finishing pass

A CI-green pack is not yet a registry-ready, fleet-consistent one. The scaffold
**emits** the deterministic finishing-pass pieces and **audits + warns** (at the
end of every run) for the two it can't do from stdlib alone (issue #1877):

| Piece | Severity if absent | Follow-up |
|-------|--------------------|-----------|
| Registry icon | **ERROR** — `Icon` already points at `…/main/icon.png`, so a missing PNG publishes a 404 | `just assets` (needs `rsvg-convert`) → commit `icon.png` |
| Registry banner | **ERROR** — same, for `Banner` | `just assets` → commit `banner.png` |
| Bespoke artwork | **ERROR** while `PLACEHOLDER-GLYPH` survives | draw the pictogram, delete the marker, re-run `just assets` |
| Renovate (not dependabot) + registry workflows | WARN | emitted by the scaffold; a gap means drift |
| Screenshot pipeline / README prose | WARN — pack-specific, deferrable | run `comfyui-screenshot-pipeline`, then `just screenshots` |

**Ask the generator; do not read this table for status.** The audit is
re-runnable against any existing pack, and it is the authority:

```sh
python3 ${CLAUDE_SKILL_DIR}/scaffold.py --verify path/to/comfyui-<name>
```

It emits `ICON_PNG=`, `PLACEHOLDER_GLYPH=`, `SCREENSHOTS=`, a `SIBLING_GAP_COUNT=`
diff against a mature sibling, and a `STATUS=OK|WARN|ERROR` verdict — exit 1 on
ERROR. Run it before opening the registry PR, and any time you inherit a pack
someone else scaffolded.

Two gates back it up, because a printed note is not a gate: `just assets` refuses
to rasterize placeholder art, and the pack's own
`tests/test_publish_hygiene.py::test_registry_display_assets_present` fails CI
while the PNGs `[tool.comfy]` names are missing or still placeholders. That test
is why this can no longer go unnoticed — `comfyui-touch-manager` published with
`Icon = ""` for weeks with CI green, and `comfyui-output-swap` sat 31 hours after
its own audit flagged the rasterize, both caught only when a human looked.

## Registry publishing

The generated `publish.yml` builds `web/dist/` then publishes via
`Comfy-Org/publish-node-action`. Three registry facts worth knowing:

- **Active vs Flagged is a pointer.** The registry serves one *Active* version
  per node; publishing moves that pointer to the new version. A version that gets
  **Flagged** (review) stays in the registry but is no longer the Active target —
  installs fall back to the last Active version. Publishing a fresh good version
  re-points Active forward.
- **Flags fire on ANY finding, even info severity.** Full reasons are on the
  public API via `GET /nodes/<id>/versions?include_status_reason=true`
  (notifications otherwise post to the Comfy Org Discord
  `#security-review-council`). Known classes: `python_network_operations`
  (yara) on any urllib/requests use in shipped `.py`, and `vendored_unknown`
  (provenance_scan) on **any bundler-built dist file** — even pure own-source
  bundles. The scaffold's `tests/test_publish_hygiene.py` + `.comfyignore` +
  `--banner` attribution keep the scan surface minimal, and its
  `registry-health.yml` writes the findings into the tracking issue — see the
  `comfy-registry-lifecycle` skill's security-scan section.
- **`.comfyignore` trims the tarball.** comfy-cli builds the published `node.zip`
  as *git-tracked files − `.comfyignore` matches + `[tool.comfy] includes`*. The
  scaffold ships a default `.comfyignore` so only the runtime backend, the built
  `web/dist`, and metadata ship — CI, tests, docs, build inputs, and the TS source
  stay out. Tarball trimming requires **comfy-cli >= 1.10.3**.

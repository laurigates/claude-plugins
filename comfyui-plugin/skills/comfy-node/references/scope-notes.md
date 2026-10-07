# comfy-node - Scope Notes

What the orchestrator and the scaffold deliberately do and do not do.

## Notes

- The orchestrator never runs `tofu apply` — all applies go through the gitops
  repo's `tofu-apply.yml` GitHub Actions workflow, triggered by publishing the
  release-please release (see `gitops/CLAUDE.md`). Local gitops work is
  `plan`/`validate` only.
- The scaffold now emits the registry finishing-pass pieces (icon/banner SVGs +
  wiring, renovate + registry-health + clear-autorelease workflows) and audits
  for the rest; `just assets` (rsvg-convert) produces the served PNGs. See the
  finishing-pass note in Phase 2 (issue #1877).
- Screenshots pipeline + `docs/blueprint/` PRD/ADR set are not scaffolded; add
  them later from a reference pack (the `comfyui-screenshot-pipeline` skill) if
  the pack warrants them.

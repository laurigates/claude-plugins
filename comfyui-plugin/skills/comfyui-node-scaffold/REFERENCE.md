# comfyui-node-scaffold — Reference Index

Supporting material for [`comfyui-node-scaffold`](SKILL.md), split across
`references/` so a run loads only the material its path needs. The operational
workflow lives in `SKILL.md`; nothing below is loaded unless you follow one of
these links.

| Path you are on | File | Carries |
|---|---|---|
| Picking between the four variants, or deciding whether to pass `--widgets` | [`references/variants.md`](references/variants.md) | What the `--widgets` switch changes about the emitted modal; the `gesture` canvas-pointer skeleton; the `shim` CSS-registry skeleton |
| Typing the generator command line | [`references/invocation.md`](references/invocation.md) | The `backend` / standalone-modal / `gesture` / `shim` recipes, the full flag list, the ≤46-char banner-tagline rule |
| Implementing inside the generated pack | [`references/implementing-the-pack.md`](references/implementing-the-pack.md) | What you get (emitted file inventory), the hard rules baked into the output, the notes & deferrals (what is *not* generated) |
| Getting a scaffolded pack registry-ready and published | [`references/registry-readiness.md`](references/registry-readiness.md) | The `PLACEHOLDER-GLYPH` artwork gate, the finishing-pass table + `--verify` audit, the three registry-publishing facts |
| Maintaining the template itself, or auditing the fleet | [`references/template-upkeep.md`](references/template-upkeep.md) | The two pins the generator owns (`uv.lock` updater, `MODAL_KIT_VERSION`); the `check-fleet-drift.py` sweep and `fleet-policy.toml` authority model |

This file is an index only. Add new reference material to the file whose path
needs it — or a new `references/*.md` plus a row here — rather than growing this
page (`.claude/rules/context-engineering.md` § "Split long skills across files").

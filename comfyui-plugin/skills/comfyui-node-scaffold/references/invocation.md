# comfyui-node-scaffold — Invocation Recipes and Flags

Every generator invocation beyond the frontend-only example in
[`../SKILL.md`](../SKILL.md) § "How to run", the full flag list, and the tagline
rule that decides what the banner renders.

## Invocation recipes

Pack with a Python backend:

```sh
python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name comfyui-model-gallery --display "Model Gallery" --desc "Touch-first card-grid picker for the folder-backed model combos." --variant backend --widgets lora_name,ckpt_name,vae_name,control_net_name
```

Standalone-modal pack (manager/dashboard launched from a toolbar button — modal
variant, **no** `--widgets`):

```sh
python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name comfyui-touch-manager --display "Touch Manager" --desc "Touch-first node/extension manager modal opened from the toolbar." --variant backend
```

Canvas-gesture pack (resize/move/region — no widget, no modal, no kit):

```sh
python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name comfyui-touch-resize --display "Touch Resize" --desc "Selection-gated corner grab-handle resize for ComfyUI nodes and groups on touch." --variant gesture
```

CSS/shim pack (scoped `<style>` injection + commands — no modal, no widget, no kit):

```sh
python3 ${CLAUDE_SKILL_DIR}/scaffold.py --name comfyui-touch-shim --display "Touch Shim" --desc "Stopgap mobile CSS shims for upstream ComfyUI frontend bugs." --variant shim
```

## Flag reference

Flags: `--name` (repo + served URL segment), `--display` (Comfy DisplayName),
`--desc`, `--subfamily` (`touch`|`info`, accent palette), `--tagline` (banner subtitle, ≤46 chars — see below), `--variant
{frontend,backend,gesture,shim}`, `--widgets` (CSV → the TS stub's
`TARGET_WIDGETS`; on a modal variant, **omitting** it emits the standalone-modal
skeleton instead of the widget-intercept one; ignored by `gesture` and `shim`),
`--publisher` (default `laurigates`), `--dir` (parent dir, default cwd).

It refuses to overwrite an existing directory.

## The banner tagline is not the description

`banner.svg` renders its subtitle at 44px starting at x=340 on a 1344px canvas,
so anything past **~46 characters runs off the edge** — invisible until someone
rasterizes the PNG and looks at it. Omitting `--tagline` derives one from
`--desc` (first clause, trimmed to a word boundary) and warns when it had to
truncate. Pass `--tagline` for anything better than a machine truncation:

```sh
--desc "Drag one output onto another to take over its downstream links — reroute a connection's source." --tagline "Move a connection's source in one drag"
```

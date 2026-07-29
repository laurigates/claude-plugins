# {{ display_name }} (`{{ module_id }}`)

{% if variant == "app" -%}
A FoundryVTT v13 module with an ApplicationV2 UI panel, built with Vite + TypeScript. The window opens from a settings-menu button registered in `init`. See ADR-0001 for the toolchain.
{%- elsif variant == "libwrapper" -%}
A FoundryVTT v13 module that patches a core method, built with Vite + TypeScript. Patches go through libWrapper when active, with a manual monkey-patch fallback. See ADR-0001 for the toolchain.
{%- else -%}
A FoundryVTT v13 module (settings + lifecycle hooks), built with Vite + TypeScript. See ADR-0001 for the toolchain.
{%- endif %}

## Layout

| Path | Role |
|------|------|
| `module.json` | The manifest. `id` = `{{ module_id }}` and MUST match the install folder + zip name. release-please bumps `$.version` in lockstep with `package.json`. |
| `src/module.ts` | ESM entry (`esmodules`). Registers hooks; built to `dist/{{ module_id }}.mjs` by Vite. |
| `src/settings.ts` | `game.settings` registration (called from `init`). |
| `src/constants.ts` | `MODULE_ID` / `MODULE_TITLE` — the single source for the id. |
| `src/foundry-shims.d.ts` | Loose ambient types for the Foundry globals. Keep `tsc` green; verify the real API before trusting a shape. |
{%- if variant == "app" %}
| `src/app.ts` | The `{{ module_id | pascal_case }}App` ApplicationV2 window. |
| `templates/app.hbs` | Its Handlebars template (auto-loaded via `static PARTS`). |
{%- elsif variant == "libwrapper" %}
| `src/patches.ts` | libWrapper-guarded method patch + a manual fallback. |
{%- endif %}
| `lang/en.json` | Localization. Keys are namespaced under `{{ module_id }}.`. |
| `styles/{{ module_id }}.css` | Styles, every selector scoped under `.{{ module_id }}*`. |

## Rules of the road

- **Target the harness-pinned Foundry version.** The local `foundryvtt-harness`
  pins a specific build; module behavior is version-specific. `module.json`
  `compatibility.{minimum,verified}` is the manifest source of truth — keep it in
  sync with what you actually test against, and bump the pin and the code
  together.
- **Verify the Foundry API before patching.** `game.*`, document classes, hooks,
  and the `foundry.applications.*` namespaces change across major versions.
  Check <https://foundryvtt.com/api/> or the live console — not memory.
- **ESM only, paths must byte-match the manifest.** `esmodules` references
  `{{ module_id }}.mjs`; if the Vite output name drifts, the module silently fails
  to load.
- **Do not commit `dist/`.** It is a build artifact (git-ignored); CI builds it
  for releases.
- **`just check` is the gate.** Typecheck + build + lint + test must pass before
  pushing.

## Hooks

`init` registers settings (and patches); {% if variant == "libwrapper" %}`init` also calls `registerPatches()` (libWrapper registration must happen at/after `init`); {% endif %}`ready` runs once
`game.*` is populated. Settings are only readable from `setup` onward.

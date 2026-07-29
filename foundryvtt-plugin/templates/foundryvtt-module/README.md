# {{ display_name }}

{{ description }}

A [FoundryVTT](https://foundryvtt.com/) module (v{{ fvtt_min }}+; verified on
v{{ fvtt_verified }}), built with Vite + TypeScript.

## Install

In Foundry, **Add-on Modules → Install Module → Manifest URL**, paste:

```
https://github.com/{{ github_owner }}/{{ project-name }}/releases/latest/download/module.json
```

## Development

Requires [bun](https://bun.sh/). The local [foundryvtt-harness](https://github.com/{{ github_owner }}/foundryvtt-harness)
(or any local Foundry on `:30000`) is the run/test environment.

```
bun install
just check        # typecheck + build + lint + test (the CI gate)
just dev          # Vite dev server with HMR, proxying to Foundry on :30000
```

To run inside Foundry, build and symlink `dist/` into your Foundry data:

```
just build
ln -s "$(pwd)/dist" "<FoundryData>/Data/modules/{{ module_id }}"
```

(`dist/` is git-ignored and rebuilt; the manifest, lang, styles{% if variant == "app" %}, templates{% endif %} are
copied into it by the build.)

## Releasing

Conventional-commit `feat:` / `fix:` commits drive
[release-please](https://github.com/googleapis/release-please): merging its
release PR tags a version, bumps `package.json` **and** `module.json`, builds the
module, zips `dist/`, and attaches `{{ module_id }}.zip` + `module.json` to the
GitHub release — which is what the manifest URL above resolves to.

## License

MIT — see [LICENSE](LICENSE).

# Migration Mapping

Used by Step 7 (`--migrate <source>`) to map each source into `mise.toml`.

| Source | Action |
|--------|--------|
| `asdf` | Read `.tool-versions`, map each line to a `[tools]` entry, keep `legacy_version_file = true`, then remove `.tool-versions` once verified. asdf plugin names usually match mise core/aqua names. |
| `nvm` | `.nvmrc` → `node = "<ver>"`. |
| `pyenv` | `.python-version` → `python = "<ver>"` (a list if multiple). |
| `brew` | Move CLI tools (not casks/services/build-deps) from Brewfile to `aqua:`/core backends; leave GUI apps, fonts, daemons, and compilers in Homebrew. |
| `makefile` | Convert each target to a `[tasks.<name>]` with `run`; map prerequisites to `depends`. See REFERENCE.md task grammar. |

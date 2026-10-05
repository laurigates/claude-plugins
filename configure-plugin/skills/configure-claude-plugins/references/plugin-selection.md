# Plugin Selection by Project Type

Used by Step 2 (Select plugins) of `/configure:claude-plugins` when `--plugins` is not specified.

| Project Indicator | Recommended Plugins |
|-------------------|---------------------|
| `package.json` | `git-plugin`, `typescript-plugin`, `testing-plugin`, `code-quality-plugin` |
| `pyproject.toml` / `setup.py` | `git-plugin`, `python-plugin`, `testing-plugin`, `code-quality-plugin` |
| `Cargo.toml` | `git-plugin`, `rust-plugin`, `testing-plugin`, `code-quality-plugin` |
| `Dockerfile` | Above + `container-plugin` |
| `.github/workflows/` | Above + `github-actions-plugin` |
| `idf_component.yml` / `sdkconfig` | `git-plugin`, `code-quality-plugin`, `testing-plugin`, `container-plugin` |
| ESPHome yaml | `git-plugin`, `python-plugin`, `code-quality-plugin` |
| `CMakeLists.txt` (without Dockerfile / ESP-IDF / ESPHome indicators) | `git-plugin`, `code-quality-plugin`, `testing-plugin`, `tools-plugin` + `clangd@claude-plugins-official` (LSP) |
| Default (any) | `git-plugin`, `code-quality-plugin`, `testing-plugin`, `tools-plugin` |

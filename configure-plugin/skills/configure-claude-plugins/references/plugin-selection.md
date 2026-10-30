# Plugin Selection by Project Type

Used by Step 2 (Select plugins) of `/configure:claude-plugins` when `--plugins` is not specified.

1. **Stack plugins come from the policy.** Each entry in the `stacks` array of [`configure-plugin/policy/repo-baseline.json`](../../../policy/repo-baseline.json) whose `detect` matches the repo root adds its `plugins`, including any official LSP plugin it names. Detection rules and the never-flip-`false` rule: [settings-json.md](settings-json.md#applying-the-repo-baseline-policy).
2. **Add the workflow plugins by indicator:**

| Project Indicator | Recommended Plugins |
|-------------------|---------------------|
| Any policy stack matched in step 1 | `git-plugin`, `testing-plugin`, `code-quality-plugin` |
| `.github/workflows/` | Above + `github-actions-plugin` |
| `idf_component.yml` / `sdkconfig` | `git-plugin`, `code-quality-plugin`, `testing-plugin`, `container-plugin` |
| ESPHome yaml | `git-plugin`, `python-plugin`, `code-quality-plugin` |
| `CMakeLists.txt` (without Dockerfile / ESP-IDF / ESPHome indicators) | `git-plugin`, `code-quality-plugin`, `testing-plugin`, `tools-plugin` + `clangd-lsp@claude-plugins-official` (LSP) |
| Default (none of the above) | `git-plugin`, `code-quality-plugin`, `testing-plugin`, `tools-plugin` |

# Exhaustive enabledPlugins Enumeration

Used by Step 3 of `/configure:claude-plugins` when `--exhaustive` is set (or the user asks to "pin plugins" / "override global plugins").

## Exhaustive enumeration (when `--exhaustive` is set)

Build the full `enabledPlugins` map by reading every plugin name from the two relevant marketplaces, then writing each one with an explicit `true`/`false`. Every marketplace plugin is named, so the project's map **fully overrides** the user-global enable state — a plugin the user toggled on globally is forced off here unless it is explicitly `true`. This skill only ever writes `<cwd>/.claude/settings.json`; it never modifies `~/.claude/settings.json` (user-global toggles stay as the user set them).

**Deriving each plugin's boolean.** Start from the Step 2 recommended set (those become `true`), then refine from repo context using the signals in this section's table. A plugin a value already exists for in the project's current `enabledPlugins` **wins over the suggestion** — only fill in *missing* entries from this logic, so a deliberate prior choice is never silently flipped.

| Signal in repo | Suggest enabling |
|---|---|
| `pyproject.toml`, `requirements.txt`, `*.py` | `python-plugin` |
| `Cargo.toml`, `*.rs` | `rust-plugin` (and `bevy-plugin` if Bevy is in deps) |
| `go.mod`, `*.go` | `go-plugin` (if present in the marketplace) |
| `package.json`, `*.ts`, `*.tsx` | `typescript-plugin` |
| `*.tf`, `terraform/` | `terraform-plugin` |
| `Dockerfile`, `compose.yaml` | `container-plugin` |
| `Chart.yaml`, `kustomization.yaml`, `k8s/` | `kubernetes-plugin` / `helm-plugin` |
| `flake.nix`, `default.nix` | `nix-plugin` |
| `langchain` in deps | `langchain-plugin` |
| `home-assistant`/`hass` configs | `home-assistant-plugin` |
| `.github/workflows/` | `github-actions-plugin` |
| macOS host (`uname -s` = Darwin) | `macos-plugin` |
| Markdown-heavy `docs/` or `blog/` | `documentation-plugin`, `blog-plugin` |

Always-useful baseline (enable unless the user says otherwise): `agents-plugin`, `agent-patterns-plugin`, `blueprint-plugin`, `code-quality-plugin`, `communication-plugin`, `configure-plugin`, `git-plugin`, `health-plugin`, `prose-plugin`, `taskwarrior-plugin`, `testing-plugin`, `tools-plugin`, `workflow-orchestration-plugin`. Anything else not matched defaults to `false`.

1. **Read the laurigates marketplace** in priority order:
   - If a local clone is present (e.g. inside this repo or a sibling checkout), parse `.claude-plugin/marketplace.json`:
     ```bash
     jq -r '.plugins[].name' .claude-plugin/marketplace.json
     ```
   - Otherwise fetch over the GitHub API:
     ```bash
     gh api repos/laurigates/claude-plugins/contents/.claude-plugin/marketplace.json --jq '.content' | base64 -d | jq -r '.plugins[].name'
     ```
   - Suffix each name with `@claude-plugins` to match the existing stanza format.

2. **Add the official LSP plugins** (`@claude-plugins-official`). The currently shipped names are: `pyright`, `typescript-language-server`, `rust-analyzer`, `gopls`, `swift-language-server`, `clangd`. Mark the LSP that matches the detected stack as `true`, the rest as `false`. If none match (no detectable stack), leave them all `false`.

3. **Compose the map** with all entries, alphabetised within each marketplace block. Suffix `@claude-plugins` matches the `extraKnownMarketplaces` *key* (not the marketplace `name` used in workflows):

```json
{
  "enabledPlugins": {
    "accessibility-plugin@claude-plugins": false,
    "agent-patterns-plugin@claude-plugins": false,
    "agents-plugin@claude-plugins": false,
    "...": "...",
    "code-quality-plugin@claude-plugins": true,
    "configure-plugin@claude-plugins": true,
    "git-plugin@claude-plugins": true,
    "health-plugin@claude-plugins": true,
    "hooks-plugin@claude-plugins": true,
    "testing-plugin@claude-plugins": true,
    "typescript-plugin@claude-plugins": true,
    "...": "...",

    "clangd@claude-plugins-official": false,
    "gopls@claude-plugins-official": false,
    "pyright@claude-plugins-official": false,
    "rust-analyzer@claude-plugins-official": false,
    "swift-language-server@claude-plugins-official": false,
    "typescript-language-server@claude-plugins-official": true
  }
}
```

4. **Drop unknown global entries.** If the project's existing `enabledPlugins` (or a merged-in copy of the user's global file) contains plugin names that are not in either marketplace listing, surface them in the report and ask whether to keep them. They may belong to a third marketplace the user has enrolled. Do not delete them silently — stale entries are harmless and the user may have notes about them.

5. **Show the diff before writing.** Exhaustive mode rewrites the whole `enabledPlugins` map, so present the proposal before committing it. Group it as:
   - **Already correct** — count only, do not list each one.
   - **Will add** — new key → `true`/`false`, with a one-line reason for each `true`.
   - **Will change** — existing key → flipped value, with the reason.

   Render compact (a small markdown table or a `+`/`-` list). **Highlight any currently-`true` entry the proposal would turn off** — that is where users most often disagree. Then confirm once (accept "yes"/"go"/"apply", or let the user veto specific plugins and re-render). Skip the prompt under `--check-only` (report the diff only) and under `--fix` when the user already opted into non-interactive application.

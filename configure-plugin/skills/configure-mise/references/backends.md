# Backend Reference

Used by Step 3 (Build the `[tools]` block) when picking a backend per tool.

| Tool kind | Backend | Syntax | Why |
|-----------|---------|--------|-----|
| Language runtime | core | `python = ["3.12","3.13"]`, `node = "lts"`, `go = "1.23"`, `rust = "latest"` | Native version switching, the reason mise exists |
| Python CLI tool | `pipx:` | `"pipx:ruff" = "latest"` | Routed through `uvx` (fast); set `pipx.uvx = true` |
| Standalone CLI binary | `aqua:` | `"aqua:BurntSushi/ripgrep" = "latest"` | Checksums + SLSA provenance + Cosign — the secure default |
| Node global | `npm:` | `"npm:typescript-language-server" = "latest"` | When no aqua entry exists |
| Rust tool (no aqua) | `cargo:` | `"cargo:tokei" = "latest"` | Builds from source; prefer aqua if available |
| Go tool (no aqua) | `go:` | `"go:golang.org/x/tools/gopls" = "latest"` | Installs via `go install` |
| GitHub release (no aqua) | `github:` | `"github:starship/starship" = "latest"` | Direct release-asset fetch |

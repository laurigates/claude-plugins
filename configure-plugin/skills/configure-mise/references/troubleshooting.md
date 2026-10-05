# Troubleshooting

Used by Step 6 (Apply) and Step 5 (Audit) when mise, trust, a backend, or a tool install fails.

- **mise not installed**: Offer the install one-liner (`curl https://mise.run | sh`) or note it is itself a Homebrew bootstrap tool; do not block the audit.
- **Untrusted config**: mise refuses to load an untrusted file — run `mise trust` after writing.
- **`pipx:` tool fails to resolve**: ensure `uv` is a mise-managed tool and `pipx.uvx = true` is set (`jdx/mise#7477`).
- **aqua package not found**: the `org/repo` name must match an aqua-registry entry; fall back to `github:`/`cargo:`/`go:` or core.
- **Tool "keeps coming back" after removal**: stale per-node-version copies + `~/.default-npm-packages` re-seeding — sweep procedure in [REFERENCE.md § Stale tool copies](../REFERENCE.md#stale-tool-copies-a-tool-keeps-coming-back).
- **node ≥26 on minimal Linux**: prebuilt binaries link `libatomic.so.1`; gate `node` to platforms that have it (chezmoi-style `os` guard) or pin an older line.

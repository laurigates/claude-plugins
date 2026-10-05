# Install Script Reference

Used by Step 3 (build tool inventory) and Step 4 (create or update `scripts/install_pkgs.sh`).

## Tool inventory (Step 3)

| Tool | Install method | Version source |
|------|---------------|----------------|
| `pre-commit` | `pip install pre-commit` | latest |
| `helm` | Official get-helm-3 script from `raw.githubusercontent.com` | latest stable |
| `terraform` | Binary from `releases.hashicorp.com` (`.zip`) | Pin to `.pre-commit-config.yaml` rev or latest |
| `tflint` | GitHub release binary (`.zip`) | Pin to `.pre-commit-config.yaml` rev |
| `actionlint` | GitHub release binary (`.tar.gz`) | Pin to `.pre-commit-config.yaml` rev |
| `helm-docs` | GitHub release binary (`.tar.gz`) | Pin to `.pre-commit-config.yaml` rev |
| `gitleaks` | GitHub release binary (`.tar.gz`) | Pin to `.pre-commit-config.yaml` rev |
| `just` | GitHub release binary (`.tar.gz`) | latest stable |

All download sources are compatible with the "Limited" network allowlist (github.com, releases.hashicorp.com, raw.githubusercontent.com, pypi.org).

**Keep the pins fresh, not hand-maintained.** Annotate each `<TOOL>_VERSION="x.y.z"` line with a `# renovate: datasource=... depName=...` comment and add a matching `customManager` to `renovate.json` so the pins are auto-updated rather than rotting (see `.claude/rules/version-pinning.md`). Where a tool's version is also pinned in `.pre-commit-config.yaml` (e.g. `gitleaks`), enable Renovate's `pre-commit` manager and group the dep so both bump in lockstep.

## Required script structure (Step 4)

Create `scripts/install_pkgs.sh` with:

1. **Remote guard** — exit immediately if not in a remote session:
   ```bash
   if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
     exit 0
   fi
   ```

2. **Idempotency guard** per tool — use `command -v <tool>` before downloading:
   ```bash
   if ! command -v helm >/dev/null 2>&1; then
     # install helm
   fi
   ```

3. **Install to `~/.local/bin`** — writable without sudo regardless of whether the session runs as root. Ensure this directory is on the PATH that *agent subshells* inherit: add it to a `path-bootstrap.sh` SessionStart hook (see this repo's `scripts/path-bootstrap.sh`) or append it to `$CLAUDE_ENV_FILE`. A bare `export PATH=...` inside the install script does **not** persist to later tool calls (see `.claude/rules/sandbox-guidance.md`).

4. **Temp directory cleanup** — use a temp dir per download, remove it after:
   ```bash
   tmp_dir=$(mktemp -d)
   # ... download and extract ...
   rm -rf "$tmp_dir"
   ```

5. **`unzip` bootstrap** — terraform and tflint ship as `.zip`; install `unzip` via apt if absent.

6. One install block per tool in this order: `pre-commit`, `helm`, `terraform`, `tflint`, `actionlint`, `helm-docs`, `gitleaks`, `just`.

Make the script executable: `chmod +x scripts/install_pkgs.sh`

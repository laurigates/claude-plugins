# Drift Audit Reference

Used by Step 2b (detect spec drift in an already-onboarded repo) and Step 7 (portfolio sweep after a spec change).

## Drift signals (Step 2b)

| Spec item | Drift signal to check |
|-----------|----------------------|
| Renovate-managed pins | Each `<TOOL>_VERSION="x.y.z"` line carries a `# renovate: datasource=... depName=...` annotation (Step 3). A bare pin is DRIFT. |
| Pinned versions current | Each pinned version matches the Step 3 reference. A pin behind reference (e.g. `gitleaks 8.30.0` vs `8.30.1`, `just 1.40.0` vs `1.52.0`) is DRIFT. |
| `scripts/path-bootstrap.sh` wired first | `path-bootstrap.sh` exists **and** runs as the first `SessionStart` hook before `install_pkgs.sh` (Step 5). Missing or out-of-order is DRIFT. |
| Allowlist-safe downloads | No runtime `api.github.com/.../releases/latest` lookups — `api.github.com` is outside the web "Limited" allowlist and breaks the install. A `latest` lookup is DRIFT; replace with a pinned `github.com/.../releases/download/<tag>` URL. |
| Remote + idempotency guards | The `CLAUDE_CODE_REMOTE` guard and per-tool `command -v` guards are present (Step 4). |

Report drift as a positive signal:

| Spec item | Status |
|-----------|--------|
| Renovate pin annotations | PRESENT / DRIFT / ABSENT |
| Pinned versions vs reference | CURRENT / STALE (list each stale tool) |
| `path-bootstrap.sh` wired first | PRESENT / DRIFT / ABSENT |
| Allowlist-safe downloads | OK / USES api.github.com |

## Portfolio sweep (Step 7)

When the canonical spec itself changes (new pinned tool, a wired-first
`path-bootstrap.sh`, a download-source fix), every previously-onboarded repo
silently falls out of spec — `install_pkgs.sh` still "exists", so nothing flags
the drift (issue #1670). Make drift a positive signal: re-audit the whole
portfolio rather than waiting for a manual cross-repo check.

Run `/configure:web-session --check-only` in each repo that already has
`scripts/install_pkgs.sh` and collect the Step 2b drift reports. A thin sweep
helper over the onboarded repos turns the silent non-event into an explicit
PRESENT/DRIFT/ABSENT list — find the onboarded repos, then re-audit each:

```bash
# Discover onboarded repos under a portfolio root (each has scripts/install_pkgs.sh)
find . -maxdepth 3 -path '*/scripts/install_pkgs.sh' -print | while read -r script; do
  repo_dir=$(dirname "$(dirname "$script")")
  echo "=== ${repo_dir} ==="
  # Re-audit against the current spec (Step 2b drift checks)
  grep -q 'renovate:' "$script" && echo "renovate-pins: PRESENT" || echo "renovate-pins: DRIFT"
  find "${repo_dir}/scripts" -maxdepth 1 -name 'path-bootstrap.sh' -print -quit | grep -q . \
    && echo "path-bootstrap: PRESENT" || echo "path-bootstrap: ABSENT"
  grep -q 'api.github.com' "$script" && echo "allowlist: USES api.github.com (DRIFT)" || echo "allowlist: OK"
done
```

For each repo that reports DRIFT/ABSENT, run the full `/configure:web-session`
(no `--check-only`) so Steps 3-5 re-apply the current spec, then open one PR per
repo. Surface the deltas as a table so the sweep result is reviewable at a glance.

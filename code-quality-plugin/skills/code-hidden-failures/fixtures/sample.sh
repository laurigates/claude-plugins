#!/usr/bin/env bash
# Regression fixture for /code:error-swallowing scan-shell.sh.
# Each line is annotated with its expected (severity, rule).

set -euo pipefail

# --- Low: allowlisted frontmatter extraction idiom ----------------------------
extract_status() {
  # Expected: Low | sh-or-true  (allowlisted: function name prefix "extract_")
  head -50 "$1" | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//' || true
}

# Expected: Low | sh-stderr-null  (allowlisted content regex: `command -v`)
command -v jq >/dev/null 2>&1

# --- Medium: generic suppression on recoverable op ---------------------------
# Expected: Medium | sh-or-true
make lint || true

# Expected: Medium | sh-stderr-null
ls /tmp/maybe-missing 2>/dev/null

# Expected: Medium | sh-set-plus-e
set +e

# --- High: suppression around a destructive/required op ----------------------
# Expected: High | sh-or-true  (promoted by `npm publish`)
npm publish --tag latest || true

# Expected: High | sh-both-null  (promoted by `git push`)
git push origin main >/dev/null 2>&1

# Expected: High | sh-or-true  (promoted by `rm -rf`)
rm -rf /var/app/state || true

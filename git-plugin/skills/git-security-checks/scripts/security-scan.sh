#!/usr/bin/env bash
# Security Scan Script
# Runs a comprehensive security scan pipeline in one execution.
# Usage: bash security-scan.sh [--staged-only]
#
# Checks: gitleaks, gitignore patterns, sensitive file detection,
# high-entropy strings in staged files.

set -uo pipefail

STAGED_ONLY=false
[ "${1:-}" = "--staged-only" ] && STAGED_ONLY=true

echo "=== SECURITY SCAN ==="
echo "MODE=$([ "$STAGED_ONLY" = true ] && echo "staged-only" || echo "full")"
echo ""

findings=0

# Which rules a .gitleaks.toml loads: default | extend-path | custom | none.
# gitleaks takes rules only from [[rules]] tables and from [extend]
# (useDefault = true, or path = <another config>), so a file holding just an
# [allowlist] / [[allowlists]] loads ZERO rules. gitleaks auto-discovers that
# file, and the scan below then reports clean whatever the tree holds. Keys are
# matched case-insensitively, as gitleaks' viper loader reads them; multi-line
# string bodies are skipped. configure-plugin's configure-security.sh carries
# the same classifier.
gitleaks_rule_source() {
  awk '
    BEGIN { section = ""; in_ml = 0; dflt = 0; xpath = 0; custom = 0 }
    {
      line = tolower($0)
      quotes = gsub(/\047\047\047|"""/, "&", line)
      if (in_ml) { if (quotes % 2 == 1) in_ml = 0; next }
      if (quotes % 2 == 1) in_ml = 1
      if (line ~ /^[[:space:]]*(#|$)/) next
      if (line ~ /^[[:space:]]*\[\[[[:space:]]*rules[[:space:]]*\]\]/) { custom = 1; section = "rules"; next }
      if (line ~ /^[[:space:]]*\[[[:space:]]*extend[[:space:]]*\]/) { section = "extend"; next }
      if (line ~ /^[[:space:]]*\[/) { section = "other"; next }
      if (section != "extend" && section != "") next
      prefix = (section == "") ? "extend[[:space:]]*\\.[[:space:]]*" : ""
      if (line ~ ("^[[:space:]]*" prefix "usedefault[[:space:]]*=[[:space:]]*true([[:space:]#]|$)")) dflt = 1
      if (line ~ ("^[[:space:]]*" prefix "path[[:space:]]*=[[:space:]]*(\"[^\"]+\"|\047[^\047]+\047)")) xpath = 1
      if (section == "" && line ~ /^[[:space:]]*extend[[:space:]]*=[[:space:]]*\{/) {
        if (line ~ /usedefault[[:space:]]*=[[:space:]]*true/) dflt = 1
        if (line ~ /path[[:space:]]*=[[:space:]]*("[^"]+"|\047[^\047]+\047)/) xpath = 1
      }
    }
    END {
      if (dflt) print "default"
      else if (xpath) print "extend-path"
      else if (custom) print "custom"
      else print "none"
    }
  ' "$1"
}

# Check 1: gitleaks (if available)
echo "--- GITLEAKS ---"
if command -v gitleaks >/dev/null 2>&1; then
  if [ "$STAGED_ONLY" = true ]; then
    scan_output=$(gitleaks protect --staged --no-banner 2>&1)
    scan_exit=$?
  else
    scan_output=$(gitleaks detect --source . --no-banner 2>&1)
    scan_exit=$?
  fi
  gitleaks_rules=""
  [ -f ".gitleaks.toml" ] && gitleaks_rules=$(gitleaks_rule_source ".gitleaks.toml")
  if [ $scan_exit -ne 0 ]; then
    echo "STATUS=secrets_found"
    echo "$scan_output" | head -20
    findings=$((findings + 1))
  elif [ "$gitleaks_rules" = "none" ]; then
    # A clean result from a config with zero rules says nothing about the tree.
    echo "STATUS=inert_config"
    findings=$((findings + 1))
  else
    echo "STATUS=clean"
  fi

  # Check for .gitleaks.toml config
  if [ "$gitleaks_rules" = "none" ]; then
    echo "CONFIG=inert"
    echo "HINT: .gitleaks.toml loads zero rules (no [extend] useDefault = true, no [[rules]]), so the scan checked nothing. Add [extend] useDefault = true above the [allowlist]"
  elif [ -f ".gitleaks.toml" ]; then
    echo "CONFIG=present"
  else
    echo "CONFIG=missing"
    echo "HINT: Create .gitleaks.toml for project-specific allowlists"
  fi
else
  echo "STATUS=not_installed"
  echo "HINT: brew install gitleaks (or go install github.com/gitleaks/gitleaks/v8@latest)"
fi
echo ""

# Check 2: Sensitive file patterns in staged/tracked files
echo "--- SENSITIVE FILES ---"
sensitive_patterns=(
  ".env"
  ".env.local"
  ".env.production"
  "credentials.json"
  "service-account.json"
  "*.pem"
  "*.key"
  "*.p12"
  "*.pfx"
  "id_rsa"
  "id_ed25519"
  ".api_tokens"
  "secrets.yml"
  "secrets.yaml"
  ".gcp-credentials.json"
)

if [ "$STAGED_ONLY" = true ]; then
  file_list=$(git diff --cached --name-only 2>/dev/null)
else
  file_list=$(git ls-files 2>/dev/null)
fi

echo "FOUND:"
for pattern in "${sensitive_patterns[@]}"; do
  matches=$(echo "$file_list" | grep -E "(^|/)${pattern}$" 2>/dev/null || true)
  if [ -n "$matches" ]; then
    while IFS= read -r line; do printf '  - %s\n' "$line"; done <<< "$matches"
    findings=$((findings + 1))
  fi
done
[ $findings -eq 0 ] && echo "  none"
echo ""

# Check 3: Gitignore coverage
echo "--- GITIGNORE COVERAGE ---"
if [ -f ".gitignore" ]; then
  echo "GITIGNORE=present"
  missing_patterns=()
  for pattern in ".env" "*.pem" "*.key" "credentials.json" ".api_tokens"; do
    if ! grep -qF "$pattern" .gitignore 2>/dev/null; then
      missing_patterns+=("$pattern")
    fi
  done
  if [ ${#missing_patterns[@]} -gt 0 ]; then
    echo "MISSING_PATTERNS:"
    printf '  - %s\n' "${missing_patterns[@]}"
    findings=$((findings + 1))
  else
    echo "COVERAGE=good"
  fi
else
  echo "GITIGNORE=missing"
  echo "HINT: Create .gitignore with sensitive file patterns"
  findings=$((findings + 1))
fi
echo ""

# Check 4: High-entropy strings in staged files (simple heuristic)
echo "--- HIGH ENTROPY STRINGS ---"
if [ "$STAGED_ONLY" = true ]; then
  diff_content=$(git diff --cached 2>/dev/null)
else
  diff_content=$(git diff 2>/dev/null)
fi

if [ -n "$diff_content" ]; then
  # Look for common secret patterns in diffs
  suspect_lines=$(echo "$diff_content" | grep -n "^+" | grep -iE "(api[_-]?key|secret|token|password|credential|private[_-]?key)\s*[:=]" 2>/dev/null | grep -v "^+++ " | head -10)
  if [ -n "$suspect_lines" ]; then
    echo "SUSPECT_PATTERNS:"
    echo "$suspect_lines" | sed 's/^/  /' | head -10
    findings=$((findings + 1))
  else
    echo "STATUS=clean"
  fi
else
  echo "STATUS=no_diff"
fi
echo ""

# Check 5: Pre-commit hook status
echo "--- PRE-COMMIT STATUS ---"
if [ -f ".pre-commit-config.yaml" ]; then
  echo "CONFIG=present"
  gitleaks_hook=$(grep -A2 "gitleaks" .pre-commit-config.yaml 2>/dev/null | head -3)
  if [ -n "$gitleaks_hook" ]; then
    echo "GITLEAKS_HOOK=configured"
  else
    echo "GITLEAKS_HOOK=not_configured"
    echo "HINT: Add gitleaks hook to .pre-commit-config.yaml"
  fi

  # Check if hooks are installed
  if [ -f ".git/hooks/pre-commit" ] && grep -q "pre-commit" .git/hooks/pre-commit 2>/dev/null; then
    echo "HOOKS_INSTALLED=true"
  else
    echo "HOOKS_INSTALLED=false"
    echo "HINT: Run 'pre-commit install'"
  fi
else
  echo "CONFIG=missing"
  echo "HINT: Create .pre-commit-config.yaml with security hooks"
fi
echo ""

# Summary
echo "=== SCAN SUMMARY ==="
echo "TOTAL_FINDINGS=$findings"
if [ $findings -eq 0 ]; then
  echo "STATUS=PASS"
else
  echo "STATUS=FINDINGS_DETECTED"
fi
echo "=== SCAN COMPLETE ==="

exit "$([ $findings -gt 0 ] && echo 1 || echo 0)"

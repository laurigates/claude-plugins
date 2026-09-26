#!/usr/bin/env bash
#
# check-public-export.sh — sanitization tripwire for internal -> public exports.
#
# Scans a candidate export tree for internal IDENTIFIERS and for Markdown links
# that ESCAPE the tree, before the content lands somewhere public (a public
# repo, a blog post, a talk, a shareable). It flags the leak classes a human
# reviewer reliably misses one of, every time.
#
# This is NOT a secret scanner — run gitleaks for tokens/keys. This catches
# *context* leakage: project IDs, service-account emails, internal hostnames,
# home paths, personal emails/names, and links pointing back into private repos.
#
# Built-in patterns cover only org-neutral shapes (GCP service-account emails,
# 12-digit GCP project numbers, absolute home paths). Your organisation's own
# identifier shapes (project-id prefixes, internal domains, staff email domain)
# go in a --patterns file, so they stay out of this public script.
#
# Usage:
#   check-public-export.sh [options] <export-root>
#
# Options:
#   --patterns FILE  Extra leak classes, one "label::regex" per line (extended
#                    regex, case-sensitive; '#' comment lines and blank lines
#                    ignored). Repeatable. Example line:
#                      Internal hostname (corp.example)::\b[a-z0-9-]+\.corp\.example\b
#   --names FILE     Newline-separated personal names to flag (one per line;
#                    '#' comments allowed). Names can't be regex'd reliably, so
#                    seed this per export from the source's git authors / RBAC.
#   --allow REGEX    Dismiss findings matching REGEX (repeatable). Use for
#                    known-benign hits, e.g. a diagram CSS class that shares a
#                    project-id prefix.
#   --repo-root D    Treat D (not the scanned dir) as the link boundary. Use
#                    when the export already lives inside a larger PUBLIC repo,
#                    so links to siblings (../LICENSE, ../other-doc) are not
#                    "escapes". Default: the scanned dir (strict
#                    self-containment — the right mode for a pre-export gate).
#   --no-links       Skip the Markdown link-escape structural check.
#   -q, --quiet      Print only the summary line.
#   -h, --help       This help.
#
# Exit status: 0 = clean, 1 = findings, 2 = usage error.
#
# Write patterns so they do NOT match genericized <placeholder> tokens (those
# use angle brackets, which [a-z0-9-] character classes exclude).

set -euo pipefail

# ---------------------------------------------------------------------------
# Built-in leak classes as "label::regex" (extended-regex, case-sensitive).
# Org-specific shapes belong in a --patterns file, not here.
# ---------------------------------------------------------------------------
PATTERNS=(
  "GCP service-account email::\\b[a-z0-9][a-z0-9-]*@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com\\b"
  "GCP project number (12-digit)::\\b[0-9]{12}\\b"
  "Absolute home path::/(Users|home)/[a-z][a-z0-9_-]+/"
)

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
NAMES_FILE=""
DO_LINKS=1
QUIET=0
ROOT=""
REPO_ROOT=""
ALLOWS=()
PATTERN_FILES=()

usage() { sed -n '2,45p' "$0" | sed 's/^#\{0,1\} \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --patterns) PATTERN_FILES+=("${2:-}"); shift 2 ;;
    --names)  NAMES_FILE="${2:-}"; shift 2 ;;
    --allow)  ALLOWS+=("${2:-}"); shift 2 ;;
    --repo-root) REPO_ROOT="${2:-}"; shift 2 ;;
    --no-links) DO_LINKS=0; shift ;;
    -q|--quiet) QUIET=1; shift ;;
    -h|--help) usage 0 ;;
    -*) echo "unknown option: $1" >&2; usage 2 ;;
    *) ROOT="$1"; shift ;;
  esac
done

[[ -n "$ROOT" ]] || { echo "error: export-root required" >&2; usage 2; }
[[ -d "$ROOT" ]] || { echo "error: not a directory: $ROOT" >&2; exit 2; }
command -v rg >/dev/null || { echo "error: ripgrep (rg) is required" >&2; exit 2; }
REPO_ROOT="${REPO_ROOT:-$ROOT}"
[[ -d "$REPO_ROOT" ]] || { echo "error: --repo-root not a directory: $REPO_ROOT" >&2; exit 2; }

for pf in "${PATTERN_FILES[@]:-}"; do
  [[ -n "$pf" ]] || continue
  [[ -f "$pf" ]] || { echo "error: --patterns file not found: $pf" >&2; exit 2; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" == *"::"* ]] || { echo "error: pattern line lacks 'label::regex': $line" >&2; exit 2; }
    PATTERNS+=("$line")
  done < "$pf"
done

FINDINGS=0
say() { [[ "$QUIET" == 1 ]] || printf '%s\n' "$*"; }
# report LABEL CONTENT — takes findings as an arg (NOT stdin) so it runs in the
# parent shell; piping into it would drop the FINDINGS counter in a subshell.
report() {
  local label="$1" out="$2"
  # Drop lines matching any --allow regex (known-benign hits).
  local a
  for a in "${ALLOWS[@]:-}"; do
    [[ -n "$a" ]] || continue
    out="$(printf '%s\n' "$out" | rg -v -e "$a" || true)"
  done
  [[ -n "$out" ]] || return 0
  local n; n=$(printf '%s\n' "$out" | grep -c '' || true)
  FINDINGS=$((FINDINGS + n))
  say ""
  say "✗ ${label}  (${n})"
  [[ "$QUIET" == 1 ]] || printf '%s\n' "$out" | sed 's/^/    /'
}
# scan LABEL REGEX — rg into a variable (command substitution keeps the parent
# shell), then report.
scan() {
  local label="$1" regex="$2" out
  out="$(rg -n --no-heading --no-ignore -e "$regex" "$ROOT" 2>/dev/null || true)"
  report "$label" "$out"
}

# ---------------------------------------------------------------------------
# 1. Identifier patterns
# ---------------------------------------------------------------------------
for entry in "${PATTERNS[@]}"; do
  label="${entry%%::*}"; regex="${entry#*::}"
  scan "$label" "$regex"
done

# ---------------------------------------------------------------------------
# 2. Personal names (from --names file; literal, word-boundaried)
# ---------------------------------------------------------------------------
if [[ -n "$NAMES_FILE" ]]; then
  [[ -f "$NAMES_FILE" ]] || { echo "error: --names file not found: $NAMES_FILE" >&2; exit 2; }
  while IFS= read -r name; do
    name="${name%%#*}"; name="$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$name" ]] || continue
    name_out="$(rg -n --no-heading --no-ignore -F -- "$name" "$ROOT" 2>/dev/null || true)"
    report "Personal name: ${name}" "$name_out"
  done < "$NAMES_FILE"
fi

# ---------------------------------------------------------------------------
# 3. Structural: Markdown links that ESCAPE the export root
#    (relative links that resolve outside ROOT, or to a missing target).
# ---------------------------------------------------------------------------
if [[ "$DO_LINKS" == 1 ]]; then
  link_out="$(SCAN="$ROOT" BOUNDARY="$REPO_ROOT" python3 - <<'PY'
import os, re
scan = os.path.realpath(os.environ["SCAN"])
boundary = os.path.realpath(os.environ["BOUNDARY"])
hits = []
for dirpath, _, files in os.walk(scan):
    for fn in files:
        if not fn.endswith(".md"):
            continue
        p = os.path.join(dirpath, fn)
        try:
            text = open(p, encoding="utf-8", errors="replace").read()
        except Exception:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            for m in re.finditer(r'\]\(([^)]+)\)', line):
                t = m.group(1).strip()
                if t.startswith(("http://", "https://", "#", "mailto:")):
                    continue
                path = t.split("#")[0]
                if not path:
                    continue
                full = os.path.realpath(os.path.join(dirpath, path))
                rel = os.path.relpath(p, scan)
                if not (full == boundary or full.startswith(boundary + os.sep)):
                    hits.append(f"{rel}:{i}: link escapes boundary -> {t}")
                elif not os.path.exists(full):
                    hits.append(f"{rel}:{i}: broken link -> {t}")
print("\n".join(hits))
PY
)"
  report "Markdown links escaping root / broken" "$link_out"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
say ""
if [[ "$FINDINGS" -eq 0 ]]; then
  echo "✓ clean — no internal identifiers or escaping links found in ${ROOT}"
  exit 0
else
  echo "✗ ${FINDINGS} potential leak(s) found in ${ROOT} — review each before publishing."
  echo "  (false positives: dismiss case-by-case; genericize real hits to <placeholders>.)"
  echo "  Reminder: this is not a secret scan — also run gitleaks for tokens/keys."
  exit 1
fi

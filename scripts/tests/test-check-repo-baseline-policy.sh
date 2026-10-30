#!/usr/bin/env bash
# shellcheck disable=SC2016  # file-level: backticked plugin names in the planted docs are literal markdown, not command substitution
# Regression test for scripts/check-repo-baseline-policy.sh
#
# Per .claude/rules/regression-testing.md: the policy guard ships with a test
# proving it (a) passes on the real configure-plugin/policy/repo-baseline.json
# against the real marketplace and skill docs, and (b) flags each defect class.
# The load-bearing case is the seeded `pyright@claude-plugins-official`: the
# configure-claude-plugins exhaustive-mode reference shipped six official LSP
# names without their `-lsp` suffix, and Claude Code silently ignores an
# enabledPlugins key that names no plugin. Fixtures live in a temp dir so the
# test never touches the real repo state.
set -uo pipefail

script_dir="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
check="$script_dir/check-repo-baseline-policy.sh"
contract="$script_dir/check-structured-output-contract.sh"
real_policy="$repo_root/configure-plugin/policy/repo-baseline.json"
real_marketplace="$repo_root/.claude-plugin/marketplace.json"

pass=0
fail=0

ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ko() { echo "FAIL: $1"; fail=$((fail + 1)); }

# Here-string, not `printf … | grep -q`: under pipefail a matching grep -q can
# SIGPIPE the producer and report a hit as a miss (shell-scripting.md).
assert_has() {
  if grep -q -- "$3" <<<"$2"; then ok "$1"; else ko "$1"; printf '%s\n' "$2"; fi
}
assert_lacks() {
  if grep -q -- "$3" <<<"$2"; then ko "$1"; printf '%s\n' "$2"; else ok "$1"; fi
}
assert_strict_ok() {
  if bash "$check" --project-dir "$2" --strict >/dev/null 2>&1; then ok "$1"; else ko "$1"; fi
}
assert_strict_fails() {
  if bash "$check" --project-dir "$2" --strict >/dev/null 2>&1; then ko "$1"; else ok "$1"; fi
}
valid() { printf '%s\n' "$1" | bash "$contract" --validate - >/dev/null 2>&1 && echo true || echo false; }

tmp_root="$(mktemp -d)"
[ -n "$tmp_root" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$tmp_root"' EXIT

# make_fixture <dir> <policy-json> [<skill-doc-text>]
# Writes the real marketplace, the given policy and one skill doc.
make_fixture() {
  mkdir -p "$1/.claude-plugin" "$1/configure-plugin/policy" "$1/configure-plugin/skills/demo/references"
  cp "$real_marketplace" "$1/.claude-plugin/marketplace.json"
  printf '%s\n' "$2" > "$1/configure-plugin/policy/repo-baseline.json"
  printf '%s\n' "${3:-Enable \`typescript-lsp@claude-plugins-official\` for TypeScript.}" \
    > "$1/configure-plugin/skills/demo/references/notes.md"
}

# policy_with <jq-filter>  — the real policy transformed by a jq filter
policy_with() { jq "$1" "$real_policy"; }

# --- TEST A: the real repo passes ---------------------------------------------
out_a="$(bash "$check" --project-dir "$repo_root")"
assert_has "real policy reports STATUS=OK" "$out_a" "^STATUS=OK$"
assert_has "real policy reports ISSUE_COUNT=0" "$out_a" "^ISSUE_COUNT=0$"
assert_has "real policy is read as version 1" "$out_a" "^POLICY_VERSION=1$"
assert_lacks "real run scanned at least one skill doc" "$out_a" "^DOCS_SCANNED=0$"
assert_strict_ok "real repo passes --strict (exit 0)" "$repo_root"

# --- TEST B: seeded bad official name (the #3318 defect) ----------------------
b="$tmp_root/b"
make_fixture "$b" "$(policy_with '.stacks[0].plugins += ["pyright@claude-plugins-official"]')"
out_b="$(bash "$check" --project-dir "$b")"
assert_has "pyright@claude-plugins-official flagged unknown_official_plugin" "$out_b" "TYPE=unknown_official_plugin MSG=pyright@claude-plugins-official"
assert_has "seeded bad name yields STATUS=ERROR" "$out_b" "^STATUS=ERROR$"
assert_strict_fails "seeded bad name fails --strict (exit 1)" "$b"

# --- TEST C: a laurigates plugin the marketplace does not publish -------------
c="$tmp_root/c"
make_fixture "$c" "$(policy_with '.stacks[0].plugins += ["go-plugin@laurigates-claude-plugins"]')"
out_c="$(bash "$check" --project-dir "$c")"
assert_has "go-plugin@laurigates-claude-plugins flagged unknown_marketplace_plugin" "$out_c" "TYPE=unknown_marketplace_plugin MSG=go-plugin@laurigates-claude-plugins"

# --- TEST D: a suffix that is neither marketplace -----------------------------
d="$tmp_root/d"
make_fixture "$d" "$(policy_with '.stacks[0].plugins += ["rust-plugin@claude-plugins"]')"
out_d="$(bash "$check" --project-dir "$d")"
assert_has "legacy @claude-plugins suffix flagged unknown_marketplace_suffix" "$out_d" "TYPE=unknown_marketplace_suffix MSG=rust-plugin@claude-plugins"

# --- TEST E: a skill doc names a non-existent official plugin -----------------
e="$tmp_root/e"
make_fixture "$e" "$(policy_with '.')" \
  '| `CMakeLists.txt` | `tools-plugin` + `clangd@claude-plugins-official` (LSP) |'
out_e="$(bash "$check" --project-dir "$e")"
assert_has "clangd@claude-plugins-official in a skill doc flagged doc_unknown_official_plugin" "$out_e" "TYPE=doc_unknown_official_plugin MSG=configure-plugin/skills/demo/references/notes.md:1"
assert_strict_fails "bad doc name fails --strict (exit 1)" "$e"
e2="$tmp_root/e2"
make_fixture "$e2" "$(policy_with '.')" \
  'Use `clangd-lsp@claude-plugins-official`; a `<name>@claude-plugins-official` key is a placeholder.'
out_e2="$(bash "$check" --project-dir "$e2")"
assert_has "correct -lsp name and a <placeholder> in a skill doc pass" "$out_e2" "^STATUS=OK$"
assert_has "the correct doc reference is counted" "$out_e2" "^DOC_OFFICIAL_REFS=1$"

# --- TEST F: policy is not valid JSON -----------------------------------------
f="$tmp_root/f"
make_fixture "$f" '{"version": 1,'
out_f="$(bash "$check" --project-dir "$f")"
assert_has "unparseable policy flagged policy_invalid_json" "$out_f" "TYPE=policy_invalid_json"
assert_strict_fails "unparseable policy fails --strict" "$f"

# --- TEST G: policy file missing ----------------------------------------------
g="$tmp_root/g"
make_fixture "$g" '{}'
rm "$g/configure-plugin/policy/repo-baseline.json"
out_g="$(bash "$check" --project-dir "$g")"
assert_has "absent policy flagged missing_policy" "$out_g" "TYPE=missing_policy"

# --- TEST H: marketplace key in the floor differs from marketplace .name ------
h="$tmp_root/h"
make_fixture "$h" "$(policy_with '.settings.floor.extraKnownMarketplaces |= with_entries(.key = "claude-plugins")')"
out_h="$(bash "$check" --project-dir "$h")"
assert_has "floor marketplace key != marketplace name flagged marketplace_key_mismatch" "$out_h" "TYPE=marketplace_key_mismatch"

# --- TEST I: no skill docs to scan is an ERROR, not a silent OK ---------------
i="$tmp_root/i"
make_fixture "$i" "$(policy_with '.')"
rm -rf "$i/configure-plugin/skills"
out_i="$(bash "$check" --project-dir "$i")"
assert_has "missing skill docs flagged nothing_scanned" "$out_i" "TYPE=nothing_scanned"

# --- TEST J: unknown flags are rejected, never swallowed (#2057) --------------
if bash "$check" --project-dir "$repo_root" --stirct >/dev/null 2>&1; then
  ko "an unknown flag is rejected"
else
  rc=$?
  if [ "$rc" -eq 2 ]; then ok "an unknown flag is rejected (exit 2)"; else ko "an unknown flag is rejected (exit 2, got $rc)"; fi
fi

# --- TEST K: structured-output contract on ERROR and OK -----------------------
assert_has "ERROR output names the first finding in REASON=" "$out_b" "^REASON=unknown_official_plugin: pyright@claude-plugins-official"
assert_has "ERROR output satisfies the structured-output contract" "$(valid "$out_b")" "^true$"
k="$tmp_root/k"
make_fixture "$k" "$(policy_with '.stacks[0].plugins += ["pyright@claude-plugins-official", "go-plugin@laurigates-claude-plugins"]')"
out_k="$(bash "$check" --project-dir "$k")"
assert_has "two findings yield a (+1 more) suffix" "$out_k" "^REASON=unknown_official_plugin: .* (+1 more)$"
assert_has "two-finding output satisfies the structured-output contract" "$(valid "$out_k")" "^true$"
assert_has "OK output satisfies the structured-output contract" "$(valid "$out_a")" "^true$"
assert_lacks "OK output carries no REASON=" "$out_a" "^REASON="

echo ""
echo "RESULTS: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

#!/usr/bin/env bash
# Regression test for security-scan.sh's gitleaks section.
#
# A .gitleaks.toml holding only [allowlist] loads zero gitleaks rules, so a scan
# that reads it reports clean whatever the tree holds. security-scan.sh used to
# print STATUS=clean / CONFIG=present for that file. It must now print
# STATUS=inert_config / CONFIG=inert and count a finding, while a config that
# extends the default ruleset keeps STATUS=clean / CONFIG=present.
#
# Cases A-D run the shipped script with a stub gitleaks that always reports
# clean, so they need no gitleaks install. Case E runs the REAL gitleaks (when
# present) over a committed, generated token: the bare-allowlist config must be
# the one gitleaks misses, and the extended config the one it catches.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scan_script="${script_dir}/../security-scan.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$scan_script" ] || fail "security-scan.sh not found at $scan_script"

# GIT_DIR and friends override `git -C` and the cwd, so a leaked value would
# point these fixtures' git commands at the real checkout (#1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

work="$(mktemp -d)" || { fail "mktemp -d failed"; }
if [ -n "$work" ] && [ -d "$work" ]; then :; else fail "bad work dir"; fi
trap 'rm -rf "$work"' EXIT

stub_bin="${work}/stub-bin"
mkdir -p "$stub_bin"
cat > "${stub_bin}/gitleaks" <<'STUB'
#!/usr/bin/env bash
# Stub: every scan is clean, which is exactly what gitleaks reports for a
# zero-rule config.
echo "no leaks found"
exit 0
STUB
chmod +x "${stub_bin}/gitleaks"
# A stub without the executable bit is skipped by PATH lookup and the real
# binary runs instead.
[ -x "${stub_bin}/gitleaks" ] || fail "gitleaks stub is not executable"

# $1 = repo dir, $2 = printf format for .gitleaks.toml ("" = no config file)
make_repo() {
  local mr_dir="$1" mr_cfg="$2"
  mkdir -p "$mr_dir"
  git -C "$mr_dir" init -q -b main >/dev/null 2>&1 || fail "git init failed in $mr_dir"
  # Cover every pattern Check 3 looks for, so the gitleaks section is the only
  # thing that can raise a finding in these fixtures.
  printf '.env\n*.pem\n*.key\ncredentials.json\n.api_tokens\n' > "${mr_dir}/.gitignore"
  if [ -n "$mr_cfg" ]; then
    # shellcheck disable=SC2059  # the fixture config is a printf format by design
    printf "$mr_cfg" > "${mr_dir}/.gitleaks.toml"
  fi
}

# Runs the scan inside $1 with $2 prepended to PATH; sets scan_out / scan_rc /
# gl_section (the --- GITLEAKS --- block only, since the pre-commit section also
# prints a CONFIG= line).
scan_out=""; scan_rc=0; gl_section=""
run_scan() {
  scan_out="$(cd "$1" && PATH="$2:$PATH" bash "$scan_script" 2>&1)"
  scan_rc=$?
  gl_section="$(sed -n '/^--- GITLEAKS ---$/,/^$/p' <<<"$scan_out")"
  [ -n "$gl_section" ] || fail "no GITLEAKS section in output:\n$scan_out"
}

bare_cfg="[allowlist]\npaths = ['''^no-such-path$''']\n"
extend_cfg="[extend]\nuseDefault = true\n\n[allowlist]\npaths = ['''^no-such-path$''']\n"

# Case A — THE REPORTED DEFECT: an allowlist-only config.
make_repo "${work}/a" "$bare_cfg"
run_scan "${work}/a" "$stub_bin"
grep -q "^STATUS=inert_config$" <<<"$gl_section" || fail "A: expected STATUS=inert_config:\n$gl_section"
grep -q "^CONFIG=inert$" <<<"$gl_section" || fail "A: expected CONFIG=inert:\n$gl_section"
grep -q "STATUS=clean" <<<"$gl_section" && fail "A: a zero-rule scan must not report clean:\n$gl_section"
grep -q "^TOTAL_FINDINGS=1$" <<<"$scan_out" || fail "A: expected TOTAL_FINDINGS=1:\n$scan_out"
[ "$scan_rc" -eq 1 ] || fail "A: expected exit 1, got $scan_rc"
pass "A: an allowlist-only .gitleaks.toml reports inert_config and counts a finding"

# Case B — GUARD INTEGRITY: a config that extends the default ruleset stays clean.
make_repo "${work}/b" "$extend_cfg"
run_scan "${work}/b" "$stub_bin"
grep -q "^STATUS=clean$" <<<"$gl_section" || fail "B: expected STATUS=clean:\n$gl_section"
grep -q "^CONFIG=present$" <<<"$gl_section" || fail "B: expected CONFIG=present:\n$gl_section"
grep -q "^TOTAL_FINDINGS=0$" <<<"$scan_out" || fail "B: expected TOTAL_FINDINGS=0:\n$scan_out"
[ "$scan_rc" -eq 0 ] || fail "B: expected exit 0, got $scan_rc"
pass "B: [extend] useDefault = true keeps STATUS=clean / CONFIG=present"

# Case C — custom [[rules]] without [extend] also loads rules.
make_repo "${work}/c" "[[rules]]\nid = \"gh-pat\"\nregex = '''ghp_[0-9a-zA-Z]{36}'''\n"
run_scan "${work}/c" "$stub_bin"
grep -q "^CONFIG=present$" <<<"$gl_section" || fail "C: expected CONFIG=present:\n$gl_section"
grep -q "^STATUS=clean$" <<<"$gl_section" || fail "C: expected STATUS=clean:\n$gl_section"
pass "C: a config with its own [[rules]] is not inert"

# Case D — no config: gitleaks runs on its built-in rules, unchanged behaviour.
make_repo "${work}/d" ""
run_scan "${work}/d" "$stub_bin"
grep -q "^CONFIG=missing$" <<<"$gl_section" || fail "D: expected CONFIG=missing:\n$gl_section"
grep -q "^STATUS=clean$" <<<"$gl_section" || fail "D: expected STATUS=clean:\n$gl_section"
pass "D: no .gitleaks.toml keeps CONFIG=missing / STATUS=clean"

# Case E — the real gitleaks agrees that the bare config is the one that misses
# a committed token. The token is generated at runtime, never a literal.
if command -v gitleaks >/dev/null 2>&1; then
  real_dir="$(dirname "$(command -v gitleaks)")"
  token="ghp_$(od -An -tx1 -N18 /dev/urandom | tr -d ' \n')"
  [ "${#token}" -eq 40 ] || fail "E: canary token generation failed: ${token}"
  for e_case in bare extend; do
    e_dir="${work}/e-${e_case}"
    if [ "$e_case" = bare ]; then make_repo "$e_dir" "$bare_cfg"; else make_repo "$e_dir" "$extend_cfg"; fi
    printf 'token = "%s"\n' "$token" > "${e_dir}/settings.txt"
    git -C "$e_dir" add -- settings.txt .gitignore .gitleaks.toml
    git -C "$e_dir" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false \
      commit -q -m fixture >/dev/null 2>&1 || fail "E: fixture commit failed in $e_dir"
    run_scan "$e_dir" "$real_dir"
    if [ "$e_case" = bare ]; then
      grep -q "^STATUS=inert_config$" <<<"$gl_section" \
        || fail "E: real gitleaks with the bare config should miss the token (inert_config):\n$gl_section"
    else
      grep -q "^STATUS=secrets_found$" <<<"$gl_section" \
        || fail "E: real gitleaks with [extend] useDefault = true should find the token:\n$gl_section"
    fi
  done
  pass "E: gitleaks $(gitleaks version 2>/dev/null) misses a committed token under the bare config and finds it under [extend]"
else
  echo "SKIP: gitleaks not on PATH — case E against the real scanner not run"
fi

echo "ALL TESTS PASSED"

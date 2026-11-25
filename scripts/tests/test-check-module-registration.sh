#!/usr/bin/env bash
# shellcheck disable=SC2016  # file-level: fixture bodies are single-quoted on purpose — they must reach the file unexpanded
# Regression tests for scripts/check-module-registration.sh (issue #3805).
#
# Each case builds an isolated root holding one fixture loader, runs the guard
# against it, and checks ISSUE_COUNT. Positive cases are paired with the
# near-miss that must stay silent, so the suite fails an over-reporting guard
# and a mute one alike.
#
# Run: bash scripts/tests/test-check-module-registration.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$repo_root/scripts/check-module-registration.sh"
CONTRACT="$repo_root/scripts/check-structured-output-contract.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then echo "bad sandbox dir" >&2; exit 1; fi
trap 'rm -rf "$WORK"' EXIT

ok()    { printf '  PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
notok() { printf '  FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

# new_case <name> <file> <body>: a root holding one fixture file.
new_case() {
  local d="$WORK/$1"
  mkdir -p "$(dirname "$d/$2")"
  printf '%s\n' "$3" > "$d/$2"
  printf '%s\n' "$d"
}

field() { grep -m1 "^$2=" <<<"$1" | cut -d= -f2-; }

assert_count() {
  local desc="$1" want="$2" dir="$3" out got
  out=$(bash "$GUARD" "$dir" 2>&1)
  got=$(field "$out" ISSUE_COUNT)
  if [ "$got" = "$want" ]; then ok "$desc"; else notok "$desc (want ISSUE_COUNT=$want, got '$got')"; fi
}

echo "=== check-module-registration regression tests ==="

# 1. The #3805 shape: a .py loader with no registration.
d=$(new_case py-bare plug/scripts/loader.py 'import importlib.util
spec = importlib.util.spec_from_file_location("x", "x.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)')
assert_count "py loader without sys.modules registration is flagged" 1 "$d"

# 2. Same loader, registered before exec_module: silent.
d=$(new_case py-registered plug/scripts/loader.py 'import importlib.util, sys
spec = importlib.util.spec_from_file_location("x", "x.py")
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)')
assert_count "py loader registered before exec_module is not flagged" 0 "$d"

# 3. Registered AFTER exec_module: the order is the point, so flagged.
d=$(new_case py-late plug/scripts/loader.py 'import importlib.util, sys
spec = importlib.util.spec_from_file_location("x", "x.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
sys.modules[spec.name] = mod')
assert_count "registration after exec_module is flagged" 1 "$d"

# 4. Two loaders in one file, only the first registered: the second is flagged.
#    A file-level grep for `sys.modules[` (the #3805 discovery query) misses it.
d=$(new_case py-two plug/scripts/loader.py 'import importlib.util, sys
a = importlib.util.spec_from_file_location("a", "a.py")
ma = importlib.util.module_from_spec(a)
sys.modules[a.name] = ma
a.loader.exec_module(ma)
b = importlib.util.spec_from_file_location("b", "b.py")
mb = importlib.util.module_from_spec(b)
b.loader.exec_module(mb)')
assert_count "second unregistered loader in a file with one registered is flagged" 1 "$d"

# 5. An unrelated sys.modules write (a stub) before the spec does not count.
d=$(new_case py-stub plug/scripts/tests/test_x.py 'import importlib.util, sys
sys.modules["numpy"] = object()
spec = importlib.util.spec_from_file_location("x", "x.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)')
assert_count "a stub sys.modules write before the spec does not satisfy the loader" 1 "$d"

# 6. sys.modules.setdefault counts as registration.
d=$(new_case py-setdefault plug/scripts/loader.py 'import importlib.util, sys
spec = importlib.util.spec_from_file_location("x", "x.py")
mod = importlib.util.module_from_spec(spec)
sys.modules.setdefault(spec.name, mod)
spec.loader.exec_module(mod)')
assert_count "sys.modules.setdefault counts as registration" 0 "$d"

# 7/8. Shell one-liner: unregistered flagged, registered silent.
d=$(new_case sh-bare plug/hooks/test-x.sh 'python3 -c '"'"'import importlib.util as u, sys; s = u.spec_from_file_location("e", sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)'"'"' x.py')
assert_count "unregistered shell one-liner loader is flagged" 1 "$d"
d=$(new_case sh-registered plug/hooks/test-x.sh 'python3 -c '"'"'import importlib.util as u, sys; s = u.spec_from_file_location("e", sys.argv[1]); m = u.module_from_spec(s); sys.modules[s.name] = m; s.loader.exec_module(m)'"'"' x.py')
assert_count "registered shell one-liner loader is not flagged" 0 "$d"

# 9. A heredoc loader in a .sh test is scanned like a .py file.
d=$(new_case sh-heredoc plug/scripts/tests/test-y.sh 'python3 - "$TOOL" <<'"'"'PY'"'"'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("il", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
PY')
assert_count "unregistered heredoc loader is flagged" 1 "$d"

# 10. A commented-out registration does not count.
d=$(new_case py-commented plug/scripts/loader.py 'import importlib.util, sys
spec = importlib.util.spec_from_file_location("x", "x.py")
mod = importlib.util.module_from_spec(spec)
# sys.modules[spec.name] = mod
spec.loader.exec_module(mod)')
assert_count "a commented-out registration does not count" 1 "$d"

# 11. Escape hatch on the exec_module line.
d=$(new_case py-ok plug/scripts/loader.py 'import importlib.util
spec = importlib.util.spec_from_file_location("x", "x.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)  # module-registration: ok')
assert_count "the module-registration: ok marker suppresses the finding" 0 "$d"

# 12. exec_module with no spec_from_file_location (a non-path loader) is out of scope.
d=$(new_case py-nonpath plug/scripts/loader.py 'import importlib.util
spec = importlib.util.find_spec("json")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)')
assert_count "exec_module without spec_from_file_location is not flagged" 0 "$d"

# 13. Discovery prunes node_modules and agent worktrees.
d=$(new_case pruned node_modules/x/loader.py 'import importlib.util
spec = importlib.util.spec_from_file_location("x", "x.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)')
assert_count "loaders under node_modules are not scanned" 0 "$d"

# 14. The hazard itself: on Python 3.12-3.14 the unregistered shape fails and
#     the registered one loads. Skipped on interpreters where both load.
d="$WORK/repro"; mkdir -p "$d"
printf 'from __future__ import annotations\nfrom dataclasses import dataclass\n@dataclass\nclass A:\n    x: int\n' > "$d/target.py"
load() {  # load <register 0|1>: exit 0 when the target loads
  python3 - "$d/target.py" "$1" <<'PY' 2>/dev/null
import importlib.util, sys
spec = importlib.util.spec_from_file_location("target_under_test", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
if sys.argv[2] == "1":
    sys.modules[spec.name] = mod
spec.loader.exec_module(mod)
PY
}
if load 1; then
  if load 0; then
    printf '  SKIP: %s\n' "python3 $(python3 -c 'import sys; print(sys.version.split()[0])') loads the unregistered shape; hazard not reproducible here"
  else
    ok "unregistered dataclass + future-annotations target fails, registered one loads"
  fi
else
  notok "the registered loader shape failed to load a dataclass target"
fi

# 15. Structured-output contract on the failing and passing outputs.
for case_dir in "$WORK/py-two" "$WORK/py-registered"; do
  if bash "$GUARD" "$case_dir" | bash "$CONTRACT" --validate >/dev/null 2>&1; then
    ok "output for $(basename "$case_dir") passes the structured-output contract"
  else
    notok "output for $(basename "$case_dir") fails the structured-output contract"
  fi
done

# 16. --strict exits 1 on a finding, 0 on a clean tree.
bash "$GUARD" --strict "$WORK/py-bare" >/dev/null 2>&1
rc_bad=$?
bash "$GUARD" --strict "$WORK/py-registered" >/dev/null 2>&1
rc_good=$?
if [ "$rc_bad" = 1 ] && [ "$rc_good" = 0 ]; then ok "--strict exits 1 on a finding and 0 when clean"
else notok "--strict exit codes (finding=$rc_bad, clean=$rc_good)"; fi

echo
echo "PASSED=$PASS"
echo "FAILED=$FAIL"
[ "$FAIL" -eq 0 ]

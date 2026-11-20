#!/usr/bin/env bash
# test-check-justfile-script-modes.sh — regression tests for
# check-justfile-script-modes.sh (issue #3695).
#
# Pins:
#   A. a recipe running an executable tracked script passes
#   B. a recipe running a 100644 tracked script fails (the #3695 shape)
#   C. a ./path passed as an ARGUMENT is not an invocation
#   D. command position after `&&` / `;` / `$(` is detected
#   E. an untracked ./path (build output) is skipped
#   F. a `mod name 'dir'` module's recipe resolves against the module dir
#   G. both outputs satisfy the structured-output contract (--validate)
#
# Fixtures are throwaway git repos; only the index is read (no commits), so
# no user.name / HOME git config is touched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHECK="${REPO_ROOT}/scripts/check-justfile-script-modes.sh"
CONTRACT="${REPO_ROOT}/scripts/check-structured-output-contract.sh"

pass=0
fail=0
check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
  fi
}

[ -f "$CHECK" ] || { echo "missing script: $CHECK" >&2; exit 1; }

WORK="$(mktemp -d)" || { echo "mktemp failed" >&2; exit 1; }
if [ ! -d "$WORK" ]; then echo "bad sandbox dir" >&2; exit 1; fi
trap 'rm -rf "$WORK"' EXIT

# mk_repo <name> -> echoes a fresh fixture repo dir
mk_repo() {
  local d="$WORK/$1"
  [ -n "$1" ] || return 1
  mkdir -p "$d/scripts"
  git -C "$d" init -q
  echo "$d"
}

# track <repo> <path> <+x|-x>
track() {
  mkdir -p "$(dirname "$1/$2")"
  printf '#!/usr/bin/env bash\necho hi\n' > "$1/$2"
  git -C "$1" add -- "$2"
  git -C "$1" update-index --chmod="$3" -- "$2"
}

run() { bash "$CHECK" --project-dir "$1" >/dev/null 2>&1; echo $?; }

# A. executable script passes
d=$(mk_repo A)
track "$d" scripts/ok.sh +x
printf 'lint:\n    ./scripts/ok.sh {{args}}\n' > "$d/justfile"
check "A: 100755 script exit 0" "0" "$(run "$d")"

# B. 100644 script fails
d=$(mk_repo B)
track "$d" scripts/bad.py -x
printf 'lint:\n    @./scripts/bad.py\n' > "$d/justfile"
check "B: 100644 script exit 1" "1" "$(run "$d")"

# C. ./path as an argument only
d=$(mk_repo C)
track "$d" scripts/data.sh -x
printf 'lint:\n    python3 tool.py --input ./scripts/data.sh\n' > "$d/justfile"
check "C: argument ./path not flagged" "0" "$(run "$d")"

# D. command position after && ; $(
# The literal "$(" is the separator under test, so it stays single-quoted.
# shellcheck disable=SC2016
for sep in '&&' ';' '$('; do
  d=$(mk_repo "D$RANDOM")
  track "$d" scripts/bad.sh -x
  printf 'lint:\n    echo start %s ./scripts/bad.sh\n' "$sep" > "$d/justfile"
  check "D: detected after '$sep'" "1" "$(run "$d")"
done

# E. untracked path skipped
d=$(mk_repo E)
printf 'run:\n    ./build/out.bin\n' > "$d/justfile"
check "E: untracked ./path skipped" "0" "$(run "$d")"

# F. module recipe resolves against module dir
d=$(mk_repo F)
track "$d" sub/scripts/bad.sh -x
printf "mod sub 'sub'\n" > "$d/justfile"
printf 'go:\n    ./scripts/bad.sh\n' > "$d/sub/justfile"
check "F: module script mode checked" "1" "$(run "$d")"

# G. structured-output contract
if [ -f "$CONTRACT" ]; then
  out_ok=$(bash "$CHECK" --project-dir "$WORK/A" 2>/dev/null)
  out_err=$(bash "$CHECK" --project-dir "$WORK/B" 2>/dev/null)
  bash "$CONTRACT" --validate - >/dev/null 2>&1 <<<"$out_ok"
  check "G1: OK output satisfies contract" "0" "$?"
  bash "$CONTRACT" --validate - >/dev/null 2>&1 <<<"$out_err"
  check "G2: ERROR output satisfies contract" "0" "$?"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[ "$fail" -eq 0 ]

#!/usr/bin/env bash
# Regression test for tools-plugin/scripts/just-recipe-help.py
#
# The defect this guards: `just --list` shows ONE line per recipe, and with no
# `[doc()]` attribute that line is the LAST line of the comment block above the
# recipe. In a justfile whose blocks carry examples, the listing degrades into
# fragments and nothing reports it. The helper surfaces the block and the
# wrapped tool's flags; the audit is the gate.
#
# Every bug this helper can have is an UNDER-REPORT — a recipe not parsed, a
# subcommand not registered, a flag not read — and an under-report reads
# exactly like a justfile or script with less in it. So the tests below are
# mostly two-sided: each asserts the tool FINDS the thing and, where it
# matters, that it does not find it when it is absent.
#
# Guards:
#   A. the parse agrees exactly with `just --summary` (the independent control)
#   B. a recipe whose params carry a DEFAULT (`PYBIN="python3"`) is not dropped
#      — the first draft forbade `=` and silently parsed 48 of 57 recipes
#   C. `:=` assignments are not mistaken for recipes
#   D. a `_`-prefixed recipe counts as private with NO [private] attribute,
#      because just hides it from --list and --summary by itself
#   E. audit is SILENT on a well-authored justfile (a gate that fires on
#      everything is one nobody reads)
#   F. audit CATCHES each fragment shape by name: indented sub-item, command
#      example, lowercase continuation, missing block
#   G. an empty parse of a non-empty justfile raises rather than reporting none
#   H. a dynamically-named flag makes the tool REFUSE, not print a short list
#   I. a subcommand with no flags of its own is still listed
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper="$script_dir/../just-recipe-help.py"

pass_count=0
fail_count=0

assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

contains() { printf '%s' "$1" | grep -q -- "$2" && echo true || echo false; }

tmp="$(mktemp -d)"
# mktemp can fail; an empty $tmp would make every path below resolve to / .
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: could not create a sandbox" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT

# --------------------------------------------------------------- the fixture
# A justfile exercising every shape at once.
mkdir -p "$tmp/good/scripts"
cat >"$tmp/good/justfile" <<'JUSTFILE'
SCRIPTS := justfile_directory() / "scripts"

# One line, which is a perfectly good description.
build:
    @echo build

# A long block whose author knew the rule and ended it with a summary.
#   just deploy --dry-run
# Deploy the current build to staging.
[doc("Deploy the current build to staging.")]
deploy target="staging":
    @echo {{target}}

# A recipe taking a default, which the first draft dropped entirely.
[doc("Run the suite under a chosen interpreter.")]
test PYBIN="python3" *ARGS:
    @{{PYBIN}} -c "print(1)"

# Hidden from --list by the underscore alone, with no [private] attribute.
_helper:
    @echo helper

[doc("Wraps a real script, so its flags are readable.")]
wrapped *ARGS:
    @python3 {{SCRIPTS}}/tool.py {{ARGS}}
JUSTFILE

cat >"$tmp/good/scripts/tool.py" <<'PYEOF'
"""A tool with subcommands, one of which takes no flags."""
import argparse


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers()
    p = sub.add_parser("run", help="do the thing")
    p.add_argument("--jobs", type=int, default=4, help="worker count")
    p = sub.add_parser("status", help="report only")
    p.set_defaults(fn=None)
    return ap.parse_args()
PYEOF

# ------------------------------- A/B/C/D: the parse, against just's own parse
if command -v just >/dev/null 2>&1; then
  theirs="$(cd "$tmp/good" && just --summary 2>/dev/null | tr ' ' '\n' | sort)"
  mine="$(cd "$tmp/good" && python3 "$helper" --audit 2>/dev/null | head -2)"
  assert "A: just --summary is non-empty, so the control is not vacuous" \
    "$([ -n "$theirs" ] && echo true || echo false)"
  # `just --summary` lists 4 (build deploy test wrapped); _helper is hidden.
  assert "A: just hides the _-prefixed recipe from --summary" \
    "$([ "$(printf '%s\n' "$theirs" | grep -c .)" = "4" ] && echo true || echo false)"
  assert "D: the helper agrees — 5 parsed, 4 listed" \
    "$(contains "$mine" "5 recipe(s), 4 listed")"
else
  echo "SKIP: just is not installed; A and D cannot be controlled" >&2
fi

parsed="$(cd "$tmp/good" && python3 "$helper" test 2>&1)"
assert "B: a recipe whose params carry a default is parsed" \
  "$(contains "$parsed" 'test PYBIN="python3" \*ARGS')"

# Capture first, then match. Piping into `grep -q` under `set -o pipefail`
# reports the PYTHON exit status (2, "no such recipe") as the pipeline's, so
# the assertion reads false on the very output that proves it correct.
notfound="$(cd "$tmp/good" && python3 "$helper" scripts 2>&1)"
assert "C: the SCRIPTS := assignment is not parsed as a recipe" \
  "$(contains "$notfound" "no recipe or script")"
assert "C: and the four real recipes are offered instead" \
  "$(contains "$notfound" "wrapped")"

# ---------------------------------------------- E: silent on a good justfile
audit_good="$(cd "$tmp/good" && python3 "$helper" --audit 2>&1)"
rc_good=$?
assert "E: a well-authored justfile produces no findings" \
  "$(contains "$audit_good" "0 with an unusable description")"
assert "E: and exits 0" "$([ "$rc_good" = "0" ] && echo true || echo false)"

# ----------------------------------------- F: catches each fragment shape
mkdir -p "$tmp/bad"
cat >"$tmp/bad/justfile" <<'JUSTFILE'
# Render the thing.
#   just indented --flag
indented:
    @echo hi

# Render the thing.
# just example-cmd --flag
example-cmd:
    @echo hi

# Render the thing, which takes a while and is
# worth doing before lunch.
continued:
    @echo hi

no-comment:
    @echo hi
JUSTFILE

audit_bad="$(cd "$tmp/bad" && python3 "$helper" --audit 2>&1)"
rc_bad=$?
assert "F: all four bad shapes are reported" \
  "$(contains "$audit_bad" "4 with an unusable description")"
assert "F: an indented last line is named as a sub-item" \
  "$(contains "$audit_bad" "indented, so it is a sub-item")"
assert "F: a command example is named as one" \
  "$(contains "$audit_bad" "is a command example")"
assert "F: a lowercase continuation is named as one" \
  "$(contains "$audit_bad" "continues a sentence")"
assert "F: a missing block is named as a blank listing" \
  "$(contains "$audit_bad" "no comment block")"
assert "F: and exits non-zero" "$([ "$rc_bad" = "1" ] && echo true || echo false)"

# ---------------------------------- G: an empty parse raises, never reports 0
mkdir -p "$tmp/empty"
cat >"$tmp/empty/justfile" <<'JUSTFILE'
# only comments here
# and nothing that looks like a recipe
JUSTFILE
empty_out="$(cd "$tmp/empty" && python3 "$helper" --audit 2>&1)"
assert "G: an empty parse of a non-empty justfile names the parser" \
  "$(contains "$empty_out" "parser is")"

# ------------------------------- H: a flag it cannot read makes it REFUSE
mkdir -p "$tmp/dyn/scripts"
cat >"$tmp/dyn/justfile" <<'JUSTFILE'
# Wrap a script whose flags are built in a loop.
run *ARGS:
    @python3 scripts/dyn.py {{ARGS}}
JUSTFILE
cat >"$tmp/dyn/scripts/dyn.py" <<'PYEOF'
"""Builds its flag names dynamically."""
import argparse
ap = argparse.ArgumentParser()
for name in ("--a", "--b"):
    ap.add_argument(name)
ap.add_argument("--readable")
PYEOF
dyn_out="$(cd "$tmp/dyn" && python3 "$helper" run 2>&1)"
dyn_rc=$?
assert "H: a dynamically-named flag is refused, not partially listed" \
  "$(contains "$dyn_out" "REFUSING")"
assert "H: and the refusal exits 3" \
  "$([ "$dyn_rc" = "3" ] && echo true || echo false)"
assert "H: no partial flag list is printed alongside the refusal" \
  "$(printf '%s' "$dyn_out" | grep -q -- '--readable' && echo false || echo true)"

# ------------- J: an indirect help= is resolved or named, but never dropped
# `help=SOME_CONSTANT` used to print the flag bare, indistinguishable from a
# flag with no help at all — the same under-report the tool refuses elsewhere,
# which slipped through because `unresolved` counts unreadable flag NAMES and
# the name is fine here. Two-sided: asserting only that the resolvable case
# resolves would pass against an implementation that still drops the other.
mkdir -p "$tmp/indirect/scripts"
cat >"$tmp/indirect/justfile" <<'JUSTFILE'
# Wrap a script whose help text is held in a constant.
run *ARGS:
    @python3 scripts/indirect.py {{ARGS}}
JUSTFILE
cat >"$tmp/indirect/scripts/indirect.py" <<'PYEOF'
"""Holds its help text in a local, the usual way."""
import argparse


def main():
    blurb = "the text that must survive"
    ap = argparse.ArgumentParser()
    ap.add_argument("--resolvable", help=blurb)
    ap.add_argument("--opaque", help="x".join(["a", "b"]))
    return ap.parse_args()
PYEOF
ind_out="$(cd "$tmp/indirect" && python3 "$helper" run 2>&1)"
ind_rc=$?
assert "J: a constant help= is resolved to its text" \
  "$(contains "$ind_out" "the text that must survive")"
assert "J: an unresolvable help= is NAMED, not dropped" \
  "$(contains "$ind_out" "not a literal")"
assert "J: an indirect help= is not an unreadable flag NAME, so no refusal" \
  "$([ "$ind_rc" = "0" ] && echo true || echo false)"
assert "J: and it did not silently become a refusal either" \
  "$(printf '%s' "$ind_out" | grep -q 'REFUSING' && echo false || echo true)"

# ------------------------- I: a flagless subcommand is still listed by name
wrapped_out="$(cd "$tmp/good" && python3 "$helper" wrapped 2>&1)"
assert "I: a subcommand WITH flags is listed" \
  "$(contains "$wrapped_out" "SUBCOMMAND  run")"
assert "I: a subcommand with NO flags is still listed" \
  "$(contains "$wrapped_out" "SUBCOMMAND  status")"
assert "I: and is marked as having none, not silently empty" \
  "$(contains "$wrapped_out" "no flags of its own")"
assert "I: the {{SCRIPTS}} interpolation resolved to a real path" \
  "$(contains "$wrapped_out" "worker count")"

# ---------------------------------------------------------------- summary
echo "PASSED=$pass_count FAILED=$fail_count"
[ "$fail_count" -eq 0 ] || exit 1
echo "STATUS=OK"

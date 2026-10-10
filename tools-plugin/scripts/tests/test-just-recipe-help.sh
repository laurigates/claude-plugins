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
#   J-L. an indirect help= is resolved or named; a flag is filed by receiver;
#      show_script reads a .py docstring and does not parse a .sh as one
#   M-V. the scanner's name handling (laurigates/comfyui-nodes#199, #223):
#      a name bound to differing values is named, not guessed (M); a constant
#      inside an f-string or `+` is substituted (N); every rebinding form
#      forgets the old parser (O); flags added through a parameter go to a
#      marked UNTRACED heading (P); a function's bindings end with it (Q); an
#      annotated construction is traced (R); an argument group follows its
#      receiver (S); a refused subcommand help= is named (T); the [private]
#      attribute alone hides a recipe (U); a binding is forgotten only where
#      it runs (V); a recipe running a .sh gets no argparse --help hint (W)
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

ARMS = ["a", "b"]


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers()
    p = sub.add_parser("run", help="do the thing")
    p.add_argument("--jobs", type=int, default=4, help="worker count")
    p = sub.add_parser("status", help="report only")
    p.set_defaults(fn=None)
    # UNASSIGNED, the idiomatic spelling when a subcommand takes no flags --
    # reading only ast.Assign made these vanish entirely.
    # The interpolation is a runtime expression on purpose: a bare string
    # constant is SUBSTITUTED (block N), and I is about the f-string being
    # rendered at all, not about name resolution.
    sub.add_parser("bare", help=f"reads {len(ARMS)} arms")
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

LIMIT = 5


def main():
    blurb = "the text that must survive"
    ap = argparse.ArgumentParser()
    ap.add_argument("--resolvable", help=blurb)
    ap.add_argument("--fstring", help=f"cap at {LIMIT} items")
    ap.add_argument("--concat", help="scales: " + ", ".join(["a"]))
    ap.add_argument("--opaque", help=some_call())
    return ap.parse_args()
PYEOF
ind_out="$(cd "$tmp/indirect" && python3 "$helper" run 2>&1)"
ind_rc=$?
assert "J: a constant help= is resolved to its text" \
  "$(contains "$ind_out" "the text that must survive")"
# NOT `contains "cap at {LIMIT} items"` — that is VACUOUS. When the rendering
# is broken the marker prints the f-string's SOURCE, which contains the very
# same substring, so the assertion passes either way. (Caught by mutating
# `shown = _help_display(...)` to `None` and watching the suite stay green.)
# Exactly ONE flag here is genuinely opaque, so the marker must appear once.
marker_count="$(printf '%s' "$ind_out" | grep -c 'not a literal')"
assert "J: only the opaque flag falls back to the marker (got $marker_count)" \
  "$([ "$marker_count" = "1" ] && echo true || echo false)"
assert "J: the f-string's text is rendered, not its source expression" \
  "$(printf '%s' "$ind_out" | grep -q "f'cap at" && echo false || echo true)"
assert "J: with the interpolation left as a visible placeholder" \
  "$(contains "$ind_out" "cap at {LIMIT} items")"
assert "J: a concatenation keeps its literal half" \
  "$(contains "$ind_out" "scales: ")"
assert "J: an indirect help= is not an unreadable flag NAME, so no refusal" \
  "$([ "$ind_rc" = "0" ] && echo true || echo false)"
assert "J: and it did not silently become a refusal either" \
  "$(printf '%s' "$ind_out" | grep -q 'REFUSING' && echo false || echo true)"

# ---- K: a flag is filed under the parser it was CALLED on, not the last one
# Source order files `--x` under whichever parser was declared most recently;
# only the receiver says `run`. A flag printed beneath a subcommand that does
# not accept it is worse than an omission — it looks authoritative, and a
# reader who copies the signature gets a command that fails.
mkdir -p "$tmp/recv/scripts"
cat >"$tmp/recv/justfile" <<'JUSTFILE'
# Wrap a script that declares its parsers before populating them.
run *ARGS:
    @python3 scripts/recv.py {{ARGS}}
JUSTFILE
cat >"$tmp/recv/scripts/recv.py" <<'PYEOF'
"""Declares subcommands first, then adds their flags."""
import argparse

LAST_DESC = "declared after run's flags exist"


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers()
    p_run = sub.add_parser("run", help="the first one")
    sub.add_parser("status", help="flagless, declared in between")
    p_last = sub.add_parser("last", help=LAST_DESC)
    p_run.add_argument("--x", help="belongs to run")
    p_last.add_argument("--y", help="belongs to last")
    try:
        import fancy
    except ImportError:
        ap.add_argument("--fallback", help="only without fancy")
    match "x":
        case "x":
            ap.add_argument("--from-match", help="ast.Match keeps arms in cases")
    return ap.parse_args()


def other():
    # Rebinds the SAME local name main() used for the "run" sub-parser, from a
    # call this scan does not recognise. A stale mapping would file --stale
    # under "run"; the name must be forgotten, and since a forgotten name is
    # bound by something untraceable its flags go to UNTRACED (block O).
    ap2 = argparse.ArgumentParser()
    p_run = build_somehow(ap2)
    p_run.add_argument("--stale")
PYEOF
recv_out="$(cd "$tmp/recv" && python3 "$helper" run 2>&1)"
# awk, not `sed -n '/a/,/b/p'` — a sed range INCLUDES its terminator, so the
# status block ran on into `last` and picked up its --y. The assertion failed
# on correct output, which is the wrong way round for a test.
block() { printf '%s' "$recv_out" | awk -v s="SUBCOMMAND  $1" '
  index($0, s) == 1 { f = 1; next } /^SUBCOMMAND/ { f = 0 } /^FLAGS/ { f = 0 } f'; }
assert "K: --x is filed under run, not under the last-declared parser" \
  "$(contains "$(block run)" "\-\-x")"
assert "K: --y is filed under last" "$(contains "$(block last)" "\-\-y")"
assert "K: the flagless subcommand in between accepts nothing" \
  "$(printf '%s' "$(block status)" | grep -q -- '--' && echo false || echo true)"
assert "K: and says so rather than printing an empty section" \
  "$(contains "$(block status)" "no flags of its own")"
assert "K: an add_argument inside an except handler is seen at all" \
  "$(contains "$recv_out" "\-\-fallback")"
# A subcommand help bound to a NAME. add_argument's help resolves through the
# constants map; add_parser's did not, so the subcommand printed as a bare name.
assert "K: a subcommand help bound to a name resolves through the constants" \
  "$(contains "$recv_out" "declared after run's flags exist")"
assert "K: an add_argument inside a match arm is seen (ast.Match uses cases)" \
  "$(contains "$recv_out" "ast.Match keeps arms in cases")"
# A stale `parsers` entry OUTRANKS the cursor, so a name rebound by a call this
# scan does not recognise must forget its old parser rather than keep it.
assert "K: a rebound name does not file its flags under the old subcommand" \
  "$(printf '%s' "$(block run)" | grep -q -- '\-\-stale' && echo false || echo true)"

# ------------------------- I: a flagless subcommand is still listed by name
wrapped_out="$(cd "$tmp/good" && python3 "$helper" wrapped 2>&1)"
assert "I: a subcommand WITH flags is listed" \
  "$(contains "$wrapped_out" "SUBCOMMAND  run")"
assert "I: a subcommand with NO flags is still listed" \
  "$(contains "$wrapped_out" "SUBCOMMAND  status")"
assert "I: and is marked as having none, not silently empty" \
  "$(contains "$wrapped_out" "no flags of its own")"
assert "I: an UNASSIGNED add_parser is listed, not silently dropped" \
  "$(contains "$wrapped_out" "SUBCOMMAND  bare")"
assert "I: and its f-string help is rendered, same as a flag's" \
  "$(contains "$wrapped_out" "reads {len(ARMS)} arms")"
assert "I: the {{SCRIPTS}} interpolation resolved to a real path" \
  "$(contains "$wrapped_out" "worker count")"

# --- L: show_script reads a .py's docstring and does not parse a .sh as one
# TWO-SIDED on purpose. Asserting only the .sh arm proves nothing is
# OVER-parsed and never that anything is parsed: dropping the suffix check
# silently removes the module docstring from every Python script — the headline
# half of what this command prints — while the .sh assertions still hold.
cp "$tmp/good/scripts/tool.py" "$tmp/good/scripts/doc_example.py"
cat >"$tmp/good/scripts/plain.sh" <<'SHEOF'
#!/usr/bin/env bash
set -euo pipefail
echo hi
SHEOF
sh_out="$(cd "$tmp/good" && python3 "$helper" plain.sh 2>&1)"
py_out="$(cd "$tmp/good" && python3 "$helper" doc_example.py 2>&1)"
assert "L: a shell script is not reported as broken Python" \
  "$(printf '%s' "$sh_out" | grep -q 'does not parse' && echo false || echo true)"
assert "L: and says what it actually is" \
  "$(contains "$sh_out" "is a shell script, not argparse")"
assert "L: a Python script still gets its NOTES section" \
  "$(contains "$py_out" "NOTES")"
assert "L: with the module docstring in it" \
  "$(contains "$py_out" "A tool with subcommands")"

# ======================================================================
# M-V: the scanner's name handling (laurigates/comfyui-nodes#199, #223).
#
# `scan_arguments` resolves every name it reports through two module-wide
# maps, `constants` and `parsers`. Both used to fail toward a plausible help
# page rather than toward an error, and `unresolved` (which counts unreadable
# flag NAMES) could catch none of it. Each block below fails on the scanner
# as it stood before the port, except S and V, which pin guards the port
# itself needs and are mutation-checked instead.
mkdir -p "$tmp/scope/scripts"
cat >"$tmp/scope/justfile" <<'JUSTFILE'
# A placeholder, so the helper has a justfile to anchor the scripts to.
noop:
    @echo noop
JUSTFILE

# scan NAME -> the helper's output for scripts/NAME, stderr included.
scan() { (cd "$tmp/scope" && python3 "$helper" "$1" 2>&1); }

# flags_in OUTPUT HEADING -> the flag names in one section, space-joined.
# HEADING must be followed by end-of-line or a space, so `SUBCOMMAND  x` does
# not also match `SUBCOMMAND  xy`; `FLAGS  (` is the main parser.
flags_in() {
  awk -v s="$2" '
    /^(FLAGS|SUBCOMMAND|UNTRACED|NOTES)  / {
      f = ($0 == s || index($0, s " ") == 1 || (s ~ /\($/ && index($0, s) == 1)); next }
    f && /^  -/ { sub(/,$/, "", $1); out = out (out ? " " : "") $1 }
    END { print out }' <<<"$1"
}

# help_of OUTPUT FLAG -> the help text printed under one flag.
help_of() {
  awk -v want="$2" '
    /^(FLAGS|SUBCOMMAND|UNTRACED|NOTES)  / { cur = ""; next }
    /^  -/ { cur = $1; sub(/,$/, "", cur); next }
    /^      / && cur == want { sub(/^ +/, ""); print }' <<<"$1"
}

eq() { [ "$1" = "$2" ] && echo true || echo false; }
# The heading for flags added through a receiver named `p`; backticks literal.
untraced_p="UNTRACED  flags added through \`p\`"
has() { grep -qF -- "$2" <<<"$1" && echo true || echo false; }
lacks() { grep -qF -- "$2" <<<"$1" && echo false || echo true; }

# -- M: a name bound to differing values is NAMED, not guessed (#199 F1) -----
# `constants` was built first-wins over `ast.walk`, so the text printed under
# --thing depended only on which function was defined first, with no marker.
# Both orderings are asserted: a first-wins map passes one of them by
# construction. --same is the other side (bound twice to the SAME string, so
# unambiguous); --later is a string once and a call elsewhere; --desc reads a
# parameter that shadows a module constant.
m_decoy='
def other():
    MSG = "WRONG TEXT from the other function"
    SAME = "one string, bound twice"
    LATER = compute()
    return MSG, SAME, LATER

DESC = "a module default that the parameter below shadows"

def add_desc(parser, DESC):
    parser.add_argument("--desc", help=DESC)
'
m_main='
def main():
    MSG = "the real help for --thing"
    SAME = "one string, bound twice"
    LATER = "a string here, a call in other()"
    ap = argparse.ArgumentParser()
    ap.add_argument("--thing", help=MSG)
    ap.add_argument("--same", help=SAME)
    ap.add_argument("--later", help=LATER)
'
printf 'import argparse\n%s%s' "$m_decoy" "$m_main" >"$tmp/scope/scripts/m_decoy_first.py"
printf 'import argparse\n%s%s' "$m_main" "$m_decoy" >"$tmp/scope/scripts/m_main_first.py"
for order in decoy_first main_first; do
  out="$(scan "m_$order.py")"
  thing="$(help_of "$out" --thing)"
  assert "M[$order]: --thing prints neither function's string" \
    "$([ "$(lacks "$thing" "WRONG TEXT")$(lacks "$thing" "the real help")" = truetrue ] && echo true || echo false)"
  assert "M[$order]: --thing is named by the marker instead" "$(has "$thing" "not a literal")"
  assert "M[$order]: a name bound twice to ONE string still resolves" \
    "$(has "$(help_of "$out" --same)" "one string, bound twice")"
  assert "M[$order]: a name that is a string once and a call elsewhere is named" \
    "$(has "$(help_of "$out" --later)" "not a literal")"
  assert "M[$order]: a parameter shadowing a module constant is not the constant" \
    "$(lacks "$(help_of "$out" --desc)" "module default")"
  assert "M[$order]: and is named by the marker" \
    "$(has "$(help_of "$out" --desc)" "not a literal")"
done

# -- N: a name inside an f-string or a concatenation resolves (#199 F3) -------
# `help=BLURB` resolved; the same name one level down printed `{BLURB}`, the
# placeholder a genuine runtime value gets. `{RUNTIME}` stays one, which is
# the other side, and a conversion (`!r`) changes the text argparse prints, so
# it is left visibly unresolved rather than substituted without its quotes.
cat >"$tmp/scope/scripts/n_inline.py" <<'PYEOF'
import argparse
BLURB = "the text that must survive"
RUNTIME = compute()
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--f", help=f"see {BLURB}, not {RUNTIME}")
    ap.add_argument("--c", help="see " + BLURB)
    ap.add_argument("--n", help="see " + BLURB + " now")
    ap.add_argument("--r", help=f"see {BLURB!r}")
    sub = ap.add_subparsers()
    sub.add_parser("s", help=f"about {BLURB}")
PYEOF
out="$(scan n_inline.py)"
assert "N: a name in an f-string is substituted, a runtime value is not" \
  "$(eq "$(help_of "$out" --f)" "see the text that must survive, not {RUNTIME}")"
assert "N: a name on the right of a + is substituted" \
  "$(eq "$(help_of "$out" --c)" "see the text that must survive")"
assert "N: a name in the middle of a chained + is substituted" \
  "$(eq "$(help_of "$out" --n)" "see the text that must survive now")"
assert "N: a !r conversion is left visible, not substituted without quotes" \
  "$(eq "$(help_of "$out" --r)" "see {BLURB}")"
assert "N: a subcommand's f-string help substitutes too" \
  "$(has "$out" "SUBCOMMAND  s  -- about the text that must survive")"

# -- O: every rebinding form forgets the old parser (#199 F2) -----------------
# The forget used to fire only for an Assign of a Call, so each form below left
# `p` mapped to `one()`'s subcommand -- and a mapping OUTRANKS the cursor, so
# --b printed under `x`, which does not accept it. Two-sided: --b must leave
# `x` AND still be listed, under a marked heading; dropping it would trade the
# mis-report for an under-report. There is deliberately no ArgumentParser() in
# two(): that resets the cursor, the other way to land somewhere plausible.
o_case() {
  local id="$1" rebind="$2" use="$3"
  printf 'import argparse\ndef one():\n    ap = argparse.ArgumentParser()\n    sub = ap.add_subparsers()\n    p = sub.add_parser("x")\n    p.add_argument("--a")\ndef two(ap2, cfg, others):\n    %s\n    %s\n' \
    "$rebind" "$use" >"$tmp/scope/scripts/o_$id.py"
  local out
  out="$(scan "o_$id.py")"
  assert "O[$id]: --b is not filed under x through a stale mapping" \
    "$(eq "$(flags_in "$out" "SUBCOMMAND  x")" "--a")"
  assert "O[$id]: --b is listed under an UNTRACED heading naming \`p\`" \
    "$(eq "$(flags_in "$out" "$untraced_p")" "--b")"
}
o_case name "p = ap2" "p.add_argument('--b')"
o_case subscript "p = cfg['parser']" "p.add_argument('--b')"
o_case annassign "p: Parser = make()" "p.add_argument('--b')"
o_case for "for p in others:" "    p.add_argument('--b')"
o_case with "with make() as p:" "    p.add_argument('--b')"
o_case walrus "(p := make())" "p.add_argument('--b')"

# The same rebinding INSIDE one function. The forget alone holds this one: the
# scope restore below cannot, and the old code handed the forgotten `p` to the
# cursor, which still pointed at `x`.
cat >"$tmp/scope/scripts/o_same_function.py" <<'PYEOF'
import argparse
def main(ap2):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers()
    p = sub.add_parser("x")
    p.add_argument("--a")
    p = build_somehow(ap2)
    p.add_argument("--b")
PYEOF
out="$(scan o_same_function.py)"
assert "O[same-function]: a call rebinding p in one function does not file --b under x" \
  "$(eq "$(flags_in "$out" "SUBCOMMAND  x")" "--a")"

# -- P: flags added through a PARAMETER are marked, not guessed (#199 F2) -----
# The ordinary shared-flags helper. A forgotten receiver used to fall back to
# the source-order cursor -- here `y`, the last subcommand bound -- so
# --verbose printed under `y` and was missing from `x`, both confidently.
cat >"$tmp/scope/scripts/p_param.py" <<'PYEOF'
import argparse
def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers()
    p = sub.add_parser("x")
    p.add_argument("--a")
    _add_common(p)
    p = sub.add_parser("y")
    p.add_argument("--c")
    _add_common(p)
def _add_common(p):
    p.add_argument("--verbose", help="say more")
PYEOF
out="$(scan p_param.py)"
assert "P: x keeps only its own flag" "$(eq "$(flags_in "$out" "SUBCOMMAND  x")" "--a")"
assert "P: --verbose is not filed under y, the last subcommand bound" \
  "$(eq "$(flags_in "$out" "SUBCOMMAND  y")" "--c")"
assert "P: --verbose is listed under a marked UNTRACED heading" \
  "$(eq "$(flags_in "$out" "$untraced_p")" "--verbose")"
untraced_heading="$(grep -F 'UNTRACED' <<<"$out" | head -1)"
assert "P: the heading names the helper the parameter belongs to" \
  "$(has "$untraced_heading" "a parameter of _add_common()")"
assert "P: the heading does not read as a subcommand" "$(lacks "$untraced_heading" "SUBCOMMAND")"
assert "P: the flag's help text still prints" "$(eq "$(help_of "$out" --verbose)" "say more")"

# -- Q: a function's bindings end with it (#223 follow-up, 3bb18fb) -----------
# Forgetting a NESTED helper's parameter module-wide reached back into main():
# --run-only, added through main's own `p` after the def, moved to UNTRACED and
# `run` printed "(no flags of its own)". Both sides: --verbose stays untraced.
cat >"$tmp/scope/scripts/q_nested.py" <<'PYEOF'
import argparse
def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers()
    p = sub.add_parser("run")
    def _common(p):
        p.add_argument("--verbose")
    _common(p)
    p.add_argument("--run-only")
PYEOF
out="$(scan q_nested.py)"
assert "Q: a nested helper's parameter does not untrace main's p" \
  "$(eq "$(flags_in "$out" "SUBCOMMAND  run")" "--run-only")"
assert "Q: and the helper's own flag is still marked UNTRACED" \
  "$(eq "$(flags_in "$out" "$untraced_p")" "--verbose")"

# -- R: an ANNOTATED parser construction is traced (#223 follow-up, 3bb18fb) --
# `ap: argparse.ArgumentParser = argparse.ArgumentParser()` is not an
# ast.Assign. Before the port the annotated add_parser was not registered at
# all; after a forget-every-binding port without this, every flag of an
# annotated parser would be listed UNTRACED.
cat >"$tmp/scope/scripts/r_annotated.py" <<'PYEOF'
import argparse
def main():
    ap: argparse.ArgumentParser = argparse.ArgumentParser()
    ap.add_argument("--top")
    sub = ap.add_subparsers()
    p: argparse.ArgumentParser = sub.add_parser("x")
    p.add_argument("--b")
PYEOF
out="$(scan r_annotated.py)"
assert "R: an annotated ArgumentParser() is the main parser" \
  "$(eq "$(flags_in "$out" "FLAGS  (")" "--top")"
assert "R: an annotated add_parser registers its subcommand and its flag" \
  "$(eq "$(flags_in "$out" "SUBCOMMAND  x")" "--b")"
assert "R: nothing is marked UNTRACED" "$(lacks "$out" "UNTRACED")"

# -- S: an argument group follows the parser it was made FROM -----------------
# A group is a recognised construction. Without that, forgetting every binding
# would move each `g = ap.add_mutually_exclusive_group()` flag into UNTRACED.
# The second fixture is the one the cursor cannot pass: it has moved on to `y`
# before `p`'s group is made, and `eg` is made from the main parser after both
# subcommands are bound.
cat >"$tmp/scope/scripts/s_groups.py" <<'PYEOF'
import argparse
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--a")
    sub = ap.add_subparsers()
    p = sub.add_parser("x")
    sub.add_parser("later")
    eg = p.add_argument_group("tuning")
    eg.add_argument("--b")
PYEOF
out="$(scan s_groups.py)"
assert "S: a mutually exclusive group's flag stays on the main parser" \
  "$(eq "$(flags_in "$out" "FLAGS  (")" "--top --a")"
assert "S: an argument group's flag stays on its subcommand" \
  "$(eq "$(flags_in "$out" "SUBCOMMAND  x")" "--b")"
assert "S: nothing is marked UNTRACED" "$(lacks "$out" "UNTRACED")"
cat >"$tmp/scope/scripts/s_receiver.py" <<'PYEOF'
import argparse
def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers()
    p = sub.add_parser("x")
    q = sub.add_parser("y")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--a")
    eg = ap.add_argument_group("tuning")
    eg.add_argument("--top")
    q.add_argument("--c")
PYEOF
out="$(scan s_receiver.py)"
assert "S: a group made from p files under x, not under the cursor's y" \
  "$(eq "$(flags_in "$out" "SUBCOMMAND  x")" "--a")"
assert "S: a group made from the main parser files under it" \
  "$(eq "$(flags_in "$out" "FLAGS  (")" "--top")"
assert "S: y keeps only its own flag" "$(eq "$(flags_in "$out" "SUBCOMMAND  y")" "--c")"

# -- T: a refused subcommand help= name is NAMED (#223 follow-up, 3bb18fb) ----
# The stricter constants map refuses a name bound to two strings, and
# add_parser had no marker to fall through to, so the subcommand printed with
# no line at all. Before the port it printed the OTHER function's text.
cat >"$tmp/scope/scripts/t_subhelp.py" <<'PYEOF'
import argparse
def other():
    HELP = "other text"
def main():
    HELP = "run things"
    OK = "the one string"
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers()
    sub.add_parser("run", help=HELP)
    sub.add_parser("ok", help=OK)
PYEOF
out="$(scan t_subhelp.py)"
run_heading="$(grep -F 'SUBCOMMAND  run' <<<"$out")"
assert "T: a refused subcommand help name does not print another function's text" \
  "$(lacks "$run_heading" "other text")"
assert "T: it is named by the marker instead of dropped" \
  "$(has "$run_heading" "help is \`HELP\`, which is not a literal")"
assert "T: a resolvable subcommand help name still resolves" \
  "$(has "$out" "SUBCOMMAND  ok  -- the one string")"

# -- U: the [private] attribute alone hides a recipe (#204) -------------------
# Recipe.private is a disjunction and the fixtures above cover only its
# underscore half, so an underscore-only implementation passes every other
# assertion here. Two-sided: an inert `private` fails the second.
mkdir -p "$tmp/priv"
cat >"$tmp/priv/justfile" <<'JUSTFILE'
# Hidden by the attribute and by nothing else.
[private]
deploy:
    @echo hi

# Listed.
visible:
    @echo hi
JUSTFILE
priv_out="$(cd "$tmp/priv" && python3 "$helper" --audit 2>&1)"
assert "U: the [private] attribute alone makes a recipe private" \
  "$(has "$priv_out" "2 recipe(s), 1 listed")"
if command -v just >/dev/null 2>&1; then
  priv_summary="$(cd "$tmp/priv" && just --summary 2>/dev/null)"
  assert "U: just agrees (control): only visible is listed" "$(eq "$priv_summary" "visible")"
fi

# -- V: a binding is forgotten only where it runs -----------------------------
# Two guards in the forget, each pinned. A comprehension's target is local to
# it, so `[p for p in ...]` must not untrace main's p; and a statement's
# nested BLOCKS are visited in source order, so an `if` whose body rebinds p
# AFTER using it must not forget p before the use.
cat >"$tmp/scope/scripts/v_nested.py" <<'PYEOF'
import argparse
def main(other):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers()
    p = sub.add_parser("x")
    names = [p for p in ("a", "b")]
    p.add_argument("--a")
    if names:
        p.add_argument("--b")
        p = other
PYEOF
out="$(scan v_nested.py)"
assert "V: a comprehension target and a later rebinding leave x's flags in place" \
  "$(eq "$(flags_in "$out" "SUBCOMMAND  x")" "--a --b")"
assert "V: nothing is marked UNTRACED" "$(lacks "$out" "UNTRACED")"

# -- W: a recipe that runs a shell script gets no argparse --help hint --------
# print_flags reports a .sh as "not argparse" and returns 0, and show() then
# went on to print "Argparse's own text ... just <recipe> --help" -- a command
# that does not reach any argparse at all. Found by running this helper over
# lab/justfile in laurigates/comfyui-nodes, whose `torch-update` runs a .sh.
mkdir -p "$tmp/shrecipe"
cat >"$tmp/shrecipe/justfile" <<'JUSTFILE'
# Reinstall the stack.
reinstall:
    "{{source_directory()}}/update_stack.sh"
JUSTFILE
printf '#!/usr/bin/env bash\necho hi\n' >"$tmp/shrecipe/update_stack.sh"
sh_recipe_out="$(cd "$tmp/shrecipe" && python3 "$helper" reinstall 2>&1)"
assert "W: the recipe's shell script is found and named" \
  "$(has "$sh_recipe_out" "update_stack.sh is a shell script, not argparse")"
assert "W: no argparse --help hint is printed for a shell script" \
  "$(lacks "$sh_recipe_out" "Argparse's own text")"

# ---------------------------------------------------------------- summary
echo "PASSED=$pass_count FAILED=$fail_count"
[ "$fail_count" -eq 0 ] || exit 1
echo "STATUS=OK"

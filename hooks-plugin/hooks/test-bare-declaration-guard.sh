#!/usr/bin/env bash
# shellcheck disable=SC2016   # fixtures are shell source: their $names must stay unexpanded
# Regression tests for bare-declaration-guard.sh
#
# Run: bash hooks-plugin/hooks/test-bare-declaration-guard.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# The hook blocks with exit 2 and a message on stderr, and allows with exit 0
# and no output, so assertions read the exit code and stderr.
#
# Covers:
#   - The fixture table: each line is fed to the hook as a Write to a shell
#     file, and the verdict must match the expectation.
#   - The same table against the real shells. A line the hook blocks must
#     print an exported canary when run with its variables unset; a line the
#     hook allows must not. This is what ties the hook's pattern to what the
#     shells do, so a pattern change that drifts from the behaviour fails here.
#     bash is always run; zsh is run when installed, and skipped with a note
#     when not.
#   - The fixes the block message prints are themselves allowed, or a block
#     becomes a retry loop.
#   - Which files count as shell files: extension, rc-file name, chezmoi
#     source name, shebang in the written content, shebang of the file on disk.
#   - Only added lines are checked: a line already in an Edit's old_string or
#     in the file a Write replaces is not blocked.
#   - The `# allow-bare-decl` comment, the opt-out variable, other tools, and
#     input the hook cannot parse.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/bare-declaration-guard.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "$WORK" ] || { echo "mktemp -d produced no dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

ok()  { printf "  PASS: %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL + 1)); }

write_json() {      # $1 file_path, $2 content
    jq -nc --arg p "$1" --arg c "$2" \
        '{tool_name:"Write",tool_input:{file_path:$p,content:$c},session_id:"t"}'
}
edit_json() {       # $1 file_path, $2 old_string, $3 new_string
    jq -nc --arg p "$1" --arg o "$2" --arg n "$3" \
        '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n},session_id:"t"}'
}

# run_hook <json> [VAR=value] — sets RC (exit code) and ERR (stderr).
run_hook() {
    if [ -n "${2:-}" ]; then
        ERR=$(env "$2" bash "$HOOK" 2>&1 >/dev/null <<<"$1"); RC=$?
    else
        ERR=$(bash "$HOOK" 2>&1 >/dev/null <<<"$1"); RC=$?
    fi
}
assert_blocks() {   # $1 desc, $2 json [, $3 VAR=value]
    run_hook "$2" "${3:-}"
    if [ "$RC" -eq 2 ] && [ -n "$ERR" ]; then ok "$1"; else bad "$1 (expected exit 2 with a message, got exit $RC)"; fi
}
assert_allows() {   # $1 desc, $2 json [, $3 VAR=value]
    run_hook "$2" "${3:-}"
    if [ "$RC" -eq 0 ] && [ -z "$ERR" ]; then ok "$1"; else bad "$1 (expected a silent exit 0, got exit $RC: ${ERR%%$'\n'*})"; fi
}

SH="$WORK/script.sh"

# ---------------------------------------------------------------------------
# Fixture table: <expect>|<truth>|<line>
#   expect  B = the hook blocks the line, A = it allows it
#   truth   which shells the line is run in to confirm the expectation:
#             both  bash and zsh behave the same
#             zsh   only zsh prints the listing (bash `local` with no
#                   arguments prints nothing, but a .sh file can be sourced
#                   by zsh, so the hook blocks `local` in any shell file)
#             none  not run (the line carries the allow comment)
# The quoted-array row assigns an empty array first: zsh expands "${names[@]}"
# of an UNSET name to one empty word (an error), and only an empty array to no
# words at all.
# ---------------------------------------------------------------------------
FIXTURES=(
    'B|zsh|local $_GH_COLORS; _gh_palette 1'
    'B|zsh|local $names'
    'B|zsh|local $a $b'
    'B|zsh|f2() { local $nothing; }; f2'
    'B|both|typeset $names'
    'B|both|declare $names'
    'B|both|export $names'
    'B|both|typeset -x $names'
    'B|both|declare -p $names'
    'B|both|export ${names}'
    'B|both|export $(grep -v "^#" .env 2>/dev/null | xargs)'
    'B|both|export `cat missing-file 2>/dev/null`'
    'B|both|names=(); typeset "${names[@]}"'
    'B|both|export "$@"'
    'B|both|if true; then export $v; fi'
    'B|both|true && declare $names'
    'B|both|export $names # the list comes from the caller'
    'A|both|local green red yellow; true'
    'A|both|local name=$value'
    'A|both|export PATH=$PATH:/opt/bin'
    'A|both|local "$name"'
    'A|both|export "$name"'
    'A|both|typeset "${name}"'
    'A|both|local $x=1'
    'A|both|export $key=$value'
    'A|both|local first $rest'
    'A|both|typeset ${names:-fallback}'
    'A|both|typeset "${names[@]:?names is empty}"'
    'A|both|typeset "${name:?name is empty}"'
    'A|both|# local $names'
    'A|both|true # usage: source lib.sh; export $names'
    'A|both|true # set the flag, then export $names'
    'A|both|echo "$names"'
    'A|both|readonly_names=$names'
    'A|none|export $names # allow-bare-decl'
)

echo "Fixture table: hook verdict"
for row in "${FIXTURES[@]}"; do
    expect=${row%%|*}; rest=${row#*|}; line=${rest#*|}
    json=$(write_json "$SH" "$(printf '#!/usr/bin/env bash\n%s\n' "$line")")
    if [ "$expect" = B ]; then
        assert_blocks "blocks: $line" "$json"
    else
        assert_allows "allows: $line" "$json"
    fi
done

# ---------------------------------------------------------------------------
# Fixture table against the real shells
# ---------------------------------------------------------------------------
# prints_canary <shell> <line> — 0 when running the line prints the canary.
prints_canary() {
    local out
    case "$1" in
        bash) out=$(cd "$WORK" && GUARD_TEST_CANARY=canary-value-7f3a bash --norc --noprofile -c \
                  "export GUARD_TEST_CANARY; f() { $2
}; f" 2>&1) ;;
        zsh)  out=$(cd "$WORK" && GUARD_TEST_CANARY=canary-value-7f3a zsh -f -c \
                  "export GUARD_TEST_CANARY; f() { $2
}; f" 2>&1) ;;
    esac
    grep -qF canary-value-7f3a <<<"$out"
}

echo ""
echo "Fixture table: what the shells do"
HAVE_ZSH=0
command -v zsh >/dev/null 2>&1 && HAVE_ZSH=1
[ "$HAVE_ZSH" -eq 1 ] || echo "  NOTE: zsh is not installed; the zsh column is not run"

# Control: the method can see a listing and can see its absence.
if prints_canary bash 'export'; then ok "control: a literal bare export prints the canary in bash"; else bad "control: a literal bare export prints the canary in bash"; fi
if prints_canary bash 'true'; then bad "control: a no-op prints no canary in bash"; else ok "control: a no-op prints no canary in bash"; fi

for row in "${FIXTURES[@]}"; do
    expect=${row%%|*}; rest=${row#*|}; truth=${rest%%|*}; line=${rest#*|}
    [ "$truth" = none ] && continue
    for shell in bash zsh; do
        [ "$shell" = zsh ] && [ "$HAVE_ZSH" -eq 0 ] && continue
        want=$expect
        # A zsh-only listing: in bash the line prints nothing.
        [ "$truth" = zsh ] && [ "$shell" = bash ] && want=A
        if prints_canary "$shell" "$line"; then got=B; else got=A; fi
        if [ "$got" = "$want" ]; then
            ok "$shell $( [ "$want" = B ] && echo 'lists parameters' || echo 'prints no listing' ): $line"
        else
            bad "$shell: expected $( [ "$want" = B ] && echo 'a listing' || echo 'no listing' ) from: $line"
        fi
    done
done

# ---------------------------------------------------------------------------
echo ""
echo "The block message"
# ---------------------------------------------------------------------------
run_hook "$(write_json "$SH" "$(printf '#!/usr/bin/env bash\nlocal $names\n')")"
case "$ERR" in *'local $names'*) ok "the message quotes the offending line" ;; *) bad "the message quotes the offending line" ;; esac
case "$ERR" in *'allow-bare-decl'*) ok "the message names the allow comment" ;; *) bad "the message names the allow comment" ;; esac
case "$ERR" in *'CLAUDE_HOOKS_DISABLE_BARE_DECLARATION_GUARD=1 '*) bad "the message does not offer the opt-out as an inline prefix" ;; *) ok "the message does not offer the opt-out as an inline prefix" ;; esac

# The fixes it prints are the lines indented by four spaces. Each must pass
# the hook, or following the message leads straight back to a block.
FIXES=$(grep -E '^    [a-z]' <<<"$ERR" || true)
if [ -n "$FIXES" ]; then
    ok "the message prints suggested fixes"
    while IFS= read -r fix; do
        fix=${fix#    }
        assert_allows "suggested fix is allowed: $fix" "$(write_json "$SH" "$(printf '#!/usr/bin/env bash\n%s\n' "$fix")")"
    done <<<"$FIXES"
else
    bad "the message prints suggested fixes"
fi

# ---------------------------------------------------------------------------
echo ""
echo "Which files are checked"
# ---------------------------------------------------------------------------
BODY='export $names'
for name in lib.sh lib.bash wrappers.zsh job.ksh .zshrc .zshenv .bashrc .bash_profile .profile \
            dot_zshrc.tmpl private_dot_zshenv executable_setup.sh.tmpl; do
    assert_blocks "shell file by name: $name" "$(write_json "$WORK/$name" "$BODY")"
done
for name in notes.md tool.py data.json Makefile shell.nix; do
    assert_allows "not a shell file: $name" "$(write_json "$WORK/$name" "$BODY")"
done
assert_blocks "Write: no extension, bash shebang in the content" \
    "$(write_json "$WORK/tool" "$(printf '#!/usr/bin/env bash\n%s\n' "$BODY")")"
assert_blocks "Write: no extension, zsh shebang in the content" \
    "$(write_json "$WORK/tool" "$(printf '#!/bin/zsh\n%s\n' "$BODY")")"
assert_blocks "Write: no extension, sh shebang in the content" \
    "$(write_json "$WORK/tool" "$(printf '#!/bin/sh\n%s\n' "$BODY")")"
assert_allows "Write: no extension, python shebang in the content" \
    "$(write_json "$WORK/tool" "$(printf '#!/usr/bin/env python3\n%s\n' "$BODY")")"
assert_allows "Write: no extension, no shebang" "$(write_json "$WORK/tool" "$BODY")"

printf '#!/usr/bin/env bash\necho hello\n' > "$WORK/ondisk"
assert_blocks "Edit: no extension, the file on disk has a bash shebang" \
    "$(edit_json "$WORK/ondisk" 'echo hello' "$(printf 'echo hello\n%s' "$BODY")")"
printf '#!/usr/bin/env python3\nprint(1)\n' > "$WORK/ondisk-py"
assert_allows "Edit: no extension, the file on disk has a python shebang" \
    "$(edit_json "$WORK/ondisk-py" 'print(1)' "$(printf 'print(1)\n%s' "$BODY")")"
assert_allows "Edit: no extension, the file does not exist" \
    "$(edit_json "$WORK/absent" 'x' "$BODY")"

# ---------------------------------------------------------------------------
echo ""
echo "Only added lines are checked"
# ---------------------------------------------------------------------------
assert_blocks "Edit adds the line" \
    "$(edit_json "$SH" 'echo start' "$(printf 'echo start\nexport $names')")"
assert_allows "Edit keeps a line that old_string already had" \
    "$(edit_json "$SH" "$(printf 'export $names\necho start')" "$(printf 'export $names\necho begin')")"
assert_allows "Edit keeps the line with different indentation" \
    "$(edit_json "$SH" "$(printf 'export $names\necho start')" "$(printf '    export $names\necho begin')")"
assert_blocks "Edit keeps one such line and adds another" \
    "$(edit_json "$SH" 'export $names' "$(printf 'export $names\ntypeset $others')")"

printf '#!/usr/bin/env bash\nexport $names\necho old\n' > "$WORK/existing.sh"
assert_allows "Write keeps a line the file on disk already has" \
    "$(write_json "$WORK/existing.sh" "$(printf '#!/usr/bin/env bash\nexport $names\necho new\n')")"
assert_blocks "Write keeps that line and adds another" \
    "$(write_json "$WORK/existing.sh" "$(printf '#!/usr/bin/env bash\nexport $names\ntypeset $others\n')")"
run_hook "$(write_json "$WORK/existing.sh" "$(printf '#!/usr/bin/env bash\nexport $names\ntypeset $others\n')")"
case "$ERR" in *'typeset $others'*) ok "the message names the added line" ;; *) bad "the message names the added line" ;; esac
case "$ERR" in *'export $names'*) bad "the message leaves out the line that was already there" ;; *) ok "the message leaves out the line that was already there" ;; esac

# ---------------------------------------------------------------------------
echo ""
echo "The allow comment"
# ---------------------------------------------------------------------------
assert_allows "allow comment on the same line" \
    "$(write_json "$SH" 'export $names  # allow-bare-decl: names is checked above')"
assert_allows "allow comment on the line above" \
    "$(write_json "$SH" "$(printf '# allow-bare-decl: names is checked above\nexport $names\n')")"
assert_blocks "allow comment two lines above does not apply" \
    "$(write_json "$SH" "$(printf '# allow-bare-decl\necho between\nexport $names\n')")"
assert_allows "a comment line that reads like a statement is not code" \
    "$(write_json "$SH" "$(printf '# usage: source lib.sh; export $names\n#   then export $names\n')")"
assert_blocks "the words outside a comment do not allow the line" \
    "$(write_json "$SH" "$(printf 'allow-bare-decl=1\nexport $names\n')")"
assert_blocks "an allowed line does not excuse another line" \
    "$(write_json "$SH" "$(printf 'export $names  # allow-bare-decl\ntypeset $others\n')")"

# ---------------------------------------------------------------------------
echo ""
echo "Opt-out, other tools, unusable input"
# ---------------------------------------------------------------------------
J=$(write_json "$SH" 'export $names')
assert_blocks "control: this input blocks" "$J"
assert_allows "CLAUDE_HOOKS_DISABLE_BARE_DECLARATION_GUARD=1 in the hook's environment" "$J" \
    "CLAUDE_HOOKS_DISABLE_BARE_DECLARATION_GUARD=1"
assert_allows "Read is not checked" \
    "$(jq -nc --arg p "$SH" '{tool_name:"Read",tool_input:{file_path:$p}}')"
assert_allows "Bash is not checked" \
    "$(jq -nc '{tool_name:"Bash",tool_input:{command:"export $names"}}')"
assert_allows "Write with no content" \
    "$(jq -nc --arg p "$SH" '{tool_name:"Write",tool_input:{file_path:$p}}')"
assert_allows "input that is not JSON" 'not json at all'
assert_allows "tool_input that is not an object" '{"tool_name":"Write","tool_input":"export $names"}'
assert_allows "empty input" ''

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

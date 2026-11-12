#!/usr/bin/env bash
# PreToolUse hook — blocks an Edit or Write that adds, to a shell file, a
# declaration whose arguments are all expansions.
#
# `local`, `typeset`, `declare` and `export` list parameters when they run with
# no arguments. A declaration whose every argument is an expansion becomes
# exactly that when the expansions are empty:
#
#   local $names                      # names unset: a bare `local`
#   export $(grep -v '^#' .env | xargs)   # .env missing: a bare `export`
#   typeset "${names[@]}"             # empty array: a bare `typeset`
#
# The listing goes to stdout, so it lands in whatever captures the output: an
# agent transcript, a CI log, a redirected file. With exported API tokens in
# the environment it is a credential leak. Measured in bash 5.2 and zsh 5.9
# with an exported canary variable: `typeset`, `declare` and `export` print it
# in both shells, `local` prints it in zsh (bash's bare `local` prints
# nothing). A .sh file can be sourced by zsh, so `local` is checked in every
# shell file. hooks-plugin/hooks/test-bare-declaration-guard.sh runs each
# fixture in the real shells, so the pattern below cannot drift from them.
#
# What is checked: the text an Edit or Write ADDS (new_string, or content). A
# line that old_string or the file on disk already holds is not blocked, so
# editing near an existing instance still works.
#
# What is not flagged, because the statement cannot run bare:
#   local name=$value        an assignment
#   local first $rest        a literal name among the arguments
#   export "$name"           a quoted single value: empty is an error
#   typeset ${names:-a b}    a non-empty default
#   typeset "${names:?msg}"  an empty value aborts
#
# Escape hatch: a `# allow-bare-decl` comment on the line, or alone on the
# line above. Unlike the opt-out variable it is meant for the agent: it puts
# the claim "this cannot expand to nothing" in the source, where a reviewer
# reads it.
#
# Not covered: text written through Bash (a heredoc, `tee`, `sed`), which
# Edit/Write hooks never see; shell inside non-shell files (justfile and
# Makefile recipes, workflow `run:` blocks); `readonly`, `integer` and `float`,
# whose bare forms list only their own kind of parameter. A match inside a
# string or a heredoc body is a false positive; the allow comment or a reword
# clears it.
#
# Toggle: a human operator can export CLAUDE_HOOKS_DISABLE_BARE_DECLARATION_GUARD=1
# in their shell environment to skip this hook. A hook runs as its own process,
# so an inline prefix on a command does not reach it.
#
# Matches: Edit, Write

set -euo pipefail

[ "${CLAUDE_HOOKS_DISABLE_BARE_DECLARATION_GUARD:-}" = "1" ] && exit 0

# Without jq the input cannot be read. Exit 0: this hook is not registered
# fail-closed, and a block on every Edit would be worse than a missed check.
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
jq -e 'type == "object" and ((.tool_input // {}) | type == "object")' >/dev/null 2>&1 <<<"$INPUT" || exit 0

TOOL_NAME=$(jq -r '.tool_name // empty' <<<"$INPUT")
FILE_PATH=$(jq -r '.tool_input.file_path // empty' <<<"$INPUT")

case "$TOOL_NAME" in
    Write)
        ADDED=$(jq -r '.tool_input.content // empty' <<<"$INPUT")
        EXISTING=""
        if [ -f "$FILE_PATH" ] && [ -r "$FILE_PATH" ]; then
            EXISTING=$(cat -- "$FILE_PATH")
        fi
        ;;
    Edit)
        ADDED=$(jq -r '.tool_input.new_string // empty' <<<"$INPUT")
        EXISTING=$(jq -r '.tool_input.old_string // empty' <<<"$INPUT")
        ;;
    *)
        exit 0
        ;;
esac

if [ -z "$FILE_PATH" ] || [ -z "$ADDED" ]; then
    exit 0
fi

# Cheap exit before any per-line work.
grep -Eq '(local|typeset|declare|export)' <<<"$ADDED" || exit 0

block() {
    echo "$1" >&2
    exit 2
}

SHEBANG_RE='^#!.*[/[:space:]](ba|z|k|da|a)?sh([[:space:]]|$)'

# is_shell_file — by name first, then by shebang. A chezmoi source name is
# read as the target name it produces (dot_zshrc.tmpl is .zshrc).
is_shell_file() {
    local base first=""
    base=${FILE_PATH##*/}
    base=${base%.tmpl}
    case "$base" in
        *dot_*) base=".${base##*dot_}" ;;
    esac
    case "$base" in
        *.sh | *.bash | *.zsh | *.ksh) return 0 ;;
        .zshrc | .zshenv | .zprofile | .zlogin | .zlogout) return 0 ;;
        .bashrc | .bash_profile | .bash_login | .bash_logout | .bash_aliases) return 0 ;;
        .profile | .kshrc) return 0 ;;
    esac
    if [ "$TOOL_NAME" = "Write" ]; then
        first=${ADDED%%$'\n'*}
    elif [ -f "$FILE_PATH" ] && [ -r "$FILE_PATH" ]; then
        IFS= read -r first <"$FILE_PATH" || true
    fi
    [[ "$first" =~ $SHEBANG_RE ]]
}

is_shell_file || exit 0

# ── The pattern ─────────────────────────────────────────────────────────────
# One argument that can expand to nothing:
NAME='[A-Za-z_][A-Za-z0-9_]*'
EXP="\\\$${NAME}(\\[[^]]*\\])?"                          # $names  $names[2]
EXP="${EXP}|"'\$[@*]'                                    # $@  $*
EXP="${EXP}|"'\$\{[^}]*\}'                               # ${names}
EXP="${EXP}|"'\$\(([^()]|\([^()]*\))*\)'                 # $(cmd)  $(cmd (x))
# shellcheck disable=SC2016  # a regex for a literal backtick pair, not an expansion
EXP="${EXP}|"'`[^`]*`'                                   # `cmd`
EXP="${EXP}|"'"\$@"'                                     # "$@"
EXP="${EXP}|"'"\$\{[^}"]*\[@\][^}"]*\}"'                 # "${names[@]}"
EXP="${EXP}|"'"\$\{\([^)"]*@[^)"]*\)[^}"]*\}"'           # "${(@)names}"
# A statement start, the builtin, optional flags, then ONLY such arguments up
# to the end of the statement.
LEAD='(^|[;&|({]|[[:space:]](then|do|else))[[:space:]]*'
BARE_RE="${LEAD}(local|typeset|declare|export)([[:space:]]+[-+][A-Za-z]+)*([[:space:]]+(${EXP}))+[[:space:]]*(\$|[;&|)}])"
# An argument that cannot be empty, or aborts when it is.
DEFAULT_RE='\$\{[^}]*:[-=][^}]+\}'
ABORT_RE='\$\{[^}]*:\?[^}]*\}'
ALLOW_RE='#.*allow-bare-decl'
ALLOW_ABOVE_RE='^[[:space:]]*#.*allow-bare-decl'

trim() {
    local s=$1
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

EXISTING_TRIMMED=""
if [ -n "$EXISTING" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        EXISTING_TRIMMED+="$(trim "$line")"$'\n'
    done <<<"$EXISTING"
fi

FOUND=""
prev=""
while IFS= read -r line || [ -n "$line" ]; do
    above=$prev
    prev=$line

    # Comment lines hold no code. A trailing comment is dropped for matching
    # only; the allow comment is read from the whole line.
    code=$line
    if [[ "$code" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    if [[ "$code" =~ ^(.*[^[:space:]])[[:space:]]+#.*$ ]]; then
        code=${BASH_REMATCH[1]}
    fi

    if ! [[ "$code" =~ $BARE_RE ]]; then
        continue
    fi
    statement=${BASH_REMATCH[0]}
    if [[ "$statement" =~ $DEFAULT_RE ]] || [[ "$statement" =~ $ABORT_RE ]]; then
        continue
    fi
    if [[ "$line" =~ $ALLOW_RE ]] || [[ "$above" =~ $ALLOW_ABOVE_RE ]]; then
        continue
    fi
    trimmed=$(trim "$line")
    if [ -n "$EXISTING_TRIMMED" ] && grep -Fxq -- "$trimmed" <<<"$EXISTING_TRIMMED"; then
        continue
    fi
    FOUND+="  ${trimmed}"$'\n'
done <<<"$ADDED"

[ -n "$FOUND" ] || exit 0

block "Blocked: this edit adds a declaration that runs with no arguments when its expansions are empty:

${FOUND}
\`local\`, \`typeset\`, \`declare\` and \`export\` with no arguments print every parameter in scope, exported secrets included. Rewrite the line so that it cannot expand to nothing. Any of these passes:

    local green red yellow
    export \"\$name\"
    typeset \"\${names[@]:?names is empty}\"

The first writes the names out. The second quotes a single name, so an empty value is an error instead of a listing. The third makes an empty list an error.

If the line cannot expand to nothing for a reason this check cannot see, say so in a comment at the end of the line: # allow-bare-decl: <reason>"

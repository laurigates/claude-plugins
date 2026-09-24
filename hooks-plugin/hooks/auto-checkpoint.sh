#!/usr/bin/env bash
# PreToolUse hook — auto-creates a git stash checkpoint before destructive operations
#
# Toggle: set CLAUDE_HOOKS_DISABLE_AUTO_CHECKPOINT=1 to skip this hook
#
# Matches: Bash
# Triggers on: git reset, git checkout -- (file restore), git restore, rm -rf,
#              git clean -f
# Creates: a named git stash as a recovery checkpoint
#
# ── What changed in #2652, and the polarity it keeps ─────────────────────────
#
# Until #2652 every detector was a regex over the RAW command string, so the
# hook fired on (a) `rm -rf /tmp/scratch`, whose every operand lies outside the
# repository, and (b) commands that delete nothing at all — a `gh issue comment
# --body` quoting the phrase, a heredoc body, a commit message, a `grep` for the
# pattern. One session produced 50 redundant stashes.
#
# Five hand-rolled tokenisers were tried and withdrawn before this version, and
# every one lost a spelling the shell executes (`\rm`, `bash --norc -c`, `bash
# --rcfile X -c`). So this is a PROTECTIVE hook first: it may over-checkpoint,
# it must never under-checkpoint relative to the old matcher. The design keeps
# that guarantee structurally rather than by enumerating spellings:
#
#   verdict = structural(command nodes)
#             OR legacy(residue)
#             OR legacy(command), unless the command is built only from the
#                closed allowlist of shapes below
#
#   - legacy() is the pre-#2652 matcher, verbatim (legacy_reason below).
#   - residue is the command TEXT with parser-classified spans blanked, on
#     evidence from `ast-grep --lang bash` (tree-sitter-bash): a comment; an
#     inert program (echo, printf, grep, rg, jq, cat, head, tail, wc, `gh
#     issue|pr|api|release|search|label|run|workflow|status`, `git
#     commit|log|show|diff|grep|status|tag|notes`) whose output reaches no other
#     program in its pipeline or redirected statement; or a direct `rm` whose
#     every operand the structural pass proved to lie outside the repository.
#   - Blanking is an EXEMPTION, and it holds only when the WHOLE command —
#     every statement, pipeline stage, substitution and heredoc — is built from
#     a closed allowlist of shapes (exemption_holds below). It is not a list of
#     hazards: whatever the allowlist does not name sends the whole command to
#     the old matcher, so the command checkpoints exactly as it did before
#     #2652. Allowed: simple commands, pipelines, `&&` / `||` / `;` lists,
#     comments, heredocs and here-strings, redirects to /dev/null, fd
#     duplications, input redirects, and these programs — the inert ones above,
#     rm, git (a fixed set of subcommands, no global option but -C and
#     --no-pager), gh (the subcommands above), cd, pwd, ls, mkdir, test, [,
#     true, false, :, sleep. Each program's words are read as the shell delivers
#     them (quotes removed), and one that could make an allowed program write a
#     file or run one voids the exemption: -o/-O in a short option cluster or a
#     long --output / --out… option on any program, `printf -v`, `rg --pre`,
#     `git grep --open-files-in-pager`, and for git, gh, printf and rg a word
#     this hook cannot read. So does any assignment, declaration, function,
#     command or process substitution, `${x=…}` expansion, loop, conditional,
#     subshell or group, and a heredoc with an unquoted delimiter whose body
#     holds `$` or a backtick. `exec`, `tee`, `eval`, `source`, `.`, every
#     shell, `xargs`, `find`, `parallel`, `env`, `sudo`, `awk`, `perl` and every
#     other program are simply not on the list. Shell state from BEFORE the
#     command is trusted: a name rebound by the user's profile, a git hook or
#     alias already installed, or a variable already exported is not seen.
#   - structural() walks each tree-sitter `command` node, rebuilds its argument
#     vector the way the shell would (quotes removed, escapes resolved), and
#     looks for an `rm`/`git` token ANYWHERE in it — so `sudo rm`, `timeout 5
#     rm`, `env X=1 rm`, `\rm`, `/bin/rm`, `"rm"` and `xargs rm` need no wrapper
#     allowlist. The quoted arguments of a shell invoker (`bash -c "…"`, `sh
#     -ec '…'`, `eval "…"`, …), of a command piped into one, and heredoc bodies
#     fed to one are re-parsed as shell, with no option parsing to get wrong.
#
# Every failure of the parser therefore degrades toward the old behaviour: no
# ast-grep, an ast-grep error, a tree-sitter ERROR node, or a shape outside the
# allowlist all leave the old matcher deciding over the whole command. The only
# way to under-checkpoint is an allowlisted shape that runs text or writes a
# file after all.
#
# ── rm operands: when is a deletion "outside the repository"? ────────────────
#
# Only when every operand is a literal ABSOLUTE path that is disjoint from the
# repository — neither inside it nor an ancestor of it — both as a case-folded
# physical path string (symlinks followed through `cd -P`) and by file identity
# (`[ A -ef B ]` on device and inode, which a macOS firmlink, a /.vol path, a
# bind mount or a symlink cannot disguise). The repository is `git rev-parse
# --show-toplevel` plus its git dir and common dir. A glob operand is judged by
# its literal directory prefix. Anything else checkpoints:
#
#   - a path the hook cannot resolve now: a `..` after a component that does
#     not exist, a dangling or looping symlink, or anything through /proc or
#     /dev, whose names resolve per process (/proc/self/cwd, /dev/fd/N)
#   - a relative operand — a preceding `cd` in the same command could point it
#     anywhere, so `cd /tmp && rm -rf scratch` still checkpoints
#   - an operand carrying an expansion or substitution. `rm -rf "$T"` where T
#     came from `mktemp -d` is NOT statically resolvable and still checkpoints;
#     #2652 is REDUCED for that shape, not fixed
#   - a wrapped rm (`sudo rm`, `bash -c "rm …"`) still reaches the old matcher
#     through the residue, so an out-of-repo target behind a wrapper still
#     checkpoints as before
#
# Build-artifact names (node_modules, dist, build, …) are exempt as before, but
# per operand: `rm -rf dist ./src` now checkpoints, where the old matcher let the
# first artifact name exempt the whole command. So does one holding a `..`
# component (`node_modules/../src`), which the old matcher's `\b` let through.
#
# CLAUDE_HOOKS_AUTO_CHECKPOINT_NO_ASTGREP=1 forces the no-parser path (tests):
# the old matcher alone, i.e. the pre-#2652 behaviour.

set -euo pipefail

# Toggle off
[ "${CLAUDE_HOOKS_DISABLE_AUTO_CHECKPOINT:-}" = "1" ] && exit 0

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only applies to Bash tool
[ "$TOOL_NAME" != "Bash" ] && exit 0
[ -z "$COMMAND" ] && exit 0

# Must be in a git repo
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Check if there are uncommitted changes worth checkpointing
has_changes() {
  [ -n "$(git status --porcelain 2>/dev/null)" ]
}

create_checkpoint() {
  local reason="$1"
  if has_changes; then
    local timestamp commit
    timestamp=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date '+%s')
    commit=$(git stash create --include-untracked 2>/dev/null || true)
    if [ -n "$commit" ]; then
      if git stash store -m "auto-checkpoint before ${reason} (${timestamp})" "$commit" 2>/dev/null; then
        echo "Created checkpoint stash before ${reason}. Recover with: git stash list" >&2
      fi
    fi
  fi
}

# ── The pre-#2652 matcher, kept as the floor ─────────────────────────────────
#
# The five detectors below are the old hook's, in the old order, with two
# mechanical changes. Each grep reads a here-string instead of `echo "$x" | grep
# -q`, because under `set -o pipefail` a grep that exits on its first match
# SIGPIPEs the echo on inputs past the pipe buffer, and the pipeline then reads
# as "no match" — a silent miss on exactly the long commands that carry
# heredocs. And each grep runs only when its regex's literal word (reset,
# checkout, restore, rm, clean) occurs in the text, which it must for the regex
# to match, so the verdict is unchanged and most commands spawn no grep at all.
LEGACY_REASON=""
legacy_reason() {
  local text=$1
  LEGACY_REASON=""
  case $text in *reset*)
    if grep -Eq '^\s*git\s+reset\b' <<<"$text"; then LEGACY_REASON="git reset"; return 0; fi ;;
  esac
  case $text in *checkout*)
    if grep -Eq 'git\s+checkout\s+--\s+' <<<"$text"; then LEGACY_REASON="git checkout file restore"; return 0; fi ;;
  esac
  case $text in *restore*)
    if grep -Eq 'git\s+restore\s+' <<<"$text" && ! grep -q -- '--staged' <<<"$text"; then
      LEGACY_REASON="git restore"; return 0
    fi ;;
  esac
  case $text in *rm*)
    if grep -Eq 'rm\s+(-rf|-fr)\s+' <<<"$text" && \
       ! grep -Eq 'rm\s+(-rf|-fr)\s+(node_modules|dist|build|\.next|\.cache|__pycache__|\.pytest_cache|target|\.build)\b' <<<"$text"; then
      LEGACY_REASON="rm -rf"; return 0
    fi ;;
  esac
  case $text in *clean*)
    if grep -Eq 'git\s+clean\s+-[a-z]*f' <<<"$text"; then LEGACY_REASON="git clean"; return 0; fi ;;
  esac
  return 0
}

checkpoint_if_legacy() {
  legacy_reason "$1"
  if [ -n "$LEGACY_REASON" ]; then
    create_checkpoint "$LEGACY_REASON"
    exit 0
  fi
}

# A command whose text never spells `rm` or `git` — once quotes, backslashes and
# line breaks are dropped — cannot deliver either program name to the shell, and
# the old matcher cannot fire on it either. Skip the parser for it.
STRIPPED=${COMMAND//[\\\"\']/}
STRIPPED=${STRIPPED//$'\n'/}
case $STRIPPED in
  *rm* | *git*) ;;
  *) exit 0 ;;
esac

# `sg` is ast-grep's short binary name, but it collides with shadow-utils' sg(1)
# on essentially every Debian/Ubuntu box. Verify the resolved `sg` really is
# ast-grep before adopting it (#2451).
ASTGREP=""
if [ "${CLAUDE_HOOKS_AUTO_CHECKPOINT_NO_ASTGREP:-}" != "1" ]; then
  if command -v ast-grep >/dev/null 2>&1; then
    ASTGREP="ast-grep"
  elif command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'; then
    ASTGREP="sg"
  fi
fi

# No parser: the old matcher decides, exactly as before #2652. FAIL SAFE — the
# opposite of bash-antipatterns.sh and validate-terraform-apply.sh, which fail
# open, because a missed checkpoint loses work and a spare one costs a stash.
if [ -z "$ASTGREP" ]; then
  checkpoint_if_legacy "$COMMAND"
  exit 0
fi

# ast-grep reports BYTE offsets, so every slice below is byte-indexed.
LC_ALL=C
export LC_ALL

# ── ast-grep rules ───────────────────────────────────────────────────────────
#
# `inert-name` is a program that never executes its arguments. `inert-command`
# adds the context conditions under which its OUTPUT also reaches nothing else:
# not inside a command or process substitution or a function body, and not
# inside any pipeline or redirected statement that also holds a non-inert
# command or writes to a real file. tree-sitter-bash places the `| tail -1` of
# `gh … <<'EOF' | tail -1` INSIDE the heredoc redirect, so the
# redirected-statement arm is what sees `cat <<EOF | bash` at all.
#
# `gh` is inert only under the subcommands below, which take their arguments as
# data. Elsewhere gh executes them: `gh alias set x '!cmd'` (or `--shell`, or
# `gh alias import -`) then `gh x` runs cmd through sh; an unknown subcommand is
# an alias or an extension; `gh config set browser 'cmd'` is run by `--web`.
#
# The `gate-*` rules find shapes that void the exemption wherever they occur;
# exemption_holds() reads them.
INERT_PROGS='^(echo|printf|grep|egrep|fgrep|rg|jq|cat|head|tail|wc)$'
INERT_GIT='^git[ \t]+(commit|log|show|diff|grep|status|tag|notes)([ \t\n]|$)'
INERT_GH='^gh[ \t]+(issue|pr|api|release|search|label|run|workflow|status)([ \t\n]|$)'
# The only redirects that write nothing: to /dev/null, an fd duplication or
# close, and an input redirect.
BENIGN_REDIRECT='^[0-9]*(>|>>|&>|&>>|>\|)[ \t]*/dev/null$|^[0-9]*[<>]&[ \t]*([0-9]+|-)$|^[0-9]*<[ \t]*[^<>&|( \t]+$'
# A heredoc delimiter with no quote or backslash in it: the body is expanded.
UNQUOTED_DELIM='^[^\x27\x22\x5c]*$'
RM_NAME='^\\?(/[^/ \t]+)*/?rm$'
INVOKER_WORD='^\\?(/[^/ \t]+)*/?(sh|bash|zsh|ksh|dash|ash|mksh|yash|fish|eval)$'

INERT_UTILS="utils:
  inert-name:
    all:
      - kind: command
      - not: { has: { kind: variable_assignment } }
      - any:
          - has: { field: name, regex: '${INERT_PROGS}' }
          - regex: '${INERT_GIT}'
          - regex: '${INERT_GH}'
  inert-command:
    all:
      - kind: command
      - matches: inert-name
      - not: { inside: { stopBy: end, any: [ { kind: command_substitution }, { kind: process_substitution }, { kind: function_definition } ] } }
      - not:
          inside:
            stopBy: end
            any: [ { kind: pipeline }, { kind: redirected_statement } ]
            has:
              stopBy: end
              any:
                - { kind: command, not: { matches: inert-name } }
                - { kind: file_redirect, not: { regex: '${BENIGN_REDIRECT}' } }"

AST_RULES="id: cmd
language: bash
rule: { kind: command }
---
id: perr
language: bash
rule: { kind: ERROR }
---
id: comment
language: bash
rule: { kind: comment }
---
id: subst
language: bash
rule: { any: [ { kind: command_substitution }, { kind: process_substitution } ] }
---
id: inert-cmd
language: bash
${INERT_UTILS}
rule: { matches: inert-command }
---
id: gate-kind
language: bash
rule:
  any:
    - { kind: command_substitution }
    - { kind: process_substitution }
    - { kind: arithmetic_expansion }
    - { kind: function_definition }
    - { kind: variable_assignment }
    - { kind: variable_assignments }
    - { kind: declaration_command }
    - { kind: unset_command }
    - { kind: for_statement }
    - { kind: c_style_for_statement }
    - { kind: while_statement }
    - { kind: if_statement }
    - { kind: case_statement }
    - { kind: subshell }
    - { kind: compound_statement }
    - { kind: test_command }
    - { kind: negated_command }
    - { kind: array }
    - { kind: translated_string }
    - { kind: brace_expression }
---
id: gate-exp
language: bash
rule: { kind: expansion, regex: '=' }
---
id: gate-redir
language: bash
rule: { kind: file_redirect, not: { regex: '${BENIGN_REDIRECT}' } }
---
id: gate-heredoc
language: bash
rule:
  kind: heredoc_redirect
  regex: '[\x24\x60]'
  has: { kind: heredoc_start, regex: '${UNQUOTED_DELIM}' }
---
id: inert-stmt
language: bash
${INERT_UTILS}
rule: { kind: redirected_statement, has: { field: body, matches: inert-command } }
---
id: hot-stmt
language: bash
${INERT_UTILS}
rule:
  kind: redirected_statement
  not:
    has:
      field: body
      any:
        - { matches: inert-command }
        - { kind: command, has: { field: name, regex: '${RM_NAME}' } }
---
id: sh-piped
language: bash
rule:
  kind: command
  inside:
    stopBy: end
    any: [ { kind: pipeline }, { kind: redirected_statement } ]
    has: { stopBy: end, kind: command, has: { field: name, regex: '${INVOKER_WORD}' } }
---
id: sh-heredoc
language: bash
rule:
  kind: heredoc_body
  any:
    - inside:
        stopBy: end
        kind: redirected_statement
        has: { field: body, has: { stopBy: end, regex: '${INVOKER_WORD}' } }
    - inside:
        stopBy: end
        kind: redirected_statement
        has: { stopBy: end, kind: command, has: { field: name, regex: '${INVOKER_WORD}' } }"

# One node per line: "<rule-id> <start-byte> <end-byte>". Any ast-grep or jq
# failure yields no lines — and no lines means nothing is proven inert, so the
# residue stays whole and the old matcher decides.
nodes_of() {
  local out
  out=$(printf '%s' "$1" | "$ASTGREP" scan --inline-rules "$AST_RULES" --stdin --json=compact 2>/dev/null) || true
  [ -n "$out" ] || return 0
  jq -r '.[] | "\(.ruleId) \(.range.byteOffset.start) \(.range.byteOffset.end)"' <<<"$out" 2>/dev/null || true
}

# ── Shell-word reconstruction ────────────────────────────────────────────────
#
# Split one command node into the argument vector the shell would build.
# Quotes are REMOVED, because the shell removes them: `"rm"` and `r''m` both
# run rm, and `rm "-rf"` really receives -rf. Per token: TOK_VAL is the
# delivered value; TOK_Q marks a token with any quoted or escaped part (a shell
# invoker's script argument); TOK_E marks a value this hook cannot know — a
# `$VAR`, `$(…)`, backtick, `<(…)`, `$'…'`, an unquoted leading `~`, or an
# unquoted `{` (brace expansion).
TOK_VAL=()
TOK_Q=()
TOK_E=()
BACKSLASH=$'\\'
tokenize() {
  local s=$1
  local n=${#s}
  local c depth
  local i=0
  local cur="" started=0 q=0 e=0
  TOK_VAL=()
  TOK_Q=()
  TOK_E=()
  while [ "$i" -lt "$n" ]; do
    c=${s:i:1}
    if [ "$c" = "'" ]; then
      q=1
      started=1
      i=$((i + 1))
      while [ "$i" -lt "$n" ] && [ "${s:i:1}" != "'" ]; do
        cur+=${s:i:1}
        i=$((i + 1))
      done
      i=$((i + 1))
      continue
    fi
    if [ "$c" = '"' ]; then
      q=1
      started=1
      i=$((i + 1))
      while [ "$i" -lt "$n" ]; do
        c=${s:i:1}
        if [ "$c" = '"' ]; then break; fi
        if [ "$c" = "$BACKSLASH" ]; then
          i=$((i + 1))
          cur+=${s:i:1}
          i=$((i + 1))
          continue
        fi
        if [ "$c" = '$' ] || [ "$c" = '`' ]; then e=1; fi
        cur+=$c
        i=$((i + 1))
      done
      i=$((i + 1))
      continue
    fi
    if [ "$c" = "$BACKSLASH" ]; then
      i=$((i + 1))
      # Backslash-newline is a line continuation: it vanishes, word and all.
      if [ "${s:i:1}" = $'\n' ]; then
        i=$((i + 1))
        continue
      fi
      cur+=${s:i:1}
      i=$((i + 1))
      started=1
      q=1
      continue
    fi
    if [ "$c" = '~' ] && [ "$started" = 0 ]; then
      e=1
    fi
    if [ "$c" = '{' ]; then
      e=1
    fi
    if [ "$c" = '$' ] || { { [ "$c" = '<' ] || [ "$c" = '>' ]; } && [ "${s:i+1:1}" = "(" ]; }; then
      e=1
      started=1
      cur+=$c
      i=$((i + 1))
      # Consume a balanced $(…), ${…} or <(…) so its contents cannot pose as
      # further arguments.
      c=${s:i:1}
      if [ "$c" = "(" ] || [ "$c" = "{" ]; then
        depth=0
        while [ "$i" -lt "$n" ]; do
          c=${s:i:1}
          cur+=$c
          i=$((i + 1))
          if [ "$c" = "(" ] || [ "$c" = "{" ]; then depth=$((depth + 1)); fi
          if [ "$c" = ")" ] || [ "$c" = "}" ]; then
            depth=$((depth - 1))
            if [ "$depth" -le 0 ]; then break; fi
          fi
        done
      fi
      continue
    fi
    if [ "$c" = '`' ]; then
      e=1
      started=1
      cur+=$c
      i=$((i + 1))
      while [ "$i" -lt "$n" ]; do
        c=${s:i:1}
        cur+=$c
        i=$((i + 1))
        if [ "$c" = '`' ]; then break; fi
      done
      continue
    fi
    case $c in
      ' ' | $'\t' | $'\n')
        if [ "$started" = 1 ]; then
          TOK_VAL+=("$cur")
          TOK_Q+=("$q")
          TOK_E+=("$e")
          cur=""
          started=0
          q=0
          e=0
        fi
        ;;
      *)
        cur+=$c
        started=1
        ;;
    esac
    i=$((i + 1))
  done
  if [ "$started" = 1 ]; then
    TOK_VAL+=("$cur")
    TOK_Q+=("$q")
    TOK_E+=("$e")
  fi
  return 0
}

# ── Is a literal absolute path outside the repository? ───────────────────────
#
# "Outside" is decided twice, and a path is exempt only when both agree:
#
#   - by FILE IDENTITY (device and inode, `[ A -ef B ]`), which a second name
#     for the same directory cannot fool: a macOS firmlink
#     (/System/Volumes/Data/Users/… is /Users/…), /.vol/<dev>/<ino>, a bind
#     mount, a symlink (identity_disjoint below);
#   - by the path STRING, case-folded (paths_disjoint below), which also merges
#     two spellings that differ only in letter case on a case-sensitive
#     filesystem, where identity would call them distinct.
#
# The protected roots are the work tree's top and the repository's git dir and
# common dir; in a linked worktree those two lie outside the work tree.
#
# ANCS lists every directory whose deletion would take a root with it, by
# string: each root's path prefixes and, on macOS, those of its firmlink
# spelling under /System/Volumes/Data. Climbing by `..` alone misses those: the
# data volume's root (/System/Volumes/Data) and /System hold /private/tmp/repo,
# yet `..` from /private leads to /, not to them.
REPO_TOP=""
PROTECT=()
PROTECT_LC=()
ANCS=()
add_ancestors() {
  local a=$1
  while :; do
    ANCS+=("$a")
    [ "$a" != / ] || break
    a=${a%/*}
    [ -n "$a" ] || a=/
  done
}
ensure_repo_top() {
  local out lc line d top=""
  local -a roots=() lcs=()
  if [ -n "$REPO_TOP" ]; then return 0; fi
  # One git call and one subshell resolve all three (absolute, so each `cd -P`
  # is independent of the last). A git without --path-format fails here, and
  # every absolute operand then checkpoints. No `case` inside the substitution:
  # bash 3.2 misparses its `)`.
  out=$(git rev-parse --path-format=absolute --show-toplevel --git-dir --git-common-dir 2>/dev/null |
    while IFS= read -r line; do
      [ "${line#/}" != "$line" ] || exit 1
      CDPATH='' cd -P -- "$line" 2>/dev/null || exit 1
      pwd -P
    done) || return 1
  lc=$(printf '%s\n' "$out" | tr '[:upper:]' '[:lower:]') || return 1
  while IFS= read -r line; do
    [ -n "$line" ] || return 1
    case $line in *[![:print:]]*) return 1 ;; esac
    [ -n "$top" ] || top=$line
    roots+=("$line")
  done <<<"$out"
  while IFS= read -r line; do lcs+=("$line"); done <<<"$lc"
  [ "${#roots[@]}" = 3 ] && [ "${#lcs[@]}" = 3 ] || return 1
  ANCS=()
  for d in "${roots[@]}"; do
    add_ancestors "$d"
    if [ -d /System/Volumes/Data ] && [ "/System/Volumes/Data$d" -ef "$d" ]; then
      add_ancestors "/System/Volumes/Data$d"
    fi
  done
  PROTECT=("${roots[@]}")
  PROTECT_LC=("${lcs[@]}")
  REPO_TOP=$top
}

# Reads an absolute path and sets:
#   DEEP   the longest leading run of its components that the KERNEL resolves
#          to an existing directory, spelled with the literal components (`..`
#          included) so that identity_disjoint stats what rm will reach, not
#          bash's string idea of it. Searched from the whole path down, because
#          a longer prefix can resolve where a shorter one does not
#          (/.vol/<dev>/<ino> exists; /.vol/<dev> does not).
#   EXISTS 1 when that run is the whole path.
#   PHYS   the physical string: DEEP through `cd -P`, the rest appended.
# Refused (return 1, so the caller checkpoints), because what the path names
# when rm runs cannot be read now:
#   - a `..` after the existing run;
#   - a first missing component that is a symlink (dangling, a loop, or a link
#     to a non-directory): what it points at when rm runs is unknown;
#   - a path through /proc or /dev, by name or by identity, whose names resolve
#     per process (/proc/self/cwd, /dev/fd/N): the hook's own view of them says
#     nothing about rm's.
PHYS=""
DEEP=""
EXISTS=0
physical_path() {
  local rest=${1#/} comp k kd n tail d
  local -a comps=() pres=(/)
  while [ -n "$rest" ]; do
    comp=${rest%%/*}
    case $rest in
      */*) rest=${rest#*/} ;;
      *) rest="" ;;
    esac
    case $comp in '' | .) continue ;; esac
    comps+=("$comp")
    pres+=("${pres[${#pres[@]} - 1]%/}/$comp")
  done
  n=${#comps[@]}
  case ${comps[0]-} in proc | dev) return 1 ;; esac
  for ((kd = n; kd > 0; kd--)); do
    if [ -d "${pres[kd]}" ]; then break; fi
  done
  for ((k = 1; k <= kd; k++)); do
    if [ "${pres[k]}" -ef /proc ] || [ "${pres[k]}" -ef /dev ]; then return 1; fi
  done
  DEEP=${pres[kd]}
  EXISTS=0
  if [ "$kd" = "$n" ]; then EXISTS=1; fi
  tail=""
  for ((k = kd; k < n; k++)); do
    comp=${comps[k]}
    if [ "$comp" = .. ]; then return 1; fi
    if [ "$k" = "$kd" ] && [ -L "${pres[k + 1]}" ]; then return 1; fi
    tail=$tail/$comp
  done
  d=$(CDPATH='' cd -P -- "$DEEP" 2>/dev/null && pwd -P) || return 1
  [ -n "$d" ] || return 1
  PHYS=${d%/}$tail
  [ -n "$PHYS" ] || PHYS=/
}

# 0 when the two physical paths are disjoint: neither equal, nor one inside the
# other. Deleting an ANCESTOR of the repository deletes the repository.
#
# Compared case-insensitively, because `cd -P` keeps the case as typed and the
# default macOS filesystem ignores it: `/USERS/me/repo/src` is inside
# `/Users/me/repo`. On a case-sensitive filesystem this can only merge two
# distinct paths, which errs toward checkpointing. A non-ASCII byte in either
# path is refused outright — Unicode normalisation (NFC vs NFD) is the same
# trap one level down. Callers pass both paths already lower-cased (one `tr`
# per operand, and one for the roots in ensure_repo_top).
paths_disjoint() {
  local a=$1 b=$2
  if [ "$a" = / ] || [ "$b" = / ] || [ "$a" = "$b" ]; then return 1; fi
  case $a/ in "$b"/*) return 1 ;; esac
  case $b/ in "$a"/*) return 1 ;; esac
  return 0
}

# 0 when DEEP is none of the protected roots and sits below none of them, and —
# when the whole path exists — is none of their ancestors. Every comparison is
# `-ef` on a path the kernel resolves, so no spelling of a directory is trusted
# to be its only name. "Below" climbs from DEEP by appending `/..`; "ancestor"
# climbs from each root the same way and also checks ANCS. A level that cannot
# be stat'ed (vanished, or longer than PATH_MAX) refuses, as does a climb deeper
# than 255 levels.
identity_disjoint() {
  local up=$DEEP anc root n=0
  while :; do
    [ -e "$up" ] || return 1
    for root in "${PROTECT[@]}"; do
      if [ "$up" -ef "$root" ]; then return 1; fi
    done
    if [ "$up" -ef "$up/.." ]; then break; fi
    up=$up/..
    n=$((n + 1))
    [ "$n" -lt 256 ] || return 1
  done
  [ "$EXISTS" = 1 ] || return 0
  for anc in "${ANCS[@]}"; do
    if [ "$DEEP" -ef "$anc" ]; then return 1; fi
  done
  for root in "${PROTECT[@]}"; do
    anc=$root
    n=0
    while :; do
      [ -e "$anc" ] || return 1
      if [ "$DEEP" -ef "$anc" ]; then return 1; fi
      if [ "$anc" -ef "$anc/.." ]; then break; fi
      anc=$anc/..
      n=$((n + 1))
      [ "$n" -lt 256 ] || return 1
    done
  done
  return 0
}

path_outside_repo() {
  local p=$1 root plc
  case $p in
    /*) ;;
    *) return 1 ;;
  esac
  # A glob is never exempt: a component it matches can be a symlink into the
  # repository (`/outside/lin*/src`), and under bash 3.2 `.?` matches `..`.
  # `^`, `~` and `#` are glob operators in zsh under extended_glob.
  case $p in *[\*\?\[~#^]*) return 1 ;; esac
  physical_path "$p" || return 1
  ensure_repo_top || return 1
  case $PHYS in *[![:print:]]*) return 1 ;; esac
  plc=$(printf '%s' "$PHYS" | tr '[:upper:]' '[:lower:]') || return 1
  for root in "${PROTECT_LC[@]}"; do
    paths_disjoint "$plc" "$root" || return 1
  done
  identity_disjoint
}

# A build-artifact name, relative, with no `..` component (`node_modules/../src`
# is ./src).
BUILD_ARTIFACT_RE='^(node_modules|dist|build|\.next|\.cache|__pycache__|\.pytest_cache|target|\.build)(/.*)?$'

# $1 = token index of an rm operand. 0 when deleting it cannot touch the repo's
# work: a literal absolute path outside the repository, or an unquoted
# build-artifact name.
rm_operand_exempt() {
  local k=$1 a=${TOK_VAL[$1]}
  [ "${TOK_E[k]}" = 0 ] || return 1
  case $a in
    /*) path_outside_repo "$a" ;;
    */../* | */..) return 1 ;;
    *) [ "${TOK_Q[k]}" = 0 ] && [[ $a =~ $BUILD_ARTIFACT_RE ]] ;;
  esac
}

# Reason set by rm_reason / git_reason (globals, not echo, so no subshell forks
# on a hook that runs before every Bash call).
RSN=""

# $1 = index of the rm token. Sets RSN="rm -rf" when the invocation is a
# recursive forced delete that can reach the repository. Options are read
# anywhere before `--`, because GNU getopt permutes (`rm ./src -rf` recurses);
# long options match on any unique prefix, as getopt accepts them. No operands
# at all (`xargs rm -rf`, `find … -exec`) means the targets arrive at run time:
# checkpoint.
rm_reason() {
  local i=$1 n=${#TOK_VAL[@]} k a name letters
  local r=0 f=0 opts_done=0 nops=0 all_exempt=1
  for ((k = i + 1; k < n; k++)); do
    a=${TOK_VAL[k]}
    if [ "$opts_done" = 0 ] && [ "${TOK_E[k]}" = 0 ]; then
      case $a in
        --)
          opts_done=1
          continue
          ;;
        --?*)
          name=${a#--}
          name=${name%%=*}
          case $name in r | re | rec | recu | recur | recurs | recursi | recursiv | recursive) r=1 ;; esac
          case $name in f | fo | for | forc | force) f=1 ;; esac
          continue
          ;;
        -?*)
          letters=${a#-}
          case $letters in *[rR]*) r=1 ;; esac
          case $letters in *f*) f=1 ;; esac
          continue
          ;;
      esac
    fi
    nops=$((nops + 1))
    if ! rm_operand_exempt "$k"; then all_exempt=0; fi
  done
  if [ "$r" = 1 ] && [ "$f" = 1 ]; then
    if [ "$nops" = 0 ] || [ "$all_exempt" = 0 ]; then RSN="rm -rf"; fi
  fi
  return 0
}

# $1 = index of the git token. Sets RSN to the checkpoint reason for reset,
# checkout --, restore (unless staged-only) and clean --force, the old
# matcher's four git triggers, in any spelling of git's global options.
git_reason() {
  local i=$1 n=${#TOK_VAL[@]} j a k sub
  local ncdir=0 cdir_idx=-1 staged=0 worktree=0
  j=$((i + 1))
  while [ "$j" -lt "$n" ]; do
    a=${TOK_VAL[j]}
    case $a in
      -C)
        ncdir=$((ncdir + 1))
        cdir_idx=$((j + 1))
        j=$((j + 2))
        continue
        ;;
      -c | --git-dir | --work-tree | --namespace | --config-env | --attr-source)
        j=$((j + 2))
        continue
        ;;
      -*)
        j=$((j + 1))
        continue
        ;;
    esac
    break
  done
  [ "$j" -lt "$n" ] || return 0
  sub=${TOK_VAL[j]}
  # `git -C /elsewhere …` operates on another repository.
  if [ "$ncdir" = 1 ] && [ "$cdir_idx" -lt "$n" ] && [ "${TOK_E[cdir_idx]}" = 0 ] &&
    path_outside_repo "${TOK_VAL[cdir_idx]}"; then
    return 0
  fi
  case $sub in
    reset)
      RSN="git reset"
      ;;
    checkout)
      for ((k = j + 1; k < n; k++)); do
        if [ "${TOK_VAL[k]}" = "--" ]; then
          RSN="git checkout file restore"
          return 0
        fi
      done
      ;;
    restore)
      for ((k = j + 1; k < n; k++)); do
        case ${TOK_VAL[k]} in
          --staged) staged=1 ;;
          --worktree) worktree=1 ;;
          --*) ;;
          -*W*) worktree=1 ;;
        esac
      done
      if [ "$staged" = 0 ] || [ "$worktree" = 1 ]; then RSN="git restore"; fi
      ;;
    clean)
      for ((k = j + 1; k < n; k++)); do
        case ${TOK_VAL[k]} in
          --f | --fo | --for | --forc | --force)
            RSN="git clean"
            return 0
            ;;
          --*) ;;
          -*f*)
            RSN="git clean"
            return 0
            ;;
        esac
      done
      ;;
  esac
  return 0
}

# ── The closed allowlist behind the exemption ────────────────────────────────
#
# Blanking a span from the residue asserts that its text is never run. That
# holds only if nothing else in the same command can run it, or plant it where
# something will: a shell fed a file or stdin, `eval`, `source`, an `exec`
# redirecting later output, `tee`, `find -exec`, `awk '{system($0)}'`, `git -c
# alias.x='!…'`, `git fetch --upload-pack=…`, a GIT_PAGER prefix, `git log
# --output=F` writing a hook. Earlier rounds found those one at a time; this
# list stops enumerating them. The exemption holds only for a command whose
# every part is named below; anything else sends the whole command to the old
# matcher.
ALLOW_PROGS='^(echo|printf|grep|egrep|fgrep|rg|jq|cat|head|tail|wc|rm|git|gh|cd|pwd|ls|mkdir|test|\[|true|false|:|sleep)$'
ALLOW_GIT_SUBS='^(status|log|show|diff|grep|commit|tag|notes|add|rev-parse|branch|switch|checkout|restore|reset|clean|stash|rm|mv|ls-files|merge-base|rev-list|describe|shortlog|blame|reflog|cat-file|show-ref|for-each-ref|symbolic-ref)$'
ALLOW_GH_SUBS='^(issue|pr|api|release|search|label|run|workflow|status)$'
# An option that makes a program write a file: a short cluster holding o or O
# (`sort -o F`, `git grep -O<pager>`, `curl -o F`), or a long option spelling a
# prefix of --output, or --out… . Checked on every word of every program.
WRITE_OPT='^-[A-Za-z0-9]*[oO]|^--(o|ou|out|outp|outpu)(=|$)|^--(output|out-|out_|outfile|o-file)'

# 0 when the tokenised command (TOK_*) is an allowlisted shape.
command_allowed() {
  local t=${#TOK_VAL[@]} k prog j sub
  [ "$t" -gt 0 ] || return 1
  [ "${TOK_E[0]}" = 0 ] || return 1
  prog=${TOK_VAL[0]}
  [[ $prog =~ $ALLOW_PROGS ]] || return 1
  for ((k = 1; k < t; k++)); do
    if [ "${TOK_E[k]}" = 1 ]; then
      # git, gh, printf and rg each have an option that runs or writes, and a
      # word whose value this hook cannot know could spell it.
      case $prog in git | gh | printf | rg) return 1 ;; esac
      continue
    fi
    if [[ ${TOK_VAL[k]} =~ $WRITE_OPT ]]; then return 1; fi
  done
  case $prog in
    printf)
      # printf's only option is -v VAR, and a later `eval "$VAR"` runs it.
      case ${TOK_VAL[1]-} in
        --) ;;
        -*) return 1 ;;
      esac
      ;;
    rg)
      for ((k = 1; k < t; k++)); do
        case ${TOK_VAL[k]} in --pre* | --hostname-bin*) return 1 ;; esac
      done
      ;;
    gh)
      if [ "$t" -lt 2 ] || ! [[ ${TOK_VAL[1]} =~ $ALLOW_GH_SUBS ]]; then return 1; fi
      ;;
    git)
      # Global options: -C DIR and --no-pager only. `-c` alone can define an
      # alias, a pager, an editor or a hooks path.
      j=1
      while [ "$j" -lt "$t" ]; do
        case ${TOK_VAL[j]} in
          -C) j=$((j + 2)) ;;
          --no-pager) j=$((j + 1)) ;;
          -*) return 1 ;;
          *) break ;;
        esac
      done
      [ "$j" -lt "$t" ] || return 0
      sub=${TOK_VAL[j]}
      [[ $sub =~ $ALLOW_GIT_SUBS ]] || return 1
      if [ "$sub" = grep ]; then
        # --open-files-in-pager by any unique prefix (-O is WRITE_OPT's).
        for ((k = j + 1; k < t; k++)); do
          case ${TOK_VAL[k]} in --op*) return 1 ;; esac
        done
      fi
      ;;
  esac
  return 0
}

# 0 when the top-level command (TOP_NODES, from analyse) is built only from the
# allowlist: no gate-* node anywhere, and every command node an allowlisted
# shape. No nodes at all is a parse that proved nothing.
TOP_NODES=""
exemption_holds() {
  local rid s e
  [ -n "$TOP_NODES" ] || return 1
  while read -r rid s e; do
    case $rid in gate-*) return 1 ;; esac
  done <<<"$TOP_NODES"
  while read -r rid s e; do
    [ "$rid" = cmd ] || continue
    tokenize "${COMMAND:s:e-s}"
    command_allowed || return 1
  done <<<"$TOP_NODES"
  return 0
}

# ── Residue painting ─────────────────────────────────────────────────────────
#
# SEGS holds disjoint "<start> <end> <label>" segments covering the snippet.
# paint() overwrites a range with a label; painting outer nodes before inner
# ones makes the INNERMOST classified node decide each byte. Label B = blank
# (proven inert), K = keep.
SEGS=()
paint() {
  local ps=$1 pe=$2 pl=$3 seg ss se sl rest
  local -a out=()
  for seg in "${SEGS[@]}"; do
    ss=${seg%% *}
    rest=${seg#* }
    se=${rest%% *}
    sl=${rest#* }
    if [ "$se" -le "$ps" ] || [ "$ss" -ge "$pe" ]; then
      out+=("$seg")
      continue
    fi
    if [ "$ss" -lt "$ps" ]; then out+=("$ss $ps $sl"); fi
    if [ "$se" -gt "$pe" ]; then out+=("$pe $se $sl"); fi
  done
  out+=("$ps $pe $pl")
  SEGS=("${out[@]}")
}

# 0 when "<start> <end> <label>" entry $1 sorts before $2: start ascending,
# then end descending (outer before inner), then B before K — so on an
# identical range K is painted last and wins.
entry_before() {
  local s1=${1%% *} s2=${2%% *} r1=${1#* } r2=${2#* }
  local e1=${r1%% *} e2=${r2%% *} l1=${r1#* } l2=${r2#* }
  if [ "$s1" -ne "$s2" ]; then [ "$s1" -lt "$s2" ]; return; fi
  if [ "$e1" -ne "$e2" ]; then [ "$e1" -gt "$e2" ]; return; fi
  [ "$l1" = B ] && [ "$l2" = K ]
}

# Insertion sort of SORT_IN into SORT_OUT — a handful of entries, and no
# sort(1) process on a hook that runs before every Bash call.
SORT_IN=()
SORT_OUT=()
sort_entries() {
  local x y placed
  local -a merged
  SORT_OUT=()
  for x in "${SORT_IN[@]+"${SORT_IN[@]}"}"; do
    merged=()
    placed=0
    for y in "${SORT_OUT[@]+"${SORT_OUT[@]}"}"; do
      if [ "$placed" = 0 ] && entry_before "$x" "$y"; then
        merged+=("$x")
        placed=1
      fi
      merged+=("$y")
    done
    if [ "$placed" = 0 ]; then merged+=("$x"); fi
    SORT_OUT=("${merged[@]}")
  done
}

# ── Analysis ─────────────────────────────────────────────────────────────────

SHELL_INVOKERS='sh|bash|zsh|ksh|dash|ash|mksh|yash|fish|eval|su|runuser|script|flock|watch'
QUEUE=()
REASON=""

# 0 when the `#` at byte $2 of $1 starts a comment for the shell: it opens a
# word, so it is the first byte or follows a blank or `;`, `&`, `|` that no odd
# run of backslashes escapes. tree-sitter-bash also opens a comment after an
# escaped blank (`\ #`, `\<TAB>#`, `\<newline>#`), where the shell keeps `#` in
# the word and runs the rest of the line. Anything else is kept, not blanked.
comment_opens_word() {
  local text=$1 at=$2 j n=0
  [ "${text:at:1}" = "#" ] || return 1
  [ "$at" -gt 0 ] || return 0
  case ${text:at-1:1} in
    ' ' | $'\t' | $'\n' | ';' | '&' | '|') ;;
    *) return 1 ;;
  esac
  for ((j = at - 2; j >= 0; j--)); do
    [ "${text:j:1}" = "$BACKSLASH" ] || break
    n=$((n + 1))
  done
  [ $((n % 2)) = 0 ]
}

# Structural pass over one snippet. Sets REASON on the first destructive
# invocation. With $2 = 1 (the top-level command) it also computes RESIDUE.
RESIDUE=""
HAS_PARSE_ERROR=0
analyse() {
  local snippet=$1 top=$2
  local nodes rid s e key text t k first base owned invoker
  local inert_keys=" " piped_keys=" " cmd_list=() paint_list=()
  nodes=$(nodes_of "$snippet")
  if [ "$top" = 1 ]; then TOP_NODES=$nodes; fi

  while read -r rid s e; do
    [ -n "$rid" ] || continue
    case $rid in
      inert-cmd) inert_keys+="$s:$e " ;;
      sh-piped) piped_keys+="$s:$e " ;;
    esac
  done <<<"$nodes"

  while read -r rid s e; do
    [ -n "$rid" ] || continue
    case $rid in
      perr) HAS_PARSE_ERROR=1 ;;
      comment)
        if comment_opens_word "$snippet" "$s"; then
          paint_list+=("$s $e B")
        else
          paint_list+=("$s $e K")
        fi
        ;;
      inert-cmd | inert-stmt) paint_list+=("$s $e B") ;;
      subst | hot-stmt) paint_list+=("$s $e K") ;;
      sh-heredoc) QUEUE+=("${snippet:s:e-s}") ;;
      cmd) cmd_list+=("$s $e") ;;
    esac
  done <<<"$nodes"

  for key in "${cmd_list[@]+"${cmd_list[@]}"}"; do
    read -r s e <<<"$key"
    case $inert_keys in *" $s:$e "*) continue ;; esac
    text=${snippet:s:e-s}
    tokenize "$text"
    t=${#TOK_VAL[@]}
    owned=0

    # A shell invoker anywhere in the word list makes every quoted or escaped
    # argument a script: re-parse it as shell. No option parsing — the
    # withdrawn attempts lost `--norc` and `--rcfile X` to exactly that. A
    # command whose output is piped into a shell (`echo '…' | sh`) gets the same
    # treatment, since its quoted arguments become that shell's script.
    invoker=0
    case $piped_keys in *" $s:$e "*) invoker=1 ;; esac
    for ((k = 0; k < t; k++)); do
      base=${TOK_VAL[k]##*/}
      if [ "${TOK_E[k]}" = 0 ] && [[ $base =~ ^($SHELL_INVOKERS)$ ]]; then
        invoker=1
        break
      fi
    done
    if [ "$invoker" = 1 ]; then
      for ((k = 0; k < t; k++)); do
        if [ "${TOK_Q[k]}" = 1 ]; then QUEUE+=("${TOK_VAL[k]#<<<}"); fi
      done
    fi

    # The first word that is not a NAME=value assignment is the program.
    first=-1
    for ((k = 0; k < t; k++)); do
      if [[ ${TOK_VAL[k]} =~ ^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?= ]]; then continue; fi
      first=$k
      break
    done

    RSN=""
    for ((k = 0; k < t; k++)); do
      if [ "${TOK_E[k]}" = 0 ] && [ "${TOK_VAL[k]##*/}" = rm ]; then
        rm_reason "$k"
        if [ -n "$RSN" ]; then REASON=$RSN; return 0; fi
        if [ "$k" = "$first" ]; then owned=1; fi
        break
      fi
    done
    for ((k = 0; k < t; k++)); do
      if [ "${TOK_E[k]}" = 0 ] && [ "${TOK_VAL[k]##*/}" = git ]; then
        git_reason "$k"
        if [ -n "$RSN" ]; then REASON=$RSN; return 0; fi
        break
      fi
    done

    if [ "$owned" = 1 ]; then
      paint_list+=("$s $e B")
    else
      paint_list+=("$s $e K")
    fi
  done

  [ "$top" = 1 ] || return 0

  # Paint outer before inner; on an identical range, B before K so that K wins.
  local entry ps pe pl rest res=""
  SEGS=("0 ${#snippet} K")
  SORT_IN=("${paint_list[@]+"${paint_list[@]}"}")
  sort_entries
  for entry in "${SORT_OUT[@]+"${SORT_OUT[@]}"}"; do
    ps=${entry%% *}
    rest=${entry#* }
    paint "$ps" "${rest%% *}" "${rest#* }"
  done
  SORT_IN=("${SEGS[@]}")
  sort_entries
  for entry in "${SORT_OUT[@]}"; do
    ps=${entry%% *}
    rest=${entry#* }
    pe=${rest%% *}
    pl=${rest#* }
    if [ "$pl" = K ]; then
      res+=${snippet:ps:pe-ps}
    else
      res+=$'\001'
    fi
  done
  RESIDUE=$res
  return 0
}

analyse "$COMMAND" 1
if [ -n "$REASON" ]; then
  create_checkpoint "$REASON"
  exit 0
fi

# Re-parse shell-invoker scripts, breadth first, bounded in depth and count.
depth=0
reentered=0
while [ "${#QUEUE[@]}" -gt 0 ] && [ "$depth" -lt 3 ] && [ "$reentered" -lt 16 ]; do
  current=("${QUEUE[@]}")
  QUEUE=()
  for snippet in "${current[@]}"; do
    reentered=$((reentered + 1))
    [ "$reentered" -le 16 ] || break
    [ -n "$snippet" ] || continue
    analyse "$snippet" 0
    if [ -n "$REASON" ]; then
      create_checkpoint "$REASON"
      exit 0
    fi
  done
  depth=$((depth + 1))
done

# A parse with an ERROR node is a shape tree-sitter did not understand, so no
# span of it is trusted as inert: the old matcher reads the whole command.
if [ "$HAS_PARSE_ERROR" = 1 ]; then
  checkpoint_if_legacy "$COMMAND"
  exit 0
fi

# The old matcher needs a literal `rm` or `git` in the text it reads; a residue
# without either cannot fire it, so skip the five greps.
case $RESIDUE in
  *rm* | *git*) checkpoint_if_legacy "$RESIDUE" ;;
esac

# The residue is clean. If the whole command fires the old matcher, it does so
# only through the blanked spans, and blanking is an exemption that holds for
# allowlisted shapes alone (exemption_holds). Otherwise the old matcher's
# verdict over the whole command stands, exactly as before #2652. Checked last,
# so the common command pays for no extra tokenising.
legacy_reason "$COMMAND"
if [ -n "$LEGACY_REASON" ] && ! exemption_holds; then
  create_checkpoint "$LEGACY_REASON"
fi
exit 0

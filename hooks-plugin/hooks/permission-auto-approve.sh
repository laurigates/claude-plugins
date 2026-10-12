#!/usr/bin/env bash
# PermissionRequest hook — auto-approve safe operations, auto-deny dangerous ones
#
# Toggle: set CLAUDE_HOOKS_DISABLE_PERMISSION_AUTO=1 to skip this hook
#
# Matches: Bash (and optionally all tools)
# Approves: read-only git, test runners, linters — only when EVERY command in
#           the command line is one of them (see below)
# Denies: destructive filesystem ops, force push to protected branches
# Passes through: everything else (user decides)
#
# Customize the APPROVE and DENY patterns below for your project.
#
# ── Why approval is decided per parsed command node (#2733) ──────────────────
#
# The approve rules used to be `grep -Eq '^\s*git\s+(status|…)'` over the raw
# command string. grep anchors `^` at every LINE, and nothing looked past the
# first statement, so `git status && touch x`, `npm test; chmod -R 777 .` and
# `git log -1<newline>touch x` were all approved as a whole — and because the
# deny rules ran after the approve rules, `git status && rm -rf /` was approved
# without the deny rule ever being reached.
#
# Now:
#   1. The deny rules run FIRST, on the raw text (over-denying is the safe
#      polarity for a deny rule, so they stay regexes).
#   2. The command is parsed with `ast-grep --lang bash` (tree-sitter-bash), as
#      terraform-plugin/hooks/validate-terraform-apply.sh (#2506) and
#      auto-checkpoint.sh (#2652) do, and approval requires that:
#        - the parse has no ERROR node and no empty (MISSING) command node;
#        - every byte outside the command nodes is a list/pipeline separator
#          (`&&` `||` `;` `|` `&` newline) or whitespace — so a subshell, group,
#          loop, conditional, function, redirection, heredoc or comment, all of
#          which leave their own syntax outside the command node, yields no
#          decision;
#        - every command node's own bytes contain no expansion, substitution,
#          redirection, escape or separator character ($ ` ( ) < > ; & | \ #
#          or a newline) — so `$(…)`, `<(…)`, `$VAR` and a quoted multi-line
#          argument yield no decision even where they sit inside the node;
#        - every command node matches one of the approve rules below, which
#          keep their pre-#2733 meaning but are now matched against the node's
#          own text instead of the raw string.
#      The node bytes are sliced from the raw command by the parser's byte
#      offsets, so a parser that misreports node boundaries cannot smuggle a
#      separator past the per-node character check.
#   3. With no ast-grep, a failing / garbled / timed-out parse (5 s), or any
#      condition above unmet, the hook emits NO decision. For an allow hook the
#      safe fallback is "ask the user", never the old regex.

set -euo pipefail

# Toggle off
[ "${CLAUDE_HOOKS_DISABLE_PERMISSION_AUTO:-}" = "1" ] && exit 0

# Byte semantics for ${COMMAND:offset:length}: ast-grep reports byte offsets.
LC_ALL=C

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only handle Bash commands
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

[ -z "$COMMAND" ] && exit 0

# --- AUTO-DENY: Dangerous operations (before approve, on the raw text) ---
#
# Two layers, and either one denies (over-denying is the safe polarity):
#   1. The original raw-text regexes, kept as a floor.
#   2. A word-level read of every statement (#2885), so respellings the
#      regexes miss are caught too: `rm -r -f /`, `rm -rf -- /`, `rm -Rf "$HOME"`,
#      `git push -f origin main`, `git push origin +main`. Statements are split
#      on ; & | ( ) ` and newlines, words on whitespace, and quotes are dropped.
#      That is cruder than bash, deliberately: it can only add denials.

# A recursive rm target that is the filesystem root or the home directory.
# shellcheck disable=SC2016  # $HOME is matched literally, not expanded
DANGEROUS_RM_TARGET='^(/|~|\$HOME|\$\{HOME\})/*(\.|\*)?/*$'
# A push refspec (or its destination) naming a protected branch.
PROTECTED_REF='(^|:)\+?(refs/heads/)?(main|master)$'

# Prints a deny reason for the raw command, or returns 1.
deny_reason() {
  local cmd=$1 stmt w i j n sub recursive dangerous force protected plus
  local -a words
  # shellcheck disable=SC2016  # $HOME is a grep pattern, not shell expansion
  if grep -Eq 'rm\s+(-rf|-fr)\s+(/|~/|\$HOME)' <<<"$cmd"; then
    echo "Destructive operation on root or home directory"
    return 0
  fi
  if grep -Eq 'git\s+push\s+.*--force.*\s(main|master)\b' <<<"$cmd"; then
    echo "Force push to protected branch"
    return 0
  fi
  cmd=${cmd//[;&|()\`$'\r']/$'\n'}
  while IFS= read -r stmt; do
    read -ra words <<<"$stmt" || true
    n=${#words[@]}
    for ((i = 0; i < n; i++)); do
      w=${words[i]//[\"\']/}
      words[i]=${w#\\}
    done
    for ((i = 0; i < n; i++)); do
      case ${words[i]##*/} in
        rm)
          recursive=false
          dangerous=false
          for w in "${words[@]:i+1}"; do
            if [[ $w =~ ^-[a-zA-Z]*[rR] ]] || [ "$w" = --recursive ]; then
              recursive=true
            elif [[ $w =~ $DANGEROUS_RM_TARGET ]]; then
              dangerous=true
            fi
          done
          if $recursive && $dangerous; then
            echo "Destructive operation on root or home directory"
            return 0
          fi
          ;;
        git)
          # Skip git's global options to reach the subcommand.
          sub=""
          for ((j = i + 1; j < n; j++)); do
            case ${words[j]} in
              -C | -c | --git-dir | --work-tree | --namespace) j=$((j + 1)) ;;
              -*) ;;
              *)
                sub=${words[j]}
                break
                ;;
            esac
          done
          [ "$sub" = push ] || continue
          force=false
          protected=false
          plus=false
          for w in "${words[@]:j+1}"; do
            case $w in
              --force | --force-with-lease | --force-with-lease=*) force=true ;;
              --*) ;;
              -*) [[ $w =~ ^-[a-zA-Z]*f[a-zA-Z]*$ ]] && force=true ;;
              *)
                if [[ $w =~ $PROTECTED_REF ]]; then
                  protected=true
                  [[ $w == +* ]] && plus=true
                fi
                ;;
            esac
          done
          if { $force && $protected; } || $plus; then
            echo "Force push to protected branch"
            return 0
          fi
          ;;
      esac
    done
  done <<<"$cmd"
  return 1
}

if reason=$(deny_reason "$COMMAND"); then
  printf '{"decision": "deny", "reason": "%s"}\n' "$reason"
  exit 0
fi

# --- AUTO-APPROVE: Safe, read-only operations ---
#
# Each command node must pass two gates (#2885, #2886):
#   1. Its raw text matches the rule's regex, every program and subcommand
#      ending at a word boundary, so `pytest=1 touch x`, `pytestx`,
#      `npx jest-evil`, `make test-and-deploy` and `git statusfoo` do not match.
#   2. Its words, de-quoted the way bash would, pass the rule's argv check.
#      argv[0] must equal the program, so an assignment prefix never matches.
#      A node holding a glob or brace character ({ } * ? [ ]) gets no
#      decision, because bash would expand it into words this hook never saw
#      (`git diff {--output=/tmp/x,}`, `git diff *`).
# The argv checks are allowlists where the option space is small (git branch,
# git remote, test runners, linters) and a denylist of writer/executor flags
# for the git log/diff/show family. Anything they do not recognise falls
# through to the user's prompt.

# Splits $1 into WORDS, removing quotes as bash would. Returns 1 on a glob or
# brace character or an unbalanced quote. The per-node character gate has
# already refused $ ` \ and the separators, so quotes are the only syntax left.
# Words split on space and tab only, as bash's parser does.
WORDS=()
split_words() {
  local s=$1 c q="" w="" inword=false i
  WORDS=()
  [[ $s =~ [][{}*?] ]] && return 1
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then q=""; else w+=$c; fi
    elif [ "$c" = "'" ] || [ "$c" = '"' ]; then
      q=$c
      inword=true
    elif [ "$c" = " " ] || [ "$c" = $'\t' ]; then
      if $inword; then WORDS+=("$w"); fi
      w=""
      inword=false
    else
      w+=$c
      inword=true
    fi
  done
  [ -z "$q" ] || return 1
  if $inword; then WORDS+=("$w"); fi
  return 0
}

# path_ok <word>: refuses a word naming something outside the working tree or
# more arguments: an absolute, ~ or .. path (`pytest /tmp/evil_test.py`,
# `tsc -p ../x`) runs or loads code the repository does not hold, and pytest
# reads `@file` as more arguments.
path_ok() {
  [[ $1 == @* ]] && return 1
  [[ $1 == [/~]* ]] && return 1
  [[ $1 =~ (^|/)\.\.(/|$) ]] && return 1
  return 0
}

# words_ok <flags-re> <value-flags-re> <positional: yes|no|js> <word>…
# Each word must be a whole-word match of <flags-re>, a <value-flags-re> flag
# with its value (`--flag=v`, or `--flag v` when v does not start with -), or
# a positional argument. Values and positionals both pass path_ok; a value
# flag such as `-t`/`-k` takes a test-name pattern rather than a path, and one
# spelled like an absolute path going to the prompt is the safe polarity. Any
# other word starting with - is refused, however the flag is spelled. `js`
# also refuses the positional `init` (vitest scaffolding).
words_ok() {
  local flags_re=$1 value_re=$2 pos=$3 w
  shift 3
  while [ "$#" -gt 0 ]; do
    w=$1
    shift
    if [[ $w == -* ]]; then
      [[ $w =~ ^($flags_re)$ ]] && continue
      if [[ $w =~ ^($value_re)=. ]]; then
        path_ok "${w#*=}" || return 1
        continue
      fi
      if [[ $w =~ ^($value_re)$ ]] && [ "$#" -gt 0 ] && [[ $1 != -* ]]; then
        path_ok "$1" || return 1
        shift
        continue
      fi
      return 1 # an unknown flag, or a value flag without its value
    fi
    path_ok "$w" || return 1
    case $pos in
      yes) ;;
      js) [ "$w" != init ] || return 1 ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# split_dd <word>…: BEFORE_DD = words before the first `--`, AFTER_DD = after.
BEFORE_DD=()
AFTER_DD=()
split_dd() {
  local seen=false w
  BEFORE_DD=()
  AFTER_DD=()
  for w in "$@"; do
    if ! $seen && [ "$w" = -- ]; then
      seen=true
    elif $seen; then
      AFTER_DD+=("$w")
    else
      BEFORE_DD+=("$w")
    fi
  done
}

NONE='[^-].*' # a flags-re that no flag (a word starting with -) can match

# git log/diff/show/…: refuse --output (writes a file) and --ext-diff /
# --textconv (run configured programs). git does not abbreviate these today;
# a prefix spelling of 3+ letters is refused anyway (`--text` is its own option).
git_no_writer_flags() {
  local w name
  for w in "$@"; do
    [[ $w == --?* ]] || continue
    name=${w#--}
    name=${name%%=*}
    case $name in output | ext-diff | textconv) return 1 ;; esac
    if [ "${#name}" -ge 3 ] && [ "$name" != text ]; then
      [[ output == "$name"* || ext-diff == "$name"* || textconv == "$name"* ]] && return 1
    fi
  done
  return 0
}

# git branch: listing only. A bare positional creates a branch unless a list
# mode flag (--list, --contains, --merged, --points-at, …) is present. `-l` is
# left out: before git 2.20 it meant --create-reflog.
git_branch_ok() {
  local list=false w positional=0
  while [ "$#" -gt 0 ]; do
    w=$1
    shift
    case $w in
      -a | --all | -r | --remotes | -v | -vv | --verbose | --show-current | -i | --ignore-case | \
        --color | --no-color | --column | --no-column | --omit-empty | --no-abbrev) ;;
      --list) list=true ;;
      --contains=* | --no-contains=* | --merged=* | --no-merged=* | --points-at=*) list=true ;;
      --sort=* | --format=* | --color=* | --column=* | --abbrev=*) ;;
      --contains | --no-contains | --merged | --no-merged | --points-at | --sort | --format)
        case $w in --sort | --format) ;; *) list=true ;; esac
        # Consume the value only when it cannot be another flag.
        if [ "$#" -gt 0 ] && [[ $1 != -* ]]; then shift; fi
        ;;
      *)
        [[ $w == -* ]] && return 1
        positional=$((positional + 1))
        ;;
    esac
  done
  [ "$positional" -eq 0 ] || $list
}

# git remote: no arguments, -v, `show [-n] <name>…` or `get-url [--push] [--all] <name>`.
git_remote_ok() {
  case ${1:-} in -v | --verbose) shift ;; esac
  [ "$#" -eq 0 ] && return 0
  local sub=$1
  shift
  case $sub in
    show) words_ok '-n' "$NONE" yes "$@" ;;
    get-url) words_ok '--push|--all' "$NONE" yes "$@" ;;
    *) return 1 ;;
  esac
}

git_ok() {
  [ "$#" -gt 0 ] || return 1
  local sub=$1
  shift
  case $sub in
    branch) git_branch_ok "$@" ;;
    remote) git_remote_ok "$@" ;;
    status | log | diff | show | blame | shortlog | describe | ls-files | rev-parse | rev-list)
      git_no_writer_flags "$@"
      ;;
    *) return 1 ;;
  esac
}

# Flags a JS test runner (vitest, jest, or the script behind `npm test`) may
# take. Not -u/--update/--updateSnapshot (rewrites snapshots), --config,
# --reporter, --outputFile, --setupFiles or anything else that names a file.
JS_RUNNER_FLAGS='--run|--watch=false|--no-watch|--silent|--verbose|--bail|--bail=[0-9]+|--passWithNoTests|--ci|-i|--runInBand|--maxWorkers=[0-9]+%?|--coverage|--changed|--onlyChanged|--detectOpenHandles'
JS_RUNNER_VALUES='-t|--testNamePattern'

# runner_ok <argv>…: argv[0..1] were already matched against the rule.
runner_ok() {
  case $1 in
    npm)
      # npm's own flags (before --) include --script-shell, which runs a program.
      split_dd "${@:3}"
      words_ok '--silent|-s|--if-present' "$NONE" no ${BEFORE_DD[@]+"${BEFORE_DD[@]}"} &&
        words_ok "$JS_RUNNER_FLAGS" "$JS_RUNNER_VALUES" js ${AFTER_DD[@]+"${AFTER_DD[@]}"}
      ;;
    npx) words_ok "$JS_RUNNER_FLAGS" "$JS_RUNNER_VALUES" js "${@:3}" ;;
    bun)
      # Not -u/--update-snapshots, --preload, -c/--config.
      words_ok '--bail|--bail=[0-9]+|--only|--todo|--coverage' \
        '-t|--test-name-pattern|--timeout|--rerun-each' yes "${@:3}"
      ;;
    pytest)
      # Not -p (imports a plugin), -c/--rootdir/-o (config), --basetemp (it is
      # deleted and recreated), -W (imports a warning class), @argsfile.
      words_ok '-[xvsql]+|-r[a-zA-Z]+|--exitfirst|--showlocals|--lf|--last-failed|--ff|--failed-first|--nf|--new-first|--sw|--stepwise|--co|--collect-only|--no-header|--no-summary|--strict-markers|--tb=[a-z]+|--maxfail=[0-9]+|--durations=[0-9]+|-n[0-9]+|--color=(yes|no|auto)' \
        '-k|-m|--maxfail|--tb|--durations|-n|--deselect|--ignore' yes "${@:2}"
      ;;
    cargo)
      # Not --config, -Z, --manifest-path, --target-dir; after --, not --logfile.
      split_dd "${@:3}"
      words_ok '--workspace|--all|--release|--lib|--bins|--tests|--examples|--benches|--all-targets|--doc|--all-features|--no-default-features|--no-fail-fast|--no-run|-q|--quiet|-v|-vv|--verbose|--locked|--offline|--frozen|-j[0-9]+' \
        '-p|--package|-F|--features|--test|--bin|--example|--exclude|-j|--jobs' yes ${BEFORE_DD[@]+"${BEFORE_DD[@]}"} &&
        words_ok '--nocapture|--show-output|--ignored|--include-ignored|--exact|-q|--quiet|--list' \
          '--test-threads|--skip' yes ${AFTER_DD[@]+"${AFTER_DD[@]}"}
      ;;
    go)
      # Not -exec, -toolexec, -o, -c, -coverprofile, -args, -mod.
      words_ok '-v|-race|-short|-cover|-failfast|-json|-benchmem' \
        '-run|-skip|-count|-timeout|-bench|-tags|-parallel|-cpu|-shuffle' yes "${@:3}"
      ;;
    make)
      # Exactly `make test`: a further target, VAR=value (SHELL=…), -f or -C
      # would run something else, so no positional and no value flags.
      words_ok '-k|--keep-going|-s|--silent|--quiet|-j[0-9]*' "$NONE" no "${@:3}"
      ;;
    *) return 1 ;;
  esac
}

# linter_ok <argv>…: argv[0..2] were already matched against the rule.
linter_ok() {
  case $1 in
    npx)
      case $2 in
        eslint)
          # Not --fix, -c/--config, --rulesdir, --plugin, -o/--output-file, -f.
          words_ok '--quiet|--fix-dry-run|--no-eslintrc|--no-inline-config|--report-unused-disable-directives|--no-error-on-unmatched-pattern|--no-warn-ignored|--color|--no-color' \
            '--max-warnings|--ext' yes "${@:3}"
          ;;
        prettier)
          # Not --write/-w, --plugin, --config.
          words_ok '--check|-c|--list-different|-l|--no-color' "$NONE" yes "${@:3}"
          ;;
        biome)
          # Not --write, --fix, --apply, --apply-unsafe, --unsafe, --config-path.
          case ${3:-} in check | lint | format | ci) ;; *) return 1 ;; esac
          words_ok '--error-on-warnings|--no-errors-on-unmatched|--verbose|--changed|--staged' \
            '--diagnostic-level|--max-diagnostics' yes "${@:4}"
          ;;
        *) return 1 ;;
      esac
      ;;
    bun) [ "$#" -eq 3 ] ;; # exactly `bun run lint` / `bun run check`
    ruff)
      # Not --fix, --fix-only, --unsafe-fixes, --add-noqa, -o, --config, --watch.
      words_ok '--statistics|--show-fixes|--diff|--no-fix|-q|--quiet|-s|--silent|--no-cache|--exit-zero|-e|--preview' \
        '--output-format|--select|--ignore|--extend-select|--target-version|--line-length' yes "${@:3}"
      ;;
    mypy)
      # Not --install-types, --config-file (loads plugins), --python-executable,
      # --cache-dir, --junit-xml or any --*-report directory.
      words_ok '--strict|--ignore-missing-imports|--no-error-summary|--pretty|--show-error-codes|--show-column-numbers|--no-incremental|--warn-unused-ignores|--check-untyped-defs|--disallow-untyped-defs|--explicit-package-bases|--namespace-packages|--show-traceback|-v|--verbose' \
        '-p|--package|-m|--module|--python-version|--follow-imports' yes "${@:2}"
      ;;
    tsc)
      # Not --outDir/--outFile, --build, --incremental, --generateTrace.
      words_ok '--noEmit|--pretty|--strict|--skipLibCheck|--noErrorTruncation|--listFiles|--extendedDiagnostics|--diagnostics' \
        '-p|--project' yes "${@:3}"
      ;;
    *) return 1 ;;
  esac
}

# Prints the approve reason for ONE command node's text, or returns 1.
approve_reason() {
  local node=$1
  split_words "$node" || return 1
  [ "${#WORDS[@]}" -gt 0 ] || return 1
  # Read-only git operations
  if grep -Eq '^\s*git\s+(status|log|diff|branch|remote|show|blame|shortlog|describe|ls-files|rev-parse|rev-list)(\s|$)' <<<"$node"; then
    [ "${WORDS[0]}" = git ] || return 1
    git_ok "${WORDS[@]:1}" || return 1
    echo "Read-only git operation"
  # Test runners (fail-fast; no flag that runs a named program or writes outside the tree)
  elif grep -Eq '^\s*(npm\s+test|npx\s+(vitest|jest)|bun\s+test|pytest|cargo\s+test|go\s+test|make\s+test)(\s|$)' <<<"$node"; then
    case ${WORDS[0]}:${WORDS[1]:-} in
      npm:test | npx:vitest | npx:jest | bun:test | pytest:* | cargo:test | go:test | make:test) ;;
      *) return 1 ;;
    esac
    runner_ok "${WORDS[@]}" || return 1
    echo "Test execution"
  # Linters and formatters (read-only check mode)
  elif grep -Eq '^\s*(npx\s+(biome|eslint|prettier)|bun\s+run\s+(lint|check)|ruff\s+check|mypy|tsc\s+--noEmit)(\s|$)' <<<"$node"; then
    case ${WORDS[0]}:${WORDS[1]:-}:${WORDS[2]:-} in
      npx:biome:* | npx:eslint:* | npx:prettier:* | bun:run:lint | bun:run:check | ruff:check:* | mypy:*:* | tsc:--noEmit:*) ;;
      *) return 1 ;;
    esac
    linter_ok "${WORDS[@]}" || return 1
    echo "Linter/formatter check"
  # gh CLI read operations (these verbs take no writer or executor flags)
  elif grep -Eq '^\s*gh\s+(pr\s+(view|checks|list|diff)|issue\s+(view|list)|run\s+(view|list))(\s|$)' <<<"$node"; then
    case ${WORDS[0]}:${WORDS[1]:-}:${WORDS[2]:-} in
      gh:pr:view | gh:pr:checks | gh:pr:list | gh:pr:diff | gh:issue:view | gh:issue:list | gh:run:view | gh:run:list) ;;
      *) return 1 ;;
    esac
    echo "GitHub CLI read operation"
  else
    return 1
  fi
}

# `sg` collides with shadow-utils' sg(1); adopt it only if it IS ast-grep (#2451).
ASTGREP=""
if command -v ast-grep >/dev/null 2>&1; then
  ASTGREP="ast-grep"
elif command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'; then
  ASTGREP="sg"
fi
[ -n "$ASTGREP" ] || exit 0

# Empty when coreutils `timeout` is absent (stock macOS); the `+` expansion
# below keeps an empty array legal under `set -u` on bash < 4.4.
TIMEOUT=()
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT=(timeout 5)
fi

AST_RULES='id: command
language: bash
rule:
  kind: command
---
id: error
language: bash
rule:
  kind: ERROR
'

# Any parser failure (missing, non-zero exit, timeout) => no decision.
PARSE=$(printf '%s' "$COMMAND" \
  | ${TIMEOUT[@]+"${TIMEOUT[@]}"} "$ASTGREP" scan --inline-rules "$AST_RULES" --stdin --json=compact 2>/dev/null) || exit 0

# One "<start> <end>" line per command node in source order, or "ERROR".
# Garbage output fails jq => no decision.
NODES=$(printf '%s' "$PARSE" | jq -r '
  if any(.[]; .ruleId != "command") then "ERROR"
  else sort_by(.range.byteOffset.start)[] | "\(.range.byteOffset.start) \(.range.byteOffset.end)"
  end' 2>/dev/null) || exit 0
[ -n "$NODES" ] || exit 0

# Separators a plain list/pipeline may leave between command nodes.
SEPARATORS='^[[:space:];&|]*$'
# Characters a plain command node may not contain.
UNSAFE_NODE_CHARS=$'[$`()<>;&|\\#\n\r]'

LEN=${#COMMAND}
pos=0
reason=""
while read -r start end; do
  [ "$start" = "ERROR" ] && exit 0
  [[ $start =~ ^[0-9]+$ && $end =~ ^[0-9]+$ ]] || exit 0
  # Overlapping, empty, or out-of-range node => no decision.
  if [ "$start" -lt "$pos" ] || [ "$end" -le "$start" ] || [ "$end" -gt "$LEN" ]; then
    exit 0
  fi
  [[ ${COMMAND:pos:start-pos} =~ $SEPARATORS ]] || exit 0
  node=${COMMAND:start:end-start}
  [[ $node =~ $UNSAFE_NODE_CHARS ]] && exit 0
  node_reason=$(approve_reason "$node") || exit 0
  [ -n "$reason" ] || reason=$node_reason
  pos=$end
done <<<"$NODES"
[[ ${COMMAND:pos} =~ $SEPARATORS ]] || exit 0
[ -n "$reason" ] || exit 0

printf '{"decision": "approve", "reason": "%s"}\n' "$reason"
exit 0

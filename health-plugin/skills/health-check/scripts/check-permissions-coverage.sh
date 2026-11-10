#!/usr/bin/env bash
# Check Permissions Coverage (health-check 1d)
# Compares the commands a project's task files run against the Bash allow rules
# in the user, project and project-local settings files. ~/.claude/settings.local.json
# is local scope for the home directory, so Claude Code reads it only in a
# session started there (https://code.claude.com/docs/en/permissions, "When
# your local settings file needs trust"); it is read only when --project-dir is
# the home directory, as that project's local file.
#
# Scanned: justfile / Justfile recipe lines, Makefile recipe lines (TAB-led),
# and .pre-commit-config.yaml `entry:` values. Each line is split on && || ; |
# outside quotes, the way Claude Code splits a compound command. A quoted
# string that runs onto later lines, a here-document body and a `#` comment
# are skipped. The wrappers Claude Code strips (timeout, time, nice, nohup,
# stdbuf, command, builtin, noglob) are dropped before matching. A leading
# VAR=value assignment is dropped only for NODE_ENV, the one variable the docs
# name as stripped ("certain known-safe environment variables"); any other
# assignment stays in the matched text, because "an allow rule won't match
# past an assignment of any other variable". This is a line scanner, not a
# shell parser, so a first word that is not on PATH, not a file in the project
# and not ./-prefixed is reported as TOOL=<word> STATE=unresolved (verbose) and
# counted in TOOLS_UNRESOLVED, never in STATUS.
#
# Rule forms accepted: bare `Bash`, `Bash(*)` (match everything), the
# space-wildcard form `Bash(git status *)`, the legacy `Bash(git status:*)`
# form, and any rule with `*` elsewhere. A trailing ` *` that is the rule's
# only wildcard also matches the bare command, as in the permissions docs.
#
# Commands Claude Code runs without a rule (its documented read-only set: ls,
# cat, echo, pwd, head, tail, grep, find, wc, which, diff, stat, du, cd) and
# shell keywords/builtins are not counted.
#
# Scoring (distinct tools with at least one unmatched command):
#   0 -> OK, 1-3 -> WARN, 4+ -> ERROR.
# Allow rules in the project files whose tool no scanned file runs are listed
# as UNUSED_RULE (informational, never a finding).
#
# Exit 0 on OK/WARN, 1 on ERROR.
# Usage: bash check-permissions-coverage.sh --home-dir <path> --project-dir <path> [--verbose]

set -uo pipefail

home_dir=""
project_dir=""
verbose_mode=false

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --verbose) verbose_mode=true; shift ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

echo "=== PERMISSIONS COVERAGE ==="

# Associative arrays need bash 4+. macOS /bin/bash is 3.2, and an agent
# subshell can start with a /usr/bin:/bin PATH, so fail loudly there instead of
# stopping mid-run with no STATUS line.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "STATUS=ERROR"
  echo "REASON=bash_too_old: bash ${BASH_VERSION:-unknown} has no associative arrays; run with bash 4 or later"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=bash_too_old BASH_VERSION=${BASH_VERSION:-unknown} MSG=bash 4 or later is required; put a newer bash (e.g. Homebrew's) first on PATH"
  echo "=== END PERMISSIONS COVERAGE ==="
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "REASON=missing_tool: jq is required to read permissions.allow"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required to read permissions.allow"
  echo "=== END PERMISSIONS COVERAGE ==="
  exit 1
fi
echo "JQ_AVAILABLE=true"

# ---------------------------------------------------------------------------
# Allow rules
# ---------------------------------------------------------------------------
# No USER_LOCAL entry: with --project-dir at the home directory,
# PROJECT_LOCAL_SETTINGS is ~/.claude/settings.local.json; anywhere else Claude
# Code does not read that file.
declare -A settings_paths=(
  [USER_SETTINGS]="${home_dir}/.claude/settings.json"
  [PROJECT_SETTINGS]="${project_dir}/.claude/settings.json"
  [PROJECT_LOCAL_SETTINGS]="${project_dir}/.claude/settings.local.json"
)

bash_globs=()      # one glob per Bash rule, ready for [[ == ]]
project_rules=()   # Bash rule bodies from project + project-local files
allow_all=false

# rule_body_to_glob <body>: escape glob specials except '*', and turn the
# legacy trailing ':*' into ' *'.
rule_body_to_glob() {
  local rule_body="$1" glob_out=""
  if [[ "$rule_body" == *':*' ]]; then
    rule_body="${rule_body%:\*} *"
  fi
  local i ch
  for (( i = 0; i < ${#rule_body}; i++ )); do
    ch="${rule_body:i:1}"
    case "$ch" in
      "\\"|'['|']'|'?') glob_out+="\\${ch}" ;;
      *) glob_out+="$ch" ;;
    esac
  done
  printf '%s' "$glob_out"
}

for settings_key in USER_SETTINGS PROJECT_SETTINGS PROJECT_LOCAL_SETTINGS; do
  settings_file="${settings_paths[$settings_key]}"
  if [ ! -f "$settings_file" ]; then
    echo "${settings_key}=MISSING"
    continue
  fi
  if ! rules_raw=$(jq -r '.permissions.allow // [] | .[] | strings' "$settings_file" 2>/dev/null); then
    echo "${settings_key}=INVALID"
    continue
  fi
  echo "${settings_key}=OK"
  while IFS= read -r rule_line; do
    rule_line="${rule_line%$'\r'}"
    [ -z "$rule_line" ] && continue
    if [ "$rule_line" = "Bash" ] || [ "$rule_line" = "Bash(*)" ]; then
      allow_all=true
      continue
    fi
    [[ "$rule_line" == Bash\(*\) ]] || continue
    rule_body="${rule_line#Bash(}"
    rule_body="${rule_body%)}"
    bash_globs+=("$(rule_body_to_glob "$rule_body")")
    case "$settings_key" in
      PROJECT_SETTINGS|PROJECT_LOCAL_SETTINGS) project_rules+=("$rule_body") ;;
    esac
  done <<< "$rules_raw"
done

echo "BASH_ALLOW_RULES=${#bash_globs[@]}"
echo "BASH_ALLOW_ALL=${allow_all}"

# command_is_allowed <command>: 0 when some allow rule matches.
command_is_allowed() {
  local cmd="$1" glob star_only
  [ "$allow_all" = true ] && return 0
  for glob in "${bash_globs[@]}"; do
    # shellcheck disable=SC2053 # unquoted RHS is the pattern on purpose
    [[ "$cmd" == $glob ]] && return 0
    # A trailing ' *' that is the only wildcard also matches the bare command.
    star_only="${glob//[^*]/}"
    if [[ "$glob" == *' *' ]] && [ "${#star_only}" -eq 1 ]; then
      [ "$cmd" = "${glob% \*}" ] && return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Commands referenced by project files
# ---------------------------------------------------------------------------
declare -A readonly_cmds=(
  [ls]=1 [cat]=1 [echo]=1 [pwd]=1 [head]=1 [tail]=1 [grep]=1 [find]=1
  [wc]=1 [which]=1 [diff]=1 [stat]=1 [du]=1 [cd]=1
)
declare -A shell_words=(
  [if]=1 [then]=1 [else]=1 [elif]=1 [fi]=1 [for]=1 [while]=1 [until]=1
  [do]=1 [done]=1 [case]=1 [esac]=1 [function]=1 [return]=1 [exit]=1
  [set]=1 [export]=1 [local]=1 [unset]=1 [shift]=1 [true]=1 [false]=1
  [test]=1 [:]=1 [source]=1 [.]=1 [printf]=1 [read]=1 [eval]=1 [exec]=1
  [trap]=1 [wait]=1 [declare]=1 [readonly]=1
)

declare -A tool_seen=()          # every tool name a file runs (incl. exempt)
declare -A tool_missing_cmd=()   # tool -> first unmatched command
declare -A tool_missing_file=()  # tool -> file it came from
declare -A tool_counted=()       # tools that need a rule (non-exempt)
declare -A tool_unresolved=()    # first words that resolve to no program
tool_order=()                    # stable report order of counted tools
unresolved_order=()

# Leading assignments Claude Code strips before matching allow rules. The docs
# name only NODE_ENV ("so `Bash(npm test *)` matches `NODE_ENV=test npm test`");
# the full list is not published, so nothing else is assumed safe.
safe_env_names=" NODE_ENV "

# tool_resolves <word>: on PATH, a ./-prefixed path, or a file that exists
# (absolute, or relative to the project).
tool_resolves() {
  local tool_word="$1"
  [[ "$tool_word" == ./* ]] && return 0
  command -v "$tool_word" >/dev/null 2>&1 && return 0
  [ -e "$tool_word" ] && return 0
  [ -e "${project_dir}/${tool_word}" ] && return 0
  return 1
}

# record_segment <file-label> <segment>
record_segment() {
  local file_label="$1" segment="$2"
  local -a words=()
  local kept_assignments="" assign_name
  read -r -a words <<< "$segment"
  # Leading VAR=value assignments: drop the documented safe ones, keep the rest
  # in the text matched against allow rules.
  while [ "${#words[@]}" -gt 0 ] && [[ "${words[0]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    # `x=$(cmd ...)` runs cmd inside a substitution; the words after the
    # assignment are its arguments, not a command this scanner can name.
    # shellcheck disable=SC2016 # literal `$(` and backtick, matched as text
    [[ "${words[0]}" == *'$('* || "${words[0]}" == *'`'* ]] && return 0
    assign_name="${words[0]%%=*}"
    if [[ "$safe_env_names" != *" ${assign_name} "* ]]; then
      kept_assignments+="${words[0]} "
    fi
    words=("${words[@]:1}")
  done
  # Drop the wrappers Claude Code strips before matching.
  while [ "${#words[@]}" -gt 0 ]; do
    case "${words[0]}" in
      time|nohup|command|builtin|noglob) words=("${words[@]:1}") ;;
      timeout) words=("${words[@]:2}") ;;
      nice)
        words=("${words[@]:1}")
        if [ "${words[0]:-}" = "-n" ]; then words=("${words[@]:2}"); fi ;;
      stdbuf)
        words=("${words[@]:1}")
        while [[ "${words[0]:-}" == -* ]]; do words=("${words[@]:1}"); done ;;
      *) break ;;
    esac
  done
  [ "${#words[@]}" -eq 0 ] && return 0
  local tool_word="${words[0]}"
  case "$tool_word" in
    ''|'#'*|*'{{'*|*'}}'*|*'$'*|*'('*|*')'*|'['|'[['|']'|']]'|'{'|'}'|'!'|-*|*=*) return 0 ;;
  esac
  # A command name is a plain word or path; anything else is a fragment of a
  # multi-line string (a jq program, a heredoc body) and is not a command.
  [[ "$tool_word" =~ ^[A-Za-z0-9_./][A-Za-z0-9_./+-]*$ ]] || return 0
  tool_seen["$tool_word"]=1
  [ -n "${readonly_cmds[$tool_word]:-}" ] && return 0
  [ -n "${shell_words[$tool_word]:-}" ] && return 0
  if ! tool_resolves "$tool_word"; then
    if [ -z "${tool_unresolved[$tool_word]:-}" ]; then
      tool_unresolved["$tool_word"]="$file_label"
      unresolved_order+=("$tool_word")
    fi
    return 0
  fi
  if [ -z "${tool_counted[$tool_word]:-}" ]; then
    tool_counted["$tool_word"]=1
    tool_order+=("$tool_word")
  fi
  local full_cmd="${kept_assignments}${words[*]}"
  if ! command_is_allowed "$full_cmd"; then
    if [ -z "${tool_missing_cmd[$tool_word]:-}" ]; then
      tool_missing_cmd["$tool_word"]="$full_cmd"
      tool_missing_file["$tool_word"]="$file_label"
    fi
  fi
}

# Quote open at the end of the previous scanned line: "", "'" or '"'. A recipe
# line can open a string (a jq program, an echo message) that closes lines
# later; the text in between is an argument, not a command.
scan_quote=""

# record_line <file-label> <command line>: split on && || ; | outside quotes
# and record each segment. A segment that starts inside a quote carried over
# from an earlier line is skipped, as is everything after an unquoted `#` that
# starts a word.
record_line() {
  local file_label="$1" cmd_line="$2"
  local i ch prev=" " seg="" n=${#cmd_line} skip_seg=false
  [ -n "$scan_quote" ] && skip_seg=true
  for (( i = 0; i < n; i++ )); do
    ch="${cmd_line:i:1}"
    if [ -n "$scan_quote" ]; then
      seg+="$ch"
      if [ "$scan_quote" = '"' ] && [ "$ch" = "\\" ]; then
        i=$((i + 1)); seg+="${cmd_line:i:1}"
      elif [ "$ch" = "$scan_quote" ]; then
        scan_quote=""
      fi
      prev="$ch"
      continue
    fi
    case "$ch" in
      "\\") seg+="${ch}${cmd_line:i+1:1}"; i=$((i + 1)) ;;
      "'"|'"') scan_quote="$ch"; seg+="$ch" ;;
      '#')
        if [[ "$prev" == [[:space:]] ]]; then break; fi
        seg+="$ch" ;;
      ';'|'|'|'&')
        if [ "$ch" = '&' ] && [ "${cmd_line:i+1:1}" != '&' ]; then
          seg+="$ch"   # 2>&1, a background &: not a command separator here
        else
          [ "$ch" != ';' ] && [ "${cmd_line:i+1:1}" = "$ch" ] && i=$((i + 1))
          $skip_seg || record_segment "$file_label" "$seg"
          seg=""; skip_seg=false
        fi ;;
      *) seg+="$ch" ;;
    esac
    prev="$ch"
  done
  $skip_seg || record_segment "$file_label" "$seg"
}

scanned_files=()

scan_recipe_file() {
  # $1 = path, $2 = label, $3 = recipe-line regex, $4 = prefix chars to strip
  local recipe_path="$1" file_label="$2" line_regex="$3" strip_chars="$4"
  local raw_line body trimmed continued=false heredoc_end=""
  # `<<WORD` / `<<-'WORD'` but not a `<<<` here-string.
  local heredoc_regex="(^|[^<])<<-?[[:space:]]*[\"']?([A-Za-z_][A-Za-z0-9_]*)"
  scan_quote=""
  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    raw_line="${raw_line%$'\r'}"
    if [ -n "$heredoc_end" ]; then
      trimmed="${raw_line#"${raw_line%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      [ "$trimmed" = "$heredoc_end" ] && heredoc_end=""
      continue
    fi
    if [ "$continued" = true ]; then
      [[ "$raw_line" == *"\\" ]] || continued=false
      continue
    fi
    # A line outside any recipe ends the recipe, and any quote it left open.
    if ! [[ "$raw_line" =~ $line_regex ]]; then
      scan_quote=""
      continue
    fi
    body="${raw_line#"${raw_line%%[![:space:]]*}"}"
    [ -z "$body" ] && continue
    if [ -z "$scan_quote" ]; then
      [[ "$body" == '#'* ]] && continue
      while [ -n "$body" ] && [[ "$strip_chars" == *"${body:0:1}"* ]]; do
        body="${body:1}"
      done
    fi
    if [[ "$body" == *"\\" ]]; then
      continued=true
      body="${body%\\}"
    fi
    local quote_before="$scan_quote"
    record_line "$file_label" "$body"
    if [ -z "$quote_before" ] && [[ "$body" =~ $heredoc_regex ]]; then
      heredoc_end="${BASH_REMATCH[2]}"
      scan_quote=""
    fi
  done < "$recipe_path"
  scan_quote=""
}

for just_name in justfile Justfile; do
  just_path="${project_dir}/${just_name}"
  if [ -f "$just_path" ]; then
    scanned_files+=("$just_name")
    scan_recipe_file "$just_path" "$just_name" '^[[:space:]]+[^[:space:]]' '@-'
    break
  fi
done

if [ -f "${project_dir}/Makefile" ]; then
  scanned_files+=("Makefile")
  scan_recipe_file "${project_dir}/Makefile" "Makefile" $'^\t' '@-+'
fi

precommit_path="${project_dir}/.pre-commit-config.yaml"
if [ -f "$precommit_path" ]; then
  scanned_files+=(".pre-commit-config.yaml")
  entry_regex='^[[:space:]]*-?[[:space:]]*entry:[[:space:]]*(.+)$'
  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    raw_line="${raw_line%$'\r'}"
    [[ "$raw_line" =~ $entry_regex ]] || continue
    entry_value="${BASH_REMATCH[1]}"
    entry_value="${entry_value%%[[:space:]]#*}"
    case "$entry_value" in '>'*|'|'*) continue ;; esac
    entry_value="${entry_value#[\"\']}"
    entry_value="${entry_value%[\"\']}"
    scan_quote=""
    record_line ".pre-commit-config.yaml" "$entry_value"
    scan_quote=""
  done < "$precommit_path"
fi

if [ "${#scanned_files[@]}" -eq 0 ]; then
  echo "SCANNED_FILES=none"
else
  scanned_csv=$(printf '%s,' "${scanned_files[@]}")
  echo "SCANNED_FILES=${scanned_csv%,}"
fi

missing_count=0
for tool_word in "${tool_order[@]}"; do
  [ -n "${tool_missing_cmd[$tool_word]:-}" ] && missing_count=$((missing_count + 1))
done
echo "TOOLS_FOUND=${#tool_order[@]}"
echo "TOOLS_COVERED=$(( ${#tool_order[@]} - missing_count ))"
echo "TOOLS_MISSING=${missing_count}"
echo "TOOLS_UNRESOLVED=${#unresolved_order[@]}"

# Unused project rules: the rule's first word is a tool no scanned file runs.
unused_count=0
unused_rules=()
for rule_body in "${project_rules[@]}"; do
  rule_tool="${rule_body%% *}"
  rule_tool="${rule_tool%:\*}"
  [[ -z "$rule_tool" || "$rule_tool" == *'*'* ]] && continue
  if [ -z "${tool_seen[$rule_tool]:-}" ]; then
    unused_count=$((unused_count + 1))
    unused_rules+=("Bash(${rule_body})")
  fi
done
echo "UNUSED_RULE_COUNT=${unused_count}"

if [ "$verbose_mode" = true ]; then
  for tool_word in "${tool_order[@]}"; do
    if [ -n "${tool_missing_cmd[$tool_word]:-}" ]; then
      echo "TOOL=${tool_word} STATE=missing"
    else
      echo "TOOL=${tool_word} STATE=covered"
    fi
  done
  for tool_word in "${unresolved_order[@]}"; do
    echo "TOOL=${tool_word} STATE=unresolved FILE=${tool_unresolved[$tool_word]}"
  done
  for rule_text in "${unused_rules[@]}"; do
    echo "UNUSED_RULE=${rule_text}"
  done
fi

if [ "$missing_count" -eq 0 ]; then
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END PERMISSIONS COVERAGE ==="
  exit 0
fi

if [ "$missing_count" -ge 4 ]; then
  check_status="ERROR"
else
  check_status="WARN"
fi

issues_out=""
first_reason=""
for tool_word in "${tool_order[@]}"; do
  missing_cmd="${tool_missing_cmd[$tool_word]:-}"
  [ -z "$missing_cmd" ] && continue
  issues_out+="  - SEVERITY=${check_status} TYPE=missing_permission TOOL=${tool_word} FILE=${tool_missing_file[$tool_word]} MSG=no Bash allow rule matches: ${missing_cmd}"$'\n'
  if [ -z "$first_reason" ]; then
    first_reason="missing_permission: no Bash allow rule matches ${missing_cmd} (${tool_missing_file[$tool_word]})"
  fi
done

reason="${first_reason//[[:space:]]/ }"
reason="${reason:0:180}"
[ "$missing_count" -gt 1 ] && reason="${reason} (+$((missing_count - 1)) more)"

echo "STATUS=${check_status}"
echo "REASON=${reason}"
echo "ISSUE_COUNT=${missing_count}"
echo "ISSUES:"
printf '%s' "$issues_out"
echo "=== END PERMISSIONS COVERAGE ==="

[ "$check_status" = "ERROR" ] && exit 1
exit 0

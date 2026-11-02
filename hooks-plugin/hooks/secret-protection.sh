#!/usr/bin/env bash
# PreToolUse hook — blocks access to sensitive files and credential exposure
#
# Toggle: a human operator can export CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1
# in their shell environment to skip this hook. The toggle is only honored
# when set in the process environment — an inline prefix on the command line
# is intentionally NOT honored so that an agent cannot self-serve the bypass
# (see .claude/rules/handling-blocked-hooks.md).
#
# Matches: Read, Edit, Write, Bash
# Detects: .env files, SSH keys, cloud credentials, private keys, token files

set -euo pipefail

# Toggle off
[ "${CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION:-}" = "1" ] && exit 0

# This hook is registered with `"onFailure": "block"` (Claude Code 2.1.295+)
# on Read|Edit|Write|Bash: any exit other than 0 or 2 blocks the call, so a
# crash here would block every file read. Paths where the hook cannot apply
# exit 0 explicitly — input jq cannot parse or whose tool_input is not an
# object, and a missing jq. The missing-jq exit lets every call through: that
# is deliberate, because failing closed there would block every Read.
# scripts/check-hook-fail-closed.sh runs each of these paths.
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
printf '%s' "$INPUT" | jq -e 'type == "object" and ((.tool_input // {}) | type == "object")' >/dev/null 2>&1 || exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Every block message ends with this note. It deliberately does NOT read
# "set CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1 to override" — that phrasing
# reads to an agent as a bypass it can perform, but the toggle is only read
# from the hook's own process environment, so an inline prefix on the
# retried command does nothing (see .claude/rules/handling-blocked-hooks.md).
OVERRIDE_NOTE="If this is a false positive, delegate to the user per .claude/rules/handling-blocked-hooks.md — ask them to export CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1 in their own shell (only honored there, not inline on a command). Do not attempt to self-serve this bypass."

block() {
  echo "$1" >&2
  exit 2
}

# ── Parsed exemption for the Bash checks (issue #2737) ──────────────────────
#
# The Bash checks below match their patterns against the raw command text, so
# a commit message, a `gh issue comment --body`, a commit-message heredoc or a
# trailing comment that merely DESCRIBES a secret read (`docs: never cat .env
# in CI`) was blocked as one.
#
# This hook is protective, so the parse may only REMOVE a block, never add one,
# and every regex below still runs unchanged first. When a regex would block,
# sp_confirm re-runs the same regex anchored at each occurrence of its verb and
# keeps the block if ANY occurrence sits in text the shell executes. An
# occurrence is exempt only when the innermost quoted/heredoc/comment/
# substitution node around it (tree-sitter-bash, via `ast-grep --lang bash`) is:
#
#   - a comment;
#   - a quoted argument, or heredoc body, of a command whose text starts with
#     `git commit` or `gh issue|pr <create|comment|edit|review|close|reopen|
#     merge>` — a CLOSED allowlist of programs that send text somewhere rather
#     than run it (no leading assignment, wrapper or git global option: `git -c
#     core.editor=… commit` runs its value);
#   - the heredoc body of a bare, unredirected `cat` inside a `$(…)` that is
#     (part of) such an argument — the `git commit -m "$(cat <<'EOF' … EOF)"`
#     idiom. A `cat <<EOF > f` writes the body somewhere a later command could
#     run it, so it is not exempt.
#
# A `$(…)`, backtick or `<(…)` inside that text is its own innermost node and
# is never exempt. So is every other program's text: `echo 'cat .env' | bash`,
# `bash -c`, `eval`, `ssh`, `perl -e 'system(…)'`, `X='cat .env'; eval "$X"`.
#
# FAIL TO THE FLOOR: no ast-grep, an ast-grep error, a non-array answer, a
# parse containing an ERROR node, or a command that could rebind what `git` /
# `gh` / `cat` mean (a function definition, `alias`, `hash`, `enable`,
# `builtin`, `trap`, `shopt`, a `PATH=`/`BASH_ENV=`/`ENV=` assignment) exempts
# nothing, and the regex verdict stands exactly as before this change. What
# stays out of scope, as for every text-matching gate here: a program that
# executes text it was handed EARLIER (a commit-msg hook planted to run the
# message) — the exemption trusts `git commit` and `gh` to send their text, not
# run it. CLAUDE_HOOKS_SECRET_PROTECTION_NO_ASTGREP=1
# forces that path (tests). Offsets are bytes (ast-grep reports byte offsets),
# so the offset arithmetic runs under LC_ALL=C.
#
# Three more conditions keep an occurrence from being exempt (review of #2737):
#
#   - the allowlisted command itself names a protected file as a FILE argument
#     (`--body-file .env`, `--template .env`, `-F`, `--file`, `-t`): it reads
#     and publishes that file, so its text exempts nothing (SP_FILEARG);
#   - the text is EXPANDED by the shell (a double-quoted argument, or an
#     unquoted-delimiter heredoc body) and expands a secret-named variable
#     (`"echo $API_TOKEN"`): the value is published (SP_SECRETVAR). Single-
#     quoted text and quoted-delimiter heredocs stay exempt;
#   - an unquoted-delimiter heredoc body holding a backtick: tree-sitter-bash
#     does not parse a backtick substitution there (`$(…)` it does).
#
# The re-check reads COMMAND with every backslash-newline continuation turned
# into two spaces (SP_VIEW, same byte length so the parser's offsets still
# line up), so a read the shell joins across lines is seen as one line.
SP_ALLOW='^(git[ \t]+commit|gh[ \t]+(issue|pr)[ \t]+(create|comment|edit|review|close|reopen|merge))\b'
SP_FILEARG='(^|\s)(--body-file|--template|--file|-F|-t)(=|\s+)?\S*(\.env|\.ssh/|\.aws/credentials|\.kube/config|\.docker/config\.json|credentials\.json|secrets\.json|\.api_tokens)'
SP_SECRETVAR='\$\{?[A-Za-z0-9_]*_(KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL|AUTH)[Ss]?\b'
# Placeholders: @CMD@ = an allowlisted command that takes no protected file
# argument; @SECRETVAR@ = SP_SECRETVAR.
# Filled by `read`, not `$(cat <<'YAML' … )`: macOS /bin/bash 3.2 scans a
# `$( … )` body for backticks even inside a quoted heredoc, so the "`" rule
# below would open a substitution that never closes and the hook would fail to
# parse (#3145, #3261). `read -d ''` returns 1 at EOF, hence `|| true`; it keeps
# the heredoc's final newline, which `$( … )` stripped, so drop it.
IFS= read -r -d '' SP_RULES <<'YAML' || true
id: n
language: bash
rule:
  any:
    - kind: string
    - kind: raw_string
    - kind: ansi_c_string
    - kind: translated_string
    - kind: heredoc_body
    - kind: comment
    - kind: command_substitution
    - kind: process_substitution
---
id: e
language: bash
rule:
  any:
    - kind: comment
    - any:
        - kind: raw_string
        - kind: ansi_c_string
        - kind: string
          not: { regex: '@SECRETVAR@' }
        - kind: translated_string
          not: { regex: '@SECRETVAR@' }
      inside:
        any:
          - @CMD@
          - kind: concatenation
            inside: @CMD@
    - kind: heredoc_body
      any:
        - inside: { kind: heredoc_redirect, has: { kind: heredoc_start, regex: "[\"'\\\\]" } }
        - not:
            any:
              - regex: "`"
              - regex: '@SECRETVAR@'
      inside:
        kind: heredoc_redirect
        inside:
          kind: redirected_statement
          any:
            - has: @CMD@
            - has: { kind: command, regex: '^cat$' }
              not: { has: { kind: file_redirect, stopBy: end } }
              inside:
                kind: command_substitution
                inside:
                  any:
                    - @CMD@
                    - kind: concatenation
                      inside: @CMD@
                    - kind: string
                      inside:
                        any:
                          - @CMD@
                          - kind: concatenation
                            inside: @CMD@
---
id: err
language: bash
rule:
  any:
    - kind: ERROR
    - kind: function_definition
    - kind: variable_assignment
      regex: '^(PATH|BASH_ENV|ENV)='
    - kind: command
      regex: '^(alias|unalias|hash|enable|builtin|trap|shopt)\b'
YAML
SP_RULES=${SP_RULES%$'\n'}
SP_CMD="{ kind: command, regex: '${SP_ALLOW}', not: { regex: '${SP_FILEARG}' } }"
SP_RULES=${SP_RULES//@CMD@/"$SP_CMD"}
SP_RULES=${SP_RULES//@SECRETVAR@/"$SP_SECRETVAR"}
SP_VIEW=""
SP_STATE=""     # "" = not built yet, "floor" = exempt nothing, "ready"
SP_N_START=()
SP_N_END=()
SP_EXEMPT=" "   # " start:end start:end … "

sp_build() {
  local astgrep="" out rows id s e
  SP_STATE="floor"
  [ "${CLAUDE_HOOKS_SECRET_PROTECTION_NO_ASTGREP:-}" = "1" ] && return 0
  # `sg` collides with shadow-utils' sg(1); adopt it only when it is ast-grep (#2451).
  if command -v ast-grep >/dev/null 2>&1; then
    astgrep="ast-grep"
  elif command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'; then
    astgrep="sg"
  fi
  [ -n "$astgrep" ] || return 0
  out=$(printf '%s' "$COMMAND" | "$astgrep" scan --inline-rules "$SP_RULES" --stdin --json=compact 2>/dev/null) || return 0
  rows=$(printf '%s' "$out" | jq -r 'if type == "array" then .[] | "\(.ruleId) \(.range.byteOffset.start) \(.range.byteOffset.end)" else error end' 2>/dev/null) || return 0
  while read -r id s e; do
    case "$id" in
      err) return 0 ;;
      n) SP_N_START+=("$s"); SP_N_END+=("$e") ;;
      e) SP_EXEMPT+="$s:$e " ;;
    esac
  done <<<"$rows"
  SP_STATE="ready"
}

# Exit 0 when byte offset $1 of COMMAND lies in exempt text (see above).
sp_offset_exempt() {
  local off=$1 k best=-1 best_s=-1 best_e=0
  [ "$SP_STATE" = "ready" ] || return 1
  for ((k = 0; k < ${#SP_N_START[@]}; k++)); do
    if [ "${SP_N_START[k]}" -le "$off" ] && [ "$off" -lt "${SP_N_END[k]}" ]; then
      if [ "${SP_N_START[k]}" -gt "$best_s" ] || { [ "${SP_N_START[k]}" -eq "$best_s" ] && [ "${SP_N_END[k]}" -lt "$best_e" ]; }; then
        best=$k
        best_s=${SP_N_START[k]}
        best_e=${SP_N_END[k]}
      fi
    fi
  done
  [ "$best" -ge 0 ] || return 1
  case "$SP_EXEMPT" in *" $best_s:$best_e "*) return 0 ;; esac
  return 1
}

# Print, one per line, the match of ERE $2 anchored at each non-exempt
# occurrence of verb alternation $1 in COMMAND. $3 = 1 when $2 begins with the
# `(^VERB|[^…]VERB)` boundary alternation, so the anchor sits one byte before
# the verb (on the boundary character) unless the verb starts a line; 2 when $2
# is a whole-line pattern anchored at the start of the verb's line.
sp_executed_matches() {
  local LC_ALL=C
  local verbs=$1 re=$2 bounded=$3 rest=$SP_VIEW base=0 pre v s line
  while [[ $rest =~ $verbs ]]; do
    pre=${rest%%"${BASH_REMATCH[0]}"*}
    v=$((base + ${#pre}))
    rest=${rest:${#pre}+1}
    base=$((v + 1))
    sp_offset_exempt "$v" && continue
    s=$v
    if [ "$bounded" = 1 ] && [ "$v" -gt 0 ] && [ "${SP_VIEW:v-1:1}" != $'\n' ]; then s=$((v - 1)); fi
    if [ "$bounded" = 2 ]; then
      # Anchor at the start of the verb's line (a whole-line pattern).
      pre=${SP_VIEW:0:v}
      pre=${pre##*$'\n'}
      s=$((v - ${#pre}))
    fi
    line=${SP_VIEW:s}
    line=${line%%$'\n'*}
    printf '%s\n' "$line" | grep -oE "^(${re})" | head -1 || true
  done
}

# A regex has decided to block. Exit 0 to keep the block (parser floor, or an
# executed occurrence); exit 1 when every occurrence is exempt text.
# $1 = verb alternation, $2 = the same regex, $3 = bounded flag (above).
sp_confirm() {
  [ -n "$SP_STATE" ] || sp_build
  [ "$SP_STATE" = "ready" ] || return 0
  [ -n "$(sp_executed_matches "$1" "$2" "$3")" ]
}

# Sensitive file patterns (applied to Read, Edit, Write file_path and Bash arguments)
check_sensitive_path() {
  local target="$1"
  [ -z "$target" ] && return 0

  # .env files (but allow .env.example, .env.sample, .env.template)
  if grep -Eq '(^|/)\.env($|\.[^(example|sample|template)])' <<<"$target" && \
     ! grep -Eq '\.(example|sample|template)$' <<<"$target"; then
    block "BLOCKED: Access to .env file '$target' denied. These files contain secrets.
Use .env.example for templates. ${OVERRIDE_NOTE}"
  fi

  # SSH private keys
  if grep -Eq '(^|/)(\.ssh/(id_|config|known_hosts|authorized_keys)|.*\.pem$|.*_rsa$|.*_ed25519$|.*_ecdsa$)' <<<"$target"; then
    block "BLOCKED: Access to SSH key/config '$target' denied. These are sensitive credentials.
${OVERRIDE_NOTE}"
  fi

  # Cloud credential files
  if grep -Eq '(^|/)(\.aws/credentials|\.config/gcloud/|\.kube/config|\.docker/config\.json)' <<<"$target"; then
    block "BLOCKED: Access to cloud credentials '$target' denied.
${OVERRIDE_NOTE}"
  fi

  # Generic credential/secret files
  if grep -Eq '(^|/)(credentials\.json|secrets\.json|\.api_tokens|service[_-]account.*\.json|.*\.keystore|.*\.jks|.*\.p12|.*\.pfx)$' <<<"$target"; then
    block "BLOCKED: Access to credential file '$target' denied.
${OVERRIDE_NOTE}"
  fi

  # Private key files
  if grep -Eq '\.(key|privkey)$' <<<"$target"; then
    block "BLOCKED: Access to private key file '$target' denied.
${OVERRIDE_NOTE}"
  fi

  return 0
}

# Check file_path for Read, Edit, Write tools
if [ "$TOOL_NAME" = "Read" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
  check_sensitive_path "$FILE_PATH"
fi

# Check Bash commands for sensitive file access and credential exposure
if [ "$TOOL_NAME" = "Bash" ] && [ -n "$COMMAND" ]; then
  # Every check below reads SP_VIEW: COMMAND with each backslash-newline
  # continuation joined (two spaces, so byte offsets match the parse of
  # COMMAND). The shell joins `cat \<newline>.env` into one read; a line-based
  # regex over the raw text saw neither half (review of #2737). Joining can
  # only add matches, never remove one.
  sp_bsnl=$'\\\n'
  SP_VIEW=${COMMAND//"$sp_bsnl"/  }
  # Block printing environment variables that likely contain secrets.
  # Match an actual variable *reference* whose name ends in a secret-ish suffix:
  # `$VAR_KEY`, `${VAR_TOKEN}`, etc. The name is a contiguous identifier
  # ([A-Za-z0-9_]*) — NOT `.*` — so the match cannot bridge a `$(date …)` command
  # substitution to a distant unrelated `_KEY` elsewhere on the line. That `.*`
  # greediness false-blocked routine config echoes like
  # `echo "$(date) KC_HOSTNAME=$kch FE_KEYCLOAK_URL=$feu"`, where `FE_KEYCLOAK`
  # contains `_KEY` but is an assignment LHS, not a secret variable reference
  # (issue #1580). Public config names ($..._HOST, $..._URL, $..._ENDPOINT) are
  # no longer caught; genuine $..._KEY/_SECRET/_TOKEN/_PASSWORD references are.
  #
  # Each regex below decides first; sp_confirm can only lift a block whose every
  # verb occurrence is exempt text (#2737, see the parsed-exemption header).
  #
  # The verb must be a whole command word (issue #3271): bounded on the left by
  # line start or a byte that is not part of a word or filename (so `.env`,
  # `dotenv`, `myenv`, `my-env` are not the `env` verb, while `/usr/bin/env`
  # and `(echo` still are) and on the right by whitespace. Bracket expressions
  # only — portable ERE for both `grep -E` and bash `=~` (bash 3.2, BSD grep).
  secret_var_verbs='(echo|printf|cat|env|printenv|export)'
  # shellcheck disable=SC2016  # $... is a grep pattern, not shell expansion
  secret_var_re="(^${secret_var_verbs}|[^A-Za-z0-9_.-]${secret_var_verbs})"'[[:space:]][^|]*\$\{?[A-Za-z0-9_]*_(KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL|AUTH)[Ss]?\b'
  if grep -Eq "$secret_var_re" <<<"$SP_VIEW" && sp_confirm "$secret_var_verbs" "$secret_var_re" 1; then
    block "BLOCKED: Command may expose secret environment variables.
Use the application's configuration system instead of echoing secrets.
${OVERRIDE_NOTE}"
  fi

  # Block printenv/env for full environment dump
  if grep -Eq '^\s*(printenv|env)\s*$' <<<"$SP_VIEW" &&
    sp_confirm '(printenv|env)' '\s*(printenv|env)\s*$' 2; then
    block "BLOCKED: Dumping the full environment may expose secrets.
Use 'printenv VAR_NAME' for specific non-sensitive variables instead.
${OVERRIDE_NOTE}"
  fi

  # Check for cat/read/access of sensitive files in bash commands.
  #
  # The gap between the reader verb and the file pattern is `[^|;&]*` — NOT
  # `[^|]*` — so a match cannot bridge a command separator (`;`, `&&`, `||`) or
  # a pipe. The wider form let a verb in one statement bind to an unrelated
  # `.env` mention in a *later* statement, false-blocking commands that read no
  # secret at all, e.g. `... | head -1); grep -nE '\.env|PATTERN' "$f"`, where
  # the only `.env` is inside a grep pattern (issue #2444). Same greediness
  # class as the `.*` → `[A-Za-z0-9_]*` narrowing documented above (#1580).
  #
  # The verb group is anchored at a word start — `(^VERB|[^A-Za-z]VERB)` — so
  # a verb cannot match inside an ordinary English word. Without it
  # `regardless`, `unless`, `thread`, `encode` and `furthermore` each supplied a
  # verb, and prose that went on to mention `.env.integration` — a
  # commit-message heredoc describing config precedence — was blocked as a
  # sensitive-file read (issue #2597).
  #
  # The hook may run under BSD grep 2.6.0 (macOS), GNU grep (CI) or ugrep, and
  # they disagree on the shorter anchor forms. `(^|[^A-Za-z])VERB` is a compile
  # error in ugrep 6.0.0 ("empty expression") that the trailing `|| true`
  # swallows, leaving `$match` empty and every reader-verb block failing open.
  # `\b`/`\<` compile everywhere, but ugrep's `-o` (6.0.0 and 7.8.4) then
  # returns `cat .env` for `cat .env.example`, so the template exemption below
  # never sees the suffix and a template read is blocked. The explicit
  # alternation behaves the same on all three. Its second branch captures one
  # boundary character, trimmed from `$match` before the block message; the
  # exemption re-greps from `${pattern}` and never sees it.
  #
  # The anchor also stops binaries whose name merely ends in a verb from
  # matching by accident. The common ones (`nvim`, `gcat`, `zless`, …) are
  # listed explicitly so those reads stay blocked; anything else whose name
  # merely ends in a verb (`multitail`, `lolcat`) is not matched any more.
  reader_verbs='(cat|gcat|zcat|bzcat|xzcat|head|ghead|tail|gtail|less|zless|more|nano|vim|nvim|gvim|mvim|vi|code|read)'
  #
  # Filter verbs (issue #2900): sed/awk/grep/cut/perl/rg print a file's
  # contents as readily as cat — `sed -n 's/^export KEY=//p' ~/.api_tokens`
  # exfiltrated a key with nothing blocking it. Unlike the verbs above, these
  # take a *pattern or script* argument that routinely mentions a protected
  # name (`grep -rn ".env" src/`, `sed 's/.env/.env.local/' f`), so they match
  # only when the protected name starts a standalone file argument: preceded by
  # whitespace or `<`, optionally behind a path prefix (`~/`, `$HOME/`,
  # `src/`). A quoted argument counts only with a path-shaped prefix that
  # starts at `~`, `$`, `/` or `.` and ends in `/` (`"$HOME/.api_tokens"`):
  # a bare quoted `".env"` is a search pattern far more often than a path, and
  # `'s/.env/…/'` is a sed script. The verb's leading boundary also excludes
  # `-` and `_`, so `--grep` / `my_sed` do not supply the verb.
  filter_verbs='(sed|gsed|awk|gawk|mawk|nawk|grep|egrep|fgrep|zgrep|rg|cut|perl)'
  path_prefix="([\"'][~\$/.][^[:space:]|;&'\"<>]*/|[^[:space:]|;&'\"<>]*/)?"

  # Exit 0 when one reader/filter match ($2, for pattern $1) is a real secret
  # read; exit 1 when it is a template. The template rule:
  #
  # .env.example / .env.sample / .env.template are templates committed by
  # convention, not secrets. check_sensitive_path() already exempts them on
  # the Read/Edit/Write path; without the same exemption here, `cat
  # .env.example` was blocked while `Read`ing the identical file was allowed
  # (issue #2444). Scoped to the .env pattern to mirror check_sensitive_path()
  # exactly — the other patterns keep no exemption.
  #
  # The exemption requires *every* .env token in the matched region to be a
  # template. Inspecting only the last one would let a real secret hide behind
  # a template in the same statement (`cat .env .env.example`).
  #
  # A token also stops at a backtick, comma or `)`, and loses trailing periods,
  # so prose that wraps or punctuates the filename (`` `.env.example` ``,
  # `.env.example,`, `.env.example.`) still reads as the template (issue
  # #3297). The class lives in a single-quoted variable to keep the backtick
  # out of the `$(...)` below (bash 3.2 parses a backtick there unreliably).
  sp_env_tok_class='[^[:space:]|;&'"'"'"`,)]*'
  match_is_secret() {
    local env_tokens non_template
    if [ "$1" = '\.env\b' ]; then
      env_tokens=$(echo "$2" | grep -oE "${1}${sp_env_tok_class}" | sed 's/\.*$//' || true)
      non_template=$(echo "$env_tokens" | grep -vE '\.(example|sample|template)$' || true)
      [ -n "$env_tokens" ] && [ -z "$non_template" ] && return 1
    fi
    return 0
  }

  for pattern in '\.env\b' '\.ssh/' '\.aws/credentials' '\.kube/config' '\.docker/config\.json' 'credentials\.json' 'secrets\.json' '\.api_tokens\b'; do
    reader_re="(^${reader_verbs}|[^A-Za-z]${reader_verbs})[[:space:]]+[^|;&]*${pattern}[^[:space:]|;&'\"]*"
    filter_re="(^${filter_verbs}|[^A-Za-z0-9_-]${filter_verbs})[[:space:]]+([^|;&]*[[:space:]<])?${path_prefix}${pattern}[^[:space:]|;&'\"]*"
    # Capture the matched substrings (verb + path) rather than a bare boolean,
    # so the block message can name what tripped it and the exemption below can
    # inspect the actual path argument. Inspect every match across the command
    # rather than just the first: taking only `head -1` let a real secret read
    # slip past if preceded by an exempted template in a chained command, e.g.
    # `cat .env.example; cat .env` (issue #2611).
    matches=$(
      {
        echo "$SP_VIEW" | grep -oE "$reader_re" || true
        echo "$SP_VIEW" | grep -oE "$filter_re" || true
      }
    )
    [ -z "$matches" ] && continue

    while IFS= read -r match; do
      [ -z "$match" ] && continue
      # Drop the single boundary character the second alternative captured (a
      # space, `;`, `(`, quote, …); a start-of-line match begins with the verb
      # and is left alone.
      match="${match#[!A-Za-z]}"
      match_is_secret "$pattern" "$match" || continue

      # The regex says block. Lift it only when every verb occurrence of this
      # pattern's matches is exempt text (#2737); otherwise name an executed
      # secret read in the message.
      [ -n "$SP_STATE" ] || sp_build
      if [ "$SP_STATE" = "ready" ]; then
        executed=""
        while IFS= read -r m; do
          [ -n "$m" ] || continue
          m="${m#[!A-Za-z]}"
          if match_is_secret "$pattern" "$m"; then
            executed=$m
            break
          fi
        done <<<"$(
          sp_executed_matches "$reader_verbs" "$reader_re" 1
          sp_executed_matches "$filter_verbs" "$filter_re" 1
        )"
        [ -n "$executed" ] || break
        match=$executed
      fi

      block "BLOCKED: Command accesses a sensitive file matching '${pattern}' (matched: '${match}').
${OVERRIDE_NOTE}"
    done <<< "$matches"
  done
fi

exit 0

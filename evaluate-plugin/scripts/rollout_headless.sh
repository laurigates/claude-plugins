#!/usr/bin/env bash
# Run ONE eval rollout through a real headless `claude -p` child, so plugin
# loading, description routing, allowed-tools and hooks are exercised the way a
# user's session exercises them (the in-session Task-subagent harness pastes the
# SKILL.md in and tests none of that).
#
# The script never performs the task itself: it launches the child, records its
# stream-json transcript, parses it into a harness-neutral trace.json (via
# parse_trace.py), snapshots the workdir, and prints one KEY=VALUE block.
#
# Usage:
#   rollout_headless.sh --run-dir <dir> --workdir <dir> (--prompt <text> | --prompt-file <f>)
#     [--plugin-dir <dir>]...          omit for the baseline config
#     [--model haiku] [--effort <low|medium|high|xhigh|max>]
#     [--max-budget-usd <usd>]         required unless EVAL_ALLOW_UNCAPPED=1 (0.25 is a sane cap)
#     [--max-turns <n>]                probed: WARN and retried without it if the CLI rejects it
#     [--allowed-tools <list>] [--permission bypass|default] [--timeout 300]
#     [--env-mode clean|inherit] [--passthrough-env NAME[,NAME...]]...
#     [--stop-on-skill] [--no-snapshot] [--snapshot-max-mb 50]
#
# Env modes:
#   clean (default)  `env -i` + an allowlist (PATH, locale, proxy/CA, auth tokens),
#                    a throwaway fake HOME (no user settings, hooks or MCP; only
#                    ~/.claude/.credentials.json is copied in when no token is
#                    exported), plus CLOUD_PASSTHROUGH when CLAUDE_CODE_REMOTE is
#                    set, plus --passthrough-env names. A clean child that cannot
#                    authenticate is an ERROR (auth_failed) naming the fix; it is
#                    NEVER silently retried in inherit mode, which would hand the
#                    parent's credentials to a --dangerously-skip-permissions child.
#   inherit          explicit opt-in only: the parent env minus every CLAUDE*
#                    session variable (and the session-ingress / trace-context
#                    vars) and minus a third-party credential denylist (GH_TOKEN,
#                    AWS_*, CLOUDSDK_*, ...; each one stripped is named in a WARN);
#                    the real HOME stays, so ~/.ssh, ~/.aws and user-level hooks are
#                    reachable -- a WARN says so.
#
# Permissions: bypass (default) runs --dangerously-skip-permissions in the
# throwaway workdir (IS_SANDBOX=1 when euid is 0); default runs
# --permission-mode default, which with --allowed-tools Skill is trigger mode.
#
# Guards (exit 2): workdir inside this script's repo, inside the CALLER's repo
# (the git toplevel of $PWD -- an installed ${CLAUDE_PLUGIN_ROOT} copy is not
# the user's checkout), or inside any git repo rooted above it; a `skills` path
# component; run-dir missing, run-dir inside the workdir, claude/jq/python3
# missing, bad args.
#
# The prompt reaches the child on stdin, never in argv: `claude -p "$prompt"`
# parses a prompt starting with '-' (YAML front matter, `--version`) as options.
#
# Writes into RUN_DIR: transcript.jsonl, stderr.log, trace.json, transcript.md
# (final text + "\n\n---\n## Tool calls" appendix), timing.json, workspace/,
# rollout-meta.json (prompt as sha256 and passthrough var NAMES only).
#
# Output: one `=== HEADLESS ROLLOUT ===` block (see the end of this file).
# Exit: 0 OK/WARN, 1 ERROR, 2 usage/guard error.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
parse_trace="${EVAL_PARSE_TRACE:-$script_dir/parse_trace.py}"

# Cloud passthrough. Measured 2026-10-05 (claude 2.1.289, nested in a Claude
# Code cloud session, CLAUDE_CODE_REMOTE set): a child under `env -i` with only
# PATH + a fake HOME authenticated and completed -- the egress gateway supplies
# auth transparently, so neither ANTHROPIC_BASE_URL, the proxy vars, nor
# CLAUDE_SESSION_INGRESS_TOKEN_FILE is needed. The list is therefore empty; it
# stays as the single place to add a var if a future cloud image needs one.
# Applied only when CLAUDE_CODE_REMOTE is set in the parent.
CLOUD_PASSTHROUGH=()

# Allowlist for clean mode: harmless plumbing + auth tokens that a local user
# may export (the fake HOME has no login). Session identity never passes.
CLEAN_ALLOWLIST=(
  PATH TERM LANG LANGUAGE LC_ALL LC_CTYPE LC_MESSAGES TZ TMPDIR USER LOGNAME SHELL
  CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
  HTTPS_PROXY HTTP_PROXY NO_PROXY https_proxy http_proxy no_proxy
  NODE_EXTRA_CA_CERTS SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE GIT_SSL_CAINFO
)

usage() { sed -n '2,45p' "$0"; }

# ---------------------------------------------------------------- output helpers
issues=()      # "SEVERITY|TYPE|MSG"
add_issue() { issues+=("$1|$2|$3"); }

one_line() {   # collapse whitespace, cap length
  printf '%s' "$1" | tr '\n\r\t' '   ' | tr -s ' ' | cut -c1-"${2:-180}"
}

usage_error() {
  echo "ERROR: $1" >&2
  echo "=== HEADLESS ROLLOUT ==="
  echo "STATUS=ERROR"
  echo "REASON=$(one_line "usage: $1")"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=usage MSG=$(one_line "$1")"
  echo "=== END HEADLESS ROLLOUT ==="
  exit 2
}

# ---------------------------------------------------------------- args
run_dir=""; workdir=""; prompt=""; prompt_file=""; prompt_set=false
plugin_dirs=(); model="haiku"; effort=""; budget=""; max_turns=""
allowed_tools=""; permission="bypass"; timeout_s=300
env_mode="clean"; passthrough_raw=()
stop_on_skill=false; do_snapshot=true; snapshot_max_mb=50

need_val() { [ $# -ge 2 ] || usage_error "$1 requires a value"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --run-dir) need_val "$@"; run_dir="$2"; shift 2 ;;
    --workdir) need_val "$@"; workdir="$2"; shift 2 ;;
    --prompt) need_val "$@"; prompt="$2"; prompt_set=true; shift 2 ;;
    --prompt-file) need_val "$@"; prompt_file="$2"; shift 2 ;;
    --plugin-dir) need_val "$@"; plugin_dirs+=("$2"); shift 2 ;;
    --model) need_val "$@"; model="$2"; shift 2 ;;
    --effort) need_val "$@"; effort="$2"; shift 2 ;;
    --max-budget-usd) need_val "$@"; budget="$2"; shift 2 ;;
    --max-turns) need_val "$@"; max_turns="$2"; shift 2 ;;
    --allowed-tools) need_val "$@"; allowed_tools="$2"; shift 2 ;;
    --permission) need_val "$@"; permission="$2"; shift 2 ;;
    --timeout) need_val "$@"; timeout_s="$2"; shift 2 ;;
    --env-mode) need_val "$@"; env_mode="$2"; shift 2 ;;
    --passthrough-env) need_val "$@"; passthrough_raw+=("$2"); shift 2 ;;
    --stop-on-skill) stop_on_skill=true; shift ;;
    --no-snapshot) do_snapshot=false; shift ;;
    --snapshot-max-mb) need_val "$@"; snapshot_max_mb="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage_error "unknown argument: $1" ;;
  esac
done

[ -n "$run_dir" ] || usage_error "--run-dir is required"
[ -n "$workdir" ] || usage_error "--workdir is required"
if [ "$prompt_set" = true ] && [ -n "$prompt_file" ]; then
  usage_error "pass --prompt or --prompt-file, not both"
fi
if [ -n "$prompt_file" ]; then
  [ -f "$prompt_file" ] || usage_error "prompt file not found: $prompt_file"
  prompt="$(cat "$prompt_file")"
elif [ "$prompt_set" != true ]; then
  usage_error "--prompt or --prompt-file is required"
fi
[ -n "$prompt" ] || usage_error "the prompt is empty"

case "$permission" in bypass|default) ;; *) usage_error "--permission must be bypass or default" ;; esac
case "$env_mode" in clean|inherit) ;; *) usage_error "--env-mode must be clean or inherit" ;; esac
[[ "$timeout_s" =~ ^[1-9][0-9]*$ ]] || usage_error "--timeout must be a positive integer (seconds)"
[[ "$snapshot_max_mb" =~ ^[1-9][0-9]*$ ]] || usage_error "--snapshot-max-mb must be a positive integer"
if [ -n "$max_turns" ] && ! [[ "$max_turns" =~ ^[1-9][0-9]*$ ]]; then
  usage_error "--max-turns must be a positive integer"
fi
if [ -n "$effort" ]; then
  case "$effort" in low|medium|high|xhigh|max) ;; *) usage_error "--effort must be low|medium|high|xhigh|max" ;; esac
fi
uncapped=false
if [ -z "$budget" ]; then
  if [ "${EVAL_ALLOW_UNCAPPED:-}" = "1" ]; then
    uncapped=true
  else
    usage_error "--max-budget-usd is required (e.g. 0.25); set EVAL_ALLOW_UNCAPPED=1 to run uncapped"
  fi
elif ! [[ "$budget" =~ ^[0-9]+(\.[0-9]+)?$ ]] || ! awk -v b="$budget" 'BEGIN { exit !(b > 0) }'; then
  usage_error "--max-budget-usd must be a positive number"
fi

# Passthrough names: split on commas, validate, refuse session-identity vars.
passthrough=()
denied_passthrough=()
is_session_var() {
  case "$1" in
    CLAUDECODE|CLAUDE_CODE_SESSION_ID|CLAUDE_CODE_REMOTE*|CLAUDE_CODE_CHILD_SESSION|CLAUDE_CODE_ENTRYPOINT|\
    CLAUDE_CODE_MESSAGING_*|CLAUDE_PID|CLAUDE_CODE_SSE_PORT|SESSION_INGRESS_URL|CLAUDE_SESSION_INGRESS_TOKEN_FILE|TRACEPARENT) return 0 ;;
  esac
  return 1
}
for raw in "${passthrough_raw[@]+"${passthrough_raw[@]}"}"; do
  IFS=',' read -r -a parts <<<"$raw"
  for v in "${parts[@]+"${parts[@]}"}"; do
    v="${v// /}"
    [ -n "$v" ] || continue
    [[ "$v" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || usage_error "invalid --passthrough-env name: $v"
    if is_session_var "$v"; then denied_passthrough+=("$v"); else passthrough+=("$v"); fi
  done
done

# ---------------------------------------------------------------- guards
[ -d "$run_dir" ] || usage_error "run dir not found: $run_dir (create it with prepare_run.sh)"
[ -d "$workdir" ] || usage_error "workdir not found: $workdir"
run_dir="$(cd "$run_dir" && pwd -P)"
workdir="$(cd "$workdir" && pwd -P)"

# Refuse a workdir inside a repo the child would treat as its project (it would
# load that repo's CLAUDE.md, rules and hooks, and a "commit it" prompt would
# commit there). Three roots: the repo this script lives in; the CALLER's repo
# -- in normal use the script runs from an installed ${CLAUDE_PLUGIN_ROOT}
# outside the user's checkout, so the script's own tree alone protects nothing;
# and any repo whose toplevel is strictly above the workdir. A workdir that IS
# a repo toplevel (a fixture that ran `git init` in its mktemp dir) is fine.
toplevel_of() { git -C "$1" rev-parse --show-toplevel 2>/dev/null | head -1; }
guard_roots=()
script_repo="$(toplevel_of "$script_dir")"
[ -n "$script_repo" ] || script_repo="$(cd "$script_dir/../.." && pwd -P)"
guard_roots+=("$script_repo")
caller_repo="$(toplevel_of "$PWD")"
[ -n "$caller_repo" ] && guard_roots+=("$caller_repo")
for root in "${guard_roots[@]}"; do
  root="$(cd "$root" 2>/dev/null && pwd -P)" || continue
  case "$workdir/" in
    "$root"/*) usage_error "workdir is inside the repo ($root): the child would load its CLAUDE.md, rules and hooks; use a mktemp dir" ;;
  esac
done
enclosing="$(toplevel_of "$workdir")"
if [ -n "$enclosing" ]; then
  enclosing="$(cd "$enclosing" && pwd -P)"
  [ "$enclosing" = "$workdir" ] || \
    usage_error "workdir is inside the repo ($enclosing): the child would load its CLAUDE.md, rules and hooks; use a mktemp dir"
fi
case "$workdir/" in
  */skills/*) usage_error "workdir has a skills path component: $workdir (path-scoped **/skills/** rules would load, #2667)" ;;
esac
case "$run_dir/" in
  "$workdir"/*) usage_error "run dir is inside the workdir; the snapshot would copy itself" ;;
esac
for pd in "${plugin_dirs[@]+"${plugin_dirs[@]}"}"; do
  [ -d "$pd" ] || usage_error "plugin dir not found: $pd"
done

claude_bin="$(command -v claude || true)"
[ -n "$claude_bin" ] || usage_error "claude CLI not found on PATH"
command -v jq >/dev/null 2>&1 || usage_error "jq not found on PATH"
command -v python3 >/dev/null 2>&1 || usage_error "python3 not found on PATH"
timeout_bin="$(command -v timeout || command -v gtimeout || true)"

# Absolute plugin dirs (the child runs from the workdir).
abs_plugin_dirs=()
for pd in "${plugin_dirs[@]+"${plugin_dirs[@]}"}"; do
  abs_plugin_dirs+=("$(cd "$pd" && pwd -P)")
done

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1; fi
}

# ---------------------------------------------------------------- scratch + fake HOME
scratch="$(mktemp -d)" || usage_error "mktemp -d failed"
if ! { [ -n "$scratch" ] && [ -d "$scratch" ]; }; then usage_error "mktemp -d returned no directory"; fi
child_pid=""
# shellcheck disable=SC2329,SC2317  # invoked via trap (SC2317 is the pre-0.10 code)
cleanup() {
  [ -n "$child_pid" ] && kill -TERM "$child_pid" 2>/dev/null
  rm -rf "$scratch"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

fake_home="$scratch/home"
mkdir -p "$fake_home/.claude"
jq -n '{hasCompletedOnboarding: true}' >"$fake_home/.claude.json"
# A git identity so a rollout that commits does not fail on "who are you".
printf '[user]\n\tname = Eval Runner\n\temail = eval-runner@example.invalid\n[commit]\n\tgpgsign = false\n[init]\n\tdefaultBranch = main\n' \
  >"$fake_home/.gitconfig"

# Local convenience (mirrors ctx-probe.sh): the fake HOME has no login, so pick
# up a token from ~/.api_tokens when none is exported. Parsed, never sourced.
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -f "${HOME:-/nonexistent}/.api_tokens" ]; then
  while IFS= read -r tok_line; do
    tok_line="${tok_line#export }"
    tok_name="${tok_line%%=*}"; tok_val="${tok_line#*=}"
    tok_val="${tok_val%\"}"; tok_val="${tok_val#\"}"; tok_val="${tok_val%\'}"; tok_val="${tok_val#\'}"
    case "$tok_name" in
      CLAUDE_CODE_OAUTH_TOKEN) export CLAUDE_CODE_OAUTH_TOKEN="$tok_val" ;;
      ANTHROPIC_API_KEY) export ANTHROPIC_API_KEY="$tok_val" ;;
    esac
  done < <(grep -E '^(export )?(CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY)=' "$HOME/.api_tokens" 2>/dev/null)
fi

# The fake HOME has no login. A user logged in via /login keeps the OAuth
# credential in ~/.claude/.credentials.json (Linux; macOS uses the keychain):
# copy ONLY that file in, so clean mode authenticates without the real HOME.
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ] \
   && [ -f "${HOME:-/nonexistent}/.claude/.credentials.json" ]; then
  (umask 077 && cp "$HOME/.claude/.credentials.json" "$fake_home/.claude/.credentials.json") 2>/dev/null || true
fi

# Third-party credentials stripped even in explicit inherit mode: the child runs
# with --dangerously-skip-permissions by default, so anything here is reachable
# by the agent under test. Each one present is named in a WARN.
CREDENTIAL_DENYLIST_RE='^(GH_TOKEN|GITHUB_TOKEN|GH_ENTERPRISE_TOKEN|GITHUB_ENTERPRISE_TOKEN|GITLAB_TOKEN|NPM_TOKEN|PYPI_TOKEN|HF_TOKEN|AWS_.*|AZURE_.*|ARM_.*|CLOUDSDK_.*|GOOGLE_.*|GCLOUD_.*|GIT_CONFIG_.*|GIT_ASKPASS|SSH_ASKPASS|SSH_AUTH_SOCK|CCR_.*|SBX_.*|DOCKER_AUTH_CONFIG|KUBECONFIG|VAULT_TOKEN|OPENAI_API_KEY)$'
stripped_creds=()

# ---------------------------------------------------------------- child env
child_env=()        # NAME=VALUE for env -i (clean) or env (inherit)
child_unset=()      # names to unset (inherit)
passed_names=()     # names actually passed beyond the base allowlist (for meta)
build_env() {
  local mode="$1" v
  child_env=(); child_unset=(); passed_names=()
  if [ "$mode" = clean ]; then
    for v in "${CLEAN_ALLOWLIST[@]}"; do
      [ -n "${!v+x}" ] && child_env+=("$v=${!v}")
    done
    if [ -n "${CLAUDE_CODE_REMOTE:-}" ]; then
      for v in "${CLOUD_PASSTHROUGH[@]+"${CLOUD_PASSTHROUGH[@]}"}"; do
        if [ -n "${!v+x}" ]; then child_env+=("$v=${!v}"); passed_names+=("$v"); fi
      done
    fi
    child_env+=("HOME=$fake_home")
  else
    stripped_creds=()
    while IFS= read -r v; do
      case "$v" in
        CLAUDE_CODE_OAUTH_TOKEN) ;;
        CLAUDE*|SESSION_INGRESS_URL|TRACEPARENT) child_unset+=("$v") ;;
        *) if [[ "$v" =~ $CREDENTIAL_DENYLIST_RE ]]; then
             child_unset+=("$v"); stripped_creds+=("$v")
           fi ;;
      esac
    done < <(compgen -e)
  fi
  for v in "${passthrough[@]+"${passthrough[@]}"}"; do
    if [ -n "${!v+x}" ]; then child_env+=("$v=${!v}"); passed_names+=("$v"); fi
  done
  if [ "$permission" = bypass ] && [ "$(id -u)" = "0" ]; then
    child_env+=("IS_SANDBOX=1")
  fi
}

# ---------------------------------------------------------------- child argv
use_max_turns=true; use_effort=true
build_args() {
  # -p with no positional prompt: the prompt is read from stdin (run_child).
  claude_args=(-p --output-format stream-json --verbose
    --model "$model" --no-session-persistence --setting-sources "project,local")
  local pd
  for pd in "${abs_plugin_dirs[@]+"${abs_plugin_dirs[@]}"}"; do claude_args+=(--plugin-dir "$pd"); done
  [ "$uncapped" = true ] || claude_args+=(--max-budget-usd "$budget")
  if [ -n "$max_turns" ] && [ "$use_max_turns" = true ]; then claude_args+=(--max-turns "$max_turns"); fi
  if [ -n "$effort" ] && [ "$use_effort" = true ]; then claude_args+=(--effort "$effort"); fi
  [ -n "$allowed_tools" ] && claude_args+=(--allowedTools "$allowed_tools")
  if [ "$permission" = bypass ]; then
    claude_args+=(--dangerously-skip-permissions)
  else
    claude_args+=(--permission-mode default)
  fi
}

transcript="$run_dir/transcript.jsonl"
stderr_log="$run_dir/stderr.log"

# A Skill tool_use on an assistant line. Cheap substring pre-filter, jq confirms.
is_skill_line() {
  case "$1" in
    *'"type":"assistant"'*'"Skill"'*|*'"type": "assistant"'*'"Skill"'*) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$1" | jq -e 'select(.type == "assistant")
    | [.message.content[]? | select(.type == "tool_use" and .name == "Skill")] | length > 0' >/dev/null 2>&1
}

prompt_path="$scratch/prompt.txt"
printf '%s' "$prompt" >"$prompt_path"

child_exit=0; stopped=false; timed_out=false
run_child() {
  local mode="$1" fifo="$scratch/stream.fifo" line
  build_env "$mode"
  build_args
  : >"$transcript"; : >"$stderr_log"
  rm -f "$fifo"; mkfifo "$fifo" || return 1
  stopped=false; timed_out=false
  local tcmd=()
  [ -n "$timeout_bin" ] && tcmd=("$timeout_bin" --kill-after=10 "$timeout_s")
  if [ "$mode" = clean ]; then
    ( cd "$workdir" && exec env -i "${child_env[@]}" "${tcmd[@]+"${tcmd[@]}"}" "$claude_bin" "${claude_args[@]}" ) \
      >"$fifo" 2>"$stderr_log" <"$prompt_path" &
  else
    local unset_args=() u
    for u in "${child_unset[@]+"${child_unset[@]}"}"; do unset_args+=(-u "$u"); done
    ( cd "$workdir" && exec env "${unset_args[@]+"${unset_args[@]}"}" "${child_env[@]+"${child_env[@]}"}" \
        "${tcmd[@]+"${tcmd[@]}"}" "$claude_bin" "${claude_args[@]}" ) \
      >"$fifo" 2>"$stderr_log" <"$prompt_path" &
  fi
  child_pid=$!
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "$line" >>"$transcript"
    if [ "$stop_on_skill" = true ] && [ "$stopped" = false ] && is_skill_line "$line"; then
      stopped=true
      kill -TERM "$child_pid" 2>/dev/null
    fi
  done <"$fifo"
  wait "$child_pid"; child_exit=$?
  child_pid=""
  rm -f "$fifo"
  if [ "$stopped" = false ] && { [ "$child_exit" -eq 124 ] || [ "$child_exit" -eq 137 ]; } && [ -n "$timeout_bin" ]; then
    timed_out=true
  fi
  return 0
}

rejected_flag() {  # the CLI refused a flag before doing anything
  [ ! -s "$transcript" ] && grep -qiE "unknown option ['\"]?$1|unrecognized option ['\"]?$1|error: .*$1" "$stderr_log" 2>/dev/null
}

auth_failed() {
  grep -qiE 'not logged in|please run /login|invalid api key|authentication_error|oauth token (has )?expired' \
    "$stderr_log" 2>/dev/null && return 0
  jq -e -s '[.[] | select(.type == "result" and .is_error == true)
             | (.result // "" | tostring) | test("(?i)not logged in|/login|invalid api key|authentication")] | any' \
    "$transcript" >/dev/null 2>&1
}

[ -n "$timeout_bin" ] || add_issue WARN no_timeout_binary "neither timeout nor gtimeout found; --timeout is not enforced"
[ "$uncapped" = true ] && add_issue WARN uncapped "no --max-budget-usd cap (EVAL_ALLOW_UNCAPPED=1)"
for v in "${denied_passthrough[@]+"${denied_passthrough[@]}"}"; do
  add_issue WARN passthrough_denied "refused to pass session variable $v to the child"
done

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
start_s="$(date +%s)"
effective_env_mode="$env_mode"
run_child "$effective_env_mode"

# Probed flags: retry once without a flag the CLI rejects.
if [ -n "$max_turns" ] && rejected_flag --max-turns; then
  use_max_turns=false
  add_issue WARN max_turns_rejected "the claude CLI rejected --max-turns; ran without it (budget/timeout/--stop-on-skill still cap the run)"
  run_child "$effective_env_mode"
fi
if [ -n "$effort" ] && rejected_flag --effort; then
  use_effort=false
  add_issue WARN effort_rejected "the claude CLI rejected --effort; ran without it"
  run_child "$effective_env_mode"
fi
# No automatic inherit fallback: retrying a bypass-permission child with the
# parent's env and real HOME would hand it every credential the user holds.
if auth_failed; then
  if [ "$effective_env_mode" = clean ]; then
    add_issue ERROR auth_failed "the clean-env child could not authenticate: export CLAUDE_CODE_OAUTH_TOKEN (claude setup-token) or ANTHROPIC_API_KEY, or put one in ~/.api_tokens; --env-mode inherit is an explicit opt-in"
  else
    add_issue ERROR auth_failed "the child could not authenticate in inherit mode"
  fi
fi
if [ "$effective_env_mode" = inherit ]; then
  add_issue WARN inherit_env "inherit mode: the child keeps the real HOME (~/.ssh, ~/.aws, ~/.config/gh, user hooks) and the parent env minus session vars; stripped ${#stripped_creds[@]} credential var(s) (names in rollout-meta.json inherit_stripped_env): $(one_line "${stripped_creds[*]}" 120)"
fi
end_s="$(date +%s)"
ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
duration_ms=$(( (end_s - start_s) * 1000 ))

# ---------------------------------------------------------------- parse
trace="$run_dir/trace.json"
rm -f "$trace"
parse_ok=false
if [ ! -s "$transcript" ]; then
  add_issue ERROR empty_transcript "the child produced no stream-json output (exit $child_exit): $(one_line "$(head -c 300 "$stderr_log")" 120)"
elif [ ! -f "$parse_trace" ]; then
  add_issue ERROR parse_trace_missing "parser not found: $parse_trace"
else
  python3 "$parse_trace" --input "$transcript" --harness claude-code --output "$trace" --workdir "$workdir" \
    >"$scratch/parse.out" 2>"$scratch/parse.err"
  parse_exit=$?
  if [ "$parse_exit" -eq 0 ] && jq -e 'type == "object"' "$trace" >/dev/null 2>&1; then
    parse_ok=true
  else
    add_issue ERROR parse_failed "parse_trace.py exit $parse_exit: $(one_line "$(head -c 300 "$scratch/parse.err")" 120)"
  fi
fi

tj() { [ "$parse_ok" = true ] && jq -r "$1" "$trace" 2>/dev/null; }
model_id="$(tj '.model_id // ""')"
cost_usd="$(tj '.cost_usd // "" | tostring')"
[ "$cost_usd" = "null" ] && cost_usd=""
num_turns="$(tj '.num_turns // "" | tostring')"
[ "$num_turns" = "null" ] && num_turns=""
skills_invoked="$(tj '[.skills_invoked[]?.skill] | unique | join(",")')"
trace_stop="$(tj '.stop_reason // "incomplete"')"
[ -n "$trace_stop" ] || trace_stop="incomplete"
child_session="$(tj '.session_id // ""')"

# ---------------------------------------------------------------- stop reason
if [ "$stopped" = true ]; then
  stop_reason="stopped_on_skill"
elif [ "$timed_out" = true ]; then
  stop_reason="timeout"
  add_issue ERROR timeout "the child exceeded --timeout ${timeout_s}s and was killed"
elif [ "$parse_ok" != true ]; then
  stop_reason="error"
else
  case "$trace_stop" in
    completed) stop_reason="completed" ;;
    max_turns) stop_reason="max_turns"
      add_issue WARN max_turns "the child hit --max-turns ${max_turns:-?} before finishing" ;;
    budget) stop_reason="budget"
      add_issue WARN budget "the child hit --max-budget-usd ${budget:-?} before finishing" ;;
    incomplete) stop_reason="error"
      add_issue ERROR truncated_stream "the stream ended without a result event (child exit $child_exit)" ;;
    *) stop_reason="error"
      add_issue ERROR child_error "the child reported an error result (child exit $child_exit)" ;;
  esac
fi
if [ "$stop_reason" = completed ] && [ "$child_exit" -ne 0 ]; then
  add_issue WARN child_exit_nonzero "result event says completed but the child exited $child_exit"
fi

# ---------------------------------------------------------------- leak checks
if [ "$parse_ok" = true ]; then
  if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] && [ "$child_session" = "$CLAUDE_CODE_SESSION_ID" ]; then
    add_issue WARN session_id_leak "child session_id equals the parent CLAUDE_CODE_SESSION_ID"
  fi
  # Hook events the loaded plugin dirs declare; anything else that fired is foreign.
  declared_events=""
  for pd in "${abs_plugin_dirs[@]+"${abs_plugin_dirs[@]}"}"; do
    hook_files=()
    manifest="$pd/.claude-plugin/plugin.json"
    if [ -f "$manifest" ]; then
      mh_type="$(jq -r '.hooks | type' "$manifest" 2>/dev/null)"
      case "$mh_type" in
        string) hook_files+=("$pd/$(jq -r '.hooks' "$manifest")") ;;
        array) while IFS= read -r hf; do hook_files+=("$pd/$hf"); done < <(jq -r '.hooks[] | strings' "$manifest") ;;
        object) declared_events+=" $(jq -r '(.hooks.hooks // .hooks) | keys[]' "$manifest" 2>/dev/null | tr '\n' ' ')" ;;
      esac
    fi
    [ -f "$pd/hooks/hooks.json" ] && hook_files+=("$pd/hooks/hooks.json")
    for hf in "${hook_files[@]+"${hook_files[@]}"}"; do
      [ -f "$hf" ] && declared_events+=" $(jq -r '(.hooks // {}) | keys[]' "$hf" 2>/dev/null | tr '\n' ' ')"
    done
  done
  foreign="$(jq -r --arg declared "$declared_events" '
      ($declared | split(" ") | map(select(length > 0))) as $d
      | [.hooks_fired[]?
         | if type == "object" then (.hook_event // .event // ((.hook_name // .name // "") | split(":")[0]))
           else (tostring | split(":")[0]) end
         | select(length > 0) | select(. as $e | $d | index($e) | not)]
      | unique | join(",")' "$trace" 2>/dev/null)"
  if [ -n "$foreign" ]; then
    add_issue WARN foreign_hook "hooks fired that no --plugin-dir declares: $foreign"
  fi
fi

# ---------------------------------------------------------------- transcript.md
transcript_md="$run_dir/transcript.md"
if [ "$parse_ok" = true ]; then
  jq -r '
    (.final_text // "") + "\n\n---\n## Tool calls\n\n" +
    ( [.tool_calls[]?
        | "- [turn \(.turn // "?")] \(.name // "?"): \((.input_summary // "") | tostring | gsub("\n"; " ") | .[0:300])"
          + (if .denied then " (denied)" else "" end)
          + (if .is_error then " (error)" else "" end)]
      | if length == 0 then "(none)" else join("\n") end ) + "\n"' "$trace" >"$transcript_md"
else
  printf '\n\n---\n## Tool calls\n\n(unavailable: trace not parsed)\n' >"$transcript_md"
fi

# ---------------------------------------------------------------- workspace snapshot
workspace=""
if [ "$do_snapshot" = true ]; then
  ws="$run_dir/workspace"
  # Apparent size, not allocated blocks: a sparse file (truncate -s 100G) is
  # 4 KB to plain `du -sk` but full-size to anything that copies it later.
  size_kb="$(du -sk --apparent-size "$workdir" 2>/dev/null | cut -f1)"
  [ -n "$size_kb" ] || size_kb="$(du -skA "$workdir" 2>/dev/null | cut -f1)"
  size_kb="${size_kb:-0}"
  if [ "$size_kb" -gt $(( snapshot_max_mb * 1024 )) ]; then
    add_issue WARN snapshot_skipped "workdir is ${size_kb}KB, over --snapshot-max-mb ${snapshot_max_mb}; no workspace snapshot"
  else
    rm -rf "$ws"
    mkdir -p "$ws"
    if cp -a "$workdir/." "$ws/" 2>"$scratch/cp.err"; then
      workspace="$ws"
    else
      add_issue WARN snapshot_failed "copying the workdir failed: $(one_line "$(head -c 200 "$scratch/cp.err")" 120)"
    fi
  fi
fi

# ---------------------------------------------------------------- timing + meta
jq -n --arg s "$started_at" --arg e "$ended_at" --argjson d "$duration_ms" \
  --arg cost "$cost_usd" --arg turns "$num_turns" \
  '{started_at: $s, ended_at: $e, duration_ms: $d, durationMs: $d, harness: "claude-code",
    total_cost_usd: (if $cost == "" then null else ($cost | tonumber) end),
    num_turns: (if $turns == "" then null else ($turns | tonumber) end)}' >"$run_dir/timing.json"

prompt_sha="$(printf '%s' "$prompt" | sha256_of)"
# The prompt is on stdin, so argv carries no prompt text to redact.
redacted_args=("${claude_args[@]}")
plugin_json="$(printf '%s\n' "${abs_plugin_dirs[@]+"${abs_plugin_dirs[@]}"}" | jq -R . | jq -s 'map(select(length > 0))')"
passed_json="$(printf '%s\n' "${passed_names[@]+"${passed_names[@]}"}" | jq -R . | jq -s 'map(select(length > 0))')"
denied_json="$(printf '%s\n' "${denied_passthrough[@]+"${denied_passthrough[@]}"}" | jq -R . | jq -s 'map(select(length > 0))')"
stripped_json="$(printf '%s\n' "${stripped_creds[@]+"${stripped_creds[@]}"}" | jq -R . | jq -s 'map(select(length > 0))')"
argv_json="$(printf '%s\n' "${redacted_args[@]}" | jq -R . | jq -s .)"
jq -n --arg sha "$prompt_sha" --arg model "$model" --arg effort "$effort" --arg budget "$budget" \
  --arg max_turns "$max_turns" --arg allowed "$allowed_tools" --arg perm "$permission" \
  --argjson timeout "$timeout_s" --arg env_req "$env_mode" --arg env_eff "$effective_env_mode" \
  --argjson stop "$stop_on_skill" --argjson plugins "$plugin_json" --argjson passed "$passed_json" \
  --argjson denied "$denied_json" --argjson stripped "$stripped_json" --argjson argv "$argv_json" --arg workdir "$workdir" \
  --argjson mt_ok "$use_max_turns" --argjson eff_ok "$use_effort" --argjson remote "$([ -n "${CLAUDE_CODE_REMOTE:-}" ] && echo true || echo false)" \
  '{harness: "claude-code", prompt_sha256: $sha, model: $model,
    effort: (if $effort == "" then null else $effort end),
    max_budget_usd: (if $budget == "" then null else ($budget | tonumber) end),
    max_turns: (if $max_turns == "" then null else ($max_turns | tonumber) end),
    max_turns_accepted: (if $max_turns == "" then null else $mt_ok end),
    effort_accepted: (if $effort == "" then null else $eff_ok end),
    allowed_tools: (if $allowed == "" then null else $allowed end),
    permission: $perm, timeout_s: $timeout, stop_on_skill: $stop,
    env_mode_requested: $env_req, env_mode: $env_eff, cloud_remote: $remote,
    passthrough_env_names: $passed, passthrough_env_denied: $denied,
    inherit_stripped_env: $stripped,
    plugin_dirs: $plugins, workdir: $workdir, claude_argv: $argv}' >"$run_dir/rollout-meta.json"

# ---------------------------------------------------------------- report
has_error=false; has_warn=false
for i in "${issues[@]+"${issues[@]}"}"; do
  case "$i" in ERROR\|*) has_error=true ;; WARN\|*) has_warn=true ;; esac
done
if [ "$has_error" = true ]; then report_status=ERROR
elif [ "$has_warn" = true ]; then report_status=WARN
else report_status=OK; fi

echo "=== HEADLESS ROLLOUT ==="
echo "RUN_DIR=$run_dir"
echo "WORKDIR=$workdir"
echo "TRANSCRIPT_JSONL=$transcript"
echo "TRANSCRIPT_MD=$transcript_md"
echo "TRACE=$([ "$parse_ok" = true ] && echo "$trace")"
echo "WORKSPACE=$workspace"
echo "MODEL_ID=$model_id"
echo "COST_USD=$cost_usd"
echo "NUM_TURNS=$num_turns"
echo "SKILLS_INVOKED=$skills_invoked"
echo "STOP_REASON=$stop_reason"
echo "CHILD_EXIT=$child_exit"
echo "ENV_MODE=$effective_env_mode"
echo "STATUS=$report_status"
if [ "$report_status" != OK ]; then
  first=""
  for i in "${issues[@]}"; do
    case "$i" in "$report_status|"*) [ -z "$first" ] && first="$i" ;; esac
  done
  others=$(( ${#issues[@]} - 1 ))
  f_rest="${first#*|}"
  reason="$(one_line "${f_rest%%|*}: ${f_rest#*|}" 180)"
  [ "$others" -gt 0 ] && reason="$reason (+$others more)"
  echo "REASON=$reason"
fi
echo "ISSUE_COUNT=${#issues[@]}"
if [ "${#issues[@]}" -gt 0 ]; then
  echo "ISSUES:"
  for i in "${issues[@]}"; do
    sev="${i%%|*}"; rest="${i#*|}"
    echo "  - SEVERITY=$sev TYPE=${rest%%|*} MSG=$(one_line "${rest#*|}" 300)"
  done
fi
echo "=== END HEADLESS ROLLOUT ==="

[ "$report_status" = ERROR ] && exit 1
exit 0

#!/usr/bin/env bash
# Subagent context/compaction probe.
#
# For each (model × autoCompactEnabled) arm, run `claude -p` in an isolated fake
# HOME whose main agent spawns ONE briefed subagent that reads a filler corpus
# and reports each file's sentinel. CLAUDE_AUTOCOMPACT_PCT_OVERRIDE is set low
# so a 1M-window model compacts at ~100k instead of ~800k — cheap to trigger.
#
# Questions each arm answers (see ../README.md):
#   Q1  Does main-config autoCompactEnabled=false reach subagents?   (ac-off arm: SUBAGENT_COMPACTED)
#   Q2  Does the subagent resume its task after compacting?          (SENTINELS_* vs. DISTINCT_FILES_READ)
#   Q3  Does PreCompact fire inside a subagent, with an agent_id?    (HOOK_PreCompact, PRECOMPACT_WITH_AGENT_ID)
#
# Auth: the fake HOME has no login, so this sources CLAUDE_CODE_OAUTH_TOKEN (or
# ANTHROPIC_API_KEY) from the environment or ~/.api_tokens (`claude setup-token`).
#
# Usage: ctx-probe.sh [--models "opus[1m] sonnet[1m]"] [--arms "on off"] [--pct 10]
#                     [--files 30] [--kb 40] [--run-id ID] [--results-root DIR] [--dry-run]
#
# The child runs under `env -i` with an allowlist (PATH, TERM, locale, auth,
# proxy/CA) so no parent Claude Code session variable leaks into an arm.
# CLAUDE_CODE_SUBAGENT_MODEL is set to the arm's model so the subagent keeps the
# [1m] window instead of falling back to a default model.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exp_root="$(dirname "$here")"

models="opus[1m]"
arms="on off"
pct=10
files=30
kb=40
run_id="$(date +%Y%m%dT%H%M%S)"
dry_run=0
results_root="$exp_root/results"

while [ $# -gt 0 ]; do
  case "$1" in
    --models) models="$2"; shift 2 ;;
    --arms) arms="$2"; shift 2 ;;
    --pct) pct="$2"; shift 2 ;;
    --files) files="$2"; shift 2 ;;
    --kb) kb="$2"; shift 2 ;;
    --run-id) run_id="$2"; shift 2 ;;
    --results-root) results_root="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

for dep in jq awk sha256sum; do
  command -v "$dep" >/dev/null || { echo "STATUS=missing_dependency DEP=$dep"; exit 1; }
done
claude_bin="$(command -v claude || true)"
[ -n "$claude_bin" ] || [ "$dry_run" -eq 1 ] || { echo "STATUS=missing_dependency DEP=claude"; exit 1; }

if [ "$dry_run" -eq 0 ]; then
  if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -f "$HOME/.api_tokens" ]; then
    set +e +u; set -a
    # shellcheck disable=SC1091
    . "$HOME/.api_tokens" 2>/dev/null
    set +a; set -e -u
  fi
  if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "STATUS=no_auth (set CLAUDE_CODE_OAUTH_TOKEN via 'claude setup-token', or ANTHROPIC_API_KEY)"
    exit 1
  fi
fi

results="$results_root/$run_id"
mkdir -p "$results"
# Fixture lives outside the repo so the child session loads no project
# CLAUDE.md, rules or settings. sentinels.txt is copied into results for scoring.
fixture="$(mktemp -d)"
if [ -z "$fixture" ] || [ ! -d "$fixture" ]; then echo "mktemp failed" >&2; exit 1; fi
trap 'rm -rf "$fixture"' EXIT
bash "$here/make-fixture.sh" "$fixture" "$files" "$kb"
cp "$fixture/sentinels.txt" "$results/sentinels.txt"

last="$(printf 'f%02d.txt' "$files")"
prompt="This is a context-window probe. Do exactly this and nothing else.

Spawn ONE subagent with the Agent tool (subagent_type: general-purpose; do not set model, so it inherits yours). Give it this brief verbatim:

---
Read the files $fixture/files/f01.txt through $fixture/files/$last in numeric order with the Read tool: one whole file per call (no offset/limit), one call at a time. The last line of each file is \`SENTINEL <file> <hex>\`. After the last file, reply with only the sentinel lines, one per line, in file order. Never guess or reconstruct a sentinel that is not in a Read result visible in your current context; write \`MISSING <file>\` for that file instead.
---

Then reply with the subagent's report verbatim and nothing else."

printf 'arm\tmodel\tautocompact\tcompacted\tauto_compacted\tcompactions\tpeak_ctx\tfiles_read\treport_source\tcorrect\twrong\tdeclared_missing\tabsent\tprecompact_hooks\tprecompact_agent_id\tstatus\n' > "$results/summary.tsv"

# Environment passed to the child: an allowlist, not the parent's environment.
base_env=("PATH=$PATH")
for var in TERM LANG LC_ALL CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY \
    HTTPS_PROXY HTTP_PROXY NO_PROXY https_proxy http_proxy no_proxy \
    NODE_EXTRA_CA_CERTS SSL_CERT_FILE REQUESTS_CA_BUNDLE; do
  if [ -n "${!var:-}" ]; then base_env+=("$var=${!var}"); fi
done

set -f  # model names contain [ ]; keep word splitting, disable globbing
for model in $models; do
  for arm in $arms; do
    case "$arm" in on) ac=true ;; off) ac=false ;; *) echo "unknown arm: $arm" >&2; exit 2 ;; esac
    slug="$(printf '%s' "$model" | tr -c 'A-Za-z0-9' '_')-ac-$arm"
    arm_dir="$results/$slug"
    home="$arm_dir/home"
    mkdir -p "$home/.claude"

    jq -n --argjson ac "$ac" '{hasCompletedOnboarding: true, autoCompactEnabled: $ac}' > "$home/.claude.json"
    hook_cmd="bash $(printf %q "$here/log-hook.sh") $(printf %q "$arm_dir/hooks.jsonl")"
    jq -n --arg c "$hook_cmd" '{hooks: (["PreCompact","PostCompact","SubagentStart","SubagentStop"]
        | map({key: ., value: [{matcher: "", hooks: [{type: "command", command: $c}]}]}) | from_entries)}' \
      > "$home/.claude/settings.json"
    printf 'MODEL=%s\nAUTO_COMPACT_ENABLED=%s\nAUTOCOMPACT_PCT_OVERRIDE=%s\n' "$model" "$ac" "$pct" > "$arm_dir/arm.env"

    echo "=== RUN $slug ==="
    if [ "$dry_run" -eq 1 ]; then
      echo "DRY_RUN: cd $fixture/files && env -i <allowlist> HOME=$home CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=$pct CLAUDE_CODE_SUBAGENT_MODEL='$model' claude -p <prompt> --model '$model' --output-format stream-json --verbose --allowedTools Read,Agent,Task"
      continue
    fi

    ( cd "$fixture/files" && env -i "${base_env[@]}" \
        HOME="$home" CLAUDE_AUTOCOMPACT_PCT_OVERRIDE="$pct" CLAUDE_CODE_SUBAGENT_MODEL="$model" \
        "$claude_bin" -p "$prompt" --model "$model" --output-format stream-json --verbose \
          --allowedTools "Read,Agent,Task" \
        > "$arm_dir/main.jsonl" 2> "$arm_dir/stderr.log" ) || echo "RUN_EXIT=$?"

    # analyze.sh exits 1 on an ERROR arm; record it and keep going.
    bash "$here/analyze.sh" "$arm_dir" "$results/sentinels.txt" > "$arm_dir/summary.txt" || true
    cat "$arm_dir/summary.txt"
    s="$arm_dir/summary.txt"
    v() { awk -F= -v k="$1" '$1 == k {sub(/^[^=]*=/, ""); print; exit}' "$s"; }
    peak="$(awk -F= '/^PEAK_CTX=/ && $2 > m {m = $2} END {print m + 0}' "$s")"
    comps="$(awk -F= '/^COMPACTIONS=/ {t += $2} END {print t + 0}' "$s")"
    read_n="$(awk -F= '/^DISTINCT_FILES_READ=/ && $2 > m {m = $2} END {print m + 0}' "$s")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$slug" "$model" "$ac" "$(v SUBAGENT_COMPACTED)" "$(v SUBAGENT_AUTO_COMPACTED)" "$comps" "$peak" "$read_n" \
      "$(v REPORT_SOURCE)" "$(v SENTINELS_CORRECT)" "$(v SENTINELS_WRONG)" "$(v SENTINELS_DECLARED_MISSING)" \
      "$(v SENTINELS_ABSENT)" "$(v HOOK_PreCompact)" "$(v PRECOMPACT_WITH_AGENT_ID)" "$(v STATUS)" >> "$results/summary.tsv"
  done
done
set +f

echo "=== SUMMARY ==="
column -t -s $'\t' "$results/summary.tsv" 2>/dev/null || cat "$results/summary.tsv"
echo "RESULTS_DIR=$results"

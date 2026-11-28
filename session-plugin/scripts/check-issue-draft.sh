#!/usr/bin/env bash
# check-issue-draft.sh — scan a drafted GitHub issue body before it is filed.
#
# session-workflow-capture runs this over every draft. A draft bound for a
# public, generic tracker (--audience public) must carry nothing tied to the
# session, the machine or the calling repository; a draft bound for the calling
# repository itself (--audience project) is checked for secrets and session
# artifacts only, since repo-specific detail belongs there.
#
# READ-ONLY. Deterministic: the same draft and inputs give the same verdict.
# Output follows .claude/rules/structured-script-output.md. Exit 0 on OK/WARN,
# 1 on ERROR, 2 on a usage error.
#
# Usage:
#   bash check-issue-draft.sh --draft <file> --audience public|project
#       [--project-dir <path>] [--home-dir <path>] [--target-repo <owner/name>]
#       [--deny-file <file>]
#
# Inputs beyond the draft:
#   --project-dir   the calling repository; its git remote (owner/name, host)
#                   and checkout directory name become terms a public draft
#                   must not carry, unless --target-repo IS that repository
#   --deny-file     extra literal terms, one per line (private repo names,
#                   people, internal codenames); '#' lines are comments
#   private_terms:  a YAML list in the frontmatter of .claude/session-plugin.local.md
#                   (project) and ~/.claude/session-plugin.local.md (user)
#
# What each audience checks (ERROR blocks filing, WARN asks for a look):
#   TYPE              public  project
#   secret            ERROR   ERROR    token and key shapes, plus gitleaks if installed
#   home_path         ERROR   WARN     /Users/<x>, /home/<x>, C:\Users\<x>, \\wsl$\<distro>\home\<x>
#   session_artifact  ERROR   WARN     ~/.claude/projects paths and slugs, session UUIDs, wf_ run ids, toolu_ ids
#   cloud_account     ERROR   WARN     AWS ARNs and account ids
#   email             ERROR   WARN     any address except noreply, example domains and git@host: remotes
#   calling_repo      ERROR   -        owner/name or remote URL of the calling repo
#   calling_owner     ERROR   -        the calling repo's owner, unless the target repo has the same owner
#   calling_repo_unknown WARN -        no git remote could be read, so the repo checks did not run
#   remote_host       ERROR   -        a git host of the calling repo other than github.com
#   private_term      ERROR   -        --deny-file and private_terms: entries
#   repo_name         WARN    -        the calling repo's bare name as a word
#   checkout_dir      WARN    -        the checkout directory name as a word
#   ip_address        WARN    WARN     IPv4 outside loopback and the documentation ranges; a
#                                      four-part version (v1.2.3.4, version 22.11.0.4, an
#                                      octet over 255, a -rc1/-beta2/+build7 suffix) is skipped
#   internal_host     WARN    -        *.internal, *.local, *.lan, *.corp, *.intra, *.svc
#   relative_link     WARN    -        a markdown link into ../ or ./ (dead in another repo)
#   ticket_link       WARN    -        Jira-style /browse/KEY-123 links
#   chat_link         WARN    -        Slack archive links
#   checkout_layout   WARN    -        ~/repos/<name>, ~/src/<name> and similar checkout paths
set -uo pipefail

draft=""
audience=""
project_dir=""
home_dir=""
target_repo=""
deny_file=""

while [ $# -gt 0 ]; do
  case "$1" in
    --draft) draft="${2:-}"; shift 2 ;;
    --audience) audience="${2:-}"; shift 2 ;;
    --project-dir) project_dir="${2:-}"; shift 2 ;;
    --home-dir) home_dir="${2:-}"; shift 2 ;;
    --target-repo) target_repo="${2:-}"; shift 2 ;;
    --deny-file) deny_file="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

: "${project_dir:=$(pwd)}"
: "${home_dir:=$HOME}"
gitleaks_bin="${CHECK_ISSUE_DRAFT_GITLEAKS_BIN:-gitleaks}"

usage_error() {
  echo "=== ISSUE DRAFT SCAN ==="
  echo "STATUS=ERROR"
  echo "REASON=usage: $1"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=usage MSG=$1"
  echo "=== END ISSUE DRAFT SCAN ==="
  exit 2
}

[ -n "$draft" ] || usage_error "--draft <file> is required"
[ -f "$draft" ] || usage_error "draft not found: $draft"
case "$audience" in public|project) ;; *) usage_error "--audience must be public or project" ;; esac

have() { command -v "$1" >/dev/null 2>&1; }
lower() { tr '[:upper:]' '[:lower:]' <<<"$1"; }

findings=""   # rows: SEVERITY<TAB>TYPE<TAB>LINE<TAB>MSG
add() { findings+="$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"$'\n'; }

# sev <public-severity> <project-severity>; "-" means not checked
sev() { if [ "$audience" = public ]; then echo "$1"; else echo "$2"; fi; }

show() { # shorten a match for the report: one line, trimmed, at most $2 chars
  local s="$1" max="${2:-40}"
  s=${s//$'\n'/ }; s=${s//$'\t'/ }
  s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"
  if [ "${#s}" -gt "$max" ]; then s="${s:0:$max}..."; fi
  printf '%s' "$s"
}

# scan <type> <severity> <ERE> <msg> [case-insensitive] [redact]
scan() {
  local t="$1" s="$2" re="$3" msg="$4" ci="${5:-}" redact="${6:-}" hits line match
  [ "$s" = "-" ] && return 0
  if [ -n "$ci" ]; then hits=$(grep -noiE -e "$re" "$draft" 2>/dev/null)
  else hits=$(grep -noE -e "$re" "$draft" 2>/dev/null); fi
  [ -n "$hits" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    match=${line#*:}
    if [ -n "$redact" ]; then match="${match:0:4}..."; else match=$(show "$match"); fi
    add "$s" "$t" "${line%%:*}" "$msg ($match)"
  done <<<"$hits"
}

# scan_literal <type> <severity> <term> <msg> — fixed-string, word-bounded, case-insensitive
scan_literal() {
  local t="$1" s="$2" term="$3" msg="$4" hits ln
  [ "$s" = "-" ] && return 0
  [ "${#term}" -ge 3 ] || return 0
  hits=$(grep -noiwF -e "$term" "$draft" 2>/dev/null | cut -d: -f1 | sort -un)
  [ -n "$hits" ] || return 0
  while IFS= read -r ln; do
    [ -n "$ln" ] && add "$s" "$t" "$ln" "$msg ($(show "$term"))"
  done <<<"$hits"
}

# --- secrets ----------------------------------------------------------------
s_secret=$(sev ERROR ERROR)
scan secret "$s_secret" 'gh[pousr]_[A-Za-z0-9]{30,}' "GitHub token" "" redact
scan secret "$s_secret" 'github_pat_[A-Za-z0-9_]{20,}' "GitHub fine-grained token" "" redact
scan secret "$s_secret" 'sk-ant-[A-Za-z0-9_-]{20,}' "Anthropic API key" "" redact
scan secret "$s_secret" 'sk-[A-Za-z0-9]{32,}' "API key" "" redact
scan secret "$s_secret" 'sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{20,}' "OpenAI project or service key" "" redact
scan secret "$s_secret" '(AKIA|ASIA)[0-9A-Z]{16}' "AWS access key id" "" redact
scan secret "$s_secret" 'xox[abprs]-[A-Za-z0-9-]{10,}' "Slack token" "" redact
scan secret "$s_secret" 'AIza[0-9A-Za-z_-]{35}' "Google API key" "" redact
scan secret "$s_secret" '-----BEGIN [A-Z ]*PRIVATE KEY-----' "private key block"
scan secret "$s_secret" 'glpat-[A-Za-z0-9_-]{20,}' "GitLab token" "" redact
if have "$gitleaks_bin"; then
  gl_dir=$(mktemp -d) || gl_dir=""
  if [ -n "$gl_dir" ]; then
    cp "$draft" "$gl_dir/draft.md"
    "$gitleaks_bin" dir "$gl_dir" --no-banner --report-format json \
      --report-path "$gl_dir/report.json" --exit-code 0 >/dev/null 2>&1 \
      || "$gitleaks_bin" detect --no-git --source "$gl_dir" --no-banner --report-format json \
           --report-path "$gl_dir/report.json" --exit-code 0 >/dev/null 2>&1 || true
    if [ -s "$gl_dir/report.json" ] && have jq; then
      while IFS=$'\t' read -r gl_line gl_rule; do
        [ -n "$gl_line" ] || continue
        # The regex set above already reported this line: one row per leak.
        grep -q $'\tsecret\t'"${gl_line}"$'\t' <<<"$findings" && continue
        add "$s_secret" secret "$gl_line" "gitleaks rule $gl_rule"
      done < <(jq -r '.[]? | [(.StartLine // 0), (.RuleID // "unknown")] | @tsv' "$gl_dir/report.json" 2>/dev/null)
    fi
    rm -rf "$gl_dir"
  fi
fi

# --- machine and session artifacts -------------------------------------------
s_home=$(sev ERROR WARN)
scan home_path "$s_home" '/(Users|home)/[A-Za-z][A-Za-z0-9._-]*([/[:space:]"'"'"'`),;:]|$)' "absolute home path"
scan home_path "$s_home" '[A-Za-z]:\\Users\\[A-Za-z][A-Za-z0-9._-]*' "absolute home path"
scan home_path "$s_home" '\\\\wsl(\$|\.localhost)\\[^\\]+\\home\\[A-Za-z][A-Za-z0-9._-]*' "WSL home path"
# shellcheck disable=SC2088  # a literal "~/" in the draft text, not a path to expand
scan checkout_layout "$(sev WARN -)" '~/(repos|src|code|projects|work|dev|git|workspace)/[A-Za-z0-9._-]+' "local checkout layout"
s_sess=$(sev ERROR WARN)
scan session_artifact "$s_sess" '\.claude/projects/[^[:space:])`"]+' "Claude transcript path"
scan session_artifact "$s_sess" '(^|[^A-Za-z0-9/])-(home|Users)-[A-Za-z0-9._-]+-' "Claude transcript slug"
# UUIDs, minus the RFC 4122 example and the nil UUID, which generic drafts quote.
uuid_hits=$(grep -noiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$draft" 2>/dev/null \
  | grep -viE ':(123e4567-e89b-12d3-a456-426614174000|00000000-0000-0000-0000-000000000000)$' || true)
while IFS= read -r line; do
  [ -n "$line" ] && add "$s_sess" session_artifact "${line%%:*}" "session or object UUID (${line#*:})"
done <<<"$uuid_hits"
s_cloud=$(sev ERROR WARN)
scan cloud_account "$s_cloud" 'arn:aws[a-z-]*:[a-z0-9-]*:[a-z0-9-]*:[0-9]{12}:' "AWS ARN with account id"
scan cloud_account "$s_cloud" 'account[ _-]?(id|number)?[^0-9A-Za-z]{1,5}[0-9]{12}([^0-9]|$)' "AWS account id" ci
scan session_artifact "$s_sess" '(^|[^A-Za-z0-9_])wf_[0-9a-f]{6,}(-[0-9a-f]+)?' "Workflow run id"
scan session_artifact "$s_sess" 'toolu_[A-Za-z0-9]{10,}' "tool-use id"
s_mail=$(sev ERROR WARN)
# A trailing ':' marks an SCP-style git remote (git@host:owner/repo), which the
# calling-repo and host checks own; a line that already has a secret row is
# skipped so a token used as a URL credential is never printed through this rule.
mail_hits=$(grep -noiE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}:?' "$draft" 2>/dev/null \
  | grep -vE ':$' \
  | grep -viE ':[^:]*(noreply|no-reply)@|@(example\.(com|org|net)|users\.noreply\.github\.com)$' || true)
while IFS= read -r line; do
  [ -n "$line" ] || continue
  grep -q $'\tsecret\t'"${line%%:*}"$'\t' <<<"$findings" && continue
  add "$s_mail" email "${line%%:*}" "email address ($(show "${line#*:}"))"
done <<<"$mail_hits"
s_ip=$(sev WARN WARN)
# A dotted quad is a version, not an address, when an octet exceeds 255, when
# a lone v/V sits right before it (v22.11.0.4), when the word before it is
# version/ver/release/build, or when a pre-release tag (-rc1, -alpha, -beta2,
# -pre, -dev, -snapshot) or a +<alnum> suffix follows (22.11.0.4+build7). Each
# match carries the word before it and any suffix so those can be read; a bare
# quad stays a WARN (#3683). Not skipped: user@10.1.2.3 (ssh, scp, git remotes,
# URL userinfo) and 10.0.0.1-eth0, which are addresses. Known gap: a word rule
# reads only the word right before a quad, so "10.1.2.3 build 10.4.5.6" skips
# the second address.
is_version_quad() { # match-text ip
  local m="$1" ip="$2" pre post o
  for o in ${ip//./ }; do [ $((10#$o)) -gt 255 ] && return 0; done
  pre=$(tr '[:upper:]' '[:lower:]' <<<"${m%%"$ip"*}")
  post=${m#*"$ip"}
  post=$(tr '[:upper:]' '[:lower:]' <<<"$post")
  [[ "$pre" =~ (^|[^a-z])v$ ]] && return 0
  [[ "$pre" =~ (^|[^a-z])(version|ver|release|build)[[:space:]]*[:=]?[[:space:]]*$ ]] && return 0
  [[ "$post" =~ ^(-(rc|alpha|beta|pre|dev|snapshot)[0-9]*([^0-9a-z]|$)|\+[0-9a-z]) ]] && return 0
  return 1
}
ip_hits=$(grep -noE '(^|[^0-9.])([A-Za-z]+[[:space:]]*[:=]?[[:space:]]*)?([0-9]{1,3}\.){3}[0-9]{1,3}([-+][0-9A-Za-z]+)?($|[^0-9.])' "$draft" 2>/dev/null || true)
while IFS= read -r line; do
  [ -n "$line" ] || continue
  ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' <<<"${line#*:}")
  ip=${ip%%$'\n'*}
  case "$ip" in 127.*|0.0.0.0|192.0.2.*|198.51.100.*|203.0.113.*) continue ;; esac
  is_version_quad "${line#*:}" "$ip" && continue
  add "$s_ip" ip_address "${line%%:*}" "IPv4 address ($ip)"
done <<<"$ip_hits"
scan internal_host "$(sev WARN -)" '[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.(internal|local|lan|corp|intra|svc)\.?([^A-Za-z0-9.-]|$)' "internal hostname"
scan ticket_link "$(sev WARN -)" '(atlassian\.net/browse/|/browse/)[A-Z][A-Z0-9]+-[0-9]+' "ticket link"
scan chat_link "$(sev WARN -)" '[A-Za-z0-9-]+\.slack\.com/archives/[A-Za-z0-9]+' "chat archive link"
scan relative_link "$(sev WARN -)" '\]\(\.{1,2}/[^)]*\)' "relative link (dead outside its repo)"

# --- the calling repository -----------------------------------------------------
calling_repo=""; calling_host=""; calling_name=""
if have git; then
  remote_url=$(git -C "$project_dir" remote get-url origin 2>/dev/null || true)
  if [ -z "$remote_url" ]; then
    # No origin: the first remote stands for the repository.
    remotes=$(git -C "$project_dir" remote 2>/dev/null || true)
    first_remote=${remotes%%$'\n'*}
    [ -n "$first_remote" ] && remote_url=$(git -C "$project_dir" remote get-url "$first_remote" 2>/dev/null || true)
  fi
  if [ -n "$remote_url" ]; then
    hostpart=$(sed -E 's#^[a-z+]+://##; s#^[^@]*@##; s#[:/].*$##' <<<"$remote_url")
    repopart=$(sed -E 's#^[a-z+]+://[^/]+/##; s#^[^@]*@[^:]+:##; s#\.git$##; s#/$##' <<<"$remote_url")
    calling_host=$(lower "$hostpart")
    case "$repopart" in */*) calling_repo="$repopart"; calling_name="${repopart##*/}" ;; esac
  fi
fi
same_repo=false
if [ -n "$calling_repo" ] && [ -n "$target_repo" ] && [ "$(lower "$calling_repo")" = "$(lower "$target_repo")" ]; then
  same_repo=true
fi
if [ "$same_repo" = false ]; then
  if [ -n "$calling_repo" ]; then
    scan_literal calling_repo "$(sev ERROR -)" "$calling_repo" "calling repository"
    [ -n "$calling_name" ] && scan_literal repo_name "$(sev WARN -)" "$calling_name" "calling repository name"
    calling_owner=${calling_repo%%/*}
    if [ "$(lower "$calling_owner")" != "$(lower "${target_repo%%/*}")" ]; then
      scan_literal calling_owner "$(sev ERROR -)" "$calling_owner" "calling repository owner"
    fi
  elif [ "$audience" = public ]; then
    add WARN calling_repo_unknown 0 "no git remote could be read from --project-dir, so the calling-repo checks did not run"
  fi
  if [ -n "$calling_host" ] && [ "$calling_host" != "github.com" ]; then
    scan_literal remote_host "$(sev ERROR -)" "$calling_host" "private git host"
  fi
  checkout=$(basename "$project_dir")
  if [ -n "$checkout" ] && [ "$(lower "$checkout")" != "$(lower "${calling_name:-}")" ]; then
    scan_literal checkout_dir "$(sev WARN -)" "$checkout" "checkout directory name"
  fi
fi

# --- private terms ----------------------------------------------------------------
# private_terms: from plugin settings frontmatter, inline [a, b] or a block list.
settings_terms() {
  local f="$1"
  [ -f "$f" ] || return 0
  awk '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    /^private_terms:[[:space:]]*\[/ {
      s = $0; sub(/^[^[]*\[/, "", s); sub(/\].*$/, "", s)
      n = split(s, a, ","); for (i = 1; i <= n; i++) print a[i]; next
    }
    /^private_terms:[[:space:]]*$/ { inlist = 1; next }
    inlist && /^[[:space:]]*-[[:space:]]*/ { s = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", s); print s; next }
    inlist && /^[^[:space:]]/ { inlist = 0 }
  ' "$f" | sed -E "s/^[[:space:]\"']+//; s/[[:space:]\"']+$//" | sed '/^$/d'
}
terms=$( { settings_terms "$project_dir/.claude/session-plugin.local.md"
           settings_terms "$home_dir/.claude/session-plugin.local.md"
           if [ -n "$deny_file" ] && [ -f "$deny_file" ]; then grep -vE '^[[:space:]]*(#|$)' "$deny_file"; fi
         } | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | sort -u)
s_priv=$(sev ERROR -)
while IFS= read -r term; do
  [ -n "$term" ] && scan_literal private_term "$s_priv" "$term" "private term"
done <<<"$terms"

# --- report --------------------------------------------------------------------------
findings=$(sed '/^$/d' <<<"$findings" | sort -t$'\t' -k3,3n -s)
errors=0; warns=0; total=0
if [ -n "$findings" ]; then
  errors=$(grep -c $'^ERROR\t' <<<"$findings" || true)
  warns=$(grep -c $'^WARN\t' <<<"$findings" || true)
  total=$(wc -l <<<"$findings"); total=$((total + 0))
fi
draft_status=OK
[ "${warns:-0}" -gt 0 ] && draft_status=WARN
[ "${errors:-0}" -gt 0 ] && draft_status=ERROR

echo "=== ISSUE DRAFT SCAN ==="
echo "AUDIENCE=${audience}"
echo "DRAFT=${draft}"
echo "CALLING_REPO=${calling_repo:-unknown}"
echo "TARGET_REPO=${target_repo:-unset}"
echo "SAME_REPO=${same_repo}"
echo "PRIVATE_TERM_COUNT=$(sed '/^$/d' <<<"$terms" | wc -l | tr -d ' ')"
echo "ERROR_COUNT=${errors:-0}"
echo "WARN_COUNT=${warns:-0}"
echo "STATUS=${draft_status}"
if [ "$draft_status" != OK ]; then
  first=$(grep -m1 "^${draft_status}"$'\t' <<<"$findings")
  reason="$(cut -f2 <<<"$first"): line $(cut -f3 <<<"$first") $(cut -f4 <<<"$first")"
  reason=$(tr -s '[:space:]' ' ' <<<"$reason"); reason="${reason% }"
  reason=${reason:0:180}
  [ "$total" -gt 1 ] && reason="${reason} (+$((total - 1)) more)"
  echo "REASON=${reason}"
fi
echo "ISSUE_COUNT=${total}"
if [ "$total" -gt 0 ]; then
  echo "ISSUES:"
  while IFS=$'\t' read -r f_sev f_type f_line f_msg; do
    [ -n "$f_sev" ] && echo "  - SEVERITY=${f_sev} TYPE=${f_type} LINE=${f_line} MSG=${f_msg}"
  done <<<"$findings"
fi
echo "=== END ISSUE DRAFT SCAN ==="
[ "$draft_status" = ERROR ] && exit 1
exit 0

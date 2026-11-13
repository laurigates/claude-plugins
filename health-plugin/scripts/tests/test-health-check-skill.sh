#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016 # `a && pass || fail` assertions; literal ${CLAUDE_*} text is matched on purpose
# Semantic guard for health-plugin/skills/health-check (SKILL.md + sidecars).
#
# Pins four invariants a bulk edit can silently break:
#   1. allowed-tools carries no near-full shell grant: no bare `Bash`,
#      `Bash(*)`, `Bash(bash *)` or `Bash(sh *)`. `Bash(bash *)` prefix-matches
#      any `bash -c '<script>'` (.claude/rules/agentic-permissions.md).
#   2. Every bundled script the body runs is pre-approved: each
#      `bash ${CLAUDE_SKILL_DIR}/…sh` / `bash ${CLAUDE_PLUGIN_ROOT}/…sh`
#      invocation is unquoted and has a matching `Bash(bash <path> *)` rule;
#      every such rule names a script that exists; every scripts/check-*.sh is
#      run by the body; no invocation carries a `$(…)` or backtick substitution. Measured on
#      Claude Code 2.1.322 (#3577): a quoted path is pre-approved only while it
#      holds no space, and a `$(…)` in the command voids the pre-approval.
#   3. No `/health:<name>` command reference in ANY health-plugin skill's
#      SKILL.md, REFERENCE.md or references/*.md, in any plugin's markdown, or
#      in health-plugin's hook and skill scripts points at a skill that is
#      `user-invocable: false` (typing it does nothing); the entry point is
#      `/health:check --scope=… [--fix]`.
#   4. The 1d permissions-coverage check is the script, and its reference
#      documents both rule forms (`Bash(<prefix> *)` and `Bash(<prefix>:*)`).
#   5. The stack and agentic audits are invoked through the Skill tool, never
#      by reading a sibling SKILL.md path.
#   6. health-plugin's README and docs/flow.md and health-check's
#      audit-scopes.md and command-reference.md carry no pre-fix claims.
#   7. The test-health-plugin-skill-guards pre-commit hook's files: regex and
#      --only globs reach every health-plugin skill script and test suite.
#
# Usage: bash test-health-check-skill.sh [--plugin-dir <health-plugin dir>]
# Exit 0 when every invariant holds, 1 otherwise.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/../.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --plugin-dir) plugin_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done

skill_dir="${plugin_dir}/skills/health-check"
skill_md="${skill_dir}/SKILL.md"

pass_count=0
fail_count=0
pass() { echo "PASS: $1"; pass_count=$((pass_count + 1)); }
fail() { printf 'FAIL: %b\n' "$1" >&2; fail_count=$((fail_count + 1)); }

[ -f "$skill_md" ] || { echo "FAIL: ${skill_md} not found" >&2; exit 1; }

skill_text="$(<"$skill_md")"

# --- frontmatter allowed-tools -> one rule per line
allowed_line="$(grep -m1 '^allowed-tools:' <<<"$skill_text")"
allowed_value="${allowed_line#allowed-tools:}"
mapfile -t grant_rules < <(tr ',' '\n' <<<"$allowed_value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed '/^$/d')
[ "${#grant_rules[@]}" -gt 0 ] && pass "allowed-tools parsed (${#grant_rules[@]} rules)" \
  || fail "no allowed-tools rules parsed from ${skill_md}"

# --- 1. no near-full shell grant
broad_hits=()
for rule_text in "${grant_rules[@]}"; do
  case "$rule_text" in
    'Bash'|'Bash(*)'|'Bash(bash *)'|'Bash(sh *)'|'Bash(bash:*)'|'Bash(sh:*)') broad_hits+=("$rule_text") ;;
  esac
done
if [ "${#broad_hits[@]}" -eq 0 ]; then
  pass "no bare Bash / Bash(*) / Bash(bash *) / Bash(sh *) grant"
else
  fail "near-full shell grant in allowed-tools: ${broad_hits[*]}"
fi

# resolve_script <path with ${CLAUDE_*}>: print the on-disk path.
resolve_script() {
  local raw="$1"
  raw="${raw//\$\{CLAUDE_SKILL_DIR\}/$skill_dir}"
  raw="${raw//\$\{CLAUDE_PLUGIN_ROOT\}/$plugin_dir}"
  printf '%s' "$raw"
}

# --- 2a. body invocations: unquoted, granted, present on disk
body_text="$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2' "$skill_md")"
mapfile -t quoted_calls < <(grep -oE 'bash "\$\{CLAUDE_(SKILL_DIR|PLUGIN_ROOT)\}/[A-Za-z0-9_./-]*\.sh"' <<<"$body_text" | sort -u)
if [ "${#quoted_calls[@]}" -eq 0 ]; then
  pass "no quoted bundled-script invocation (a quoted path with a space is not pre-approved)"
else
  fail "quoted bundled-script invocations: ${quoted_calls[*]}"
fi

mapfile -t script_calls < <(grep -oE 'bash \$\{CLAUDE_(SKILL_DIR|PLUGIN_ROOT)\}/[A-Za-z0-9_./-]*\.sh' <<<"$body_text" | sed 's/^bash //' | sort -u)
[ "${#script_calls[@]}" -gt 0 ] && pass "body runs ${#script_calls[@]} bundled scripts" \
  || fail "body runs no bundled script in the anchored form"
for call_path in "${script_calls[@]}"; do
  wanted_rule="Bash(bash ${call_path} *)"
  matched=false
  for rule_text in "${grant_rules[@]}"; do
    [ "$rule_text" = "$wanted_rule" ] && matched=true && break
  done
  if [ "$matched" = true ]; then
    pass "granted: ${call_path}"
  else
    fail "no allowed-tools rule '${wanted_rule}' for the body invocation of ${call_path}"
  fi
  disk_path="$(resolve_script "$call_path")"
  [ -f "$disk_path" ] || fail "body runs ${call_path}, which does not exist at ${disk_path}"
done

# --- 2a'. no command substitution on a bundled-script invocation line (#3577)
# Measured on Claude Code 2.1.322 (`claude -p`, default mode, no allow rules):
# `bash <skill-dir>/scripts/check-plugins.sh --home-dir "$HOME" --project-dir
# "$(pwd)"` was denied ("Quoted text in this command can't be checked before it
# runs") although its anchored grant matched; the same command with a literal
# path ran. The scripts default --project-dir to the working directory.
# A backtick substitution is the same construct, so it is caught too. The
# command ends at the line end in a fenced block, and at the closing delimiter
# of an inline code span (a run of N backticks right before `bash`), so the
# span's own closing backtick is not read as a substitution.
invocation_re='bash \$\{CLAUDE_(SKILL_DIR|PLUGIN_ROOT)\}/[A-Za-z0-9_./-]*\.sh'
span_open_re='(`+)$'
# has_substitution <line>: succeed when the line's bundled-script invocation
# carries a $(…) or backtick command substitution.
has_substitution() {
  local line_text="$1" prefix_text rest_text cmd_text delim=""
  [[ "$line_text" =~ $invocation_re ]] || return 1
  prefix_text="${line_text%%"${BASH_REMATCH[0]}"*}"
  rest_text="${line_text#"$prefix_text"}"
  [[ "${prefix_text% }" =~ $span_open_re ]] && delim="${BASH_REMATCH[1]}"
  if [ -n "$delim" ]; then
    cmd_text="${rest_text%%"$delim"*}"
  else
    cmd_text="$rest_text"
  fi
  [[ "$cmd_text" == *'$('* || "$cmd_text" == *'`'* ]]
}

# Fixtures: the detector must flag both substitution forms in both contexts
# and pass the inline-span shapes the body really uses.
subst_flag=(
  'bash ${CLAUDE_SKILL_DIR}/scripts/check-plugins.sh --project-dir "$(pwd)"'
  'bash ${CLAUDE_SKILL_DIR}/scripts/check-plugins.sh --project-dir "`pwd`"'
  '| x | `bash ${CLAUDE_SKILL_DIR}/scripts/check-plugins.sh --project-dir "$(pwd)"` |'
  '| x | `` bash ${CLAUDE_PLUGIN_ROOT}/skills/s/scripts/fix.sh --project-dir `pwd` `` |'
)
subst_clean=(
  'bash ${CLAUDE_SKILL_DIR}/scripts/check-plugins.sh --home-dir "$HOME"'
  '| `registry` | `bash ${CLAUDE_PLUGIN_ROOT}/skills/s/scripts/fix.sh --home-dir "$HOME"` (append `--dry-run`) |'
  '| x | `` bash ${CLAUDE_SKILL_DIR}/scripts/check-plugins.sh --home-dir "$HOME" `` and `y` |'
)
detector_ok=true
for fixture_line in "${subst_flag[@]}"; do
  has_substitution "$fixture_line" || { detector_ok=false; fail "substitution detector missed: ${fixture_line}"; }
done
for fixture_line in "${subst_clean[@]}"; do
  has_substitution "$fixture_line" && { detector_ok=false; fail "substitution detector flagged a clean line: ${fixture_line}"; }
done
[ "$detector_ok" = true ] && pass "substitution detector flags \$(…) and backticks, fenced and inline, and passes clean spans"

subst_calls=()
while IFS= read -r body_line; do
  has_substitution "$body_line" && subst_calls+=("$body_line")
done <<<"$body_text"
if [ "${#subst_calls[@]}" -eq 0 ]; then
  pass "no bundled-script invocation carries a \$(…) or backtick substitution (it voids the pre-approval)"
else
  fail "bundled-script invocations with a command substitution (not pre-approved):\n  $(printf '%s\n  ' "${subst_calls[@]}")"
fi

# --- 2b. every script grant names an existing script
for rule_text in "${grant_rules[@]}"; do
  [[ "$rule_text" == 'Bash(bash ${CLAUDE_'* ]] || continue
  grant_path="${rule_text#Bash(bash }"
  grant_path="${grant_path% \*)}"
  disk_path="$(resolve_script "$grant_path")"
  [ -f "$disk_path" ] || fail "allowed-tools grants ${grant_path}, which does not exist"
done

# --- 2c. every bundled check-*.sh is run by the body
shopt -s nullglob
for check_path in "${skill_dir}"/scripts/check-*.sh; do
  check_name="$(basename "$check_path")"
  if grep -qF "bash \${CLAUDE_SKILL_DIR}/scripts/${check_name} " <<<"$body_text"; then
    pass "body runs scripts/${check_name}"
  else
    fail "scripts/${check_name} ships beside the skill but the body never runs it"
  fi
done
shopt -u nullglob

# --- 3. no /health:<non-invocable> command references, in any health-plugin
# skill: health-audit and health-agentic-audit cited /health:plugins and each
# other after health-check stopped doing so, so the scan covers every skill dir.
# It also covers every plugin's markdown and health-plugin's hook and skill
# scripts: health-drift-probe.sh printed "/health:audit" as the remediation of
# a SessionStart nudge, and evaluate-skill and feedback-session cited it in
# their When-to-Use tables. Test fixtures (tests/ dirs) and CHANGELOG.md are
# excluded: the first hold the broken text on purpose, the second is history.
doc_files=()
for any_skill_dir in "${plugin_dir}"/skills/*/; do
  for doc_md in "${any_skill_dir}SKILL.md" "${any_skill_dir}REFERENCE.md" "${any_skill_dir}"references/*.md; do
    [ -f "$doc_md" ] && doc_files+=("$doc_md")
  done
done
[ "${#doc_files[@]}" -gt 1 ] || fail "found no health-plugin skill docs to scan under ${plugin_dir}/skills"
repo_root="$(cd "${plugin_dir}/.." && pwd)"
mapfile -t extra_files < <(
  grep -rlE --include='*.md' --exclude='CHANGELOG.md' --exclude-dir=tests \
    --exclude-dir=node_modules --exclude-dir=worktrees '/health:[a-z]' "$repo_root"/*-plugin 2>/dev/null
  grep -rlE --include='*.sh' --exclude-dir=tests '/health:[a-z]' \
    "${plugin_dir}/hooks" "${plugin_dir}/scripts" "${plugin_dir}"/skills/*/scripts 2>/dev/null
)
for extra_file in "${extra_files[@]}"; do
  in_list=false
  for doc_md in "${doc_files[@]}"; do
    [ "$doc_md" = "$extra_file" ] && in_list=true && break
  done
  [ "$in_list" = true ] || doc_files+=("$extra_file")
done
[ -f "${plugin_dir}/hooks/health-drift-probe.sh" ] && grep -qF 'health-drift-probe.sh' <<<"$(printf '%s\n' "${doc_files[@]}")" \
  && pass "health-drift-probe.sh is in the /health: reference scan" \
  || fail "health-drift-probe.sh is not scanned for /health: references (scan scope broke)"
bad_refs=()
for doc_md in "${doc_files[@]}"; do
  doc_text="$(<"$doc_md")"
  while IFS= read -r cmd_name; do
    [ -z "$cmd_name" ] && continue
    target=""
    for candidate in "${plugin_dir}/skills/health-${cmd_name}/SKILL.md" "${plugin_dir}/skills/${cmd_name}/SKILL.md"; do
      [ -f "$candidate" ] && target="$candidate" && break
    done
    if [ -z "$target" ]; then
      bad_refs+=("${doc_md#"${repo_root}"/}: /health:${cmd_name} (no such skill)")
    elif grep -qE '^user-invocable:[[:space:]]*false' "$target"; then
      bad_refs+=("${doc_md#"${repo_root}"/}: /health:${cmd_name} (user-invocable: false)")
    fi
  done < <(grep -oE '/health:[a-z][a-z-]*' <<<"$doc_text" | sed 's#^/health:##' | sort -u)
done
if [ "${#bad_refs[@]}" -eq 0 ]; then
  pass "every /health:<name> reference names a user-invocable skill"
else
  fail "non-invocable /health: command references:\n  $(printf '%s\n  ' "${bad_refs[@]}")"
fi

# --- 4. 1d is the script and the reference documents both rule forms
env_md="${skill_dir}/references/environment-checks.md"
if [ -f "$env_md" ]; then
  env_text="$(<"$env_md")"
  grep -qF 'check-permissions-coverage.sh' <<<"$env_text" \
    && pass "environment-checks.md routes 1d to check-permissions-coverage.sh" \
    || fail "environment-checks.md 1d does not name check-permissions-coverage.sh"
  grep -qF 'Bash(<prefix> *)' <<<"$env_text" && grep -qF 'Bash(<prefix>:*)' <<<"$env_text" \
    && pass "1d reference documents both Bash(<prefix> *) and Bash(<prefix>:*)" \
    || fail "1d reference must document both Bash(<prefix> *) and Bash(<prefix>:*) forms"
  # 1e is a script (#3579): the inline jq snippet had no grant, so it prompted.
  grep -qF 'check-marketplace-enrollment.sh' <<<"$env_text" \
    && pass "environment-checks.md routes 1e to check-marketplace-enrollment.sh" \
    || fail "environment-checks.md 1e does not name check-marketplace-enrollment.sh"
  grep -qE 'MP_KEY=\$\(jq' <<<"$env_text" \
    && fail "environment-checks.md still carries the inline 1e jq snippet (no grant covers it)" \
    || pass "environment-checks.md carries no inline 1e jq snippet"
else
  fail "references/environment-checks.md missing"
fi

# --- 4b. SKILL.md stays under the skill-quality WARN band (#3579)
# #3570 grew the file past 10,000 chars with per-script output-key lists; those
# live in references/ now. Counted as check_skill_size() counts: decoded chars.
skill_chars="$(python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "$skill_md")"
[ "$skill_chars" -le 10000 ] && pass "SKILL.md is ${skill_chars} chars (<= 10,000)" \
  || fail "SKILL.md is ${skill_chars} chars, over the 10,000-char WARN band; move output-key detail to references/"

# --- 5. stack/agentic audits are loaded through the Skill tool
# health-check used to tell the agent to "follow the steps" in
# ${CLAUDE_PLUGIN_ROOT}/skills/health-audit/SKILL.md. Text read with the Read
# tool gets no substitution, so health-audit's `bash ${CLAUDE_SKILL_DIR}/…`
# resolved against the wrong directory, and health-check grants neither that
# script nor `claude plugin list`. Loading the skill applies both.
sibling_reads="$(grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/skills/[a-z-]+/SKILL\.md' <<<"$body_text" | sort -u)"
[ -z "$sibling_reads" ] && pass "body never routes through a sibling SKILL.md path" \
  || fail "body routes through a sibling SKILL.md (Read gets no \${CLAUDE_SKILL_DIR} substitution): ${sibling_reads//$'\n'/ }"
for audit_skill in health-plugin:health-audit health-plugin:health-agentic-audit; do
  grep -qE "Skill tool[^|]*\`${audit_skill}\`|\`${audit_skill}\`[^|]*Skill tool" <<<"$body_text" \
    && pass "body invokes ${audit_skill} through the Skill tool" \
    || fail "body does not invoke ${audit_skill} through the Skill tool"
done

# --- 6. plugin docs and health-check references agree with the skills
# Each of these reverted to its pre-fix text without failing any test:
# README's Permission Debugging bullets (a three-file hierarchy, "Shell operator
# protections"), flow.md's stack --fix node (--fix enables and removes keys and
# installs nothing), audit-scopes.md's registry-backed usage inventory, and
# command-reference.md's bare `bash check-usage.sh` (no grant matches it).
assert_doc() {  # <label> <file> forbid|require <ERE>
  local label="$1" doc_file="$2" mode="$3" pattern="$4"
  if [ ! -f "$doc_file" ]; then
    fail "${label}: ${doc_file} missing"
  elif grep -qE -- "$pattern" "$doc_file"; then
    [ "$mode" = require ] && pass "$label" || fail "${label}: ${doc_file#"${plugin_dir}"/} matches /${pattern}/"
  else
    [ "$mode" = forbid ] && pass "$label" || fail "${label}: ${doc_file#"${plugin_dir}"/} lacks /${pattern}/"
  fi
}
readme_md="${plugin_dir}/README.md"
flow_md="${plugin_dir}/docs/flow.md"
scopes_md="${skill_dir}/references/audit-scopes.md"
cmdref_md="${skill_dir}/references/command-reference.md"
assert_doc "README: no three-file settings hierarchy" "$readme_md" forbid 'user → project → local'
assert_doc "README: no 'Shell operator protections' bullet" "$readme_md" forbid 'Shell operator protections'
assert_doc "README: settings precedence names managed" "$readme_md" require 'managed → `--settings`'
assert_doc "flow.md: stack --fix installs nothing" "$flow_md" forbid 'install missing'
assert_doc "flow.md: stack --fix removes keys" "$flow_md" require 'health-audit --fix<br/>enable relevant<br/>remove irrelevant keys'
assert_doc "flow.md: agentic --fix adds no optimisation tables" "$flow_md" forbid 'add optimisation tables'
assert_doc "audit-scopes.md: usage inventory is the registry" "$scopes_md" require 'installed_plugins\.json'
assert_doc "audit-scopes.md: usage honours defaultEnabled" "$scopes_md" require 'defaultEnabled: false'
assert_doc "command-reference.md: no unanchored bash check-*.sh" "$cmdref_md" forbid '`bash check-[a-z-]+\.sh'
assert_doc "command-reference.md: permissions coverage row" "$cmdref_md" require 'check-permissions-coverage\.sh'

# --- 7. local parity: the pre-commit hook reaches every health-plugin test
# The hook used to trigger only on skill markdown and scripts/tests, and its
# --only glob skipped skills/*/scripts/tests, so an edit to check-hooks.sh,
# check-usage.sh, check-permissions-coverage.sh or enabled-plugins.sh ran none
# of their suites locally while CI's test-skill-scripts.yml did.
precommit_yaml="${repo_root}/.pre-commit-config.yaml"
if [ -f "$precommit_yaml" ]; then
  hook_block="$(awk '/- id: test-health-plugin-skill-guards$/{f=1; print; next} f && /- id: /{exit} f{print}' "$precommit_yaml")"
  hook_files_re="$(sed -n "s/^[[:space:]]*files: '\(.*\)'$/\1/p" <<<"$hook_block" | head -n1)"
  hook_entry="$(sed -n 's/^[[:space:]]*entry: //p' <<<"$hook_block" | head -n1)"
  if [ -z "$hook_files_re" ] || [ -z "$hook_entry" ]; then
    fail "pre-commit hook test-health-plugin-skill-guards not found or has no files:/entry:"
  else
    mapfile -t hook_globs < <(grep -oE -- "--only '[^']+'" <<<"$hook_entry" | sed -E "s/^--only '//; s/'$//")
    unreached=()
    shopt -s nullglob
    for watched in "${plugin_dir}"/skills/*/scripts/*.sh "${plugin_dir}"/skills/*/scripts/tests/test-*.sh \
                   "${plugin_dir}"/scripts/tests/test-*.sh "${plugin_dir}"/skills/*/SKILL.md; do
      rel_path="${watched#"${repo_root}"/}"
      grep -qE -- "$hook_files_re" <<<"$rel_path" || unreached+=("files: misses ${rel_path}")
    done
    for test_path in "${plugin_dir}"/skills/*/scripts/tests/test-*.sh "${plugin_dir}"/scripts/tests/test-*.sh; do
      rel_path="${test_path#"${repo_root}"/}"
      globbed=false
      for g in "${hook_globs[@]}"; do
        # shellcheck disable=SC2053 # unquoted RHS is the glob on purpose
        [[ "$rel_path" == $g ]] && globbed=true && break
      done
      [ "$globbed" = true ] || unreached+=("--only misses ${rel_path}")
    done
    shopt -u nullglob
    [ "${#unreached[@]}" -eq 0 ] && pass "pre-commit hook watches and runs every health-plugin test" \
      || fail "pre-commit hook test-health-plugin-skill-guards does not reach:\n  $(printf '%s\n  ' "${unreached[@]}")"
  fi
fi

echo "PASSED=${pass_count} FAILED=${fail_count}"
[ "$fail_count" -eq 0 ]

#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # SC2016: literal ${CLAUDE_SKILL_DIR} and backticks are the text under test
# test-registry-skills.sh -- semantic guard for the two plugin-registry skills:
#   health-plugin/skills/health-plugins/SKILL.md
#   health-plugin/skills/plugin-registry/SKILL.md (+ REFERENCE.md)
#
# Invariants (each one was broken before the 2026-11-10 fix):
#   1. NARROW GRANTS. allowed-tools carries no bare `Bash` and no
#      `Bash(bash *)` / `Bash(sh *)`. Every `Bash(bash ${CLAUDE_SKILL_DIR}/<p> *)`
#      rule names a script that exists, and the body runs it with exactly that
#      spelling. On Claude Code 2.1.322 a quoted path matched the unquoted
#      rule only while the path held no space; with a space it was not
#      pre-approved, and neither was a quoted rule (#3577), so quoting buys
#      nothing. Rule: .claude/rules/agentic-permissions.md
#      § Skill allowed-tools is a pre-approval.
#   2. NO HIDDEN COMMANDS. A `/health:<name>` citation must resolve to a
#      health-plugin skill that is user-invocable; a `user-invocable: false`
#      skill is hidden from the / menu, so citing it as a command sends the
#      user to nothing. Both SKILL.md files name the user-facing path,
#      `/health:check --scope=registry`.
#   3. CLI AND SCRIPT FIRST. plugin-registry routes registry changes through
#      `claude plugin install|uninstall` and fix-registry.sh, never "write the
#      JSON with the Write tool"; hand-editing survives only under a
#      "Last resort" heading that starts with a `cp` backup. health-plugins
#      installs with `claude plugin install ... --scope`, not "via the
#      Claude Code UI". Every `--scope <value>` is one the CLI accepts.
#      In plugin-registry/REFERENCE.md, a paragraph telling the reader to
#      change the registry with jq, by hand or with the Write tool must point
#      at SKILL.md § Last resort.
#   4. ONE REFERENCE. health-plugins carries no registry-structure or #14202
#      background section and names health-plugin:plugin-registry for them
#      (with both, config-drift rated the pair 93% similar).
#
# Usage:
#   bash test-registry-skills.sh                    # run the suite
#   bash test-registry-skills.sh --check-root DIR   # print violations for a tree
#                                                   # laid out like the repo root
#                                                   # (used to replay old text)
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"

HP_REL="health-plugin/skills/health-plugins/SKILL.md"
PR_REL="health-plugin/skills/plugin-registry/SKILL.md"
PRREF_REL="health-plugin/skills/plugin-registry/REFERENCE.md"
VALID_SCOPES="user project local managed"

frontmatter() { awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f {print}' "$1"; }
# Body after the frontmatter; a file with no frontmatter (REFERENCE.md) is all body.
body() { awk 'NR==1 && /^---$/ {f=1; next} NR==1 {b=1} f && /^---$/ {f=0; b=1; next} b {print}' "$1"; }
fm_field() { frontmatter "$1" | grep -m1 "^$2:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r'; }

# Emits one "TYPE<TAB>FILE<TAB>DETAIL" line per violation found under $1.
check_tree() {
  local root="$1" rel file skill_dir tools tok script_rel bdy name target inv
  for rel in "$HP_REL" "$PR_REL"; do
    file="${root}/${rel}"
    [ -f "$file" ] || { printf 'missing_file\t%s\t-\n' "$rel"; continue; }
    skill_dir="$(dirname "$file")"
    tools="$(fm_field "$file" allowed-tools)"
    bdy="$(body "$file")"

    # Invariant 1: narrow grants.
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      if [ "$tok" = "Bash" ]; then
        printf 'bare_bash\t%s\t%s\n' "$rel" "$tok"
      elif [[ "$tok" =~ ^Bash\((bash|sh)\ \*\)$ ]]; then
        printf 'broad_shell\t%s\t%s\n' "$rel" "$tok"
      elif [[ "$tok" =~ ^Bash\(bash\ \$\{CLAUDE_SKILL_DIR\}/([^\ ]+)\ \*\)$ ]]; then
        script_rel="${BASH_REMATCH[1]}"
        [ -f "${skill_dir}/${script_rel}" ] || printf 'missing_script\t%s\t%s\n' "$rel" "$script_rel"
        grep -qF "bash \${CLAUDE_SKILL_DIR}/${script_rel}" <<<"$bdy" \
          || printf 'rule_not_invoked\t%s\t%s\n' "$rel" "$script_rel"
      fi
    done < <(grep -oE 'Bash(\([^)]*\))?' <<<"$tools")
    if grep -qF 'bash "${CLAUDE_SKILL_DIR}' <<<"$bdy"; then
      printf 'quoted_invocation\t%s\t%s\n' "$rel" 'bash "${CLAUDE_SKILL_DIR}..."'
    fi

    # Invariant 2 (user-facing path): both skills name it.
    grep -qF '/health:check --scope=registry' <<<"$bdy" \
      || printf 'missing_user_path\t%s\t/health:check --scope=registry\n' "$rel"
  done

  # Invariant 2: every /health:<name> resolves to a user-invocable skill.
  for rel in "$HP_REL" "$PR_REL" "$PRREF_REL"; do
    file="${root}/${rel}"
    [ -f "$file" ] || continue
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      target=""
      for cand in "health-${name}" "${name}"; do
        if [ -f "${root}/health-plugin/skills/${cand}/SKILL.md" ]; then
          target="${root}/health-plugin/skills/${cand}/SKILL.md"; break
        fi
      done
      if [ -z "$target" ]; then
        printf 'unknown_command\t%s\t/health:%s\n' "$rel" "$name"; continue
      fi
      inv="$(fm_field "$target" user-invocable)"
      [ "$inv" = "false" ] && printf 'hidden_command\t%s\t/health:%s\n' "$rel" "$name"
    done < <(body "$file" | grep -oE '/health:[a-z][a-z-]*' | sed 's#^/health:##' | sort -u)
  done

  # Invariant 3: CLI and script first; manual edit only as a backed-up last resort.
  file="${root}/${PR_REL}"
  if [ -f "$file" ]; then
    bdy="$(body "$file")"
    grep -qiE 'with (the )?Write tool|Write tool to' <<<"$bdy" \
      && printf 'write_tool_edit\t%s\tWrite tool\n' "$PR_REL"
    grep -qE '(^|[ ,])Write(,|$)' <<<"$(fm_field "$file" allowed-tools)" \
      && printf 'write_grant\t%s\tWrite\n' "$PR_REL"
    for needle in 'fix-registry.sh' 'claude plugin install' 'claude plugin uninstall'; do
      grep -qF "$needle" <<<"$bdy" || printf 'missing_cli_route\t%s\t%s\n' "$PR_REL" "$needle"
    done
    local last_resort
    last_resort="$(awk '/^#+ Last resort/ {f=1; next} f && /^#{1,3} / {exit} f {print}' <<<"$bdy")"
    if [ -z "$last_resort" ]; then
      printf 'missing_last_resort\t%s\tLast resort heading\n' "$PR_REL"
    elif ! grep -qF 'cp ~/.claude/plugins/installed_plugins.json' <<<"$last_resort"; then
      printf 'missing_backup\t%s\tcp backup in Last resort\n' "$PR_REL"
    fi
  fi
  # Invariant 3 in REFERENCE.md: a paragraph that tells the reader to change the
  # registry with jq, by hand or with the Write tool must point at SKILL.md
  # § Last resort, which carries the backup and the order of operations.
  # (REFERENCE.md once said "drop the entry from the registry with `jq` after
  # backing the file up" with no pointer, and no test failed.)
  file="${root}/${PRREF_REL}"
  if [ -f "$file" ]; then
    local para
    while IFS= read -r para; do
      [ -n "$para" ] || continue
      grep -qF '§ Last resort' <<<"$para" && continue
      if grep -qiE '(drop|remove|delete|edit|rewrite|change)[^.]*(entry|entries|registry|installed_plugins\.json)[^.]*(with `?jq`?|by hand|with (the )?Write tool)|jq [^|`]*> *[^ `]*installed_plugins\.json|mv [^ `]+ [^ `]*installed_plugins\.json|hand-edit (the |an? )?(registry|entry|installed_plugins\.json)' <<<"$para"; then
        printf 'registry_hand_edit\t%s\t%s\n' "$PRREF_REL" "${para:0:120}"
      fi
    done < <(body "$file" | awk 'BEGIN{RS=""} {gsub(/\n/, " "); print}')
  fi

  file="${root}/${HP_REL}"
  if [ -f "$file" ]; then
    bdy="$(body "$file")"
    grep -qiF 'Claude Code UI' <<<"$bdy" && printf 'ui_install\t%s\tClaude Code UI\n' "$HP_REL"
    grep -qE 'claude plugin install [^`]*--scope' <<<"$bdy" \
      || printf 'missing_cli_install\t%s\tclaude plugin install --scope\n' "$HP_REL"

    # Invariant 4: ONE REFERENCE. health-plugins runs the scripts; the registry
    # structure and the #14202 background live in plugin-registry. When both
    # skills carried them, config-drift rated the pair 93% similar (threshold
    # 0.91) and the health-plugin config-drift probe surfaced a new WARN.
    grep -qE '^#+ Background' <<<"$bdy" && printf 'duplicated_reference\t%s\tBackground section\n' "$HP_REL"
    grep -qF 'github.com/anthropics/claude-code/issues/14202' <<<"$bdy" \
      && printf 'duplicated_reference\t%s\t#14202 issue link\n' "$HP_REL"
    grep -qE '"(installPath|projectPath|scope)"[[:space:]]*:' <<<"$bdy" \
      && printf 'duplicated_reference\t%s\tregistry JSON structure\n' "$HP_REL"
    grep -qF 'health-plugin:plugin-registry' <<<"$bdy" \
      || printf 'missing_reference_pointer\t%s\thealth-plugin:plugin-registry\n' "$HP_REL"
  fi

  # Invariant 3: every --scope value is one the CLI accepts.
  for rel in "$HP_REL" "$PR_REL" "$PRREF_REL"; do
    file="${root}/${rel}"
    [ -f "$file" ] || continue
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      case " $VALID_SCOPES " in
        *" $tok "*) ;;
        *) printf 'bad_scope\t%s\t--scope %s\n' "$rel" "$tok" ;;
      esac
    done < <(grep -oE -- '--scope [a-z<]+' "$file" | awk '{print $2}' | grep -v '^<' | sort -u)
  done
}

if [ "${1:-}" = "--check-root" ]; then
  out="$(check_tree "${2:?--check-root needs a directory}")"
  count=0
  [ -n "$out" ] && count="$(grep -c . <<<"$out")"
  echo "=== REGISTRY SKILLS CHECK ==="
  if [ "$count" -eq 0 ]; then
    echo "STATUS=OK"
  else
    echo "STATUS=ERROR"
    first="$(head -n1 <<<"$out")"
    reason="$(cut -f1 <<<"$first"): $(cut -f2 <<<"$first") $(cut -f3 <<<"$first")"
    [ "$count" -gt 1 ] && reason="${reason} (+$((count - 1)) more)"
    echo "REASON=${reason:0:200}"
  fi
  echo "ISSUE_COUNT=${count}"
  if [ "$count" -gt 0 ]; then
    echo "ISSUES:"
    while IFS=$'\t' read -r v_type v_file v_detail; do
      echo "  - SEVERITY=ERROR TYPE=${v_type} FILE=${v_file} MSG=${v_detail}"
    done <<<"$out"
  fi
  echo "=== END REGISTRY SKILLS CHECK ==="
  [ "$count" -eq 0 ]
  exit $?
fi

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }

sandbox="$(mktemp -d)"
[ -n "$sandbox" ] && [ -d "$sandbox" ] || { echo "FAIL: mktemp -d returned nothing"; exit 1; }
trap 'rm -rf "$sandbox"' EXIT

# Fresh copy of the health-plugin skills tree for one mutation case.
fresh_tree() {
  local dest="${sandbox}/$1"
  mkdir -p "${dest}/health-plugin"
  cp -R "${repo_root}/health-plugin/skills" "${dest}/health-plugin/skills"
  printf '%s' "$dest"
}

# expect_violation <case> <type> <file-rel> <perl -0pi substitution>
expect_violation() {
  local case_name="$1" want="$2" rel="$3" perl_expr="$4" tree out
  tree="$(fresh_tree "$case_name")"
  perl -0pi -e "$perl_expr" "${tree}/${rel}"
  if cmp -s "${tree}/${rel}" "${repo_root}/${rel}"; then
    bad "${case_name}: mutation did not change ${rel} (fixture is stale)"
    return
  fi
  out="$(check_tree "$tree")"
  if grep -q "^${want}"$'\t' <<<"$out"; then
    ok "${case_name}: flags ${want}"
  else
    bad "${case_name}: expected ${want}, got: ${out:-<none>}"
  fi
}

# --- Case 0: the shipped tree is clean ------------------------------------
out="$(check_tree "$repo_root")"
if [ -z "$out" ]; then
  ok "shipped skills satisfy all invariants"
else
  bad "shipped skills have violations:"$'\n'"$out"
fi

# --- Invariant 1 ------------------------------------------------------------
expect_violation broad_shell broad_shell "$HP_REL" \
  's/^allowed-tools: .*$/allowed-tools: Bash(bash *), Read, Write, Edit/m'
expect_violation bare_bash bare_bash "$PR_REL" \
  's/^allowed-tools: /allowed-tools: Bash, /m'
# Body call sites only (a code-block line and a table cell); the frontmatter rule
# keeps its spelling, so the rule no longer matches what the body runs.
expect_violation quoted_call rule_not_invoked "$HP_REL" \
  's/(^|`)bash \$\{CLAUDE_SKILL_DIR\}\/scripts\/check-registry\.sh/$1bash "\$\{CLAUDE_SKILL_DIR\}\/scripts\/check-registry.sh"/mg'
expect_violation missing_script missing_script "$HP_REL" \
  's/scripts\/fix-registry\.sh \*\)/scripts\/no-such-fix.sh *)/'

# --- Invariant 2 ------------------------------------------------------------
expect_violation hidden_cmd hidden_command "$PR_REL" \
  's/\z/\nRun `\/health:plugins --fix` to repair.\n/'
expect_violation hidden_cmd_ref hidden_command "$PRREF_REL" \
  's/\z/\nSee `\/health:settings-configuration`.\n/'
expect_violation no_user_path missing_user_path "$HP_REL" \
  's/\/health:check --scope=registry/\/health:check/g'

# --- Invariant 3 ------------------------------------------------------------
expect_violation write_tool write_tool_edit "$PR_REL" \
  's/\z/\n4. Write the updated JSON with the Write tool\n/'
expect_violation write_grant write_grant "$PR_REL" \
  's/Read, Edit,/Read, Write, Edit,/'
expect_violation no_fix_script missing_cli_route "$PR_REL" \
  's/fix-registry\.sh/fix.sh/g'
expect_violation no_backup missing_backup "$PR_REL" \
  's/cp ~\/\.claude\/plugins\/installed_plugins\.json ~\/\.claude\/plugins\/installed_plugins\.json\.backup/echo skip/'
expect_violation ui_install ui_install "$HP_REL" \
  's/\z/\n2. Remind the user to run `\/plugin install` via the Claude Code UI.\n/'
expect_violation bad_scope bad_scope "$PR_REL" \
  's/--scope local`/--scope global`/'
# --- Invariant 4 ------------------------------------------------------------
expect_violation hp_background duplicated_reference "$HP_REL" \
  's/\n## Parameters/\n## Background: Issue #14202\n\n[anthropics\/claude-code#14202](https:\/\/github.com\/anthropics\/claude-code\/issues\/14202) is open.\n\n## Parameters/'
expect_violation hp_structure duplicated_reference "$HP_REL" \
  's/\z/\n```json\n{"scope": "project", "projectPath": "\/p", "installPath": "\/i"}\n```\n/'
expect_violation hp_no_pointer missing_reference_pointer "$HP_REL" \
  's/health-plugin:plugin-registry/the reference skill/g'

# The pre-fix REFERENCE.md sentence, verbatim.
expect_violation ref_jq_edit registry_hand_edit "$PRREF_REL" \
  's/\z/\nIf the plugin was installed for a project that no longer exists, there is no\ndirectory to run the command from; drop the entry from the registry with `jq`\nafter backing the file up.\n/'
expect_violation ref_jq_redirect registry_hand_edit "$PRREF_REL" \
  's/\z/\n```bash\njq "del(.plugins[\\"x\\"])" r.json > ~\/.claude\/plugins\/installed_plugins.json\n```\n/'

# --- --check-root contract --------------------------------------------------
cr_out="$(bash "${BASH_SOURCE[0]}" --check-root "$repo_root")"
cr_exit=$?
if [ "$cr_exit" -eq 0 ] && grep -q '^STATUS=OK$' <<<"$cr_out" && grep -q '^ISSUE_COUNT=0$' <<<"$cr_out"; then
  ok "--check-root reports STATUS=OK on the shipped tree"
else
  bad "--check-root on shipped tree: exit=${cr_exit} out=${cr_out}"
fi
tree="$(fresh_tree check_root_bad)"
perl -0pi -e 's/^allowed-tools: /allowed-tools: Bash, /m' "${tree}/${PR_REL}"
cr_out="$(bash "${BASH_SOURCE[0]}" --check-root "$tree")"
cr_exit=$?
if [ "$cr_exit" -eq 1 ] && grep -q '^STATUS=ERROR$' <<<"$cr_out" && grep -q '^REASON=bare_bash: ' <<<"$cr_out"; then
  ok "--check-root reports STATUS=ERROR with REASON on a regressed tree"
else
  bad "--check-root on regressed tree: exit=${cr_exit} out=${cr_out}"
fi

echo
echo "PASSED=${pass} FAILED=${fail}"
[ "$fail" -eq 0 ]

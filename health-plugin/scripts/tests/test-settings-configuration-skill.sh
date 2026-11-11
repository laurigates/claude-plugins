#!/usr/bin/env bash
# test-settings-configuration-skill.sh — semantic guard for
# health-plugin/skills/settings-configuration (SKILL.md + REFERENCE.md), and
# for the correctness subset of it in configure-plugin/skills/
# claude-security-settings (#3572).
#
# The skill went stale for nine months (reviewed 2026-02-04) and shipped false
# claims about Claude Code's settings and permission system. This suite pins
# the invariants a later bulk edit must not undo:
#
#   frontmatter         SKILL.md opens with frontmatter carrying name,
#                       allowed-tools and a description with "Use when"
#   bare_bash_grant     allowed-tools never grants a bare `Bash`
#   managed_missing     managed settings (managed-settings.json) and the
#                       `--settings` command-line level are documented
#   precedence_order    the precedence table lists Managed > Command line >
#                       Project local > Shared project > User, in that order
#   ask_tier_missing    the `ask` tier and the deny -> ask -> allow order
#   false_compound_claim  the pre-fix claim that a wildcard never matches a
#                       command containing && or | is absent
#   subcommand_missing  compound commands are matched per subcommand
#   modes_missing       every permission mode is named
#   auto_drop_missing   auto mode dropping broad allow rules is documented
#   edit_covers_missing Edit(path) covering Write/NotebookEdit is documented
#   param_rule_missing  Tool(param:value) rules are documented
#   mcp_scope_missing   the mcp__<server>__* server-scoped form is documented
#   unknown_skill_ref   every referenced plugin:skill (and "(use X skill)")
#                       resolves to a SKILL.md in this repo
#   cat_pipe_jq         no `cat <file> | jq` example in SKILL.md or REFERENCE.md
#   dead_reference_link a REFERENCE.md link resolves, and each
#                       "REFERENCE.md § <Heading>" names a real heading
#
# Each invariant is proven to FAIL: a mutant of the live skill breaks exactly
# that invariant, and an embedded copy of the pre-fix (2026-07-18) text must
# trip the five defects it shipped with.
#
# The "core" scope (claude-security-settings) keeps every correctness
# invariant and drops the completeness group a hardening skill defers to
# settings-configuration for: ask_tier_missing, modes_missing,
# auto_drop_missing, edit_covers_missing, param_rule_missing,
# mcp_scope_missing. ask_tier_missing stays out until #3583 settles the
# `:ask` suffix the hardening skill documents.
#
# Usage:
#   test-settings-configuration-skill.sh                 run the suite
#   test-settings-configuration-skill.sh --check <dir> [core]
#                                                        check one skill dir
#                                                        (prints VIOLATION=…,
#                                                        exit 1 if any)

# SC2015: `a && b || c` assertions are deliberate. SC2016: the backticks in
# single-quoted patterns and fixtures are literal markdown, not expansions.
# shellcheck disable=SC2015,SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
LIVE_DIR="${REPO_ROOT}/health-plugin/skills/settings-configuration"
SECURITY_DIR="${REPO_ROOT}/configure-plugin/skills/claude-security-settings"

# --- checker ---------------------------------------------------------------

# Print the frontmatter block (between the first two `---` lines).
frontmatter_of() {
  awk 'NR==1 && $0!="---"{exit} NR==1{next} $0=="---"{exit} {print}' "$1"
}

# Print the body (everything after the closing frontmatter `---`).
body_of() {
  awk 'NR==1 && $0=="---"{fm=1; next} fm && $0=="---"{fm=0; done=1; next} !fm{print}' "$1"
}

# Resolve `<plugin>:<skill>` to a SKILL.md in REPO_ROOT. Accepts the
# directory as `<skill>` or as `<namespace>-<skill>` (skill-naming.md).
skill_exists() {
  local ref="$1" plugin skill ns
  plugin="${ref%%:*}"
  skill="${ref#*:}"
  ns="${plugin%-plugin}"
  [ -f "${REPO_ROOT}/${plugin}/skills/${skill}/SKILL.md" ] ||
    [ -f "${REPO_ROOT}/${plugin}/skills/${ns}-${skill}/SKILL.md" ]
}

# Resolve a bare skill name against every plugin's skills/ directory.
# Searched from inside REPO_ROOT with relative paths: REPO_ROOT may itself be
# an agent worktree under .claude/worktrees/, and an absolute-path prune would
# then prune the whole scan root and resolve nothing.
bare_skill_exists() {
  local found
  found="$(cd "$REPO_ROOT" && find . -maxdepth 4 -path './.claude/worktrees' -prune -o \
    -path "./*-plugin/skills/$1/SKILL.md" -print 2>/dev/null | head -1)"
  [ -n "$found" ]
}

# check_skill <dir> [full|core] — print one `VIOLATION=<type> DETAIL=<text>`
# line per broken invariant; return the number of violations (0 = clean).
check_skill() {
  local dir="$1" skill_md="$1/SKILL.md" ref_md="$1/REFERENCE.md"
  local scope="${2:-full}"
  local fm body all count=0

  if [ ! -f "$skill_md" ]; then
    echo "VIOLATION=frontmatter DETAIL=no SKILL.md in $dir"
    return 1
  fi

  fm="$(frontmatter_of "$skill_md")"
  body="$(body_of "$skill_md")"
  all="$body"
  [ -f "$ref_md" ] && all="${all}"$'\n'"$(cat "$ref_md")"

  v() { echo "VIOLATION=$1 DETAIL=$2"; count=$((count + 1)); }

  # frontmatter
  grep -qE '^name:[[:space:]]*[a-z0-9-]+' <<<"$fm" || v frontmatter "missing name"
  grep -qE '^description:.*Use when' <<<"$fm" || v frontmatter "description lacks 'Use when'"
  grep -qE '^allowed-tools:' <<<"$fm" || v frontmatter "missing allowed-tools"

  # bare_bash_grant: split allowed-tools on commas, look for an item == Bash
  local tools item
  tools="$(grep -m1 -E '^allowed-tools:' <<<"$fm" | sed 's/^allowed-tools:[[:space:]]*//')"
  local -a tool_items=()
  IFS=',' read -r -a tool_items <<<"$tools"
  for item in "${tool_items[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [ "$item" = "Bash" ] && v bare_bash_grant "allowed-tools grants bare Bash"
  done

  # managed_missing
  grep -qF 'managed-settings.json' <<<"$body" || v managed_missing "managed-settings.json not named"
  grep -qF -- '--settings' <<<"$body" || v managed_missing "--settings level not named"

  # precedence_order: first line number of each level label, must increase
  local prev=0 label ln
  for label in '**Managed**' '**Command line**' '**Project local**' '**Shared project**' '**User**'; do
    ln="$(grep -nF -m1 "$label" <<<"$body" | cut -d: -f1)"
    if [ -z "$ln" ]; then
      v precedence_order "level ${label} missing"
      break
    fi
    if [ "$ln" -le "$prev" ]; then
      v precedence_order "level ${label} out of order"
      break
    fi
    prev="$ln"
  done

  # ask_tier_missing
  if [ "$scope" = full ]; then
    grep -qE '"ask"[[:space:]]*:' <<<"$body" || v ask_tier_missing "no \"ask\" rule example"
    grep -qiE 'deny, then ask, then allow' <<<"$body" || v ask_tier_missing "deny -> ask -> allow order not stated"
  fi

  # false_compound_claim (the pre-fix wording and close paraphrases)
  if grep -qiE "(permission )?wildcards? (won't|will not|do not|don't|never|cannot|can't) match" <<<"$all"; then
    v false_compound_claim "claims wildcards never match commands with shell operators"
  fi

  # false_local_trust_claim: an untracked local file skips trust only in the
  # configuration home; elsewhere Claude Code runs its git check only once the
  # folder (or a parent) is trusted, or in -p (permissions docs, "When your
  # local settings file needs trust").
  if grep -qiE '(local|settings\.local\.json)`?[^.|]*skips? the trust (step|dialog|prompt)' <<<"$all"; then
    v false_local_trust_claim "claims an untracked local settings file skips the trust step everywhere"
  fi

  # false_p_trust_dialog: -p never shows the trust dialog, so "accept the
  # trust dialog" is no fix for a -p run.
  if grep -iE '`-p`' <<<"$all" | grep -qiE 'accept (the )?(workspace )?trust dialog'; then
    v false_p_trust_dialog "tells a -p run to accept a trust dialog it never shows"
  fi

  # subcommand_missing
  grep -qiE '(every|each) subcommand' <<<"$body" || v subcommand_missing "per-subcommand matching not stated"

  if [ "$scope" = full ]; then
  # modes_missing
  local mode
  for mode in acceptEdits plan auto dontAsk bypassPermissions; do
    grep -qF "\`${mode}\`" <<<"$body" || v modes_missing "mode ${mode} not named"
  done

  # auto_drop_missing
  grep -qiE 'auto mode drops broad allow rules|drops broad allow rules' <<<"$body" ||
    v auto_drop_missing "auto mode dropping broad allow rules not stated"

  # edit_covers_missing
  if ! { grep -qF 'Edit(path)' <<<"$body" && grep -qF 'NotebookEdit' <<<"$body"; }; then
    v edit_covers_missing "Edit(path) covering Write/NotebookEdit not stated"
  fi

  # param_rule_missing
  grep -qF 'Tool(param:value)' <<<"$body" || v param_rule_missing "Tool(param:value) not documented"

  # mcp_scope_missing
  grep -qE 'mcp__[A-Za-z0-9_<>-]+__\*' <<<"$body" || v mcp_scope_missing "no mcp__<server>__* form"
  fi

  # unknown_skill_ref
  local ref
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    skill_exists "$ref" || v unknown_skill_ref "${ref} resolves to no SKILL.md"
  done < <(grep -oE '`[a-z0-9-]+-plugin:[a-z0-9-]+`' <<<"$all" | tr -d '`' | sort -u)
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    bare_skill_exists "$ref" || v unknown_skill_ref "(use ${ref} skill) resolves to no SKILL.md"
  done < <(grep -oiE '\(use [a-z0-9-]+ skill\)' <<<"$all" | sed -E 's/^\([Uu]se ([a-z0-9-]+) skill\)$/\1/' | sort -u)

  # cat_pipe_jq
  grep -qE '(^|[^a-z])cat [^|`]*\|[[:space:]]*jq' <<<"$all" && v cat_pipe_jq "cat <file> | jq example"

  # dead_reference_link
  if grep -qF '(REFERENCE.md' <<<"$body"; then
    if [ ! -f "$ref_md" ]; then
      v dead_reference_link "SKILL.md links REFERENCE.md, which does not exist"
    else
      local heading
      while IFS= read -r heading; do
        [ -n "$heading" ] || continue
        grep -qxF "## ${heading}" "$ref_md" || v dead_reference_link "REFERENCE.md has no heading '${heading}'"
      done < <(grep -oE 'REFERENCE\.md § [^]]+\]' <<<"$body" | sed -E 's/^REFERENCE\.md § (.*)\]$/\1/' | sort -u)
    fi
  fi

  unset -f v
  return "$count"
}

if [ "${1:-}" = "--check" ]; then
  [ -n "${2:-}" ] || { echo "usage: $0 --check <skill-dir> [core]" >&2; exit 2; }
  check_skill "$2" "${3:-full}"
  exit $(( $? > 0 ? 1 : 0 ))
fi

# --- suite -----------------------------------------------------------------

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

SANDBOX="$(mktemp -d)"
if [ -z "$SANDBOX" ] || [ ! -d "$SANDBOX" ]; then
  echo "FAIL: mktemp -d returned no directory" >&2
  exit 1
fi
trap 'rm -rf "$SANDBOX"' EXIT
# Nothing in this suite reads HOME; pointing it at the sandbox makes any
# accidental read hermetic.
export HOME="${SANDBOX}/home"
mkdir -p "$HOME"

# expect_clean <label> <dir> [scope]
expect_clean() {
  local out
  out="$(check_skill "$2" "${3:-full}")"
  if [ -z "$out" ]; then
    pass "$1"
  else
    fail "$1 — unexpected violations:"$'\n'"$out"
  fi
}

# expect_violation <label> <dir> <type> [scope]
expect_violation() {
  local out
  out="$(check_skill "$2" "${4:-full}")"
  if grep -qE "^VIOLATION=$3( |$)" <<<"$out"; then
    pass "$1"
  else
    fail "$1 — expected VIOLATION=$3, got:"$'\n'"${out:-<none>}"
  fi
}

# make_mutant <name> — copy the live skill into the sandbox, print its dir
make_mutant() {
  local d="${SANDBOX}/$1"
  mkdir -p "$d"
  cp "${LIVE_DIR}/SKILL.md" "$d/SKILL.md"
  [ -f "${LIVE_DIR}/REFERENCE.md" ] && cp "${LIVE_DIR}/REFERENCE.md" "$d/REFERENCE.md"
  echo "$d"
}

# delete_lines <file> <ERE> — drop every line matching ERE (no sed -i)
delete_lines() {
  grep -vE "$2" "$1" > "$1.tmp"
  mv "$1.tmp" "$1"
}

# 1. The live skill satisfies every invariant.
expect_clean "live skill is clean" "$LIVE_DIR"

# 2. One mutant per invariant, each breaking exactly that invariant.
d="$(make_mutant bare-bash)"
awk '/^allowed-tools:/{print "allowed-tools: Bash, Read, Write, Edit, Glob, Grep"; next} {print}' \
  "$d/SKILL.md" > "$d/x" && mv "$d/x" "$d/SKILL.md"
expect_violation "bare Bash grant is caught" "$d" bare_bash_grant

d="$(make_mutant no-managed)"
delete_lines "$d/SKILL.md" 'managed-settings\.json'
expect_violation "missing managed settings is caught" "$d" managed_missing

d="$(make_mutant no-cli-level)"
delete_lines "$d/SKILL.md" '\-\-settings'
expect_violation "missing --settings level is caught" "$d" managed_missing

d="$(make_mutant reordered)"
awk '/^\| 1 \| \*\*Managed\*\*/{held=$0; next} {print} /^\| 5 \| \*\*User\*\*/{print held}' \
  "$d/SKILL.md" > "$d/x" && mv "$d/x" "$d/SKILL.md"
expect_violation "managed listed lowest is caught" "$d" precedence_order

d="$(make_mutant no-ask)"
delete_lines "$d/SKILL.md" 'deny, then ask, then allow'
expect_violation "missing deny->ask->allow order is caught" "$d" ask_tier_missing

d="$(make_mutant false-claim)"
printf '\nWhen a command contains shell operators:\n1. Permission wildcards won'"'"'t match\n' >> "$d/SKILL.md"
expect_violation "false compound-command claim is caught" "$d" false_compound_claim

d="$(make_mutant false-claim-ref)"
printf '\nNote: wildcards do not match commands joined with &&.\n' >> "$d/REFERENCE.md"
expect_violation "false claim in REFERENCE.md is caught" "$d" false_compound_claim

d="$(make_mutant local-trust)"
printf '\n- An untracked `.claude/settings.local.json` skips the trust step.\n' >> "$d/SKILL.md"
expect_violation "local-file-skips-trust claim is caught" "$d" false_local_trust_claim

d="$(make_mutant p-trust-dialog)"
printf '\n| Project allow rules ignored | Folder not trusted, or `-p` run in an untrusted folder | Accept the trust dialog |\n' >> "$d/SKILL.md"
expect_violation "accept-the-dialog fix for a -p run is caught" "$d" false_p_trust_dialog

d="$(make_mutant no-subcommand)"
delete_lines "$d/SKILL.md" '[Ee](very|ach) subcommand'
expect_violation "missing per-subcommand matching is caught" "$d" subcommand_missing

d="$(make_mutant no-dontask)"
delete_lines "$d/SKILL.md" '`dontAsk`'
expect_violation "missing dontAsk mode is caught" "$d" modes_missing

d="$(make_mutant no-auto-drop)"
delete_lines "$d/SKILL.md" 'drops broad allow rules'
expect_violation "missing auto-mode rule drop is caught" "$d" auto_drop_missing

d="$(make_mutant no-edit-covers)"
delete_lines "$d/SKILL.md" 'NotebookEdit'
expect_violation "missing Edit(path) coverage is caught" "$d" edit_covers_missing

d="$(make_mutant no-param)"
delete_lines "$d/SKILL.md" 'Tool\(param:value\)'
expect_violation "missing Tool(param:value) is caught" "$d" param_rule_missing

d="$(make_mutant no-mcp-scope)"
delete_lines "$d/SKILL.md" 'mcp__[A-Za-z0-9_<>-]+__\*'
expect_violation "missing mcp__<server>__* form is caught" "$d" mcp_scope_missing

d="$(make_mutant bogus-skill)"
printf '\n| MCP servers | Setting up MCP servers (use mcp-configuration skill) |\n' >> "$d/SKILL.md"
expect_violation "nonexistent bare skill reference is caught" "$d" unknown_skill_ref

d="$(make_mutant bogus-plugin-skill)"
printf '\nSee `health-plugin:mcp-configuration`.\n' >> "$d/SKILL.md"
expect_violation "nonexistent plugin:skill reference is caught" "$d" unknown_skill_ref

d="$(make_mutant cat-jq)"
printf '\n```bash\ncat .claude/settings.json | jq .\n```\n' >> "$d/REFERENCE.md"
expect_violation "cat | jq example is caught" "$d" cat_pipe_jq

d="$(make_mutant no-reference)"
rm -f "$d/REFERENCE.md"
expect_violation "dangling REFERENCE.md link is caught" "$d" dead_reference_link

d="$(make_mutant bad-heading)"
delete_lines "$d/REFERENCE.md" '^## Path Patterns$'
expect_violation "cited REFERENCE.md heading that vanished is caught" "$d" dead_reference_link

d="$(make_mutant no-use-when)"
awk '/^description:/{print "description: \"Settings hierarchy and permission patterns.\""; next} {print}' \
  "$d/SKILL.md" > "$d/x" && mv "$d/x" "$d/SKILL.md"
expect_violation "description without 'Use when' is caught" "$d" frontmatter

# 3. The pre-fix text (as shipped through 2026-11-09) trips its five defects.
pre="${SANDBOX}/pre-fix"
mkdir -p "$pre"
cat > "$pre/SKILL.md" <<'PREFIX'
---
name: settings-configuration
description: "Claude Code settings hierarchy, permission wildcards, and configuration patterns. Use when setting up permissions, debugging settings issues, or understanding allowed tools."
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, TodoWrite
created: 2026-02-04
modified: 2026-07-18
compatibility: claude-code
reviewed: 2026-02-04
---

# Claude Code Settings Configuration

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Setting up project permissions | Fixing plugin registry issues (use plugin-registry skill) |
| Debugging "permission denied" errors | Configuring hooks (use hooks-configuration skill) |
| Understanding settings hierarchy | Setting up MCP servers (use mcp-configuration skill) |

## Settings File Hierarchy

| Priority | File | Scope | Commit to Git? |
|----------|------|-------|----------------|
| 1 (lowest) | `~/.claude/settings.json` | User-level (all projects) | N/A |
| 2 | `.claude/settings.json` | Project-level | Yes |
| 3 (highest) | `.claude/settings.local.json` | Local overrides | No (gitignore) |

- `allow`: Tools matching these patterns run without prompts
- `deny`: Tools matching these patterns are always blocked

When a command contains shell operators:
1. Permission wildcards won't match
2. User sees explicit approval prompt

```bash
cat .claude/settings.json | jq .
```
PREFIX
pre_out="$(check_skill "$pre")"
for want in bare_bash_grant managed_missing ask_tier_missing false_compound_claim unknown_skill_ref cat_pipe_jq; do
  if grep -qE "^VIOLATION=${want}( |$)" <<<"$pre_out"; then
    pass "pre-fix text trips ${want}"
  else
    fail "pre-fix text should trip ${want}; got:"$'\n'"${pre_out:-<none>}"
  fi
done
# The checker must not flag the two references that did resolve.
if grep -qE 'VIOLATION=unknown_skill_ref DETAIL=\(use (plugin-registry|hooks-configuration) skill\)' <<<"$pre_out"; then
  fail "real skills plugin-registry / hooks-configuration flagged as unknown"
else
  pass "existing bare skill names resolve (control)"
fi

# 4. claude-security-settings (#3572): the correctness subset, with teeth.
expect_clean "claude-security-settings is clean (core scope)" "$SECURITY_DIR" core

# make_security_mutant <name> — copy the hardening skill into the sandbox
make_security_mutant() {
  local d="${SANDBOX}/sec-$1"
  mkdir -p "$d"
  cp "${SECURITY_DIR}/SKILL.md" "$d/SKILL.md"
  echo "$d"
}

d="$(make_security_mutant bare-bash)"
awk '/^allowed-tools:/{print "allowed-tools: Bash, Read, Write, Edit, Glob, Grep, TodoWrite"; next} {print}' \
  "$d/SKILL.md" > "$d/x" && mv "$d/x" "$d/SKILL.md"
expect_violation "security skill: bare Bash grant is caught" "$d" bare_bash_grant core

d="$(make_security_mutant reordered)"
awk '/^\| 1 \| \*\*Managed\*\*/{held=$0; next} {print} /^\| 5 \| \*\*User\*\*/{print held}' \
  "$d/SKILL.md" > "$d/x" && mv "$d/x" "$d/SKILL.md"
expect_violation "security skill: managed listed lowest is caught" "$d" precedence_order core

d="$(make_security_mutant no-managed)"
delete_lines "$d/SKILL.md" 'managed-settings\.json'
expect_violation "security skill: missing managed settings is caught" "$d" managed_missing core

d="$(make_security_mutant no-subcommand)"
delete_lines "$d/SKILL.md" '[Ee](very|ach) subcommand'
expect_violation "security skill: missing per-subcommand matching is caught" "$d" subcommand_missing core

# The completeness group stays out of the core scope.
sec_core_out="$(check_skill "$SECURITY_DIR" core)"
if grep -qE '^VIOLATION=(ask_tier_missing|modes_missing|auto_drop_missing|edit_covers_missing|param_rule_missing|mcp_scope_missing)( |$)' <<<"$sec_core_out"; then
  fail "core scope reported a completeness-group violation"
else
  pass "core scope skips the completeness group (control)"
fi

# The pre-fix hardening skill (as shipped through 2026-10-05) trips its defects.
sec_pre="${SANDBOX}/sec-pre-fix"
mkdir -p "$sec_pre"
cat > "$sec_pre/SKILL.md" <<'SECPREFIX'
---
name: claude-security-settings
description: "Claude Code security settings: permission wildcards, shell operator protections, project-level allowlists. Use when auditing or hardening .claude/settings.json permissions."
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, TodoWrite
---

### Settings File Locations

| File | Scope | Priority |
|------|-------|----------|
| `~/.claude/settings.json` | User-level (all projects) | Lowest |
| `.claude/settings.json` | Project-level (committed) | Medium |
| `.claude/settings.local.json` | Local project (gitignored) | Highest |

When a command contains shell operators:
1. Permission wildcards won't match
2. User sees explicit approval prompt

| Validate JSON | `cat .claude/settings.json \| jq .` |
SECPREFIX
sec_pre_out="$(check_skill "$sec_pre" core)"
for want in bare_bash_grant managed_missing precedence_order false_compound_claim subcommand_missing cat_pipe_jq; do
  if grep -qE "^VIOLATION=${want}( |$)" <<<"$sec_pre_out"; then
    pass "security pre-fix text trips ${want}"
  else
    fail "security pre-fix text should trip ${want}; got:"$'\n'"${sec_pre_out:-<none>}"
  fi
done

echo "PASS=${PASS} FAIL=${FAIL}"
[ "$FAIL" -eq 0 ]

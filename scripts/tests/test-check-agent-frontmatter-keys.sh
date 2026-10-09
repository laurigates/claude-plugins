#!/usr/bin/env bash
# Regression test for scripts/check-agent-frontmatter-keys.sh (#2646, #2722,
# #2723).
#
# Issue #2646: ten plugin agents declared `context: fork`, and
# .claude/rules/agent-development.md documented it as an agent field. It is a
# SKILL frontmatter field. The subagent frontmatter table at
# code.claude.com/docs/en/sub-agents.md does not list it, and the same page
# states "Claude Code ignores a field it doesn't recognize without reporting an
# error" — so the key did nothing, silently, while the rule told authors what it
# did. A live probe measured it inert (forked and briefed agents: bit-identical
# 2549 subagent_tokens, both blind to the parent turn).
#
# The guard diffs every `*-plugin/agents/*.md` top-level frontmatter key against
# the documented subagent field set. Every case below EXECUTES a copy-free run of
# the real checker against a planted fixture tree (or the real repo) and asserts
# on its structured output — a grep of the script for `context` would pass
# against a checker that never parses a file.
#
# Guards:
#   A. real repo: non-vacuous scan (agents AND fenced examples), STATUS=OK,
#      and nothing allowlisted — #2722 removed the ten `context` residuals
#   A2. real repo with the residual list EMPTIED: zero live findings, so the
#       empty default list hides nothing; a copy of a real agent with
#       `context: fork` planted back in is still caught (the guard is armed)
#   B. clean agent (documented fields + repo lifecycle dates) → OK
#   C. `context: fork` → ERROR skill_only_key, message names the fork type
#   D. `allowed-tools:` → ERROR skill_only_key
#   E. an unknown key → ERROR undocumented_key
#   F. nested keys and block-scalar bodies are NOT top-level keys
#   G. the markdown body is not frontmatter
#   H. a declared residual is suppressed, counted, and itemised — and the SAME
#      fixture with no residual declared still errors (attributable)
#   I. a stale residual entry is an ERROR
#   J. a residual for one key does not exempt a different key in that file
#   K. a worktree-shaped scan root still discovers its agents (#2219), and a
#      worktree clone nested below it is still pruned
#   L. no agents dir → SCANNED_EMPTY OK; agents dir with no files → ERROR
#   M. unknown argument → exit 2
#   N. --docs-file: the fetched table is the authority; drift is reported
#   O. a file with no frontmatter block is an ERROR
#   P. fenced agent examples (#2723): `allowed-tools:` in an agent-shaped YAML
#      or unlabeled fence is an ERROR naming file and line; `tools:`, a skill
#      frontmatter fence, a non-YAML fence, prose, and an indented line are not;
#      a listed doc missing while its plugin exists is an ERROR
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-agent-frontmatter-keys.sh"
seam="CHECK_AGENT_FRONTMATTER_KEYS_ALLOWLIST"

pass_count=0
fail_count=0

assert() {
  # assert <description> <"true"|"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

has_line() {
  # has_line <text> <exact line> — whole-line match (an unanchored KEY=1 is
  # satisfied by any sibling *_KEY=1; the #2219/#2297 anchoring lesson).
  grep -qxF -- "$2" <<<"$1" && echo true || echo false
}

has_text() {
  grep -qF -- "$2" <<<"$1" && echo true || echo false
}

lacks_text() {
  grep -qF -- "$2" <<<"$1" && echo false || echo true
}

tmp_root="$(mktemp -d)"
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then
  echo "mktemp failed" >&2
  exit 1
fi
trap 'rm -rf "$tmp_root"' EXIT

# new_tree <name> — an empty fixture repo root; prints its path.
new_tree() {
  local d="$tmp_root/$1"
  mkdir -p "$d"
  printf '%s\n' "$d"
}

# write_agent <root> <plugin> <agent> <frontmatter-body> [markdown-body]
write_agent() {
  local root="$1" plugin="$2" agent="$3" fm="$4" body="${5:-# Agent}"
  mkdir -p "$root/$plugin/agents"
  printf -- '---\n%s\n---\n\n%s\n' "$fm" "$body" > "$root/$plugin/agents/$agent.md"
}

CLEAN_FM='name: worker
description: Does work.
model: opus
effort: low
tools: Read, Grep, Glob
color: "#123456"
maxTurns: 20
skills:
  - some-skill
created: 2026-01-01
modified: 2026-01-01
reviewed: 2026-01-01'

# run <root> [args...] — run the checker with an EMPTY residual list (hermetic).
run() {
  local root="$1"; shift
  env "$seam=" bash "$checker" --project-dir "$root" "$@" 2>&1
}

# --- A: real repo, default residual list ---------------------------------------
out_a="$(bash "$checker" 2>&1)"; rc_a=$?
assert "A: real repo passes (exit 0)" \
  "$([ "$rc_a" -eq 0 ] && echo true || echo false)"
assert "A: real repo STATUS=OK" "$(has_line "$out_a" "STATUS=OK")"
assert "A: real repo scan is not empty" "$(has_line "$out_a" "SCANNED_EMPTY=false")"
scanned_a="$(grep -m1 '^AGENT_FILES_SCANNED=' <<<"$out_a" | cut -d= -f2)"
assert "A: real repo scanned a non-trivial number of agents (>=10, got '${scanned_a:-}')" \
  "$([ "${scanned_a:-0}" -ge 10 ] && echo true || echo false)"
assert "A: nothing is allowlisted (#2722 emptied the residual list)" \
  "$(has_line "$out_a" "ALLOWLISTED=0")"
assert "A: both custom-agent-definitions docs are scanned for fenced examples" \
  "$(has_line "$out_a" "EXAMPLE_DOCS_SCANNED=2")"
fences_a="$(grep -m1 '^EXAMPLE_FENCES_CHECKED=' <<<"$out_a" | cut -d= -f2)"
assert "A: the fenced-example scan is non-vacuous (>=5 fences, got '${fences_a:-}')" \
  "$([ "${fences_a:-0}" -ge 5 ] && echo true || echo false)"

# --- A2: real repo, residual list emptied --------------------------------------
out_a2="$(env "$seam=" bash "$checker" 2>&1)"; rc_a2=$?
assert "A2: real repo with no declared residuals passes (exit 0)" \
  "$([ "$rc_a2" -eq 0 ] && echo true || echo false)"
assert "A2: zero live findings with an empty residual list" \
  "$(has_line "$out_a2" "ISSUE_COUNT=0")"
assert "A2: no live \`context\` key remains in any agent" \
  "$(lacks_text "$out_a2" "KEY=context")"
# Seeded: a real agent with the removed key planted back in must still fail, so
# the clean result above is the guard passing a clean tree, not a disarmed one.
t="$(new_tree a2)"
mkdir -p "$t/agents-plugin/agents"
awk 'NR == 2 { print "context: fork" } { print }' \
  "$repo_root/agents-plugin/agents/research.md" > "$t/agents-plugin/agents/research.md"
out="$(run "$t")"; rc=$?
assert "A2: a real agent with \`context: fork\` planted back in fails (exit 1)" \
  "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "A2: the planted key is reported as skill_only_key" \
  "$(has_text "$out" "TYPE=skill_only_key FILE=agents-plugin/agents/research.md KEY=context ")"

# --- B: clean agent -------------------------------------------------------------
t="$(new_tree b)"; write_agent "$t" demo-plugin worker "$CLEAN_FM"
out="$(run "$t")"; rc=$?
assert "B: clean agent exits 0" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "B: clean agent STATUS=OK" "$(has_line "$out" "STATUS=OK")"
assert "B: no REASON= on the OK path" "$(lacks_text "$out" "REASON=")"
assert "B: clean agent scanned exactly 1 file" "$(has_line "$out" "AGENT_FILES_SCANNED=1")"
assert "B: clean agent ISSUE_COUNT=0" "$(has_line "$out" "ISSUE_COUNT=0")"

# --- C: context: fork -----------------------------------------------------------
t="$(new_tree c)"; write_agent "$t" demo-plugin worker "$CLEAN_FM
context: fork"
out="$(run "$t")"; rc=$?
assert "C: context: fork exits 1" "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "C: REASON= names the worst finding" "$(printf '%s\n' "$out" | grep -qE '^REASON=skill_only_key: .{1,}$' && echo true || echo false)"
assert "C: context: fork is reported as a skill-only key" \
  "$(has_text "$out" "TYPE=skill_only_key FILE=demo-plugin/agents/worker.md KEY=context ")"
assert "C: the message points at the runtime fork subagent type" \
  "$(has_text "$out" "subagent_type: \"fork\"")"

# --- D: allowed-tools -----------------------------------------------------------
t="$(new_tree d)"; write_agent "$t" demo-plugin worker "$CLEAN_FM
allowed-tools: Read"
out="$(run "$t")"; rc=$?
assert "D: allowed-tools exits 1" "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "D: allowed-tools is reported as a skill-only key" \
  "$(has_text "$out" "TYPE=skill_only_key FILE=demo-plugin/agents/worker.md KEY=allowed-tools ")"

# --- E: unknown key -------------------------------------------------------------
t="$(new_tree e)"; write_agent "$t" demo-plugin worker "$CLEAN_FM
temperature: 0.2"
out="$(run "$t")"; rc=$?
assert "E: an unknown key exits 1" "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "E: an unknown key is reported as undocumented" \
  "$(has_text "$out" "TYPE=undocumented_key FILE=demo-plugin/agents/worker.md KEY=temperature ")"

# --- F: nested keys and block-scalar bodies -------------------------------------
t="$(new_tree f)"; write_agent "$t" demo-plugin worker 'name: worker
description: |
  A block scalar whose body looks like frontmatter:
  context: fork
  allowed-tools: Read
model: opus
tools: Read
hooks:
  Stop:
    - matcher: ""
experimental:
  cacheTtl: 1h'
out="$(run "$t")"; rc=$?
assert "F: nested keys and block-scalar lines are not top-level keys (exit 0)" \
  "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "F: ISSUE_COUNT=0" "$(has_line "$out" "ISSUE_COUNT=0")"

# --- G: the body is not frontmatter ---------------------------------------------
t="$(new_tree g)"; write_agent "$t" demo-plugin worker "$CLEAN_FM" '# Agent

context: fork
allowed-tools: Read'
out="$(run "$t")"; rc=$?
assert "G: body lines that look like keys are not frontmatter (exit 0)" \
  "$([ "$rc" -eq 0 ] && echo true || echo false)"

# --- H: declared residual suppresses, counts, itemises --------------------------
t="$(new_tree h)"; write_agent "$t" demo-plugin worker "$CLEAN_FM
context: fork"
out="$(env "$seam=demo-plugin/agents/worker.md|context" bash "$checker" --project-dir "$t" 2>&1)"; rc=$?
assert "H: a declared residual passes (exit 0)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "H: ALLOWLISTED=1" "$(has_line "$out" "ALLOWLISTED=1")"
assert "H: the suppression is itemised" \
  "$(has_text "$out" "FILE=demo-plugin/agents/worker.md KEY=context")"
out="$(run "$t")"; rc=$?
assert "H: the same fixture with no residual declared fails (exit 1)" \
  "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "H: ALLOWLISTED=0 is still emitted" "$(has_line "$out" "ALLOWLISTED=0")"

# --- I: stale residual ----------------------------------------------------------
t="$(new_tree i)"; write_agent "$t" demo-plugin worker "$CLEAN_FM"
out="$(env "$seam=demo-plugin/agents/worker.md|context" bash "$checker" --project-dir "$t" 2>&1)"; rc=$?
assert "I: a stale residual entry fails (exit 1)" "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "I: the stale entry is named" \
  "$(has_text "$out" "TYPE=stale_allowlist_entry ENTRY=demo-plugin/agents/worker.md|context")"

# --- J: a residual does not exempt a different key ------------------------------
t="$(new_tree j)"; write_agent "$t" demo-plugin worker "$CLEAN_FM
context: fork
agent: general-purpose"
out="$(env "$seam=demo-plugin/agents/worker.md|context" bash "$checker" --project-dir "$t" 2>&1)"; rc=$?
assert "J: a different key in a residual file still fails (exit 1)" \
  "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "J: the other key is reported" "$(has_text "$out" "KEY=agent ")"
assert "J: exactly one issue (context stays suppressed)" "$(has_line "$out" "ISSUE_COUNT=1")"

# --- K: worktree-shaped root + nested clone -------------------------------------
t="$tmp_root/k/repo/.claude/worktrees/agent-deadbeef"
mkdir -p "$t"
write_agent "$t" demo-plugin worker "$CLEAN_FM"
write_agent "$t/demo-plugin/.claude/worktrees/agent-cafe" demo-plugin worker "$CLEAN_FM
context: fork"
out="$(run "$t")"; rc=$?
assert "K: a worktree-shaped root still discovers its agent (AGENT_FILES_SCANNED=1)" \
  "$(has_line "$out" "AGENT_FILES_SCANNED=1")"
assert "K: the nested worktree clone is pruned (exit 0, no finding from it)" \
  "$([ "$rc" -eq 0 ] && echo true || echo false)"

# --- L: empty corpus vs misfire -------------------------------------------------
t="$(new_tree l1)"; mkdir -p "$t/demo-plugin/skills/x"
out="$(run "$t")"; rc=$?
assert "L: a tree with no agents dir is legitimately empty (exit 0)" \
  "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "L: SCANNED_EMPTY=true" "$(has_line "$out" "SCANNED_EMPTY=true")"
t="$(new_tree l2)"; mkdir -p "$t/demo-plugin/agents"
out="$(run "$t")"; rc=$?
assert "L: an agents dir with zero files is a misfire (exit 1)" \
  "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "L: the misfire is named nothing_scanned" "$(has_text "$out" "TYPE=nothing_scanned")"

# --- M: unknown argument --------------------------------------------------------
bash "$checker" --bogus >/dev/null 2>&1; rc=$?
assert "M: an unknown argument exits 2" "$([ "$rc" -eq 2 ] && echo true || echo false)"

# --- N: --docs-file authority and drift -----------------------------------------
docs="$tmp_root/sub-agents.md"
cat > "$docs" <<'EOF'
# Subagents

A decoy table whose header ALSO starts with `Field` — the parser must key on the
`| Field | Required |` header, not on the first column's name.

| Field        | Type   | Notes            |
| :----------- | :----- | :--------------- |
| `decoyField` | string | not frontmatter  |

| Field         | Required | Description        |
| :------------ | :------- | :----------------- |
| `name`        | Yes      | Unique identifier  |
| `description` | Yes      | When to delegate   |
| `tools`       | No       | Tools              |
| `model`       | No       | Model              |
| `brandNew`    | No       | A field added upstream |

| Mode      | Description |
| :-------- | :---------- |
| `default` | Manual mode |
EOF
t="$(new_tree n)"; write_agent "$t" demo-plugin worker 'name: worker
description: Does work.
tools: Read
model: opus
brandNew: true
color: "#123456"'
out="$(run "$t" --docs-file "$docs")"; rc=$?
assert "N: a field documented only upstream is accepted under --docs-file" \
  "$(lacks_text "$out" "KEY=brandNew")"
assert "N: a field the fetched table no longer lists is flagged" \
  "$(has_text "$out" "TYPE=undocumented_key FILE=demo-plugin/agents/worker.md KEY=color ")"
# Exact line: if the second (permission-mode) table were read as fields, the
# value would read `brandNew,default` and this whole-line match would fail.
assert "N: drift names exactly the upstream-only field" \
  "$(has_line "$out" "DOCS_ONLY_FIELDS=brandNew")"
assert "N: the docs table is reported as parsed (5 fields)" \
  "$(has_line "$out" "DOCS_FIELDS=5")"
assert "N: exit 1 (color is undocumented under the fetched table)" \
  "$([ "$rc" -eq 1 ] && echo true || echo false)"
printf '# No table here\n' > "$tmp_root/empty-docs.md"
out="$(run "$t" --docs-file "$tmp_root/empty-docs.md")"; rc=$?
assert "N: a docs file without the table is an ERROR, not an empty authority" \
  "$(has_text "$out" "TYPE=docs_table_not_found")"
assert "N: docs_table_not_found exits 1" "$([ "$rc" -eq 1 ] && echo true || echo false)"

# --- O: no frontmatter ----------------------------------------------------------
t="$(new_tree o)"; mkdir -p "$t/demo-plugin/agents"
printf '# Just a body\n' > "$t/demo-plugin/agents/worker.md"
out="$(run "$t")"; rc=$?
assert "O: an agent with no frontmatter block fails (exit 1)" \
  "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "O: it is named no_frontmatter" "$(has_text "$out" "TYPE=no_frontmatter")"

# --- P: fenced agent examples (#2723) ------------------------------------------
cad="agent-patterns-plugin/skills/custom-agent-definitions"
# write_cad <root> <skill-md-body> <reference-md-body>
write_cad() {
  mkdir -p "$1/$cad"
  printf '%s\n' "$2" > "$1/$cad/SKILL.md"
  printf '%s\n' "$3" > "$1/$cad/REFERENCE.md"
}
FENCE='```'
CLEAN_REF="# Reference

${FENCE}yaml
tools: Read, Grep
disallowedTools: Write, Edit
${FENCE}"

t="$(new_tree p1)"; write_agent "$t" demo-plugin worker "$CLEAN_FM"
write_cad "$t" "---
name: custom-agent-definitions
description: Agents.
allowed-tools: Read, Write
---

# Custom Agent Definitions

${FENCE}yaml
---
name: my-agent
description: Does work
model: opus
allowed-tools: Bash, Read
---
${FENCE}" "$CLEAN_REF"
out="$(run "$t")"; rc=$?
assert "P: allowed-tools in an agent example fence fails (exit 1)" \
  "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "P: the finding names the file, the line, and the key" \
  "$(has_text "$out" "TYPE=example_skill_only_key FILE=$cad/SKILL.md LINE=14 KEY=allowed-tools ")"
assert "P: the skill's OWN frontmatter allowed-tools is not a finding (exactly one issue)" \
  "$(has_line "$out" "ISSUE_COUNT=1")"
assert "P: the message names the agent field" "$(has_text "$out" "the agent field is \`tools:\`")"

# The same tree with the example corrected passes.
write_cad "$t" "# Custom Agent Definitions

${FENCE}yaml
---
name: my-agent
model: opus
tools: Bash, Read
---
${FENCE}" "$CLEAN_REF"
out="$(run "$t")"; rc=$?
assert "P: tools: in the agent example passes (exit 0)" \
  "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "P: both docs and both fences are counted" \
  "$([ "$(has_line "$out" "EXAMPLE_DOCS_SCANNED=2")" = true ] && [ "$(has_line "$out" "EXAMPLE_FENCES_CHECKED=2")" = true ] && echo true || echo false)"

# Not agent examples: a skill frontmatter fence, a bash fence, prose, and an
# indented block-scalar line. An unlabeled fence with the skill spelling of
# disallowedTools IS one.
t="$(new_tree p2)"; write_agent "$t" demo-plugin worker "$CLEAN_FM"
write_cad "$t" "# Custom Agent Definitions

Prose: write allowed-tools: in a skill, tools: in an agent.

${FENCE}yaml
name: my-skill
user-invocable: false
allowed-tools: Read
${FENCE}

${FENCE}bash
allowed-tools: Read
${FENCE}

${FENCE}yaml
description: |
  allowed-tools: Read
tools: Read
${FENCE}

${FENCE}
name: my-agent
disallowed-tools: Write
${FENCE}" "$CLEAN_REF"
out="$(run "$t")"; rc=$?
assert "P: only the unlabeled agent fence with disallowed-tools is reported (exactly one issue)" \
  "$(has_line "$out" "ISSUE_COUNT=1")"
assert "P: an unlabeled agent fence with disallowed-tools is reported" \
  "$(has_text "$out" "TYPE=example_skill_only_key FILE=$cad/SKILL.md LINE=23 KEY=disallowed-tools ")"
assert "P: the bash fence is not a YAML example (4 of 5 fences counted)" \
  "$(has_line "$out" "EXAMPLE_FENCES_CHECKED=4")"

# A listed doc missing while its plugin exists: a rename must not retire the scan.
t="$(new_tree p3)"; write_agent "$t" demo-plugin worker "$CLEAN_FM"
write_cad "$t" "# Custom Agent Definitions" "$CLEAN_REF"
rm "$t/$cad/REFERENCE.md"
out="$(run "$t")"; rc=$?
assert "P: a missing example doc fails (exit 1)" \
  "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "P: it is named example_doc_missing" \
  "$(has_text "$out" "TYPE=example_doc_missing FILE=$cad/REFERENCE.md ")"

echo "check-agent-frontmatter-keys (#2646/#2723): ${pass_count} passed, ${fail_count} failed"
[ "$fail_count" -eq 0 ]

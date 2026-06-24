#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq expressions use $ for variable references, not shell expansion
set -euo pipefail

# Plugin compliance checker - validates plugin structure and metadata
# Usage: ./scripts/plugin-compliance-check.sh [plugin1 plugin2 ...]
# If no args provided, auto-detects all *-plugin directories

# Change to repository root
cd "$(dirname "$0")/.." || exit 1

# Auto-detect plugins if no args provided
if [ $# -eq 0 ]; then
  PLUGINS=()
  while IFS= read -r -d '' dir; do
    PLUGINS+=("$(basename "$dir")")
  done < <(find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0 | sort -z)
else
  PLUGINS=("$@")
fi

if [ ${#PLUGINS[@]} -eq 0 ]; then
  echo "No plugins found"
  exit 0
fi

# Status tracking
issues=()
recommendations=()
overall_failed=false

# Results arrays (parallel indexed with PLUGINS)
results_json=()
results_frontmatter=()
results_body=()
results_marketplace=()
results_release=()
results_bash=()
results_desc=()
results_when_to_use=()
results_size=()
results_overall=()

# Helper: extract YAML frontmatter field
extract_field() {
  local file="$1"
  local field="$2"
  head -50 "$file" 2>/dev/null | grep -m1 "^${field}:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r' || echo ""
}

# Convert status code to symbol
to_symbol() {
  case $1 in
    0) echo "✅" ;;
    1) echo "⚠️" ;;
    *) echo "❌" ;;
  esac
}

# Check 1: plugin.json required fields
check_plugin_json() {
  local plugin="$1"
  local json_file="${plugin}/.claude-plugin/plugin.json"

  if [ ! -f "$json_file" ]; then
    issues+=("❌ ${plugin}: Missing .claude-plugin/plugin.json")
    return 2
  fi

  local plugin_name
  plugin_name=$(jq -r '.name // ""' "$json_file" 2>/dev/null)

  if [ -z "$plugin_name" ]; then
    issues+=("❌ ${plugin}: plugin.json missing required 'name' field")
    return 2
  fi

  if [ "$plugin_name" != "$plugin" ]; then
    issues+=("❌ ${plugin}: plugin.json name '${plugin_name}' doesn't match directory '${plugin}'")
    return 2
  fi

  if ! echo "$plugin_name" | grep -qE '^[a-z][a-z0-9-]*$'; then
    issues+=("❌ ${plugin}: plugin.json name '${plugin_name}' not in kebab-case format")
    return 2
  fi

  local missing_recommended=()
  local version description keywords
  version=$(jq -r '.version // ""' "$json_file" 2>/dev/null)
  description=$(jq -r '.description // ""' "$json_file" 2>/dev/null)
  keywords=$(jq -r '.keywords // [] | length' "$json_file" 2>/dev/null || echo "0")

  [ -z "$version" ] && missing_recommended+=("version")
  [ -z "$description" ] && missing_recommended+=("description")
  [ "$keywords" = "0" ] && missing_recommended+=("keywords")

  if [ ${#missing_recommended[@]} -gt 0 ]; then
    recommendations+=("⚠️ ${plugin}: plugin.json missing recommended fields: ${missing_recommended[*]}")
    return 1
  fi

  return 0
}

# Check 2: Skill frontmatter completeness
check_skill_frontmatter() {
  local plugin="$1"
  local skills_dir="${plugin}/skills"

  if [ ! -d "$skills_dir" ]; then
    return 0
  fi

  local skill_files=()
  while IFS= read -r -d '' f; do
    skill_files+=("$f")
  done < <(find "$skills_dir" -type f \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)

  if [ ${#skill_files[@]} -eq 0 ]; then
    return 0
  fi

  local has_errors=false
  local has_warnings=false

  for skill_file in "${skill_files[@]}"; do
    local skill_name
    skill_name=$(basename "$(dirname "$skill_file")")

    local fm_name fm_description fm_allowed_tools
    fm_name=$(extract_field "$skill_file" "name")
    fm_description=$(extract_field "$skill_file" "description")
    fm_allowed_tools=$(extract_field "$skill_file" "allowed-tools")

    local missing_required=()
    [ -z "$fm_name" ] && missing_required+=("name")
    [ -z "$fm_description" ] && missing_required+=("description")
    [ -z "$fm_allowed_tools" ] && missing_required+=("allowed-tools")

    if [ ${#missing_required[@]} -gt 0 ]; then
      issues+=("❌ ${plugin}/${skill_name}: SKILL.md missing required fields: ${missing_required[*]}")
      has_errors=true
      continue
    fi

    local fm_model fm_created fm_modified fm_reviewed
    fm_model=$(extract_field "$skill_file" "model")
    fm_created=$(extract_field "$skill_file" "created")
    fm_modified=$(extract_field "$skill_file" "modified")
    fm_reviewed=$(extract_field "$skill_file" "reviewed")

    local missing_recommended=()
    # Note: `model` may be set to `opus` or `sonnet` at the extremes; haiku is
    # disallowed for any skill (see check below). See
    # .claude/rules/skill-development.md ("Model Selection") for policy.
    [ -z "$fm_created" ] && missing_recommended+=("created")
    [ -z "$fm_modified" ] && missing_recommended+=("modified")
    [ -z "$fm_reviewed" ] && missing_recommended+=("reviewed")

    local fm_args fm_argument_hint
    fm_args=$(extract_field "$skill_file" "args")
    fm_argument_hint=$(extract_field "$skill_file" "argument-hint")

    if [ -n "$fm_args" ] && [ -z "$fm_argument_hint" ]; then
      missing_recommended+=("argument-hint (args present)")
    elif [ -z "$fm_args" ] && [ -n "$fm_argument_hint" ]; then
      missing_recommended+=("args (argument-hint present)")
    fi

    if [ ${#missing_recommended[@]} -gt 0 ]; then
      recommendations+=("⚠️ ${plugin}/${skill_name}: SKILL.md missing recommended fields: ${missing_recommended[*]}")
      has_warnings=true
    fi

    # Regression: model: haiku breaks AskUserQuestion (PR #879) and the cost
    # savings vs Sonnet do not justify the quality risk for non-interactive
    # skills either. Sonnet is the floor — see .claude/rules/skill-development.md.
    if [ "$fm_model" = "haiku" ]; then
      issues+=("❌ ${plugin}/${skill_name}: model: haiku is disallowed — use sonnet (floor) or opus")
      has_errors=true
    fi

    # Regression: unquoted args:/argument-hint: values that contain `[ ... ]`
    # flow sequences or embedded colons break YAML parsing — `[a] [b]` raises
    # "expected block end, but found '['", and `<x> --foo "type(scope): bar"`
    # raises "mapping values are not allowed here". When YAML parsing fails,
    # Claude Code falls back to the file body for the description, and the
    # skill autocompletes under its namespace prefix instead of the short form
    # (16 skills affected before this fix). A single unquoted `[foo]` parses
    # but yields a list instead of a string, also wrong.
    # Regression: a duplicated top-level frontmatter key (e.g. two `modified:`
    # lines from a date-stamping script that appends instead of replacing)
    # aborts the OpenCode/rulesync export with "duplicated mapping key".
    # PyYAML's safe_load silently keeps the last value, so the parse check
    # below cannot catch it — a SafeLoader subclass that rejects duplicates is
    # required to match rulesync's (js-yaml) strictness. (just export-opencode)
    local yaml_err
    yaml_err=$(python3 - "$skill_file" <<'PY' 2>&1 || true)
import sys, yaml
path = sys.argv[1]
with open(path) as fh:
    content = fh.read()
if not content.startswith('---'):
    sys.exit(0)
parts = content.split('---', 2)
if len(parts) < 3:
    sys.exit(0)

class DupKeyLoader(yaml.SafeLoader):
    pass

def _no_duplicates(loader, node, deep=False):
    seen = set()
    for key_node, _ in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in seen:
            raise yaml.constructor.ConstructorError(
                None, None, f"duplicated mapping key: {key!r}", key_node.start_mark)
        seen.add(key)
    return yaml.SafeLoader.construct_mapping(loader, node, deep)

DupKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_duplicates)

try:
    fm = yaml.load(parts[1], Loader=DupKeyLoader) or {}
except Exception as e:
    print(f"PARSE_ERROR: {str(e).splitlines()[0]}")
    sys.exit(0)
for field in ('args', 'argument-hint'):
    if field in fm and not isinstance(fm[field], str):
        print(f"WRONG_TYPE: {field} parses as {type(fm[field]).__name__}, not str — quote the value")
PY
    if [ -n "$yaml_err" ]; then
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md frontmatter ${line}")
      done <<< "$yaml_err"
      has_errors=true
    fi
  done

  if $has_errors; then
    return 2
  elif $has_warnings; then
    return 1
  fi

  return 0
}

# Check 3: Skill body integrity
# Regression: git-pr-feedback had 'name: fieldname' + '---' entries scattered in body,
# which render as accidental setext H2 headings in markdown (PR #799).
check_skill_body() {
  local plugin="$1"
  local skills_dir="${plugin}/skills"

  if [ ! -d "$skills_dir" ]; then
    return 0
  fi

  local has_errors=false

  while IFS= read -r -d '' skill_file; do
    local skill_name
    skill_name=$(basename "$(dirname "$skill_file")")

    # Detect YAML-key lines immediately followed by '---' outside the frontmatter.
    # In CommonMark, "key: value\n---" creates a setext H2 heading — clearly unintended.
    # Use awk: skip the opening frontmatter block (first ---...--- pair), then flag hits.
    # Also skip content inside triple-backtick code fences to avoid false positives.
    local bad_lines
    bad_lines=$(awk '
      /^---$/ && fm_count < 2 { fm_count++; prev = ""; next }
      fm_count >= 2 {
        if (/^```/) { in_code = !in_code }
        if (!in_code && prev ~ /^[a-z][a-z-]*:/ && /^---$/) {
          print NR ": " prev
        }
        prev = $0
        next
      }
      { prev = $0 }
    ' "$skill_file")

    if [ -n "$bad_lines" ]; then
      while IFS= read -r hit; do
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md body has YAML-key+separator (accidental H2 heading) at line ${hit}")
      done <<< "$bad_lines"
      has_errors=true
    fi

    # Regression: blueprint rule-writing skills must reference the configurable
    # output path (`generated_rules_path`) rather than hardcoding `.claude/rules/`.
    # See issue #1043: hardcoded paths collide with hand-authored rules in the
    # parent .claude/rules/ directory. blueprint-init writes the initial rules
    # (development.md / testing.md / document-management.md) and must honour the
    # same configurable path it offers in Step 4a (issue #1675).
    if [ "$skill_name" = "blueprint-generate-rules" ] || [ "$skill_name" = "blueprint-derive-rules" ] || [ "$skill_name" = "blueprint-init" ]; then
      if ! grep -q "generated_rules_path" "$skill_file"; then
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md must reference 'generated_rules_path' to honour configurable output directory (issue #1043, #1675)")
        has_errors=true
      fi
    fi

    # Regression: blueprint-init Step 3 must gate the "migrate documents
    # (Recommended)" default on cross-reference density — when a doc is
    # referenced from OUTSIDE docs/, migration is expensive and the
    # unconditional recommendation is wrong (issue #1674). The semantic
    # invariant is that the cross-reference gating survives bulk edits.
    if [ "$skill_name" = "blueprint-init" ]; then
      if ! grep -q "referenced outside" "$skill_file"; then
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md Step 3 must gate the migrate-documents recommendation on cross-reference density ('referenced outside' docs/) (issue #1674)")
        has_errors=true
      fi
    fi

    # Regression: configure-claude-plugins documents two suffix forms
    # (`@claude-plugins` for settings.json enabledPlugins, `@laurigates-claude-plugins`
    # for workflow plugins: blocks) that are visually similar but semantically distinct.
    # See issue #1337: a reader copy-pasting between sections silently produced a
    # non-functional config because the explanation lived 50 lines away in
    # "Important Notes". The semantic invariant is that BOTH suffix forms must
    # carry inline annotation strings near each use — not just a far-away footnote.
    if [ "$skill_name" = "configure-claude-plugins" ]; then
      # The annotations must both exist (proves the two forms are explained inline)
      if ! grep -q "extraKnownMarketplaces key" "$skill_file"; then
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md must include inline note 'extraKnownMarketplaces key' near @claude-plugins usage (issue #1337)")
        has_errors=true
      fi
      if ! grep -q "marketplace .name. in marketplace.json" "$skill_file"; then
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md must include inline note 'marketplace \`name\` in marketplace.json' near @laurigates-claude-plugins usage (issue #1337)")
        has_errors=true
      fi
    fi

    # Regression: task-add must emit the stable UUID alongside the numeric ID.
    # Taskwarrior numeric IDs are a display index over pending tasks and shift
    # down by one whenever any other task is completed. A session that created
    # task 141 then annotated `task 141 ...` 30 min later silently landed the
    # annotation on an unrelated task whose ID had drifted (issue #1417). The
    # semantic invariant is that the skill resolves the immutable UUID via the
    # `+LATEST` virtual tag so downstream annotate/modify/done address the
    # right task. Guards against a bulk edit silently dropping the UUID emit.
    if [ "$skill_name" = "task-add" ]; then
      if ! grep -q "task +LATEST _get uuid" "$skill_file"; then
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md must emit the stable UUID via 'task +LATEST _get uuid' after create (issue #1417)")
        has_errors=true
      fi
    fi

    # Regression: task-reconcile is the only skill that ACTS on the stale-task
    # drift task-status detects. Its load-bearing invariants are (1) a bulk
    # `task import` round-trip for leaf tasks, (2) a default-safe dry-run with an
    # explicit --apply to mutate. A bulk edit that drops either silently turns
    # off the safety preview or the JSON close path. Scoped to this skill.
    if [ "$skill_name" = "task-reconcile" ]; then
      for token in "task import" "--apply" "dry-run"; do
        if ! grep -q -- "$token" "$skill_file"; then
          issues+=("❌ ${plugin}/${skill_name}: SKILL.md must retain '${token}' (reconcile JSON-close path / dry-run safety)")
          has_errors=true
        fi
      done
    fi

    # Regression: task-coordinate / task-status select dispatch candidates from
    # taskwarrior's native +READY virtual tag (subsumes -BLOCKED, respects
    # wait:/scheduled:). A bulk edit reverting to the hand-rolled
    # `-BLOCKED -ACTIVE` filter would silently re-surface waiting/future-scheduled
    # work as candidates. Guard that +READY survives.
    if [ "$skill_name" = "task-coordinate" ] || [ "$skill_name" = "task-status" ]; then
      if ! grep -q "+READY" "$skill_file"; then
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md must use the native '+READY' tag for ready-candidate selection (native scheduling adoption)")
        has_errors=true
      fi
    fi

    # Regression: install-native-hooks must document that `task import` bypasses
    # taskwarrior native hooks — the caveat that keeps reconcile's bulk path and
    # the opt-in hooks from being mistaken for overlapping enforcement. Scoped.
    if [ "$skill_name" = "install-native-hooks" ]; then
      if ! grep -q "task import" "$skill_file"; then
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md must document that 'task import' bypasses native hooks")
        has_errors=true
      fi
    fi

    # Regression: parallel-agent-dispatch must document dispatching a Skill-less
    # agentType for read-only fan-out. A general-purpose subagent carries the
    # Skill tool, which injects the ~88k-char skill_listing attachment up front;
    # combined with file reads + a forced StructuredOutput schema it overflows
    # the context window (40-100% batch failures). The fix recommends a
    # Skill-less agentType (no skill_listing tax) for read-only fan-out
    # (issue #1549, folds #1550). Guards a bulk edit dropping the guidance.
    if [ "$skill_name" = "parallel-agent-dispatch" ]; then
      for token in "skill_listing" "Skill-less agentType"; do
        if ! grep -q -- "$token" "$skill_file"; then
          issues+=("❌ ${plugin}/${skill_name}: SKILL.md must retain '${token}' (Skill-less read-only fan-out guidance, issue #1549)")
          has_errors=true
        fi
      done
    fi

    # Regression: evaluate-legibility's Step-3 triage and the cold-reader prompt
    # depend on the verdict vocabulary (`clear` / `needs-revision`) and the
    # QUESTIONS / HESITATIONS critique headings reused from cold-read-gate. A
    # bulk edit that "tightens" the prose and drops those literal tokens would
    # silently sever the gate from its consumer (Slice 2 triage reads them).
    # Guards the semantic invariant, scoped to this skill only.
    if [ "$skill_name" = "evaluate-legibility" ]; then
      for token in "clear" "needs-revision" "QUESTIONS" "HESITATIONS"; do
        if ! grep -q "$token" "$skill_file"; then
          issues+=("❌ ${plugin}/${skill_name}: SKILL.md must retain the cold-reader token '${token}' (verdict/critique schema reused from cold-read-gate)")
          has_errors=true
        fi
      done
    fi

    # Regression: project-continue read deprecated blueprint v1/v2 state paths
    # `.claude/blueprints/prds/` and `.claude/blueprints/work-orders/`, so it
    # never found PRDs or work-orders in a current-format (v3.x) blueprint repo
    # where state lives under `docs/`. See issue #1503: the canonical paths are
    # `docs/prds/` (blueprint-init) and `docs/blueprint/work-orders/`
    # (blueprint-status). The semantic invariant is that the resume skill points
    # at the live state directories — a bulk edit re-introducing the deprecated
    # paths silently breaks task resumption again. (blueprint-migration/upgrade
    # skills legitimately cite the old paths as historical move sources, so this
    # guard is scoped to project-continue only.)
    if [ "$skill_name" = "project-continue" ]; then
      if grep -q '\.claude/blueprints/' "$skill_file"; then
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md references deprecated '.claude/blueprints/' state path — use canonical 'docs/prds/' and 'docs/blueprint/work-orders/' (issue #1503)")
        has_errors=true
      fi
    fi

    # Regression: git-issue / git-issue-manage advertised bare issue numbers only,
    # so a pasted GitHub issue URL or `#N` was silently ignored, and cross-repo
    # URLs had no `-R owner/repo` plumbing. The semantic invariant is that the
    # advertised URL/#N form is actually NORMALIZED in the body (`/issues/` URL
    # shape) AND that cross-repo refs carry `-R`. A bulk edit that re-tightens the
    # args back to "issue numbers" must not drop the normalization step.
    if [ "$skill_name" = "git-issue" ] || [ "$skill_name" = "git-issue-manage" ]; then
      if ! grep -qF "/issues/" "$skill_file" || ! grep -qF -- "-R " "$skill_file"; then
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md must normalize issue-URL/#N refs ('/issues/' shape) and carry '-R <owner>/<repo>' for cross-repo URLs")
        has_errors=true
      fi
    fi

    # Regression: project-refocus accepted no focus directive (args: ""), so a
    # user's "/project:refocus focus on X, ignore Y" was dropped. The fix parses
    # $ARGUMENTS as an optional steering directive that biases Remaining-vs-Stale
    # bucketing. The load-bearing semantic invariant is that the directive is
    # STEERING, not OVERRIDE: it must not cancel a live user boundary. A bulk edit
    # that adds directive support but drops the boundary guard would re-introduce
    # the auto-mode.md Conversation-Stated-Boundaries hazard — so assert all four
    # tokens. (Scoped on the directory name 'project-refocus', not name: refocus.)
    if [ "$skill_name" = "project-refocus" ]; then
      for token in '$ARGUMENTS' 'focus directive' 'Stale-eligible' 'boundary'; do
        if ! grep -qF "$token" "$skill_file"; then
          issues+=("❌ ${plugin}/${skill_name}: SKILL.md must retain focus-directive token '${token}' (steering-not-override invariant)")
          has_errors=true
        fi
      done
    fi

    # Regression: github-actions-auth-security must document the GitHub Actions
    # script-injection mitigation (distinct from Claude *prompt* injection):
    # untrusted run-context values bound to an intermediate `env:` variable and
    # referenced as a quoted shell variable, never interpolated `${{ … }}`
    # directly into a `run:` script. This is GitHub's single most-missed
    # secure-use item (see .claude/rules/github-actions-security.md). A bulk edit
    # that "tightens" the security section and drops the env-var indirection
    # example would silently restore the injection footgun, so assert both the
    # section heading and the concrete corrected-pattern token survive.
    if [ "$skill_name" = "github-actions-auth-security" ]; then
      for token in "Script Injection" "PR_TITLE"; do
        if ! grep -qF "$token" "$skill_file"; then
          issues+=("❌ ${plugin}/${skill_name}: SKILL.md must retain script-injection token '${token}' (env-var indirection for untrusted workflow input — see .claude/rules/github-actions-security.md)")
          has_errors=true
        fi
      done
    fi

    # Regression: git-pr-sync-check is the advisory layer of the PR-branch-sync
    # guard trio (see .claude/rules/pr-branch-sync.md). Its body must keep the
    # verdict contract that the SessionStart probe, the PreToolUse hook, and the
    # precondition cross-refs in git-commit/git-push/git-issue all speak: a single
    # `VERDICT=` line, the load-bearing `pr_merged` verdict (the stale-merged-branch
    # case the whole feature exists to catch), and `mergedAt` (the gh-json-fields.md
    # field — proves it reads merge state correctly, not a phantom `merged` field).
    if [ "$skill_name" = "git-pr-sync-check" ]; then
      for token in 'VERDICT=' 'pr_merged' 'mergedAt'; do
        if ! grep -qF "$token" "$skill_file"; then
          issues+=("❌ ${plugin}/${skill_name}: SKILL.md must retain PR-sync verdict token '${token}' (see .claude/rules/pr-branch-sync.md)")
          has_errors=true
        fi
      done
    fi

    # Regression: git-pr-watch wraps the native PR-activity subscription. Its body
    # must name `subscribe_pr_activity` (the MCP tool that makes the watch real);
    # dropping it would leave a skill that documents watching without the call.
    if [ "$skill_name" = "git-pr-watch" ]; then
      if ! grep -qF "subscribe_pr_activity" "$skill_file"; then
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md must retain 'subscribe_pr_activity' (the native PR-watch MCP tool — see .claude/rules/pr-branch-sync.md)")
        has_errors=true
      fi
    fi

    # Regression: git-pr-feedback must foreground verifying automated-reviewer
    # claims before accepting them — automated reviewers (Gemini Code Assist,
    # Copilot) produce confidently-wrong suggestions, and the fix/refute/defer
    # flow must carry a `Refuted` action (reply with the refutation + evidence,
    # do not change code). A bulk edit dropping the verification prose or the
    # Refuted row would silently restore "apply bot suggestions on trust"
    # (issue #1545).
    if [ "$skill_name" = "git-pr-feedback" ]; then
      for token in 'automated reviewer' 'Refuted'; do
        if ! grep -qF "$token" "$skill_file"; then
          issues+=("❌ ${plugin}/${skill_name}: SKILL.md must retain verify-automated-reviewer-claims token '${token}' (issue #1545)")
          has_errors=true
        fi
      done
    fi

    # Regression: execution-grounded-review is the execution-grounded verifier in
    # the agent-patterns review family — the one thing that distinguishes it from
    # adversarial-review (which reads a design) is that it RUNS the suite first
    # and grounds each acceptance criterion in EXECUTION EVIDENCE, marking a
    # criterion with no execution backing as UNVERIFIED rather than passing it on
    # appearance. A bulk edit that "tightens" the skill into another read-the-diff
    # reviewer would silently erase exactly that property, so assert the three
    # load-bearing tokens: the execute-first step, the evidence principle, and the
    # no-silent-pass coverage verdict. (See .claude/rules/loop-integrity.md.)
    if [ "$skill_name" = "execution-grounded-review" ]; then
      for token in 'Run the suite first' 'execution evidence' 'UNVERIFIED'; do
        if ! grep -qF "$token" "$skill_file"; then
          issues+=("❌ ${plugin}/${skill_name}: SKILL.md must retain execution-grounded token '${token}' (execute-first / evidence-grounded / no-silent-pass — see .claude/rules/loop-integrity.md)")
          has_errors=true
        fi
      done
    fi

    # Regression: code-review is the canary for restoring `context: fork` after
    # the plugin-skill blocker (anthropics/claude-code#16803) was fixed
    # 2026-04-18. See laurigates/claude-plugins#980 and
    # .claude/rules/skill-fork-context.md: the gate "revisit when both #16803 and
    # #33154 resolved" expired degenerately — #33154 was a Cowork product bug
    # closed as stale, never a CLI tracker — so the decision moved to an
    # empirical canary. The semantic invariant is that this single-subagent,
    # verbose-output skill carries `context: fork` so its output stays out of the
    # main context. A bulk edit silently dropping it would erase the canary and
    # the only on-disk signal that the restoration is in flight; if the [1m]
    # verification fails, removing it is a deliberate edit that updates this guard
    # and the rule together.
    if [ "$skill_name" = "code-review" ] && [ "$plugin" = "code-quality-plugin" ]; then
      if ! grep -q '^context: fork' "$skill_file"; then
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md must retain 'context: fork' (canary for the #16803 fix — see .claude/rules/skill-fork-context.md and issue #980)")
        has_errors=true
      fi
    fi

    # Regression: agent-teams must document the post-2.1.178 implicit-team model,
    # not the removed TeamCreate/TeamDelete tools. Claude Code 2.1.178 removed
    # those tools — every session has one implicit team gated on
    # CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1, and team_name is accepted-but-ignored.
    # The skill was built entirely around the removed tools, so it would have
    # instructed Claude to call tools that no longer exist (issue #1733). Anchor on
    # the two markers of the current model; a bulk edit reverting to a
    # TeamCreate-setup flow drops both. (The literal strings TeamCreate/TeamDelete
    # legitimately remain in the BREAKING note and the Common Mistakes row, so we
    # assert the *presence* of the new model rather than the absence of the words.)
    if [ "$skill_name" = "agent-teams" ] && [ "$plugin" = "agent-patterns-plugin" ]; then
      for token in 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' 'implicit team'; do
        if ! grep -qF "$token" "$skill_file"; then
          issues+=("❌ ${plugin}/${skill_name}: SKILL.md must document the implicit-team model token '${token}' (TeamCreate/TeamDelete removed in 2.1.178 — issue #1733)")
          has_errors=true
        fi
      done
    fi

    # Regression: evaluate-improve must gate any --apply on the AEGIS source-cases
    # DELTA-VERIFY: re-run the source-failure set (the eval cases that motivated
    # the edit, captured in Step 1) against the drafted candidate and confirm the
    # failure count SHRINKS before writing the live SKILL.md — not merely that the
    # aggregate golden-set pass rate rose (HarnessX/AEGIS, issue #1662). The
    # pre-existing --best-of ranked only by golden-set pass rate, which can reward
    # a candidate that lifts unrelated cases while leaving the motivating failures
    # broken. A bulk edit that drops the gate or reverts ranking to pass-rate-only
    # would silently restore that gap, so assert the three load-bearing tokens.
    if [ "$skill_name" = "evaluate-improve" ] && [ "$plugin" = "evaluate-plugin" ]; then
      for token in 'Delta-verify gate' 'source-failure set' 'shrink'; do
        if ! grep -qF "$token" "$skill_file"; then
          issues+=("❌ ${plugin}/${skill_name}: SKILL.md must retain delta-verify token '${token}' (re-run source-failure cases, confirm the count shrinks before apply — issue #1662)")
          has_errors=true
        fi
      done
    fi

    # Regression: comfyui-node-scaffold must emit a TypeScript + bun-build pack
    # consuming @laurigates/comfy-modal-kit (NOT a vanilla-JS pack with copied-in
    # modal primitives), and its biome pin must be consistent across biome.json,
    # the pre-commit hook, and CI. The previous template pinned
    # @biomejs/biome@1.9.4 in pre-commit while biome.json/CI were on 2.x — a
    # silent mismatch the pre-commit hook surfaced as a config-parse failure.
    # The templates live in the sibling scaffold.py (not the SKILL.md body), so
    # this check reads that generator. Semantic invariants:
    #   1. emits TypeScript (src/index.ts), not web/js/*.js vanilla
    #   2. consumes the shared kit via import (no copied modal-shell/-fuzzy)
    #   3. every biome pin is the same version (no 1.9.4 drift)
    if [ "$skill_name" = "comfyui-node-scaffold" ]; then
      local scaffold_py
      scaffold_py="$(dirname "$skill_file")/scaffold.py"
      if [ ! -f "$scaffold_py" ]; then
        issues+=("❌ ${plugin}/${skill_name}: scaffold.py missing next to SKILL.md")
        has_errors=true
      else
        # 1. TypeScript, not vanilla JS.
        if ! grep -q '"src/index.ts":' "$scaffold_py"; then
          issues+=("❌ ${plugin}/${skill_name}: scaffold.py must emit TypeScript 'src/index.ts' (TS+bun template, not vanilla web/js/*.js)")
          has_errors=true
        fi
        if grep -q '"web/js/' "$scaffold_py"; then
          issues+=("❌ ${plugin}/${skill_name}: scaffold.py must not emit vanilla 'web/js/*.js' — the TS source lives in src/ and builds to web/dist/")
          has_errors=true
        fi
        # 2. Consume the shared kit; never copy the primitives in.
        if ! grep -q 'comfy-modal-kit' "$scaffold_py"; then
          issues+=("❌ ${plugin}/${skill_name}: scaffold.py modal variants must consume @laurigates/comfy-modal-kit (the dependency + import)")
          has_errors=true
        fi
        if grep -Eq 'shutil\.copy|modal-shell\.js"|modal-fuzzy\.js"' "$scaffold_py"; then
          issues+=("❌ ${plugin}/${skill_name}: scaffold.py must not copy modal-shell.js/modal-fuzzy.js into the pack — consume the kit instead")
          has_errors=true
        fi
        # 3. biome pin consistency: every generated biome pin must flow from the
        #    single @@BIOME_VERSION@@ token, never a hard-coded version. No stale
        #    1.x literal pin (the original bug), and a single-source constant.
        if grep -Eq '@biomejs/biome@1\.[0-9]' "$scaffold_py"; then
          issues+=("❌ ${plugin}/${skill_name}: scaffold.py pins a stale 1.x @biomejs/biome — must use @@BIOME_VERSION@@ (2.x)")
          has_errors=true
        fi
        if ! grep -q '^BIOME_VERSION = ' "$scaffold_py"; then
          issues+=("❌ ${plugin}/${skill_name}: scaffold.py must single-source the biome pin in a BIOME_VERSION constant")
          has_errors=true
        fi
        # Any hard-coded biome version pin in a template (a literal X.Y.Z next to
        # 'biome', rather than the @@BIOME_VERSION@@ token) can drift — reject it.
        if grep -Eq 'biome[^@]*@[0-9]+\.[0-9]+\.[0-9]+|biome/schemas/[0-9]+\.[0-9]+\.[0-9]+' "$scaffold_py"; then
          issues+=("❌ ${plugin}/${skill_name}: scaffold.py hard-codes a biome version in a template — use the @@BIOME_VERSION@@ token so all pins stay in lockstep")
          has_errors=true
        fi
      fi
    fi

    # Regression: feedback-session Step 1a silently filed against the cwd git
    # remote even when the session's tool calls were dominated by a different
    # plugin/source repo (issue #1425). The semantic invariant is that the
    # dominant-source scan runs for BOTH the cwd-with-remote and the no-remote
    # cases, and that a mismatch between the dominant source and the cwd remote
    # surfaces a confirmation prompt rather than silently using the cwd repo.
    # Two literal strings anchor the fix:
    #   "Mismatch detected" — the mismatch-confirmation prompt heading
    #   "SUGGESTED_REPO" in the cwd-remote-present branch — proves the dominant
    #     source is compared against the cwd remote, not only used as fallback
    if [ "$skill_name" = "feedback-session" ]; then
      if ! grep -q "Mismatch detected" "$skill_file"; then
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md must include 'Mismatch detected' mismatch-confirmation prompt in Step 1a (issue #1425)")
        has_errors=true
      fi
      if ! grep -q "dominant source differs from" "$skill_file"; then
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md must include the cwd-remote-vs-dominant-source branch ('dominant source differs from') in Step 1a decision table (issue #1425)")
        has_errors=true
      fi
    fi

    # Regression: configure-web-session had no drift signal for already-onboarded
    # repos — an existing install_pkgs.sh read as compliant even after the canonical
    # spec moved on (Renovate pins, path-bootstrap.sh wired first, allowlist-safe
    # download URLs), so 7/7 repos silently fell out of spec (issue #1670). The
    # semantic invariant is that the skill carries a drift-detection step for the
    # already-onboarded case plus a portfolio re-audit sweep. Two literals anchor
    # the fix; dropping either erases the drift signal.
    if [ "$skill_name" = "configure-web-session" ]; then
      for token in 'spec drift' 're-audit'; do
        if ! grep -qiF "$token" "$skill_file"; then
          issues+=("❌ ${plugin}/${skill_name}: SKILL.md must retain drift/re-audit token '${token}' for already-onboarded repos (issue #1670)")
          has_errors=true
        fi
      done
    fi

    # Regression: configure-release-please documented only the legacy
    # MY_RELEASE_PLEASE_TOKEN PAT as the canonical release token, with no mention
    # of the GitHub App-token pattern that is the laurigates org standard
    # (gitops provisions RELEASE_PLEASE_APP_ID / RELEASE_PLEASE_PRIVATE_KEY on
    # release_please=true repos). Following the skill verbatim produced a PAT
    # workflow that diverges from every other repo and never consumes the
    # gitops credentials (issue #1789). The semantic invariant is that the
    # SKILL.md body advertises the App-token pattern as a (preferred) option.
    # Two literals anchor the fix; dropping either erases the App-token guidance.
    if [ "$skill_name" = "configure-release-please" ]; then
      for token in 'create-github-app-token' 'RELEASE_PLEASE_APP_ID'; do
        if ! grep -qF "$token" "$skill_file"; then
          issues+=("❌ ${plugin}/${skill_name}: SKILL.md must document the GitHub App-token pattern token '${token}' alongside the PAT (issue #1789)")
          has_errors=true
        fi
      done
    fi
  done < <(find "$skills_dir" -type f \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)

  if $has_errors; then
    return 2
  fi

  return 0
}

# Check 4: marketplace.json entry
check_marketplace() {
  local plugin="$1"
  local marketplace_file=".claude-plugin/marketplace.json"

  if [ ! -f "$marketplace_file" ]; then
    issues+=("❌ ${plugin}: Missing .claude-plugin/marketplace.json")
    return 2
  fi

  local entry
  entry=$(jq --arg plugin "$plugin" '.plugins[] | select(.name == $plugin)' "$marketplace_file" 2>/dev/null)

  if [ -z "$entry" ]; then
    issues+=("❌ ${plugin}: No entry in marketplace.json")
    return 2
  fi

  local mp_name mp_source mp_description mp_version
  mp_name=$(echo "$entry" | jq -r '.name // ""')
  mp_source=$(echo "$entry" | jq -r '.source // ""')
  mp_description=$(echo "$entry" | jq -r '.description // ""')
  mp_version=$(echo "$entry" | jq -r '.version // ""')

  local missing_fields=()
  [ -z "$mp_name" ] && missing_fields+=("name")
  [ -z "$mp_source" ] && missing_fields+=("source")
  [ -z "$mp_description" ] && missing_fields+=("description")
  [ -z "$mp_version" ] && missing_fields+=("version")

  local expected_source="./${plugin}"
  if [ -n "$mp_source" ] && [ "$mp_source" != "$expected_source" ]; then
    missing_fields+=("source (expected '${expected_source}', got '${mp_source}')")
  fi

  if [ ${#missing_fields[@]} -gt 0 ]; then
    recommendations+=("⚠️ ${plugin}: marketplace.json entry issues: ${missing_fields[*]}")
    return 1
  fi

  return 0
}

# Check 5: release-please config
check_release_config() {
  local plugin="$1"
  local config_file="release-please-config.json"
  local manifest_file=".release-please-manifest.json"

  local has_errors=false

  if [ ! -f "$config_file" ]; then
    issues+=("❌ ${plugin}: Missing release-please-config.json")
    has_errors=true
  else
    local config_entry
    config_entry=$(jq --arg plugin "$plugin" '.packages[$plugin]' "$config_file" 2>/dev/null)
    if [ "$config_entry" = "null" ] || [ -z "$config_entry" ]; then
      issues+=("❌ ${plugin}: Not in release-please-config.json packages")
      has_errors=true
    fi
  fi

  if [ ! -f "$manifest_file" ]; then
    issues+=("❌ ${plugin}: Missing .release-please-manifest.json")
    has_errors=true
  else
    local manifest_entry
    manifest_entry=$(jq --arg plugin "$plugin" '.[$plugin]' "$manifest_file" 2>/dev/null)
    if [ "$manifest_entry" = "null" ] || [ -z "$manifest_entry" ]; then
      issues+=("❌ ${plugin}: Not in .release-please-manifest.json")
      has_errors=true
    fi
  fi

  if $has_errors; then
    return 2
  fi

  return 0
}

# Check 6: Shell utility patterns without scripts
# Regression: health-check used Bash(test *), Bash(jq *) etc. causing ~20 individual
# approval prompts. Skills with shell utility patterns should use standalone scripts.
check_bash_patterns() {
  local plugin="$1"
  local skills_dir="${plugin}/skills"

  if [ ! -d "$skills_dir" ]; then
    return 0
  fi

  local skill_files=()
  while IFS= read -r -d '' f; do
    skill_files+=("$f")
  done < <(find "$skills_dir" -type f \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)

  if [ ${#skill_files[@]} -eq 0 ]; then
    return 0
  fi

  # Shell utilities that indicate inline scripting (not primary CLI tools)
  # shellcheck disable=SC2034  # documents the canonical list; loop below enumerates
  local shell_utils="test|jq|head|tail|cat|cp|mkdir|chmod|wc|date|ls|find"
  local has_warnings=false

  for skill_file in "${skill_files[@]}"; do
    local skill_name
    skill_name=$(basename "$(dirname "$skill_file")")

    local fm_allowed_tools
    fm_allowed_tools=$(extract_field "$skill_file" "allowed-tools")
    [ -z "$fm_allowed_tools" ] && continue

    # Count shell utility Bash patterns
    local util_count=0
    local util_list=""
    for util in test jq head tail cat cp mkdir chmod wc date; do
      if echo "$fm_allowed_tools" | grep -qE "Bash\(${util} "; then
        util_count=$((util_count + 1))
        util_list="${util_list:+${util_list}, }${util}"
      fi
    done

    # Warn if 3+ shell utility patterns and no scripts/ directory
    if [ "$util_count" -ge 3 ]; then
      local scripts_dir
      scripts_dir="$(dirname "$skill_file")/scripts"
      if [ ! -d "$scripts_dir" ]; then
        recommendations+=("⚠️ ${plugin}/${skill_name}: ${util_count} shell utility Bash patterns (${util_list}) — consider consolidating into scripts/ with Bash(bash *)")
        has_warnings=true
      fi
    fi
  done

  if $has_warnings; then
    return 1
  fi

  return 0
}

# Check 7: Skill description quality for auto-invocation and listing-budget length
# Regression A: skills whose description lacks a "Use when..." trigger clause are
# not matched by Claude's auto-invocation heuristic, so they rarely fire without
# explicit user instruction. See .claude/rules/skill-quality.md "Description
# Quality" checklist.
# Regression B: overly verbose descriptions eat the listing budget faster than
# they earn invocation accuracy. The May 2026 tightening pass brought every
# description below 250 chars; this gate keeps new contributions inside the
# target band (≤200 OK, 201-300 WARN, >300 ERROR). See .claude/rules/skill-quality.md
# "Description Length and the Listing Budget".
# Delegates to scripts/audit-skill-descriptions.py which handles multi-line YAML
# block scalars correctly.
check_skill_descriptions() {
  local plugin="$1"
  local skills_dir="${plugin}/skills"

  if [ ! -d "$skills_dir" ]; then
    return 0
  fi

  local audit_script="scripts/audit-skill-descriptions.py"
  if [ ! -f "$audit_script" ] || ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi

  local audit_json
  if ! audit_json=$(python3 "$audit_script" --plugin "$plugin" --json 2>/dev/null); then
    return 0
  fi

  local has_errors=false
  local has_warnings=false

  # Trigger axis: MISSING/EMPTY → error, NO_TRIGGER on auto-invokable → warn
  while IFS=$'\t' read -r category skill_path auto; do
    [ -z "$category" ] && continue
    local skill_slug
    skill_slug=$(basename "$(dirname "$skill_path")")
    case "$category" in
      MISSING|EMPTY)
        issues+=("❌ ${plugin}/${skill_slug}: description is ${category} — Claude cannot auto-invoke this skill")
        has_errors=true
        ;;
      NO_TRIGGER)
        if [ "$auto" = "true" ]; then
          recommendations+=("⚠️ ${plugin}/${skill_slug}: description lacks a \"Use when...\" trigger clause — Claude may not auto-invoke this skill (see .claude/rules/skill-quality.md)")
          has_warnings=true
        fi
        ;;
    esac
  done < <(echo "$audit_json" | jq -r '.[] | select(.category != "OK") | [.category, .path, (.auto_invokable | tostring)] | @tsv')

  # Length axis: WARN (201-300) → recommendation, ERROR (>300) → fail
  while IFS=$'\t' read -r length_category length skill_path; do
    [ -z "$length_category" ] && continue
    local skill_slug
    skill_slug=$(basename "$(dirname "$skill_path")")
    case "$length_category" in
      WARN)
        recommendations+=("⚠️ ${plugin}/${skill_slug}: description is ${length} chars — over the 200-char target band (see .claude/rules/skill-quality.md)")
        has_warnings=true
        ;;
      ERROR)
        issues+=("❌ ${plugin}/${skill_slug}: description is ${length} chars — exceeds the 300-char hard limit; rewrite before merge (see .claude/rules/skill-quality.md)")
        has_errors=true
        ;;
    esac
  done < <(echo "$audit_json" | jq -r '.[] | select(.length_category == "WARN" or .length_category == "ERROR") | [.length_category, (.length | tostring), .path] | @tsv')

  if $has_errors; then
    return 2
  elif $has_warnings; then
    return 1
  fi
  return 0
}

# Check 8: "When to Use This Skill" section presence
# Regression: Wave 3 issue draining (umbrella issue #1156) swept every plugin's
# skills to comply with .claude/rules/skill-quality.md (lines 27-38), which
# requires every SKILL.md to have a `## When to Use This Skill` heading
# immediately followed by a markdown table. This check keeps the tree compliant.
check_skill_when_to_use() {
  local plugin="$1"
  local skills_dir="${plugin}/skills"

  if [ ! -d "$skills_dir" ]; then
    return 0
  fi

  local skill_files=()
  while IFS= read -r -d '' f; do
    skill_files+=("$f")
  done < <(find "$skills_dir" -type f \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)

  if [ ${#skill_files[@]} -eq 0 ]; then
    return 0
  fi

  local has_errors=false

  for skill_file in "${skill_files[@]}"; do
    local skill_name
    skill_name=$(basename "$(dirname "$skill_file")")

    # Find the heading line number (exact match, anchored).
    local heading_line
    heading_line=$(grep -n '^## When to Use This Skill$' "$skill_file" | head -1 | cut -d: -f1)

    if [ -z "$heading_line" ]; then
      issues+=("❌ ${plugin}/${skill_name}: SKILL.md missing '## When to Use This Skill' heading (see .claude/rules/skill-quality.md)")
      has_errors=true
      continue
    fi

    # Look for a markdown table row (line starting with '|') within ~10 lines
    # after the heading. The blank line and the table header both count as
    # acceptable interleaving — we only need the first '|' to appear by then.
    local window_start=$((heading_line + 1))
    local window_end=$((heading_line + 10))
    local table_line
    table_line=$(awk -v start="$window_start" -v end="$window_end" \
      'NR >= start && NR <= end && /^\|/ { print NR; exit }' "$skill_file")

    if [ -z "$table_line" ]; then
      issues+=("❌ ${plugin}/${skill_name}: SKILL.md '## When to Use This Skill' heading at line ${heading_line} not followed by a markdown table within 10 lines")
      has_errors=true
    fi
  done

  if $has_errors; then
    return 2
  fi

  return 0
}

# Check 9: Skill body size
# The cost a SKILL.md body imposes once loaded is *tokens*, not lines — and
# lines are a poor token proxy (chars/line varies ~3.6x across this repo, so
# equal line counts can differ 2-3x in tokens). We gate on bytes (≈ characters
# via `wc -c`), the cheapest tight proxy for tokens (~4 chars/token for English
# prose), and surface an estimated token count (chars/4, matching the
# description-budget convention in .claude/rules/skill-quality.md). Thresholds:
#   ≤ 10000 chars (~2500 tok)        → OK (silent)
#   10001 – 26000 (~2500-6500 tok)   → WARN (review for REFERENCE.md / scripts/ extraction)
#   > 26000 chars (~6500 tok)        → ERROR (exceeds ceiling — must extract before merge)
# 26000 chars ≈ Anthropic's published 500-line body guidance at this repo's
# median line density. See .claude/rules/skill-quality.md "Size Limits".
check_skill_size() {
  local plugin="$1"
  local skills_dir="${plugin}/skills"

  if [ ! -d "$skills_dir" ]; then
    return 0
  fi

  local has_errors=false
  local has_warnings=false

  while IFS= read -r -d '' skill_file; do
    local skill_name
    skill_name=$(basename "$(dirname "$skill_file")")

    local char_count est_tokens
    char_count=$(wc -c < "$skill_file" | tr -d ' ')
    est_tokens=$(( char_count / 4 ))

    if [ "$char_count" -gt 26000 ]; then
      issues+=("❌ ${plugin}/${skill_name}: SKILL.md is ${char_count} chars (~${est_tokens} tokens, >26000 ceiling) — extract content to REFERENCE.md or scripts/ (see .claude/rules/skill-quality.md)")
      has_errors=true
    elif [ "$char_count" -gt 10000 ]; then
      recommendations+=("⚠️ ${plugin}/${skill_name}: SKILL.md is ${char_count} chars (~${est_tokens} tokens, >10000) — consider extracting to REFERENCE.md or scripts/ (ceiling: 26000 chars / ~6500 tokens)")
      has_warnings=true
    fi
  done < <(find "$skills_dir" -type f \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)

  if $has_errors; then
    return 2
  elif $has_warnings; then
    return 1
  fi

  return 0
}

# Main check loop
for i in "${!PLUGINS[@]}"; do
  plugin="${PLUGINS[$i]}"

  if [ ! -d "$plugin" ]; then
    issues+=("❌ ${plugin}: Directory not found")
    results_json+=("❌")
    results_frontmatter+=("❌")
    results_body+=("❌")
    results_marketplace+=("❌")
    results_release+=("❌")
    results_bash+=("❌")
    results_desc+=("❌")
    results_when_to_use+=("❌")
    results_size+=("❌")
    results_overall+=("❌")
    overall_failed=true
    continue
  fi

  # Run checks (capture exit codes without triggering set -e)
  json_status=0; check_plugin_json "$plugin" || json_status=$?
  frontmatter_status=0; check_skill_frontmatter "$plugin" || frontmatter_status=$?
  body_status=0; check_skill_body "$plugin" || body_status=$?
  marketplace_status=0; check_marketplace "$plugin" || marketplace_status=$?
  release_status=0; check_release_config "$plugin" || release_status=$?
  bash_status=0; check_bash_patterns "$plugin" || bash_status=$?
  desc_status=0; check_skill_descriptions "$plugin" || desc_status=$?
  when_to_use_status=0; check_skill_when_to_use "$plugin" || when_to_use_status=$?
  size_status=0; check_skill_size "$plugin" || size_status=$?

  results_json+=("$(to_symbol $json_status)")
  results_frontmatter+=("$(to_symbol $frontmatter_status)")
  results_body+=("$(to_symbol $body_status)")
  results_marketplace+=("$(to_symbol $marketplace_status)")
  results_release+=("$(to_symbol $release_status)")
  results_bash+=("$(to_symbol $bash_status)")
  results_desc+=("$(to_symbol $desc_status)")
  results_when_to_use+=("$(to_symbol $when_to_use_status)")
  results_size+=("$(to_symbol $size_status)")

  # Overall: ❌ if any ❌, ⚠️ if any ⚠️, ✅ if all ✅
  plugin_overall="✅"
  for status in $json_status $frontmatter_status $body_status $marketplace_status $release_status $bash_status $desc_status $when_to_use_status $size_status; do
    if [ "$status" -ge 2 ]; then
      plugin_overall="❌"
      overall_failed=true
      break
    elif [ "$status" -eq 1 ]; then
      plugin_overall="⚠️"
    fi
  done
  results_overall+=("$plugin_overall")
done

# Output report
echo "## Plugin Compliance Review"
echo ""
echo "| Plugin | plugin.json | Frontmatter | Body | Marketplace | Release Config | Bash Patterns | Descriptions | When-to-Use | Size | Overall |"
echo "|--------|-------------|-------------|------|-------------|----------------|---------------|--------------|-------------|------|---------|"

for i in "${!PLUGINS[@]}"; do
  echo "| ${PLUGINS[$i]} | ${results_json[$i]} | ${results_frontmatter[$i]} | ${results_body[$i]} | ${results_marketplace[$i]} | ${results_release[$i]} | ${results_bash[$i]} | ${results_desc[$i]} | ${results_when_to_use[$i]} | ${results_size[$i]} | ${results_overall[$i]} |"
done

echo ""

# Issues section
if [ ${#issues[@]} -gt 0 ]; then
  echo "### Issues Found"
  echo ""
  for issue in "${issues[@]}"; do
    echo "- $issue"
  done
  echo ""
fi

# Recommendations section
if [ ${#recommendations[@]} -gt 0 ]; then
  echo "### Recommendations"
  echo ""
  for rec in "${recommendations[@]}"; do
    echo "- $rec"
  done
  echo ""
fi

if $overall_failed; then
  exit 1
fi

exit 0

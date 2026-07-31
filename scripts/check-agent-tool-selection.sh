#!/usr/bin/env bash
# Verify every plugin agent .md file embeds a "## Tool Selection" section in
# its body, so the most-violated bash-vs-harness rules ride along in the
# agent's system prompt rather than relying on inherited memory — and that no
# agent body instructs ancestry-based branch DELETION.
#
# Background: agent threads do not reliably load `~/.claude/rules/*.md`, so
# rules like "use Glob, not find" produced 200+ weekly hook reminders even
# though the same guidance lived in the user's rule files. The fix is to
# bake the rules into each agent's system prompt — see issue #1109.
#
# What counts as compliant:
#   - The agent file contains a literal `## Tool Selection` heading.
#   - The section mentions both `Glob` and `Grep` (a coarse content sniff
#     that catches the "section exists but is empty / placeholder-only"
#     failure mode).
#   - No line instructs ancestry-based branch cleanup (see below).
#
# Regression: agents-plugin/agents/*.md, testing-plugin/agents/test-runner.md,
# friction-learner.md, and the rest had no Tool Selection section, so each
# spawned thread re-discovered the bash hook blocks (issue #1109).
#
# Regression (ancestry-based branch deletion): git-plugin/agents/git-ops.md
# shipped `git branch --merged main | grep -v ... | xargs git branch -d` in an
# always-on agent prompt. `git branch --merged` is an ANCESTRY check, so it
# under-reports on every squash-merge repo (the release-please default): a
# squash collapses a branch into one fresh-SHA commit, so the branch's own
# commits are never ancestors and a fully-landed branch reads as unmerged.
# Piping that into `xargs git branch -d` is a delete loop keyed on a signal
# known to be wrong — the SAME defect already fixed for `git-plugin:deadbranch`
# (issue #1869, recorded in .claude/rules/regression-testing.md). `-d` refuses
# the unsafe deletes today, but the classification is still wrong and the usual
# "fix" for the refusals is `-D`, which deletes real work.
#
# The two accepted signals survive a squash-merge and are what an agent should
# be told to use instead:
#   gh pr list --state all --head <branch> --json state,mergedAt   (authoritative)
#   git cherry main <branch>                                        ('-' = upstream)
# or the encoded recipe `just -g branch-audit`. See
# `~/.claude/rules/pr-merge-hazards.md` #1.
#
# Detection is a per-line shape denylist (the accepted form for this repo's
# denylist lints — see issue #2009, which deliberately did NOT migrate them to
# the tree-sitter helper because they carry no fence/table state machine):
#   (a) `git branch [-flags] --merged` at the START of a line — a command an
#       agent will run, not a prose mention. Teaching prose embeds the command
#       mid-sentence in backticks, so it never matches.
#   (b) `--merged` and a `branch -d`/`-D` composed on ONE line — the xargs
#       one-liner, wherever it sits.
#
# Usage:
#   bash scripts/check-agent-tool-selection.sh             # all agents
#   bash scripts/check-agent-tool-selection.sh path/to/agent.md ...
#
# Exit codes:
#   0 - all agents compliant
#   1 - one or more agents missing the section or instructing an unsafe delete

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# Paths exempt from the ancestry-based-branch-cleanup check. `experiments/claude-probe/`
# uses the broken idiom DELIBERATELY as a trap fixture — its whole purpose is to test
# whether a model notices that `git branch --merged` omits a squash-merged branch
# (see experiments/claude-probe/docs/trap-corpus.md and
# experiments/claude-probe/fixtures/trap-branch-merge/setup.sh). Default discovery
# below only walks `*-plugin/agents/*.md`, so the probe is already out of reach; this
# entry keeps it exempt if discovery is ever widened or a probe file is passed
# explicitly — exactly the drift that would otherwise break the experiment.
# Matched as a path PREFIX. Test seam: CHECK_AGENT_TOOL_SELECTION_ALLOWLIST
# (whitespace-separated) extends it.
BRANCH_CLEANUP_ALLOWLIST=("experiments/claude-probe/")
# shellcheck disable=SC2206  # intentional word-split of the test-seam env var
BRANCH_CLEANUP_ALLOWLIST+=(${CHECK_AGENT_TOOL_SELECTION_ALLOWLIST:-})

# is_branch_cleanup_allowlisted <file> — true if the file sits under an allowlist prefix.
is_branch_cleanup_allowlisted() {
  local candidate="${1#./}"
  local entry
  for entry in ${BRANCH_CLEANUP_ALLOWLIST[@]+"${BRANCH_CLEANUP_ALLOWLIST[@]}"}; do
    entry="${entry#./}"
    [ -z "$entry" ] && continue
    case "$candidate" in
      "$entry"* | */"$entry"*) return 0 ;;
    esac
  done
  return 1
}

# Collect agent files. If args were passed, use those; otherwise discover
# every `*-plugin/agents/*.md` (excluding .claude-plugin and node_modules).
agent_files=()
if [ $# -gt 0 ]; then
  for arg in "$@"; do
    agent_files+=("$arg")
  done
else
  while IFS= read -r -d '' agent_file; do
    agent_files+=("$agent_file")
  done < <(
    find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0 \
      | xargs -0 -I {} find {} -path '*/agents/*.md' -type f -print0
  )
fi

if [ ${#agent_files[@]} -eq 0 ]; then
  echo "No agent files found"
  exit 0
fi

errors=0
checked=0

for agent_file in "${agent_files[@]}"; do
  [ -f "$agent_file" ] || continue
  checked=$((checked + 1))

  if ! grep -qE '^## Tool Selection$' "$agent_file"; then
    echo "❌ $agent_file: missing '## Tool Selection' section" >&2
    errors=$((errors + 1))
    continue
  fi

  # Coarse content sniff — make sure the section names both alternatives the
  # canonical block calls out, not just a placeholder heading.
  if ! grep -q 'Glob' "$agent_file" || ! grep -q 'Grep' "$agent_file"; then
    echo "❌ $agent_file: '## Tool Selection' section does not mention Glob and Grep" >&2
    errors=$((errors + 1))
    continue
  fi

  # Ancestry-based branch cleanup — a delete loop keyed on a signal that is wrong
  # on every squash-merge repo. See the header block for the full rationale.
  if is_branch_cleanup_allowlisted "$agent_file"; then
    continue
  fi

  # (a) a `git branch ... --merged` COMMAND at the start of a line, and
  # (b) `--merged` composed with a branch delete on one line (the xargs one-liner).
  # Both are read from the file once; a here-string feeds grep -q so an early
  # pipe close cannot fake a failure under pipefail (shell-pipefail-grep-q rule).
  file_body="$(cat "$agent_file")"
  cleanup_hits="$(grep -nE '^[[:space:]]*git[[:space:]]+branch([[:space:]]+-[^[:space:]]+)*[[:space:]]+--merged' <<<"$file_body" || true)"
  compose_hits="$(grep -nE '\-\-merged.*branch[[:space:]]+-[dD]([[:space:]]|$)' <<<"$file_body" || true)"

  if [ -n "$cleanup_hits" ] || [ -n "$compose_hits" ]; then
    echo "❌ $agent_file: instructs ancestry-based branch cleanup." >&2
    # Both rules can match the same line (the xargs one-liner trips (a) and (b)) —
    # sort -u by line number so each offending line is reported once.
    printf '%s\n' "$cleanup_hits" "$compose_hits" | grep -v '^$' | sort -u -t: -k1,1n | sed 's/^/     /' >&2
    echo "   \`git branch --merged\` is an ANCESTRY check: it misses every" >&2
    echo "   squash-merged branch, so a fully-landed branch reads as unmerged." >&2
    echo "   Deleting on it is the defect already fixed for deadbranch (#1869)." >&2
    echo "   Use \`just -g branch-audit\`, or classify with a squash-surviving signal:" >&2
    echo "     gh pr list --state all --head <branch> --json state,mergedAt   # authoritative" >&2
    echo "     git cherry main <branch>                                        # '-' = upstream" >&2
    echo "   See ~/.claude/rules/pr-merge-hazards.md #1." >&2
    errors=$((errors + 1))
    continue
  fi
done

if [ $errors -gt 0 ]; then
  echo "" >&2
  echo "Found $errors non-compliant agent file(s) (out of $checked checked)." >&2
  echo "Each plugin agent must embed the Tool Selection block (issue #1109) and must" >&2
  echo "not instruct ancestry-based branch deletion (issue #1869)." >&2
  exit 1
fi

echo "All $checked agent files have a Tool Selection section and no ancestry-based branch cleanup. ✅"
exit 0

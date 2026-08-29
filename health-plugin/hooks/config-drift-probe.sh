#!/usr/bin/env bash
# config-drift-probe.sh — SessionStart probe for Claude rules/skills hygiene.
#
# Surfaces drift in the configuration corpus itself: a pointer stub naming a
# skill that no longer exists, byte-identical duplicate rules across scopes, a
# rule whose topic an existing skill already covers, and an always-loaded
# budget that has crept past its ceiling.
#
# Mounts the EXISTING sweep (../scripts/config-drift.py) on the existing
# drift-protocol trigger. Per .claude/rules/drift-detection-triggering.md the
# missing piece for this class was never the logic, only the trigger, so this
# file deliberately contains no analysis of its own -- it shells out and
# forwards findings.
#
# Cost: runs `--fast --no-embed`, which is pure stdlib and spawns no git.
# Measured 2026-08-29 at this repo's root -- 0.33s wall (best of 5) over a
# corpus of 98 rules + 422 skills + 21 agents + 3 CLAUDE.md. The former figure
# here, 0.05s over "342 rules + 549 skills", named a corpus this root does not
# have and was an order of magnitude off (#2530).
#
# The no-debounce conclusion is UNCHANGED and the argument for it survives the
# correction: the debounce guidance in drift-detection-triggering.md is about
# NETWORK round-trips, and this probe makes none -- it reads local files and
# a local cache. The expensive semantic pass (an embedding model) is
# scheduled-only and never runs here.
#
# Opt-out: CLAUDE_HOOKS_DISABLE_DRIFT_NUDGE=1 (honoured by the aggregator too),
# or CLAUDE_HOOKS_DISABLE_CONFIG_DRIFT=1 for this probe alone.

set -uo pipefail

if [ "${CLAUDE_HOOKS_DISABLE_CONFIG_DRIFT:-0}" = "1" ]; then
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Same fallback chain as health-drift-probe.sh: the monorepo-relative path only
# resolves in a checkout of claude-plugins, not in an installed plugin.
PROTO_LIB="${SCRIPT_DIR}/../../hooks-plugin/hooks/lib/drift-protocol.sh"
if [ ! -f "$PROTO_LIB" ]; then
    for candidate in \
        "${CLAUDE_PLUGIN_ROOT:-}/../hooks-plugin/hooks/lib/drift-protocol.sh" \
        "$HOME/.claude/plugins/hooks-plugin/hooks/lib/drift-protocol.sh"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            PROTO_LIB="$candidate"
            break
        fi
    done
fi
if [ ! -f "$PROTO_LIB" ]; then
    exit 0
fi
# shellcheck source=../../hooks-plugin/hooks/lib/drift-protocol.sh
# shellcheck disable=SC1091  # PROTO_LIB resolves at runtime via fallback chain
. "$PROTO_LIB"

drift_init "config-drift"

ANALYZER="${SCRIPT_DIR}/../scripts/config-drift.py"
if [ ! -f "$ANALYZER" ] || ! command -v python3 >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    drift_emit
    exit 0
fi

# The analyzer's stderr is CAPTURED, not discarded. Discarding it made a dead
# analyzer indistinguishable from a clean corpus: on empty output this block
# fell through to a bare `drift_emit`, whose empty `findings` array IS the
# "checked, no drift" verdict per hooks-plugin/hooks/lib/drift-protocol.sh, and
# the hook exited 0. The analyzer now imports `lib.probe`, so it CAN die before
# printing anything (ModuleNotFoundError, a syntax error in the module) — a
# failure class the import-free version could not have. This hook introduced the
# consumer, so it owes the detection.
ERRFILE=$(mktemp) || ERRFILE=""
if [ -n "$ERRFILE" ]; then
    trap 'rm -f "$ERRFILE"' EXIT
fi

# --fast: read cached git dates only, never spawn git. --no-embed: no model, no
# download. Both keep this inside a SessionStart budget.
if [ -n "$ERRFILE" ]; then
    OUT=$(python3 "$ANALYZER" --root "${DRIFT_CWD:-.}" --fast --no-embed --format=json 2>"$ERRFILE")
else
    OUT=$(python3 "$ANALYZER" --root "${DRIFT_CWD:-.}" --fast --no-embed --format=json 2>/dev/null)
fi
ANALYZER_RC=$?

if [ -z "$OUT" ] || ! printf '%s' "$OUT" | jq empty >/dev/null 2>&1; then
    # THE OUTPUT IS THE DISCRIMINATOR, NOT THE EXIT CODE. `--format=json` prints
    # its document unconditionally — an empty corpus still yields
    # `{"findings": [], ...}` — so empty-or-unparseable stdout is by itself
    # proof the analyzer did not complete. The exit code cannot narrow that:
    # exit 1 is NORMAL (returned for any error/warn finding, alongside a full
    # document, which never reaches this branch), and exit 0 with nothing on
    # stdout is a truncated or 0-byte analyzer — an interrupted plugin install,
    # a partial write. There is no benign exit-0-with-unparseable-output case.
    #
    # Gating on `[ "$ANALYZER_RC" -ne 0 ]` here therefore let exit-0 emptiness
    # fall through to a bare `drift_emit`, whose empty `findings` array IS the
    # "checked, no drift" verdict per hooks-plugin/hooks/lib/drift-protocol.sh —
    # a false all-clear written by a dead analyzer. So: always report. The exit
    # code and stderr only choose the wording and the severity.

    # Prefer the last line that LOOKS like a Python exception over the last line
    # outright. A traceback's exception line is not reliably last: `atexit`
    # handlers, CPython's `Exception ignored in: <_io.TextIOWrapper ...>` at
    # interpreter shutdown, and wrapping python3 shims (mise/asdf/uv) all write
    # after it, and `tail -n 1` then names that noise and DISCARDS the real
    # exception. `tail -n 1` stays as the fallback for a non-Python failure
    # (a shim that cannot find an interpreter writes no exception at all).
    DETAIL=""
    if [ -n "$ERRFILE" ] && [ -s "$ERRFILE" ]; then
        DETAIL=$(grep -E '^[A-Za-z_.]*(Error|Exception):' "$ERRFILE" 2>/dev/null | tail -n 1)
        [ -n "$DETAIL" ] || DETAIL=$(tail -n 1 "$ERRFILE" 2>/dev/null)
        DETAIL=$(printf '%s' "$DETAIL" | tr -d '\000' | cut -c1-300)
    fi

    SEVERITY="error"
    KIND="analyzer_failed"
    SUMMARY="config-drift analyzer failed: ${DETAIL:-analyzer exited $ANALYZER_RC with no parseable output}"

    if [ "$ANALYZER_RC" = "3" ]; then
        # Exit 3 is config-drift.py's ARGUMENT-VALIDATION return (`root not
        # found`), not a failure — the analyzer is healthy and is refusing a bad
        # --root. A `cwd` that is not a directory would otherwise raise a
        # permanent `error`/`analyzer_failed` nudge claiming the analyzer is
        # broken, and send the reader to `/health:check` to look for a bug that
        # is not there.
        SEVERITY="warn"
        KIND="analyzer_bad_root"
        SUMMARY="config-drift skipped: ${DETAIL:-root not found}"
    else
        case "$DETAIL" in
            FileNotFoundError:* | NotADirectoryError:* | IsADirectoryError:* | \
                PermissionError:* | UnicodeDecodeError:* | OSError:*)
                # The analyzer is fine; a file in the CORPUS could not be read.
                #
                # This arm is a BACKSTOP, not the primary path. `collect()` no
                # longer crashes on an unreadable corpus file: it skips the entry
                # and the analyzer reports it itself as a `corpus_unreadable`
                # finding, which is strictly better (the sweep still runs, and
                # every unreadable path is named rather than just the first).
                # What reaches here is an uncaught read from somewhere else in
                # the analyzer. Do not delete it on the grounds that nothing
                # currently reaches it — the cost is one `case` arm, and the
                # failure it catches is otherwise reported as "the analyzer
                # failed", which points the reader at the wrong artifact.
                # "the analyzer failed" points the reader at the wrong artifact,
                # and `error` pins this to slot 1 of the aggregator's 5 lines
                # (drift-aggregator.sh sorts error first, across ALL plugins) on
                # every SessionStart until a human finds the file. The exception
                # text carries the offending path, which is what actually locates
                # it.
                SEVERITY="warn"
                KIND="corpus_unreadable"
                SUMMARY="config-drift could not read a file in the config corpus: $DETAIL"
                ;;
        esac
    fi

    drift_add_finding "$SEVERITY" "$KIND" "$SUMMARY" "/health:check"
    drift_emit
    exit 0
fi

# Forward at most 4 findings. The aggregator caps at 5 lines across ALL plugins,
# so a greedy probe crowds out its siblings. Findings are collapsed by kind:
# 74 stale-review entries must read as one actionable nudge, not 74 identical
# ones.
#
# The `fix` map below is now the SINGLE SOURCE for kind -> remediation-skill.
# It used to be one of two copies: config-drift.py carried a `--format=probe`
# renderer with its own map, which no caller ever invoked and which had already
# drifted (it was missing `coverage_metric_broken` and
# `semantic_overlap_rule_skill`, both of which this one has). That renderer and
# its `--format` choice were deleted, so this map is load-bearing rather than a
# duplicate: adding a `kind` to config-drift.py without adding a row here routes
# it to the `/health:check` fallback silently.
#
# The map is therefore COMPLETE over every kind the analyzer can emit, and
# `test-probe-lib.sh` TEST N3 pins that: it derives the kind set from
# config-drift.py's own `Finding(...)` call sites and asserts each has an
# explicit row here. `corpus_unreadable` and `semantic_pass_unavailable` were
# the two that fell through to the fallback; both now route explicitly to
# `/health:check`, which is where a reader of either goes anyway — the point is
# that the routing is a decision on the page rather than a default nobody chose.
#
# A ROW IS ONLY CORRECT IF THE TARGET CAN SEE THE FINDING'S CORPUS. The two
# widened duplicate kinds were first routed to `/agent-patterns:meta-promote` by
# copying the `duplicate_rule_lexical` row, which reads as safe and is not.
# meta-promote builds its inventory from `<scope>/.claude/{rules,skills,commands,
# agents}/` and `<scope>/*/.claude/{...}/` (SKILL.md § "Build the scope
# inventory", Target/Sources/Upstream table). A repo-root CLAUDE.md is in
# NEITHER layer, and a plugin agent at `*-plugin/agents/*.md` is not under
# `.claude/agents/` either -- so both rows named a skill that structurally cannot
# open the files the finding is about. The rule row IS correct, which is exactly
# why copying it looked safe.
#
# Re-routed against each target's own inventory logic, not its description:
#
# * `duplicate_agent_lexical` -> `/agents:analyze`. Its Step 3 gap analysis
#   carries "Consolidation opportunities: Multiple agents that could be merged"
#   -- the literal action a near-identical agent pair calls for -- and its
#   inventory is agent FILES rather than `.claude/agents/`. Caveat worth naming:
#   its Context block globs `agents-plugin/agents/*` specifically, which is 12 of
#   this marketplace's 21 agents, so the finding's own `paths` do the locating
#   for the other 9. Widening that glob to `*/agents/*.md` belongs in
#   agents-plugin, not here.
# * `duplicate_claude_md_lexical` -> `/agent-patterns:meta-context-diet`. Its
#   Context block is `find . -maxdepth 3 -name 'CLAUDE.md'` and its Step 1 globs
#   CLAUDE.md during execution -- it is the only skill in the catalog whose
#   inventory is CLAUDE.md files -- and its per-item dispositions include
#   consolidate. Same caveat, from the other direction: `-maxdepth 3` does not
#   reach every CLAUDE.md at a portfolio root, so deep pairs rely on the paths in
#   the finding.
#
# `promotion_candidate` -> `/agent-patterns:meta-promote`, checked against that
# skill's inventory rather than its title. meta-promote's Target/Sources table
# is `<scope>/.claude/{rules,skills,commands,agents}/` and `<scope>/*/.claude/{...}/`
# -- which is exactly the two scoped kinds this finding can name, since
# PROMOTION_KINDS excludes the plugin-namespaced ones. The CLAUDE.md caveat that
# re-routed `duplicate_claude_md_lexical` away from this skill applies to the
# claude_md half here too, and the finding's own `paths` (child first) do that
# locating. Promoting a rule up a scope ladder IS this skill's stated operation.
#
# `agent_discovery_misfire` routes to `/health:check` with the rest of the
# "the probe itself is broken" family (`coverage_metric_broken`,
# `corpus_unreadable`): its fix site is this analyzer, not the corpus.
#
# `semantic_overlap_skill_rule` is ABSENT ON PURPOSE and is not a gap. The
# f-string `semantic_overlap_{a[kind]}_{b[kind]}` in `check_semantic_dupes` is
# fed `rules + skills` (rules first) and iterates `np.triu_indices(k=1)`, so `a`
# is always the LOWER index: a cross-kind pair is always (rule, skill) and never
# (skill, rule). Adding the row would look like completeness and would in fact
# pin a kind that cannot be produced. If that call ever stops concatenating
# rules-then-skills, the kind becomes reachable and TEST N3 fails.
while IFS=$'\t' read -r severity kind summary remediation; do
    [ -n "$kind" ] || continue
    drift_add_finding "$severity" "$kind" "$summary" "$remediation"
done < <(printf '%s' "$OUT" | jq -r '
  def rank: {"error":0,"warn":1,"info":2}[.severity] // 3;
  def fix:
    {"agent_discovery_misfire":      "/health:check",
     "broken_pointer_stub":          "/agent-patterns:meta-promote",
     "coverage_metric_broken":       "/health:check",
     "corpus_unreadable":            "/health:check",
     "duplicate_rule_lexical":       "/agent-patterns:meta-promote",
     "duplicate_agent_lexical":      "/agents:analyze",
     "duplicate_claude_md_lexical":  "/agent-patterns:meta-context-diet",
     "semantic_overlap_rule_rule":   "/agent-patterns:meta-promote",
     "semantic_overlap_rule_skill":  "/health:skill-audit",
     "semantic_overlap_skill_skill": "/health:skill-audit",
     "promotion_candidate":          "/agent-patterns:meta-promote",
     "rule_covered_by_skill":        "/agent-patterns:meta-context-diet",
     "always_loaded_budget":         "/agent-patterns:meta-context-diet",
     "review_staleness":             "/health:skill-audit",
     "semantic_pass_unavailable":    "/health:check",
     "frontmatter_coverage":         "/agent-patterns:meta-context-diet"}[.kind] // "/health:check";
  [.findings[]]
  | group_by(.kind)
  | map( (.[0] | . + {rank: rank, fix: fix}) as $head
       | $head + {summary: (if length > 1
                            then ($head.summary + " (+\(length - 1) more of this kind)")
                            else $head.summary end)} )
  | sort_by(.rank, .kind)
  | .[:4][]
  | [.severity, .kind, .summary, .fix] | @tsv
')

drift_emit

#!/usr/bin/env bash
# compare-ref-output.sh — byte-identity gate for the config-drift contract extraction.
#
# DELIBERATELY NOT NAMED test-*.sh. `scripts/run-skill-script-tests.sh` discovers
# `*/scripts/tests/test-*.sh`, and this script is only meaningful while the base
# ref it compares against is still resolvable. Once that ref ages out of the
# clone (or the follow-up PR normalises the finding shape ON PURPOSE), a
# discovered test would go red for a reason nobody can act on — a gate everyone
# learns to bypass. Run it by hand, as the acceptance check for the extraction.
#
# WHAT IT PROVES
# Moving nine finding-construction sites, three renderers, two caches and a
# two-orientation waiver lookup has no cheap total oracle other than the output
# itself. So: check out the analyzer AS IT WAS at the base ref, run it and the
# current one BACK-TO-BACK over the same corpus, and `cmp` the bytes.
#
#   --format=report and --format=probe are EXCLUDED: both embed
#   `datetime.now()`, so two runs of the SAME file differ whenever the clock
#   ticks between them and the comparison would assert nothing.
#
# TWO CORPORA, because the real ones do not reach most of the code
# ------------------------------------------------------------------
# At this repo's root and the portfolio root, only four of the nine
# construction sites ever fire: review_staleness, rule_covered_by_skill,
# frontmatter_coverage and duplicate_rule_lexical. A comparison over those
# alone leaves `broken_pointer_stub` (the ONLY site passing a singular `path=`,
# i.e. exactly where "kwargs order == dict-literal order" could break),
# `always_loaded_budget` (the only `tokens=`) and `coverage_metric_broken`
# unexercised — and with no `~/.claude/config-drift-waivers.json` on this
# machine, the two-orientation waiver lookup and `_canon` are not exercised
# either. So a SYNTHETIC root is built under `mktemp -d` with `HOME` redirected
# (which is what puts `HOME_RULES` and the default waiver path under our
# control) and compared the same way.
#
# The synthetic corpus is guarded: after the comparison, the AFTER-side JSON is
# asserted to contain every kind it was built to fire, and to be missing the
# two waived pairs while still reporting the expired one. Without that guard a
# fixture that silently stopped firing would still `cmp` clean — an empty run
# and a working one produce the same verdict, and only the guard tells them
# apart (`~/.claude/rules/never-fabricate-test-identifiers.md`).
#
# NOT exercised, deliberately: `semantic_overlap_*` and (therefore)
# `semantic_pass_unavailable` as an embed-path finding. The semantic pass needs
# numpy + fastembed, which a bare `python3` — the interpreter both real callers
# use — does not have, and installing them to fire one construction site would
# make this acceptance check depend on a download. It is acceptable because
# `semantic_overlap_*` carries the SAME key shape as the verified
# `duplicate_rule_lexical` (`severity, kind, summary, score, paths`, in that
# order), so the property under test — the emitted key order comes from the
# call site's kwargs — is already pinned by a site with an identical signature.
#
# `test-probe-lib.sh` TEST b constructs that shape BY HAND, so it is a retyped
# copy of the call site, not the call site (never-fabricate-test-identifiers.md
# § extract the code, don't retype it): a wrong kwarg name or order in the
# shipped `check_semantic_dupes` would leave it green. The site was instead
# verified by EXECUTION during review — the shipped function was loaded out of
# both origin/main and this branch with stubbed numpy/fastembed and forced
# similarity, and emitted byte-identical findings. Treat this exclusion as
# "verified once by hand", not "covered by a test".
#
# `git show`, not `git worktree add`: no worktree is registered in this shared
# checkout, and registering one would expose this run to the coworker-collision
# hazards in .claude/rules/agent-coworker-detection.md for no benefit — a single
# file read out of a ref cannot collide with anything.
#
# STATUS vocabulary: this script predates and sits outside the
# `structured-script-output.md` OK/WARN/ERROR rollup (it is hand-run, not
# discovered), and keeps its own FAIL/OK words. `STATUS=HARNESS_ERROR` (exit 2)
# is a THIRD outcome on purpose — see below.
#
# TWO WAYS THIS GATE STOPS MEANING ANYTHING, both HARNESS_ERROR:
#   * the ref AGES OUT of the clone — loud, `git show` fails, already handled.
#   * the ref becomes IDENTICAL to the working tree — SILENT, and it happens
#     FIRST: BASE_REF defaults to origin/main, so the moment this PR merges,
#     `cmp` compares the analyzer with itself and reports 7 green assertions
#     having compared nothing. Identity is asserted against right after the
#     extraction, below.
#
# Usage: bash health-plugin/scripts/tests/compare-ref-output.sh [BASE_REF]
#        BASE_REF defaults to $BASE_REF, then origin/main.
#
# Exit: 0 identical, 1 a real content difference, 2 the harness itself failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
AFTER="${REPO_ROOT}/health-plugin/scripts/config-drift.py"
REL="health-plugin/scripts/config-drift.py"
LIB_REL="health-plugin/scripts/lib/probe.py"
BASE_REF="${1:-${BASE_REF:-origin/main}}"

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: python3 not available"
    exit 0
fi

TMP=$(mktemp -d) || { echo "FAIL: mktemp failed" >&2; exit 1; }
if [ -z "$TMP" ] || [ ! -d "$TMP" ]; then
    echo "FAIL: could not create scratch dir" >&2
    exit 1
fi
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
HARNESS=0

# harness_fail <msg...> — the harness could not produce a trustworthy BEFORE
# side. Distinct from FAIL on purpose: a harness that cannot run the baseline
# must never be able to report a CONTENT difference, because "the baseline
# produced 0 bytes" and "the baseline produced a different report" look
# identical downstream of `cmp`.
harness_fail() {
    HARNESS=$((HARNESS + 1))
    printf '  HARNESS ERROR %s\n' "$1"
    shift
    for line in "$@"; do
        printf '     %s\n' "$line"
    done
}

finish() {
    echo "PASSED=$PASS"
    echo "FAILED=$FAIL"
    echo "HARNESS_ERRORS=$HARNESS"
    if [ "$HARNESS" -gt 0 ]; then
        echo "STATUS=HARNESS_ERROR"
        echo "=== END CONFIG DRIFT REF COMPARISON ==="
        exit 2
    fi
    if [ "$FAIL" -gt 0 ]; then
        echo "STATUS=FAIL"
        echo "=== END CONFIG DRIFT REF COMPARISON ==="
        exit 1
    fi
    echo "STATUS=OK"
    echo "=== END CONFIG DRIFT REF COMPARISON ==="
    exit 0
}

echo "=== CONFIG DRIFT REF COMPARISON ==="
echo "BASE_REF=$BASE_REF"
echo "BEFORE_SHA=$(git -C "$REPO_ROOT" rev-parse --short "${BASE_REF}" 2>/dev/null || echo unknown)"

BEFORE="$TMP/config-drift.py"
if ! git -C "$REPO_ROOT" show "${BASE_REF}:${REL}" > "$BEFORE" 2>"$TMP/git.err"; then
    harness_fail "cannot read ${BASE_REF}:${REL}" "$(sed -n '1,3p' "$TMP/git.err")"
    finish
fi

# The BEFORE analyzer imports `lib.probe` from its own directory (sys.path[0])
# for every ref at or after this PR. Extracting only config-drift.py into a
# scratch dir with no lib/ makes it die with `ModuleNotFoundError: No module
# named 'lib'` — 0 bytes on stdout, exit 1 — and exit 1 is ALSO what a healthy
# run with warn-severity findings returns, so the exit-code guard below would
# pass and `cmp` would report the entire report as newly added. Extract the
# module too, when the ref has one; a ref that predates it (origin/main today)
# simply has no such path and needs nothing.
if git -C "$REPO_ROOT" cat-file -e "${BASE_REF}:${LIB_REL}" 2>/dev/null; then
    mkdir -p "$TMP/lib"
    if ! git -C "$REPO_ROOT" show "${BASE_REF}:${LIB_REL}" > "$TMP/lib/probe.py" 2>"$TMP/git.err"; then
        harness_fail "cannot read ${BASE_REF}:${LIB_REL}" "$(sed -n '1,3p' "$TMP/git.err")"
        finish
    fi
    echo "BEFORE_LIB=extracted"
else
    echo "BEFORE_LIB=absent-at-ref"
fi

# `cmp` will happily compare a file with itself and call it a pass. BASE_REF
# defaults to origin/main, so once this PR lands the baseline IS the analyzer
# under test and every re-run reports PASSED=7 FAILED=0 STATUS=OK having
# compared nothing — the gate self-neutralizes, silently, at the moment it stops
# being able to prove anything. That is a HARNESS ERROR, not a pass: the harness
# could not produce a trustworthy BEFORE side.
if cmp -s "$BEFORE" "$AFTER"; then
    harness_fail "baseline at $BASE_REF is byte-identical to the analyzer under test — nothing is being compared" \
        "pass an OLDER ref: bash $0 <ref-before-the-extraction>"
    finish
fi

# compare <label> <root> <fmt> [home]
#   Runs BEFORE and AFTER back-to-back with identical flags and compares bytes.
#   `home` redirects HOME for BOTH runs, which is how the synthetic root gets a
#   controlled HOME_RULES and default waiver path.
#   Publishes the AFTER stdout path as $LAST_AFTER; the synthetic-coverage guard
#   below reads it rather than reconstructing the filename itself.
LAST_AFTER=""
compare() {
    local label="$1" root="$2" fmt="$3" home="${4:-}"
    local tag
    tag=$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '_')
    local b_out="$TMP/before.$tag" a_out="$TMP/after.$tag"
    local b_rc a_rc

    # Back-to-back, same flags, same caches (--fast never writes the git-date
    # cache, so the real cache is read-only here and both runs see it warm --
    # which is what keeps the staleness findings in the comparison).
    if [ -n "$home" ]; then
        HOME="$home" python3 "$BEFORE" --root "$root" --fast --no-embed "--format=$fmt" > "$b_out" 2>"$TMP/b.err"
        b_rc=$?
        HOME="$home" python3 "$AFTER" --root "$root" --fast --no-embed "--format=$fmt" > "$a_out" 2>"$TMP/a.err"
        a_rc=$?
    else
        python3 "$BEFORE" --root "$root" --fast --no-embed "--format=$fmt" > "$b_out" 2>"$TMP/b.err"
        b_rc=$?
        python3 "$AFTER" --root "$root" --fast --no-embed "--format=$fmt" > "$a_out" 2>"$TMP/a.err"
        a_rc=$?
    fi
    LAST_AFTER="$a_out"

    # The BEFORE side is the ORACLE, and it is untrustworthy on TWO channels.
    # Both are classified here and return WITHOUT reaching cmp, because
    # harness_fail's contract is that a harness which cannot run the baseline
    # must never be able to report a CONTENT difference.
    #
    # Channel 2 (empty stdout) is not a heuristic: both --format=json and
    # --format=status print unconditionally, so a BEFORE run that produced 0
    # bytes DID NOT RUN. Reaching cmp with it makes the entire AFTER report look
    # newly added — 6 content FAILs and 0 harness errors, exactly the outcome
    # the docstring above says must be impossible. Stderr alone does not catch
    # it: a base ref whose analyzer is `import sys; sys.exit(1)` writes nothing
    # anywhere.
    if [ ! -s "$b_out" ]; then
        harness_fail "$label — the BEFORE (oracle) run produced 0 bytes on stdout; --format=$fmt prints unconditionally, so the baseline did not run" \
            "exit $b_rc" \
            "$(sed -n '1,4p' "$TMP/b.err")"
        return 2
    fi
    if [ -s "$TMP/b.err" ]; then
        harness_fail "$label — the BEFORE (oracle) run wrote to stderr; its output cannot be trusted" \
            "exit $b_rc, $(wc -c < "$b_out" | tr -d ' ') bytes on stdout" \
            "$(sed -n '1,4p' "$TMP/b.err")"
        return 2
    fi

    if [ "$b_rc" != "$a_rc" ]; then
        FAIL=$((FAIL + 1))
        printf '  FAIL %s\n     exit code %s -> %s\n' "$label" "$b_rc" "$a_rc"
        return 1
    fi
    if cmp -s "$b_out" "$a_out"; then
        PASS=$((PASS + 1))
        printf '  ok   %s (exit %s, %s bytes identical)\n' "$label" "$a_rc" "$(wc -c < "$a_out" | tr -d ' ')"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL %s\n' "$label"
        diff -u "$b_out" "$a_out" | head -40 | sed 's/^/     /'
        return 1
    fi
    if [ -s "$TMP/a.err" ]; then
        FAIL=$((FAIL + 1))
        printf '  FAIL %s wrote to stderr\n' "$label"
        sed -n '1,5p' "$TMP/a.err" | sed 's/^/     /'
        return 1
    fi
    return 0
}

# ------------------------------------------------------------- the real roots
# The two roots the probe actually runs at: this repo, and the portfolio root
# whose corpus is ~4x larger and spans several scopes.
ROOTS=("$REPO_ROOT")
if [ -d "$HOME/repos/laurigates" ]; then
    ROOTS+=("$HOME/repos/laurigates")
else
    echo "  note  portfolio root $HOME/repos/laurigates absent — comparing repo root only"
fi

for root in "${ROOTS[@]}"; do
    for fmt in json status; do
        compare "$fmt @ $root" "$root" "$fmt"
        [ "$HARNESS" -gt 0 ] && finish
    done
done

# -------------------------------------------------------- the synthetic root
SYNTH=$(mktemp -d) || { echo "FAIL: mktemp failed" >&2; HARNESS=$((HARNESS + 1)); finish; }
if [ -z "$SYNTH" ] || [ ! -d "$SYNTH" ]; then
    harness_fail "could not create the synthetic fixture root"
    finish
fi
trap 'rm -rf "$TMP" "$SYNTH"' EXIT

SYNTH_HOME="$SYNTH/home"
SYNTH_RULES="$SYNTH_HOME/.claude/rules"
mkdir -p "$SYNTH_RULES" "$SYNTH/proj/some-plugin/skills/quilting-loom-calibration"

# A skill with vocabulary disjoint from every rule below. Its job is to make
# `known` non-empty (so `_stub_target` runs its real resolution passes) while
# scoring far under T_COVERAGE against the stub, which is what makes the
# coverage control MISS and fires `coverage_metric_broken`.
cat > "$SYNTH/proj/some-plugin/skills/quilting-loom-calibration/SKILL.md" <<'SKILL'
---
name: quilting-loom-calibration
description: Calibrate a quilting loom. Use when the shuttle tension drifts or the heddle spacing needs re-seating.
---
# quilting-loom-calibration
Shuttle tension, heddle spacing and warp beam alignment on a quilting loom.
Re-seat the heddle before adjusting shuttle tension on any warp beam.
SKILL

# A pointer stub naming a skill that does not exist. Fires TWO sites at once:
#   * broken_pointer_stub — the only construction site passing a singular
#     `path=` kwarg, so this is the one place the "emitted key order is the
#     kwargs order" property is testable end-to-end for a singular path.
#   * coverage_metric_broken — the stub is the coverage control, and its topic
#     vocabulary (below) is disjoint from the only skill, so the control scores
#     0/1 and the metric declares itself broken.
{
    echo "# Ghost Stub"
    echo
    echo "Promoted to a skill: invoke \`no-such-skill-anywhere\` before doing the thing —"
    echo "it carries the whole procedure."
    echo
    python3 -c 'print(" ".join("stubtopic%03d" % i for i in range(60)))'
} > "$SYNTH_RULES/ghost-stub.md"

# Three duplicate pairs and three always-loaded heavyweights, generated with
# disjoint token streams so the only pairs above T_LEXICAL are the intended
# ones. No randomness and no timestamps anywhere: the corpus must be
# byte-stable across the two back-to-back runs or the comparison asserts
# nothing.
python3 - "$SYNTH_RULES" <<'PY'
import pathlib
import sys

rules = pathlib.Path(sys.argv[1])


def body(title, prefix, n):
    words = " ".join("%s%05d" % (prefix, i) for i in range(n))
    return "# %s\n\n%s\n" % (title, words)


# Duplicate pairs: identical within a pair (Jaccard 1.0, well over T_LEXICAL
# 0.45), disjoint across pairs. Names chosen so the sorted-path scan order is
# a-then-b, which is what makes "waiver written (b, a)" a real reverse-lookup.
for slug, prefix in (("one", "dupone"), ("two", "duptwo"), ("three", "dupthree")):
    text = body("Duplicate %s" % slug, prefix, 400)
    (rules / ("dup-%s-a.md" % slug)).write_text(text)
    (rules / ("dup-%s-b.md" % slug)).write_text(text)

# Always-loaded budget: user-global scope with no `paths:` frontmatter, so every
# one of these counts. BUDGET_TOKENS is 55,000 and tokens are chars // 4, so the
# corpus needs > 220,000 chars. Distinct sizes keep the "heaviest: ..." top-3
# ordering deterministic.
for name, prefix, n in (
    ("budget-heavy", "alphaword", 11000),
    ("budget-mid", "betaword", 8000),
    ("budget-light", "gammaword", 5000),
):
    (rules / ("%s.md" % name)).write_text(body(name, prefix, n))
PY

# The waiver file, exercising all three paths through `Waivers.waived`:
#   pair one   — forward (a, b), spelled with `~/` so `_canon` must expanduser
#   pair two   — reverse (b, a), so the lookup must hit the swapped key AND
#                swap the recorded hash pair to match
#   pair three — forward, with a deliberately stale `a_hash`, so the waiver
#                EXPIRES and the finding must still be reported
# `_canon` also has to realpath: mktemp hands out /var/... which macOS resolves
# to /private/var/..., and a raw string compare would silently never match.
python3 - "$SYNTH_RULES" "$SYNTH_HOME/.claude/config-drift-waivers.json" <<'PY'
import hashlib
import json
import pathlib
import sys

rules = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])


def sha(path):
    # sha256 truncated to 16 hex chars — the length is the contract (lib/probe.py).
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def p(slug, side):
    return rules / ("dup-%s-%s.md" % (slug, side))


waivers = [
    # forward, `~/`-spelled
    {
        "a": "~/.claude/rules/dup-one-a.md",
        "b": "~/.claude/rules/dup-one-b.md",
        "a_hash": sha(p("one", "a")),
        "b_hash": sha(p("one", "b")),
    },
    # reverse: filed as (b, a) while the scan yields (a, b)
    {
        "a": str(p("two", "b")),
        "b": str(p("two", "a")),
        "a_hash": sha(p("two", "b")),
        "b_hash": sha(p("two", "a")),
    },
    # expired: the file changed since the waiver was filed
    {
        "a": str(p("three", "a")),
        "b": str(p("three", "b")),
        "a_hash": "0000000000000000",
        "b_hash": sha(p("three", "b")),
    },
]
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps({"waivers": waivers}, indent=1))
PY

SYNTH_JSON=""
for fmt in json status; do
    compare "$fmt @ synthetic" "$SYNTH/proj" "$fmt" "$SYNTH_HOME"
    [ "$HARNESS" -gt 0 ] && finish
    # Take the path from compare() rather than re-deriving it from the label:
    # a guard that reconstructs its own input path can silently read nothing.
    [ "$fmt" = json ] && SYNTH_JSON="$LAST_AFTER"
done

# Guard: the synthetic corpus must actually fire what it was built to fire. A
# fixture that silently stopped producing findings would `cmp` clean and this
# whole section would assert nothing.
if [ -z "$SYNTH_JSON" ] || [ ! -s "$SYNTH_JSON" ]; then
    harness_fail "synthetic AFTER json output is missing — the coverage guard cannot run"
    finish
fi
guard=$(python3 - "$SYNTH_JSON" <<'PY'
import json
import sys

kinds = [f["kind"] for f in json.load(open(sys.argv[1]))["findings"]]
summaries = [
    f["summary"] for f in json.load(open(sys.argv[1]))["findings"]
]
want = [
    "broken_pointer_stub",
    "always_loaded_budget",
    "coverage_metric_broken",
    "duplicate_rule_lexical",
    "frontmatter_coverage",
]
missing = [k for k in want if k not in kinds]
# Waiver orientations: pairs one and two are waived and must be ABSENT; pair
# three's waiver is expired and must still be REPORTED. Asserting only the
# absences would pass against a lexical check that stopped running at all, so
# the expired pair is the control.
dupes = " ".join(s for s, k in zip(summaries, kinds) if k == "duplicate_rule_lexical")
if "dup-one" in dupes:
    missing.append("!forward-waiver-not-applied")
if "dup-two" in dupes:
    missing.append("!reverse-waiver-not-applied")
if "dup-three" not in dupes:
    missing.append("!expired-waiver-suppressed-anyway")
print(",".join(missing) if missing else "OK")
PY
)
if [ "$guard" = "OK" ]; then
    PASS=$((PASS + 1))
    printf '  ok   synthetic corpus fires every targeted site (waivers: forward, reverse, expired)\n'
else
    harness_fail "the synthetic fixture no longer exercises what it claims" "unmet: $guard"
fi

finish

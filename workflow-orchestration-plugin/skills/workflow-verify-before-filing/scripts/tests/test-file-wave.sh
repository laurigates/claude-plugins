#!/usr/bin/env bash
# Regression test for file-wave.sh (issue #2166).
#
# Runs entirely offline against PLANTED result JSON and STUB forge binaries on
# a prepended PATH — it never contacts github.com or a GitLab instance, and
# every run passes --pace-seconds 0 --backoff-seconds 0 so the real 70s/130s
# waits are never incurred.
#
# Asserts the SEMANTIC invariants the extraction has to preserve:
#   A. Empty input (no `disposition == "file"` entry) → STATUS=OK, FILED_COUNT=0,
#      exit 0 — the parallel-safe exit-0-on-empty contract.
#   B. The multi-item path files EVERY gate-passing draft and skips every other
#      disposition (gated-out candidates are counted, never filed).
#   C. Forge dispatch is deterministic and reports its source:
#      --forge flag > FILE_WAVE_FORGE > GITLAB_HOST > gh default.
#   D. Each forge gets its OWN argv shape (`gh issue create --repo/--title/--body`
#      vs `glab issue create -R/-t/-d -y`), and the host reaches glab as GITLAB_HOST.
#   E. The draft's `# ` heading becomes the title when the result carries none,
#      and the `<!-- target: … -->` comment never reaches the issue body.
#   F. A create that never yields a URL is retried up to --max-attempts, then
#      recorded as FAILED while the batch CONTINUES to the next draft
#      (STATUS=ERROR, exit 1) — a half-filed wave must still be recorded.
#   G. Every filed URL and every failure is appended to the manifest.
#   H. --dry-run creates nothing.
#   I. An unknown argument is REJECTED (exit 2), never silently swallowed.
#
# Exit 0 on success ("ALL TESTS PASSED"); non-zero on any failure.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
file_wave="${script_dir}/../file-wave.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

for dep in jq sed grep awk tail tr; do
    command -v "$dep" >/dev/null 2>&1 || { echo "SKIP: $dep not installed"; exit 0; }
done
[ -f "$file_wave" ] || fail "file-wave.sh not found at $file_wave"

fx="$(mktemp -d)" || { echo "mktemp failed" >&2; exit 1; }
if [ -z "$fx" ] || [ ! -d "$fx" ]; then echo "bad sandbox dir" >&2; exit 1; fi
trap 'rm -rf "$fx"' EXIT

mkdir -p "$fx/bin" "$fx/drafts"

# --- Stub forges -----------------------------------------------------------
# Each stub logs its argv as ONE flattened line to $FORGE_LOG (the issue body
# is multi-line, so newlines are squashed to keep one line per invocation) and
# prints a URL as its LAST line — matching how gh/glab report a created issue.
# FORGE_FAIL=1 makes every call fail without a URL, exercising the retry path
# with no waiting.
cat >"$fx/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf 'gh %s\n' "$(printf '%s ' "$@" | tr '\n' ' ')" >>"$FORGE_LOG"
if [ "${FORGE_FAIL:-0}" = "1" ]; then
    echo "HTTP 429: rate limited"
    exit 1
fi
echo "note: creating issue"
echo "https://github.com/acme/widget/issues/$RANDOM"
STUB

cat >"$fx/bin/glab" <<'STUB'
#!/usr/bin/env bash
printf 'glab %s\n' "$(printf '%s ' "$@" | tr '\n' ' ')" >>"$FORGE_LOG"
printf 'GITLAB_HOST=%s\n' "${GITLAB_HOST:-unset}" >>"$FORGE_LOG"
if [ "${FORGE_FAIL:-0}" = "1" ]; then
    echo "429 Too Many Requests"
    exit 1
fi
echo "https://gitlab.example.org/group/proj/-/work_items/$RANDOM"
STUB

chmod +x "$fx/bin/gh" "$fx/bin/glab"
export PATH="$fx/bin:$PATH"

# --- Fixture drafts --------------------------------------------------------
cat >"$fx/drafts/W2-13.md" <<'MD'
# Chart defaults SMTP to vendor dev infrastructure
<!-- target: group/subgroup/notification-service -->

## Summary
The chart ships live vendor credentials as default values.
MD

cat >"$fx/drafts/W2-14.md" <<'MD'
# Heading-derived title for a result with no title field
<!-- target: group/subgroup/other-service -->

## Summary
Body text.
MD

results_json="$fx/results.json"
empty_json="$fx/empty.json"

cat >"$results_json" <<JSON
[
  {"id":"W2-13","slug":"smtp","disposition":"file","draftPath":"$fx/drafts/W2-13.md",
   "title":"Chart defaults SMTP to vendor dev infrastructure","targetProject":"group/subgroup/notification-service"},
  {"id":"W2-14","slug":"other","disposition":"file","draftPath":"$fx/drafts/W2-14.md",
   "title":"","targetProject":"group/subgroup/other-service"},
  {"id":"W2-15","slug":"dup","disposition":"duplicate: overlaps our wave-1 report"},
  {"id":"W2-16","slug":"fixed","disposition":"fixed-upstream"}
]
JSON

echo '[{"id":"W2-20","disposition":"could-not-verify"},{"id":"W2-21","disposition":"claim-invalid"}]' >"$empty_json"

# run_wave <log> <manifest> [extra args…] — always unpaced. FILE_WAVE_FORGE /
# GITLAB_HOST / FORGE_FAIL are forwarded explicitly so a caller-side
# `VAR=x run_wave …` prefix reaches the script under test unambiguously.
run_wave() {
    local wave_log="$1" wave_manifest="$2"; shift 2
    : >"$wave_log"
    FORGE_LOG="$wave_log" \
    FORGE_FAIL="${FORGE_FAIL:-0}" \
    FILE_WAVE_FORGE="${FILE_WAVE_FORGE:-}" \
    GITLAB_HOST="${GITLAB_HOST:-}" \
        bash "$file_wave" --results "$results_json" --manifest "$wave_manifest" \
        --pace-seconds 0 --backoff-seconds 0 "$@" 2>&1
}

# --- A. Empty input is OK and exits 0 (parallel-safe) ----------------------
out="$(FORGE_LOG="$fx/a.log" bash "$file_wave" --results "$empty_json" \
        --manifest "$fx/a-manifest.txt" --pace-seconds 0 --backoff-seconds 0 2>&1)"
rc=$?
[ "$rc" -eq 0 ] || fail "A: empty input exited non-zero ($rc) — breaks exit-0-on-empty"
grep -q '^STATUS=OK$' <<<"$out" || fail "A: empty input did not report STATUS=OK"
grep -q '^FILED_COUNT=0$' <<<"$out" || fail "A: empty input reported a non-zero FILED_COUNT"
grep -q '^FILE_COUNT=0$' <<<"$out" || fail "A: gated-out dispositions were counted as filing candidates"
grep -q '^CANDIDATE_COUNT=2$' <<<"$out" || fail "A: candidate count not reported"
[ -s "$fx/a-manifest.txt" ] && fail "A: empty input wrote to the manifest"
pass "A: empty result set → STATUS=OK, nothing filed, exit 0"

# --- B/D/E/G. Multi-item path on the default (gh) forge --------------------
out="$(run_wave "$fx/b.log" "$fx/b-manifest.txt")"
rc=$?
[ "$rc" -eq 0 ] || fail "B: multi-item run exited non-zero ($rc): $out"
grep -q '^STATUS=OK$' <<<"$out" || fail "B: multi-item run did not report STATUS=OK"
grep -q '^FILE_COUNT=2$' <<<"$out" || fail "B: expected 2 gate-passing drafts (4 candidates, 2 gated out)"
grep -q '^FILED_COUNT=2$' <<<"$out" || fail "B: expected FILED_COUNT=2"
grep -q '^FAILED_COUNT=0$' <<<"$out" || fail "B: unexpected failures"
grep -q '^CANDIDATE_COUNT=4$' <<<"$out" || fail "B: candidate count should include gated-out entries"
grep -q 'ID=W2-13 REPO=group/subgroup/notification-service URL=https://' <<<"$out" \
    || fail "B: filed row for W2-13 missing"
grep -q 'ID=W2-15' <<<"$out" && fail "B: a gated-out candidate was filed"
pass "B: only disposition==file entries are filed; gated-out ones are counted"

[ "$(grep -c '^gh issue create ' "$fx/b.log")" -eq 2 ] \
    || fail "D: expected exactly 2 gh invocations, got: $(cat "$fx/b.log")"
grep -q '^gh issue create --repo group/subgroup/notification-service --title ' "$fx/b.log" \
    || fail "D: gh argv shape wrong: $(cat "$fx/b.log")"
grep -q '^glab ' "$fx/b.log" && fail "D: glab invoked on the default gh path"
pass "D(gh): gh issue create --repo/--title/--body argv shape"

grep -q 'Heading-derived title for a result with no title field' "$fx/b.log" \
    || fail "E: empty title was not backfilled from the draft's '# ' heading"
grep -q 'target: group/subgroup/notification-service' "$fx/b.log" \
    && fail "E: the <!-- target: … --> comment leaked into the issue body"
grep -q 'The chart ships live vendor credentials' "$fx/b.log" \
    || fail "E: the draft body did not reach the forge"
pass "E: title falls back to the draft heading; HTML target comment is stripped"

[ "$(grep -c ' -> https://' "$fx/b-manifest.txt")" -eq 2 ] \
    || fail "G: manifest did not record both filed URLs: $(cat "$fx/b-manifest.txt")"
pass "G: every filed URL is appended to the manifest"

# --- C/D. Forge dispatch ---------------------------------------------------
out="$(run_wave "$fx/c1.log" "$fx/c1-manifest.txt" --forge glab --host gitlab.example.org)"
grep -q '^FORGE=glab$' <<<"$out" || fail "C: --forge glab was not honoured"
grep -q '^FORGE_SOURCE=flag$' <<<"$out" || fail "C: --forge did not report FORGE_SOURCE=flag"
grep -q '^glab issue create -R group/subgroup/notification-service -t ' "$fx/c1.log" \
    || fail "D: glab argv shape wrong: $(cat "$fx/c1.log")"
grep -qE '^glab .*( |^)-y ' "$fx/c1.log" || fail "D: glab invoked without -y (would block on a prompt)"
grep -q '^GITLAB_HOST=gitlab.example.org$' "$fx/c1.log" || fail "D: --host did not reach glab as GITLAB_HOST"
pass "C/D(glab): --forge flag wins, glab argv shape, GITLAB_HOST exported"

out="$(FILE_WAVE_FORGE=glab run_wave "$fx/c2.log" "$fx/c2-manifest.txt")"
grep -q '^FORGE=glab$' <<<"$out" || fail "C: FILE_WAVE_FORGE=glab not honoured"
grep -q '^FORGE_SOURCE=env:FILE_WAVE_FORGE$' <<<"$out" || fail "C: FILE_WAVE_FORGE source not reported"
pass "C: FILE_WAVE_FORGE selects the forge when no flag is given"

out="$(GITLAB_HOST=gitlab.example.org run_wave "$fx/c3.log" "$fx/c3-manifest.txt")"
grep -q '^FORGE=glab$' <<<"$out" || fail "C: a set GITLAB_HOST did not imply glab"
grep -q '^FORGE_SOURCE=env:GITLAB_HOST$' <<<"$out" || fail "C: GITLAB_HOST source not reported"
pass "C: GITLAB_HOST implies glab"

out="$(FILE_WAVE_FORGE=glab GITLAB_HOST=gitlab.example.org \
        run_wave "$fx/c4.log" "$fx/c4-manifest.txt" --forge gh)"
grep -q '^FORGE=gh$' <<<"$out" || fail "C: --forge gh did not override the env vars"
grep -q '^FORGE_SOURCE=flag$' <<<"$out" || fail "C: flag precedence not reported"
pass "C: flag > FILE_WAVE_FORGE > GITLAB_HOST > gh default"

out="$(run_wave "$fx/c5.log" "$fx/c5-manifest.txt")"
grep -q '^FORGE=gh$' <<<"$out" || fail "C: default forge is not gh"
grep -q '^FORGE_SOURCE=default$' <<<"$out" || fail "C: default source not reported"
pass "C: gh is the default when nothing selects a forge"

# --- F. Retry, then record the failure and CONTINUE the batch --------------
out="$(FORGE_FAIL=1 run_wave "$fx/f.log" "$fx/f-manifest.txt" --max-attempts 3)"
rc=$?
[ "$rc" -eq 1 ] || fail "F: an exhausted create should exit 1 (got $rc)"
grep -q '^STATUS=ERROR$' <<<"$out" || fail "F: exhausted create did not report STATUS=ERROR"
grep -q '^FAILED_COUNT=2$' <<<"$out" || fail "F: batch stopped early instead of continuing past the failure"
grep -q '^ISSUE_COUNT=2$' <<<"$out" || fail "F: ISSUE_COUNT does not match FAILED_COUNT"
grep -q 'TYPE=create_failed .*ATTEMPTS=3' <<<"$out" || fail "F: failure row missing the attempt count"
[ "$(grep -c '^gh issue create ' "$fx/f.log")" -eq 6 ] \
    || fail "F: expected 3 attempts x 2 drafts = 6 invocations, got $(grep -c '^gh issue create ' "$fx/f.log")"
[ "$(grep -c ' -> FAILED' "$fx/f-manifest.txt")" -eq 2 ] \
    || fail "G: failures were not recorded in the manifest"
pass "F: retries up to --max-attempts, records FAILED, continues the batch, exits 1"

# --- H. Dry run creates nothing -------------------------------------------
out="$(run_wave "$fx/h.log" "$fx/h-manifest.txt" --dry-run)"
rc=$?
[ "$rc" -eq 0 ] || fail "H: dry run exited non-zero ($rc)"
grep -q '^DRY_RUN=true$' <<<"$out" || fail "H: dry run did not report DRY_RUN=true"
grep -q 'URL=DRY_RUN' <<<"$out" || fail "H: dry run did not report the drafts it would file"
[ -s "$fx/h.log" ] && fail "H: dry run invoked the forge"
[ -s "$fx/h-manifest.txt" ] && fail "H: dry run wrote to the manifest"
pass "H: --dry-run resolves and reports without creating anything"

# --- I. Usage errors are rejected, never swallowed ------------------------
out="$(bash "$file_wave" --results "$results_json" --pace-secondz 0 2>&1)"
rc=$?
[ "$rc" -eq 2 ] || fail "I: an unknown flag must exit 2 (got $rc) — see issue #2057"
grep -q 'unknown argument: --pace-secondz' <<<"$out" || fail "I: unknown flag not named on stderr"
pass "I: unknown argument rejected with exit 2"

out="$(bash "$file_wave" --pace-seconds 0 2>&1)"
rc=$?
[ "$rc" -eq 2 ] || fail "I: missing --results must exit 2 (got $rc)"
pass "I: missing --results rejected with exit 2"

echo "ALL TESTS PASSED"

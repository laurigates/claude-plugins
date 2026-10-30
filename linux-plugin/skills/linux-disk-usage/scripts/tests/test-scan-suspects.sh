#!/usr/bin/env bash
# Regression test for scan-suspects.sh.
#
# Runs entirely offline on Linux CI against a PLANTED fixture home via the
# injectable --home-dir / --root seams — never against the real system. Asserts
# the SEMANTIC invariants:
#   - Fixed-path suspects present on disk are detected with the right tier
#     (uv=safe, ollama=decision).
#   - A build-artifact dir counts ONLY when its marker sibling exists: a
#     target/ beside Cargo.toml is matched as rust-target; a target/ WITHOUT a
#     Cargo.toml is not (marker discipline).
#   - node_modules beside package.json is matched.
#   - The ranked table orders by real size (biggest fixture = rank 1).
#   - Tier totals separate safe from decision.
#   - A big dir NOT in the catalog surfaces as UNKNOWN (the feedback loop).
#   - A multi-component dir target (.claude/worktrees) matches by path suffix
#     beside its .git marker, {parent} expands to the repo root, and a bare
#     worktrees/ dir elsewhere is NOT matched.
#   - Catalog commands that once wiped whole caches stay scoped (hf-cache,
#     pre-commit-cache, bun-store).
#   - Linux rows: the go-build[0-9]* glob matches leftover temp dirs but never
#     the live .cache/go-build; a runner _work counts only beside .runner;
#     brew-cache keeps --prune=all and npx-cache stays catalogued (both
#     measured incomplete in their plain form). Absolute-path rows are kept
#     out of the fixture scan (they would measure the host) and checked at
#     catalog level instead.
#   - --help prints usage and exits 0 without scanning; an unknown argument
#     exits 2 with STATUS=ERROR_BAD_ARG.
#   - A missing catalog reports STATUS=ERROR_NO_CATALOG and exits non-zero.
#   - An empty home degrades gracefully (STATUS=OK, no suspects, exit 0).
# Exit 0 on success ("ALL TESTS PASSED"); non-zero on any failure.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scan="${script_dir}/../scan-suspects.sh"
catalog="${script_dir}/../suspects.tsv"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

for dep in du find awk sort dirname dd; do
  command -v "$dep" >/dev/null 2>&1 || { echo "SKIP: $dep not installed"; exit 0; }
done

[ -f "$scan" ] || fail "scan-suspects.sh not found at $scan"
[ -f "$catalog" ] || fail "suspects.tsv not found at $catalog"

mkfile() { mkdir -p "$(dirname "$1")"; dd if=/dev/zero of="$1" bs=1024 count="$2" 2>/dev/null; }

fx=$(mktemp -d) || { echo 'mktemp failed' >&2; exit 1; }
if [ -z "$fx" ] || [ ! -d "$fx" ]; then echo 'bad sandbox dir' >&2; exit 1; fi
trap 'rm -rf "$fx"' EXIT

# --- Plant the fixture home ------------------------------------------------
mkfile "$fx/.cache/uv/blob"                 5000   # fixed path, tier=safe
mkfile "$fx/.ollama/models/blob"            2000   # fixed path, tier=decision
# rust project: target/ beside Cargo.toml -> matched (mkfile creates proj/ first)
mkfile "$fx/repos/proj/target/artifact"     8000   # dir rust-target, biggest
: > "$fx/repos/proj/Cargo.toml"
# target/ WITHOUT Cargo.toml -> marker discipline: must NOT match
mkfile "$fx/repos/norust/target/artifact"   3000
# node project: node_modules beside package.json -> matched
mkfile "$fx/repos/webapp/node_modules/dep"  1000   # dir node-modules, tier=safe
: > "$fx/repos/webapp/package.json"
# a big dir not in the catalog -> should surface as UNKNOWN
mkfile "$fx/BigMovies/recording.mov"        4000
# agent worktrees: <repo>/.claude/worktrees beside a .git marker -> matched
mkfile "$fx/repos/agentrepo/.claude/worktrees/wt1/file" 1500
mkdir -p "$fx/repos/agentrepo/.git"
# a bare worktrees/ dir (no .claude/ parent) -> must NOT match the suffix
mkfile "$fx/repos/other/worktrees/file"     500
: > "$fx/repos/other/.git"
# go build temp dir (glob target go-build[0-9]*) vs the real build cache
mkfile "$fx/tmp/go-build123456/obj"         600
mkfile "$fx/.cache/go-build/ab/obj"         700
# self-hosted runner workspace: _work beside a .runner marker -> matched
mkfile "$fx/actions-runners/r1/_work/job"   900
: > "$fx/actions-runners/r1/.runner"
# a _work dir without the marker -> must NOT match
mkfile "$fx/repos/other/_work/file"         300

# Absolute-path rows (/swapfile, /var/log/journal, ...) bypass --home-dir and
# would measure the real host, so the fixture scan uses a catalog without them.
# Those rows are checked at catalog level further down.
fx_catalog="$fx/.fixture-catalog.tsv"
awk -F'\t' '!($1 == "path" && $3 ~ /^\//)' "$catalog" > "$fx_catalog"

out="$(bash "$scan" --home-dir "$fx" --root "$fx" --catalog "$fx_catalog" --min-mb 1 --top 25)"
rc=$?
[ "$rc" -eq 0 ] || fail "scan exited non-zero ($rc)"
grep -q '^STATUS=OK$' <<<"$out" || fail "missing STATUS=OK"
pass "scan runs clean on the fixture"

grep -q 'SUSPECT id=uv-cache tier=safe ' <<<"$out" || fail "uv-cache not detected as safe"
pass "fixed-path uv-cache detected (safe)"

grep -q 'SUSPECT id=ollama-models tier=decision ' <<<"$out" || fail "ollama not detected as decision"
pass "fixed-path ollama-models detected (decision)"

# rust-target matched, and matched at proj/ (has Cargo.toml)
grep -q 'SUSPECT id=rust-target .*proj/target' <<<"$out" || fail "rust-target not matched beside Cargo.toml"
pass "rust-target matched beside Cargo.toml"

# marker discipline: the markerless norust/target must NOT be a rust-target hit
if grep 'SUSPECT id=rust-target' <<<"$out" | grep -q 'norust'; then
  fail "markerless target/ was wrongly counted as rust-target"
fi
pass "markerless target/ correctly skipped (marker discipline)"

grep -q 'SUSPECT id=node-modules .*webapp/node_modules' <<<"$out" || fail "node-modules not matched"
pass "node-modules matched beside package.json"

# ranked rank-1 (biggest) is the 8000KB rust-target; field 4 is the id
rank1_id="$(awk -F'\t' '$1=="1"{print $4}' <<<"$out")"
[ "$rank1_id" = "rust-target" ] || fail "rank 1 should be rust-target, got '$rank1_id'"
pass "ranked table orders by real size (rust-target #1)"

# tier totals: safe (uv+target+node_modules) far exceeds decision (ollama only)
safe_kb="$(grep -oE '^TIER_SAFE_KB=[0-9]+' <<<"$out" | cut -d= -f2)"
dec_kb="$(grep -oE '^TIER_DECISION_KB=[0-9]+' <<<"$out" | cut -d= -f2)"
[ "${safe_kb:-0}" -gt "${dec_kb:-0}" ] || fail "safe total ($safe_kb) should exceed decision ($dec_kb)"
[ "${dec_kb:-0}" -ge 2000 ] || fail "decision total should be >= 2000 (ollama), got '$dec_kb'"
pass "tier totals separate safe from decision (safe=$safe_kb decision=$dec_kb)"

grep -q 'UNKNOWN .*BigMovies' <<<"$out" || fail "uncatalogued BigMovies not surfaced as UNKNOWN"
pass "uncatalogued big dir surfaced as UNKNOWN (feedback loop)"

wt_line="$(grep 'SUSPECT id=claude-worktrees ' <<<"$out")"
grep -q 'tier=decision .*path=[^ ]*/repos/agentrepo/\.claude/worktrees ' <<<"$wt_line" \
  || fail "claude-worktrees not matched as decision at agentrepo/.claude/worktrees"
grep -qF "cmd=\"git -C $fx/repos/agentrepo worktree list\"" <<<"$wt_line" \
  || fail "claude-worktrees {parent} should expand to the repo root, got: $wt_line"
grep -q 'path=[^ ]*/repos/other/worktrees' <<<"$wt_line" \
  && fail "bare worktrees/ without .claude/ parent was wrongly matched"
pass "claude-worktrees matched by path suffix beside .git; {parent} = repo root"

# Glob dir target: matches the temp dir, never the live build cache
gb_lines="$(grep 'SUSPECT id=go-build-tmp ' <<<"$out")"
grep -q 'path=[^ ]*/tmp/go-build123456 ' <<<"$gb_lines" || fail "go-build-tmp did not match the temp dir"
grep -q 'path=[^ ]*/\.cache/go-build ' <<<"$gb_lines" && fail "go-build-tmp glob matched the real .cache/go-build"
grep -q 'SUSPECT id=go-build-cache tier=safe .*cmd="go clean -cache"' <<<"$out" || fail "go-build-cache not detected via go clean -cache"
pass "go-build[0-9]* glob matches temp dirs only; .cache/go-build stays go clean -cache"

grep -q 'SUSPECT id=actions-runner-work tier=decision .*r1/_work ' <<<"$out" || fail "runner _work not matched beside .runner"
grep 'SUSPECT id=actions-runner-work' <<<"$out" | grep -q 'repos/other/_work' && fail "_work without .runner was wrongly matched"
pass "actions-runner-work matched only beside a .runner marker"

# Catalog rows that must stay scoped rather than wipe a whole cache
cat_cmd() { awk -F'\t' -v id="$1" '$2==id{print $6}' "$catalog"; }
[ "$(cat_cmd hf-cache)" = "hf cache rm <repo-id> -y" ] || fail "hf-cache should remove per repo, got '$(cat_cmd hf-cache)'"
[ "$(cat_cmd pre-commit-cache)" = "pre-commit gc" ] || fail "pre-commit-cache should use gc, got '$(cat_cmd pre-commit-cache)'"
[ "$(cat_cmd bun-store)" = "bun pm cache rm -g" ] || fail "bun-store should use -g, got '$(cat_cmd bun-store)'"
pass "hf-cache / pre-commit-cache / bun-store commands stay scoped"

# Commands measured to be incomplete in their plain form keep the full form
[ "$(cat_cmd brew-cache)" = "brew cleanup --prune=all -s" ] || fail "brew-cache needs --prune=all (plain -s leaves downloads/), got '$(cat_cmd brew-cache)'"
[ "$(cat_cmd npx-cache)" = "rm -rf {dir}" ] || fail "npx-cache row missing (npm cache clean --force leaves .npm/_npx)"
pass "brew-cache uses --prune=all; npx-cache is catalogued"

# Absolute rows were excluded from the fixture scan; keep them present and never 'safe' to rm
[ "$(awk -F'\t' '$2=="swapfile"{print $5}' "$catalog")" = "decision" ] || fail "swapfile row missing or not tier=decision"
[ "$(awk -F'\t' '$2=="journal"{print $5}' "$catalog")" = "decision" ] || fail "journal row missing or not tier=decision"
pass "absolute-path rows (swapfile, journal) present as decision"

# --- --help and unknown arguments -----------------------------------------
out_help="$(bash "$scan" --help --home-dir "$fx" 2>&1)"
rc_help=$?
[ "$rc_help" -eq 0 ] || fail "--help should exit 0, got $rc_help"
grep -q '^Usage: scan-suspects.sh' <<<"$out_help" || fail "--help should print usage"
grep -q '^=== LINUX DISK SUSPECTS SCAN' <<<"$out_help" && fail "--help must not run a scan"
pass "--help prints usage without scanning"

out_bad="$(bash "$scan" --bogus 2>/dev/null)"
rc_bad=$?
[ "$rc_bad" -eq 2 ] || fail "unknown argument should exit 2, got $rc_bad"
grep -q '^STATUS=ERROR_BAD_ARG$' <<<"$out_bad" || fail "unknown argument should report STATUS=ERROR_BAD_ARG"
pass "unknown argument rejected"

# --- Missing catalog ------------------------------------------------------
out_nocat="$(bash "$scan" --home-dir "$fx" --catalog "$fx/does-not-exist.tsv" 2>&1)"
rc_nocat=$?
grep -q '^STATUS=ERROR_NO_CATALOG$' <<<"$out_nocat" || fail "missing catalog should report ERROR_NO_CATALOG"
[ "$rc_nocat" -ne 0 ] || fail "missing catalog should exit non-zero"
pass "missing catalog fails loudly"

# --- Empty home degrades gracefully ---------------------------------------
empty=$(mktemp -d) || { echo 'mktemp failed' >&2; exit 1; }
if [ -z "$empty" ] || [ ! -d "$empty" ]; then echo 'bad sandbox dir' >&2; exit 1; fi
trap 'rm -rf "$fx" "$empty"' EXIT
out_empty="$(bash "$scan" --home-dir "$empty" --root "$empty" --catalog "$fx_catalog" --min-mb 1)"
rc_empty=$?
[ "$rc_empty" -eq 0 ] || fail "empty home should exit 0"
grep -q '^STATUS=OK$' <<<"$out_empty" || fail "empty home should still report STATUS=OK"
grep -q '^SUSPECT ' <<<"$out_empty" && fail "empty home should surface no suspects"
pass "empty home degrades gracefully"

echo "ALL TESTS PASSED"

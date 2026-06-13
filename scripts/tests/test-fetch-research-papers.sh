#!/usr/bin/env bash
# Offline regression test for scripts/fetch-research-papers.sh.
#
# Exercises the normalize + dedup + date-filter logic without network via the
# RR_FIXTURE_DIR / RR_TODAY test seams. Guards the invariants that a bulk edit
# could silently break:
#   1. All three source formats parse (HF JSON, arXiv Atom, blog RSS).
#   2. The same arXiv id from HF and arXiv is merged to ONE record.
#   3. --seen-file IDs are dropped.
#   4. Items older than --since-days are filtered out.
#   5. The structured summary emits CANDIDATE_COUNT / STATUS / per-source counts.
#
# SKIPs (exit 0) when python3 or jq is unavailable. Non-zero only on real failure.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
target="$repo_root/scripts/fetch-research-papers.sh"

if ! command -v python3 >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: python3 and jq required"
  exit 0
fi

fail=0
check() {
  # check <description> <actual> <expected>
  if [ "$2" = "$3" ]; then
    echo "PASS: $1 ($2)"
  else
    echo "FAIL: $1 — expected '$3', got '$2'"
    fail=1
  fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fixtures="$work/fixtures"
mkdir -p "$fixtures"

# HF daily papers fixture: two papers, one recent + one old. The recent one
# (2606.05922) is also present in the arXiv fixture to prove cross-source merge.
cat > "$fixtures/hf.json" <<'JSON'
[
  {"publishedAt": "2026-06-10T00:00:00.000Z",
   "paper": {"id": "2606.05922", "title": "RHO verify and best-of-N", "summary": "A technique.", "upvotes": 90}},
  {"publishedAt": "2026-06-09T00:00:00.000Z",
   "paper": {"id": "2606.00001", "title": "Recent HF only paper", "summary": "Another.", "upvotes": 5}},
  {"publishedAt": "2026-01-01T00:00:00.000Z",
   "paper": {"id": "2601.99999", "title": "Old paper", "summary": "Stale.", "upvotes": 1000}}
]
JSON

# arXiv Atom fixture: re-lists 2606.05922 (dedup target) + a unique recent paper.
cat > "$fixtures/arxiv.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>http://arxiv.org/abs/2606.05922v2</id>
    <title>RHO verify and best-of-N</title>
    <summary>Same paper, arXiv copy.</summary>
    <published>2026-06-10T00:00:00Z</published>
  </entry>
  <entry>
    <id>http://arxiv.org/abs/2606.07777v1</id>
    <title>Arxiv only recent paper</title>
    <summary>Unique to arXiv.</summary>
    <published>2026-06-11T00:00:00Z</published>
  </entry>
</feed>
XML

# Blog RSS fixture: one recent item with an explicit pubDate.
cat > "$fixtures/blog-1.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <item>
      <title>Agentic eval post</title>
      <link>https://example.com/blog/agentic-eval</link>
      <description>A blog post.</description>
      <pubDate>Wed, 10 Jun 2026 12:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>
XML

run() {
  # run <out> <since_days> [seen_file]
  RR_FIXTURE_DIR="$fixtures" RR_TODAY="2026-06-13" \
    bash "$target" --since-days "$2" --out "$1" \
    ${3:+--seen-file "$3"}
}

# --- Case 1: no seen-file, 8-day window (cutoff 2026-06-05) -------------------
summary="$(run "$work/out1.json" 8)"
total1="$(jq 'length' "$work/out1.json")"
# Expected survivors: 2606.05922 (merged), 2606.00001, 2606.07777, blog → 4.
# Excluded: 2601.99999 (old, outside window).
check "Case 1 candidate count (date-filter + cross-source merge)" "$total1" "4"

dup_count="$(jq '[.[] | select(.id == "2606.05922")] | length' "$work/out1.json")"
check "Case 1 arXiv id merged to single record" "$dup_count" "1"

hf_only_present="$(jq 'any(.[]; .id == "2606.00001")' "$work/out1.json")"
check "Case 1 HF-only recent paper kept" "$hf_only_present" "true"

old_present="$(jq 'any(.[]; .id == "2601.99999")' "$work/out1.json")"
check "Case 1 old paper filtered out" "$old_present" "false"

blog_present="$(jq 'any(.[]; .source == "blog")' "$work/out1.json")"
check "Case 1 blog RSS parsed" "$blog_present" "true"

count_line="$(printf '%s\n' "$summary" | grep -m1 '^CANDIDATE_COUNT=' | cut -d= -f2)"
check "Case 1 structured CANDIDATE_COUNT matches" "$count_line" "4"
status_line="$(printf '%s\n' "$summary" | grep -m1 '^STATUS=' | cut -d= -f2)"
check "Case 1 STATUS=OK when non-empty" "$status_line" "OK"

# --- Case 2: seen-file drops a surfaced id -----------------------------------
seen="$work/seen.txt"
printf '2606.05922\n' > "$seen"
run "$work/out2.json" 8 "$seen" >/dev/null
seen_present="$(jq 'any(.[]; .id == "2606.05922")' "$work/out2.json")"
check "Case 2 seen id dropped" "$seen_present" "false"
total2="$(jq 'length' "$work/out2.json")"
check "Case 2 count drops by one" "$total2" "3"

# --- Case 3: narrow window excludes everything (STATUS=WARN) ------------------
# since-days 1 from 2026-06-13 → cutoff 2026-06-12; only 2606.07777 (06-11)? no,
# 06-11 < 06-12 → excluded too. All filtered → empty, exit 0, STATUS=WARN.
summary3="$(run "$work/out3.json" 1)"
total3="$(jq 'length' "$work/out3.json")"
check "Case 3 narrow window filters all" "$total3" "0"
status3="$(printf '%s\n' "$summary3" | grep -m1 '^STATUS=' | cut -d= -f2)"
check "Case 3 STATUS=WARN on empty" "$status3" "WARN"
exit3=0
run "$work/out3b.json" 1 >/dev/null 2>&1 || exit3=$?
check "Case 3 exit 0 even when empty (parallel-safe)" "$exit3" "0"

echo "=== TEST SUMMARY ==="
if [ "$fail" -eq 0 ]; then
  echo "STATUS=PASS"
  exit 0
else
  echo "STATUS=FAIL"
  exit 1
fi

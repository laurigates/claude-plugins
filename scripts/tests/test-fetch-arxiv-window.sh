#!/usr/bin/env bash
# Regression test for the arXiv arm of scripts/fetch-research-papers.sh.
#
# The bug: the query was a bare
#   http://export.arxiv.org/api/query?search_query=<cats>&sortBy=submittedDate&max_results=80
# with no date qualifier and no `start=` pagination, while the downstream filter
# is discard-only. So --since-days could never widen the largest source: the
# newest 80 submissions were all that could arrive, which across cs.AI/CL/LG/SE/HC
# is about three hours against a promised 8 days. Measured before the fix:
# ARXIV_COUNT=75, identical at --since-days 8, 30 and 90.
#
# The defect lives in the REQUEST, so the emitted counts cannot see it -- a test
# that only asserts on ARXIV_COUNT passes against the broken script. These cases
# stub `curl` and assert on the URLs actually requested.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
FETCH="$repo_root/scripts/fetch-research-papers.sh"

pass=0; fail=0
assert() {
  if [ "$2" = "true" ]; then pass=$((pass+1)); else
    echo "FAIL: $1" >&2; fail=$((fail+1)); fi
}
contains() { printf '%s' "$1" | grep -qF -- "$2" && echo true || echo false; }
matches()  { printf '%s' "$1" | grep -qE -- "$2" && echo true || echo false; }

fx="$(mktemp -d)"; [ -n "$fx" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$fx"' EXIT

# mk_curl <entries-per-page> -- a curl stub that logs each URL and writes an
# Atom page holding N entries, so page fullness (and therefore pagination) is
# controllable from the test.
mk_curl() {
  local n="$1" shim="$fx/shim"
  mkdir -p "$shim"
  cat > "$shim/curl" <<STUB
#!/usr/bin/env bash
url=""; out=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    -*) shift ;;
    *) url="\$1"; shift ;;
  esac
done
echo "\$url" >> "$fx/urls.log"
case "\$url" in
  *export.arxiv.org*)
    {
      echo '<?xml version="1.0" encoding="UTF-8"?>'
      echo '<feed xmlns="http://www.w3.org/2005/Atom">'
      i=0
      while [ \$i -lt $n ]; do
        printf '<entry><id>http://arxiv.org/abs/2609.%05d v1</id>' "\$i" | tr -d ' '
        printf '<title>paper %d</title><published>%sT00:00:00Z</published>' "\$i" "\$(date -u +%Y-%m-%d)"
        printf '<summary>abstract %d</summary></entry>\n' "\$i"
        i=\$((i+1))
      done
      echo '</feed>'
    } > "\$out"
    ;;
  *) printf '<rss><channel></channel></rss>' > "\$out" ;;
esac
exit 0
STUB
  chmod +x "$shim/curl"
  printf '%s' "$shim"
}

run() { # run <entries-per-page> <extra args...>
  local n="$1"; shift
  local shim; shim="$(mk_curl "$n")"
  : > "$fx/urls.log"
  PATH="$shim:$PATH" bash "$FETCH" --out "$fx/out.json" "$@" 2>/dev/null
}

# --- CASE A: the request carries a date window derived from --since-days -----
echo "=== CASE A: --since-days reaches the arXiv REQUEST ==="
run 3 --since-days 8 >/dev/null
urls8="$(cat "$fx/urls.log")"
a_url="$(grep -m1 'export.arxiv.org' "$fx/urls.log" || true)"
assert "A: query carries a submittedDate window" "$(contains "$a_url" 'submittedDate:[')"
assert "A: window is closed with TO" "$(contains "$a_url" '+TO+')"
assert "A: still sorted newest-first" "$(contains "$a_url" 'sortOrder=descending')"
# The old query was plain http. https is not cosmetic on a public API call.
assert "A: uses https" "$(contains "$a_url" 'https://export.arxiv.org')"
assert "A: no http:// arxiv request" \
  "$([ "$(contains "$urls8" 'http://export.arxiv.org')" = false ] && echo true || echo false)"

# --- CASE B: a WIDER window produces a DIFFERENT request --------------------
# The decisive case. Pre-fix, the arXiv URL was byte-identical at every
# --since-days, which is exactly why the count never moved.
echo "=== CASE B: a wider window changes the request ==="
run 3 --since-days 90 >/dev/null
b_url="$(grep -m1 'export.arxiv.org' "$fx/urls.log" || true)"
from8="$(printf '%s' "$a_url"  | grep -oE 'submittedDate:\[[0-9]+' | head -1)"
from90="$(printf '%s' "$b_url" | grep -oE 'submittedDate:\[[0-9]+' | head -1)"
assert "B: an 8-day window has a from-date" "$([ -n "$from8" ] && echo true || echo false)"
assert "B: a 90-day window has a from-date" "$([ -n "$from90" ] && echo true || echo false)"
assert "B: the two windows DIFFER" \
  "$([ "$from8" != "$from90" ] && echo true || echo false)"
assert "B: the wider window reaches further back" \
  "$([ "${from90##*[}" -lt "${from8##*[}" ] && echo true || echo false)"

# --- CASE C: a FULL page paginates; a SHORT page stops ----------------------
# Guard integrity in both directions: without the short-page case, a script that
# always fetched every page to the cap would pass C1.
echo "=== CASE C: pagination follows page fullness ==="
run 100 --since-days 8 --arxiv-max 150 >/dev/null
n_full="$(grep -c 'export.arxiv.org' "$fx/urls.log" || true)"
assert "C: a full page triggers a second request" \
  "$([ "${n_full:-0}" -ge 2 ] && echo true || echo false)"
assert "C: the second request carries start=" \
  "$(matches "$(cat "$fx/urls.log")" 'start=100')"

run 3 --since-days 8 --arxiv-max 400 >/dev/null
n_short="$(grep -c 'export.arxiv.org' "$fx/urls.log" || true)"
assert "C: a short page stops after ONE request" \
  "$([ "${n_short:-0}" -eq 1 ] && echo true || echo false)"

# --- CASE D: truncation is reported, both polarities ------------------------
# A key emitted only when true is indistinguishable from one nobody emitted.
echo "=== CASE D: ARXIV_TRUNCATED is always emitted ==="
out_trunc="$(run 100 --since-days 8 --arxiv-max 100)"
assert "D: hitting the cap reports TRUNCATED=true" "$(contains "$out_trunc" 'ARXIV_TRUNCATED=true')"
assert "D: the cap is reported too" "$(contains "$out_trunc" 'ARXIV_MAX=100')"
out_ok="$(run 3 --since-days 8 --arxiv-max 400)"
assert "D: an unbounded run reports TRUNCATED=false" "$(contains "$out_ok" 'ARXIV_TRUNCATED=false')"
# Non-vacuity: the run must actually have parsed the stubbed entries, or every
# assertion above holds for a fetch that returned nothing.
assert "D: the stubbed entries were parsed" \
  "$([ "$(contains "$out_ok" 'ARXIV_COUNT=0')" = false ] && echo true || echo false)"
assert "D: exit 0 preserved (parallel-safe)" "$(contains "$out_ok" 'STATUS=OK')"

echo ""
echo "PASSED=$pass"
echo "FAILED=$fail"
[ "$fail" -gt 0 ] && { echo "STATUS=FAIL"; exit 1; }
echo "STATUS=OK"

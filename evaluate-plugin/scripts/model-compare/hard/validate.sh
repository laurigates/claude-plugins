#!/usr/bin/env bash
# For every task: fixture alone must score <= 0.4; fixture + oracle overlay must score 1.0.
set -u
P2B=$(cd "$(dirname "$0")" && pwd)
python3 "$P2B/make_tasks.py" >/dev/null || { echo "make_tasks.py failed"; exit 2; }
fail=0
printf '%-26s %6s %8s %7s %6s  %s\n' TASK CASES FIXTURE ORACLE LINES STATUS
for t in "$P2B"/tasks/*/; do
  id=$(basename "$t")
  [ -n "${ONLY:-}" ] && [ "$id" != "$ONLY" ] && continue
  W1=$(mktemp -d); W2=$(mktemp -d)
  cp -r "$t/fixture/." "$W1/"
  cp -r "$t/fixture/." "$W2/"; cp -r "$P2B/oracle/$id/." "$W2/"
  r1=$(cd /tmp && timeout 600 python3 -I "$t/check.py" "$W1" 2>/dev/null | tail -1)
  r2=$(cd /tmp && timeout 600 python3 -I "$t/check.py" "$W2" 2>/dev/null | tail -1)
  s1=$(printf '%s' "$r1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["score"])' 2>/dev/null || echo ERR)
  s2=$(printf '%s' "$r2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["score"])' 2>/dev/null || echo ERR)
  n=$(printf '%s' "$r2" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("cases", "?"))' 2>/dev/null || echo ?)
  lines=$(find "$t/fixture" -type f -exec cat {} + | wc -l)
  ok=$(python3 -c "import sys; a,b=sys.argv[1:]; print('OK' if a!='ERR' and b!='ERR' and float(a)<=0.4 and float(b)==1.0 else 'FAIL')" "$s1" "$s2")
  [ "$ok" = OK ] || fail=1
  printf '%-26s %6s %8s %7s %6s  %s\n' "$id" "$n" "$s1" "$s2" "$lines" "$ok"
  if [ "$ok" != OK ] || [ -n "${VERBOSE:-}" ]; then
    echo "   fixture: $r1"; echo "   oracle:  $r2"
  fi
  rm -rf "$W1" "$W2"
done
exit $fail

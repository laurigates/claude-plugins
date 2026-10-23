#!/usr/bin/env bash
# Validate the basic set: build tasks/, then for every task the untouched
# fixture must score below 1.0 and the fixture plus the reference solution
# below must score exactly 1.0. Exits 1 if any task breaks that contract.
set -u
P2=$(cd "$(dirname "$0")" && pwd)
python3 "$P2/make_tasks.py" >/dev/null || { echo "make_tasks.py failed"; exit 2; }
subst() { # file old new: literal in-place replacement (portable, no sed -i)
  python3 -c 'import sys; p,a,b=sys.argv[1:]; s=open(p).read(); open(p,"w").write(s.replace(a,b))' "$@"
}
score() { python3 -c 'import json,sys; print(json.loads(sys.argv[1])["score"])' "$1" 2>/dev/null || echo ERR; }
sol() { # task -> writes solution into $W
case "$1" in
t1-stats-bugfix) cat > "$W/stats.py" <<'PY'
def moving_average(xs, k):
    if k < 1 or k > len(xs):
        raise ValueError("bad k")
    return [sum(xs[i:i + k]) / k for i in range(len(xs) - k + 1)]
def median(xs):
    if not xs:
        raise ValueError("empty")
    s = sorted(xs); n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2
PY
;;
t2-intervals-bugfix) cat > "$W/intervals.py" <<'PY'
def merge_intervals(intervals):
    out = []
    for s, e in sorted(intervals):
        if out and s <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], e))
        else:
            out.append((s, e))
    return out
PY
;;
t3-lru-feature) cat > "$W/lru.py" <<'PY'
from collections import OrderedDict
class LRUCache:
    def __init__(self, capacity):
        self.c = capacity; self.d = OrderedDict()
    def get(self, k):
        if k not in self.d: return -1
        self.d.move_to_end(k); return self.d[k]
    def put(self, k, v):
        if self.c <= 0: return
        self.d[k] = v; self.d.move_to_end(k)
        while len(self.d) > self.c: self.d.popitem(last=False)
    def __len__(self): return len(self.d)
PY
;;
t4-refactor)
cat > "$W/util.py" <<'PY'
def compute_invoice_total(items, tax_rate, *, discount=0):
    subtotal = sum(p * q for p, q in items) * (1 - discount)
    return round(subtotal * (1 + tax_rate), 2)
PY
subst "$W/billing.py" calc_total compute_invoice_total
subst "$W/report.py" calc_total compute_invoice_total ;;
t5-test-triage) python3 -c "
import json,re,sys
src=open('$P2/tasks/t5-test-triage/check.py').read()
t=json.loads(json.loads(re.search(r'truth = json.loads\((.*)\)\n', src).group(1)))
json.dump(t, open('$W/triage.json','w'))" ;;
t6-log-analysis) python3 -c "
import json,re
src=open('$P2/tasks/t6-log-analysis/check.py').read()
t=json.loads(json.loads(re.search(r'truth = json.loads\((.*)\)\n', src).group(1)))
json.dump(t, open('$W/answers.json','w'))" ;;
t7-cache-diagnosis)
subst "$W/orders.py" 'CACHE.delete(f"stock:{sku}")' 'CACHE.delete(f"stock:{sku}"); CACHE.delete(f"batch:{sku}")'
echo "The batch endpoint caches under batch:<sku>, which place_order never invalidates. Orders now delete both keys." > "$W/diagnosis.md" ;;
t8-decompose) cat > "$W/plan.json" <<'PY'
{"subtasks": [
 {"id": "s1", "files": ["money.py"], "depends_on": [], "brief": "Add a required currency argument to format_amount in money.py returning 'EUR 12.50' style."},
 {"id": "s2", "files": ["invoice.py", "export_csv.py", "email_receipt.py"], "depends_on": ["s1"], "brief": "Update every format_amount caller in these files to pass the record's ISO currency code."}
]}
PY
;;
esac
}
fail=0
printf '%-22s %8s %7s  %s\n' TASK FIXTURE ORACLE STATUS
for t in "$P2"/tasks/*/; do
  id=$(basename "$t"); W0=$(mktemp -d) && W=$(mktemp -d) || exit 2
  cp -r "$t/fixture/." "$W0/"; cp -r "$t/fixture/." "$W/"; sol "$id"
  s0=$(score "$(cd "${TMPDIR:-/tmp}" && python3 -I "$t/check.py" "$W0" 2>/dev/null | tail -1)")
  s1=$(score "$(cd "${TMPDIR:-/tmp}" && python3 -I "$t/check.py" "$W" 2>/dev/null | tail -1)")
  ok=FAIL
  [ "$s0" != ERR ] || s0=0
  python3 -c 'import sys; a,b=sys.argv[1:]; sys.exit(0 if b != "ERR" and float(a) < 1.0 and float(b) == 1.0 else 1)' "$s0" "$s1" && ok=OK
  [ "$ok" = OK ] || fail=1
  printf '%-22s %8s %7s  %s\n' "$id" "$s0" "$s1" "$ok"
  rm -rf "$W0" "$W"
done
exit $fail

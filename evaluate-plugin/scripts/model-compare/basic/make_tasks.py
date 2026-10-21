#!/usr/bin/env python3
"""Generate the Phase 2 synthetic task set.

Each task: tasks/<id>/fixture/ (copied into a fresh workdir per run),
tasks/<id>/prompt.txt, tasks/<id>/check.py (hidden; run as
`python3 -I check.py <workdir>`, prints JSON {"score": 0..1, "detail": ...}).
"""

import json
import random
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parent / "tasks"


def w(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(text).lstrip("\n"))


def task(tid, prompt, files, check, claim):
    d = ROOT / tid
    for rel, body in files.items():
        w(d / "fixture" / rel, body)
    w(d / "prompt.txt", prompt)
    w(d / "check.py", check)
    (d / "meta.json").write_text(json.dumps({"id": tid, "claims": claim}))


CHECK_HEAD = """
import json, sys, importlib.util, os
WD = sys.argv[1]
sys.path.insert(0, WD)
os.chdir(WD)
results = []
def _setup_failed(etype, value, tb):
    # A missing or unreadable deliverable aborts the grader before any case
    # runs; report that as a zero score, never as a crash.
    print(json.dumps({"score": 0, "detail": [f"grader setup failed: {etype.__name__}: {value}"]}))
sys.excepthook = _setup_failed
def case(name, fn):
    try:
        ok = bool(fn())
    except Exception as e:
        ok = False
        name += f" ({type(e).__name__})"
    results.append((name, ok))
def done():
    passed = sum(ok for _, ok in results)
    print(json.dumps({"score": round(passed / len(results), 3),
                      "detail": [n for n, ok in results if not ok]}))
"""

# ---------------------------------------------------------------- T1
task(
    "t1-stats-bugfix",
    """
    The tests in test_stats.py fail. Fix stats.py so that `python3 test_stats.py`
    passes. Do not modify test_stats.py. Keep the existing function signatures.
    """,
    {
        "stats.py": '''
            def moving_average(xs, k):
                """Mean of each window of k consecutive values; len(xs)-k+1 results.
                Raise ValueError if k < 1 or k > len(xs)."""
                if k < 1:
                    raise ValueError("k must be >= 1")
                out = []
                for i in range(len(xs) - k):
                    out.append(sum(xs[i:i + k]) / k)
                return out


            def median(xs):
                """Median of a non-empty list; mean of the two middle values when even.
                Raise ValueError on an empty list. Must not mutate xs."""
                xs.sort()
                n = len(xs)
                return xs[n // 2]
            ''',
        "test_stats.py": """
            from stats import moving_average, median

            assert moving_average([1, 2, 3, 4], 2) == [1.5, 2.5, 3.5]
            assert median([3, 1, 2]) == 2
            assert median([4, 1, 3, 2]) == 2.5
            print("ok")
            """,
    },
    CHECK_HEAD
    + """
from stats import moving_average, median
case("ma basic", lambda: moving_average([1, 2, 3, 4], 2) == [1.5, 2.5, 3.5])
case("ma k=len", lambda: moving_average([2, 4, 6], 3) == [4.0])
case("ma k=1", lambda: moving_average([5, 7], 1) == [5.0, 7.0])
def raises(fn):
    try: fn()
    except ValueError: return True
    return False
case("ma k>len raises", lambda: raises(lambda: moving_average([1, 2], 3)))
case("ma k=0 raises", lambda: raises(lambda: moving_average([1, 2], 0)))
case("median odd", lambda: median([3, 1, 2]) == 2)
case("median even", lambda: median([4, 1, 3, 2]) == 2.5)
case("median empty raises", lambda: raises(lambda: median([])))
def nomut():
    xs = [3, 1, 2]; median(xs); return xs == [3, 1, 2]
case("median no mutation", nomut)
case("median single", lambda: median([7]) == 7)
done()
""",
    ["C1", "C2", "C4"],
)

# ---------------------------------------------------------------- T2
task(
    "t2-intervals-bugfix",
    """
    merge_intervals in intervals.py has bugs; read its docstring for the
    contract. Fix it. A quick sanity script is in check_intervals.py.
    """,
    {
        "intervals.py": '''
            def merge_intervals(intervals):
                """Merge overlapping closed intervals.

                - Input: list of (start, end) tuples with start <= end, in any order.
                - Intervals that overlap OR touch (end == next start) are merged.
                - Output: list of (start, end) tuples sorted by start.
                - The input list must not be modified.
                - An empty input returns [].
                """
                out = []
                for s, e in intervals:
                    if out and s < out[-1][1]:
                        out[-1] = (out[-1][0], e)
                    else:
                        out.append((s, e))
                return out
            ''',
        "check_intervals.py": """
            from intervals import merge_intervals
            print(merge_intervals([(1, 3), (2, 6), (8, 10)]))  # expect [(1, 6), (8, 10)]
            """,
    },
    CHECK_HEAD
    + """
from intervals import merge_intervals as m
case("basic", lambda: m([(1, 3), (2, 6), (8, 10)]) == [(1, 6), (8, 10)])
case("unsorted", lambda: m([(8, 10), (1, 3), (2, 6)]) == [(1, 6), (8, 10)])
case("touching", lambda: m([(1, 3), (3, 5)]) == [(1, 5)])
case("contained", lambda: m([(1, 10), (2, 3)]) == [(1, 10)])
case("empty", lambda: m([]) == [])
case("single", lambda: m([(4, 4)]) == [(4, 4)])
case("chain", lambda: m([(5, 6), (1, 2), (2, 5)]) == [(1, 6)])
case("disjoint", lambda: m([(3, 4), (1, 2)]) == [(1, 2), (3, 4)])
def nomut():
    xs = [(8, 10), (1, 3)]; m(xs); return xs == [(8, 10), (1, 3)]
case("no mutation", nomut)
case("negative", lambda: m([(-5, -1), (-2, 0)]) == [(-5, 0)])
done()
""",
    ["C1", "C2", "C4"],
)

# ---------------------------------------------------------------- T3
task(
    "t3-lru-feature",
    """
    Implement the LRUCache class in lru.py according to the spec in its
    docstring. Use only the standard library.
    """,
    {
        "lru.py": '''
            class LRUCache:
                """Least-recently-used cache.

                LRUCache(capacity: int)  -- capacity >= 0
                get(key) -> value, or -1 when absent. A hit marks the key most recently used.
                put(key, value) -> None. Inserts or updates; either marks the key most
                    recently used. When an insert would exceed capacity, evict the least
                    recently used key first. With capacity 0, put stores nothing.
                __len__() -> number of stored keys.
                """

                def __init__(self, capacity):
                    raise NotImplementedError
            ''',
    },
    CHECK_HEAD
    + """
from lru import LRUCache
def basic():
    c = LRUCache(2); c.put(1, 1); c.put(2, 2)
    a = c.get(1); c.put(3, 3)
    return a == 1 and c.get(2) == -1 and c.get(3) == 3 and c.get(1) == 1
case("eviction order", basic)
def update():
    c = LRUCache(2); c.put(1, 1); c.put(2, 2); c.put(1, 10); c.put(3, 3)
    return c.get(1) == 10 and c.get(2) == -1
case("update refreshes", update)
def zero():
    c = LRUCache(0); c.put(1, 1); return c.get(1) == -1 and len(c) == 0
case("capacity 0", zero)
def length():
    c = LRUCache(3); [c.put(i, i) for i in range(5)]; return len(c) == 3
case("len", length)
case("missing", lambda: LRUCache(1).get("x") == -1)
def many():
    c = LRUCache(100)
    for i in range(10000): c.put(i, i)
    return len(c) == 100 and c.get(9999) == 9999 and c.get(9899) == -1
case("many", many)
def none_val():
    c = LRUCache(1); c.put("a", None); return c.get("a") is None
case("None value", none_val)
done()
""",
    ["C1", "C2", "C4"],
)

# ---------------------------------------------------------------- T4
task(
    "t4-refactor",
    """
    Rename the function calc_total to compute_invoice_total everywhere in this
    project, and give it a new keyword-only parameter `discount` (default 0, a
    fraction such as 0.1 for 10%) that is applied to the subtotal before tax.
    Existing behaviour for callers that pass no discount must not change.
    """,
    {
        "util.py": '''
            def calc_total(items, tax_rate):
                """items: list of (price, qty). Returns subtotal * (1 + tax_rate), rounded to cents."""
                subtotal = sum(p * q for p, q in items)
                return round(subtotal * (1 + tax_rate), 2)
            ''',
        "billing.py": """
            from util import calc_total


            def invoice(items, region):
                rate = {"fi": 0.255, "se": 0.25}.get(region, 0.0)
                return {"total": calc_total(items, rate), "region": region}
            """,
        "report.py": """
            import util


            def daily(orders):
                return sum(util.calc_total(o, 0.0) for o in orders)
            """,
    },
    CHECK_HEAD
    + """
import re, glob
src = "".join(open(f).read() for f in glob.glob("*.py"))
case("old name gone", lambda: re.search(r"\\bcalc_total\\b", src) is None)
import util, billing, report
f = util.compute_invoice_total
case("same result no discount", lambda: f([(10, 2), (5, 1)], 0.255) == round(25 * (1 + 0.255), 2))
case("discount before tax", lambda: f([(100, 1)], 0.25, discount=0.1) == 112.5)
def kwonly():
    try: f([(1, 1)], 0.0, 0.5)
    except TypeError: return True
    return False
case("discount keyword-only", kwonly)
case("billing works", lambda: billing.invoice([(10, 1)], "fi") == {"total": 12.55, "region": "fi"})
case("report works", lambda: report.daily([[(10, 1)], [(5, 2)]]) == 20.0)
done()
""",
    ["C1", "C2", "C4"],
)

# ---------------------------------------------------------------- T5 test triage
random.seed(7)
causes = {
    "A": "ModuleNotFoundError: No module named 'yaml'",
    "B": "rounding change in money.round_cents",
    "C": "network fixture timeout (flaky)",
    "D": "missing 'region' key in config",
}
# Failures: test name, ground-truth cause, traceback text. Some surface errors
# differ from the root cause (D shows up as a TypeError downstream; B as an
# assertion in an unrelated-looking test).
fails = [
    (
        "tests/test_config.py::test_load_defaults",
        "A",
        "tests/test_config.py:3: in <module>\n    import yaml\nE   ModuleNotFoundError: No module named 'yaml'",
    ),
    (
        "tests/test_config.py::test_override_env",
        "A",
        "tests/test_config.py:3: in <module>\n    import yaml\nE   ModuleNotFoundError: No module named 'yaml'",
    ),
    (
        "tests/test_money.py::test_round_half",
        "B",
        "    assert round_cents(2.675) == 2.68\nE   assert 2.67 == 2.68\nE    +  where 2.67 = round_cents(2.675)",
    ),
    (
        "tests/test_invoice.py::test_total_with_tax",
        "B",
        "    assert inv.total == Decimal('31.38')\nE   AssertionError: assert Decimal('31.37') == Decimal('31.38')\n\napp/invoice.py:41: total = money.round_cents(subtotal * (1 + rate))",
    ),
    (
        "tests/test_report.py::test_daily_sum",
        "B",
        "    assert report.daily(orders) == 1045.05\nE   assert 1045.04 == 1045.05\n\napp/report.py:12: return money.round_cents(sum(...))",
    ),
    (
        "tests/test_sync.py::test_push_remote",
        "C",
        "conftest.py:58: in remote_api\n    resp = session.get(url, timeout=2)\nE   requests.exceptions.ReadTimeout: HTTPSConnectionPool(host='staging.internal', port=443): Read timed out. (read timeout=2)",
    ),
    (
        "tests/test_sync.py::test_pull_remote",
        "C",
        "conftest.py:58: in remote_api\n    resp = session.get(url, timeout=2)\nE   requests.exceptions.ReadTimeout: HTTPSConnectionPool(host='staging.internal', port=443): Read timed out. (read timeout=2)",
    ),
    (
        "tests/test_shipping.py::test_rate_lookup",
        "D",
        "app/shipping.py:22: in rate_for\n    zone = ZONES[cfg['region']]\nE   KeyError: 'region'",
    ),
    (
        "tests/test_shipping.py::test_free_threshold",
        "D",
        "app/shipping.py:30: in free_threshold\n    return THRESHOLDS.get(cfg.get('region')) * 1.0\nE   TypeError: unsupported operand type(s) for *: 'NoneType' and 'float'",
    ),
    (
        "tests/test_tax.py::test_vat_lookup",
        "D",
        "app/tax.py:15: in vat\n    return VAT[region.lower()]\nE   AttributeError: 'NoneType' object has no attribute 'lower'\n\napp/tax.py:9: region = settings.get('region')",
    ),
    (
        "tests/test_export.py::test_csv_amounts",
        "B",
        "    assert rows[1][3] == '19.99'\nE   AssertionError: assert '19.98' == '19.99'\n\napp/export.py:27: fmt = f\"{money.round_cents(x):.2f}\"",
    ),
    (
        "tests/test_health.py::test_upstream_ping",
        "C",
        "conftest.py:58: in remote_api\n    resp = session.get(url, timeout=2)\nE   requests.exceptions.ConnectTimeout: HTTPSConnectionPool(host='staging.internal', port=443): Max retries exceeded",
    ),
]
random.shuffle(fails)
log = [
    "============================= test session starts ==============================",
    "collected 214 items",
    "",
]
for name, _, tb in fails:
    log += [f"_________________ {name.split('::')[1]} _________________", tb, ""]
log += [
    "=========================== short test summary info ============================"
]
log += [f"FAILED {n}" for n, _, _ in fails]
log += [
    f"================= {len(fails)} failed, 202 passed in 41.20s ================="
]
truth = {n: c for n, _, c in [(f[0], None, f[1]) for f in fails]}
task(
    "t5-test-triage",
    """
    pytest_output.log is the output of a CI test run. Every failure has exactly
    one of these root causes:

      A: the PyYAML dependency is missing from the environment
      B: a recent change to money.round_cents (rounding mode)
      C: a flaky network fixture timing out against the staging server
      D: the deployed config no longer contains the 'region' key

    Classify every failing test. Write triage.json mapping each full failing
    test id (as printed after FAILED) to one letter, e.g.
    {"tests/test_x.py::test_y": "A"}. Note the visible exception is not always
    the root cause.
    """,
    {"pytest_output.log": "\n".join(log) + "\n"},
    CHECK_HEAD
    + f"""
truth = json.loads({json.dumps(json.dumps(truth))})
got = json.load(open("triage.json"))
for k, v in truth.items():
    case(k, lambda k=k, v=v: str(got.get(k, "")).strip().upper() == v)
done()
""",
    ["C6"],
)

# ---------------------------------------------------------------- T6 log analysis
random.seed(11)
svcs = ["api", "auth", "billing", "search", "worker"]
lines, errs = [], {s: 0 for s in svcs}
first_burst = None
streak = {"svc": None, "n": 0}
t0 = 0
for i in range(1500):
    t0 += random.randint(1, 4)
    s = random.choice(svcs)
    lvl = (
        "ERROR"
        if random.random() < (0.12 if s == "billing" else 0.05)
        else random.choice(["INFO"] * 8 + ["WARN"])
    )
    # Planted near-miss (billing, billing, auth, billing) and the real burst.
    forced = {
        400: "billing",
        401: "billing",
        402: "auth",
        403: "billing",
        404: "api",
        900: "search",
        901: "search",
        902: "search",
    }
    if i in forced:
        s, lvl = forced[i], ("INFO" if i == 404 else "ERROR")
    hh, mm, ss = t0 // 3600, (t0 // 60) % 60, t0 % 60
    ts = f"2026-10-14T{8 + hh:02d}:{mm:02d}:{ss:02d}Z"
    lines.append(
        f'{ts} level={lvl} service={s} msg="{"request failed" if lvl == "ERROR" else "ok"}" req_id={1000 + i}'
    )
    if lvl == "ERROR":
        errs[s] += 1
        if streak["svc"] == s:
            streak["n"] += 1
        else:
            streak = {"svc": s, "n": 1}
        if streak["n"] == 3 and first_burst is None:
            first_burst = ts
    else:
        # only ERROR lines count toward a streak; any non-ERROR line from any service resets
        streak = {"svc": None, "n": 0}
answers = {
    "total_errors": sum(errs.values()),
    "top_service": max(errs, key=errs.get),
    "first_burst_ts": first_burst,
}
task(
    "t6-log-analysis",
    """
    Analyse app.log and write answers.json with exactly these keys:
      total_errors   -- number of lines with level=ERROR
      top_service    -- the service with the most ERROR lines
      first_burst_ts -- timestamp of the line that completes the first run of
                        3 consecutive log lines that are all level=ERROR from
                        the same service (null if none)
    """,
    {"app.log": "\n".join(lines) + "\n"},
    CHECK_HEAD
    + f"""
truth = json.loads({json.dumps(json.dumps(answers))})
got = json.load(open("answers.json"))
for k, v in truth.items():
    case(k, lambda k=k, v=v: got.get(k) == v)
done()
""",
    ["C1", "C2", "W7"],
)

# ---------------------------------------------------------------- T7 big picture
task(
    "t7-cache-diagnosis",
    """
    Bug report: "After an order is placed, the stock shown for an item is stale
    for up to 60 seconds, but only if that item was previously fetched through
    the batch endpoint. Single-item lookups that were never batch-fetched update
    immediately."

    Find the root cause, fix it in the code, and write a two-sentence
    explanation to diagnosis.md. Keep the caching (do not remove it).
    """,
    {
        "cache.py": """
            import time

            class TTLCache:
                def __init__(self, ttl=60, clock=time.monotonic):
                    self.ttl, self.clock, self._d = ttl, clock, {}

                def get(self, key):
                    hit = self._d.get(key)
                    if hit and self.clock() - hit[1] < self.ttl:
                        return hit[0]
                    return None

                def set(self, key, value):
                    self._d[key] = (value, self.clock())

                def delete(self, key):
                    self._d.pop(key, None)

            CACHE = TTLCache()
            """,
        "inventory.py": """
            STOCK = {"sku-1": 10, "sku-2": 5, "sku-3": 0}

            def read_stock(sku):
                return STOCK.get(sku, 0)

            def decrement(sku, qty):
                STOCK[sku] = read_stock(sku) - qty
            """,
        "api.py": """
            from cache import CACHE
            import inventory

            def _key(sku):
                return f"stock:{sku}"

            def get_stock(sku):
                v = CACHE.get(_key(sku))
                if v is None:
                    v = inventory.read_stock(sku)
                    CACHE.set(_key(sku), v)
                return v

            def get_stock_batch(skus):
                out = {}
                for sku in skus:
                    v = CACHE.get(f"batch:{sku}")
                    if v is None:
                        v = inventory.read_stock(sku)
                        CACHE.set(f"batch:{sku}", v)
                        CACHE.set(_key(sku), v)
                    out[sku] = v
                return out
            """,
        "orders.py": """
            from cache import CACHE
            import inventory

            def place_order(sku, qty):
                inventory.decrement(sku, qty)
                CACHE.delete(f"stock:{sku}")
                return {"sku": sku, "qty": qty}
            """,
    },
    CHECK_HEAD
    + """
import importlib
def fresh():
    for m in ["cache", "inventory", "api", "orders"]:
        sys.modules.pop(m, None)
    import cache, inventory, api, orders
    return cache, inventory, api, orders
def batch_then_order():
    cache, inv, api, orders = fresh()
    api.get_stock_batch(["sku-1", "sku-2"])
    orders.place_order("sku-1", 3)
    return api.get_stock_batch(["sku-1"])["sku-1"] == 7 and api.get_stock("sku-1") == 7
case("batch fresh after order", batch_then_order)
def single_then_order():
    cache, inv, api, orders = fresh()
    api.get_stock("sku-2"); orders.place_order("sku-2", 1)
    return api.get_stock("sku-2") == 4
case("single fresh after order", single_then_order)
def still_cached():
    cache, inv, api, orders = fresh()
    api.get_stock_batch(["sku-1"])
    inv.STOCK["sku-1"] = 999  # out-of-band change, no invalidation
    return api.get_stock_batch(["sku-1"])["sku-1"] == 10 and api.get_stock("sku-1") == 10
case("caching kept", still_cached)
case("diagnosis written", lambda: os.path.getsize("diagnosis.md") > 40)
done()
""",
    ["C5"],
)

# ---------------------------------------------------------------- T8 decomposition
mods = {
    "money.py": """
        def format_amount(x):
            return f"{x:.2f}"
        """,
    "invoice.py": """
        from money import format_amount

        def render(inv):
            return f"Invoice {inv['id']}: {format_amount(inv['total'])}"
        """,
    "export_csv.py": """
        import money

        def row(o):
            return ",".join([o["id"], money.format_amount(o["amount"])])
        """,
    "email_receipt.py": """
        from money import format_amount as fmt

        def body(o):
            return f"Thanks! You paid {fmt(o['amount'])}."
        """,
    "auth.py": """
        def check(user, pw):
            return user == "admin" and pw == "secret"
        """,
    "search.py": """
        def search(items, q):
            # amounts are compared numerically here, never formatted
            return [i for i in items if q in i["name"]]
        """,
    "dashboard.py": """
        from invoice import render

        def panel(invs):
            return "\\n".join(render(i) for i in invs)
        """,
}
task(
    "t8-decompose",
    """
    You are the coordinator. The feature to build: "amounts must be formatted
    with an ISO currency code (e.g. 'EUR 12.50'); format_amount gains a required
    currency argument, and every caller must pass one."

    Do NOT implement it. Instead write plan.json for parallel worker agents:
    {"subtasks": [{"id": "s1", "files": ["..."], "depends_on": [], "brief": "..."}]}
    Rules: at most 4 subtasks; every file that must change appears in exactly
    one subtask; do not include files that need no change; depends_on lists ids
    of subtasks that must finish first (no cycles); each brief is at most 60
    words and must be self-contained for a worker who has not seen this task.
    """,
    mods,
    CHECK_HEAD
    + """
need = {"money.py", "invoice.py", "export_csv.py", "email_receipt.py"}
plan = json.load(open("plan.json"))
subs = plan.get("subtasks", [])
ids = [s.get("id") for s in subs]
files = [f for s in subs for f in s.get("files", [])]
case("<=4 subtasks", lambda: 1 <= len(subs) <= 4)
case("unique ids", lambda: len(set(ids)) == len(ids))
case("deps valid", lambda: all(d in ids for s in subs for d in s.get("depends_on", [])))
def acyclic():
    g = {s["id"]: set(s.get("depends_on", [])) for s in subs}
    seen = set()
    while g:
        ready = [k for k, v in g.items() if v <= seen]
        if not ready: return False
        for k in ready: seen.add(k); g.pop(k)
    return True
case("acyclic", acyclic)
case("no file twice", lambda: len(files) == len(set(files)))
case("covers needed", lambda: need <= set(files))
case("no extras", lambda: set(files) <= need)
case("briefs <=60 words", lambda: all(0 < len(str(s.get("brief", "")).split()) <= 60 for s in subs))
def money_first():
    own = {f: s["id"] for s in subs for f in s.get("files", [])}
    m = own.get("money.py")
    return m is not None and all(m in s.get("depends_on", []) or s["id"] == m for s in subs if set(s.get("files", [])) & (need - {"money.py"}))
case("money.py ordered first", money_first)
case("not implemented", lambda: "currency" not in open("money.py").read())
done()
""",
    ["C8", "W2"],
)

print("t6 truth:", answers)
print("tasks:", sorted(p.name for p in ROOT.iterdir()))

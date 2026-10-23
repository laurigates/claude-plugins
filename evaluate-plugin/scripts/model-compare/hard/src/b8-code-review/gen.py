"""Generate the b8 review task: before/after sources -> change.patch + repo/ (post-change),
hidden truth (planted bug lines, harmless-change lines) and the oracle findings.json."""
import difflib
import json
import shutil
import textwrap
from pathlib import Path

HERE = Path(__file__).resolve().parent


def d(s):
    return textwrap.dedent(s).lstrip("\n")


FILES = {}  # rel -> (before, after)

FILES["inventory/batching.py"] = (d('''
    """Helpers for processing inventory updates in batches."""


    def chunked(items, size):
        """Split ``items`` into consecutive lists of at most ``size`` elements."""
        if size < 1:
            raise ValueError("size must be >= 1")
        return [items[i:i + size] for i in range(0, len(items), size)]


    def window_starts(n, size):
        """Start offsets of every full window of ``size`` over ``n`` elements."""
        return list(range(0, n - size + 1))


    def flush_all(updates, sink, size=100):
        for batch in chunked(updates, size):
            sink.write_many(batch)
    '''), d('''
    """Helpers for processing inventory updates in batches."""


    def chunked(items, size):
        """Split ``items`` into consecutive lists of at most ``size`` elements.

        Works on any iterable (generators included) without materialising it.
        """
        if size < 1:
            raise ValueError("size must be >= 1")
        chunks, current = [], []
        for item in items:
            current.append(item)
            if len(current) == size:
                chunks.append(current)
                current = []
        if len(current) > 1:
            chunks.append(current)
        return chunks


    def window_starts(n, size):
        """Start offsets of every full window of ``size`` over ``n`` elements."""
        return list(range(n - size + 1))


    def flush_all(updates, sink, size=100):
        """Write ``updates`` to ``sink`` in batches of ``size``."""
        for batch in chunked(updates, size):
            sink.write_many(batch)
    '''))

FILES["inventory/stock.py"] = (d('''
    import logging
    import threading

    log = logging.getLogger(__name__)


    class InsufficientStock(Exception):
        pass


    class StockLedger:
        """Thread-safe on-hand quantities per SKU."""

        def __init__(self):
            self._lock = threading.Lock()
            self._levels = {}

        def adjust(self, sku, delta):
            with self._lock:
                current = self._levels.get(sku, 0)
                new = current + delta
                if new < 0:
                    raise InsufficientStock(sku)
                self._levels[sku] = new
                log.debug("stock %s: %d -> %d", sku, current, new)
                return new

        def level(self, sku):
            with self._lock:
                return self._levels.get(sku, 0)

        def snapshot(self):
            self._lock.acquire()
            try:
                return dict(self._levels)
            finally:
                self._lock.release()
    '''), d('''
    import logging
    import threading

    log = logging.getLogger(__name__)


    class InsufficientStock(Exception):
        def __init__(self, sku, available=None, requested=None):
            super().__init__(sku)
            self.sku, self.available, self.requested = sku, available, requested


    class StockLedger:
        """Thread-safe on-hand quantities per SKU."""

        def __init__(self):
            self._lock = threading.Lock()
            self._levels = {}

        def adjust(self, sku, delta):
            # keep the critical section short: validation and logging happen outside it
            with self._lock:
                current = self._levels.get(sku, 0)
            new = current + delta
            if new < 0:
                raise InsufficientStock(sku, available=current, requested=-delta)
            log.debug("stock %s: %d -> %d", sku, current, new)
            with self._lock:
                self._levels[sku] = new
            return new

        def level(self, sku):
            with self._lock:
                return self._levels.get(sku, 0)

        def snapshot(self):
            with self._lock:
                return dict(self._levels)
    '''))

FILES["inventory/search.py"] = (d('''
    import logging

    log = logging.getLogger(__name__)

    MAX_LIMIT = 50


    def search_products(conn, term, limit=20):
        """Case-insensitive product name search."""
        limit = max(1, min(int(limit), MAX_LIMIT))
        log.info("search term=%s limit=%d", term, limit)
        cur = conn.execute(
            "SELECT sku, name FROM products WHERE name LIKE ? ORDER BY name LIMIT ?",
            (f"%{term}%", limit),
        )
        return [{"sku": sku, "name": name} for sku, name in cur.fetchall()]
    '''), d('''
    import logging

    log = logging.getLogger(__name__)

    MAX_LIMIT = 50


    def search_products(conn, term, limit=20, category=None):
        """Case-insensitive product name search, optionally within one category."""
        limit = max(1, min(int(limit), MAX_LIMIT))
        sql = "SELECT sku, name FROM products WHERE name LIKE ?"
        params = [f"%{term}%"]
        if category:
            sql += f" AND category = '{category}'"
        sql += " ORDER BY name LIMIT ?"
        params.append(limit)
        rows = conn.execute(sql, params).fetchall()
        results = [{"sku": sku, "name": name} for sku, name in rows]
        log.info(f"search term={term!r} limit={limit} category={category!r} hits={len(results)}")
        return results
    '''))

FILES["inventory/tags.py"] = (d('''
    DEFAULT_TAGS = ("new",)


    def normalize(tag):
        return tag.strip().lower().replace(" ", "-")


    def merge_tags(existing, extra=None):
        """Union of ``existing`` and ``extra`` tags, normalized and sorted."""
        merged = set(normalize(t) for t in existing)
        merged.update(normalize(t) for t in (extra or ()))
        return sorted(merged)


    def tags_for_new_product(user_tags):
        return merge_tags(DEFAULT_TAGS, user_tags)
    '''), d('''
    DEFAULT_TAGS = ("new",)


    def normalize(tag):
        return tag.strip().lower().replace(" ", "-")


    def merge_tags(existing, extra=[]):
        """Union of ``existing`` and ``extra`` tags, normalized and sorted."""
        for tag in existing:
            if normalize(tag) not in extra:
                extra.append(normalize(tag))
        return sorted(set(normalize(t) for t in extra))


    def tags_for_new_product(user_tags):
        return merge_tags(DEFAULT_TAGS, list(user_tags))
    '''))

FILES["inventory/importer.py"] = (d('''
    import csv
    import logging
    from decimal import Decimal, InvalidOperation

    log = logging.getLogger(__name__)


    class ImportFailed(Exception):
        pass


    def parse_row(row):
        try:
            price = Decimal(row["price"])
        except InvalidOperation:
            raise ValueError(f"bad price {row['price']!r}") from None
        return {"sku": row["sku"].strip().upper(), "name": row["name"].strip(), "price": price}


    def import_csv(path):
        """Parse a product CSV. Any malformed line aborts the whole import."""
        records = []
        with open(path, newline="", encoding="utf-8") as fh:
            for lineno, row in enumerate(csv.DictReader(fh), start=2):
                try:
                    records.append(parse_row(row))
                except (ValueError, KeyError) as exc:
                    raise ImportFailed(f"line {lineno}: {exc}") from exc
        return records
    '''), d('''
    import csv
    import logging
    from decimal import Decimal, InvalidOperation

    log = logging.getLogger(__name__)


    class ImportFailed(Exception):
        pass


    def parse_row(row):
        try:
            price = Decimal(row["price"])
        except InvalidOperation:
            raise ValueError(f"bad price {row['price']!r}") from None
        return {"sku": row["sku"].strip().upper(), "name": row["name"].strip(), "price": price}


    def import_csv(path):
        """Parse a product CSV. Any malformed line aborts the whole import.
        Blank lines (e.g. a trailing newline from spreadsheet exports) are ignored."""
        records = []
        with open(path, newline="", encoding="utf-8") as fh:
            for lineno, row in enumerate(csv.DictReader(fh), start=2):
                try:
                    if not any((v or "").strip() for v in row.values()):
                        continue
                    records.append(parse_row(row))
                except (ValueError, KeyError):
                    log.debug("skipping unparseable line %d", lineno)
                    continue
        return records
    '''))

FILES["inventory/reservations.py"] = (d('''
    from dataclasses import dataclass
    from datetime import datetime, timedelta, timezone

    HOLD = timedelta(minutes=15)


    @dataclass
    class Reservation:
        sku: str
        qty: int
        expires_at: datetime  # naive UTC, as stored in the database


    def _utcnow_naive():
        return datetime.now(timezone.utc).replace(tzinfo=None)


    class ReservationBook:
        def __init__(self, rows):
            self._items = [Reservation(**r) for r in rows]

        def reserve(self, sku, qty):
            r = Reservation(sku, qty, _utcnow_naive() + HOLD)
            self._items.append(r)
            return r

        def active(self):
            now = _utcnow_naive()
            return [r for r in self._items if r.expires_at > now]

        def reserved_qty(self, sku):
            return sum(r.qty for r in self.active() if r.sku == sku)
    '''), d('''
    from dataclasses import dataclass
    from datetime import datetime, timedelta, timezone

    HOLD = timedelta(minutes=15)


    @dataclass
    class Reservation:
        sku: str
        qty: int
        expires_at: datetime  # naive UTC, as stored in the database


    def _utcnow_naive():
        return datetime.now(timezone.utc).replace(tzinfo=None)


    class ReservationBook:
        def __init__(self, rows):
            self._items = [Reservation(**r) for r in rows]

        def reserve(self, sku, qty, hold=HOLD):
            r = Reservation(sku, qty, _utcnow_naive() + hold)
            self._items.append(r)
            return r

        def active(self, now=None):
            now = now or datetime.now()
            return [r for r in self._items if r.expires_at > now]

        def reserved_qty(self, sku):
            return sum(r.qty for r in self.active() if r.sku == sku)
    '''))

FILES["inventory/pricing.py"] = (d('''
    from decimal import ROUND_HALF_UP, Decimal


    def with_vat(net, rate):
        return (Decimal(net) * (1 + Decimal(rate))).quantize(Decimal("0.01"), ROUND_HALF_UP)


    def bulk_discount(qty):
        if qty >= 100:
            return Decimal("0.10")
        if qty >= 10:
            return Decimal("0.05")
        return Decimal("0")
    '''), d('''
    from decimal import ROUND_HALF_UP, Decimal

    CENT = Decimal("0.01")
    DISCOUNT_TIERS = ((100, Decimal("0.10")), (10, Decimal("0.05")))


    def with_vat(net, rate):
        """Gross amount for ``net`` at VAT ``rate`` (e.g. "0.255"), rounded half-up to cents."""
        return (Decimal(net) * (1 + Decimal(rate))).quantize(CENT, ROUND_HALF_UP)


    def bulk_discount(qty):
        for threshold, discount in DISCOUNT_TIERS:
            if qty >= threshold:
                return discount
        return Decimal("0")
    '''))

# (file, unique substring on the target line of the AFTER text, category)
BUGS = [
    ("inventory/batching.py", "    if len(current) > 1:", "off-by-one"),
    ("inventory/stock.py", "        new = current + delta", "concurrency"),
    ("inventory/search.py", "sql += f\" AND category = '{category}'\"", "injection"),
    ("inventory/tags.py", "def merge_tags(existing, extra=[]):", "mutable-default"),
    ("inventory/importer.py", "            except (ValueError, KeyError):", "error-handling"),
    ("inventory/reservations.py", "        now = now or datetime.now()", "timezone"),
]
HARMLESS = [
    ("inventory/batching.py", "    return list(range(n - size + 1))"),
    ("inventory/stock.py", "            return dict(self._levels)"),
    ("inventory/search.py", "    log.info(f\"search term={term!r}"),
]
CATEGORIES = ["off-by-one", "concurrency", "injection", "mutable-default", "error-handling",
              "timezone", "resource-leak", "null-handling", "performance", "other"]


def line_of(text, needle):
    assert text.count(needle) == 1, needle
    return text[: text.index(needle)].count("\n") + 1


def main():
    fix = HERE / "fixture"
    shutil.rmtree(fix, ignore_errors=True)
    patch = []
    for rel, (before, after) in FILES.items():
        out = fix / "repo" / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(after)
        patch += difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                      f"a/{rel}", f"b/{rel}", n=3)
    (fix / "repo" / "inventory" / "__init__.py").write_text("")
    (fix / "change.patch").write_text("".join(patch))
    bugs = [{"file": f, "line": line_of(FILES[f][1], n), "category": c} for f, n, c in BUGS]
    harmless = [{"file": f, "line": line_of(FILES[f][1], n)} for f, n in HARMLESS]
    (HERE / "oracle").mkdir(exist_ok=True)
    (HERE / "oracle" / "findings.json").write_text(json.dumps(bugs, indent=1) + "\n")
    (HERE / "check_body.py").write_text(
        CHECK.replace("@BUGS@", json.dumps(bugs)).replace("@HARMLESS@", json.dumps(harmless))
        .replace("@CATS@", json.dumps(CATEGORIES)))
    (HERE / "prompt.txt").write_text(PROMPT.format(cats=", ".join(CATEGORIES)))


PROMPT = """\
Review a change before it is merged. change.patch is the unified diff; repo/
contains the files as they are AFTER the change (paths in the patch are
relative to repo/). The change is a mix of refactors and small features.

Find the defects that this change introduces (behavioural regressions, bugs,
security problems). Do not report style issues, and do not report changes
that are behaviour-preserving. Precision matters: each finding on correct
code costs points.

Deliverable: findings.json - a JSON list of objects
    {{"file": "<path relative to repo/, e.g. inventory/stock.py>",
      "line": <line number in the post-change file>,
      "category": "<one of: {cats}>",
      "note": "<one sentence>"}}
"""

CHECK = r'''
BUGS = json.loads(r"""@BUGS@""")
HARMLESS = json.loads(r"""@HARMLESS@""")
CATS = json.loads(r"""@CATS@""")
TOL = 3


def norm(path):
    p = str(path).replace("\\", "/").strip()
    while p.startswith("./"):
        p = p[2:]
    if p.startswith("repo/"):
        p = p[5:]
    return p


try:
    with open(os.path.join(WD, "findings.json"), encoding="utf-8") as fh:
        raw = json.load(fh)
    if not isinstance(raw, list):
        raise ValueError("findings.json must be a list")
    findings = []
    for f in raw:
        try:
            findings.append((norm(f["file"]), int(f["line"]), str(f.get("category", "")).strip().lower()))
        except Exception:
            pass
except Exception:
    findings = None


def near(f, target, tol=TOL):
    return f[0] == target["file"] and abs(f[1] - target["line"]) <= tol


for b in BUGS:
    tag = f"{b['file']}:{b['line']} {b['category']}"
    case(f"found {tag}", lambda b=b: findings is not None and any(near(f, b) for f in findings))
    case(f"category {tag}", lambda b=b: findings is not None and any(near(f, b) and f[2] == b["category"] for f in findings), weight=0.5)
for h in HARMLESS:
    case(f"no finding on harmless change {h['file']}:{h['line']}",
         lambda h=h: findings is not None and not any(near(f, h, 1) for f in findings))
case("findings.json present and well-formed", lambda: findings is not None and len(findings) > 0)
# Unmatched findings (not near any planted bug or harmless change) beyond 2 cost 0.05 each.
stray = 0
if findings:
    stray = sum(1 for f in findings
                if not any(near(f, t) for t in BUGS) and not any(near(f, t, 1) for t in HARMLESS))
total = sum(w for _, _, w in results)
base = sum(w for _, ok, w in results if ok) / total
done(score=base - 0.05 * max(0, stray - 2), extra={"stray_findings": stray})
'''

if __name__ == "__main__":
    main()

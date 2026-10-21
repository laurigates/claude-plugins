from datetime import datetime, timedelta, timezone
import base64, json as _json

errors = load("inventory.errors")
store_mod = load("inventory.store")
api_items = load("inventory.api.items")
api_mov = load("inventory.api.movements")
svc_items = load("inventory.service.items")
svc_mov = load("inventory.service.movements")
models = load("inventory.models")
repo_items = load("inventory.repo.items")
routes = load("inventory.api.routes")
T0 = datetime(2026, 2, 1, tzinfo=timezone.utc)


class Clock:
    def __init__(self):
        self.now = T0
    def __call__(self):
        v = self.now
        self.now += timedelta(seconds=30)
        return v


def mk(n=0, **kw):
    st = store_mod.Store(clock=Clock())
    for i in range(n):
        svc_items.create_item(st, sku=f"SKU{i:03d}", name=f"Thing {i}", category="tools",
                              quantity=i, price_cents=100 + i)
    return st


def lst(st, **q):
    return api_items.list_items(st, {"query": {k: str(v) for k, v in q.items()}})


def walk(st, fn=lst, **q):
    seen, cur, guard = [], None, 0
    while guard < 60:
        guard += 1
        qq = dict(q)
        if cur:
            qq["cursor"] = cur
        status, body = fn(st, **qq)
        assert status == 200, (status, body)
        seen += [r["id"] for r in body["items"]]
        cur = body["next_cursor"]
        if cur is None:
            return seen
    raise AssertionError("no end")


def err(resp):
    status, body = resp
    return status, body.get("error", {}).get("code"), body.get("error", {}).get("field"), body.get("error", {}).get("message")


# ---- basic paging
def c_default():
    st = mk(45)
    s, b = lst(st)
    return s == 200 and len(b["items"]) == 20 and isinstance(b["next_cursor"], str) and [r["id"] for r in b["items"]] == list(range(1, 21))
case("default limit 20 + cursor", c_default)
case("walk returns all in order", lambda: walk(mk(45)) == list(range(1, 46)))
def c_exact():
    st = mk(40)
    s, b1 = lst(st)
    s, b2 = lst(st, cursor=b1["next_cursor"])
    return len(b2["items"]) == 20 and b2["next_cursor"] is None
case("exact multiple: last page next_cursor null", c_exact)
case("single page null cursor", lambda: lst(mk(3))[1]["next_cursor"] is None)
case("empty store", lambda: lst(mk(0)) == (200, {"items": [], "next_cursor": None}))
case("limit=1 walk", lambda: walk(mk(5), limit=1) == [1, 2, 3, 4, 5])
case("limit=100 ok", lambda: len(lst(mk(120), limit=100)[1]["items"]) == 100)
case("limit may change between pages", lambda: (lambda st: (lambda b: [r["id"] for r in lst(st, limit=7, cursor=b["next_cursor"])[1]["items"]])(lst(st, limit=3)[1]))(mk(20)) == [4, 5, 6, 7, 8, 9, 10])

# ---- validation (conventions: helper messages, envelope)
case("limit=0 rejected w/ helper message", lambda: err(lst(mk(2), limit=0)) == (400, "validation_error", "limit", "limit must be between 1 and 100"))
case("limit=101 rejected", lambda: err(lst(mk(2), limit=101))[:3] == (400, "validation_error", "limit"))
case("limit=abc rejected w/ helper message", lambda: err(lst(mk(2), limit="abc")) == (400, "validation_error", "limit", "limit must be an integer"))
case("min_quantity=-1 rejected", lambda: err(lst(mk(2), min_quantity=-1)) == (400, "validation_error", "min_quantity", "min_quantity must be >= 0"))
case("archived=maybe rejected w/ helper message", lambda: err(lst(mk(2), archived="maybe")) == (400, "validation_error", "archived", "archived must be a boolean"))

# ---- cursor errors
def c_garbage():
    return err(lst(mk(5), cursor="%%%not-a-cursor"))[:3] == (400, "invalid_cursor", "cursor")
case("garbage cursor -> invalid_cursor", c_garbage)
def c_b64junk():
    junk = base64.urlsafe_b64encode(b'{"nope": 1}').decode()
    junk2 = base64.urlsafe_b64encode(b"\xff\xfe garbage").decode()
    return err(lst(mk(5), cursor=junk))[:3] == (400, "invalid_cursor", "cursor") and err(lst(mk(5), cursor=junk2))[:3] == (400, "invalid_cursor", "cursor")
case("well-formed base64 junk cursor -> invalid_cursor", c_b64junk)
def c_filter_bound():
    st = mk(30)
    for i in range(30, 40):
        svc_items.create_item(st, sku=f"G{i}", name=f"g{i}", category="garden")
    s, b = lst(st, limit=5, category="tools")
    return err(lst(st, limit=5, category="garden", cursor=b["next_cursor"]))[:3] == (400, "invalid_cursor", "cursor")
case("cursor bound to filters", c_filter_bound)
def c_cross_endpoint():
    st = mk(30)
    s, b = lst(st, limit=5)
    return err(api_mov.list_movements(st, {"query": {"cursor": b["next_cursor"]}}))[:3] == (400, "invalid_cursor", "cursor")
case("items cursor rejected by movements", c_cross_endpoint)
def c_errtype():
    E = errors.InvalidCursorError
    return issubclass(E, errors.ValidationError) and E.status == 400 and E.code == "invalid_cursor"
case("InvalidCursorError subclasses ValidationError", c_errtype)
def c_svc_raises():
    try:
        svc_items.list_items(mk(3), cursor="zzz")
    except errors.InvalidCursorError as e:
        return e.field == "cursor"
    return False
case("service raises InvalidCursorError", c_svc_raises)

# ---- filters
def seeded():
    st = store_mod.Store(clock=Clock())
    rows = [("H1", "Claw Hammer", "tools", 5), ("H2", "Sledge hammer", "tools", 0),
            ("D1", "Drill", "electrical", 9), ("R1", "Rake", "garden", 3),
            ("HX9", "Hose", "garden", 12), ("P1", "Primer", "paint", 7)]
    for sku, name, cat, qty in rows:
        svc_items.create_item(st, sku=sku, name=name, category=cat, quantity=qty)
    svc_items.archive_item(st, 6)
    return st
def skus(resp):
    return [r["sku"] for r in resp[1]["items"]]
case("category filter", lambda: skus(lst(seeded(), category="garden")) == ["R1", "HX9"])
case("min_quantity filter", lambda: skus(lst(seeded(), min_quantity=5)) == ["H1", "D1", "HX9"])
case("archived default/true/false", lambda: skus(lst(seeded(), archived="true")) == ["P1"] and "P1" not in skus(lst(seeded())) and skus(lst(seeded(), archived="false")) == skus(lst(seeded())))
case("q matches name or sku case-insensitively", lambda: skus(lst(seeded(), q="HAMMER")) == ["H1", "H2"] and skus(lst(seeded(), q="hx")) == ["HX9"])
case("filters combine with AND", lambda: skus(lst(seeded(), q="h", category="tools", min_quantity=1)) == ["H1"])
def c_filtered_walk():
    st = mk(0)
    for i in range(50):
        svc_items.create_item(st, sku=f"K{i}", name=f"k{i}", category="tools" if i % 3 else "paint", quantity=i % 7)
    got = walk(st, limit=4, category="tools", min_quantity=2)
    want = [i + 1 for i in range(50) if i % 3 and i % 7 >= 2]
    return got == want
case("filtered multi-page walk", c_filtered_walk)

# ---- ordering & stability
def c_created_order():
    st = mk(0)
    base = datetime(2025, 6, 1, tzinfo=timezone.utc)
    offs = [5, 1, 3, 1, 0, 3]
    for i, o in enumerate(offs):
        svc_items.create_item(st, sku=f"O{i}", name="o", category="tools",
                              created_at=(base + timedelta(days=o)).isoformat())
    return walk(st, limit=2) == [5, 2, 4, 3, 6, 1]
case("order by created_at then id (legacy timestamps)", c_created_order)
def c_delete_between():
    st = mk(10)
    s, b = lst(st, limit=4)
    last = b["items"][-1]["id"]
    repo_items.delete(st, last)            # anchor row disappears
    repo_items.delete(st, 2)               # earlier row disappears
    s, b2 = lst(st, limit=4, cursor=b["next_cursor"])
    return [r["id"] for r in b2["items"]] == [5, 6, 7, 8]
case("deleting rows between pages does not skip", c_delete_between)
def c_archive_between():
    st = mk(10)
    s, b = lst(st, limit=3)
    svc_items.archive_item(st, 3)
    svc_items.archive_item(st, 1)
    rest = walk_from(st, b["next_cursor"], limit=3)
    return rest == [4, 5, 6, 7, 8, 9, 10]
def walk_from(st, cur, **q):
    out = []
    while cur:
        s, b = lst(st, cursor=cur, **q)
        out += [r["id"] for r in b["items"]]
        cur = b["next_cursor"]
    return out
case("archiving rows between pages does not skip", c_archive_between)
def c_insert_between():
    st = mk(6)
    s, b = lst(st, limit=3)
    svc_items.create_item(st, sku="NEW", name="new", category="tools")  # newest -> must appear
    svc_items.create_item(st, sku="OLD", name="old", category="tools", created_at="2020-01-01T00:00:00+00:00")
    rest = walk_from(st, b["next_cursor"], limit=3)
    return rest == [4, 5, 6, 7]
case("rows inserted between pages", c_insert_between)

# ---- conventions: serializer + Page + service API
def c_serializer():
    st = seeded()
    s, b = lst(st)
    one = api_items.get_item(st, {"params": {"id": "1"}})[1]
    return b["items"][0] == one
case("list rows use the item serializer", c_serializer)
def c_page():
    p = svc_items.list_items(mk(5), limit=2)
    return isinstance(p, models.Page) and [i.id for i in p.items] == [1, 2] and isinstance(p.next_cursor, str)
case("service returns models.Page (typed args)", c_page)

# ---- movements
def mstore():
    st = mk(3)
    for k, it, d in [("in", 1, 5), ("in", 2, 4), ("out", 1, 2), ("adjust", 3, 7), ("in", 1, 1), ("out", 2, 1), ("in", 3, 2)]:
        svc_mov.record_movement(st, item_id=it, kind=k, delta=d)
    return st
def ml(st, **q):
    return api_mov.list_movements(st, {"query": {k: str(v) for k, v in q.items()}})
case("movements newest first", lambda: [m["id"] for m in ml(mstore())[1]["items"]] == [7, 6, 5, 4, 3, 2, 1])
case("movements walk limit=2", lambda: walk(mstore(), fn=ml, limit=2) == [7, 6, 5, 4, 3, 2, 1])
def c_mov_ties():
    st = mk(1)
    st.clock = lambda: T0
    for _ in range(5):
        svc_mov.record_movement(st, item_id=1, kind="in", delta=1)
    return walk(st, fn=ml, limit=2) == [5, 4, 3, 2, 1]
case("movements tie-break by id desc", c_mov_ties)
case("movements item_id + kind", lambda: [m["id"] for m in ml(mstore(), item_id=1, kind="in")[1]["items"]] == [5, 1])
case("movements unknown item_id -> empty", lambda: ml(mstore(), item_id=99) == (200, {"items": [], "next_cursor": None}))
def c_since():
    st = mstore()
    since = st.movements[4].created_at.isoformat()
    return [m["id"] for m in ml(st, since=since)[1]["items"]] == [7, 6, 5, 4]
case("movements since inclusive", c_since)
case("movements bad kind", lambda: err(ml(mstore(), kind="teleport")) == (400, "validation_error", "kind", "kind must be one of: in, out, adjust"))
case("movements naive since rejected", lambda: err(ml(mstore(), since="2026-01-01T00:00:00"))[:3] == (400, "validation_error", "since"))
case("movements item_id=0 rejected", lambda: err(ml(mstore(), item_id=0))[:3] == (400, "validation_error", "item_id"))
case("movement cursor bound to filters", lambda: (lambda st: err(ml(st, limit=1, kind="out", cursor=ml(st, limit=1, kind="in")[1]["next_cursor"]))[:3])(mstore()) == (400, "invalid_cursor", "cursor"))

# ---- regression: existing suite
def c_suite():
    import unittest, io
    suite = unittest.defaultTestLoader.discover(os.path.join(WD, "tests"), top_level_dir=WD)
    r = unittest.TextTestRunner(stream=io.StringIO()).run(suite)
    return r.wasSuccessful() and r.testsRun >= 9
case("project test suite passes", c_suite, timeout=60)
done()

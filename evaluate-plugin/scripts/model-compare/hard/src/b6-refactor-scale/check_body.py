import inspect, math, re, warnings, io, contextlib, glob

ZR = {"DOMESTIC": 1.20, "EU": 2.80, "NORDIC": 2.10, "WORLD": 6.50}


def ref(w, z, express=False):
    p = (9.90 if express else 4.90) + ZR[z] * (math.ceil(w * 2) / 2)
    return round(p * 1.5 if express else p, 2)


OLD = re.compile(r"\bcalc_shipping\b")
pricing = load("shipkit.pricing")
pkg = load("shipkit")
zones = load("shipkit.zones")


def strict(fn):
    """Run fn with DeprecationWarning as an error (internal code must not use the alias)."""
    def run():
        with warnings.catch_warnings():
            warnings.simplefilter("error", DeprecationWarning)
            return fn()
    return run


def clean(rel):
    t = read(rel)
    return t is not None and not OLD.search(t)


def migrated(rel, modname, fn):
    """Per-file case: file no longer uses the old name AND behaviour is unchanged."""
    def run():
        if not clean(rel):
            return False
        mod = load(modname)
        return mod is not None and strict(lambda: fn(mod))()
    return run


GRID = [(0.4, "EU"), (1.0, "DOMESTIC"), (2.26, "NORDIC"), (12, "WORLD"), (0.01, "EU")]

# ---------- the new function
def c_sig():
    ps = list(inspect.signature(pricing.quote_shipping).parameters.values())
    return ([p.name for p in ps] == ["zone", "weight_kg", "service"]
            and ps[0].kind == ps[1].kind == inspect.Parameter.POSITIONAL_OR_KEYWORD
            and ps[2].kind == inspect.Parameter.KEYWORD_ONLY and ps[2].default == "standard")
case("quote_shipping signature", c_sig)
case("quote_shipping values", strict(lambda: all(pricing.quote_shipping(z, w) == ref(w, z) and pricing.quote_shipping(z, w, service="express") == ref(w, z, True) for w, z in GRID)))
def c_errors():
    def ve(f):
        try:
            f()
        except ValueError:
            return True
        return False
    def te(f):
        try:
            f()
        except TypeError:
            return True
        return False
    q = pricing.quote_shipping
    return (ve(lambda: q("EU", 1, service="overnight")) and ve(lambda: q("EU", 0)) and ve(lambda: q("MARS", 1))
            and te(lambda: q("EU", 1, "express")) and te(lambda: q("EU", 1, express=True)))
case("quote_shipping validation", strict(c_errors))

# ---------- deprecated alias
def c_alias_warns():
    with warnings.catch_warnings(record=True) as rec:
        warnings.simplefilter("always")
        v = pricing.calc_shipping(2.26, "NORDIC", express=True)
    dep = [w for w in rec if issubclass(w.category, DeprecationWarning)]
    return v == ref(2.26, "NORDIC", True) and len(dep) == 1 and os.path.basename(dep[0].filename) == os.path.basename(__file__)
case("alias warns (attributed to caller) and delegates", c_alias_warns)
def c_alias_forms():
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        a = pricing.calc_shipping
        return (a(1.0, "EU") == ref(1.0, "EU") and a(1.0, "EU", True) == ref(1.0, "EU", True)
                and a(weight_kg=3, zone="WORLD", express=True) == ref(3, "WORLD", True))
case("alias keeps old signature", c_alias_forms)
def c_pkg():
    with warnings.catch_warnings(record=True) as rec:
        warnings.simplefilter("always")
        v = pkg.calc_shipping(1.0, "EU")
    return (v == ref(1.0, "EU") and any(issubclass(w.category, DeprecationWarning) for w in rec)
            and pkg.quote_shipping is pricing.quote_shipping and "quote_shipping" in pkg.__all__
            and "calc_shipping" not in pkg.__all__ and "calc_shipping_zone" in pkg.__all__)
case("package exports", c_pkg)
case("calc_shipping_zone untouched", lambda: zones.calc_shipping_zone("se") == "NORDIC" and pkg.calc_shipping_zone("us") == "WORLD" and "calc_shipping_zone" in (read("config/pipelines.json") or "") and "calc_shipping_zone" in load("shipkit.registry").HANDLERS)

# ---------- every call site, per file
case("parcel.py", migrated("shipkit/parcel.py", "shipkit.parcel", lambda m: m.Parcel(1.2).shipping_cost("EU") == ref(1.2, "EU") and m.Parcel(0.5, 60, 40, 40).shipping_cost("WORLD", True) == ref(19.2, "WORLD", True) and m.Parcel(2).shipping_cost("NORDIC", express=True) == ref(2, "NORDIC", True)))
case("cart.py", migrated("shipkit/cart.py", "shipkit.cart", lambda m: m.cart_shipping([(1.0, 2), (0.3, 1)], "EU") == ref(2.5, "EU") and m.cart_shipping([(1.0, 1)], "WORLD", express=True) == ref(1.2, "WORLD", True) and m.cart_shipping([], "EU") == 0.0))
case("checkout.py", migrated("shipkit/checkout.py", "shipkit.checkout", lambda m: m.shipping_options([(1.0, 2)], "EU", 20) == [("standard", ref(2.2, "EU")), ("express", ref(2.2, "EU", True))] and m.shipping_options([(1.0, 2)], "EU", 200)[0] == ("standard", 0.0)))
INV = {"weight_kg": 3.1, "zone": "NORDIC", "express": True, "items": [("mug", 12.0)]}
case("invoices.py", migrated("shipkit/invoices.py", "shipkit.invoices", lambda m: m.invoice_lines(INV) == [("mug", 12.0), ("shipping", ref(3.1, "NORDIC", True))] and m.invoice_total({**INV, "express": False}) == round((12.0 + ref(3.1, "NORDIC")) * 1.255, 2) and m.invoice_lines({k: v for k, v in INV.items() if k != "express"})[-1][1] == ref(3.1, "NORDIC")))
case("returns.py (partial)", migrated("shipkit/returns.py", "shipkit.returns", lambda m: m.return_label_cost(0.3) == ref(0.3, "DOMESTIC") and m.return_label_cost(4.2) == ref(4.2, "DOMESTIC") and m.refund_after_label(20.0, 1.0) == round(20.0 - ref(1.0, "DOMESTIC"), 2)))
case("bulk.py (map)", migrated("shipkit/bulk.py", "shipkit.bulk", lambda m: m.bulk_quotes([1.0, 2.5, 0.2], ["EU", "WORLD", "DOMESTIC"]) == [ref(1.0, "EU"), ref(2.5, "WORLD"), ref(0.2, "DOMESTIC")] and m.cheapest_zone(2.0, ["WORLD", "EU", "NORDIC"]) == "NORDIC"))
case("plugins.py (getattr)", migrated("shipkit/plugins.py", "shipkit.plugins", lambda m: m.load_pricer() is pricing.quote_shipping))
case("registry.py (dict key)", migrated("shipkit/registry.py", "shipkit.registry", lambda m: m.dispatch("quote_shipping", zone="EU", weight_kg=1.0, service="express") == ref(1.0, "EU", True) and m.dispatch("calc_shipping_zone", country_code="de") == "EU" and "calc_shipping" not in m.HANDLERS))
def c_pipeline(m):
    a = m.run("nightly_quotes")
    b = m.run("express_audit")
    return a == ["NORDIC", ref(2.5, "NORDIC"), ref(0.4, "EU", True), 6.5] and b == [ref(12, "WORLD", True), ref(1, "DOMESTIC")]
case("pipeline + config/pipelines.json", migrated("config/pipelines.json", "shipkit.pipeline", c_pipeline))
def c_config_shape():
    cfg = json.loads(read("config/pipelines.json"))
    steps = [s for p in cfg["pipelines"].values() for s in p if s["op"] == "quote_shipping"]
    return len(steps) == 4 and all("express" not in s["args"] for s in steps) and sum(s["args"].get("service") == "express" for s in steps) == 2
case("config uses new op and service arg", c_config_shape)
def c_cli(m):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        a = m.main(["--zone", "EU", "--weight", "2.5", "--express"])
        b = m.main(["--zone", "DOMESTIC", "--weight", "1"])
    return a == f"EU 2.5 kg express: {ref(2.5, 'EU', True):.2f} EUR" and b == f"DOMESTIC 1 kg standard: {ref(1, 'DOMESTIC'):.2f} EUR"
case("cli.py", migrated("shipkit/cli.py", "shipkit.cli", c_cli))
ORD = [{"weight_kg": 1, "zone": "EU"}, {"weight_kg": 2, "zone": "EU", "express": True}, {"weight_kg": 0.5, "zone": "WORLD"}]
case("reports.py (incl. docstring)", migrated("shipkit/reports.py", "shipkit.reports", lambda m: m.shipping_by_zone(ORD) == {"EU": round(ref(1, "EU") + ref(2, "EU", True), 2), "WORLD": ref(0.5, "WORLD")} and m.most_expensive(ORD) is ORD[1]))
case("promotions.py", migrated("shipkit/promotions.py", "shipkit.promotions", lambda m: m.discounted_shipping(2, "EU", True, 10) == round(ref(2, "EU", True) * 0.9, 2) and m.discounted_shipping(2, "EU", False, 100) == 0.0 and m.flat_rate_saves(1, "WORLD", 10) is True))
def c_market(m):
    class Custom(m.Seller):
        @staticmethod
        def pricer(weight_kg, zone, express=False):
            return weight_kg * 10 + (1 if express else 0)
    return (m.Seller("a", 1.5).quote(2, "EU") == round(ref(2, "EU") + 1.5, 2)
            and m.Seller("b").quote(2, "EU", True) == ref(2, "EU", True)
            and m.FlatSeller("c", 1).quote(9, "WORLD", True) == 16.0
            and Custom("d").quote(3, "EU", express=True) == 31.0)
case("marketplace.py (pricer contract kept)", migrated("shipkit/marketplace.py", "shipkit.marketplace", c_market))
case("estimates.py", migrated("shipkit/estimates.py", "shipkit.estimates", lambda m: m.estimate("fast", 1.4, "NORDIC") == ref(1.4, "NORDIC", True) and m.ESTIMATORS["cheap"](1.4, "NORDIC") == ref(1.4, "NORDIC")))
def c_api(m):
    h = m.handle_quote
    return (h({"weight_kg": 2, "zone": "EU", "express": True}) == (200, {"price": ref(2, "EU", True), "currency": "EUR"})
            and h({"weight_kg": 2, "zone": "EU"}) == (200, {"price": ref(2, "EU"), "currency": "EUR"})
            and h({"weight_kg": 2, "zone": "EU", "express": False})[1]["price"] == ref(2, "EU")
            and h({"weight_kg": 2, "zone": "MARS"})[0] == 400
            and h({"weight_kg": 2})[0] == 400
            and h({"weight_kg": 2, "zone": "EU", "service": "express"})[0] == 400)
case("api.py (public schema unchanged)", migrated("shipkit/api.py", "shipkit.api", c_api))

# ---------- docs, tests, global sweep
def c_readme():
    t = read("README.md") or ""
    stale = [l for l in t.splitlines() if OLD.search(l) and "deprecat" not in l.lower()]
    return "quote_shipping(" in t and not stale and "calc_shipping_zone" in t
case("README updated", c_readme)
def c_tests():
    import unittest
    for f in glob.glob("tests/*.py"):
        if OLD.search(read(f) or ""):
            return False
    with warnings.catch_warnings():
        warnings.simplefilter("error", DeprecationWarning)
        suite = unittest.defaultTestLoader.discover(os.path.join(WD, "tests"), top_level_dir=WD)
        r = unittest.TextTestRunner(stream=io.StringIO()).run(suite)
    return r.wasSuccessful() and r.testsRun >= 7
case("tests migrated and passing", c_tests, timeout=60)
def c_sweep():
    allowed = {"shipkit/pricing.py", "shipkit/__init__.py"}
    for f in glob.glob("**/*", recursive=True):
        if os.path.isdir(f) or "__pycache__" in f or f in allowed:
            continue
        if not f.endswith((".py", ".json", ".toml", ".cfg", ".ini", ".txt", ".yaml", ".yml")):
            continue
        if OLD.search(read(f) or ""):
            return False
    return True
case("no stale references outside the alias", c_sweep)
done()

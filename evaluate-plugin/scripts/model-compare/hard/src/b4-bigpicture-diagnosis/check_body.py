import re
from decimal import Decimal

app_mod = load("pricesvc.app")
cfg_mod = load("pricesvc.config")
errs = load("pricesvc.errors")
REG = 0.5


class Clock:
    def __init__(self):
        self.now = 0.0
    def monotonic(self):
        return self.now
    def sleep(self, s):
        self.now += s


class Catalog:
    def __init__(self, failures=0):
        self.prices = {("AA-24", "nordic"): Decimal("14.90"), ("AA-24", "dach"): Decimal("15.50"),
                       ("HDMI-2", "nordic"): Decimal("9.99"), ("AA-24", "jp"): Decimal("14.90")}
        self.failures, self.calls = failures, 0
    def get_price(self, sku, region):
        self.calls += 1
        if self.failures:
            self.failures -= 1
            raise errs.TransientError("catalog timeout")
        return self.prices.get((sku, region))


class Fx:
    def __init__(self, failures=0):
        self.rates = {("EUR", "SEK"): Decimal("11.4321"), ("EUR", "NOK"): Decimal("11.7012"),
                      ("EUR", "DKK"): Decimal("7.4601"), ("EUR", "JPY"): Decimal("162.37")}
        self.failures, self.calls, self.down = failures, 0, False
    def get_rate(self, base, target):
        self.calls += 1
        if self.down:
            raise errs.TransientError("fx down")
        if self.failures:
            self.failures -= 1
            raise errs.TransientError("fx timeout")
        return self.rates[(base, target)]


class Metrics:
    def __init__(self, down=False):
        self.down, self.points = down, []
    def push(self, name, value):
        if self.down:
            raise errs.TransientError("metrics down")
        self.points.append(name)


def mk(cat_fail=0, fx_fail=0, metrics_down=False):
    c, f, m, clk = Catalog(cat_fail), Fx(fx_fail), Metrics(metrics_down), Clock()
    cfg = cfg_mod.load_config(env={})
    a = app_mod.build_app(catalog_backend=c, fx_backend=f, metrics_backend=m, config=cfg, clock=clk)
    return a, c, f, clk


def q(app, cur, sku="AA-24", region="nordic", qty=1):
    return app.handle_quote({"sku": sku, "region": region, "currency": cur, "quantity": qty})


EXP = {"EUR": "14.90", "SEK": "170.34", "NOK": "174.35", "DKK": "111.16"}


def ok(resp, cur):
    s, b = resp
    return s == 200 and b["currency"] == cur and b["unit_price"] == EXP[cur]


# ---------- the incident scenarios
def c_outage_503():
    a, c, f, clk = mk()
    f.down = True
    return q(a, "SEK") == (503, {"error": "rate_unavailable"})
case("FX outage -> 503 rate_unavailable", c_outage_503)
def c_recover():
    a, c, f, clk = mk()
    f.down = True
    q(a, "SEK")
    f.down = False
    clk.now += 1
    return ok(q(a, "SEK"), "SEK")
case("after FX recovers, correct SEK price immediately", c_recover)
def c_no_leak_nok():
    a, c, f, clk = mk()
    f.down = True
    q(a, "SEK")
    f.down = False
    return ok(q(a, "NOK"), "NOK")
case("outage result not served to NOK customers", c_no_leak_nok)
def c_dkk_after_sek():
    a, c, f, clk = mk()
    return ok(q(a, "SEK"), "SEK") and ok(q(a, "DKK"), "DKK") and ok(q(a, "SEK"), "SEK")
case("normal day: DKK after SEK correct", c_dkk_after_sek)
def c_eur_then_sek():
    a, c, f, clk = mk()
    return ok(q(a, "EUR"), "EUR") and ok(q(a, "SEK"), "SEK")
case("EUR then SEK correct", c_eur_then_sek)
def c_sek_then_eur():
    a, c, f, clk = mk()
    return ok(q(a, "SEK"), "SEK") and ok(q(a, "EUR"), "EUR")
case("SEK then EUR correct", c_sek_then_eur)
def c_rotation():
    a, c, f, clk = mk()
    seq = ["SEK", "NOK", "DKK", "EUR"] * 3
    return all(ok(q(a, cur), cur) for cur in seq) and c.calls <= 4
case("currency rotation correct and cached (<= 1 catalog call per currency)", c_rotation)
def c_outage_then_eur():
    a, c, f, clk = mk()
    f.down = True
    r1 = q(a, "SEK")
    return r1[0] == 503 and ok(q(a, "EUR"), "EUR")
case("outage: EUR still served correctly after failed SEK", c_outage_then_eur)

# ---------- caching / retry still present (regressions)
def c_cache():
    a, c, f, clk = mk()
    for _ in range(3):
        q(a, "SEK")
    return c.calls == 1 and f.calls == 1
case("price cache still used", c_cache, weight=REG)
def c_ttl():
    a, c, f, clk = mk()
    q(a, "SEK")
    clk.now += 301
    q(a, "SEK")
    return c.calls == 2
case("price cache TTL honoured", c_ttl, weight=REG)
def c_fx_cache():
    a, c, f, clk = mk()
    q(a, "SEK")
    q(a, "SEK", sku="HDMI-2")
    return f.calls == 1
case("FX rate cache still used", c_fx_cache, weight=REG)
case("FX transient failure retried", lambda: (lambda t: ok(q(t[0], "SEK"), "SEK") and t[2].calls == 2)(mk(fx_fail=1)), weight=REG)
case("FX two transient failures retried", lambda: (lambda t: ok(q(t[0], "NOK"), "NOK") and t[2].calls == 3)(mk(fx_fail=2)), weight=REG)
case("catalog transient failure retried", lambda: ok(q(mk(cat_fail=1)[0], "SEK"), "SEK"), weight=REG)
case("catalog down -> 502", lambda: q(mk(cat_fail=9)[0], "SEK") == (502, {"error": "upstream_unavailable"}), weight=REG)
def c_metrics_down():
    a, c, f, clk = mk(metrics_down=True)
    return ok(q(a, "SEK"), "SEK") and ok(q(a, "SEK"), "SEK") and a.metrics.dropped >= 1
case("metrics outage never fails a quote", c_metrics_down, weight=REG)
def c_eur_outage():
    a, c, f, clk = mk()
    f.down = True
    return ok(q(a, "EUR"), "EUR") and f.calls == 0
case("EUR needs no FX during outage", c_eur_outage, weight=REG)
case("JPY 0 decimals + totals", lambda: q(mk()[0], "JPY", region="jp", qty=3)[1] == {"sku": "AA-24", "region": "jp", "currency": "JPY", "unit_price": "2419", "quantity": 3, "total": "7257"}, weight=REG)
case("unknown sku 404 / bad request 400", lambda: q(mk()[0], "SEK", sku="NOPE")[0] == 404 and q(mk()[0], "CHF")[0] == 400, weight=REG)
def c_suite():
    import unittest, io
    suite = unittest.defaultTestLoader.discover(os.path.join(WD, "tests"), top_level_dir=WD)
    r = unittest.TextTestRunner(stream=io.StringIO()).run(suite)
    return r.wasSuccessful() and r.testsRun >= 6
case("project tests pass", c_suite, timeout=60, weight=REG)

# ---------- diagnosis.md (lenient keyword checks, one per causal layer)
D = (read("diagnosis.md") or "").lower()
case("diagnosis: cache key ignores currency (currency vs currency_code)", lambda: "currency_code" in D and re.search(r"cache[ _-]?key|key", D) is not None)
case("diagnosis: retry fallback swallows FX failure", lambda: re.search(r"fallback|swallow", D) is not None and "retry" in D)
case("diagnosis: None rate treated as no conversion", lambda: "none" in D and re.search(r"convert|conversion|unconverted", D) is not None)
done()

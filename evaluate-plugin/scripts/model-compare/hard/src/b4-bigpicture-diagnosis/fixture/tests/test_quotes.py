import unittest

from pricesvc.app import build_app
from pricesvc.config import load_config
from tests.fakes import FakeCatalog, FakeFx, FakeMetrics, ManualClock

PRICES = {("AA-24", "nordic"): "14.90", ("AA-24", "dach"): "15.50"}
RATES = {("EUR", "SEK"): "11.4321", ("EUR", "NOK"): "11.7012", ("EUR", "DKK"): "7.4601"}


class QuoteTest(unittest.TestCase):
    def setUp(self):
        self.clock = ManualClock()
        self.catalog = FakeCatalog(PRICES)
        self.fx = FakeFx(RATES)
        self.app = build_app(
            catalog_backend=self.catalog, fx_backend=self.fx, metrics_backend=FakeMetrics(),
            config=load_config(env={}), clock=self.clock,
        )

    def test_eur_quote(self):
        status, body = self.app.handle_quote({"sku": "aa-24", "region": "nordic", "currency": "eur", "quantity": 2})
        self.assertEqual(status, 200)
        self.assertEqual((body["unit_price"], body["total"]), ("14.90", "29.80"))

    def test_sek_quote(self):
        status, body = self.app.handle_quote({"sku": "AA-24", "region": "nordic", "currency": "SEK"})
        self.assertEqual((status, body["currency"], body["unit_price"]), (200, "SEK", "170.34"))

    def test_cached(self):
        for _ in range(3):
            self.app.handle_quote({"sku": "AA-24", "region": "nordic", "currency": "SEK"})
        self.assertEqual(self.catalog.calls, 1)

    def test_unknown_sku(self):
        status, body = self.app.handle_quote({"sku": "NOPE", "region": "nordic", "currency": "EUR"})
        self.assertEqual((status, body), (404, {"error": "unknown_sku"}))

    def test_bad_currency_for_region(self):
        status, _ = self.app.handle_quote({"sku": "AA-24", "region": "dach", "currency": "SEK"})
        self.assertEqual(status, 400)

    def test_catalog_down(self):
        self.catalog.failures = 5
        status, body = self.app.handle_quote({"sku": "AA-24", "region": "nordic", "currency": "EUR"})
        self.assertEqual((status, body), (502, {"error": "upstream_unavailable"}))


if __name__ == "__main__":
    unittest.main()

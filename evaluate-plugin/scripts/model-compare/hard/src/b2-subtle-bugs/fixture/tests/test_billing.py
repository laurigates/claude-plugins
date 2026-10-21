import unittest
from datetime import date, datetime, timezone

from billing.charges import IdempotencyConflict, charge, refund
from billing.ledger import Ledger
from billing.reports import daily_totals, daily_totals_range
from billing.testing import FakeGateway

T = datetime(2026, 5, 4, 10, 0, tzinfo=timezone.utc)


class ChargeTest(unittest.TestCase):
    def test_charge_records_entry(self):
        ledger, gw = Ledger(), FakeGateway()
        e = charge(ledger, gw, customer_id="c1", amount_cents=500, idempotency_key="k1", now=T)
        self.assertEqual((e.kind, e.amount_cents, e.customer_id), ("charge", 500, "c1"))
        self.assertEqual(len(ledger.entries), 1)

    def test_same_key_returns_existing(self):
        ledger, gw = Ledger(), FakeGateway()
        a = charge(ledger, gw, customer_id="c1", amount_cents=500, idempotency_key="k1", now=T)
        b = charge(ledger, gw, customer_id="c1", amount_cents=500, idempotency_key="k1", now=T)
        self.assertEqual(a, b)
        self.assertEqual(len(gw.captures), 1)

    def test_conflict(self):
        ledger, gw = Ledger(), FakeGateway()
        charge(ledger, gw, customer_id="c1", amount_cents=500, idempotency_key="k1", now=T)
        with self.assertRaises(IdempotencyConflict):
            charge(ledger, gw, customer_id="c1", amount_cents=900, idempotency_key="k1", now=T)


class ReportTest(unittest.TestCase):
    def test_daily_total_nets_refunds(self):
        ledger, gw = Ledger(), FakeGateway()
        e = charge(ledger, gw, customer_id="c1", amount_cents=5000, idempotency_key="k", now=T)
        charge(ledger, gw, customer_id="c2", amount_cents=700, idempotency_key="k2", now=T)
        refund(ledger, charge_entry=e, now=T)
        self.assertEqual(daily_totals(ledger, date(2026, 5, 4)), 700)

    def test_range(self):
        ledger, gw = Ledger(), FakeGateway()
        charge(ledger, gw, customer_id="c1", amount_cents=100, idempotency_key="a", now=T)
        got = daily_totals_range(ledger, date(2026, 5, 3), date(2026, 5, 5))
        self.assertEqual(got, {date(2026, 5, 3): 0, date(2026, 5, 4): 100, date(2026, 5, 5): 0})


if __name__ == "__main__":
    unittest.main()

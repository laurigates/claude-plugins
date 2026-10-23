import unittest

from shipkit import pipeline
from shipkit.checkout import shipping_options
from shipkit.pricing import calc_shipping
from shipkit.returns import return_label_cost


class IntegrationTest(unittest.TestCase):
    def test_checkout_free_standard(self):
        opts = dict(shipping_options([(1.0, 2)], "EU", subtotal=200))
        self.assertEqual(opts["standard"], 0.0)
        self.assertEqual(opts["express"], calc_shipping(2.2, "EU", True))

    def test_returns(self):
        self.assertEqual(return_label_cost(0.3), calc_shipping(0.3, "DOMESTIC"))

    def test_pipeline(self):
        results = pipeline.run("nightly_quotes")
        self.assertEqual(results[0], "NORDIC")
        self.assertEqual(results[1], calc_shipping(2.5, "NORDIC"))


if __name__ == "__main__":
    unittest.main()

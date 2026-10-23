import unittest

from shipkit.pricing import quote_shipping


class PricingTest(unittest.TestCase):
    def test_standard(self):
        self.assertEqual(quote_shipping("DOMESTIC", 1.0), 6.1)

    def test_rounds_up_to_half_kg(self):
        self.assertEqual(quote_shipping("EU", 1.01), quote_shipping("EU", 1.5))

    def test_express(self):
        self.assertEqual(quote_shipping("EU", 2, service="express"), round((9.9 + 2.8 * 2) * 1.5, 2))

    def test_bad_zone(self):
        with self.assertRaises(ValueError):
            quote_shipping("MARS", 1)


if __name__ == "__main__":
    unittest.main()

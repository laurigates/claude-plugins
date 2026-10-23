import unittest

from shipkit.pricing import calc_shipping


class PricingTest(unittest.TestCase):
    def test_standard(self):
        self.assertEqual(calc_shipping(1.0, "DOMESTIC"), 6.1)

    def test_rounds_up_to_half_kg(self):
        self.assertEqual(calc_shipping(1.01, "EU"), calc_shipping(1.5, "EU"))

    def test_express(self):
        self.assertEqual(calc_shipping(2, "EU", express=True), round((9.9 + 2.8 * 2) * 1.5, 2))

    def test_bad_zone(self):
        with self.assertRaises(ValueError):
            calc_shipping(1, "MARS")


if __name__ == "__main__":
    unittest.main()

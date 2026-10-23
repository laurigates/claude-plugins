from .pricing import quote_shipping


class Seller:
    """A marketplace seller; sellers may override ``pricer`` with their own tariff."""


    def __init__(self, name, handling_fee=0.0):
        self.name = name
        self.handling_fee = handling_fee

    def quote(self, weight_kg, zone, express=False):
        return round(self.pricer(weight_kg, zone, express) + self.handling_fee, 2)

    @staticmethod
    def pricer(weight_kg, zone, express=False):
        return quote_shipping(zone, weight_kg, service="express" if express else "standard")


class FlatSeller(Seller):
    @staticmethod
    def pricer(weight_kg, zone, express=False):
        return 15.0 if express else 5.0

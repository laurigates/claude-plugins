from dataclasses import dataclass

from .pricing import quote_shipping


@dataclass
class Parcel:
    weight_kg: float
    length_cm: float = 30
    width_cm: float = 20
    height_cm: float = 10

    @property
    def volumetric_kg(self):
        return self.length_cm * self.width_cm * self.height_cm / 5000

    @property
    def billable_kg(self):
        return max(self.weight_kg, self.volumetric_kg)

    def shipping_cost(self, zone, express=False):
        """Cost of shipping this parcel, using the larger of real and volumetric weight."""
        return quote_shipping(zone, self.billable_kg, service="express" if express else "standard")

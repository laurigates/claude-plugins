"""Shipping price calculation."""
import math

from .zones import ZONE_RATES

BASE_FEE = {"standard": 4.90, "express": 9.90}
EXPRESS_FACTOR = 1.5


def calc_shipping(weight_kg, zone, express=False):
    """Price in euros for sending a parcel of ``weight_kg`` to ``zone``.

    The weight is rounded up to the next half kilogram. Express service has a
    higher base fee and a 1.5x surcharge on the total.
    """
    if weight_kg <= 0:
        raise ValueError("weight_kg must be positive")
    if zone not in ZONE_RATES:
        raise ValueError(f"unknown zone {zone!r}")
    billable = math.ceil(weight_kg * 2) / 2
    service = "express" if express else "standard"
    price = BASE_FEE[service] + ZONE_RATES[zone] * billable
    if express:
        price *= EXPRESS_FACTOR
    return round(price, 2)

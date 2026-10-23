from .pricing import quote_shipping


def discounted_shipping(weight_kg, zone, express, percent_off):
    """Shipping after a percentage promotion; never below 0."""
    cost = quote_shipping(zone, weight_kg, service="express" if express else "standard")
    return round(max(0.0, cost * (1 - percent_off / 100)), 2)


def flat_rate_saves(weight_kg, zone, flat):
    return quote_shipping(zone, weight_kg) > flat

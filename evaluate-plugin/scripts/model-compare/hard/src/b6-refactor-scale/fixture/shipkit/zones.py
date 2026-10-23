"""Shipping zones."""

ZONE_RATES = {"DOMESTIC": 1.20, "EU": 2.80, "NORDIC": 2.10, "WORLD": 6.50}

_COUNTRY_ZONES = {
    "FI": "DOMESTIC",
    "SE": "NORDIC", "NO": "NORDIC", "DK": "NORDIC", "IS": "NORDIC",
    "DE": "EU", "FR": "EU", "EE": "EU", "NL": "EU", "ES": "EU", "IT": "EU",
}


def calc_shipping_zone(country_code):
    """Map an ISO 3166 alpha-2 country code to a shipping zone."""
    return _COUNTRY_ZONES.get(country_code.upper(), "WORLD")

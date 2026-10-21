"""JSON API handler. The request schema is public and must stay stable:
{"weight_kg": number, "zone": str, "express": bool (optional)}."""
from .pricing import calc_shipping


def handle_quote(body):
    try:
        price = calc_shipping(**body)
    except (TypeError, ValueError) as exc:
        return 400, {"error": str(exc)}
    return 200, {"price": price, "currency": "EUR"}

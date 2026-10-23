"""JSON API handler. The request schema is public and must stay stable:
{"weight_kg": number, "zone": str, "express": bool (optional)}."""
from .pricing import quote_shipping


def handle_quote(body):
    try:
        unknown = set(body) - {"weight_kg", "zone", "express"}
        if unknown:
            raise TypeError(f"unexpected field(s): {', '.join(sorted(unknown))}")
        service = "express" if body.get("express", False) else "standard"
        price = quote_shipping(body["zone"], body["weight_kg"], service=service)
    except (KeyError, TypeError, ValueError) as exc:
        return 400, {"error": str(exc)}
    return 200, {"price": price, "currency": "EUR"}

"""Management reports.

Shipping figures are recomputed with quote_shipping so that reports always use
current tariffs rather than the price stored on the order.
"""
from .pricing import quote_shipping


def shipping_by_zone(orders):
    """orders: iterable of dicts with weight_kg, zone, express."""
    totals = {}
    for o in orders:
        service = "express" if o.get("express", False) else "standard"
        cost = quote_shipping(o["zone"], o["weight_kg"], service=service)
        totals[o["zone"]] = round(totals.get(o["zone"], 0.0) + cost, 2)
    return dict(sorted(totals.items()))


def most_expensive(orders):
    return max(orders, key=lambda o: quote_shipping(o["zone"], o["weight_kg"]))

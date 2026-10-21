"""Management reports.

Shipping figures are recomputed with calc_shipping so that reports always use
current tariffs rather than the price stored on the order.
"""
from .pricing import calc_shipping


def shipping_by_zone(orders):
    """orders: iterable of dicts with weight_kg, zone, express."""
    totals = {}
    for o in orders:
        cost = calc_shipping(o["weight_kg"], o["zone"], o.get("express", False))
        totals[o["zone"]] = round(totals.get(o["zone"], 0.0) + cost, 2)
    return dict(sorted(totals.items()))


def most_expensive(orders):
    return max(orders, key=lambda o: calc_shipping(o["weight_kg"], o["zone"]))

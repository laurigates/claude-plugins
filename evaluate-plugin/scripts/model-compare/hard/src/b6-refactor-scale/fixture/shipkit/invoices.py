from . import pricing

VAT = 0.255


def invoice_lines(order):
    """order: dict with weight_kg, zone, express, items=[(name, price)]."""
    lines = [(name, price) for name, price in order["items"]]
    shipping = pricing.calc_shipping(
        weight_kg=order["weight_kg"], zone=order["zone"], express=order.get("express", False)
    )
    lines.append(("shipping", shipping))
    return lines


def invoice_total(order):
    net = sum(price for _, price in invoice_lines(order))
    return round(net * (1 + VAT), 2)

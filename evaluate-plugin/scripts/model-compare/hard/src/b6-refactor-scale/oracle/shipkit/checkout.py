from .cart import cart_weight
from .pricing import quote_shipping as _ship

FREE_SHIPPING_FROM = 150.0


def shipping_options(lines, zone, subtotal):
    """Return the shipping options offered at checkout, cheapest first."""
    weight = cart_weight(lines)
    standard = 0.0 if subtotal >= FREE_SHIPPING_FROM else _ship(zone, weight)
    express = _ship(zone, weight, service="express")
    return [("standard", standard), ("express", express)]

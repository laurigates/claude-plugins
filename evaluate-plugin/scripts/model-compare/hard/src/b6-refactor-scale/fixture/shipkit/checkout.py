from .cart import cart_weight
from .pricing import calc_shipping as _ship

FREE_SHIPPING_FROM = 150.0


def shipping_options(lines, zone, subtotal):
    """Return the shipping options offered at checkout, cheapest first."""
    weight = cart_weight(lines)
    standard = 0.0 if subtotal >= FREE_SHIPPING_FROM else _ship(weight, zone)
    express = _ship(weight, zone, True)
    return [("standard", standard), ("express", express)]

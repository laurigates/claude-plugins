from .pricing import calc_shipping

PACKAGING_KG = 0.2


def cart_weight(lines):
    """lines: iterable of (unit_weight_kg, quantity)."""
    return sum(w * q for w, q in lines) + PACKAGING_KG


def cart_shipping(lines, zone, express=False):
    if not lines:
        return 0.0
    return calc_shipping(cart_weight(lines), zone, express=express)

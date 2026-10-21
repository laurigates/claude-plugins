"""Return labels are always domestic standard service."""
import functools

from .pricing import quote_shipping

_domestic = functools.partial(quote_shipping, "DOMESTIC")


def return_label_cost(weight_kg):
    return _domestic(weight_kg)


def refund_after_label(paid, weight_kg):
    return round(max(0.0, paid - return_label_cost(weight_kg)), 2)

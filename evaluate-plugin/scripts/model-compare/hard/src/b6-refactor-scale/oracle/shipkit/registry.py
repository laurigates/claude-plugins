"""Named operations available to pipelines."""
from . import pricing, zones

HANDLERS = {
    "quote_shipping": pricing.quote_shipping,
    "calc_shipping_zone": zones.calc_shipping_zone,
    "zone_rate": lambda zone: zones.ZONE_RATES[zone],
}


def dispatch(op, **kwargs):
    try:
        handler = HANDLERS[op]
    except KeyError:
        raise KeyError(f"unknown operation {op!r}") from None
    return handler(**kwargs)

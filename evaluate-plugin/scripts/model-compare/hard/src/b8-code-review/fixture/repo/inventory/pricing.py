from decimal import ROUND_HALF_UP, Decimal

CENT = Decimal("0.01")
DISCOUNT_TIERS = ((100, Decimal("0.10")), (10, Decimal("0.05")))


def with_vat(net, rate):
    """Gross amount for ``net`` at VAT ``rate`` (e.g. "0.255"), rounded half-up to cents."""
    return (Decimal(net) * (1 + Decimal(rate))).quantize(CENT, ROUND_HALF_UP)


def bulk_discount(qty):
    for threshold, discount in DISCOUNT_TIERS:
        if qty >= threshold:
            return discount
    return Decimal("0")

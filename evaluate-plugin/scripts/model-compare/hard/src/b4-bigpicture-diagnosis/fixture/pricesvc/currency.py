from decimal import ROUND_HALF_UP, Decimal

DECIMALS = {"JPY": 0}


def quantum(currency):
    return Decimal(1).scaleb(-DECIMALS.get(currency, 2))


def convert(amount, rate):
    """Apply an FX multiplier; ``rate`` None means the amount is already in the
    target currency."""
    if rate is None:
        return amount
    return amount * rate


def round_money(amount, currency):
    return amount.quantize(quantum(currency), rounding=ROUND_HALF_UP)

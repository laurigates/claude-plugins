import re

from .errors import InvalidRequest
from .models import QuoteRequest
from .regions import allowed_currencies

_SKU = re.compile(r"^[A-Z0-9][A-Z0-9-]{1,31}$")


def parse_request(raw):
    if not isinstance(raw, dict):
        raise InvalidRequest("request must be an object")
    sku = str(raw.get("sku", "")).strip().upper()
    region = str(raw.get("region", "")).strip().lower()
    currency = str(raw.get("currency", "")).strip().upper()
    if not _SKU.match(sku):
        raise InvalidRequest("invalid sku")
    if currency not in allowed_currencies(region):
        raise InvalidRequest(f"currency {currency or '?'} not sold in region {region or '?'}")
    try:
        quantity = int(raw.get("quantity", 1))
    except (TypeError, ValueError):
        raise InvalidRequest("quantity must be an integer") from None
    if not 1 <= quantity <= 999:
        raise InvalidRequest("quantity out of range")
    return QuoteRequest(sku=sku, region=region, currency_code=currency, quantity=quantity)

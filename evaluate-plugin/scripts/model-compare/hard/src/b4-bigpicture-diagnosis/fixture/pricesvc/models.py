from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True)
class QuoteRequest:
    sku: str
    region: str
    currency_code: str
    quantity: int = 1


@dataclass(frozen=True)
class Quote:
    sku: str
    region: str
    currency_code: str
    unit_price: Decimal
    quantity: int

    @property
    def total(self):
        return self.unit_price * self.quantity

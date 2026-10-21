from dataclasses import dataclass
from datetime import datetime


@dataclass
class Item:
    id: int
    sku: str
    name: str
    category: str
    quantity: int
    price_cents: int
    created_at: datetime
    archived: bool = False


@dataclass
class Movement:
    id: int
    item_id: int
    kind: str  # "in" | "out" | "adjust"
    delta: int
    note: str
    created_at: datetime


@dataclass
class Warehouse:
    id: int
    name: str
    region: str
    created_at: datetime

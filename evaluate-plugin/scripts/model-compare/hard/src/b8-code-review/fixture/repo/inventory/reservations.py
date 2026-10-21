from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

HOLD = timedelta(minutes=15)


@dataclass
class Reservation:
    sku: str
    qty: int
    expires_at: datetime  # naive UTC, as stored in the database


def _utcnow_naive():
    return datetime.now(timezone.utc).replace(tzinfo=None)


class ReservationBook:
    def __init__(self, rows):
        self._items = [Reservation(**r) for r in rows]

    def reserve(self, sku, qty, hold=HOLD):
        r = Reservation(sku, qty, _utcnow_naive() + hold)
        self._items.append(r)
        return r

    def active(self, now=None):
        now = now or datetime.now()
        return [r for r in self._items if r.expires_at > now]

    def reserved_qty(self, sku):
        return sum(r.qty for r in self.active() if r.sku == sku)

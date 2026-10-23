import itertools
import threading
from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class Entry:
    id: int
    customer_id: str
    kind: str              # "charge" | "refund"
    amount_cents: int      # always positive; see signed_amount
    at: datetime           # timezone-aware, UTC
    idempotency_key: str
    gateway_ref: str

    @property
    def signed_amount(self):
        return self.amount_cents if self.kind == "charge" else -self.amount_cents


class Ledger:
    """Append-only, thread-safe list of entries."""

    def __init__(self):
        self._entries = []
        self._ids = itertools.count(1)
        self._lock = threading.Lock()

    @property
    def entries(self):
        with self._lock:
            return list(self._entries)

    def record(self, *, customer_id, kind, amount_cents, at, idempotency_key, gateway_ref):
        if at.tzinfo is None:
            raise ValueError("ledger timestamps must be timezone-aware")
        with self._lock:
            entry = Entry(next(self._ids), customer_id, kind, amount_cents, at,
                          idempotency_key, gateway_ref)
            self._entries.append(entry)
            return entry

    def find_by_key(self, idempotency_key, kind="charge"):
        with self._lock:
            for entry in self._entries:
                if entry.idempotency_key == idempotency_key and entry.kind == kind:
                    return entry
        return None

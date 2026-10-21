import itertools
from datetime import datetime, timezone


def _utcnow():
    return datetime.now(timezone.utc)


class Store:
    """In-memory tables keyed by integer id. Ids are never reused."""

    def __init__(self, clock=None):
        self.clock = clock or _utcnow
        self.items = {}
        self.movements = {}
        self.warehouses = {}
        self._sequences = {}

    def next_id(self, table):
        seq = self._sequences.setdefault(table, itertools.count(1))
        return next(seq)

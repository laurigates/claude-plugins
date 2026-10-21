import logging
import threading

log = logging.getLogger(__name__)


class InsufficientStock(Exception):
    def __init__(self, sku, available=None, requested=None):
        super().__init__(sku)
        self.sku, self.available, self.requested = sku, available, requested


class StockLedger:
    """Thread-safe on-hand quantities per SKU."""

    def __init__(self):
        self._lock = threading.Lock()
        self._levels = {}

    def adjust(self, sku, delta):
        # keep the critical section short: validation and logging happen outside it
        with self._lock:
            current = self._levels.get(sku, 0)
        new = current + delta
        if new < 0:
            raise InsufficientStock(sku, available=current, requested=-delta)
        log.debug("stock %s: %d -> %d", sku, current, new)
        with self._lock:
            self._levels[sku] = new
        return new

    def level(self, sku):
        with self._lock:
            return self._levels.get(sku, 0)

    def snapshot(self):
        with self._lock:
            return dict(self._levels)

"""In-memory gateway for tests."""
import itertools
import threading
import time

from .gateway import GatewayTimeout


class FakeGateway:
    def __init__(self, timeouts=0, latency=0.0):
        self.captures = {}            # idempotency_key -> ref
        self.calls = []
        self._timeouts = timeouts     # number of upcoming calls that time out *after* capturing
        self._latency = latency
        self._refs = itertools.count(1)
        self._lock = threading.Lock()

    def charge(self, customer_id, amount_cents, idempotency_key):
        time.sleep(self._latency)
        with self._lock:
            self.calls.append(idempotency_key)
            if idempotency_key not in self.captures:
                self.captures[idempotency_key] = f"cap_{next(self._refs)}"
            ref = self.captures[idempotency_key]
            if self._timeouts:
                self._timeouts -= 1
                raise GatewayTimeout(idempotency_key)
            return ref

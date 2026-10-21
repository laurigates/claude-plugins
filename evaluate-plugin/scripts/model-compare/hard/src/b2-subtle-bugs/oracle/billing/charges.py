import logging
import threading
import time
from datetime import datetime, timezone

from .gateway import GatewayTimeout

log = logging.getLogger(__name__)

MAX_ATTEMPTS = 3
BACKOFF_SECONDS = 0.01


class IdempotencyConflict(Exception):
    """An idempotency key was reused for a different request."""


def _utcnow():
    return datetime.now(timezone.utc)


def _capture_with_retry(gateway, customer_id, amount_cents, idempotency_key):
    for attempt in range(1, MAX_ATTEMPTS + 1):
        # the SAME key on every attempt: the gateway deduplicates on it, so a
        # timeout after a successful capture is safe to retry
        try:
            return gateway.charge(customer_id, amount_cents, idempotency_key)
        except GatewayTimeout:
            log.warning("gateway timeout (attempt %d/%d) for %s", attempt, MAX_ATTEMPTS, idempotency_key)
            if attempt == MAX_ATTEMPTS:
                raise
            time.sleep(BACKOFF_SECONDS * attempt)


_key_locks = {}
_key_locks_guard = threading.Lock()


def _lock_for(key):
    with _key_locks_guard:
        return _key_locks.setdefault(key, threading.Lock())


def charge(ledger, gateway, *, customer_id, amount_cents, idempotency_key, now=None):
    """Charge a customer exactly once per idempotency key and record it.

    - Calling charge() again with the same idempotency_key (e.g. a client retry)
      must not charge the customer again; it returns the Entry recorded by the
      first successful call.
    - Reusing a key with a different customer_id or amount_cents raises
      IdempotencyConflict.
    - Transient gateway timeouts are retried up to MAX_ATTEMPTS times. If every
      attempt times out, GatewayTimeout propagates and nothing is recorded.
    - GatewayDeclined propagates immediately and nothing is recorded.
    - Calls with different keys must not wait for each other: a gateway call can
      take several seconds.
    """
    if amount_cents <= 0:
        raise ValueError("amount_cents must be positive")
    with _lock_for(idempotency_key):
        existing = ledger.find_by_key(idempotency_key)
        if existing is not None:
            if (existing.customer_id, existing.amount_cents) != (customer_id, amount_cents):
                raise IdempotencyConflict(idempotency_key)
            return existing
        ref = _capture_with_retry(gateway, customer_id, amount_cents, idempotency_key)
        return ledger.record(
            customer_id=customer_id,
            kind="charge",
            amount_cents=amount_cents,
            at=(now or _utcnow()).astimezone(timezone.utc),
            idempotency_key=idempotency_key,
            gateway_ref=ref,
        )


def refund(ledger, *, charge_entry, amount_cents=None, now=None):
    """Record a refund of (part of) a previous charge. Gateway refunds are
    issued by a separate batch job; here we only book them."""
    amount = charge_entry.amount_cents if amount_cents is None else amount_cents
    if not 0 < amount <= charge_entry.amount_cents:
        raise ValueError("refund amount out of range")
    return ledger.record(
        customer_id=charge_entry.customer_id,
        kind="refund",
        amount_cents=amount,
        at=(now or _utcnow()).astimezone(timezone.utc),
        idempotency_key=f"refund:{charge_entry.idempotency_key}",
        gateway_ref=charge_entry.gateway_ref,
    )

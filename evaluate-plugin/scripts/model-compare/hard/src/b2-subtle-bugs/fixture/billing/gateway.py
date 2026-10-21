"""Payment gateway interface.

A gateway object exposes::

    charge(customer_id: str, amount_cents: int, idempotency_key: str) -> str

returning the gateway's capture reference. The gateway deduplicates on
``idempotency_key``: a second call with a key it has already captured returns
the original reference and does not capture again.

``GatewayTimeout`` means "no response in time" - the capture may or may not
have happened. ``GatewayDeclined`` is final.
"""


class GatewayError(Exception):
    pass


class GatewayTimeout(GatewayError):
    pass


class GatewayDeclined(GatewayError):
    pass

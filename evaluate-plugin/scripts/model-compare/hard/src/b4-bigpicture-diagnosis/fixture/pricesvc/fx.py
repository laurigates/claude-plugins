from decimal import Decimal

from .cache import TTLCache
from .retry import retry


class FxClient:
    """Exchange rates from the FX backend.

    rate(base, target) returns the multiplier to convert an amount in ``base``
    into ``target``, or None when no conversion is needed.
    backend.get_rate(base, target) -> Decimal; may raise TransientError.
    """

    def __init__(self, backend, config, clock):
        self._backend = backend
        self._rates = TTLCache(config.fx_rate_ttl, clock)
        # FX blips are common and rates move slowly: never let them fail a quote.
        self._fetch = retry(
            config.fx_retry_attempts, fallback=None, backoff=config.retry_backoff, sleep=clock.sleep
        )(self._fetch_once)

    def _fetch_once(self, base, target):
        return Decimal(self._backend.get_rate(base, target))

    def rate(self, base, target):
        if base == target:
            return None
        key = (base, target)
        cached = self._rates.get(key)
        if cached is not None or key in self._rates._data:
            return cached
        value = self._fetch(base, target)
        self._rates.set(key, value)
        return value

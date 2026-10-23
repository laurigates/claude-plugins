from decimal import Decimal

from .errors import TransientError, UnknownSku, UpstreamUnavailable
from .retry import retry


class CatalogClient:
    """Fetches EUR unit prices from the catalog backend.

    backend.get_price(sku, region) -> Decimal | None (None = unknown sku);
    may raise TransientError.
    """

    def __init__(self, backend, config, clock):
        self._backend = backend
        self._fetch = retry(
            config.catalog_retry_attempts, backoff=config.retry_backoff, sleep=clock.sleep
        )(self._fetch_once)

    def _fetch_once(self, sku, region):
        return self._backend.get_price(sku, region)

    def eur_price(self, sku, region):
        try:
            price = self._fetch(sku, region)
        except TransientError as exc:
            raise UpstreamUnavailable(str(exc)) from exc
        if price is None:
            raise UnknownSku(sku)
        return Decimal(price)

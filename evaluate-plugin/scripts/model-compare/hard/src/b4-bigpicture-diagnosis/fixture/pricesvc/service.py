from .cache import TTLCache
from .currency import convert
from .keys import cache_key
from .models import Quote


class QuoteService:
    def __init__(self, config, catalog, fx, metrics, clock):
        self.config = config
        self.catalog = catalog
        self.fx = fx
        self.metrics = metrics
        self.cache = TTLCache(config.cache_ttl, clock)

    def unit_price(self, req):
        key = cache_key(req, self.config.cache_key_fields)
        cached = self.cache.get(key)
        if cached is not None:
            self.metrics.incr("price_cache_hit")
            return cached
        self.metrics.incr("price_cache_miss")
        eur = self.catalog.eur_price(req.sku, req.region)
        rate = self.fx.rate(self.config.base_currency, req.currency_code)
        price = convert(eur, rate)
        self.cache.set(key, price)
        return price

    def quote(self, req):
        return Quote(
            sku=req.sku,
            region=req.region,
            currency_code=req.currency_code,
            unit_price=self.unit_price(req),
            quantity=req.quantity,
        )

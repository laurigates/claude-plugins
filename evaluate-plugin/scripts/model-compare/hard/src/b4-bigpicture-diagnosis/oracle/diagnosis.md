# INC-2291 diagnosis

Four layers combine:

1. **Retry fallback (fx.py / retry.py).** `FxClient` wrapped the FX fetch in
   `retry(..., fallback=None)`, so after the retries were exhausted the FX outage
   was swallowed and `rate()` returned `None` (and even cached that `None` in the
   rate cache for `fx_rate_ttl`).
2. **Currency conversion (currency.py / service.py).** `convert(amount, None)`
   means "already in the target currency", so the EUR catalog price (14.90) was
   passed through unconverted, and the serializer labelled it with the requested
   currency (SEK). The 503 `rate_unavailable` path in the handler was dead code.
3. **Cache key derivation (config.py + keys.py).** The default
   `cache_key_fields` lists `currency`, but `QuoteRequest` names the attribute
   `currency_code`. `cache_key` silently rendered the missing attribute as empty,
   so the key ignored the currency entirely: SEK, NOK, DKK and EUR quotes for the
   same sku/region shared one entry. That is how the bad EUR-as-SEK number was
   then served to NOK customers, and how a DKK customer saw a SEK amount on a
   normal day.
4. **Price cache TTL.** The wrong unit price lived in the price cache for
   `cache_ttl` (300 s), which is why it persisted after the FX provider recovered
   and why a restart "fixed" it.

Fixes: the FX client no longer uses a fallback; transient failures are still
retried, and on exhaustion it raises `RateUnavailable` (handler -> 503) and caches
nothing. The default key fields use `currency_code`, and `cache_key` now raises
for a field that does not exist on the request instead of silently collapsing
keys. The retry decorator itself is unchanged: metrics intentionally use its
fallback so a metrics outage never fails a quote.

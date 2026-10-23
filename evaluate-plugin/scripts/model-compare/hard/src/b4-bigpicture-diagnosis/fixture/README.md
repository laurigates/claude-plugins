# pricesvc

Quote service for the storefronts. Given a SKU, a sales region and a currency it
returns a unit price and a total. Catalog prices are kept in EUR; other
currencies are converted with the FX service.

## API

`App.handle_quote(request: dict) -> (status, body)`

Request: `{"sku": str, "region": str, "currency": str, "quantity": int (optional, default 1)}`

| Status | Body |
|--------|------|
| 200 | `{"sku", "region", "currency", "unit_price", "total", "quantity"}` - amounts are strings with the currency's number of decimals |
| 400 | `{"error": "invalid_request", "detail": "..."}` |
| 404 | `{"error": "unknown_sku"}` |
| 502 | `{"error": "upstream_unavailable"}` - catalog could not be reached |
| 503 | `{"error": "rate_unavailable"}` - an exchange rate could not be obtained |

## Architecture

    handlers -> service -> (cache, catalog client, fx client) -> backends
                       \-> serializer

* `retry.py` - retry decorator used by every outbound client.
* `cache.py` / `keys.py` - TTL cache for unit prices; the key is derived from
  the request fields listed in config `cache_key_fields`.
* `fx.py` - FX client with its own short-lived rate cache.
* `metrics.py` - best-effort metrics; a metrics outage must never fail a quote.

## Configuration

`load_config(overrides=None, env=os.environ)`; every key in
`config.DEFAULTS` can be overridden with an environment variable
`PRICESVC_<KEY>` (tuples are comma separated).

## Tests

    python3 -m unittest discover -s tests -t .

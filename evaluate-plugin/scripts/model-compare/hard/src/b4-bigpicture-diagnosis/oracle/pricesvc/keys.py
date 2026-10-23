def cache_key(request, fields):
    """Build a cache key from the given request fields, e.g.
    ``price:sku=AA-24|region=nordic|currency_code=SEK``.

    Every configured field must exist on the request: silently rendering a
    misspelt field as empty would collapse distinct requests onto one key.
    Optional fields that exist but are None are rendered as empty."""
    parts = []
    for name in fields:
        if not hasattr(request, name):
            raise AttributeError(f"cache key field {name!r} does not exist on {type(request).__name__}")
        value = getattr(request, name)
        parts.append(f"{name}={'' if value is None else value}")
    return "price:" + "|".join(parts)

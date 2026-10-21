def cache_key(request, fields):
    """Build a cache key from the given request fields, e.g.
    ``price:sku=AA-24|region=nordic``. Fields absent on the request are rendered
    as empty so that optional fields don't break key construction."""
    parts = []
    for name in fields:
        value = getattr(request, name, None)
        parts.append(f"{name}={'' if value is None else value}")
    return "price:" + "|".join(parts)

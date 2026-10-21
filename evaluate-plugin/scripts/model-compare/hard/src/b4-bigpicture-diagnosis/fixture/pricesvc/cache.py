class TTLCache:
    """Tiny TTL cache. ``clock`` provides monotonic()."""

    def __init__(self, ttl, clock):
        self.ttl = ttl
        self.clock = clock
        self._data = {}

    def get(self, key):
        hit = self._data.get(key)
        if hit is None:
            return None
        value, expires = hit
        if self.clock.monotonic() >= expires:
            del self._data[key]
            return None
        return value

    def set(self, key, value):
        self._data[key] = (value, self.clock.monotonic() + self.ttl)

    def clear(self):
        self._data.clear()

    def __len__(self):
        return len(self._data)

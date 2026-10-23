from .retry import retry


class Metrics:
    """Best-effort metrics. backend.push(name, value) may raise TransientError;
    failures are retried once and then dropped."""

    def __init__(self, backend, config):
        self._backend = backend
        self._enabled = config.metrics_enabled
        self.dropped = 0

    @retry(2, fallback=False)
    def _push(self, name, value):
        self._backend.push(name, value)
        return True

    def incr(self, name, value=1):
        if not self._enabled or self._backend is None:
            return
        if not self._push(name, value):
            self.dropped += 1

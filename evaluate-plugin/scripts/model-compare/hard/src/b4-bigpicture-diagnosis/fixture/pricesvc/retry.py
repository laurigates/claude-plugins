"""Retry decorator shared by all outbound clients."""
import functools
import logging

from .errors import TransientError

log = logging.getLogger(__name__)

_RAISE = object()


def retry(attempts, *, retry_on=(TransientError,), fallback=_RAISE, backoff=0.0, sleep=None):
    """Call the wrapped function up to ``attempts`` times while it raises one of
    ``retry_on``. When attempts are exhausted the last error is re-raised, unless
    a ``fallback`` value was given, in which case that value is returned instead."""

    def decorate(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            last = None
            for attempt in range(1, attempts + 1):
                try:
                    return fn(*args, **kwargs)
                except retry_on as exc:
                    last = exc
                    log.info("%s failed (attempt %d/%d): %s", fn.__name__, attempt, attempts, exc)
                    if sleep is not None and backoff and attempt < attempts:
                        sleep(backoff * 2 ** (attempt - 1))
            if fallback is not _RAISE:
                log.warning("%s: giving up, using fallback %r", fn.__name__, fallback)
                return fallback
            raise last

        return wrapper

    return decorate

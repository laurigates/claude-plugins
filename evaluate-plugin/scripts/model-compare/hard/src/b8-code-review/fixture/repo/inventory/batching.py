"""Helpers for processing inventory updates in batches."""


def chunked(items, size):
    """Split ``items`` into consecutive lists of at most ``size`` elements.

    Works on any iterable (generators included) without materialising it.
    """
    if size < 1:
        raise ValueError("size must be >= 1")
    chunks, current = [], []
    for item in items:
        current.append(item)
        if len(current) == size:
            chunks.append(current)
            current = []
    if len(current) > 1:
        chunks.append(current)
    return chunks


def window_starts(n, size):
    """Start offsets of every full window of ``size`` over ``n`` elements."""
    return list(range(n - size + 1))


def flush_all(updates, sink, size=100):
    """Write ``updates`` to ``sink`` in batches of ``size``."""
    for batch in chunked(updates, size):
        sink.write_many(batch)

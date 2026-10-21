"""Keyset pagination helpers shared by the list services."""
import base64
import json
from datetime import datetime

from .errors import InvalidCursorError
from .models import Page
from .validation import parse_int

DEFAULT_LIMIT = 20
MAX_LIMIT = 100


def parse_limit(raw):
    return parse_int(raw, "limit", default=DEFAULT_LIMIT, min_value=1, max_value=MAX_LIMIT)


def _sort_key(row):
    return (row.created_at, row.id)


def encode_cursor(scope, filters, row):
    payload = {"s": scope, "f": filters, "k": [row.created_at.isoformat(), row.id]}
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def decode_cursor(cursor, scope, filters):
    if cursor in (None, ""):
        return None
    try:
        text = str(cursor)
        raw = base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))
        payload = json.loads(raw)
        created_at = datetime.fromisoformat(payload["k"][0])
        row_id = payload["k"][1]
        ok = (
            payload["s"] == scope
            and payload["f"] == filters
            and isinstance(row_id, int)
            and created_at.tzinfo is not None
        )
    except Exception:
        ok = False
    if not ok:
        raise InvalidCursorError("cursor is invalid", field="cursor")
    return (created_at, row_id)


def paginate(rows, *, scope, filters, limit, cursor, descending=False):
    after = decode_cursor(cursor, scope, filters)
    rows = sorted(rows, key=_sort_key, reverse=descending)
    if after is not None:
        if descending:
            rows = [r for r in rows if _sort_key(r) < after]
        else:
            rows = [r for r in rows if _sort_key(r) > after]
    page = rows[:limit]
    more = len(rows) > limit
    next_cursor = encode_cursor(scope, filters, page[-1]) if more else None
    return Page(items=page, next_cursor=next_cursor)

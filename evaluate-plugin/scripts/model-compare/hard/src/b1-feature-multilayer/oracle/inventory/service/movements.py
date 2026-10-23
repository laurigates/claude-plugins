from ..errors import ConflictError
from ..models import Movement
from ..repo import movements as repo
from ..pagination import paginate, parse_limit
from ..validation import parse_choice, parse_datetime, parse_int, require
from . import items as item_service

KINDS = ("in", "out", "adjust")


def record_movement(store, *, item_id, kind, delta, note=None):
    item = item_service.get_item(store, item_id)
    kind = parse_choice(kind, "kind", KINDS)
    require(kind is not None, "kind", "kind is required")
    delta = parse_int(delta, "delta")
    require(delta is not None, "delta", "delta is required")
    if kind in ("in", "out"):
        require(delta > 0, "delta", "delta must be positive for in/out movements")
    change = -delta if kind == "out" else delta
    if item.quantity + change < 0:
        raise ConflictError("insufficient stock", field="delta")
    item.quantity += change
    movement = Movement(
        id=store.next_id("movements"),
        item_id=item.id,
        kind=kind,
        delta=change,
        note=(note or "").strip(),
        created_at=store.clock(),
    )
    return repo.insert(store, movement)


def list_movements(store, *, limit=None, cursor=None, item_id=None, kind=None, since=None):
    limit = parse_limit(limit)
    item_id = parse_int(item_id, "item_id", min_value=1)
    kind = parse_choice(kind, "kind", KINDS)
    since = parse_datetime(since, "since")
    filters = {
        "item_id": item_id,
        "kind": kind,
        "since": since.isoformat() if since is not None else None,
    }

    def matches(m):
        return (
            (item_id is None or m.item_id == item_id)
            and (kind is None or m.kind == kind)
            and (since is None or m.created_at >= since)
        )

    rows = [m for m in repo.all_movements(store) if matches(m)]
    return paginate(rows, scope="movements", filters=filters, limit=limit, cursor=cursor,
                    descending=True)

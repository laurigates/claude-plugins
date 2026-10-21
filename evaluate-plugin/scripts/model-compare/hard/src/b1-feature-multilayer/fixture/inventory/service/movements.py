from ..errors import ConflictError
from ..models import Movement
from ..repo import movements as repo
from ..validation import parse_choice, parse_int, require
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


def list_movements(store):
    return repo.all_movements(store)

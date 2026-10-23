from ..service import movements as service
from ._errors import endpoint
from .serializers import movement_to_dict


@endpoint
def list_movements(store, request):
    movements = service.list_movements(store)
    return 200, {"items": [movement_to_dict(m) for m in movements]}


@endpoint
def create_movement(store, request):
    body = request.get("body") or {}
    movement = service.record_movement(
        store,
        item_id=body.get("item_id"),
        kind=body.get("kind"),
        delta=body.get("delta"),
        note=body.get("note"),
    )
    return 201, movement_to_dict(movement)

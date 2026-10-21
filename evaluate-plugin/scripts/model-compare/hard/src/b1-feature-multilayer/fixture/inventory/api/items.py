from ..service import items as service
from ._errors import endpoint
from .serializers import item_to_dict


@endpoint
def list_items(store, request):
    items = service.list_items(store)
    return 200, {"items": [item_to_dict(i) for i in items]}


@endpoint
def get_item(store, request):
    item = service.get_item(store, request.get("params", {}).get("id"))
    return 200, item_to_dict(item)


@endpoint
def create_item(store, request):
    body = request.get("body") or {}
    item = service.create_item(
        store,
        sku=body.get("sku"),
        name=body.get("name"),
        category=body.get("category"),
        quantity=body.get("quantity"),
        price_cents=body.get("price_cents"),
        created_at=body.get("created_at"),
    )
    return 201, item_to_dict(item)


@endpoint
def archive_item(store, request):
    item = service.archive_item(store, request.get("params", {}).get("id"))
    return 200, item_to_dict(item)


@endpoint
def delete_item(store, request):
    service.delete_item(store, request.get("params", {}).get("id"))
    return 204, {}

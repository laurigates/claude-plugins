from ..service import warehouses as service
from ._errors import endpoint
from .serializers import warehouse_to_dict


@endpoint
def list_warehouses(store, request):
    return 200, {"items": [warehouse_to_dict(w) for w in service.list_warehouses(store)]}


@endpoint
def create_warehouse(store, request):
    body = request.get("body") or {}
    warehouse = service.create_warehouse(store, name=body.get("name"), region=body.get("region"))
    return 201, warehouse_to_dict(warehouse)

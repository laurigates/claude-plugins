from . import items, movements, warehouses

ROUTES = {
    ("GET", "/items"): items.list_items,
    ("POST", "/items"): items.create_item,
    ("GET", "/items/{id}"): items.get_item,
    ("POST", "/items/{id}/archive"): items.archive_item,
    ("DELETE", "/items/{id}"): items.delete_item,
    ("GET", "/movements"): movements.list_movements,
    ("POST", "/movements"): movements.create_movement,
    ("GET", "/warehouses"): warehouses.list_warehouses,
    ("POST", "/warehouses"): warehouses.create_warehouse,
}


def dispatch(store, method, route, request=None):
    handler = ROUTES.get((method, route))
    if handler is None:
        return 404, {"error": {"code": "no_route", "message": f"{method} {route}"}}
    return handler(store, request or {})

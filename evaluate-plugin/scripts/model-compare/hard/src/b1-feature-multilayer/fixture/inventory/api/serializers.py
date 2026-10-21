def _ts(value):
    return value.isoformat()


def item_to_dict(item):
    return {
        "id": item.id,
        "sku": item.sku,
        "name": item.name,
        "category": item.category,
        "quantity": item.quantity,
        "price": f"{item.price_cents // 100}.{item.price_cents % 100:02d}",
        "archived": item.archived,
        "created_at": _ts(item.created_at),
    }


def movement_to_dict(movement):
    return {
        "id": movement.id,
        "item_id": movement.item_id,
        "kind": movement.kind,
        "delta": movement.delta,
        "note": movement.note,
        "created_at": _ts(movement.created_at),
    }


def warehouse_to_dict(warehouse):
    return {
        "id": warehouse.id,
        "name": warehouse.name,
        "region": warehouse.region,
        "created_at": _ts(warehouse.created_at),
    }

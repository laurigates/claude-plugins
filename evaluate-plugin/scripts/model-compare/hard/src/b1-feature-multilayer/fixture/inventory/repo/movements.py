"""Storage access for stock movements."""


def insert(store, movement):
    store.movements[movement.id] = movement
    return movement


def all_movements(store):
    return list(store.movements.values())


def for_item(store, item_id):
    return [m for m in store.movements.values() if m.item_id == item_id]

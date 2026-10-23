"""Storage access for items. No validation happens here."""


def insert(store, item):
    store.items[item.id] = item
    return item


def get(store, item_id):
    return store.items.get(item_id)


def get_by_sku(store, sku):
    for item in store.items.values():
        if item.sku == sku:
            return item
    return None


def all_items(store):
    return list(store.items.values())


def delete(store, item_id):
    return store.items.pop(item_id, None)

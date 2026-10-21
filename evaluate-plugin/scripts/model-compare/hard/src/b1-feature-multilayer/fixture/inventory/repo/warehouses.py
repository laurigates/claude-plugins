"""Storage access for warehouses."""


def insert(store, warehouse):
    store.warehouses[warehouse.id] = warehouse
    return warehouse


def get(store, warehouse_id):
    return store.warehouses.get(warehouse_id)


def all_warehouses(store):
    return list(store.warehouses.values())

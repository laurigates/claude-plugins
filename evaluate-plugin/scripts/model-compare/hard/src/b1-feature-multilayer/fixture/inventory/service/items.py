from ..errors import ConflictError, NotFoundError
from ..models import Item
from ..repo import items as repo
from ..validation import non_empty_str, parse_datetime, parse_int

CATEGORIES = ("tools", "hardware", "electrical", "garden", "paint")


def create_item(store, *, sku, name, category, quantity=None, price_cents=None, created_at=None):
    sku = non_empty_str(sku, "sku", max_length=32).upper()
    name = non_empty_str(name, "name")
    category = non_empty_str(category, "category", max_length=32)
    quantity = parse_int(quantity, "quantity", default=0, min_value=0)
    price_cents = parse_int(price_cents, "price_cents", default=0, min_value=0)
    created_at = parse_datetime(created_at, "created_at", default=None) or store.clock()
    if repo.get_by_sku(store, sku) is not None:
        raise ConflictError(f"sku {sku} already exists", field="sku")
    item = Item(
        id=store.next_id("items"),
        sku=sku,
        name=name,
        category=category,
        quantity=quantity,
        price_cents=price_cents,
        created_at=created_at,
    )
    return repo.insert(store, item)


def get_item(store, item_id):
    item_id = parse_int(item_id, "id", min_value=1)
    item = repo.get(store, item_id)
    if item is None:
        raise NotFoundError(f"item {item_id} not found")
    return item


def list_items(store):
    return [item for item in repo.all_items(store) if not item.archived]


def archive_item(store, item_id):
    item = get_item(store, item_id)
    item.archived = True
    return item


def delete_item(store, item_id):
    item = get_item(store, item_id)
    if item.quantity:
        raise ConflictError("cannot delete an item with stock on hand", field="quantity")
    repo.delete(store, item.id)
    return item

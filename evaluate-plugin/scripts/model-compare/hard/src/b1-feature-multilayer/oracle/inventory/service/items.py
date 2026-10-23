from ..errors import ConflictError, NotFoundError
from ..models import Item
from ..repo import items as repo
from ..pagination import paginate, parse_limit
from ..validation import non_empty_str, parse_bool, parse_datetime, parse_int

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


def list_items(store, *, limit=None, cursor=None, category=None, min_quantity=None,
               archived=None, q=None):
    limit = parse_limit(limit)
    category = None if category in (None, "") else str(category)
    min_quantity = parse_int(min_quantity, "min_quantity", min_value=0)
    archived = parse_bool(archived, "archived", default=False)
    q = None if q in (None, "") else str(q).lower()
    filters = {"category": category, "min_quantity": min_quantity, "archived": archived, "q": q}

    def matches(item):
        return (
            item.archived == archived
            and (category is None or item.category == category)
            and (min_quantity is None or item.quantity >= min_quantity)
            and (q is None or q in item.name.lower() or q in item.sku.lower())
        )

    rows = [item for item in repo.all_items(store) if matches(item)]
    return paginate(rows, scope="items", filters=filters, limit=limit, cursor=cursor)


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

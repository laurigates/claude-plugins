from ..models import Warehouse
from ..repo import warehouses as repo
from ..validation import non_empty_str, parse_choice

REGIONS = ("north", "south", "east", "west")


def create_warehouse(store, *, name, region):
    name = non_empty_str(name, "name")
    region = parse_choice(region, "region", REGIONS)
    if region is None:
        region = "north"
    warehouse = Warehouse(
        id=store.next_id("warehouses"), name=name, region=region, created_at=store.clock()
    )
    return repo.insert(store, warehouse)


def list_warehouses(store):
    return sorted(repo.all_warehouses(store), key=lambda w: w.name.lower())

import functools

from ..errors import InventoryError


def endpoint(handler):
    """Wrap a handler so domain errors become the standard error envelope."""

    @functools.wraps(handler)
    def wrapper(store, request=None):
        try:
            return handler(store, request or {})
        except InventoryError as err:
            return err.status, {"error": err.to_dict()}

    return wrapper

# inventory

A small in-memory inventory service. There is no HTTP server: each endpoint is a
plain function `handler(store, request) -> (status, body)` registered in
`inventory/api/routes.py`. `request` is a dict with optional keys:

- `query`  - dict of query-string values (always strings, as a web framework would pass them)
- `params` - dict of path parameters (strings)
- `body`   - decoded JSON body (dict)

## Layers

| Layer | Package | Responsibility |
|-------|---------|----------------|
| models | `inventory/models.py` | dataclasses, no behaviour |
| repo | `inventory/repo/` | storage access only; no validation, no errors other than returning `None` |
| service | `inventory/service/` | business rules and **all input parsing/validation** |
| api | `inventory/api/` | maps request dicts to service calls and domain objects to JSON-able dicts |

## Conventions

- **Errors.** Every domain error is a subclass of `inventory.errors.InventoryError`
  and carries a stable `code`, an HTTP `status`, and an optional `field`. New
  error kinds are added to `inventory/errors.py` as subclasses; never raise bare
  `ValueError`/`KeyError` out of the service layer.
- **Validation.** Raw request values are passed to the service layer unparsed.
  The service parses them with the helpers in `inventory/validation.py`
  (`parse_int`, `parse_bool`, `parse_choice`, `parse_datetime`, `non_empty_str`,
  `require`) so that error messages are uniform across endpoints.
- **Error envelope.** Handlers are wrapped with `@endpoint` (`inventory/api/_errors.py`),
  which turns an `InventoryError` into `(err.status, {"error": err.to_dict()})`.
- **Serialization.** Domain objects are turned into dicts only through
  `inventory/api/serializers.py`.
- **Time.** The store owns the clock (`store.clock()`, timezone-aware UTC). Never
  call `datetime.now()` elsewhere.

## Running the tests

    python3 run_tests.py

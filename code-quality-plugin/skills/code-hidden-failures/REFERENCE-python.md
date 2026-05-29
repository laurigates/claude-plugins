# Reference — Python Error Swallowing

Detection rules for `.py`. Use `sg --lang py` for structural matches.

## Patterns

| ID | ast-grep pattern | Default severity |
|----|------------------|------------------|
| `py-bare-except-pass` | `try:\n  $$$\nexcept:\n  pass` | High |
| `py-broad-except-pass` | `except Exception: pass` / `except BaseException: pass` | High |
| `py-typed-except-pass` | `except $TYPE: pass` (narrow type) | Medium |
| `py-except-ellipsis` | `except $TYPE: ...` | Medium |
| `py-except-only-log-debug` | `except $TYPE as $E:\n  logging.debug($$$)` with no raise | Medium |
| `py-suppress-misuse` | `contextlib.suppress(Exception):` wrapping a required op | High |
| `py-suppress-narrow` | `contextlib.suppress(FileNotFoundError):` on cache/optional path | Low |
| `py-asyncio-ensure-future-floating` | `asyncio.ensure_future(coro)` with no task registered | Medium |
| `py-try-return-none` | `except $T: return None` where caller doesn't check | Medium |

### ast-grep commands

```bash
sg -p $'try:\n  $$$\nexcept:\n  pass' --lang py
sg -p $'try:\n  $$$\nexcept Exception:\n  pass' --lang py
sg -p $'with suppress($TYPE):\n  $$$' --lang py
```

## Allowlist (classify as Low)

| Pattern | Why |
|---------|-----|
| `except (FileNotFoundError, PermissionError): pass` on optional cache | Intentional, narrow, harmless |
| `except KeyboardInterrupt` that re-raises or sys.exit()s cleanly | Signal handling |
| `except $T as e: logger.exception(...); raise` | Log + re-raise — correct |
| Any `except` containing `raise` | Propagates, not suppresses |
| `except` inside a `__del__` or `__exit__` finalizer | Python style requires suppression to avoid secondary exceptions |

## Severity promotion

Promote to **High** if the protected suite contains:

- DB mutation: `session.commit`, `cursor.execute` with INSERT/UPDATE/DELETE
- FS writes outside `/tmp`
- Network writes: `requests.post`, `requests.put`, `requests.delete`,
  `httpx.*` mutating methods
- Crypto: `sign`, `decrypt`, `verify`, key loading
- Config loading: `yaml.safe_load`, `json.load` on files the app depends on

Demote a `py-bare-except-pass` to Medium only when the enclosing function is
a `__del__`, `__exit__`, or an explicit `atexit` handler.

## Remediation templates

### CLI script

```python
# Before
try:
    do_thing()
except:
    pass

# After
try:
    do_thing()
except Exception as exc:  # noqa: BLE001 — surfaced below
    print(f"warn: do_thing failed: {exc}", file=sys.stderr)  # TODO(error-swallowing): review wording
    sys.exit(1)
```

### Backend service

```python
# Before
try:
    db.commit()
except Exception:
    pass

# After
try:
    db.commit()
except Exception:
    logger.exception("db.commit failed")
    raise
```

### Library

```python
# Before
try:
    result = parse(data)
except ValueError:
    return None

# After — option A: propagate
return parse(data)

# After — option B: explicit Result-like return
try:
    return parse(data), None
except ValueError as exc:
    return None, exc
```

## Framework-specific notes

### Django

- `get_object_or_404` inside an `except Http404: pass` branch is **High**
  when it hides a permissions/ownership check failure.

### FastAPI

- A route handler `except` that returns 200 with empty body instead of
  raising `HTTPException` is **High**.

### Celery

- A task `except: pass` prevents retries and silences the worker — **High**
  unless the task is explicitly `acks_late=False` with documented reason.

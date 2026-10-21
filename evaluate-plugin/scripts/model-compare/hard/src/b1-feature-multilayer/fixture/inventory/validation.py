"""Parsing helpers shared by every service function.

All helpers accept the raw value as it arrived (usually a string from a query
string, sometimes an already-typed value from a JSON body or an internal
caller). ``None`` and ``""`` mean "not supplied" and yield ``default``.
"""
from datetime import datetime

from .errors import ValidationError

_MISSING = (None, "")


def require(condition, field, message):
    if not condition:
        raise ValidationError(message, field=field)


def _range_message(field, lo, hi):
    if lo is not None and hi is not None:
        return f"{field} must be between {lo} and {hi}"
    if lo is not None:
        return f"{field} must be >= {lo}"
    return f"{field} must be <= {hi}"


def parse_int(raw, field, *, default=None, min_value=None, max_value=None):
    if raw in _MISSING:
        return default
    if isinstance(raw, bool):
        raise ValidationError(f"{field} must be an integer", field=field)
    if isinstance(raw, int):
        value = raw
    else:
        try:
            value = int(str(raw).strip(), 10)
        except ValueError:
            raise ValidationError(f"{field} must be an integer", field=field) from None
    if (min_value is not None and value < min_value) or (
        max_value is not None and value > max_value
    ):
        raise ValidationError(_range_message(field, min_value, max_value), field=field)
    return value


def parse_bool(raw, field, *, default=None):
    if raw in _MISSING:
        return default
    if isinstance(raw, bool):
        return raw
    text = str(raw).strip().lower()
    if text in ("true", "1", "yes"):
        return True
    if text in ("false", "0", "no"):
        return False
    raise ValidationError(f"{field} must be a boolean", field=field)


def parse_choice(raw, field, choices, *, default=None):
    if raw in _MISSING:
        return default
    if raw not in choices:
        raise ValidationError(
            f"{field} must be one of: {', '.join(choices)}", field=field
        )
    return raw


def parse_datetime(raw, field, *, default=None):
    """ISO 8601 timestamp with an explicit offset (``Z`` allowed)."""
    if raw in _MISSING:
        return default
    if isinstance(raw, datetime):
        value = raw
    else:
        try:
            value = datetime.fromisoformat(str(raw).strip())
        except ValueError:
            raise ValidationError(f"{field} must be an ISO 8601 timestamp", field=field) from None
    if value.tzinfo is None:
        raise ValidationError(f"{field} must include a timezone offset", field=field)
    return value


def non_empty_str(raw, field, *, max_length=200):
    if raw is None or not isinstance(raw, str) or not raw.strip():
        raise ValidationError(f"{field} is required", field=field)
    value = raw.strip()
    if len(value) > max_length:
        raise ValidationError(f"{field} must be at most {max_length} characters", field=field)
    return value

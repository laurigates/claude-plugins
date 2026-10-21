import os
from dataclasses import dataclass, fields

DEFAULTS = {
    "cache_ttl": 300,
    "cache_key_fields": ("sku", "region", "currency_code"),
    "fx_rate_ttl": 60,
    "fx_retry_attempts": 3,
    "catalog_retry_attempts": 2,
    "retry_backoff": 0.0,
    "base_currency": "EUR",
    "metrics_enabled": True,
}


@dataclass(frozen=True)
class Config:
    cache_ttl: int
    cache_key_fields: tuple
    fx_rate_ttl: int
    fx_retry_attempts: int
    catalog_retry_attempts: int
    retry_backoff: float
    base_currency: str
    metrics_enabled: bool


def _coerce(name, raw, default):
    if isinstance(default, bool):
        return str(raw).lower() in ("1", "true", "yes")
    if isinstance(default, tuple):
        return tuple(p.strip() for p in str(raw).split(",") if p.strip())
    return type(default)(raw)


def load_config(overrides=None, env=None):
    env = os.environ if env is None else env
    values = dict(DEFAULTS)
    for f in fields(Config):
        key = f"PRICESVC_{f.name.upper()}"
        if key in env:
            values[f.name] = _coerce(f.name, env[key], DEFAULTS[f.name])
    values.update(overrides or {})
    return Config(**values)

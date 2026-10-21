# shipkit

Shipping-cost toolkit used by the web shop, the marketplace and the returns desk.

## Pricing

All prices come from one function:

```python
from shipkit.pricing import quote_shipping

quote_shipping("EU", 2.3)                     # standard service
quote_shipping("EU", 2.3, service="express")  # express service
```

`service` is `"standard"` (default) or `"express"`. The old
`calc_shipping(weight_kg, zone, express=False)` remains as a deprecated alias.

Weights are rounded up to the next half kilogram. Zones are defined in
`shipkit/zones.py`; use `calc_shipping_zone(country_code)` to map an ISO
country code to a zone.

## Pipelines

Batch jobs are described in `config/pipelines.json`. Each step names an
operation registered in `shipkit/registry.py` (for example `quote_shipping` or
`calc_shipping_zone`) and its keyword arguments.

## CLI

    python3 -m shipkit.cli --zone EU --weight 2.5 [--express]

## Tests

    python3 -m unittest discover -s tests -t .

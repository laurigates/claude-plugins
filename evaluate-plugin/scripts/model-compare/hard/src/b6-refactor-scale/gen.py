"""Derive the b6 oracle from the fixture via explicit, asserted replacements."""
import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIX, ORA = HERE / "fixture", HERE / "oracle"

EDITS = {
    "shipkit/pricing.py": [
        ('"""Shipping price calculation."""\nimport math\n',
         '"""Shipping price calculation."""\nimport math\nimport warnings\n'),
        ('EXPRESS_FACTOR = 1.5\n',
         'EXPRESS_FACTOR = 1.5\nSERVICES = ("standard", "express")\n'),
        ('def calc_shipping(weight_kg, zone, express=False):\n    """Price in euros for sending a parcel of ``weight_kg`` to ``zone``.',
         'def quote_shipping(zone, weight_kg, *, service="standard"):\n    """Price in euros for sending a parcel of ``weight_kg`` to ``zone``.'),
        ('    higher base fee and a 1.5x surcharge on the total.\n    """\n',
         '    higher base fee and a 1.5x surcharge on the total. ``service`` is\n'
         '    "standard" or "express".\n    """\n    if service not in SERVICES:\n'
         '        raise ValueError(f"unknown service {service!r}")\n'),
        ('    service = "express" if express else "standard"\n', ''),
        ('    if express:\n        price *= EXPRESS_FACTOR\n    return round(price, 2)\n',
         '    if service == "express":\n        price *= EXPRESS_FACTOR\n    return round(price, 2)\n\n\n'
         'def calc_shipping(weight_kg, zone, express=False):\n'
         '    """Deprecated: use ``quote_shipping(zone, weight_kg, service=...)``."""\n'
         '    warnings.warn(\n'
         '        "calc_shipping() is deprecated; use quote_shipping(zone, weight_kg, service=...)",\n'
         '        DeprecationWarning,\n        stacklevel=2,\n    )\n'
         '    return quote_shipping(zone, weight_kg, service="express" if express else "standard")\n'),
    ],
    "shipkit/__init__.py": [
        ("from .pricing import calc_shipping\n", "from .pricing import calc_shipping, quote_shipping  # calc_shipping: deprecated alias\n"),
        ('__all__ = ["Parcel", "calc_shipping", "calc_shipping_zone"]', '__all__ = ["Parcel", "calc_shipping_zone", "quote_shipping"]'),
    ],
    "shipkit/parcel.py": [
        ("from .pricing import calc_shipping", "from .pricing import quote_shipping"),
        ("        return calc_shipping(self.billable_kg, zone, express)",
         '        return quote_shipping(zone, self.billable_kg, service="express" if express else "standard")'),
    ],
    "shipkit/cart.py": [
        ("from .pricing import calc_shipping", "from .pricing import quote_shipping"),
        ("    return calc_shipping(cart_weight(lines), zone, express=express)",
         '    return quote_shipping(zone, cart_weight(lines), service="express" if express else "standard")'),
    ],
    "shipkit/checkout.py": [
        ("from .pricing import calc_shipping as _ship", "from .pricing import quote_shipping as _ship"),
        ("_ship(weight, zone)\n", "_ship(zone, weight)\n"),
        ("_ship(weight, zone, True)", '_ship(zone, weight, service="express")'),
    ],
    "shipkit/invoices.py": [
        ("""    shipping = pricing.calc_shipping(
        weight_kg=order["weight_kg"], zone=order["zone"], express=order.get("express", False)
    )""", """    service = "express" if order.get("express", False) else "standard"
    shipping = pricing.quote_shipping(
        weight_kg=order["weight_kg"], zone=order["zone"], service=service
    )"""),
    ],
    "shipkit/returns.py": [
        ("from .pricing import calc_shipping", "from .pricing import quote_shipping"),
        ('_domestic = functools.partial(calc_shipping, zone="DOMESTIC")', '_domestic = functools.partial(quote_shipping, "DOMESTIC")'),
    ],
    "shipkit/bulk.py": [
        ("from .pricing import calc_shipping", "from .pricing import quote_shipping"),
        ("    return list(map(calc_shipping, weights, zones))", "    return list(map(quote_shipping, zones, weights))"),
        ("key=lambda z: calc_shipping(weight_kg, z)", "key=lambda z: quote_shipping(z, weight_kg)"),
    ],
    "shipkit/plugins.py": [('PRICER_NAME = "calc_shipping"', 'PRICER_NAME = "quote_shipping"')],
    "shipkit/registry.py": [('    "calc_shipping": pricing.calc_shipping,', '    "quote_shipping": pricing.quote_shipping,')],
    "config/pipelines.json": [
        ('{"op": "calc_shipping", "args": {"weight_kg": 2.5, "zone": "NORDIC"}}',
         '{"op": "quote_shipping", "args": {"weight_kg": 2.5, "zone": "NORDIC"}}'),
        ('{"op": "calc_shipping", "args": {"weight_kg": 0.4, "zone": "EU", "express": true}}',
         '{"op": "quote_shipping", "args": {"weight_kg": 0.4, "zone": "EU", "service": "express"}}'),
        ('{"op": "calc_shipping", "args": {"weight_kg": 12, "zone": "WORLD", "express": true}}',
         '{"op": "quote_shipping", "args": {"weight_kg": 12, "zone": "WORLD", "service": "express"}}'),
        ('{"op": "calc_shipping", "args": {"weight_kg": 1, "zone": "DOMESTIC", "express": false}}',
         '{"op": "quote_shipping", "args": {"weight_kg": 1, "zone": "DOMESTIC", "service": "standard"}}'),
    ],
    "shipkit/cli.py": [
        ("from .pricing import calc_shipping", "from .pricing import quote_shipping"),
        ("    price = calc_shipping(args.weight, args.zone, args.express)",
         '    price = quote_shipping(args.zone, args.weight, service="express" if args.express else "standard")'),
    ],
    "shipkit/reports.py": [
        ("recomputed with calc_shipping so", "recomputed with quote_shipping so"),
        ("from .pricing import calc_shipping", "from .pricing import quote_shipping"),
        ('        cost = calc_shipping(o["weight_kg"], o["zone"], o.get("express", False))',
         '        service = "express" if o.get("express", False) else "standard"\n'
         '        cost = quote_shipping(o["zone"], o["weight_kg"], service=service)'),
        ('key=lambda o: calc_shipping(o["weight_kg"], o["zone"])', 'key=lambda o: quote_shipping(o["zone"], o["weight_kg"])'),
    ],
    "shipkit/promotions.py": [
        ("from .pricing import calc_shipping", "from .pricing import quote_shipping"),
        ("    cost = calc_shipping(weight_kg, zone, express)",
         '    cost = quote_shipping(zone, weight_kg, service="express" if express else "standard")'),
        ("    return calc_shipping(weight_kg, zone) > flat", "    return quote_shipping(zone, weight_kg) > flat"),
    ],
    "shipkit/marketplace.py": [
        ("from .pricing import calc_shipping", "from .pricing import quote_shipping"),
        ("    pricer = staticmethod(calc_shipping)\n", ""),
        ("        return round(self.pricer(weight_kg, zone, express) + self.handling_fee, 2)",
         "        return round(self.pricer(weight_kg, zone, express) + self.handling_fee, 2)\n\n"
         "    @staticmethod\n    def pricer(weight_kg, zone, express=False):\n"
         '        return quote_shipping(zone, weight_kg, service="express" if express else "standard")'),
    ],
    "shipkit/estimates.py": [
        ("from .pricing import calc_shipping", "from .pricing import quote_shipping"),
        ('    "fast": lambda w, z: calc_shipping(w, z, express=True),\n    "cheap": lambda w, z: calc_shipping(w, z),',
         '    "fast": lambda w, z: quote_shipping(z, w, service="express"),\n    "cheap": lambda w, z: quote_shipping(z, w),'),
    ],
    "shipkit/api.py": [
        ("from .pricing import calc_shipping", "from .pricing import quote_shipping"),
        ("        price = calc_shipping(**body)",
         "        unknown = set(body) - {\"weight_kg\", \"zone\", \"express\"}\n"
         "        if unknown:\n            raise TypeError(f\"unexpected field(s): {', '.join(sorted(unknown))}\")\n"
         "        service = \"express\" if body.get(\"express\", False) else \"standard\"\n"
         "        price = quote_shipping(body[\"zone\"], body[\"weight_kg\"], service=service)"),
        ("    except (TypeError, ValueError) as exc:", "    except (KeyError, TypeError, ValueError) as exc:"),
    ],
    "README.md": [
        ("""from shipkit.pricing import calc_shipping

calc_shipping(2.3, "EU")                # standard service
calc_shipping(2.3, "EU", express=True)  # express service
```""", """from shipkit.pricing import quote_shipping

quote_shipping("EU", 2.3)                     # standard service
quote_shipping("EU", 2.3, service="express")  # express service
```

`service` is `"standard"` (default) or `"express"`. The old
`calc_shipping(weight_kg, zone, express=False)` remains as a deprecated alias."""),
        ("(for example `calc_shipping` or\n`calc_shipping_zone`)", "(for example `quote_shipping` or\n`calc_shipping_zone`)"),
    ],
    "tests/test_pricing.py": [
        ("from shipkit.pricing import calc_shipping", "from shipkit.pricing import quote_shipping"),
        ('calc_shipping(1.0, "DOMESTIC")', 'quote_shipping("DOMESTIC", 1.0)'),
        ('calc_shipping(1.01, "EU"), calc_shipping(1.5, "EU")', 'quote_shipping("EU", 1.01), quote_shipping("EU", 1.5)'),
        ('calc_shipping(2, "EU", express=True)', 'quote_shipping("EU", 2, service="express")'),
        ('            calc_shipping(1, "MARS")', '            quote_shipping("MARS", 1)'),
    ],
    "tests/test_integration.py": [
        ("from shipkit.pricing import calc_shipping", "from shipkit.pricing import quote_shipping"),
        ('calc_shipping(2.2, "EU", True)', 'quote_shipping("EU", 2.2, service="express")'),
        ('calc_shipping(0.3, "DOMESTIC")', 'quote_shipping("DOMESTIC", 0.3)'),
        ('calc_shipping(2.5, "NORDIC")', 'quote_shipping("NORDIC", 2.5)'),
    ],
}


def main():
    shutil.rmtree(ORA, ignore_errors=True)
    for rel, pairs in EDITS.items():
        text = (FIX / rel).read_text()
        for old, new in pairs:
            assert text.count(old) == 1, (rel, old)
            text = text.replace(old, new)
        out = ORA / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text)


if __name__ == "__main__":
    main()

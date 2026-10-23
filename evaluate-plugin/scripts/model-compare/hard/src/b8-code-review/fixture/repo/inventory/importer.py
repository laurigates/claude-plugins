import csv
import logging
from decimal import Decimal, InvalidOperation

log = logging.getLogger(__name__)


class ImportFailed(Exception):
    pass


def parse_row(row):
    try:
        price = Decimal(row["price"])
    except InvalidOperation:
        raise ValueError(f"bad price {row['price']!r}") from None
    return {"sku": row["sku"].strip().upper(), "name": row["name"].strip(), "price": price}


def import_csv(path):
    """Parse a product CSV. Any malformed line aborts the whole import.
    Blank lines (e.g. a trailing newline from spreadsheet exports) are ignored."""
    records = []
    with open(path, newline="", encoding="utf-8") as fh:
        for lineno, row in enumerate(csv.DictReader(fh), start=2):
            try:
                if not any((v or "").strip() for v in row.values()):
                    continue
                records.append(parse_row(row))
            except (ValueError, KeyError):
                log.debug("skipping unparseable line %d", lineno)
                continue
    return records

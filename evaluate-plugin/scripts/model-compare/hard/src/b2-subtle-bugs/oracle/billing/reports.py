from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

HELSINKI = ZoneInfo("Europe/Helsinki")


def _day_bounds(day, tz):
    """UTC [start, end) of the local calendar day ``day`` in ``tz``."""
    nxt = day + timedelta(days=1)
    start = datetime(day.year, day.month, day.day, tzinfo=tz).astimezone(timezone.utc)
    end = datetime(nxt.year, nxt.month, nxt.day, tzinfo=tz).astimezone(timezone.utc)
    return start, end


def daily_totals(ledger, day: date, tz=HELSINKI) -> int:
    """Net amount in cents booked on local calendar date ``day`` in ``tz``.

    Net means charges minus refunds: a refund is booked on the day it happens
    and reduces that day's total (a charge fully refunded on the same day nets
    to 0). An entry belongs to the day whose local midnight is at or before its
    timestamp and whose next local midnight is after it.
    """
    start, end = _day_bounds(day, tz)
    return sum(e.signed_amount for e in ledger.entries if start <= e.at < end)


def daily_totals_range(ledger, first: date, last: date, tz=HELSINKI) -> dict:
    """{date: net cents} for every local date from ``first`` to ``last``
    inclusive (days without entries map to 0), same rules as daily_totals."""
    if last < first:
        raise ValueError("last must not be before first")
    days = (last - first).days + 1
    out = {first + timedelta(days=i): 0 for i in range(days)}
    for entry in ledger.entries:
        local_day = entry.at.astimezone(tz).date()
        if local_day in out:
            out[local_day] += entry.signed_amount
    return out

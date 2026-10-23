import threading, time
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

gwmod = load("billing.gateway")
ledger_mod = load("billing.ledger")
charges = load("billing.charges")
reports = load("billing.reports")
HEL = ZoneInfo("Europe/Helsinki")
UTC = timezone.utc
T = datetime(2026, 5, 4, 10, 0, tzinfo=UTC)
REG = 0.5   # weight of regression (already-correct behaviour) cases
try:
    charges.BACKOFF_SECONDS = 0
except Exception:
    pass


class GW:
    """Gateway that dedupes on key; `timeouts` upcoming calls capture then time out."""
    def __init__(self, timeouts=0, latency=0.0, decline=False):
        self.captures, self.calls = {}, []
        self.timeouts, self.latency, self.decline = timeouts, latency, decline
        self.lock = threading.Lock()
        self.n = 0
    def charge(self, customer_id, amount_cents, idempotency_key):
        time.sleep(self.latency)
        with self.lock:
            self.calls.append(idempotency_key)
            if self.decline:
                raise gwmod.GatewayDeclined("no")
            if idempotency_key not in self.captures:
                self.n += 1
                self.captures[idempotency_key] = f"cap{self.n}"
            ref = self.captures[idempotency_key]
            if self.timeouts:
                self.timeouts -= 1
                raise gwmod.GatewayTimeout(idempotency_key)
            return ref


def ch(lg, gw, key="k1", cust="c1", amt=500, now=T):
    return charges.charge(lg, gw, customer_id=cust, amount_cents=amt, idempotency_key=key, now=now)


# ---------------- idempotency
def c_single():
    lg, gw = ledger_mod.Ledger(), GW()
    e = ch(lg, gw)
    return len(lg.entries) == 1 and e.gateway_ref == "cap1" and len(gw.captures) == 1
case("single charge", c_single, weight=REG)
def c_seq_retry():
    lg, gw = ledger_mod.Ledger(), GW()
    a, b = ch(lg, gw), ch(lg, gw)
    return a == b and len(lg.entries) == 1 and len(gw.captures) == 1
case("sequential client retry returns first entry", c_seq_retry, weight=REG)
def c_timeout_after_capture():
    lg, gw = ledger_mod.Ledger(), GW(timeouts=1)
    e = ch(lg, gw)
    return len(gw.captures) == 1 and len(lg.entries) == 1 and e.gateway_ref == "cap1"
case("timeout after capture: one capture", c_timeout_after_capture)
def c_two_timeouts():
    lg, gw = ledger_mod.Ledger(), GW(timeouts=2)
    ch(lg, gw)
    return len(gw.captures) == 1 and len(lg.entries) == 1 and len(gw.calls) == 3
case("two timeouts then success: one capture, three calls", c_two_timeouts)
def c_gateway_key():
    lg, gw = ledger_mod.Ledger(), GW(timeouts=1)
    ch(lg, gw, key="order-7731")
    return set(gw.calls) == {"order-7731"}
case("gateway always receives the client's key", c_gateway_key)
def c_all_timeout_then_client_retry():
    lg, gw = ledger_mod.Ledger(), GW(timeouts=3)
    try:
        ch(lg, gw)
        return False
    except gwmod.GatewayTimeout:
        pass
    if lg.entries:
        return False
    e = ch(lg, gw)
    return len(gw.captures) == 1 and e.gateway_ref == "cap1" and len(lg.entries) == 1
case("all attempts time out, client retries: one capture", c_all_timeout_then_client_retry)
def c_declined():
    lg, gw = ledger_mod.Ledger(), GW(decline=True)
    try:
        ch(lg, gw)
    except gwmod.GatewayDeclined:
        return lg.entries == [] and len(gw.calls) == 1
    return False
case("declined propagates, nothing recorded", c_declined, weight=REG)
def c_conflict():
    lg, gw = ledger_mod.Ledger(), GW()
    ch(lg, gw)
    try:
        ch(lg, gw, amt=999)
    except charges.IdempotencyConflict:
        return len(gw.captures) == 1
    return False
case("key reuse with other amount -> IdempotencyConflict", c_conflict, weight=REG)
def run_threads(n, target):
    out, errs = [None] * n, []
    bar = threading.Barrier(n)
    def go(i):
        try:
            bar.wait()
            out[i] = target(i)
        except BaseException as e:
            errs.append(e)
    ts = [threading.Thread(target=go, args=(i,), daemon=True) for i in range(n)]
    t0 = time.monotonic()
    [t.start() for t in ts]
    [t.join(8) for t in ts]
    return out, errs, time.monotonic() - t0
def c_concurrent2():
    lg, gw = ledger_mod.Ledger(), GW(latency=0.2)
    out, errs, _ = run_threads(2, lambda i: ch(lg, gw, key="dbl"))
    return not errs and len(lg.entries) == 1 and out[0] == out[1] and len(gw.captures) == 1
case("double submit (2 concurrent, same key): one entry", c_concurrent2)
def c_concurrent8_timeouts():
    lg, gw = ledger_mod.Ledger(), GW(latency=0.05, timeouts=2)
    out, errs, _ = run_threads(8, lambda i: ch(lg, gw, key="burst", amt=1200))
    return not errs and len(lg.entries) == 1 and len({o.id for o in out}) == 1 and len(gw.captures) == 1
case("8 concurrent retries with timeouts: one entry", c_concurrent8_timeouts)
def c_concurrent_conflict():
    lg, gw = ledger_mod.Ledger(), GW(latency=0.2)
    out, errs, _ = run_threads(2, lambda i: ch(lg, gw, key="cc", amt=100 + i))
    return len(lg.entries) == 1 and len(errs) == 1 and isinstance(errs[0], charges.IdempotencyConflict)
case("concurrent same key, different amount: one entry + conflict", c_concurrent_conflict)
def c_parallel_keys():
    lg, gw = ledger_mod.Ledger(), GW(latency=0.3)
    out, errs, el = run_threads(6, lambda i: ch(lg, gw, key=f"p{i}", cust=f"c{i}"))
    return not errs and len(lg.entries) == 6 and el < 1.2
case("different keys are not serialized", c_parallel_keys, weight=REG)

# ---------------- DST daily totals
def at_local(y, mo, d, h, mi, fold=0):
    return datetime(y, mo, d, h, mi, fold=fold, tzinfo=HEL).astimezone(UTC)
def L(entries):
    lg = ledger_mod.Ledger()
    for i, (when, amt) in enumerate(entries):
        kind = "charge" if amt > 0 else "refund"
        lg.record(customer_id="c", kind=kind, amount_cents=abs(amt), at=when,
                  idempotency_key=f"x{i}", gateway_ref=f"r{i}")
    return lg
def spring():
    return L([(at_local(2026, 3, 28, 23, 30), 1), (at_local(2026, 3, 29, 0, 30), 10),
              (at_local(2026, 3, 29, 12, 0), 100), (at_local(2026, 3, 29, 23, 30), 1000),
              (at_local(2026, 3, 30, 0, 30), 10000), (at_local(2026, 3, 30, 23, 59), 100000)])
def fall(y=2025, d=26):
    return L([(at_local(y, 10, d - 1, 23, 30), 1), (at_local(y, 10, d, 0, 30), 10),
              (at_local(y, 10, d, 3, 30, fold=0), 100), (at_local(y, 10, d, 3, 30, fold=1), 1000),
              (at_local(y, 10, d, 23, 30), 10000), (at_local(y, 10, d + 1, 0, 30), 100000)])
case("normal day total", lambda: reports.daily_totals(L([(datetime(2026, 5, 4, 21, 30, tzinfo=UTC), 5), (datetime(2026, 5, 4, 20, 59, tzinfo=UTC), 7)]), date(2026, 5, 4)) == 7, weight=REG)
case("spring-forward day 2026-03-29", lambda: reports.daily_totals(spring(), date(2026, 3, 29)) == 1110)
case("day before spring-forward", lambda: reports.daily_totals(spring(), date(2026, 3, 28)) == 1, weight=REG)
case("day after spring-forward", lambda: reports.daily_totals(spring(), date(2026, 3, 30)) == 110000, weight=REG)
case("fall-back day 2025-10-26 (incl. repeated hour)", lambda: reports.daily_totals(fall(), date(2025, 10, 26)) == 11110)
case("fall-back day 2026-10-25", lambda: reports.daily_totals(fall(2026, 25), date(2026, 10, 25)) == 11110)
case("day after fall-back", lambda: reports.daily_totals(fall(), date(2025, 10, 27)) == 100000, weight=REG)
case("local midnight belongs to new day", lambda: reports.daily_totals(L([(at_local(2026, 3, 30, 0, 0), 3), (at_local(2026, 3, 29, 0, 0), 4)]), date(2026, 3, 29)) == 4)
case("explicit tz argument honoured", lambda: reports.daily_totals(L([(datetime(2026, 3, 29, 23, 30, tzinfo=UTC), 9), (datetime(2026, 3, 29, 0, 30, tzinfo=UTC), 2)]), date(2026, 3, 29), tz=UTC) == 11, weight=REG)
def c_range_spring():
    got = reports.daily_totals_range(spring(), date(2026, 3, 27), date(2026, 3, 31))
    return got == {date(2026, 3, 27): 0, date(2026, 3, 28): 1, date(2026, 3, 29): 1110, date(2026, 3, 30): 110000, date(2026, 3, 31): 0}
case("range across spring-forward", c_range_spring)
def c_range_fall():
    got = reports.daily_totals_range(fall(), date(2025, 10, 25), date(2025, 10, 28))
    return got == {date(2025, 10, 25): 1, date(2025, 10, 26): 11110, date(2025, 10, 27): 100000, date(2025, 10, 28): 0}
case("range across fall-back", c_range_fall)
def c_range_week_sum():
    es = []
    for d in range(23, 31):
        for h in (0, 1, 2, 3, 22, 23):
            es.append((at_local(2026, 3, d, h, 15), d * 10 + h))
    lg = L(es)
    got = reports.daily_totals_range(lg, date(2026, 3, 23), date(2026, 3, 30))
    return sum(got.values()) == sum(a for _, a in es) and all(got[date(2026, 3, d)] == sum(d * 10 + h for h in (0, 1, 2, 3, 22, 23)) for d in range(23, 31))
case("range week sum reconciles (per-day exact)", c_range_week_sum)
def c_range_matches_daily():
    lg = fall(2026, 25)
    got = reports.daily_totals_range(lg, date(2026, 10, 20), date(2026, 10, 30))
    return all(got[d] == reports.daily_totals(lg, d) for d in got) and len(got) == 11
case("range agrees with daily_totals", c_range_matches_daily)
case("range normal week", lambda: reports.daily_totals_range(L([(datetime(2026, 5, 4, 21, 30, tzinfo=UTC), 5), (datetime(2026, 5, 4, 20, 59, tzinfo=UTC), 7)]), date(2026, 5, 4), date(2026, 5, 5)) == {date(2026, 5, 4): 7, date(2026, 5, 5): 5}, weight=REG)

# ---------------- red herring: refunds are netted (documented)
def c_refund_same_day():
    lg, gw = ledger_mod.Ledger(), GW()
    e = ch(lg, gw, amt=5000, now=datetime(2026, 5, 4, 9, 0, tzinfo=UTC))
    charges.refund(lg, charge_entry=e, now=datetime(2026, 5, 4, 13, 0, tzinfo=UTC))
    return reports.daily_totals(lg, date(2026, 5, 4)) == 0
case("same-day full refund nets to 0 (not a bug)", c_refund_same_day)
def c_refund_other_day():
    lg, gw = ledger_mod.Ledger(), GW()
    e = ch(lg, gw, amt=5000, now=datetime(2026, 5, 4, 9, 0, tzinfo=UTC))
    charges.refund(lg, charge_entry=e, amount_cents=2000, now=datetime(2026, 5, 6, 9, 0, tzinfo=UTC))
    r = reports.daily_totals_range(lg, date(2026, 5, 4), date(2026, 5, 6))
    return r == {date(2026, 5, 4): 5000, date(2026, 5, 5): 0, date(2026, 5, 6): -2000}
case("refund booked on its own day, negative (not a bug)", c_refund_other_day)
done()

"""Generate the b3 CI log, the hidden truth (embedded in check_body.py) and the oracle.

Every failing test is (node_id, cause_letter, outcome, failure_block, summary_msg).
Blocks are written to be diagnosable from the log alone: cascades carry their
evidence in captured logs / chained exceptions / parametrize source lines.
"""
import json
import random
import textwrap
from pathlib import Path

HERE = Path(__file__).resolve().parent
SP = "/builds/shop/.venv/lib/python3.13/site-packages"


def blk(s):
    return textwrap.dedent(s).strip("\n")


DB_PERSIST_WARN = "WARNING  shop.testing.factories:factories.py:88 could not persist Order: (sqlite3.OperationalError) no such column: orders.currency"

T = []  # (id, letter, outcome, block, summary)


def add(nid, letter, outcome, block, summary):
    T.append((nid, letter, outcome, blk(block), summary))


# ----------------------------------------------------------------- A: migration
add("tests/orders/test_checkout.py::test_create_order_persists", "A", "FAILED", f"""
    db_session = <sqlalchemy.orm.session.Session object at 0x7f3a2c1e5d10>, cart = <Cart 3 lines>

        def test_create_order_persists(db_session, cart):
    >       order = checkout.place_order(db_session, cart, customer_id=42)

    tests/orders/test_checkout.py:31:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    shop/orders/checkout.py:58: in place_order
        db.flush()
    {SP}/sqlalchemy/orm/session.py:4345: in flush
        self._flush(objects)
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    E       sqlalchemy.exc.OperationalError: (sqlite3.OperationalError) table orders has no column named currency
    E       [SQL: INSERT INTO orders (customer_id, total_cents, currency, status, created_at) VALUES (?, ?, ?, ?, ?)]
    E       [parameters: (42, 4590, 'EUR', 'pending', '2026-03-15 10:00:00.000000')]

    {SP}/sqlalchemy/engine/default.py:942: OperationalError
""", "sqlalchemy.exc.OperationalError: (sqlite3.OperationalError) table orders has no column named currency")

add("tests/orders/test_checkout.py::test_order_total_with_vat", "A", "FAILED", f"""
    order_factory = <function order_factory.<locals>.make at 0x7f3a2c0b1e40>

        def test_order_total_with_vat(order_factory):
            order = order_factory(lines=[("MUG", 2, 1200)], country="FI")
    >       assert vat.total_with_vat(order.total_cents, order.currency) == 3012
    E       AttributeError: 'NoneType' object has no attribute 'total_cents'

    tests/orders/test_checkout.py:47: AttributeError
    ------------------------------ Captured log call -------------------------------
    {DB_PERSIST_WARN}
""", "AttributeError: 'NoneType' object has no attribute 'total_cents'")

add("tests/orders/test_history.py::test_history_lists_recent", "A", "FAILED", f"""
    client = <FlaskClient <Flask 'shop'>>, seeded_orders = 5

        def test_history_lists_recent(client, seeded_orders):
            rows = history.recent_orders(customer_id=7, limit=3)
    >       assert [serializers.order_row(r)["total"] for r in rows] == ["12.00", "8.50", "3.10"]

    tests/orders/test_history.py:22:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    row = {{'id': 17, 'customer_id': 7, 'total_cents': 1200, 'status': 'paid', 'created_at': '2026-03-14 09:12:00'}}

        def order_row(row):
            return {{
                "id": row["id"],
    >           "total": money.format_cents(row["total_cents"], row["currency"]),
                "status": row["status"],
            }}
    E       KeyError: 'currency'

    shop/orders/serializers.py:14: KeyError
    ------------------------------ Captured log setup ------------------------------
    INFO     shop.testing.seed:seed.py:31 seeded 5 orders via raw SQL (legacy column set)
""", "KeyError: 'currency'")

add("tests/orders/test_history.py::test_history_pagination", "A", "FAILED", f"""
    db_session = <sqlalchemy.orm.session.Session object at 0x7f3a2bf9a3d0>

        def test_history_pagination(db_session):
            for i in range(25):
    >           db_session.add(Order(customer_id=7, total_cents=100 + i, currency="EUR"))
                db_session.commit()

    tests/orders/test_history.py:40:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    E       sqlalchemy.exc.OperationalError: (sqlite3.OperationalError) table orders has no column named currency

    {SP}/sqlalchemy/engine/default.py:942: OperationalError
""", "sqlalchemy.exc.OperationalError: (sqlite3.OperationalError) table orders has no colu...")

for name in ("test_invoice_currency_symbol", "test_invoice_rounding"):
    add(f"tests/invoices/test_pdf.py::{name}", "A", "ERROR", f"""
        ______________ ERROR at setup of {name} _______________

        order_factory = <function order_factory.<locals>.make at 0x7f3a2bd02f20>

            @pytest.fixture
            def invoice(order_factory):
        >       order = order_factory(lines=[("LAMP", 1, 4990)], persist=True, strict=True)

        tests/invoices/conftest.py:12:
        _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
        shop/testing/factories.py:84: in make
            session.commit()
        E       sqlalchemy.exc.OperationalError: (sqlite3.OperationalError) no such column: orders.currency

        {SP}/sqlalchemy/engine/default.py:942: OperationalError
    """, "sqlalchemy.exc.OperationalError: (sqlite3.OperationalError) no such column: orders.currency")

add("tests/reports/test_monthly.py::test_monthly_revenue_by_currency", "A", "FAILED", f"""
    order_factory = <function order_factory.<locals>.make at 0x7f3a2b8c9a80>

        def test_monthly_revenue_by_currency(order_factory):
            for cur in ("EUR", "SEK", "EUR"):
                order_factory(lines=[("MUG", 1, 1000)], currency=cur)
            rows = monthly.revenue_by_currency(2026, 3)
    >       assert sum(r.count for r in rows) == 3
    E       assert 0 == 3
    E        +  where 0 = sum(<generator object test_monthly_revenue_by_currency.<locals>.<genexpr> at 0x7f3a2b8d1c40>)

    tests/reports/test_monthly.py:19: AssertionError
    ------------------------------ Captured log call -------------------------------
    {DB_PERSIST_WARN}
    {DB_PERSIST_WARN}
    {DB_PERSIST_WARN}
""", "assert 0 == 3")

add("tests/api/test_orders_api.py::test_get_order_returns_currency", "A", "FAILED", f"""
    client = <FlaskClient <Flask 'shop'>>, api_token = 'tok_test_7f2a'

        def test_get_order_returns_currency(client, api_token):
            resp = client.get("/api/orders/17", headers={{"Authorization": f"Bearer {{api_token}}"}})
    >       assert resp.status_code == 200
    E       assert 500 == 200
    E        +  where 500 = <WrapperTestResponse streamed [500 INTERNAL SERVER ERROR]>.status_code

    tests/api/test_orders_api.py:28: AssertionError
    ------------------------------ Captured log call -------------------------------
    ERROR    shop.api:errors.py:41 unhandled exception on GET /api/orders/17
    Traceback (most recent call last):
      File "/builds/shop/shop/api/orders.py", line 33, in get_order
        order = db.session.get(Order, order_id)
      ...
    sqlalchemy.exc.OperationalError: (sqlite3.OperationalError) no such column: orders.currency
""", "assert 500 == 200")

# ----------------------------------------------------------------- B: TZ=UTC
add("tests/reports/test_daily.py::test_daily_summary_header[fi]", "B", "FAILED", """
    lang = 'fi', frozen = '2026-03-15T00:30:00+02:00'

        @pytest.mark.parametrize("lang,frozen", [
            ("fi", "2026-03-15T00:30:00+02:00"),
            ("en", "2026-03-15T12:00:00+02:00"),
        ])
        def test_daily_summary_header(lang, frozen):
            with freeze_time(frozen):
                header = daily.summary_header(lang=lang)
    >       assert header == expected_header(lang, date(2026, 3, 15))
    E       AssertionError: assert 'Päivän yhteenveto – 14.3.2026' == 'Päivän yhteenveto – 15.3.2026'
    E         - Päivän yhteenveto – 15.3.2026
    E         ?                     ^^
    E         + Päivän yhteenveto – 14.3.2026
    E         ?                     ^^

    tests/reports/test_daily.py:44: AssertionError
""", "AssertionError: assert 'Päivän yhteenveto – 14.3.2026' == 'Päivän yhteenveto – 15.3.2026'")

add("tests/reports/test_daily.py::test_cutoff_is_local_midnight", "B", "FAILED", """
        def test_cutoff_is_local_midnight():
            with freeze_time("2026-03-15T10:00:00+02:00"):
                start, end = daily.day_window()
    >       assert start == datetime(2026, 3, 15, 0, 0)
    E       assert datetime.datetime(2026, 3, 14, 22, 0) == datetime.datetime(2026, 3, 15, 0, 0)
    E        +  where datetime.datetime(2026, 3, 15, 0, 0) = datetime(2026, 3, 15, 0, 0)

    tests/reports/test_daily.py:61: AssertionError
""", "assert datetime.datetime(2026, 3, 14, 22, 0) == datetime.datetime(2026, 3, 15, 0, 0)")

add("tests/shipping/test_slots.py::test_same_day_cutoff", "B", "FAILED", """
        def test_same_day_cutoff():
            # 14:30 Helsinki is after the 14:00 same-day cutoff
            with freeze_time("2026-03-16T14:30:00+02:00"):
                slot = slots.next_slot(zone="FI-00100")
    >       assert slot.kind == "next_day"
    E       AssertionError: assert 'same_day' == 'next_day'
    E         - next_day
    E         + same_day

    tests/shipping/test_slots.py:23: AssertionError
    ------------------------------ Captured log call -------------------------------
    DEBUG    shop.shipping.slots:slots.py:40 now=2026-03-16 12:30:00 cutoff=14:00 -> same_day
""", "AssertionError: assert 'same_day' == 'next_day'")

add("tests/shipping/test_slots.py::test_weekend_no_delivery", "B", "FAILED", """
        def test_weekend_no_delivery():
            # Saturday 00:20 local -> earliest delivery is Monday
            with freeze_time("2026-03-21T00:20:00+02:00"):
                slot = slots.next_slot(zone="FI-33100")
    >       assert slot.date == date(2026, 3, 23)
    E       AssertionError: assert datetime.date(2026, 3, 20) == datetime.date(2026, 3, 23)

    tests/shipping/test_slots.py:37: AssertionError
    ------------------------------ Captured log call -------------------------------
    DEBUG    shop.shipping.slots:slots.py:40 now=2026-03-20 22:20:00 cutoff=14:00 -> next_day
""", "AssertionError: assert datetime.date(2026, 3, 20) == datetime.date(2026, 3, 23)")

add("tests/notifications/test_reminders.py::test_reminder_sent_at_9_local", "B", "FAILED", """
        def test_reminder_sent_at_9_local():
            job = reminders.schedule_cart_reminder(cart_id=5, day=date(2026, 3, 17))
    >       assert job.run_at.strftime("%H:%M") == "09:00"
    E       AssertionError: assert '07:00' == '09:00'
    E         - 09:00
    E         + 07:00

    tests/notifications/test_reminders.py:15: AssertionError
""", "AssertionError: assert '07:00' == '09:00'")

add("tests/billing/test_due_dates.py::test_due_date_end_of_month", "B", "FAILED", """
        def test_due_date_end_of_month():
            with freeze_time("2026-03-31T01:15:00+03:00"):
                due = due_dates.invoice_due_date(terms_days=14)
    >       assert due == date(2026, 4, 14)
    E       AssertionError: assert datetime.date(2026, 4, 13) == datetime.date(2026, 4, 14)

    tests/billing/test_due_dates.py:12: AssertionError
""", "AssertionError: assert datetime.date(2026, 4, 13) == datetime.date(2026, 4, 14)")

add("tests/billing/test_due_dates.py::test_due_date_ignores_dst", "B", "FAILED", """
        def test_due_date_ignores_dst():
            # issued on the night clocks go forward
            with freeze_time("2026-03-29T01:30:00+02:00"):
                inv = due_dates.issue(customer_id=3)
    >       assert inv.issued_on == date(2026, 3, 29)
    E       AssertionError: assert datetime.date(2026, 3, 28) == datetime.date(2026, 3, 29)

    tests/billing/test_due_dates.py:27: AssertionError
""", "AssertionError: assert datetime.date(2026, 3, 28) == datetime.date(2026, 3, 29)")

# ----------------------------------------------------------------- C: payfast 4.0
PF_CAUSE = f"""
    {SP}/payfast_sdk/client.py:212: TypeError

    The above exception was the direct cause of the following exception:
"""
add("tests/payments/test_charge.py::test_charge_success", "C", "FAILED", f"""
    pf_client = <payfast_sdk.client.Client object at 0x7f3a2a9e1b50>

        def test_charge_success(pf_client):
    >       result = gateway.charge(pf_client, order_id=17, amount_cents=4590, currency="EUR")

    tests/payments/test_charge.py:18:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    shop/payments/gateway.py:47: in charge
        return _with_retries(lambda: client.charge(amount=amount_cents, currency=currency, reference=str(order_id)))
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

    fn = <function charge.<locals>.<lambda> at 0x7f3a2a9f04a0>

        def _with_retries(fn, attempts=3):
            last = None
            for _ in range(attempts):
                try:
                    return fn()
                except Exception as exc:  # network errors are common
                    last = exc
    >       raise PaymentError(f"charge failed after {{attempts}} attempts") from last
    E       shop.payments.errors.PaymentError: charge failed after 3 attempts

    shop/payments/gateway.py:31: PaymentError
    ------------------------------ Captured log call -------------------------------
    WARNING  shop.payments.gateway:gateway.py:29 attempt 1 failed: Client.charge() got an unexpected keyword argument 'amount'
    WARNING  shop.payments.gateway:gateway.py:29 attempt 2 failed: Client.charge() got an unexpected keyword argument 'amount'
    WARNING  shop.payments.gateway:gateway.py:29 attempt 3 failed: Client.charge() got an unexpected keyword argument 'amount'
""", "shop.payments.errors.PaymentError: charge failed after 3 attempts")

add("tests/payments/test_charge.py::test_charge_declined", "C", "FAILED", f"""
    pf_client = <payfast_sdk.client.Client object at 0x7f3a2a9e1b50>

        def test_charge_declined(pf_client):
            pf_client.force_decline("insufficient_funds")
            with pytest.raises(PaymentDeclined):
    >           gateway.charge(pf_client, order_id=18, amount_cents=999, currency="EUR")

    tests/payments/test_charge.py:29:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    shop/payments/gateway.py:47: in charge
        return _with_retries(lambda: client.charge(amount=amount_cents, currency=currency, reference=str(order_id)))
    shop/payments/gateway.py:25: in _with_retries
        return fn()
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    E   TypeError: Client.charge() got an unexpected keyword argument 'amount'
{textwrap.indent(blk(PF_CAUSE), "    ")}

    E       shop.payments.errors.PaymentError: charge failed after 3 attempts

    shop/payments/gateway.py:31: PaymentError
""", "shop.payments.errors.PaymentError: charge failed after 3 attempts")

add("tests/payments/test_charge.py::test_charge_status_captured", "C", "FAILED", """
    pf_client = <payfast_sdk.client.Client object at 0x7f3a2a9e1b50>

        def test_charge_status_captured(pf_client):
            res = pf_client.charge_raw(order_ref="19", minor_units=100)
    >       assert res.status == "captured"
    E       AssertionError: assert <PaymentStatus.CAPTURED: 'captured'> == 'captured'
    E        +  where <PaymentStatus.CAPTURED: 'captured'> = PaymentResult(id='pf_9a1', status=<PaymentStatus.CAPTURED: 'captured'>).status

    tests/payments/test_charge.py:41: AssertionError
""", "AssertionError: assert <PaymentStatus.CAPTURED: 'captured'> == 'captured'")

add("tests/payments/test_refund.py::test_refund_full", "C", "FAILED", f"""
    pf_client = <payfast_sdk.client.Client object at 0x7f3a2a9e1b50>, paid_order = <Order 21 paid>

        def test_refund_full(pf_client, paid_order):
    >       refunds.refund(pf_client, paid_order)

    tests/payments/test_refund.py:15:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    shop/payments/refunds.py:22: in refund
        return client.refund(payment_id=order.payment_id, amount=order.total_cents)
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    E       TypeError: Client.refund() got an unexpected keyword argument 'amount'

    {SP}/payfast_sdk/client.py:248: TypeError
""", "TypeError: Client.refund() got an unexpected keyword argument 'amount'")

add("tests/payments/test_gateway_parse.py::test_parse_settlement", "C", "FAILED", f"""
    pf_client = <payfast_sdk.client.Client object at 0x7f3a2a9e1b50>

        def test_parse_settlement(pf_client):
            resp = pf_client.get_settlement("2026-03-14")
    >       s = gateway.parse_settlement(resp.json())

    tests/payments/test_gateway_parse.py:11:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    payload = {{'currency_code': 'EUR', 'date': '2026-03-14', 'gross_minor': 125000, 'net_minor': 121250, 'schema': 'v4'}}

        def parse_settlement(payload):
            return Settlement(
                day=payload["date"],
                gross_cents=payload["gross"],
    >           currency=payload["currency"],
            )
    E       KeyError: 'currency'

    shop/payments/gateway.py:88: KeyError
""", "KeyError: 'currency'")

add("tests/api/test_checkout_api.py::test_checkout_pays_order", "C", "FAILED", """
    client = <FlaskClient <Flask 'shop'>>, cart_in_session = <Cart 2 lines>

        def test_checkout_pays_order(client, cart_in_session):
            resp = client.post("/api/checkout", json={"payment_method": "card"})
    >       assert resp.status_code == 201
    E       assert 502 == 201
    E        +  where 502 = <WrapperTestResponse streamed [502 BAD GATEWAY]>.status_code

    tests/api/test_checkout_api.py:19: AssertionError
    ------------------------------ Captured log call -------------------------------
    WARNING  shop.payments.gateway:gateway.py:29 attempt 1 failed: Client.charge() got an unexpected keyword argument 'amount'
    WARNING  shop.payments.gateway:gateway.py:29 attempt 2 failed: Client.charge() got an unexpected keyword argument 'amount'
    WARNING  shop.payments.gateway:gateway.py:29 attempt 3 failed: Client.charge() got an unexpected keyword argument 'amount'
    ERROR    shop.api.checkout:checkout.py:52 payment provider error: charge failed after 3 attempts
""", "assert 502 == 201")

add("tests/payments/test_webhook_sig.py::test_signature_verification", "C", "FAILED", """
        def test_signature_verification():
            body = b'{"event":"payment.captured","id":"pf_77"}'
            sig = sign_for_tests(body, secret="whsec_test")
    >       assert webhooks.verify(body, sig, secret="whsec_test")

    tests/payments/test_webhook_sig.py:9:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    shop/payments/webhooks.py:12: in verify
        return payfast_sdk.verify_signature(body, signature, secret)
    E       AttributeError: module 'payfast_sdk' has no attribute 'verify_signature'

    shop/payments/webhooks.py:12: AttributeError
""", "AttributeError: module 'payfast_sdk' has no attribute 'verify_signature'")

# ----------------------------------------------------------------- D: port collision
add("tests/integrations/test_erp_sync.py::test_push_order", "D", "FAILED", f"""
    mock_api = <MockServer http://127.0.0.1:8089 (not running)>

        def test_push_order(mock_api):
            mock_api.expect("POST", "/orders", status=201)
    >       erp.push_order(order_id=17, base_url=mock_api.url)

    tests/integrations/test_erp_sync.py:20:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    {SP}/requests/adapters.py:700: in send
        raise ConnectionError(e, request=request)
    E       requests.exceptions.ConnectionError: HTTPConnectionPool(host='127.0.0.1', port=8089): Max retries exceeded with url: /orders (Caused by NewConnectionError('<urllib3.connection.HTTPConnection object at 0x7f3a29d3e0d0>: Failed to establish a new connection: [Errno 111] Connection refused'))

    {SP}/requests/adapters.py:700: ConnectionError
    ---------------------------- Captured stderr setup -----------------------------
    Exception in thread mock-api-8089:
    Traceback (most recent call last):
      File "/usr/local/lib/python3.13/threading.py", line 1041, in _bootstrap_inner
        self.run()
      File "/builds/shop/tests/support/mockserver.py", line 37, in run
        self.httpd = HTTPServer(("127.0.0.1", self.port), self.handler)
      File "/usr/local/lib/python3.13/socketserver.py", line 457, in __init__
        self.server_bind()
    OSError: [Errno 98] Address already in use
""", "requests.exceptions.ConnectionError: HTTPConnectionPool(host='127.0.0.1', port=8089): Max retries exceeded with url: /orders ...")

add("tests/integrations/test_erp_sync.py::test_push_retry_on_503", "D", "FAILED", f"""
    mock_api = <MockServer http://127.0.0.1:8089 (not running)>

        def test_push_retry_on_503(mock_api):
            mock_api.expect("POST", "/orders", status=503, times=1).then(status=201)
    >       erp.push_order(order_id=18, base_url=mock_api.url)

    tests/integrations/test_erp_sync.py:31:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    E       requests.exceptions.ConnectionError: HTTPConnectionPool(host='127.0.0.1', port=8089): Max retries exceeded with url: /orders (Caused by NewConnectionError('<urllib3.connection.HTTPConnection object at 0x7f3a29d3f810>: Failed to establish a new connection: [Errno 111] Connection refused'))

    {SP}/requests/adapters.py:700: ConnectionError
""", "requests.exceptions.ConnectionError: HTTPConnectionPool(host='127.0.0.1', port=8089): Max retries exceeded with url: /orders ...")

add("tests/integrations/test_erp_sync.py::test_pull_stock_levels", "D", "FAILED", """
    mock_api = <MockServer http://127.0.0.1:8089 (not running)>

        def test_pull_stock_levels(mock_api):
            mock_api.expect("GET", "/stock/MUG", json={"sku": "MUG", "on_hand": 12})
            level = erp.stock_level("MUG", base_url=mock_api.url)
    >       assert level == 12
    E       assert None == 12

    tests/integrations/test_erp_sync.py:44: AssertionError
    ------------------------------ Captured log call -------------------------------
    WARNING  shop.erp.client:client.py:63 ERP unreachable at http://127.0.0.1:8089 ([Errno 111] Connection refused); using cached stock level (none)
""", "assert None == 12")

for name, nid in (("test_label_purchase", 1), ("test_tracking_lookup", 2)):
    add(f"tests/integrations/test_carrier_api.py::{name}", "D", "ERROR", f"""
        ____________ ERROR at setup of {name} ____________

            @pytest.fixture(scope="module")
            def mock_api():
                server = MockServer(port=8089)
        >       server.start(wait=True)

        tests/integrations/conftest.py:18:
        _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
        tests/support/mockserver.py:37: in start
            self.httpd = HTTPServer(("127.0.0.1", self.port), self.handler)
        /usr/local/lib/python3.13/socketserver.py:457: in __init__
            self.server_bind()
        _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
        E       OSError: [Errno 98] Address already in use

        /usr/local/lib/python3.13/socket.py:236: OSError
    """, "OSError: [Errno 98] Address already in use")

add("tests/webhooks/test_delivery.py::test_retry_backoff[2-2]", "D", "FAILED", """
    receiver_factory = <function receiver_factory.<locals>.make at 0x7f3a29b11f80>

        @pytest.mark.repeat(2)
        def test_retry_backoff(receiver_factory):
    >       rx = receiver_factory(port=8091, fail_first=2)

    tests/webhooks/test_delivery.py:52:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    tests/webhooks/conftest.py:30: in make
        srv = ThreadingHTTPServer(("127.0.0.1", port), handler)
    /usr/local/lib/python3.13/socketserver.py:457: in __init__
        self.server_bind()
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    E       OSError: [Errno 98] Address already in use

    /usr/local/lib/python3.13/socket.py:236: OSError
""", "OSError: [Errno 98] Address already in use")

# ----------------------------------------------------------------- E: flag pollution
add("tests/reports/test_daily.py::test_daily_summary_header[en]", "E", "FAILED", """
    lang = 'en', frozen = '2026-03-15T12:00:00+02:00'

        @pytest.mark.parametrize("lang,frozen", [
            ("fi", "2026-03-15T00:30:00+02:00"),
            ("en", "2026-03-15T12:00:00+02:00"),
        ])
        def test_daily_summary_header(lang, frozen):
            with freeze_time(frozen):
                header = daily.summary_header(lang=lang)
    >       assert header == expected_header(lang, date(2026, 3, 15))
    E       AssertionError: assert 'Daily summary v2 – 15.3.2026' == 'Daily summary – 15.3.2026'
    E         - Daily summary – 15.3.2026
    E         + Daily summary v2 – 15.3.2026
    E         ?               +++

    tests/reports/test_daily.py:44: AssertionError
""", "AssertionError: assert 'Daily summary v2 – 15.3.2026' == 'Daily summary – 15.3.2026'")

add("tests/reports/test_daily.py::test_daily_csv_columns", "E", "FAILED", """
        def test_daily_csv_columns():
            header = daily.csv_header()
    >       assert header == ["date", "sku", "qty", "revenue"]
    E       AssertionError: assert ['date', 'sku', 'qty', 'revenue', 'margin'] == ['date', 'sku', 'qty', 'revenue']
    E         Left contains one more item: 'margin'

    tests/reports/test_daily.py:70: AssertionError
""", "AssertionError: assert ['date', 'sku', 'qty', 'revenue', 'margin'] == ['date', 'sku', 'qty', 'revenue']")

add("tests/reports/test_weekly.py::test_weekly_template", "E", "FAILED", f"""
        def test_weekly_template():
    >       html = weekly.render(week=11, year=2026)

    tests/reports/test_weekly.py:14:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    shop/reports/weekly.py:21: in render
        template = env.get_template(f"reports/weekly{{'_v2' if flags.enabled('reports_v2') else ''}}.html")
    {SP}/jinja2/environment.py:1016: in get_template
        return self._load_template(name, globals)
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    E       jinja2.exceptions.TemplateNotFound: reports/weekly_v2.html

    {SP}/jinja2/loaders.py:204: TemplateNotFound
""", "jinja2.exceptions.TemplateNotFound: reports/weekly_v2.html")

add("tests/reports/test_weekly.py::test_weekly_totals", "E", "FAILED", """
        def test_weekly_totals():
            rows = weekly.totals(week=11, year=2026)
    >       assert set(rows[0]) == {"sku", "qty", "revenue"}
    E       AssertionError: assert {'margin', 'qty', 'revenue', 'sku'} == {'qty', 'revenue', 'sku'}
    E         Extra items in the left set:
    E         'margin'

    tests/reports/test_weekly.py:29: AssertionError
""", "AssertionError: assert {'margin', 'qty', 'revenue', 'sku'} == {'qty', 'revenue', 'sku'}")

add("tests/web/test_dashboard.py::test_dashboard_widgets", "E", "FAILED", """
    client = <FlaskClient <Flask 'shop'>>, staff_login = <User staff@shop.test>

        def test_dashboard_widgets(client, staff_login):
            widgets = dashboard.widgets_for(staff_login)
    >       assert [w.key for w in widgets] == ["orders_today", "low_stock", "revenue_7d"]
    E       AssertionError: assert ['orders_toda...e_7d', 'reports_v2_preview'] == ['orders_toda...', 'revenue_7d']
    E         Left contains one more item: 'reports_v2_preview'

    tests/web/test_dashboard.py:17: AssertionError
""", "AssertionError: assert ['orders_toda...e_7d', 'reports_v2_preview'] == ['orders_toda...', 'revenue_7d']")

add("tests/reports/test_export.py::test_export_filename", "E", "FAILED", """
        def test_export_filename():
            with freeze_time("2026-03-15T09:00:00+02:00"):
                name = export.filename("sales")
    >       assert name == "sales-2026-03-15.csv"
    E       AssertionError: assert 'sales-2026-03-15-v2.csv' == 'sales-2026-03-15.csv'

    tests/reports/test_export.py:11: AssertionError
""", "AssertionError: assert 'sales-2026-03-15-v2.csv' == 'sales-2026-03-15.csv'")

# ----------------------------------------------------------------- F: C locale
ASCII = "UnicodeEncodeError: 'ascii' codec can't encode character '\\xe4' in position {p}: ordinal not in range(128)"
add("tests/exports/test_csv.py::test_export_customer_names", "F", "FAILED", f"""
    tmp_path = PosixPath('/tmp/pytest-of-runner/pytest-0/test_export_customer_names0')

        def test_export_customer_names(tmp_path):
            out = tmp_path / "customers.csv"
    >       csv_export.customers(out, [Customer("Mäkinen", "Liisa")])

    tests/exports/test_csv.py:18:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    shop/exports/csv_export.py:22: in customers
        with open(path, "w", newline="") as fh:
            ...
    E       {ASCII.format(p=1)}

    /usr/local/lib/python3.13/encodings/ascii.py:19: UnicodeEncodeError
""", ASCII.format(p=1))

add("tests/exports/test_csv.py::test_export_semicolon_dialect", "F", "FAILED", f"""
    tmp_path = PosixPath('/tmp/pytest-of-runner/pytest-0/test_export_semicolon_dialect0')

        def test_export_semicolon_dialect(tmp_path):
            out = tmp_path / "orders.csv"
    >       csv_export.orders(out, [("Hämeenlinna", 3)], dialect="excel-fi")

    tests/exports/test_csv.py:33:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    E       {ASCII.format(p=1)}

    /usr/local/lib/python3.13/encodings/ascii.py:19: UnicodeEncodeError
""", ASCII.format(p=1))

add("tests/i18n/test_formatting.py::test_currency_format_fi", "F", "FAILED", """
        def test_currency_format_fi():
    >       assert fmt.money(1234.5, "fi_FI") == "1 234,50 €"

    tests/i18n/test_formatting.py:8:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    shop/i18n/fmt.py:15: in money
        locale.setlocale(locale.LC_MONETARY, f"{loc}.UTF-8")
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    E       locale.Error: unsupported locale setting

    /usr/local/lib/python3.13/locale.py:615: Error
""", "locale.Error: unsupported locale setting")

add("tests/i18n/test_formatting.py::test_sort_collation", "F", "FAILED", """
        def test_sort_collation():
            names = ["Zebra", "école", "Ölander", "apple"]
    >       assert fmt.collate(names, "fr_FR") == ["apple", "école", "Ölander", "Zebra"]
    E       AssertionError: assert ['Zebra', 'apple', 'Ölander', 'école'] == ['apple', 'école', 'Ölander', 'Zebra']
    E         At index 0 diff: 'Zebra' != 'apple'

    tests/i18n/test_formatting.py:21: AssertionError
    ------------------------------ Captured log call -------------------------------
    WARNING  shop.i18n.fmt:fmt.py:40 locale fr_FR.UTF-8 not available, falling back to the process default ('C')
""", "AssertionError: assert ['Zebra', 'apple', 'Ölander', 'école'] == ['apple', 'école', 'Ölander', 'Zebra']")

add("tests/invoices/test_pdf.py::test_invoice_customer_name_unicode", "F", "FAILED", f"""
    tmp_path = PosixPath('/tmp/pytest-of-runner/pytest-0/test_invoice_customer_name_un0')

        def test_invoice_customer_name_unicode(tmp_path):
            draft = Invoice.draft(customer_name="Jääskeläinen Oy", lines=[("LAMP", 1, 4990)])
    >       pdf.write(draft, tmp_path / "inv.txt")

    tests/invoices/test_pdf.py:58:
    _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
    shop/invoices/pdf.py:71: in write
        path.write_text(render_text(invoice))
    E       {ASCII.format(p=1)}

    /usr/local/lib/python3.13/encodings/ascii.py:19: UnicodeEncodeError
""", ASCII.format(p=1))

add("tests/notifications/test_email.py::test_subject_encoding", "F", "FAILED", """
        def test_subject_encoding(capsys):
            email.preview(subject="Tilauksesi on lähetetty", to="a@b.test")
            out = capsys.readouterr().out
    >       assert "Tilauksesi on lähetetty" in out
    E       AssertionError: assert 'Tilauksesi on lähetetty' in 'Subject: Tilauksesi on l\\\\xe4hetetty\\nTo: a@b.test\\n'

    tests/notifications/test_email.py:14: AssertionError
    ------------------------------ Captured log call -------------------------------
    WARNING  shop.notifications.email:email.py:33 stdout encoding is 'ascii' (LANG/LC_ALL unset?); escaping non-ASCII preview output
""", "AssertionError: assert 'Tilauksesi on lähetetty' in 'Subject: Tilauksesi on l\\\\xe4hetetty\\nTo: a@b.test\\n'")

# ----------------------------------------------------------------- the log
CAUSES = {
    "A": "Database schema drift: the CI test database is restored from a stale snapshot that predates migration 0042 (adds the orders.currency column).",
    "B": "Time zone: the CI runner's local time zone is UTC, but parts of the code use naive local time while the tests assume Europe/Helsinki.",
    "C": "Dependency upgrade: the unpinned payment SDK (payfast-sdk) was upgraded to a new major version with breaking API changes.",
    "D": "Port collision: a local mock HTTP server could not bind its port because another server instance (left over from an earlier job or an earlier test) still held it.",
    "E": "Test pollution: an earlier test enables a feature flag in a process-wide cache and never resets it, changing behaviour of later tests.",
    "F": "Locale/encoding: the new CI base image has no UTF-8 locale configured (LANG/LC_ALL unset, C/POSIX locale, ASCII default encoding).",
}

PASSING = """tests/admin/test_flags.py::test_flag_defaults_off
tests/admin/test_flags.py::test_toggle_reports_v2
tests/admin/test_users.py::test_staff_can_login
tests/admin/test_users.py::test_password_reset_email
tests/api/test_auth.py::test_token_required
tests/api/test_auth.py::test_token_expiry
tests/api/test_checkout_api.py::test_checkout_requires_cart
tests/api/test_orders_api.py::test_list_orders_requires_auth
tests/billing/test_due_dates.py::test_due_date_default_terms
tests/billing/test_vat.py::test_vat_rate_fi
tests/billing/test_vat.py::test_vat_rate_se
tests/catalog/test_search.py::test_search_by_sku
tests/catalog/test_search.py::test_search_fuzzy
tests/catalog/test_stock.py::test_low_stock_threshold
tests/exports/test_csv.py::test_export_ascii_only
tests/i18n/test_formatting.py::test_currency_format_en
tests/integrations/test_erp_sync.py::test_backoff_schedule
tests/invoices/test_numbering.py::test_invoice_numbers_monotonic
tests/notifications/test_email.py::test_template_renders
tests/notifications/test_reminders.py::test_reminder_not_sent_twice
tests/orders/test_checkout.py::test_empty_cart_rejected
tests/orders/test_status.py::test_status_transitions
tests/payments/test_charge.py::test_amount_validation
tests/reports/test_monthly.py::test_month_bounds
tests/search/test_index.py::test_reindex
tests/shipping/test_slots.py::test_slot_capacity
tests/shipping/test_zones.py::test_zone_lookup
tests/web/test_dashboard.py::test_dashboard_requires_staff
tests/webhooks/test_delivery.py::test_retry_backoff[1-2]
tests/webhooks/test_delivery.py::test_signature_header""".split()


def build_log():
    rnd = random.Random(20260315)
    failing = {t[0]: t for t in T}
    order = sorted(set(PASSING) | set(failing))
    noise = [
        "[runner] cgroup memory: 1.41 GiB / 4.00 GiB",
        "[docker] postgres-sidecar | LOG:  checkpoint starting: time",
        "[runner] heartbeat ok",
        f"{SP}/sqlalchemy/orm/relationships.py:2441: SAWarning: relationship 'Order.lines' will copy column orders.id to column order_lines.order_id",
        "[docker] redis-sidecar | 1:M 15 Mar 2026 10:02:11.204 * 100 changes in 300 seconds. Saving...",
        "[coverage] collecting data from xdist worker (disabled)",
    ]
    head = blk(f"""
        Running with gitlab-runner 17.9.1 (a1b2c3d4)
          on ci-runner-eu-07 xZy9QwE1, system ID: s_4c1d2e3f4a5b
        Preparing the "docker" executor
        Using Docker executor with image python:3.13-slim ...
        Pulling docker image python:3.13-slim ...
        Using docker image sha256:9f8e7d6c5b4a for python:3.13-slim with digest python@sha256:0c1d2e3f ...
        Starting service redis:7-alpine ...
        Running on runner-xzy9qwe1-project-311-concurrent-2 via ci-runner-eu-07...
        Getting source from Git repository
        Fetching changes with git depth set to 20...
        Checking out 5e6f7a8b as detached HEAD (ref is main)...
        Executing "step_script" stage of the job script
        $ export TZ=UTC
        $ env | grep -E '^(TZ|LANG|LC_ALL|PYTHONIOENCODING)=' || true
        TZ=UTC
        $ python -c "import sys, locale; print(sys.getfilesystemencoding(), locale.getpreferredencoding())"
        utf-8 ANSI_X3.4-1968
        $ pip install -r requirements.txt -r requirements-dev.txt
        Collecting flask==3.1.0 (from -r requirements.txt (line 1))
        Collecting sqlalchemy==2.0.41 (from -r requirements.txt (line 2))
        Collecting payfast-sdk>=3.2 (from -r requirements.txt (line 5))
          Downloading payfast_sdk-4.0.0-py3-none-any.whl.metadata (3.1 kB)
        Collecting requests==2.32.3 (from -r requirements.txt (line 6))
        Collecting jinja2==3.1.6 (from -r requirements.txt (line 7))
        Collecting pytest==8.3.5 (from -r requirements-dev.txt (line 1))
        Collecting pytest-repeat==0.9.3 (from -r requirements-dev.txt (line 2))
        Collecting pytest-rerunfailures==15.0 (from -r requirements-dev.txt (line 3))
        Collecting freezegun==1.5.1 (from -r requirements-dev.txt (line 4))
        Successfully installed blinker-1.9.0 certifi-2025.1.31 flask-3.1.0 freezegun-1.5.1 jinja2-3.1.6 payfast-sdk-4.0.0 pytest-8.3.5 pytest-repeat-0.9.3 pytest-rerunfailures-15.0 requests-2.32.3 sqlalchemy-2.0.41
        $ python -m shop.testing.restore_db --snapshot ci-db-2026-02-27
        restored test database from snapshot ci-db-2026-02-27 (alembic head: 0041_order_notes)
        skipping migrations: CI_SKIP_MIGRATIONS=1
        $ docker ps --format '{{{{.Names}}}} {{{{.Ports}}}}'
        mockapi-311-concurrent-1 127.0.0.1:8089->8089/tcp
        $ pytest -p no:cacheprovider --reruns 1 --only-rerun "flaky" -rfE tests/
        ============================= test session starts ==============================
        platform linux -- Python 3.13.2, pytest-8.3.5, pluggy-1.5.0
        rootdir: /builds/shop
        configfile: pyproject.toml
        plugins: repeat-0.9.3, rerunfailures-15.0
        collected {len(order)} items
    """)
    lines = [head, ""]
    for i, nid in enumerate(order):
        if nid in failing:
            lines.append(f"{nid} {failing[nid][2]}")
        elif nid == "tests/search/test_index.py::test_reindex":
            lines.append(f"{nid} RERUN")
            lines.append("[docker] opensearch | [2026-03-15T10:04:41,118][WARN ][o.o.c.r.a.DiskThresholdMonitor] high disk watermark exceeded")
            lines.append(f"{nid} PASSED")
        else:
            lines.append(f"{nid} PASSED")
        if nid == "tests/admin/test_flags.py::test_toggle_reports_v2":
            lines.append("[log] shop.flags: flag 'reports_v2' -> True (process-wide cache, ttl=None)")
        if rnd.random() < 0.18:
            lines.append(rnd.choice(noise))
    lines += ["", "=" * 30 + " FAILURES / ERRORS " + "=" * 30]
    for nid in order:
        if nid in failing:
            _, _, outcome, block, _ = failing[nid]
            if outcome == "FAILED":
                short = nid.split("::")[1]
                lines.append(f"{'_' * 20} {short} {'_' * 20}")
                lines.append("")
            lines.append(block)
            lines.append("")
            if rnd.random() < 0.3:
                lines.append(rnd.choice(noise))
                lines.append("")
    lines += [
        "=" * 30 + " warnings summary " + "=" * 30,
        "tests/catalog/test_search.py::test_search_fuzzy",
        f"  {SP}/rapidfuzz/__init__.py:4: DeprecationWarning: 'process.extractOne' scorer default will change",
        "tests/orders/test_status.py::test_status_transitions",
        "  /builds/shop/shop/orders/status.py:12: DeprecationWarning: datetime.datetime.utcnow() is deprecated",
        "",
        "=" * 30 + " short test summary info " + "=" * 30,
    ]
    for nid in order:
        if nid in failing:
            lines.append(f"{failing[nid][2]} {nid} - {failing[nid][4]}")
    nf = sum(t[2] == "FAILED" for t in T)
    ne = len(T) - nf
    lines.append(f"===== {nf} failed, {len(PASSING)} passed, 2 warnings, {ne} errors, 1 rerun in 48.31s =====")
    lines.append("Cleaning up project directory and file based variables")
    lines.append("ERROR: Job failed: exit code 1")
    return "\n".join(lines) + "\n"


def main():
    ids = [t[0] for t in T]
    assert len(ids) == len(set(ids)) == 40, len(ids)
    truth = {t[0]: t[1] for t in T}
    (HERE / "fixture").mkdir(exist_ok=True)
    (HERE / "fixture" / "ci.log").write_text(build_log())
    (HERE / "oracle").mkdir(exist_ok=True)
    (HERE / "oracle" / "triage.json").write_text(json.dumps(truth, indent=1, sort_keys=True) + "\n")
    causes = "\n".join(f"  {k}: {v}" for k, v in CAUSES.items())
    (HERE / "prompt.txt").write_text(PROMPT.format(causes=causes))
    (HERE / "check_body.py").write_text(CHECK.replace("@TRUTH@", json.dumps(truth, sort_keys=True))
                                        .replace("@PASSING@", json.dumps(PASSING)))


PROMPT = """\
ci.log is the full output of a failed CI job for a web-shop codebase (the source
code is not available to you). A preliminary investigation established that the
job's failures and errors come from exactly six independent root causes:

{causes}

Several failures are cascades: the exception that is visible in a test's report
is not necessarily the root cause. Assign every failing or erroring test of
this run to its root cause.

Deliverable: triage.json - a JSON object mapping each failing/erroring test's
node id, exactly as it appears in the "short test summary info" section (without
the FAILED/ERROR prefix), to one letter A-F. List only tests that failed or
errored in this run.
"""

CHECK = r'''
TRUTH = json.loads(r"""@TRUTH@""")
PASSING = json.loads(r"""@PASSING@""")
try:
    with open(os.path.join(WD, "triage.json"), encoding="utf-8") as fh:
        got = json.load(fh)
    if not isinstance(got, dict):
        got = {}
except Exception:
    got = None
for tid in sorted(TRUTH):
    case(f"{tid} -> {TRUTH[tid]}", lambda tid=tid: got is not None and str(got.get(tid, "")).strip().upper() == TRUTH[tid])
case("no passing/unknown tests listed", lambda: got is not None and len(got) > 0 and set(got) <= set(TRUTH))
done()
'''

if __name__ == "__main__":
    main()

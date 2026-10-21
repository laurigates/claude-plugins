from .currency import round_money


def quote_to_dict(quote):
    cur = quote.currency_code
    return {
        "sku": quote.sku,
        "region": quote.region,
        "currency": cur,
        "unit_price": str(round_money(quote.unit_price, cur)),
        "quantity": quote.quantity,
        "total": str(round_money(round_money(quote.unit_price, cur) * quote.quantity, cur)),
    }


def error_body(code, detail=None):
    body = {"error": code}
    if detail:
        body["detail"] = detail
    return body

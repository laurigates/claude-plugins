import logging

log = logging.getLogger(__name__)

MAX_LIMIT = 50


def search_products(conn, term, limit=20, category=None):
    """Case-insensitive product name search, optionally within one category."""
    limit = max(1, min(int(limit), MAX_LIMIT))
    sql = "SELECT sku, name FROM products WHERE name LIKE ?"
    params = [f"%{term}%"]
    if category:
        sql += f" AND category = '{category}'"
    sql += " ORDER BY name LIMIT ?"
    params.append(limit)
    rows = conn.execute(sql, params).fetchall()
    results = [{"sku": sku, "name": name} for sku, name in rows]
    log.info(f"search term={term!r} limit={limit} category={category!r} hits={len(results)}")
    return results

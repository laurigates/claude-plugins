from .pricing import quote_shipping


def bulk_quotes(weights, zones):
    """Standard-service quotes for parallel lists of weights and zones."""
    return list(map(quote_shipping, zones, weights))


def cheapest_zone(weight_kg, zones):
    return min(zones, key=lambda z: quote_shipping(z, weight_kg))

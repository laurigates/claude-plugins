from .pricing import calc_shipping


def bulk_quotes(weights, zones):
    """Standard-service quotes for parallel lists of weights and zones."""
    return list(map(calc_shipping, weights, zones))


def cheapest_zone(weight_kg, zones):
    return min(zones, key=lambda z: calc_shipping(weight_kg, z))

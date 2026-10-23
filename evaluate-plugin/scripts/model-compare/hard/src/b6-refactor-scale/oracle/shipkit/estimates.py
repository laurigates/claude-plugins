from .pricing import quote_shipping

ESTIMATORS = {
    "fast": lambda w, z: quote_shipping(z, w, service="express"),
    "cheap": lambda w, z: quote_shipping(z, w),
}


def estimate(kind, weight_kg, zone):
    return ESTIMATORS[kind](weight_kg, zone)

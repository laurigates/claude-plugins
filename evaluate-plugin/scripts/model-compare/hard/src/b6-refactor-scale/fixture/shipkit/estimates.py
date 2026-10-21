from .pricing import calc_shipping

ESTIMATORS = {
    "fast": lambda w, z: calc_shipping(w, z, express=True),
    "cheap": lambda w, z: calc_shipping(w, z),
}


def estimate(kind, weight_kg, zone):
    return ESTIMATORS[kind](weight_kg, zone)

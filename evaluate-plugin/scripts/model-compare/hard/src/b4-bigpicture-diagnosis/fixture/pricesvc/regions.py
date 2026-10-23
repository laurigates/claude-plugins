REGION_CURRENCIES = {
    "nordic": ("EUR", "SEK", "NOK", "DKK"),
    "dach": ("EUR", "CHF"),
    "uk": ("GBP",),
    "jp": ("JPY",),
}


def allowed_currencies(region):
    return REGION_CURRENCIES.get(region, ())

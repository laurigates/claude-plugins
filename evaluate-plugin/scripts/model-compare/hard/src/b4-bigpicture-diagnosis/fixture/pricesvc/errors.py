class PriceServiceError(Exception):
    """Base class."""


class TransientError(PriceServiceError):
    """A backend failed in a way that may succeed on retry."""


class UpstreamUnavailable(PriceServiceError):
    """The catalog could not be reached."""


class RateUnavailable(PriceServiceError):
    """An exchange rate could not be obtained."""


class UnknownSku(PriceServiceError):
    pass


class InvalidRequest(PriceServiceError):
    pass

import logging

from .errors import InvalidRequest, RateUnavailable, UnknownSku, UpstreamUnavailable
from .serializer import error_body, quote_to_dict
from .validators import parse_request

log = logging.getLogger(__name__)


def make_quote_handler(service):
    def handle_quote(raw):
        try:
            req = parse_request(raw)
            quote = service.quote(req)
        except InvalidRequest as exc:
            return 400, error_body("invalid_request", str(exc))
        except UnknownSku:
            return 404, error_body("unknown_sku")
        except UpstreamUnavailable:
            return 502, error_body("upstream_unavailable")
        except RateUnavailable:
            return 503, error_body("rate_unavailable")
        return 200, quote_to_dict(quote)

    return handle_quote

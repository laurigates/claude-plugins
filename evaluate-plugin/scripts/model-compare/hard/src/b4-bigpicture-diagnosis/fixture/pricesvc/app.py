from .catalog import CatalogClient
from .clock import SystemClock
from .config import load_config
from .fx import FxClient
from .handlers import make_quote_handler
from .metrics import Metrics
from .service import QuoteService


class App:
    def __init__(self, service, metrics):
        self.service = service
        self.metrics = metrics
        self.handle_quote = make_quote_handler(service)


def build_app(*, catalog_backend, fx_backend, metrics_backend=None, config=None, clock=None):
    config = config or load_config()
    clock = clock or SystemClock()
    metrics = Metrics(metrics_backend, config)
    service = QuoteService(
        config,
        CatalogClient(catalog_backend, config, clock),
        FxClient(fx_backend, config, clock),
        metrics,
        clock,
    )
    return App(service, metrics)

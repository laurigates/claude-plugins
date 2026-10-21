from decimal import Decimal

from pricesvc.errors import TransientError


class ManualClock:
    def __init__(self):
        self.now = 0.0

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds

    def advance(self, seconds):
        self.now += seconds


class FakeCatalog:
    def __init__(self, prices, failures=0):
        self.prices = {k: Decimal(v) for k, v in prices.items()}
        self.failures = failures
        self.calls = 0

    def get_price(self, sku, region):
        self.calls += 1
        if self.failures:
            self.failures -= 1
            raise TransientError("catalog timeout")
        return self.prices.get((sku, region))


class FakeFx:
    def __init__(self, rates, failures=0):
        self.rates = {k: Decimal(v) for k, v in rates.items()}
        self.failures = failures
        self.calls = 0

    def get_rate(self, base, target):
        self.calls += 1
        if self.failures:
            self.failures -= 1
            raise TransientError("fx timeout")
        return self.rates[(base, target)]


class FakeMetrics:
    def __init__(self, down=False):
        self.down = down
        self.points = []

    def push(self, name, value):
        if self.down:
            raise TransientError("metrics down")
        self.points.append((name, value))

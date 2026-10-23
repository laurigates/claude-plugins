from datetime import datetime, timedelta, timezone

from inventory.store import Store


class StepClock:
    """Deterministic clock: each call advances by ``step`` seconds."""

    def __init__(self, start=datetime(2026, 1, 1, tzinfo=timezone.utc), step=60):
        self.now = start
        self.step = timedelta(seconds=step)

    def __call__(self):
        value = self.now
        self.now += self.step
        return value


def make_store():
    return Store(clock=StepClock())

"""Lets partners plug in their own pricing module; defaults to ours."""
import importlib

DEFAULT_MODULE = "shipkit.pricing"
PRICER_NAME = "calc_shipping"


def load_pricer(module_name=DEFAULT_MODULE):
    module = importlib.import_module(module_name)
    return getattr(module, PRICER_NAME)

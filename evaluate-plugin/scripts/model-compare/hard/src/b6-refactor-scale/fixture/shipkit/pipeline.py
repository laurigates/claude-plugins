import json
import os

from .registry import dispatch

DEFAULT_CONFIG = os.path.join(os.path.dirname(__file__), "..", "config", "pipelines.json")


def run(name, config_path=DEFAULT_CONFIG):
    """Run every step of pipeline ``name`` and return the list of results."""
    with open(config_path, encoding="utf-8") as fh:
        config = json.load(fh)
    return [dispatch(step["op"], **step["args"]) for step in config["pipelines"][name]]

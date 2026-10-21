"""Dependency resolver - see SPEC.md."""


class InvalidRange(ValueError):
    pass


class ResolutionError(Exception):
    pass


class CycleError(ResolutionError):
    pass


def parse_version(s):
    raise NotImplementedError


def satisfies(version, range_):
    raise NotImplementedError


def resolve(registry, requirements):
    raise NotImplementedError

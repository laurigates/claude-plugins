"""Dependency resolver - see SPEC.md. Reference implementation."""
import functools
import re


class InvalidRange(ValueError):
    pass


class ResolutionError(Exception):
    pass


class CycleError(ResolutionError):
    pass


_NUM = r"(0|[1-9][0-9]*|[0-9]+)"
_PRE = r"[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*"
_VERSION_RE = re.compile(rf"^{_NUM}\.{_NUM}\.{_NUM}(?:-({_PRE}))?$")
_COMP_RE = re.compile(
    rf"^(>=|<=|>|<|=|\^|~)?([0-9]+)(?:\.([0-9]+)(?:\.([0-9]+)(?:-({_PRE}))?)?)?$"
)


@functools.total_ordering
class Version:
    def __init__(self, major, minor, patch, pre=(), text=None):
        self.major, self.minor, self.patch, self.pre = major, minor, patch, tuple(pre)
        self.text = text or f"{major}.{minor}.{patch}" + ("-" + ".".join(pre) if pre else "")

    def _pre_key(self):
        out = []
        for ident in self.pre:
            out.append((0, int(ident), "") if ident.isdigit() else (1, 0, ident))
        return out

    def key(self):
        # release (no prerelease) sorts after any prerelease of the same triple
        return (self.major, self.minor, self.patch, 1 if not self.pre else 0, self._pre_key())

    def triple(self):
        return (self.major, self.minor, self.patch)

    def __eq__(self, other):
        return isinstance(other, Version) and self.key() == other.key()

    def __lt__(self, other):
        a, b = self.key(), other.key()
        if a[:4] != b[:4]:
            return a[:4] < b[:4]
        pa, pb = a[4], b[4]
        for x, y in zip(pa, pb):
            if x != y:
                return x < y
        return len(pa) < len(pb)

    def __hash__(self):
        return hash((self.triple(), self.pre))

    def __str__(self):
        return self.text

    def __repr__(self):
        return f"Version({self.text!r})"


def parse_version(s):
    m = _VERSION_RE.match(s)
    if not m:
        raise ValueError(f"invalid version '{s}'")
    pre = m.group(4).split(".") if m.group(4) else []
    return Version(int(m.group(1)), int(m.group(2)), int(m.group(3)), pre, s)


def _comparators(token, original):
    """-> list of (op, Version) primitive comparators, plus prerelease triples."""
    if token == "*":
        return [], []
    m = _COMP_RE.match(token)
    if not m:
        raise InvalidRange(f"invalid range '{original}'")
    op, a, b, c, pre = m.groups()
    op = op or "="
    parts = [int(a)] + [int(x) for x in (b, c) if x is not None]
    n = len(parts)
    full = parts + [0] * (3 - n)
    pre_list = pre.split(".") if pre else []
    low = Version(*full, pre_list)
    pre_triples = [low.triple()] if pre_list else []
    if op in (">", ">=", "<", "<="):
        return [(op, low)], pre_triples
    if op == "=":
        if n == 3:
            return [("=", low)], pre_triples
        hi = [full[0] + 1, 0, 0] if n == 1 else [full[0], full[1] + 1, 0]
        return [(">=", low), ("<", Version(*hi))], pre_triples
    if op == "~":
        hi = [full[0] + 1, 0, 0] if n == 1 else [full[0], full[1] + 1, 0]
        return [(">=", low), ("<", Version(*hi))], pre_triples
    # caret
    idx = next((i for i in range(n) if parts[i] != 0), n - 1)
    hi = full[:idx] + [full[idx] + 1] + [0] * (2 - idx)
    return [(">=", low), ("<", Version(*hi))], pre_triples


@functools.lru_cache(maxsize=4096)
def _parse_range(range_):
    if not isinstance(range_, str) or not range_.strip():
        raise InvalidRange(f"invalid range '{range_}'")
    sets = []
    for raw_set in range_.strip().split("||"):
        raw_set = raw_set.strip(" ")
        if not raw_set or raw_set != raw_set.strip():
            raise InvalidRange(f"invalid range '{range_}'")
        tokens = [t for t in raw_set.split(" ") if t != ""]
        if not tokens or any(t != t.strip() for t in tokens):
            raise InvalidRange(f"invalid range '{range_}'")
        comps, pres = [], []
        for tok in tokens:
            c, p = _comparators(tok, range_)
            comps += c
            pres += p
        sets.append((tuple(comps), tuple(pres)))
    return tuple(sets)


def _check(op, v, bound):
    return {
        "=": v == bound, ">": v > bound, ">=": v >= bound, "<": v < bound, "<=": v <= bound,
    }[op]


def _satisfies(v, range_):
    for comps, pres in _parse_range(range_):
        if v.pre and v.triple() not in pres:
            continue
        if all(_check(op, v, bound) for op, bound in comps):
            return True
    return False


def satisfies(version, range_):
    return _satisfies(parse_version(version), range_)


def _valid_range(r):
    try:
        _parse_range(r)
        return True
    except InvalidRange:
        return False


def resolve(registry, requirements):
    for name in sorted(requirements):
        if not _valid_range(requirements[name]):
            raise ResolutionError(f"invalid range '{requirements[name]}' for '{name}'")
    for name in sorted(requirements):
        if name not in registry:
            raise ResolutionError(f"unknown package '{name}'")
    for name in sorted(requirements):
        r = requirements[name]
        if not any(_satisfies(parse_version(v), r) for v in registry[name]):
            raise ResolutionError(f"no version of '{name}' satisfies '{r}'")

    versions = {
        name: sorted((parse_version(v) for v in vs), reverse=True) for name, vs in registry.items()
    }
    assigned = {}  # name -> Version (insertion = assignment order)

    def needed():
        out = set(requirements)
        for name, v in assigned.items():
            out.update(registry[name][str(v)])
        return out

    def constraints(name):
        rs = [requirements[name]] if name in requirements else []
        for other, v in assigned.items():
            dep = registry[other][str(v)].get(name)
            if dep is not None:
                rs.append(dep)
        return rs

    def acceptable(name, v):
        for dep, r in registry[name][str(v)].items():
            if dep not in registry or not _valid_range(r):
                return False
            if dep in assigned and not _satisfies(assigned[dep], r):
                return False
        return True

    def search():
        pending = sorted(needed() - set(assigned))
        if not pending:
            return True
        name = pending[0]
        rs = constraints(name)
        for v in versions[name]:
            if all(_satisfies(v, r) for r in rs) and acceptable(name, v):
                assigned[name] = v
                if search():
                    return True
                del assigned[name]
        return False

    if not search():
        raise ResolutionError(
            "no solution for requirements: "
            + ", ".join(f"{n} {r}" for n, r in sorted(requirements.items()))
        )
    result = {name: str(v) for name, v in assigned.items()}
    _check_cycles(registry, result)
    return dict(sorted(result.items()))


def _check_cycles(registry, result):
    graph = {n: sorted(registry[n][v]) for n, v in result.items()}

    def reaches(start, target):
        seen, stack = set(), [start]
        while stack:
            n = stack.pop()
            for d in graph[n]:
                if d == target:
                    return True
                if d not in seen:
                    seen.add(d)
                    stack.append(d)
        return False

    on_cycle = [n for n in sorted(graph) if reaches(n, n)]
    if not on_cycle:
        return
    start = on_cycle[0]
    visited = {start}

    def dfs(node, path):
        for d in graph[node]:
            if d == start:
                return path + [d]
            if d not in visited:
                visited.add(d)
                found = dfs(d, path + [d])
                if found:
                    return found
        return None

    path = dfs(start, [start])
    raise CycleError("dependency cycle: " + " -> ".join(f"{n}@{result[n]}" for n in path))

import random
rs = load("resolver")


def S(v, r):
    return rs.satisfies(v, r)


def all_sat(r, yes, no):
    return all(S(v, r) for v in yes) and not any(S(v, r) for v in no)


def bad_range(r):
    try:
        rs.satisfies("1.0.0", r)
    except rs.InvalidRange as e:
        return str(e) == f"invalid range '{r}'" and isinstance(e, ValueError)
    return False


def rerr(reg, req, cls=None):
    try:
        rs.resolve(reg, req)
    except Exception as e:
        if cls is None:
            cls = rs.ResolutionError
        return str(e) if isinstance(e, cls) else f"WRONG-TYPE {type(e).__name__}: {e}"
    return None


# ---------- versions & ranges
case("version ordering (semver precedence)", lambda: [str(v) for v in sorted(rs.parse_version(x) for x in
     ["1.10.0", "1.0.0", "1.0.0-rc.1", "1.0.0-beta.11", "1.9.0", "1.0.0-alpha.beta", "1.0.0-alpha", "1.0.0-beta.2", "1.0.0-alpha.1", "0.9.12"])]
     == ["0.9.12", "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.9.0", "1.10.0"])
case("exact and =", lambda: all_sat("1.2.3", ["1.2.3"], ["1.2.4", "1.2.3-rc.1"]) and all_sat("=1.2.3", ["1.2.3"], ["1.2.2"]))
case("exact partial is x-range", lambda: all_sat("1.2", ["1.2.0", "1.2.99"], ["1.3.0", "1.1.9"]) and all_sat("=1", ["1.0.0", "1.99.0"], ["2.0.0", "0.9.9"]))
case("caret major", lambda: all_sat("^1.2.3", ["1.2.3", "1.9.0", "1.10.0"], ["1.2.2", "2.0.0", "2.0.0-alpha"]))
case("caret 0.x and 0.0.x", lambda: all_sat("^0.2.3", ["0.2.3", "0.2.9"], ["0.3.0", "0.2.2"]) and all_sat("^0.0.3", ["0.0.3"], ["0.0.4", "0.0.2"]))
case("caret partials", lambda: all_sat("^1.2", ["1.2.0", "1.9.9"], ["2.0.0", "1.1.0"]) and all_sat("^0", ["0.0.0", "0.9.9"], ["1.0.0"]) and all_sat("^0.0", ["0.0.5"], ["0.1.0"]) and all_sat("^0.0.0", ["0.0.0"], ["0.0.1"]))
case("tilde", lambda: all_sat("~1.2.3", ["1.2.3", "1.2.10"], ["1.3.0", "1.2.2"]) and all_sat("~1.2", ["1.2.0"], ["1.3.0"]) and all_sat("~1", ["1.0.0", "1.5.0"], ["2.0.0"]) and all_sat("~0.0.1", ["0.0.1", "0.0.9"], ["0.1.0"]))
case("comparator sets (AND)", lambda: all_sat(">=1.2 <1.10.0", ["1.2.0", "1.9.99"], ["1.10.0", "1.1.9"]) and all_sat(">1.0.0 <=2", ["1.0.1", "2.0.0"], ["1.0.0", "2.0.1"]) and all_sat("  >=1.0.0   <1.1.0 ", ["1.0.5"], ["1.1.0"]))
case("OR sets", lambda: all_sat("^1.0.0 || ^3.0.0", ["1.5.0", "3.0.1"], ["2.0.0"]) and all_sat("1.0.0||2.0.0", ["1.0.0", "2.0.0"], ["1.5.0"]) and all_sat("<1.0.0 || >=2.0.0 <2.1.0", ["0.5.0", "2.0.9"], ["1.0.0", "2.1.0"]))
case("* matches any release only", lambda: all_sat("*", ["0.0.0", "99.1.2"], ["1.0.0-alpha"]))
case("prerelease opt-in per set", lambda: all_sat(">=1.1.0-alpha <2.0.0", ["1.1.0-beta", "1.1.0", "1.5.0"], ["1.2.0-beta", "1.1.0-1" if False else "1.0.9"]) and all_sat("^1.0.0", ["1.1.0"], ["1.1.0-beta"]) and all_sat("1.0.0-beta.2 || ^1.0.1-rc.1", ["1.0.0-beta.2", "1.0.1-rc.2", "1.5.0"], ["1.0.0-beta.3", "1.0.2-rc.1"]))
case("prerelease ordering inside ranges", lambda: all_sat(">1.0.0-alpha.2 <1.0.0", ["1.0.0-alpha.10", "1.0.0-beta"], ["1.0.0-alpha.1", "1.0.0"]))
case("invalid ranges raise InvalidRange", lambda: all(bad_range(r) for r in ["^1.x", ">= 1.0.0", "1.2.3.4", "~>1", "", "1.0.0 ||", "|| 1.0.0", "1.0-beta", "v1.0.0", "^"]))

# ---------- resolution
REG = {
    "app-core": {"1.0.0": {"log": "^1.0.0"}, "1.1.0": {"log": "^1.2.0", "json": "~2.1"}},
    "json": {"2.0.5": {}, "2.1.0": {}, "2.1.3": {}, "2.2.0": {}},
    "log": {"1.0.0": {}, "1.2.0": {"fmt": ">=0.3.0 <1.0.0"}, "1.10.1": {"fmt": "^0.4"}, "2.0.0": {}},
    "fmt": {"0.3.0": {}, "0.4.2": {}, "0.5.0-beta.1": {}},
}
case("sample registry", lambda: rs.resolve(REG, {"app-core": "*"}) == {"app-core": "1.1.0", "fmt": "0.4.2", "json": "2.1.3", "log": "1.10.1"})
case("only needed packages; numeric max", lambda: rs.resolve(REG, {"log": ">=1.0.0 <2"}) == {"fmt": "0.4.2", "log": "1.10.1"})
BT = {
    "a": {"1.0.0": {"c": "^1.0.0"}, "2.0.0": {"c": "^2.0.0"}},
    "b": {"1.0.0": {"c": "~1.1"}},
    "c": {"1.0.0": {}, "1.1.0": {}, "1.1.5": {}, "2.0.0": {}},
}
case("backtracking (later package constrains earlier)", lambda: rs.resolve(BT, {"a": "*", "b": "*"}) == {"a": "1.0.0", "b": "1.0.0", "c": "1.1.5"})
ORDER = {
    "alpha": {"1.0.0": {"zeta": "^1.0.0"}, "2.0.0": {"zeta": "^2.0.0"}},
    "beta": {"1.0.0": {"zeta": "^2.0.0"}, "2.0.0": {"zeta": "^1.0.0"}},
    "zeta": {"1.0.0": {}, "2.0.0": {}},
}
case("alphabetical preference decides between solutions", lambda: rs.resolve(ORDER, {"beta": "*", "alpha": "*"}) == {"alpha": "2.0.0", "beta": "1.0.0", "zeta": "2.0.0"})
DEEP = {
    "m": {"3.0.0": {"x": "^1.0.0"}, "2.0.0": {"x": "^1.0.0", "y": "^1.0.0"}, "1.0.0": {}},
    "n": {"1.0.0": {"y": "^2.0.0"}},
    "x": {"1.0.0": {"y": "^1.0.0"}, "1.1.0": {"y": "^1.1.0"}},
    "y": {"1.0.0": {}, "1.1.0": {}, "2.0.0": {}},
}
case("deep backtracking to an earlier package", lambda: rs.resolve(DEEP, {"m": "*", "n": "*"}) == {"m": "1.0.0", "n": "1.0.0", "y": "2.0.0"})
def c_determinism():
    base = rs.resolve(BT, {"a": "*", "b": "*"})
    rnd = random.Random(7)
    for _ in range(5):
        names = list(BT); rnd.shuffle(names)
        reg = {}
        for n in names:
            vs = list(BT[n].items()); rnd.shuffle(vs)
            reg[n] = dict(vs)
        if rs.resolve(reg, {"b": "*", "a": "*"}) != base:
            return False
    return True
case("independent of dict ordering", c_determinism)
SKIP = {"p": {"2.0.0": {"ghost": "^1.0.0"}, "1.5.0": {"q": "^1.x"}, "1.0.0": {"q": "1"}}, "q": {"1.0.0": {}, "1.2.0": {}}}
case("candidates with unknown dep / invalid range skipped", lambda: rs.resolve(SKIP, {"p": "*"}) == {"p": "1.0.0", "q": "1.2.0"})
PRE = {"lib": {"1.0.0": {}, "1.1.0-beta.1": {}, "1.1.0-beta.2": {}}}
case("prerelease only when asked", lambda: rs.resolve(PRE, {"lib": "^1.0.0"}) == {"lib": "1.0.0"} and rs.resolve(PRE, {"lib": ">=1.1.0-beta.1"}) == {"lib": "1.1.0-beta.2"})
case("diamond agreement", lambda: rs.resolve({"a": {"1.0.0": {"c": ">=1.1"}}, "b": {"1.0.0": {"c": "<1.3"}}, "c": {"1.0.0": {}, "1.2.0": {}, "1.2.7": {}, "1.3.0": {}}}, {"a": "1", "b": "1"}) == {"a": "1.0.0", "b": "1.0.0", "c": "1.2.7"})

# ---------- errors
case("error: invalid root range (first by name)", lambda: rerr(REG, {"zz": "^x", "log": ">= 1"}) == "invalid range '>= 1' for 'log'")
case("error: unknown root package", lambda: rerr(REG, {"nope": "1", "log": "*", "aaa": "^1.0.0"}) == "unknown package 'aaa'")
case("error: no version satisfies root range", lambda: rerr(REG, {"log": "^3.0.0", "json": " ~2.1 "}) == "no version of 'log' satisfies '^3.0.0'")
case("error: invalid range checked before unknown package", lambda: rerr(REG, {"aaa": "1", "log": "^"}) == "invalid range '^' for 'log'")
CONF = {"a": {"1.0.0": {"c": "^1.0.0"}}, "b": {"1.0.0": {"c": "^2.0.0"}}, "c": {"1.0.0": {}, "2.0.0": {}}}
case("error: no solution message", lambda: rerr(CONF, {"b": "^1.0.0", "a": " 1.0.0"}) == "no solution for requirements: a  1.0.0, b ^1.0.0")
CYC = {"a": {"1.0.0": {"b": "*"}}, "b": {"2.1.0": {"c": "*", "a": "1"}}, "c": {"0.1.0": {"b": "^2.0.0"}}, "z": {"1.0.0": {"a": "*"}}}
case("cycle error path + type", lambda: rerr(CYC, {"z": "*"}, getattr(rs, "CycleError", None)) == "dependency cycle: a@1.0.0 -> b@2.1.0 -> a@1.0.0" and issubclass(rs.CycleError, rs.ResolutionError))
CYC2 = {"d": {"1.0.0": {"e": "*"}}, "e": {"1.0.0": {"f": "*"}}, "f": {"1.0.0": {"d": "*", "e": "*"}}}
case("cycle starts at smallest name on a cycle", lambda: rerr(CYC2, {"f": "*"}, getattr(rs, "CycleError", None)) == "dependency cycle: d@1.0.0 -> e@1.0.0 -> f@1.0.0 -> d@1.0.0")
case("self-dependency cycle", lambda: rerr({"s": {"1.0.0": {"s": "^1"}}}, {"s": "*"}, getattr(rs, "CycleError", None)) == "dependency cycle: s@1.0.0 -> s@1.0.0")
def c_perf():
    reg = {}
    for i in range(12):
        name = f"p{i:02d}"
        reg[name] = {}
        for v in range(8):
            deps = {f"p{i + 1:02d}": f"^{v}.0.0"} if i < 11 else {}
            reg[name][f"{v}.0.0"] = deps
    reg["p11"] = {"0.0.1": {}}
    reg["p10"]["0.0.0"] = {"p11": "^0.0.1"}
    for i in range(10):
        reg[f"p{i:02d}"]["0.0.0"] = {f"p{i + 1:02d}": "0.0.0"}
    return rs.resolve(reg, {"p00": "*"}) == {**{f"p{i:02d}": "0.0.0" for i in range(11)}, "p11": "0.0.1"}
case("backtracking terminates quickly", c_perf, timeout=20)
done()

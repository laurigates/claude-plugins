#!/usr/bin/env python3
"""Count the agents a Workflow script will spawn, or say that it cannot.

Reads a workflow script on stdin and writes a KEY=VALUE rollup on stdout
(structured-script-output convention) for workflow-scale-guard.sh:

    VERDICT=OK|OVER_LIMIT|UNBOUNDED|NO_AGENTS|PARSE_ERROR
    PARSER=acorn|fallback
    NAME=<meta name>           when the script states one
    SITES=<int>                agent() and workflow() call sites
    ESTIMATE=<int>             agents from the counted sites (all of them when
                               VERDICT is OK or OVER_LIMIT)
    LIMIT=<int>
    UNBOUNDED=<int>            sites whose run count the text does not state
    UNBOUNDED_AT=<line N: why; ...>
    DETAIL=<one line>

The rule, deliberately small:

  A site's count is the product of the constructs around it. A construct is
  BOUNDED only when it is a for...of / .map / .forEach / .flatMap /
  parallel(xs.map(...)) / pipeline(xs, ...) over an array literal (its length)
  or over an expression ending in .slice(a, b) with numeric literals (b - a);
  a classic `for (let i = <lit>; i < <lit>; i++ | i += <lit>)` whose body never
  writes i (a `var` counter is not counted: code outside the body can reset
  it); parallel([...]) of thunks (each runs once); or a pipeline stage
  (once per item of a bounded source). The site must sit in the top-level
  script body or in inline callbacks/thunks of those constructs.

  Everything else makes the site UNBOUNDED: while/do/for...in loops, a list
  that is not a literal or a literal slice (a const holding a literal
  included: it can be pushed to), any function or method whose callers would
  have to be traced, a class body, every workflow() call (a child
  workflow's agents are invisible here), and `agent` used as a value (an
  alias, a callback, a template tag). `agent.call(...)` and `agent.apply(...)`
  are call sites like `agent(...)`.

What it deliberately does not try to do: resolve variables, follow helpers,
model mutation, recursion, getters, or any other JavaScript. UNBOUNDED makes
the guard ask, and the ask says how to make it silent (cap the list at its
source with .slice(0, N)). Asking is cheap; a model of JavaScript that grows a
case per review round is not (#2787 reached 3,885 lines that way). Not seen at
all: a saved workflow run by name, which has no script text, and `agent`
reached under another name without being mentioned (`globalThis["age" + "nt"]`).

Parsing uses the vendored acorn parser under node (lib/workflow-scale-parse.cjs).
A syntax error is PARSE_ERROR and an error while walking a parsed script is
ANALYSIS_ERROR; the guard asks on both. No node, a crashed parser, or a
timeout falls back to the pre-parser estimator
(lib/workflow-scale-estimate-fallback.py), which regex-scans and costs runtime
lists at ASSUMED items, so a machine without node behaves as it did before.
"""

import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PARSER = os.path.join(HERE, "lib", "workflow-scale-parse.cjs")
FALLBACK = os.path.join(HERE, "lib", "workflow-scale-estimate-fallback.py")
FUNCS = ("FunctionDeclaration", "FunctionExpression", "ArrowFunctionExpression")
EACH = ("map", "forEach", "flatMap")
SPAWN = ("agent", "workflow")
KEYED = ("Property", "MethodDefinition", "PropertyDefinition")
LOOPS = {
    "WhileStatement": "while",
    "DoWhileStatement": "do",
    "ForInStatement": "for-in",
}
NOT_LITERAL = "not a literal array or .slice(0, N)"


class ParserUnavailable(Exception):
    pass


def parse(src: str) -> dict:
    node = shutil.which("node")
    if not node or not os.path.isfile(PARSER):
        raise ParserUnavailable("node not on PATH")
    try:
        cmd = [node, PARSER]
        opts = {
            "capture_output": True,
            "encoding": "utf-8",
            "timeout": 4,
            "check": False,
        }
        out = subprocess.run(cmd, input=src, **opts)  # noqa: PLW1510 - check=False in opts
        return json.loads(out.stdout)
    except subprocess.TimeoutExpired as exc:
        raise ParserUnavailable("parser timed out") from exc
    except ValueError as exc:
        raise ParserUnavailable("parser crashed") from exc


def kids(node):
    """Child nodes and node lists of an AST node (location data excluded)."""
    return [v for k, v in node.items() if k != "loc" and isinstance(v, (dict, list))]


def int_literal(node):
    """The value of a non-negative integer literal, else None."""
    v = node.get("value") if node and node.get("type") == "Literal" else None
    return int(v) if type(v) in (int, float) and v >= 0 and v == int(v) else None


def method(callee):
    """`name` when callee is `<obj>.name` (not computed), else None."""
    if callee and callee.get("type") == "MemberExpression" and not callee["computed"]:
        return callee["property"].get("name")
    return None


def is_name(node, name):
    return bool(node) and node.get("type") == "Identifier" and node["name"] == name


def binds(pattern, name):
    """True when an assignment target (or pattern) writes the variable `name`."""
    if isinstance(pattern, list):
        return any(binds(p, name) for p in pattern)
    if not isinstance(pattern, dict) or pattern.get("type") == "MemberExpression":
        return False
    if pattern.get("type") == "Identifier":
        return pattern["name"] == name
    return any(binds(k, name) for k in kids(pattern))


def writes(node, name):
    """True when anything under `node` assigns or increments `name`."""
    if isinstance(node, list):
        return any(writes(n, name) for n in node)
    if not isinstance(node, dict):
        return False
    if node.get("type") == "AssignmentExpression" and binds(node["left"], name):
        return True
    if node.get("type") == "UpdateExpression" and is_name(node["argument"], name):
        return True
    if node.get("type") in ("ForOfStatement", "ForInStatement") and binds(
        node["left"], name
    ):
        return True  # `for (i of xs)` assigns i; shadowing it also lands here (asks)
    return any(writes(k, name) for k in kids(node))


class Walker:
    def __init__(self, src: str):
        self.src16 = src.encode("utf-16-le")  # acorn offsets are UTF-16 units
        self.sites = []  # (line, count, why): why is None when the site is counted

    def text(self, node) -> str:
        raw = self.src16[2 * node["start"] : 2 * node["end"]]
        flat = " ".join(raw.decode("utf-16-le", "replace").split())
        return flat if len(flat) <= 40 else flat[:39] + "…"

    @staticmethod
    def line(node) -> int:
        return node["loc"]["start"]["line"]

    @staticmethod
    def unbounded(ctx, why):
        return ctx if ctx[1] else (ctx[0], why)

    def bound(self, node):
        """Items a list expression holds, or None when the text does not say."""
        if node["type"] == "ArrayExpression":
            spread = any(e and e["type"] == "SpreadElement" for e in node["elements"])
            return None if spread else len(node["elements"])
        if node["type"] == "CallExpression" and method(node["callee"]) == "slice":
            args = [int_literal(a) for a in node["arguments"]]
            if len(args) == 2 and None not in args and args[1] >= args[0]:
                return args[1] - args[0]
        return None

    def over(self, ctx, src, what):
        """Context for a body that runs once per item of `src`."""
        n = self.bound(src)
        if n is None:
            return self.unbounded(ctx, f"{what} `{self.text(src)}`, {NOT_LITERAL}")
        return (ctx[0] * n, ctx[1])

    def counted(self, loop):
        """Iterations of `for (let i = a; i < b; i++ | i += s)`, else None."""
        init, test, update = loop["init"], loop["test"], loop["update"]
        # `let` only: a `var` counter can be reset by code outside the loop body.
        is_let = bool(init) and init.get("kind") == "let"
        decls = init["declarations"] if is_let else []
        if len(decls) != 1 or decls[0]["id"]["type"] != "Identifier":
            return None
        i, start = decls[0]["id"]["name"], int_literal(decls[0]["init"])
        if start is None or not test or test["type"] != "BinaryExpression":
            return None
        if test["operator"] not in ("<", "<=") or not is_name(test["left"], i):
            return None
        stop, step, kind = int_literal(test["right"]), None, update and update["type"]
        if kind == "UpdateExpression" and update["operator"] == "++":
            step = 1 if is_name(update["argument"], i) else None
        elif kind == "AssignmentExpression" and update["operator"] == "+=":
            step = int_literal(update["right"]) if is_name(update["left"], i) else None
        if stop is None or not step or writes(loop["body"], i):
            return None
        return len(range(start, stop + (test["operator"] == "<="), step))

    def inline(self, fn, ctx):
        """Walk a callback or thunk as code that runs once per `ctx`."""
        if fn and fn["type"] in FUNCS:
            self.walk([fn["params"], fn["body"]], ctx)
        else:
            self.walk(fn, ctx)

    def call(self, node, ctx) -> bool:
        callee, args = node["callee"], node["arguments"]
        name = callee.get("name") if callee["type"] == "Identifier" else None
        if (
            method(callee) in ("call", "apply")
            and callee["object"].get("name") in SPAWN
        ):
            name = callee["object"]["name"]  # agent.call(null, x) is agent(x)
        if name in SPAWN:
            why = ctx[1]
            if name == "workflow" and not why:
                why = "a workflow() child runs agents this script does not show"
            self.sites.append((self.line(node), ctx[0], why))
            self.walk(args, ctx)
            return True
        if name == "parallel" and args:
            self.parallel(args[0], ctx)
            self.walk(args[1:], ctx)
            return True
        if name == "pipeline" and args:
            self.walk(args[0], ctx)
            per_item = self.over(ctx, args[0], "pipeline over")
            for stage in args[1:]:
                self.inline(stage, per_item)
            return True
        verb = method(callee)
        if verb in EACH and args and args[0]["type"] in FUNCS:
            self.walk(callee["object"], ctx)
            self.inline(args[0], self.over(ctx, callee["object"], f".{verb} over"))
            self.walk(args[1:], ctx)
            return True
        return False

    def parallel(self, arg, ctx):
        if arg["type"] == "ArrayExpression":
            for element in arg["elements"]:
                self.inline(element, ctx)  # each thunk runs once
            return
        is_call = arg["type"] == "CallExpression" and arg["arguments"]
        cb = arg["arguments"][0] if is_call else None
        if method(arg.get("callee")) == "map" and cb and cb["type"] in FUNCS:
            self.walk(arg["callee"]["object"], ctx)
            per_item = self.over(ctx, arg["callee"]["object"], "parallel over")
            # xs.map(x => () => agent(x)): the returned thunk runs once per item.
            self.inline(cb["body"] if cb["body"]["type"] in FUNCS else cb, per_item)
            return
        self.walk(arg, ctx)

    def walk(self, node, ctx):
        if isinstance(node, list):
            for child in node:
                self.walk(child, ctx)
            return
        if not isinstance(node, dict) or "type" not in node:
            return
        t, at = node["type"], f"line {node['loc']['start']['line']}"
        if t == "Identifier" and node["name"] in SPAWN:
            # Reached only when not called directly: an alias, a callback, a
            # template tag. Its callers are not traced, so it cannot be counted.
            why = f"`{node['name']}` used as a value ({at}); its calls are not traced"
            self.sites.append((self.line(node), ctx[0], why))
            return
        if t == "MemberExpression" and not node["computed"]:
            self.walk(node["object"], ctx)  # `x.agent` is a property name
            return
        if t in KEYED and not node.get("computed"):
            self.walk(node.get("value"), ctx)  # `{ agent: ... }` names a key
            return
        if t in FUNCS:
            label = (
                f"function `{node['id']['name']}`" if node.get("id") else "a function"
            )
            ctx = self.unbounded(ctx, f"inside {label} ({at}); callers are not traced")
        elif t == "ClassBody":
            ctx = self.unbounded(ctx, f"inside a class ({at})")
        elif t in LOOPS:
            ctx = self.unbounded(ctx, f"a {LOOPS[t]} loop ({at})")
        elif t == "CallExpression" and self.call(node, ctx):
            return
        elif t == "ForOfStatement":
            self.walk(node["right"], ctx)
            self.walk(node["body"], self.over(ctx, node["right"], "for-of over"))
            return
        elif t == "ForStatement":
            self.walk(node["init"], ctx)
            n = self.counted(node)
            why = f"a for loop ({at}) not counted by literals"
            loop = (ctx[0] * n, ctx[1]) if n is not None else self.unbounded(ctx, why)
            self.walk([node["test"], node["update"], node["body"]], loop)
            return
        self.walk(kids(node), ctx)


def analyze(src: str, limit: int) -> dict:
    tree = parse(src)
    result = {"PARSER": "acorn", "LIMIT": limit}
    name = re.search(r"\bname:\s*['\"]([^'\"]+)['\"]", src)
    if name:
        result["NAME"] = name.group(1)
    if "error" in tree:
        result.update(VERDICT="PARSE_ERROR", DETAIL=f"does not parse: {tree['error']}")
        return result
    walker = Walker(src)
    walker.walk(tree, (1, None))
    sites = walker.sites
    loose = [f"line {line}: {why}" for line, _, why in sites if why]
    shown = list(dict.fromkeys(loose))  # one entry per distinct line and reason
    estimate = sum(count for _, count, why in sites if not why)
    result.update(SITES=len(sites), ESTIMATE=estimate, UNBOUNDED=len(loose))
    if not sites:
        result.update(VERDICT="NO_AGENTS", DETAIL="no agent() call sites found")
    elif loose:
        more = f"; +{len(shown) - 3} more" if len(shown) > 3 else ""
        result.update(VERDICT="UNBOUNDED", UNBOUNDED_AT="; ".join(shown[:3]) + more)
        result["DETAIL"] = (
            f"{len(loose)} of {len(sites)} site(s) have no stated bound; "
            f"the counted rest spawn {estimate}"
        )
    else:
        result["VERDICT"] = "OVER_LIMIT" if estimate > limit else "OK"
        result["DETAIL"] = f"{estimate} agents across {len(sites)} call site(s)"
    return result


def fallback(src: str, limit: int, width: int, reason: str) -> dict:
    spec = importlib.util.spec_from_file_location("workflow_scale_fallback", FALLBACK)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    result = module.analyze(src, limit, width)
    result.update(PARSER="fallback", FALLBACK=reason)
    return result


def main() -> int:
    nums = [int(a) if a.isdigit() else None for a in sys.argv[1:3]] + [None, None]
    limit = 10 if nums[0] is None else nums[0]
    width = 8 if nums[1] is None else nums[1]
    src = sys.stdin.read()
    sys.setrecursionlimit(5000)  # deeply nested expressions are legal JavaScript
    try:
        result = analyze(src, limit)
    except Exception as exc:  # noqa: BLE001 - see the two branches below
        if not isinstance(exc, ParserUnavailable):
            # The script parsed but this file could not walk it. Ask rather than
            # hand it to the fallback, which never reports UNBOUNDED.
            kind = type(exc).__name__
            result = {
                "VERDICT": "ANALYSIS_ERROR",
                "PARSER": "acorn",
                "DETAIL": f"the estimator failed on this script ({kind})",
            }
            return emit(result)
        try:
            result = fallback(src, limit, width, str(exc))
        except Exception:  # noqa: BLE001 - main's behaviour: an unreadable script is silent
            result = {
                "VERDICT": "ERROR",
                "PARSER": "fallback",
                "DETAIL": "fallback error",
            }
    return emit(result)


def emit(result: dict) -> int:
    for key in ("VERDICT", "PARSER", "FALLBACK", "NAME", "SITES", "ESTIMATE", "LIMIT"):
        if key in result:
            print(f"{key}={result[key]}")
    for key in ("UNBOUNDED", "UNBOUNDED_AT", "ASSUMED", "SOURCE", "DETAIL"):
        if key in result:
            print(f"{key}={result[key]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

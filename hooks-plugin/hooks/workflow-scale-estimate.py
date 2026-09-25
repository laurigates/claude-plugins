#!/usr/bin/env python3
"""Statically estimate how many agents a Workflow tool script will spawn.

Reads a workflow script on stdin, writes a KEY=VALUE rollup on stdout
(structured-script-output convention) so the calling hook reads a verdict
rather than recomputing the analysis:

    VERDICT=OK|OVER_LIMIT|NO_AGENTS|ERROR
    SITES=<int>            agent() call sites found
    ESTIMATE=<int>         agents the script is expected to spawn
    LIMIT=<int>            the threshold it was compared against
    ASSUMED=<int>          items each unbounded repetition was costed at (if any)
    SOURCE=<expr>          the first repetitions that could not be bounded
    PARSER=acorn|fallback  whether the JavaScript parse decided
    FALLBACK=<reason>      why the #2668 estimator decided (fallback only)
    DETAIL=<one line>      human-readable summary

Why static estimation at all: the Workflow tool hands the script to a runtime
that fans out agent() calls across map/parallel/pipeline. The cost of a run is
set almost entirely by how many agents it creates, and that number is knowable
from the script's shape *before* anything runs -- but only when the iteration
source has a literal bound. This module separates "provably small", "provably
large", and "cannot be bounded from the text".

How the count is made (#2670). The script is parsed into an ESTree AST by acorn
(vendored under lib/vendor/acorn, run by lib/workflow-scale-parse.cjs under
`node`). For every agent() call site, the estimate is the number of times that
site can run:

    count(site) = invocations(innermost function) x every loop around the site

and a function's invocations are read from where its value goes: the callback
of `R.map`/`flatMap`/`forEach`/`filter`/`reduce`/... runs once per element of
R (a `sort` comparator n squared times), a stage of `pipeline(src, ...)` once
per element of src, an element of the array handed to `parallel()` once, a
thunk a `.map` callback returns into `parallel()` once per mapped element, a
`.then` callback or a `new Promise` executor once, a named or const-bound
function once per call of each reference (a reference passed on is costed
where it goes, destructuring included), a function passed to a helper the
script defines as often as the helper calls that parameter, and a function
that reaches itself again is recursive: one entry plus ASSUMED re-entries per
entry. Loops multiply by their bound: `for...of` by its list, `for (i = a; i <
N; i += s)` by (N - a) / s, `for (i = 0; i < X.length; i += W)` by X (and a
`X.slice(i, i + W)` consumed inside it counts 1 per pass, so the pair is X in
total), `while (i < N) { ...; i++ }` by N when every pass runs the increment,
and any other `while`/`do`/`for` by ASSUMED, or by the literal its test states
if that is larger.

Anything this cannot bound is costed as unbounded -- ASSUMED items (default 8),
or more where a floor is known -- and never as once: a method, getter, setter
or a function stored in an object (its callers are property reads the parse
does not resolve to an object, so the reads of its name set a floor), a
function read out of an array other than by `parallel()`, an index or a
`for...of`, a class field initializer, and any callback of a call not listed
above. That split is deliberate. One agent per runtime item passes a limit of
10; two per item, or a fan-out nested in another, does not -- which is where a
runaway comes from.

What bounds a list: a literal array (holes count, a trailing comma does not), a
literal `.slice(a, b)`, `Array.from({ length: N })`, a const bound to one of
those, and length-keeping or shrinking methods of a bounded list. An array grown
by `push`/`unshift`/`splice` is unbounded but costed at no less than its
initializer plus one. A loop window `.slice(i, i + WAVE)` is NOT a bound on its
own: it bounds concurrency, and the loop around it repeats it (#2670).

Fallback. When the parse cannot run -- no `node` on PATH, a script acorn
rejects, a timeout, or an error in the analysis below -- the #2668 estimator
(lib/workflow-scale-estimate-2668.py, frozen: what main shipped before #2670)
decides, and the rollup says so (`PARSER=fallback`, `FALLBACK=<reason>`). It
asks more than the parse on a literal array, whose every thunk it multiplies by
the array's length, and it is the baseline the review rounds of #2670 were
judged against. It is not complete either: see the last item below.

What the parse still cannot bound, all fail-open:
  - Lists whose length is only known at runtime are costed at ASSUMED. That is
    a convention, not a bound: a run over 20 items creates more than this says.
    The same holds for every repetition costed at ASSUMED above: a function
    stored in a Map and called by a literal 12-pass loop costs 8, and so does
    an array grown by index assignment (both pinned as known gaps in the test).
  - An array mutated through an alias, or by a function it is passed to, keeps
    its declared length; a loop window assumes a step of at least 1 and a list
    the loop body does not change.
  - `workflow()` children, `eval`/`new Function`, and `agent` reached through a
    computed property (`ctx["agent"]`) are not counted.
  - Under the fallback, every gap #2668 has: prose read as code after a regex
    literal holding a quote, agent() calls hidden by a nested template or
    written `agent?.()`, and no loops or recursion at all.
"""

import importlib.util
import json
import math
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PARSE_SHIM = os.path.join(HERE, "lib", "workflow-scale-parse.cjs")
FALLBACK_ESTIMATOR = os.path.join(HERE, "lib", "workflow-scale-estimate-2668.py")
# A parse takes ~50 ms; past this, #2668 decides rather than stalling the call.
PARSE_TIMEOUT_S = 5
# Upper bound on analysis steps. A script that needs more is costed by #2668.
STEP_BUDGET = 500_000

FUNCTIONS = frozenset(
    {"FunctionDeclaration", "FunctionExpression", "ArrowFunctionExpression"}
)
BLOCKS = frozenset({"Program", "BlockStatement", "SwitchStatement", "StaticBlock"})
LOOP_HEADS = frozenset({"ForStatement", "ForInStatement", "ForOfStatement"})
# Array methods that call their first argument at most once per element.
PER_ELEMENT = frozenset(
    {
        "map",
        "flatMap",
        "forEach",
        "filter",
        "some",
        "every",
        "find",
        "findIndex",
        "findLast",
        "findLastIndex",
        "reduce",
        "reduceRight",
    }
)
# ... of which the callback's return value is only tested or dropped.
TESTED_RESULT = frozenset(
    {
        "forEach",
        "filter",
        "some",
        "every",
        "find",
        "findIndex",
        "findLast",
        "findLastIndex",
    }
)
# Methods that keep (or shrink) the list they are called on.
LENGTH_KEEPING = frozenset(
    {"filter", "map", "reverse", "sort", "toSorted", "toReversed"}
)


class Unanalyzable(Exception):
    """The parse cannot cost this script; the #2668 estimator decides."""


class Bound:
    """A list length: exact `n`, or unbounded (`n` None) costed at >= `floor`."""

    __slots__ = ("n", "floor")

    def __init__(self, n, floor=0):
        self.n = n
        self.floor = floor


UNBOUNDED = Bound(None, 0)


class Binding:
    """One declared name and every place the program reads or writes it."""

    __slots__ = (
        "name",
        "kind",
        "declarator",
        "init",
        "fn",
        "reads",
        "writes",
        "exported",
    )

    def __init__(self, name, kind, declarator=None, init=None, fn=None):
        self.name = name
        self.kind = kind
        self.declarator = declarator
        self.init = init
        self.fn = fn
        self.reads = []
        self.writes = []
        self.exported = False


def parse(src: str) -> dict:
    """ESTree AST of `src`, or Unanalyzable naming why there is none."""
    node = shutil.which("node")
    if not node:
        raise Unanalyzable("node not found on PATH")
    if not os.path.isfile(PARSE_SHIM):
        raise Unanalyzable("parser shim missing")
    env = {k: v for k, v in os.environ.items() if k != "NODE_OPTIONS"}
    try:
        proc = subprocess.run(
            [node, PARSE_SHIM],
            input=src,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=PARSE_TIMEOUT_S,
            env=env,
        )
    except subprocess.TimeoutExpired:
        raise Unanalyzable("parser timed out") from None
    except OSError as exc:
        raise Unanalyzable(f"parser did not start ({type(exc).__name__})") from None
    if proc.returncode != 0:
        raise Unanalyzable(f"parser exited {proc.returncode}")
    try:
        data = json.loads(proc.stdout)
    except ValueError:
        raise Unanalyzable("parser output is not JSON") from None
    if not isinstance(data, dict):
        raise Unanalyzable("parser output is not an AST")
    if "error" in data:
        raise Unanalyzable(f"not parsable as a module: {data['error']}")
    return data


def short(expr: str, width: int = 60) -> str:
    """One-line, length-capped rendering of an expression for messages."""
    flat = " ".join(expr.split())
    return flat if len(flat) <= width else flat[: width - 1] + "…"


def _children(node):
    for key, val in node.items():
        if key[0] == "_":
            continue
        if isinstance(val, dict) and "type" in val:
            yield val
        elif isinstance(val, list):
            for item in val:
                if isinstance(item, dict) and "type" in item:
                    yield item


def _pattern_ids(pattern):
    """Identifier nodes a destructuring pattern binds or assigns."""
    out, stack = [], [pattern]
    while stack:
        p = stack.pop()
        if p is None:
            continue
        t = p["type"]
        if t == "Identifier":
            out.append(p)
        elif t == "ObjectPattern":
            for prop in p["properties"]:
                stack.append(
                    prop["argument"] if prop["type"] == "RestElement" else prop["value"]
                )
        elif t == "ArrayPattern":
            stack.extend(p["elements"])
        elif t == "RestElement":
            stack.append(p["argument"])
        elif t == "AssignmentPattern":
            stack.append(p["left"])
    return out


def _key_name(key, computed):
    """The property name a key or member names statically, else None."""
    if not computed and key["type"] in ("Identifier", "PrivateIdentifier"):
        return ("#" if key["type"] == "PrivateIdentifier" else "") + key["name"]
    if key["type"] == "Literal" and isinstance(key.get("value"), (str, int, float)):
        return str(key["value"])
    return None


def _int_literal(node):
    """The value of a non-negative integer literal, else None."""
    if node is not None and node["type"] == "Literal":
        v = node.get("value")
        if (
            isinstance(v, (int, float))
            and not isinstance(v, bool)
            and v >= 0
            and v == int(v)
        ):
            return int(v)
    return None


class Analysis:
    """Agent count of one parsed script. See the module docstring."""

    def __init__(self, ast: dict, src: str, assumed: int):
        self.src = src
        self.assumed = assumed
        self.labels = []
        self.memo = {}
        self.computing = set()
        self.pending = set()
        self.events = []
        self.steps = 0
        self.nodes = []
        self._index(ast)
        self._utf16 = None
        if any(ord(c) > 0xFFFF for c in src):
            # acorn offsets count UTF-16 code units; Python indexes code points.
            self._utf16 = []
            for i, c in enumerate(src):
                self._utf16.append(i)
                if ord(c) > 0xFFFF:
                    self._utf16.append(i)
            self._utf16.append(len(src))
        self.scopes = {}
        self.decl_ids = set()
        self.ref_binding = {}
        self.members = {}
        self.sites = []
        self._declare_all()
        self._resolve_all()

    # -- infrastructure ---------------------------------------------------

    def _index(self, root):
        stack = [(root, None)]
        while stack:
            node, parent = stack.pop()
            node["_p"] = parent
            node["_i"] = len(self.nodes)
            self.nodes.append(node)
            for child in list(_children(node)):
                stack.append((child, node))

    def _tick(self):
        self.steps += 1
        if self.steps > STEP_BUDGET:
            raise Unanalyzable("analysis step budget exceeded")

    def _cached(self, key, compute):
        if key in self.memo:
            return self.memo[key]
        if key in self.pending:
            # A value that depends on itself outside a function's own count
            # (`function f() { return f() }` returning a function): unbounded.
            return self.unbounded("a value that depends on itself")
        self._tick()
        self.pending.add(key)
        mark = len(self.events)
        try:
            value = compute()
        finally:
            self.pending.discard(key)
        # A value computed while a recursive function's count was pending is
        # partial; keep it only once nothing it read is still pending.
        if not any(t in self.computing for t in self.events[mark:]):
            self.memo[key] = value
        return value

    def text(self, node) -> str:
        lo, hi = node["start"], node["end"]
        if self._utf16 is not None:
            lo, hi = self._utf16[lo], self._utf16[hi]
        return self.src[lo:hi]

    def unbounded(self, label: str, floor: int = 0) -> int:
        """Cost of a repetition whose count the AST does not bound."""
        label = short(label)
        if label not in self.labels:
            self.labels.append(label)
        return max(floor, self.assumed)

    def mult(self, bound: Bound, expr) -> int:
        """Multiplier for iterating `expr`, whose length is `bound`."""
        if bound.n is not None:
            return bound.n
        return self.unbounded(self.text(expr), bound.floor)

    @staticmethod
    def inside(node, ancestor) -> bool:
        while node is not None:
            if node is ancestor:
                return True
            node = node["_p"]
        return False

    @staticmethod
    def enclosing_function(node):
        cur = node["_p"]
        while (
            cur is not None
            and cur["type"] not in FUNCTIONS
            and cur["type"] != "Program"
        ):
            cur = cur["_p"]
        return cur

    # -- scopes -----------------------------------------------------------

    def _scope_of(self, node, types):
        cur = node["_p"]
        while cur is not None and cur["type"] not in types:
            cur = cur["_p"]
        return cur

    def _declare(self, scope, ident, binding):
        names = self.scopes.setdefault(scope["_i"], {})
        self.decl_ids.add(ident["_i"])
        if ident["name"] in names:
            # A redeclaration (`var x` twice) assigns the name again.
            names[ident["name"]].writes.append(ident)
            return
        names[ident["name"]] = binding

    def _declare_all(self):
        for node in self.nodes:
            t = node["type"]
            if t == "VariableDeclaration":
                parent = node["_p"]
                if node["kind"] == "var":
                    scope = self._scope_of(node, FUNCTIONS | {"Program"})
                elif parent["type"] in LOOP_HEADS:
                    scope = parent
                else:
                    scope = self._scope_of(node, BLOCKS)
                exported = parent["type"] == "ExportNamedDeclaration"
                for decl in node["declarations"]:
                    plain = decl["id"]["type"] == "Identifier"
                    for ident in _pattern_ids(decl["id"]):
                        b = Binding(
                            ident["name"],
                            node["kind"] if plain else "pattern",
                            declarator=decl,
                            init=decl["init"] if plain else None,
                        )
                        b.exported = exported
                        self._declare(scope, ident, b)
            elif t in FUNCTIONS:
                if node.get("id"):
                    if t == "FunctionDeclaration":
                        scope = self._scope_of(node, BLOCKS)
                    else:
                        scope = node
                    b = Binding(
                        node["id"]["name"], "function", declarator=node, fn=node
                    )
                    b.exported = node["_p"]["type"] == "ExportNamedDeclaration"
                    self._declare(scope, node["id"], b)
                for param in node["params"]:
                    for ident in _pattern_ids(param):
                        self._declare(node, ident, Binding(ident["name"], "param"))
            elif t in ("ClassDeclaration", "ClassExpression") and node.get("id"):
                scope = (
                    self._scope_of(node, BLOCKS) if t == "ClassDeclaration" else node
                )
                self._declare(scope, node["id"], Binding(node["id"]["name"], "class"))
            elif t == "CatchClause" and node.get("param"):
                for ident in _pattern_ids(node["param"]):
                    self._declare(node, ident, Binding(ident["name"], "catch"))
            elif t in (
                "ImportSpecifier",
                "ImportDefaultSpecifier",
                "ImportNamespaceSpecifier",
            ):
                program = self.nodes[0]
                self._declare(
                    program, node["local"], Binding(node["local"]["name"], "import")
                )

    def _is_reference(self, ident) -> bool:
        if ident["_i"] in self.decl_ids:
            return False
        p = ident["_p"]
        t = p["type"]
        if t == "MemberExpression":
            return p["object"] is ident or p["computed"]
        if t in ("Property", "MethodDefinition", "PropertyDefinition"):
            return p.get("value") is ident or p["computed"]
        if t in (
            "LabeledStatement",
            "BreakStatement",
            "ContinueStatement",
            "MetaProperty",
        ):
            return False
        if t in ("ImportSpecifier", "ExportSpecifier"):
            return p.get("local") is ident and t == "ExportSpecifier"
        return True

    @staticmethod
    def _is_write(ident) -> bool:
        cur = ident
        while True:
            p = cur["_p"]
            t = p["type"]
            if t in ("ArrayPattern", "ObjectPattern", "RestElement"):
                cur = p
            elif t == "AssignmentPattern" and p["left"] is cur:
                cur = p
            elif (
                t == "Property"
                and p["value"] is cur
                and p["_p"]["type"] == "ObjectPattern"
            ):
                cur = p
            else:
                break
        if t == "AssignmentExpression":
            return p["left"] is cur
        if t == "UpdateExpression":
            return True
        if t in ("ForOfStatement", "ForInStatement"):
            return p["left"] is cur
        return False

    def _resolve(self, ident):
        name = ident["name"]
        cur = ident["_p"]
        while cur is not None:
            names = self.scopes.get(cur["_i"])
            if names and name in names:
                return names[name]
            cur = cur["_p"]
        return None

    def _resolve_all(self):
        for node in self.nodes:
            t = node["type"]
            if t == "MemberExpression":
                name = _key_name(node["property"], node["computed"])
                if name is not None:
                    self.members.setdefault(name, []).append(node)
                if name == "agent" and not node["computed"]:
                    call = node["_p"]
                    if call["type"] == "CallExpression" and call["callee"] is node:
                        self.sites.append(("call", call))
            if t != "Identifier" or not self._is_reference(node):
                continue
            binding = self._resolve(node)
            if node["_p"]["type"] == "ExportSpecifier":
                if binding is not None:
                    binding.exported = True
                continue
            write = self._is_write(node)
            if binding is not None:
                self.ref_binding[node["_i"]] = binding
                (binding.writes if write else binding.reads).append(node)
                if node["_p"]["type"] == "UpdateExpression":
                    binding.reads.append(node)
            if node["name"] == "agent" and not write:
                self.sites.append(("ref", node))

    # -- list bounds --------------------------------------------------------

    def same(self, a, b) -> bool:
        """Structural equality of two expressions, positions ignored."""
        if a is None or b is None:
            return a is b
        if a["type"] != b["type"]:
            return False
        if a["type"] == "Identifier":
            if a["name"] != b["name"]:
                return False
            return self.ref_binding.get(a["_i"]) is self.ref_binding.get(b["_i"])
        for key, va in a.items():
            if key[0] == "_" or key in ("start", "end", "raw"):
                continue
            vb = b.get(key)
            if isinstance(va, dict) and "type" in va:
                if not isinstance(vb, dict) or not self.same(va, vb):
                    return False
            elif isinstance(va, list):
                if not isinstance(vb, list) or len(va) != len(vb):
                    return False
                for x, y in zip(va, vb):
                    if isinstance(x, dict) and "type" in x:
                        if not isinstance(y, dict) or not self.same(x, y):
                            return False
                    elif x != y:
                        return False
            elif va != vb:
                return False
        return True

    def binding_of(self, ident):
        if ident is None or ident["type"] != "Identifier":
            return None
        return self.ref_binding.get(ident["_i"])

    def counter(self, loop):
        """(binding, start, cmp, limit, step) of `for (i = a; i < N; i += s)`."""
        init, test, update = loop["init"], loop["test"], loop["update"]
        start = binding = None
        if init is not None and init["type"] == "VariableDeclaration":
            decls = init["declarations"]
            if len(decls) == 1 and decls[0]["id"]["type"] == "Identifier":
                start = _int_literal(decls[0]["init"])
                binding = self.scopes_lookup(decls[0]["id"])
        elif (
            init is not None
            and init["type"] == "AssignmentExpression"
            and init["operator"] == "="
        ):
            start = _int_literal(init["right"])
            binding = self.binding_of(init["left"])
        if binding is None or start is None:
            return None
        if not (
            test is not None
            and test["type"] == "BinaryExpression"
            and test["operator"] in ("<", "<=")
            and self.binding_of(test["left"]) is binding
        ):
            return None
        step = None
        if update is not None:
            ut = update["type"]
            if ut == "UpdateExpression" and update["operator"] == "++":
                if self.binding_of(update["argument"]) is binding:
                    step = {"type": "Literal", "value": 1}
            elif (
                ut == "AssignmentExpression"
                and self.binding_of(update["left"]) is binding
            ):
                if update["operator"] == "+=":
                    step = update["right"]
                elif (
                    update["operator"] == "="
                    and update["right"]["type"] == "BinaryExpression"
                ):
                    r = update["right"]
                    if r["operator"] == "+" and self.binding_of(r["left"]) is binding:
                        step = r["right"]
        # A literal step must be positive; any other step is assumed to be at
        # least 1, which is what makes N (or X's length) an upper bound.
        if step is None or (step["type"] == "Literal" and not _int_literal(step)):
            return None
        if step["type"] == "UnaryExpression" and step["operator"] == "-":
            return None
        # The counter may be written only by its own update (and init).
        for w in binding.writes:
            if not (self.inside(w, update) or self.inside(w, init)):
                return None
        return binding, start, test["operator"], test["right"], step

    def window(self, loop):
        """(binding, X, W) when `loop` is `for (i = 0; i < X.length; i += W)`."""
        c = self.counter(loop)
        if c is None:
            return None
        binding, _start, _cmp, limit, step = c
        # `"start" in step`: a written step, not the 1 that `i++` stands for.
        if (
            limit["type"] == "MemberExpression"
            and not limit["computed"]
            and limit["property"].get("name") == "length"
            and "start" in step
        ):
            return binding, limit["object"], step
        return None

    def is_window_slice(self, call, at) -> bool:
        """`X.slice(i, i + W)` inside the loop that windows X by W."""
        args = call["arguments"]
        if len(args) != 2:
            return False
        binding = self.binding_of(args[0])
        if binding is None or binding.declarator is None:
            return False
        decl_list = binding.declarator["_p"]
        loop = decl_list["_p"] if decl_list else None
        if (
            loop is None
            or loop["type"] != "ForStatement"
            or loop["init"] is not decl_list
        ):
            return False
        w = self.window(loop)
        if w is None or w[0] is not binding:
            return False
        _b, x, step = w
        end = args[1]
        if end["type"] != "BinaryExpression" or end["operator"] != "+":
            return False
        if not (
            (self.binding_of(end["left"]) is binding and self.same(end["right"], step))
            or (
                self.binding_of(end["right"]) is binding
                and self.same(end["left"], step)
            )
        ):
            return False
        if not self.same(call["callee"]["object"], x):
            return False
        # The slice counts once per iteration only where the loop repeats it.
        return at is not None and self.inside(at, loop["body"])

    def bound(self, e, at=None, seen=frozenset()) -> Bound:
        """Upper bound on the length of the list `e` evaluates to."""
        self._tick()
        t = e["type"]
        if t == "ArrayExpression":
            n, floor, exact = 0, 0, True
            for el in e["elements"]:
                if el is not None and el["type"] == "SpreadElement":
                    b = self.bound(el["argument"], at, seen)
                    if b.n is None:
                        exact = False
                        floor += b.floor
                    else:
                        n += b.n
                else:
                    n += 1
            return Bound(n) if exact else Bound(None, n + floor)
        if t == "Identifier":
            return self._bound_name(e, at, seen)
        if t in ("AwaitExpression", "ChainExpression"):
            return self.bound(
                e["argument"] if t == "AwaitExpression" else e["expression"], at, seen
            )
        if t == "SequenceExpression":
            return self.bound(e["expressions"][-1], at, seen)
        if t in ("ConditionalExpression", "LogicalExpression"):
            parts = (
                (e["consequent"], e["alternate"])
                if t == "ConditionalExpression"
                else (e["left"], e["right"])
            )
            bs = [self.bound(p, at, seen) for p in parts]
            if all(b.n is not None for b in bs):
                return Bound(max(b.n for b in bs))
            return Bound(None, max(b.n if b.n is not None else b.floor for b in bs))
        if t == "CallExpression":
            return self._bound_call(e, at, seen)
        return UNBOUNDED

    def _bound_name(self, ident, at, seen) -> Bound:
        b = self.binding_of(ident)
        if b is None or b.kind not in ("const", "let", "var") or b.init is None:
            return UNBOUNDED
        if id(b) in seen or b.writes:
            return UNBOUNDED
        seen = seen | {id(b)}
        grown = False
        for r in b.reads:
            p = r["_p"]
            if p["type"] != "MemberExpression" or p["object"] is not r:
                continue
            gp = p["_p"]
            if p["computed"]:
                if (gp["type"] == "AssignmentExpression" and gp["left"] is p) or gp[
                    "type"
                ] == "UpdateExpression":
                    return UNBOUNDED
                continue
            name = p["property"].get("name")
            if name in ("push", "unshift", "splice") and gp["type"] == "CallExpression":
                grown = grown or gp["callee"] is p
            elif (
                name == "length"
                and gp["type"] == "AssignmentExpression"
                and gp["left"] is p
            ):
                return UNBOUNDED
        base = self.bound(b.init, at, seen)
        if grown:
            # Unbounded, but never below what the declaration already holds
            # plus the push: #2668 read the initializer alone (#2670 round 4).
            return Bound(None, (base.n if base.n is not None else base.floor) + 1)
        return base

    def _bound_call(self, call, at, seen) -> Bound:
        callee, args = call["callee"], call["arguments"]
        if callee["type"] != "MemberExpression" or callee["computed"]:
            return UNBOUNDED
        name = callee["property"].get("name")
        obj = callee["object"]
        if (
            obj["type"] == "Identifier"
            and obj["name"] == "Array"
            and name == "from"
            and args
        ):
            return self.array_like(args[0], at, seen)
        if (
            obj["type"] == "Identifier"
            and obj["name"] == "Object"
            and name in ("keys", "values", "entries")
        ):
            if args and args[0]["type"] == "ObjectExpression":
                props = args[0]["properties"]
                if all(p["type"] == "Property" for p in props):
                    return Bound(len(props))
            return UNBOUNDED
        if name == "slice":
            if self.is_window_slice(call, at):
                return Bound(1)
            if len(args) == 2:
                lo, hi = _int_literal(args[0]), _int_literal(args[1])
                if lo is not None and hi is not None:
                    return Bound(max(0, hi - lo))
            return self.bound(obj, at, seen)
        if name in LENGTH_KEEPING:
            return self.bound(obj, at, seen)
        if name == "flat":
            b = self.bound(obj, at, seen)
            return Bound(None, b.n if b.n is not None else b.floor)
        if name == "concat":
            parts = [self.bound(obj, at, seen)]
            for a in args:
                parts.append(
                    UNBOUNDED
                    if a["type"] == "SpreadElement"
                    else self.bound(a, at, seen)
                )
            if all(p.n is not None for p in parts):
                return Bound(sum(p.n for p in parts))
            return Bound(None, sum(p.n if p.n is not None else p.floor for p in parts))
        return UNBOUNDED

    def array_like(self, arg, at, seen) -> Bound:
        """Length of `Array.from`'s first argument."""
        if arg["type"] == "ObjectExpression":
            for p in arg["properties"]:
                if (
                    p["type"] == "Property"
                    and not p["computed"]
                    and (
                        p["key"].get("name") == "length"
                        or p["key"].get("value") == "length"
                    )
                ):
                    n = _int_literal(p["value"])
                    return Bound(n) if n is not None else UNBOUNDED
            return UNBOUNDED
        return self.bound(arg, at, seen)

    # -- how often a position runs -----------------------------------------

    def count(self, node) -> int:
        """How many times the program evaluates `node`."""
        return self._cached(("count", node["_i"]), lambda: self._count(node))

    def _count(self, node) -> int:
        repeats = []
        cur = node
        while True:
            parent = cur["_p"]
            if parent is None:
                base = 1
                break
            t = parent["type"]
            if t in FUNCTIONS:
                base = self.inv(parent)
                break
            if t == "ForStatement":
                if (
                    cur is parent["body"]
                    or cur is parent["test"]
                    or cur is parent["update"]
                ):
                    repeats.append(parent)
            elif t in ("ForOfStatement", "ForInStatement"):
                if cur is parent["body"] or cur is parent["left"]:
                    repeats.append(parent)
            elif t in ("WhileStatement", "DoWhileStatement"):
                if cur is parent["body"] or cur is parent["test"]:
                    repeats.append(parent)
            elif (
                t == "ClassBody"
                and cur["type"] == "PropertyDefinition"
                and not cur["static"]
            ):
                repeats.append(cur)
            cur = parent
        if base == 0:
            return 0
        for loop in repeats:
            base *= self.loop_factor(loop)
        return base

    def loop_factor(self, loop) -> int:
        return self._cached(
            ("loop", loop["_i"]), lambda: max(1, self._loop_factor(loop))
        )

    def _loop_factor(self, loop) -> int:
        t = loop["type"]
        if t == "PropertyDefinition":
            return self.unbounded("a class field initializer")
        if t == "ForOfStatement":
            return self.mult(self.bound(loop["right"], loop), loop["right"])
        if t == "ForInStatement":
            right = loop["right"]
            if right["type"] == "ObjectExpression" and all(
                p["type"] == "Property" for p in right["properties"]
            ):
                return len(right["properties"])
            return self.unbounded(f"for...in {self.text(right)}")
        if t == "ForStatement":
            c = self.counter(loop)
            if c is not None:
                _b, start, cmp, limit, step = c
                inclusive = 1 if cmp == "<=" else 0
                literal_step = _int_literal(step) or 1
                n = _int_literal(limit)
                if n is None and limit["type"] == "Identifier":
                    b = self.binding_of(limit)
                    if b is not None and b.kind == "const" and not b.writes:
                        n = _int_literal(b.init)
                if n is not None:
                    return math.ceil(max(0, n - start + inclusive) / literal_step)
                if (
                    limit["type"] == "MemberExpression"
                    and not limit["computed"]
                    and limit["property"].get("name") == "length"
                ):
                    b = self.bound(limit["object"], loop)
                    if b.n is not None:
                        return b.n + inclusive
                    return self.unbounded(
                        self.text(limit["object"]), b.floor + inclusive
                    )
            return self.unbounded(
                "a for loop with no static bound", self.stated_limit(loop)
            )
        n = self.while_counter(loop)
        if n is not None:
            return n
        return self.unbounded(
            "a while loop" if t == "WhileStatement" else "a do...while loop",
            self.stated_limit(loop),
        )

    def stated_limit(self, loop) -> int:
        """The literal a refused loop's test compares against (`i < 12`), or 0.

        Not a bound -- the counter may move any way -- but a loop that states
        12 is not costed at 8: the figure is a floor under ASSUMED's guess.
        """
        test = loop.get("test")
        if test is None or test["type"] != "BinaryExpression":
            return 0
        if test["operator"] in ("<", "<="):
            side = test["right"]
        elif test["operator"] in (">", ">="):
            side = test["left"]
        else:
            return 0
        n = _int_literal(side)
        return (
            n + (1 if test["operator"] in ("<=", ">=") else 0) if n is not None else 0
        )

    def while_counter(self, loop):
        """Iterations of `while (i < N) { ...; i++ }` with N a literal, else None.

        Sound only when every pass runs the increment: it must be a statement
        of the body itself (not inside an `if`), nothing may `continue` past
        it, and nothing else may write the counter.
        """
        test, body = loop["test"], loop["body"]
        if not (
            test["type"] == "BinaryExpression"
            and test["operator"] in ("<", "<=")
            and test["left"]["type"] == "Identifier"
            and body["type"] == "BlockStatement"
        ):
            return None
        b = self.binding_of(test["left"])
        if b is None or b.kind not in ("let", "var") or b.init is None:
            return None
        start = _int_literal(b.init)
        limit = _int_literal(test["right"])
        if start is None or limit is None:
            return None
        steps = []
        for stmt in body["body"]:
            e = stmt["expression"] if stmt["type"] == "ExpressionStatement" else None
            if e is None:
                continue
            if e["type"] == "UpdateExpression" and e["operator"] == "++":
                target, step = e["argument"], 1
            elif e["type"] == "AssignmentExpression" and e["operator"] == "+=":
                target, step = e["left"], _int_literal(e["right"])
            else:
                continue
            if self.binding_of(target) is b and step:
                steps.append((target, step))
        if not steps:
            return None
        if not all(any(w is t for t, _ in steps) for w in b.writes):
            return None
        for n in self.nodes:
            if n["type"] == "ContinueStatement" and self.inside(n, body):
                return None
        inclusive = 1 if test["operator"] == "<=" else 0
        n = math.ceil(max(0, limit - start + inclusive) / sum(s for _, s in steps))
        return max(n, 1) if loop["type"] == "DoWhileStatement" else n

    def inv(self, fn) -> int:
        """How many times the function `fn` is invoked."""
        key = ("inv", fn["_i"])
        if key in self.memo:
            return self.memo[key]
        i = fn["_i"]
        if i in self.computing:
            # Reached again while its own count is pending: recursion.
            self.events.append(i)
            return 0
        self._tick()
        self.computing.add(i)
        mark = len(self.events)
        try:
            raw = self._raw_inv(fn)
        finally:
            self.computing.discard(i)
        later = self.events[mark:]
        if i in later:
            # One entry plus ASSUMED re-entries per entry: the depth of a
            # recursion over an ASSUMED-long list.
            raw = max(raw, 1) * (1 + self.assumed)
            self.unbounded(f"recursion through {self.fn_name(fn)}")
        if not any(t in self.computing for t in later):
            self.memo[key] = raw
        return raw

    def by_name(self, prop, creations) -> int:
        """Invocations of a function reached only through the key of `prop`.

        Its callers are property reads (`o.run(f)`, a getter's `o.run`), which
        the parse does not resolve to an object, so it is unbounded: ASSUMED
        per function created. Every such read names the key, though, so the
        reads of that name are evidence too, and the larger figure is kept: a
        method a 12-pass loop calls costs 12, not 8.
        """
        guess = creations * self.unbounded(
            "a method, getter, setter or property function"
        )
        if prop["type"] == "MethodDefinition" and prop["kind"] == "constructor":
            cls = prop["_p"]["_p"]
            name = cls["id"]["name"] if cls.get("id") else None
            evidence = sum(
                self.count(n)
                for n in self.nodes
                if n["type"] == "NewExpression"
                and n["callee"]["type"] == "Identifier"
                and n["callee"]["name"] == name
            )
            return max(guess, evidence)
        name = _key_name(prop["key"], prop["computed"])
        if name is None:
            return guess
        return max(guess, sum(self.count(m) for m in self.members.get(name, [])))

    def fn_name(self, fn) -> str:
        if fn.get("id"):
            return fn["id"]["name"]
        p = fn["_p"]
        if p["type"] == "VariableDeclarator" and p["id"]["type"] == "Identifier":
            return p["id"]["name"]
        return "an anonymous function"

    def _raw_inv(self, fn) -> int:
        parent = fn["_p"]
        total = 0
        if fn["type"] == "FunctionDeclaration":
            if parent["type"] == "ExportDefaultDeclaration":
                total += 1  # the entry point the runtime calls
        elif parent["type"] == "MethodDefinition" or (
            parent["type"] == "Property"
            and parent["value"] is fn
            and (parent["method"] or parent["kind"] in ("get", "set"))
        ):
            c = self.count(fn)
            return c and self.by_name(parent, c)
        else:
            c = self.count(fn)
            if c:
                total += c * self.calls_per_eval(fn)
        if fn.get("id"):
            binding = self.scopes.get(
                (
                    fn
                    if fn["type"] != "FunctionDeclaration"
                    else self._scope_of(fn, BLOCKS)
                )["_i"],
                {},
            ).get(fn["id"]["name"])
            if binding is not None and binding.fn is fn:
                for r in binding.reads:
                    c = self.count(r)
                    if c:
                        total += c * self.calls_per_eval(r)
                if binding.exported:
                    total += self.unbounded(f"exported function {binding.name}")
        return total

    # -- where a function value goes ----------------------------------------

    def calls_per_eval(self, n) -> int:
        """Calls made to the function value `n` evaluates to, per evaluation."""
        return self._cached(("calls", n["_i"]), lambda: self._calls_per_eval(n))

    def _calls_per_eval(self, n) -> int:
        p = n["_p"]
        t = p["type"]
        if t in ("CallExpression", "NewExpression") and p["callee"] is n:
            return 1
        if t == "TaggedTemplateExpression" and p["tag"] is n:
            return 1
        if t == "CallExpression":
            return self._as_argument(n, p)
        if t == "NewExpression":
            callee = p["callee"]
            if (
                callee["type"] == "Identifier"
                and callee["name"] == "Promise"
                and p["arguments"][:1] == [n]
            ):
                return 1
            return self.unbounded(f"a function passed to new {self.text(callee)}()")
        if t == "ArrayExpression":
            return self.elem_calls(p)
        if t == "VariableDeclarator" and p["init"] is n:
            if p["id"]["type"] == "Identifier":
                return self.var_calls(self.scopes_lookup(p["id"]), p, elem=False)
            return self.unbounded("a destructured function")
        if t == "AssignmentExpression" and p["right"] is n:
            b = self.binding_of(p["left"])
            if b is not None and p["operator"] == "=":
                return self.var_calls(b, p, elem=False)
            return self.unbounded(f"a function assigned to {self.text(p['left'])}")
        if t == "ReturnStatement":
            return self.ret_calls(self.enclosing_function(p), elem=False)
        if t == "ArrowFunctionExpression" and p["body"] is n:
            return self.ret_calls(p, elem=False)
        if t == "ConditionalExpression":
            return 0 if p["test"] is n else self.calls_per_eval(p)
        if t in ("LogicalExpression", "AwaitExpression", "ChainExpression"):
            return self.calls_per_eval(p)
        if t == "SequenceExpression":
            return self.calls_per_eval(p) if p["expressions"][-1] is n else 0
        if t in ("ExpressionStatement", "BinaryExpression", "TemplateLiteral"):
            return 0
        if t == "UnaryExpression" and p["operator"] in (
            "typeof",
            "void",
            "!",
            "delete",
        ):
            return 0
        if (
            t in ("IfStatement", "WhileStatement", "DoWhileStatement", "ForStatement")
            and p.get("test") is n
        ):
            return 0
        if t == "MemberExpression" and p["object"] is n and not p["computed"]:
            name = p["property"].get("name")
            gp = p["_p"]
            called = gp["type"] == "CallExpression" and gp["callee"] is p
            if name in ("call", "apply") and called:
                return 1
            if name == "bind" and called:
                return self.calls_per_eval(gp)
            if name in ("length", "name"):
                return 0
        if t == "ExportDefaultDeclaration":
            return 1
        if (
            t == "Property"
            and p["value"] is n
            and p["_p"]["type"] == "ObjectExpression"
        ):
            obj = p["_p"]
            decl = obj["_p"]
            if (
                decl["type"] == "VariableDeclarator"
                and decl["init"] is obj
                and decl["id"]["type"] == "ObjectPattern"
            ):
                return self._destructured(
                    decl, _key_name(p["key"], p["computed"]), elem=False
                )
            c = self.count(n)
            return c and math.ceil(self.by_name(p, c) / c)
        return self.unbounded(f"a function used as {t}")

    def _destructured(self, decl, name, elem) -> int:
        """Calls to a value `const { name } = {...}` or `const [a] = [...]` binds."""
        targets = []
        pattern = decl["id"]
        if pattern["type"] == "ObjectPattern":
            for prop in pattern["properties"]:
                if prop["type"] == "RestElement" or name is None:
                    return self.unbounded("a destructured function")
                if _key_name(prop["key"], prop["computed"]) == name:
                    targets.append(prop["value"])
        else:
            targets = [e for e in pattern["elements"] if e is not None]
        worst = 0
        for target in targets:
            if target["type"] == "AssignmentPattern":
                target = target["left"]
            if (
                target["type"] == "RestElement"
                and target["argument"]["type"] == "Identifier"
            ):
                b = self.scopes_lookup(target["argument"])
                worst = max(worst, self.var_calls(b, decl, elem=True))
            elif target["type"] == "Identifier":
                worst = max(
                    worst, self.var_calls(self.scopes_lookup(target), decl, elem=elem)
                )
            else:
                return self.unbounded("a destructured function")
        return worst

    def _as_argument(self, n, call) -> int:
        args = call["arguments"]
        idx = next((k for k, a in enumerate(args) if a is n), -1)
        callee = call["callee"]
        if callee["type"] == "MemberExpression" and not callee["computed"]:
            name = callee["property"].get("name")
            obj = callee["object"]
            if idx == 0 and name in PER_ELEMENT:
                return self.mult(self.bound(obj, call), obj)
            if idx == 0 and name in ("sort", "toSorted"):
                n = self.mult(self.bound(obj, call), obj)
                return n * n  # a comparison sort compares fewer pairs than n squared
            if (
                name == "then"
                and idx in (0, 1)
                or name in ("catch", "finally")
                and idx == 0
            ):
                return 1  # a promise settles once
            if (
                obj["type"] == "Identifier"
                and obj["name"] == "Array"
                and name == "from"
                and idx == 1
            ):
                return self.mult(self.array_like(args[0], call, frozenset()), args[0])
        if callee["type"] == "Identifier" and callee["name"] == "pipeline" and idx >= 1:
            return self.mult(self.bound(args[0], call), args[0])
        via_param = self.param_calls(call, idx, elem=False)
        if via_param is not None:
            return via_param
        return self.unbounded(f"a function passed to {self.text(callee)}()")

    def reads_arguments(self, fn) -> bool:
        """True when `fn` can reach its arguments other than by parameter."""
        key = ("arguments", fn["_i"])
        if key not in self.memo:
            self.memo[key] = any(
                n["type"] == "Identifier"
                and n["name"] == "arguments"
                and self.inside(n, fn)
                for n in self.nodes
            )
        return self.memo[key]

    def callee_function(self, callee):
        """The function a plain-name callee always refers to, else None."""
        b = self.binding_of(callee)
        if b is None or b.writes:
            return None
        if b.kind == "function" and b.fn is not None:
            return b.fn
        if b.kind == "const" and b.init is not None and b.init["type"] in FUNCTIONS:
            return b.init
        return None

    def param_calls(self, call, idx, elem):
        """Calls per evaluation of `call` to what its argument `idx` passes.

        A helper the script defines (`retry(fn)`) calls its parameter where its
        body says so. Every call through that parameter, over all of the
        helper's invocations, is charged to each call site that passes a
        function in -- an upper bound when several sites share the helper.
        """
        target = self.callee_function(call["callee"])
        if target is None or idx < 0 or self.reads_arguments(target):
            return None
        params = target["params"]
        if idx >= len(params):
            return 0
        param = params[idx]
        if param["type"] == "AssignmentPattern":
            param = param["left"]
        if param["type"] != "Identifier":
            return None
        b = self.scopes_lookup(param)
        if b is None:
            return None
        total = 0
        for r in b.reads:
            c = self.count(r)
            if c:
                total += c * (self.elem_calls(r) if elem else self.calls_per_eval(r))
        return math.ceil(total / max(self.count(call), 1))

    def scopes_lookup(self, ident):
        """The binding a declaration identifier introduced."""
        cur = ident["_p"]
        while cur is not None:
            names = self.scopes.get(cur["_i"])
            if names and ident["name"] in names:
                return names[ident["name"]]
            cur = cur["_p"]
        return None

    def var_calls(self, binding, at, elem) -> int:
        """Calls per evaluation of `at` to what it stores in `binding`."""
        if binding is None:
            return self.unbounded("a function stored out of scope")
        total = 0
        for r in binding.reads:
            c = self.count(r)
            if c:
                total += c * (self.elem_calls(r) if elem else self.calls_per_eval(r))
        if binding.exported:
            total += self.unbounded(f"exported binding {binding.name}")
        return math.ceil(total / max(self.count(at), 1))

    def elem_calls(self, a) -> int:
        """Calls made to each function in the array `a` evaluates to."""
        return self._cached(("elem", a["_i"]), lambda: self._elem_calls(a))

    def _elem_calls(self, a) -> int:
        p = a["_p"]
        t = p["type"]
        if t == "CallExpression":
            callee = p["callee"]
            if any(x is a for x in p["arguments"]):
                if (
                    callee["type"] == "Identifier"
                    and callee["name"] == "parallel"
                    and p["arguments"][0] is a
                ):
                    return 1  # parallel() calls each thunk once
                if (
                    callee["type"] == "MemberExpression"
                    and not callee["computed"]
                    and callee["property"].get("name") == "concat"
                ):
                    return self.elem_calls(p)
                idx = next(k for k, x in enumerate(p["arguments"]) if x is a)
                via_param = self.param_calls(p, idx, elem=True)
                if via_param is not None:
                    return via_param
                return self.unbounded(f"functions passed to {self.text(callee)}()")
        if t == "MemberExpression" and p["object"] is a:
            if p["computed"]:
                return self.calls_per_eval(p)  # one element per read
            name = p["property"].get("name")
            if name == "length":
                return 0
            gp = p["_p"]
            if gp["type"] == "CallExpression" and gp["callee"] is p:
                if name in ("concat", "slice", "reverse", "toReversed", "flat"):
                    return self.elem_calls(gp)
                if name in ("at", "pop", "shift"):
                    return self.calls_per_eval(gp)
            return self.unbounded(f"functions read through .{name}")
        if t == "SpreadElement" and p["_p"]["type"] == "ArrayExpression":
            return self.elem_calls(p["_p"])
        if t == "ForOfStatement" and p["right"] is a:
            # Each pass binds one element; it is called as often per pass as
            # the loop variable is.
            left = p["left"]
            if left["type"] == "VariableDeclaration" and len(left["declarations"]) == 1:
                left = left["declarations"][0]["id"]
            b = self.scopes_lookup(left) if left["type"] == "Identifier" else None
            if b is not None and not b.writes:
                total = 0
                for r in b.reads:
                    c = self.count(r)
                    if c:
                        total += c * self.calls_per_eval(r)
                return math.ceil(total / max(self.count(p["body"]), 1))
            return self.unbounded("functions bound by a for...of")
        if t == "VariableDeclarator" and p["init"] is a:
            if p["id"]["type"] == "Identifier":
                return self.var_calls(self.scopes_lookup(p["id"]), p, elem=True)
            if p["id"]["type"] == "ArrayPattern" and a["type"] == "ArrayExpression":
                return self._destructured(p, None, elem=False)
            return self.unbounded("destructured functions")
        if t == "AssignmentExpression" and p["right"] is a:
            b = self.binding_of(p["left"])
            if b is not None and p["operator"] == "=":
                return self.var_calls(b, p, elem=True)
            return self.unbounded(f"functions assigned to {self.text(p['left'])}")
        if t == "ReturnStatement":
            return self.ret_calls(self.enclosing_function(p), elem=True)
        if t == "ArrowFunctionExpression" and p["body"] is a:
            return self.ret_calls(p, elem=True)
        if t == "ConditionalExpression" and p["test"] is not a:
            return self.elem_calls(p)
        if t in ("LogicalExpression", "AwaitExpression", "ChainExpression"):
            return self.elem_calls(p)
        if t == "SequenceExpression":
            return self.elem_calls(p) if p["expressions"][-1] is a else 0
        if t == "ExpressionStatement":
            return 0
        return self.unbounded(f"functions held in {t}")

    def ret_calls(self, fn, elem) -> int:
        """Calls per invocation of `fn` to the function(s) it returns."""
        return self._cached(("ret", fn["_i"], elem), lambda: self._ret_calls(fn, elem))

    def _ret_calls(self, fn, elem) -> int:
        if fn["type"] == "Program":
            return self.unbounded("a function the script returns")
        worst = 0
        for kind, node in self.result_uses(fn):
            if kind == "value":
                k = self.elem_calls(node) if elem else self.calls_per_eval(node)
            elif kind in ("map", "flatMap"):
                if elem and kind == "map":
                    k = self.unbounded("arrays of functions a .map returns")
                else:
                    k = self.elem_calls(node)
            elif kind == "none":
                k = 0
            else:
                k = self.unbounded(node)
            worst = max(worst, k)
        return worst

    def result_uses(self, fn):
        """Where `fn`'s return value goes, one entry per way it is invoked."""
        positions = []
        if fn["type"] == "FunctionDeclaration":
            if fn["_p"]["type"] == "ExportDefaultDeclaration":
                return [("unknown", "the entry point's return value")]
        else:
            positions.append(fn)
        if fn.get("id"):
            b = self.scopes_lookup(fn["id"])
            if b is not None and b.fn is fn:
                positions.extend(b.reads)
        uses = []
        for pos in positions:
            uses.extend(self._value_uses(pos, 0))
        return uses

    def _value_uses(self, pos, depth):
        if depth > 16:
            return [("unknown", "a function passed through many names")]
        p = pos["_p"]
        t = p["type"]
        if t == "CallExpression" and p["callee"] is pos:
            return [("value", p)]
        if t == "CallExpression":
            callee = p["callee"]
            idx = next((k for k, a in enumerate(p["arguments"]) if a is pos), -1)
            if callee["type"] == "MemberExpression" and not callee["computed"]:
                name = callee["property"].get("name")
                obj = callee["object"]
                if idx == 0 and name in ("map", "flatMap"):
                    return [(name, p)]
                if idx == 0 and name in TESTED_RESULT:
                    return [("none", None)]
                if (
                    name == "then"
                    and idx in (0, 1)
                    or name in ("catch", "finally")
                    and idx == 0
                ):
                    return [("value", p)]
                if (
                    obj["type"] == "Identifier"
                    and obj["name"] == "Array"
                    and name == "from"
                    and idx == 1
                ):
                    return [("map", p)]
            return [
                ("unknown", f"the result of a function passed to {self.text(callee)}()")
            ]
        if (
            t == "NewExpression"
            and p["callee"]["type"] == "Identifier"
            and p["callee"]["name"] == "Promise"
        ):
            return [("none", None)]
        if (
            t == "VariableDeclarator"
            and p["init"] is pos
            and p["id"]["type"] == "Identifier"
        ):
            b = self.scopes_lookup(p["id"])
            if b is not None and not b.exported:
                uses = []
                for r in b.reads:
                    uses.extend(self._value_uses(r, depth + 1))
                return uses
        if t in (
            "ConditionalExpression",
            "LogicalExpression",
            "AwaitExpression",
            "ChainExpression",
        ):
            if not (t == "ConditionalExpression" and p["test"] is pos):
                return self._value_uses(p, depth + 1)
            return [("none", None)]
        if t in (
            "ExpressionStatement",
            "BinaryExpression",
            "TemplateLiteral",
            "UnaryExpression",
        ):
            return [("none", None)]
        return [("unknown", f"the result of a function used as {t}")]

    # -- the estimate --------------------------------------------------------

    def site_count(self, kind, node) -> int:
        p = node["_p"]
        if kind == "call":
            return self.count(node)
        if (
            p["type"] in ("CallExpression", "NewExpression") and p["callee"] is node
        ) or (p["type"] == "TaggedTemplateExpression" and p["tag"] is node):
            return self.count(p)
        # `agent` passed on as a value (`xs.map(agent)`) runs where it goes.
        c = self.count(node)
        return c and c * self.calls_per_eval(node)

    def run(self, limit: int) -> dict:
        if not self.sites:
            return {
                "VERDICT": "NO_AGENTS",
                "SITES": 0,
                "LIMIT": limit,
                "DETAIL": "no agent() call sites found",
            }
        # Source order, so SOURCE names the first unbounded repetitions read.
        self.sites.sort(key=lambda site: site[1]["start"])
        estimate = sum(self.site_count(kind, node) for kind, node in self.sites)
        result = {
            "VERDICT": "OVER_LIMIT" if estimate > limit else "OK",
            "SITES": len(self.sites),
            "ESTIMATE": estimate,
            "LIMIT": limit,
        }
        if self.labels:
            result["ASSUMED"] = self.assumed
            result["SOURCE"] = ", ".join(self.labels[:2])
            result["DETAIL"] = (
                f"~{estimate} agents across {len(self.sites)} call site(s); "
                f"{len(self.labels)} repetition(s) have no static bound "
                f"({result['SOURCE']}) and were costed at {self.assumed} each"
            )
        else:
            result["DETAIL"] = (
                f"{estimate} agents across {len(self.sites)} call site(s)"
            )
        return result


def _load_fallback():
    spec = importlib.util.spec_from_file_location(
        "workflow_scale_2668", FALLBACK_ESTIMATOR
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def analyze(src: str, limit: int, assumed: int = 8) -> dict:
    """Estimate from the parse, or from #2668 when the parse cannot decide."""
    # The walk recurses once per function and per variable a function value
    # passes through; deeply nested scripts need more than the default 1000.
    sys.setrecursionlimit(max(sys.getrecursionlimit(), 4000))
    try:
        result = Analysis(parse(src), src, assumed).run(limit)
        result["PARSER"] = "acorn"
    except Unanalyzable as exc:
        reason = str(exc)
    except RecursionError:
        reason = "analysis recursion limit"
    except Exception as exc:  # noqa: BLE001 - a bug here must cost like #2668, not crash
        reason = f"analysis error ({type(exc).__name__})"
    else:
        name_match = re.search(r"\bname:\s*['\"]([^'\"]+)['\"]", src)
        if name_match:
            result["NAME"] = name_match.group(1)
        return result
    result = _load_fallback().analyze(src, limit, assumed)
    result["PARSER"] = "fallback"
    result["FALLBACK"] = short(f"{reason}; the #2668 estimator decided", 200)
    return result


def main() -> int:
    limit, assumed = 10, 8
    if len(sys.argv) > 1:
        try:
            limit = int(sys.argv[1])
        except ValueError:
            pass
    if len(sys.argv) > 2:
        try:
            assumed = int(sys.argv[2])
        except ValueError:
            pass
    try:
        src = sys.stdin.buffer.read().decode("utf-8", "replace")
    except Exception:  # noqa: BLE001 - fail open
        return 0
    try:
        result = analyze(src, limit, assumed)
    except Exception as exc:  # noqa: BLE001 - fail open: an unparsable script is not a block
        print("VERDICT=ERROR")
        print(f"DETAIL=analyzer error: {type(exc).__name__}")
        return 0
    for key in (
        "VERDICT",
        "NAME",
        "SITES",
        "ESTIMATE",
        "LIMIT",
        "ASSUMED",
        "SOURCE",
        "PARSER",
        "FALLBACK",
        "DETAIL",
    ):
        if key in result:
            print(f"{key}={result[key]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

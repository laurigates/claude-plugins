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
    HIGH=<int>             what a repetition nothing bounds was costed at (if any)
    UNBOUNDED=<expr>       the first such repetitions
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
where it goes, destructuring and a const alias included), a function passed to
a helper the script defines as often as the helper calls that parameter --
through a rest parameter (`(...fns) =>`) as often as the helper calls each
element, through a template tag's substitutions, `.call` and `.apply`
likewise, and from a spread (or after one) as often as the most-called
parameter it may land in -- an element of an array of functions as often as an
inline or named `.map`/`forEach`/`filter`/... callback calls the parameter it
arrives in, plus every call through the array the callback is handed after the
index (`(f, i, arr) => arr[i]()` may reach any element), a class's constructor
and instance fields once per `new` of it or of a subclass, a getter or method
once per read of its name (a destructuring of it included, and the key
`Object.defineProperty` gives a descriptor), a default-parameter function as
often as the body calls that parameter, a function stored in a named object or
`Map` as often as its key, `this.key` or `m.get()` is called, and a function
that reaches itself again is recursive: a tree whose entries each call the
function as often as its body does, to the depth the text proves -- one
parameter every outside call gives a number, stepped by a constant toward a
test that stops the recursive calls (`if (d < 3) rec(d + 1)`, or
`if (n <= 0) return` ahead of them) -- or else to ASSUMED levels or the larger
count its parameters are given or compared with. A function declared in a
block is also reached by calls after the block (Annex B of ECMA-262, which
applies if the runtime runs the script as sloppy code).

Loops multiply by their bound: `for...of` by its list, `for (i = a; i < N;
i += s)` by (N - a) / s (a, N and s literal, arithmetic of literals, or a
const holding one; a fractional one costs a pass more), `for (i = a; i <
X.length; i += W)` by X - a (and a `X.slice(i, i + W)` consumed inside it
counts 1 per pass, so the pair is X in total), `for...in` by an array's length
or a named object's keys, `while (i < N) { ...; i++ }` by N when every pass
runs the increment, and any other `while`/`do`/`for` by ASSUMED, or by the
count its test states if that is larger: a literal on either side
(`i !== 12`), the literal a compared name was given or assigned
(`for (let i = 12; i > 0; i--)`, `for (let i = 12; i--;)`, `let n = 12;
while (n-- > 0)`, a helper's `n` that a plain call passes 12 or defaults to),
divided by a `for` update's literal step on that name unless the body also
writes it. A loop only a `break` leaves (`while (true)`, `for (;;)`) states
the count its break's test does (`if (++n >= 12) break`: 13).

Anything this cannot bound is costed as unbounded, never as once. ASSUMED
items (default 8), or more where a floor is known, for what repeats over
runtime data: a method, getter, setter or a function stored in an object the
parse does not follow (the reads of its name set a floor), a function read out
of an array other than by `parallel()`, an index, a `for...of` or an
array-method callback, a class field or constructor where some instance is
made without naming the class, and any callback of a call not listed above.
HIGH -- one over the limit, never below ASSUMED -- for a repetition the parse
recognises and nothing in the text bounds: a loop only a `break` leaves whose
break states no count, a loop that moves its counter back, resets it, only
moves it away from its limit, raises its limit, or grows the list it runs
over, an object with a hand-built iterator, and a method the language calls
with no visible call (`toString`, `valueOf`, `toJSON`, `then`, `[Symbol.*]`).
HIGH makes the guard ask; it is not a bound. That split is deliberate. One
agent per runtime item passes a limit of 10; two per item, or a fan-out nested
in another, does not -- which is where a runaway comes from -- and a loop that
nothing in its text ends is worth a question whatever it runs over.

What bounds a list: a literal array (holes count, a trailing comma does not), a
literal `.slice(a, b)`, `Array.from({ length: N })`, `Array(N)`, `new Array(N)`,
`Array(a, b, ...)` and `Array.of`, `new Set(X)` (at most X), a string (by
character), a literal string's `split` on a literal separator (a regex one at
most (length + 1) x (1 + its groups)), `.flat()` of literal lists, a `flatMap`
callback returning literal lists, `Object.keys`/`values`/`entries` of an
object nothing adds keys to, a generator's yields (each `yield` times the
loops around it, a `yield*` the length it delegates), a const bound to one of
those, a rest parameter of a function every reference to which is a plain call
(the most arguments a call passes it), and length-keeping or shrinking methods
of a bounded list (`map`, `filter`, `fill`, `keys`, `values`, `entries`, ...).
An array grown by `push`/`unshift`/`splice`, a Set grown by `add`, or an
object a method or a write may add keys to, is unbounded but costed at no less
than its initializer plus one. A loop window `.slice(i, i + WAVE)` is NOT a
bound on its own: it bounds concurrency, and the loop around it repeats it
(#2670).

Fallback. When the parse cannot run -- no `node` on PATH, a script acorn
rejects, a timeout, or an error in the analysis below -- the #2668 estimator
(lib/workflow-scale-estimate-2668.py, frozen: what main shipped before #2670)
decides, and the rollup says so (`PARSER=fallback`, `FALLBACK=<reason>`). It
asks more than the parse on a literal array, whose every thunk it multiplies by
the array's length, and less on loops, recursion and `agent?.()`, which it does
not see; it is the baseline the review rounds of #2670 were judged against.

What the parse still cannot bound, all fail-open:
  - Lists whose length is only known at runtime are costed at ASSUMED. That is
    a convention, not a bound: a run over 20 items creates more than this says.
    The same holds for every repetition costed at ASSUMED above, including ones
    whose script states a larger count in a form this does not read, among
    them (as of round 11): an array grown by index assignment (pinned as a
    known gap in the test); a class also built without naming it
    (`new this.constructor()`, `new.target`, `Reflect.construct`, a factory's
    parameter, an alias); a getter read through object spread or
    `Object.assign`, or given by `defineProperty` a key that is not a literal;
    a function stored where the parse does not follow it (an array in an
    array, an object or Map passed on, iterated or read through
    `Object.values`); keys added to an object by assignment, `Object.assign`
    or a function it is passed to; `.flat()` deeper than one level or of a
    list that is not literal, and a `flatMap` callback returning a parameter;
    a generator that delegates to itself; `for...in` over an object with a
    `__proto__`; a counter started from a parameter, or assigned before a
    `while`; a `while (X.length)` that drains X; a template tag read through
    a member or stored and called later; and several copies of one runtime
    list (`[...units, ...units]`), costed at ASSUMED once, not per copy.
  - A repetition costed at HIGH asks, but its count may exceed HIGH: a
    `while (true)` polling loop that runs 20 times is costed at 11.
  - An array mutated through an alias, or by a function it is passed to, keeps
    its declared length; a loop window assumes a step of at least 1 and a list
    the loop body does not change.
  - `workflow()` children, `eval`/`new Function`, and `agent` reached through a
    computed property (`ctx["agent"]`) are not counted.
  - Over-counts, which ask more than needed: a call through a callback's array
    parameter is charged to every element, a function whose result a template
    tag uses and a rest list of a helper that is also passed on as a value are
    each costed at ASSUMED, an unproven recursion with two calls per entry is
    a tree ASSUMED levels deep (511 entries), and two block functions of one
    name are each charged every call of the name.
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
# Methods that keep (or shrink) the list they are called on. `keys`, `values`
# and `entries` iterate an array's indexes; on anything else the receiver's own
# bound is already unbounded.
LENGTH_KEEPING = frozenset(
    {
        "filter",
        "map",
        "reverse",
        "sort",
        "toSorted",
        "toReversed",
        "fill",
        "keys",
        "values",
        "entries",
    }
)
# Methods the language calls without a visible call site: string conversion,
# JSON, `await` on a thenable. (`[Symbol.*]` keys are recognised by text.)
IMPLICIT = frozenset({"toString", "valueOf", "toJSON", "then"})
# Global functions that never call the argument they are given.
NON_CALLING = frozenset({"Boolean", "String", "Number"})
# Expressions that never evaluate to an array: `.flat()` keeps each as one item.
NOT_LISTS = frozenset(
    {
        "Literal",
        "TemplateLiteral",
        "ObjectExpression",
        "BinaryExpression",
        "UnaryExpression",
        "UpdateExpression",
        "ArrowFunctionExpression",
        "FunctionExpression",
    }
)
# A recursion's entries are summed level by level; past this, stop counting.
RECURSION_CAP = 1_000_000


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
        "param",
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
        self.param = None  # a parameter's own node in its function's params


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


def _passes(start, limit, inclusive, step) -> int:
    """Passes of `for (i = start; i < limit; i += step)` (`<=` when inclusive)."""
    span = limit - start
    if span < 0 or (span == 0 and not inclusive):
        return 0
    n = math.floor(span / step) + 1 if inclusive else math.ceil(span / step)
    # Fractions accumulate rounding error at runtime (0.1 ten times is below
    # 1), so one more pass keeps the count an upper bound.
    if any(v != int(v) for v in (start, limit, step)):
        n += 1
    return n


class Analysis:
    """Agent count of one parsed script. See the module docstring."""

    def __init__(self, ast: dict, src: str, assumed: int, limit: int = 10):
        self.src = src
        self.assumed = assumed
        # What a repetition the parse recognises but nothing bounds is costed
        # at: one over the limit, so the guard asks (and never below ASSUMED).
        self.high = max(assumed, limit + 1)
        self.labels = []
        self.high_labels = []
        self.reentry = {}
        self.yielding = set()
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
        self.pattern_keys = {}
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

    def unbounded_high(self, label: str, floor: int = 0) -> int:
        """Cost of a repetition the parse recognises and nothing in it bounds.

        A loop no test ends, one that moves its counter back or grows the list
        it runs over, or a method the language calls implicitly, may run any
        number of times, and ASSUMED is a convention for runtime lists that
        does not fit it: it is costed one over the limit so the guard asks.
        """
        label = short(label)
        if label not in self.high_labels:
            self.high_labels.append(label)
        return max(floor, self.high)

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
                        b = Binding(ident["name"], "param")
                        b.param = param
                        self._declare(node, ident, b)
            elif t in ("ClassDeclaration", "ClassExpression") and node.get("id"):
                scope = (
                    self._scope_of(node, BLOCKS) if t == "ClassDeclaration" else node
                )
                b = Binding(node["id"]["name"], "class", declarator=node)
                b.exported = node["_p"]["type"] in (
                    "ExportNamedDeclaration",
                    "ExportDefaultDeclaration",
                )
                self._declare(scope, node["id"], b)
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
        self._annex_b()

    def _annex_b(self):
        """Bind each block-level function in its enclosing function as well.

        Outside strict code, `{ function f() {} }` also binds `f` in the
        enclosing function (ECMA-262 Annex B.3.3), so a call to `f` after the
        block reaches it. acorn parses a module, which is strict and has no such
        binding, and the Workflow runtime's mode is not documented; so the
        binding is added, and a read of it counts as a call. In strict code that
        call would throw instead, so the cost of adding it is an over-count.
        Where the enclosing function already has a `var` or function of that
        name, the block assigns to it, so its reads are charged too; two block
        functions of one name share one binding and are each charged its reads.
        """
        self.annex_b = {}
        added = set()
        for node in self.nodes:
            if node["type"] != "FunctionDeclaration" or not node.get("id"):
                continue
            block = self._scope_of(node, BLOCKS)
            if block["type"] == "Program" or block["_p"]["type"] in FUNCTIONS:
                continue
            var_scope = self._scope_of(node, FUNCTIONS | {"Program"})
            names = self.scopes.setdefault(var_scope["_i"], {})
            body = var_scope.get("body") if var_scope["type"] in FUNCTIONS else None
            lexical = self.scopes.get(body["_i"], {}) if body is not None else {}
            name = node["id"]["name"]
            b = names.get(name) or lexical.get(name)
            if b is None:
                b = names[name] = Binding(name, "function", declarator=node, fn=node)
                added.add(id(b))
            elif id(b) in added:
                b.fn = None  # which function the name holds depends on the run
            elif b.kind not in ("var", "function"):
                continue  # a let, const, class or parameter of that name wins
            self.annex_b[node["_i"]] = b

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
            if t == "Property" and node["_p"]["type"] == "ObjectPattern":
                # `const { run } = o` reads o.run, a getter included.
                name = _key_name(node["key"], node["computed"])
                if name is not None:
                    self.pattern_keys.setdefault(name, []).append(node)
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

    def const_num(self, e, depth=0):
        """The finite number `e` always evaluates to, else None.

        A numeric literal, a sign in front of one, `+`, `-` or `*` of two, or
        a name declared with one and never assigned again: `-10`, `2 - 14`,
        `const start = -10`.
        """
        if e is None or depth > 8:
            return None
        t = e["type"]
        if t == "Literal":
            v = e.get("value")
            if isinstance(v, (int, float)) and not isinstance(v, bool):
                return v if math.isfinite(v) else None
            return None
        if t == "UnaryExpression" and e["operator"] in ("-", "+"):
            v = self.const_num(e["argument"], depth + 1)
            return None if v is None else (-v if e["operator"] == "-" else v)
        if t == "BinaryExpression" and e["operator"] in ("+", "-", "*"):
            a = self.const_num(e["left"], depth + 1)
            b = self.const_num(e["right"], depth + 1)
            if a is None or b is None:
                return None
            op = e["operator"]
            v = a + b if op == "+" else a - b if op == "-" else a * b
            return v if math.isfinite(v) else None
        if t == "Identifier":
            b = self.binding_of(e)
            if b is not None and b.kind in ("const", "let", "var") and not b.writes:
                return self.const_num(b.init, depth + 1)
        return None

    def const_count(self, e):
        """`e` as a non-negative integer count (`Array(n)`, `slice(a, b)`), else None."""
        v = self.const_num(e)
        return int(v) if v is not None and v >= 0 and v == int(v) else None

    def counter(self, loop):
        """(binding, start, cmp, limit, step) of `for (i = a; i < N; i += s)`."""
        init, test, update = loop["init"], loop["test"], loop["update"]
        start = binding = None
        if init is not None and init["type"] == "VariableDeclaration":
            decls = init["declarations"]
            if len(decls) == 1 and decls[0]["id"]["type"] == "Identifier":
                start = self.const_num(decls[0]["init"])
                binding = self.scopes_lookup(decls[0]["id"])
        elif (
            init is not None
            and init["type"] == "AssignmentExpression"
            and init["operator"] == "="
        ):
            start = self.const_num(init["right"])
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
        # A step that states a number must be positive (and is divided by, see
        # _loop_factor); any other step is assumed to be at least 1, which is
        # what makes N (or X's length) an upper bound.
        if step is None:
            return None
        v = self.const_num(step)
        if (v is not None and v <= 0) or (step["type"] == "Literal" and v is None):
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
            return self._bound_elements(e["elements"], at, seen)
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
        if t == "Literal" and isinstance(e.get("value"), str):
            # A string iterates by character (spread, Array.from, for...of).
            return Bound(len(e["value"]))
        if t == "ObjectExpression":
            return self.iterable_bound(self.iterator_method(e))
        if t in ("CallExpression", "NewExpression"):
            callee, args = e["callee"], e["arguments"]
            if callee["type"] == "Identifier" and self.binding_of(callee) is None:
                # `Array(20)` / `new Array(20)`: 20 slots; `Array(a, b)`: 2.
                # `new Set(X)`: at most X.
                if callee["name"] == "Array" and len(args) == 1:
                    n = self.const_count(args[0])
                    if n is not None:
                        return Bound(n)
                    return Bound(None, self.stated_int(args[0]))
                if callee["name"] == "Array":
                    return self._bound_elements(args, at, seen)
                if callee["name"] == "Set" and t == "NewExpression" and args:
                    return self.bound(args[0], at, seen)
            cls = self.class_of(callee) if t == "NewExpression" else None
            if cls is not None:
                return self.iterable_bound(self.iterator_method(cls["body"]))
            if t == "CallExpression":
                gen = self.callee_function(callee)
                if gen is not None and gen.get("generator"):
                    return self.yields(gen)
                return self._bound_call(e, at, seen)
        return UNBOUNDED

    def iterator_method(self, obj):
        """The `[Symbol.iterator]` (or async) function an object literal or class body holds."""
        members = (
            obj["properties"] if obj["type"] == "ObjectExpression" else obj["body"]
        )
        for p in members:
            if (
                p["type"] in ("Property", "MethodDefinition")
                and p["computed"]
                and "".join(self.text(p["key"]).split())
                in ("Symbol.iterator", "Symbol.asyncIterator")
                and p["value"]["type"] in FUNCTIONS
            ):
                return p["value"]
        return None

    def iterable_bound(self, fn) -> Bound:
        """Items an object with iterator method `fn` yields: a generator's yields.

        Any other iterator hand-builds its `next()`, which no text bounds, so it
        is costed at HIGH and the guard asks.
        """
        if fn is None:
            return UNBOUNDED
        if fn.get("generator"):
            return self.yields(fn)
        return Bound(None, self.unbounded_high("an object with its own iterator"))

    def class_of(self, callee):
        """The class a `new` callee always names, else None."""
        b = self.binding_of(callee)
        if b is None or b.writes:
            return None
        if b.kind == "class":
            return b.declarator
        if (
            b.init is not None
            and b.init["type"] == "ClassExpression"
            and b.kind == "const"
        ):
            return b.init
        return None

    def yields(self, fn) -> Bound:
        """Values one run of the generator `fn` yields.

        Each `yield` counts once per pass of the loops around it in `fn`, and a
        `yield*` counts the length of what it delegates to. A loop with no test
        and no stated exit costs HIGH, so an endless generator asks.
        """
        self._tick()
        if fn["_i"] in self.yielding:
            return UNBOUNDED  # a generator that delegates to itself
        self.yielding.add(fn["_i"])
        try:
            n, floor, exact = 0, 0, True
            for y in self.nodes:
                if (
                    y["type"] != "YieldExpression"
                    or self.enclosing_function(y) is not fn
                ):
                    continue
                k = self.local_factor(y, fn)
                if not y["delegate"]:
                    n += k
                    continue
                b = self.bound(y["argument"], y)
                if b.n is None:
                    exact = False
                    floor += k * max(b.floor, self.assumed)
                else:
                    n += k * b.n
        finally:
            self.yielding.discard(fn["_i"])
        return Bound(n) if exact else Bound(None, n + floor)

    def _bound_elements(self, elements, at, seen) -> Bound:
        """Length of an array literal's elements, or of a call's arguments."""
        n, floor, exact = 0, 0, True
        for el in elements:
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

    def _bound_name(self, ident, at, seen) -> Bound:
        b = self.binding_of(ident)
        if b is None or id(b) in seen or b.writes:
            return UNBOUNDED
        rest = b.param if b.kind == "param" else None
        if rest is not None:
            if (
                rest["type"] != "RestElement"
                or rest["argument"]["type"] != "Identifier"
            ):
                return UNBOUNDED
        elif b.kind not in ("const", "let", "var") or b.init is None:
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
            # `add` grows a `new Set(X)`, which is otherwise bounded by X.
            if (
                name in ("push", "unshift", "splice", "add")
                and gp["type"] == "CallExpression"
            ):
                grown = grown or gp["callee"] is p
            elif (
                name == "length"
                and gp["type"] == "AssignmentExpression"
                and gp["left"] is p
            ):
                return UNBOUNDED
        if rest is not None:
            base = self._bound_rest(rest, at, seen)
        else:
            base = self.bound(b.init, at, seen)
        if grown:
            # Unbounded, but never below what the declaration already holds
            # plus the push: #2668 read the initializer alone (#2670 round 4).
            return Bound(None, (base.n if base.n is not None else base.floor) + 1)
        return base

    def _bound_rest(self, rest, at, seen) -> Bound:
        """Length of `(...xs) =>`'s xs: the most arguments any call passes it.

        Bounded only when every reference to the function is a plain call
        (see direct_calls); a spread passed into it adds its own bound.
        """
        fn = rest["_p"]
        idx = len(fn["params"]) - 1
        calls = self.direct_calls(fn)
        if calls is None:
            return UNBOUNDED
        per_call = []
        for args in calls:
            if any(a["type"] == "SpreadElement" for a in args[:idx]):
                return UNBOUNDED
            per_call.append(self._bound_elements(args[idx:], at, seen))
        if all(b.n is not None for b in per_call):
            return Bound(max((b.n for b in per_call), default=0))
        return Bound(None, max(b.n if b.n is not None else b.floor for b in per_call))

    def direct_calls(self, fn):
        """The arguments of every call of `fn` when each reference calls it, else None.

        A reference calls it as `f(a, b)` or `f.call(t, a, b)`, both passing
        a and b. Covers a function declaration and a function bound to a name;
        one that is exported, reassigned, passed on or read any other way is
        None.
        """
        refs = self.call_refs(fn)
        return None if refs is None else [args for _ref, args in refs]

    def call_refs(self, fn):
        """(reference, arguments) for every call of `fn`, as direct_calls, else None."""
        p = fn["_p"]
        if fn["type"] == "FunctionDeclaration":
            if p["type"] == "ExportDefaultDeclaration":
                return None
            bindings = self.fn_bindings(fn)
        elif (
            p["type"] == "VariableDeclarator"
            and p["init"] is fn
            and p["id"]["type"] == "Identifier"
        ):
            bindings = [self.scopes_lookup(p["id"])] + self.fn_bindings(fn)
        else:
            return None
        refs = []
        for b in bindings:
            if b is None or b.exported or b.writes:
                return None
            for r in b.reads:
                args = self.call_args(r)
                if args is None:
                    return None
                refs.append((r, args))
        return refs

    @staticmethod
    def call_args(ref):
        """What a reference to a function passes it: `f(a)` and `f.call(t, a)` pass a."""
        q = ref["_p"]
        if q["type"] == "CallExpression" and q["callee"] is ref:
            return q["arguments"]
        if (
            q["type"] == "MemberExpression"
            and q["object"] is ref
            and not q["computed"]
            and q["property"].get("name") == "call"
        ):
            c = q["_p"]
            if c["type"] == "CallExpression" and c["callee"] is q:
                return c["arguments"][1:]
        return None

    def _bound_call(self, call, at, seen) -> Bound:
        callee, args = call["callee"], call["arguments"]
        if callee["type"] != "MemberExpression" or callee["computed"]:
            return UNBOUNDED
        name = callee["property"].get("name")
        obj = callee["object"]
        builtin = obj["type"] == "Identifier" and self.binding_of(obj) is None
        if builtin and obj["name"] == "Array" and name == "from" and args:
            return self.array_like(args[0], at, seen)
        if builtin and obj["name"] == "Array" and name == "of":
            return self._bound_elements(args, at, seen)
        if (
            builtin
            and obj["name"] == "Object"
            and name in ("keys", "values", "entries")
        ):
            return self.key_count(args[0], at) if args else UNBOUNDED
        if name == "slice":
            if self.is_window_slice(call, at):
                return Bound(1)
            if len(args) == 2:
                lo, hi = self.const_count(args[0]), self.const_count(args[1])
                if lo is not None and hi is not None:
                    return Bound(max(0, hi - lo))
            return self.bound(obj, at, seen)
        if name == "split":
            return self.split_bound(obj, args)
        if name in LENGTH_KEEPING:
            return self.bound(obj, at, seen)
        if name == "flat":
            if not args or self.const_count(args[0]) == 1:
                b = self.flat_bound(obj, at, seen)
                if b is not None:
                    return b
            b = self.bound(obj, at, seen)
            return Bound(None, b.n if b.n is not None else b.floor)
        if name == "flatMap" and args:
            width = self.returned_width(args[0], at, seen)
            b = self.bound(obj, at, seen)
            if width is not None and b.n is not None:
                return Bound(b.n * width)
            return UNBOUNDED
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
                    n = self.const_count(p["value"])
                    return Bound(n) if n is not None else UNBOUNDED
            return UNBOUNDED
        return self.bound(arg, at, seen)

    def string_value(self, e):
        """The text of a string literal, or of a name only ever holding one."""
        if e["type"] == "Literal" and isinstance(e.get("value"), str):
            return e["value"]
        b = self.binding_of(e)
        if b is not None and b.kind in ("const", "let", "var") and not b.writes:
            if b.init is not None and b.init["type"] == "Literal":
                v = b.init.get("value")
                return v if isinstance(v, str) else None
        return None

    def regex_of(self, e):
        """The {pattern, flags} of a regex literal, or of a name only ever holding one."""
        if e["type"] == "Identifier":
            b = self.binding_of(e)
            if (
                b is None
                or b.writes
                or b.kind not in ("const", "let", "var")
                or b.init is None
            ):
                return None
            e = b.init
        return e.get("regex") if e["type"] == "Literal" else None

    def split_bound(self, obj, args) -> Bound:
        """Pieces `s.split(sep, limit)` makes of a string the text states."""
        s = self.string_value(obj)
        if s is None:
            return UNBOUNDED
        sep = self.string_value(args[0]) if args else None
        regex = self.regex_of(args[0]) if args else None
        if not args:
            n = 1
        elif sep is not None:
            n = len(s.split(sep)) if sep else len(s)
        elif regex is not None:
            # At most one split per position, each adding its captured groups.
            n = (len(s) + 1) * (1 + regex.get("pattern", "").count("("))
        else:
            return UNBOUNDED  # a separator the text does not state may be either
        if len(args) > 1:
            limit = self.const_count(args[1])
            n = n if limit is None else min(n, limit)
        return Bound(n)

    def flat_bound(self, obj, at, seen):
        """Length of `obj.flat()` when each element's length is known, else None.

        An array literal's elements are summed (an inner literal counts its
        length, anything else that is not a list counts 1), and `X.fill(v)`
        flattens to X copies of v.
        """
        if (
            obj["type"] == "CallExpression"
            and obj["callee"]["type"] == "MemberExpression"
            and not obj["callee"]["computed"]
            and obj["callee"]["property"].get("name") == "fill"
            and obj["arguments"]
        ):
            copies = self.bound(obj["callee"]["object"], at, seen)
            width = self.flat_width(obj["arguments"][0], at, seen)
            if copies.n is None or width is None:
                return None
            return Bound(copies.n * width)
        elements = self.literal_elements(obj, at, seen)
        if elements is None:
            return None
        total = 0
        for el in elements:
            if el is None:
                continue  # a hole is skipped
            if el["type"] == "SpreadElement":
                return None
            width = self.flat_width(el, at, seen)
            if width is None:
                return None
            total += width
        return Bound(total)

    def literal_elements(self, e, at, seen):
        """The elements of the array literal `e` holds, while nothing changes its length."""
        if e["type"] == "ArrayExpression":
            return e["elements"]
        b = self.binding_of(e)
        if b is None or b.init is None or b.init["type"] != "ArrayExpression":
            return None
        whole = self.bound(e, at, seen)
        if whole.n is None or whole.n != self.bound(b.init, at, seen).n:
            return None
        return b.init["elements"]

    def flat_width(self, el, at, seen):
        """Items one element becomes when flattened a level, or None when unknown."""
        if el["type"] in NOT_LISTS or self.scalar(el):
            return 1
        b = self.bound(el, at, seen)
        return b.n

    def scalar(self, ident) -> bool:
        """True for a name only ever holding a number, boolean, null or object literal."""
        b = self.binding_of(ident)
        if b is None or b.writes or b.kind not in ("const", "let", "var"):
            return False
        init = b.init
        return init is not None and (
            (init["type"] == "Literal" and not isinstance(init.get("value"), str))
            or init["type"] in ("ObjectExpression", "TemplateLiteral")
        )

    def returned_width(self, cb, at, seen):
        """Items a flatMap callback's return adds per element, or None when unknown."""
        if cb["type"] not in ("ArrowFunctionExpression", "FunctionExpression"):
            return None
        if cb["type"] == "ArrowFunctionExpression" and cb["expression"]:
            returns = [cb["body"]]
        else:
            returns = [
                n["argument"]
                for n in self.nodes
                if n["type"] == "ReturnStatement" and self.enclosing_function(n) is cb
            ]
        widest = 1 if not returns else 0
        for r in returns:
            width = 1 if r is None else self.flat_width(r, at, seen)
            if width is None:
                return None
            widest = max(widest, width)
        return widest

    def key_count(self, e, at=None) -> Bound:
        """Keys `for...in` and `Object.keys` visit.

        An object literal's properties, or those of a name bound to one that
        nothing adds keys to; an array's (or a string's) length.
        """
        if e["type"] == "ObjectExpression":
            props = e["properties"]
            # A spread adds keys, and `__proto__` hands for...in its prototype's.
            if all(
                p["type"] == "Property"
                and _key_name(p["key"], p["computed"]) != "__proto__"
                for p in props
            ):
                return Bound(len(props))
            return UNBOUNDED
        b = self.binding_of(e)
        if b is None or b.init is None:
            return self.bound(e, at)
        if b.init["type"] == "ObjectExpression":
            own = self.key_count(b.init, at)
            if b.kind in ("const", "let", "var") and not b.writes:
                if all(self.keeps_keys(r) for r in b.reads):
                    return own
            # Keys may be added: unbounded, but never below what it holds plus one.
            return Bound(None, (own.n if own.n is not None else own.floor) + 1)
        # A named key written onto an array is a key for...in visits too.
        whole = self.bound(e, at)
        for r in b.reads:
            q = r["_p"]
            if (
                q["type"] == "MemberExpression"
                and q["object"] is r
                and self._is_write(q)
            ):
                return Bound(
                    None, (whole.n if whole.n is not None else whole.floor) + 1
                )
        return whole

    def keeps_keys(self, ref) -> bool:
        """True where a read of an object cannot add a key to it."""
        q = ref["_p"]
        if q["type"] == "MemberExpression" and q["object"] is ref:
            gp = q["_p"]
            if self._is_write(q) or (
                gp["type"] == "UnaryExpression" and gp["operator"] == "delete"
            ):
                return False
            # A method may add keys through `this`.
            return not (gp["type"] == "CallExpression" and gp["callee"] is q)
        if q["type"] == "ForInStatement" and q["right"] is ref:
            return True
        if (
            q["type"] == "CallExpression"
            and q["arguments"]
            and q["arguments"][0] is ref
        ):
            c = q["callee"]
            return (
                c["type"] == "MemberExpression"
                and not c["computed"]
                and c["object"]["type"] == "Identifier"
                and c["object"]["name"] in ("Object", "JSON")
                and c["property"].get("name")
                in ("keys", "values", "entries", "stringify")
            )
        return False

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
            if parent["type"] in FUNCTIONS:
                base = self.inv(parent)
                break
            loop = self._repeater(cur, parent)
            if loop is not None:
                repeats.append(loop)
            cur = parent
        if base == 0:
            return 0
        for loop in repeats:
            base *= self.loop_factor(loop)
        return base

    @staticmethod
    def _repeater(cur, parent):
        """The loop (or instance field) that runs `cur`, a child of `parent`, again."""
        t = parent["type"]
        if t == "ForStatement":
            if (
                cur is parent["body"]
                or cur is parent["test"]
                or cur is parent["update"]
            ):
                return parent
        elif t in ("ForOfStatement", "ForInStatement"):
            if cur is parent["body"] or cur is parent["left"]:
                return parent
        elif t in ("WhileStatement", "DoWhileStatement"):
            if cur is parent["body"] or cur is parent["test"]:
                return parent
        elif (
            t == "ClassBody"
            and cur["type"] == "PropertyDefinition"
            and not cur["static"]
        ):
            return cur
        return None

    def local_factor(self, node, fn) -> int:
        """Times `node` runs per invocation of the function `fn` it is in."""
        factor, cur = 1, node
        while cur["_p"] is not fn:
            loop = self._repeater(cur, cur["_p"])
            if loop is not None:
                factor *= self.loop_factor(loop)
            cur = cur["_p"]
        return factor

    def field_runs(self, cls) -> int:
        """Times an instance field of `cls` runs per evaluation of the class."""
        made = self.constructions(cls)
        if made is None:
            return self.unbounded("a class field initializer")
        return math.ceil(made / max(self.count(cls), 1))

    def constructions(self, cls):
        """Instances of `cls` the program makes, or None when not every one is seen.

        `new C()` makes one; so does each instance of a class extending C,
        whose constructor runs C's. A reference to C read any other way (passed
        on, exported, `new` through another name) hides some, so it is None.
        """
        return self._cached(("new", cls["_i"]), lambda: self._constructions(cls))

    def _constructions(self, cls):
        if self.members.get("constructor") or any(
            n["type"] == "NewExpression"
            and n["callee"]["type"] in ("ThisExpression", "MetaProperty")
            for n in self.nodes
        ):
            return None  # `new this.constructor()` builds a class without naming it
        bindings = []
        if cls.get("id"):
            scope = (
                self._scope_of(cls, BLOCKS)
                if cls["type"] == "ClassDeclaration"
                else cls
            )
            bindings.append(self.scopes.get(scope["_i"], {}).get(cls["id"]["name"]))
        p = cls["_p"]
        total = 0
        if p["type"] == "VariableDeclarator" and p["init"] is cls:
            if p["id"]["type"] != "Identifier":
                return None
            bindings.append(self.scopes_lookup(p["id"]))
        elif p["type"] == "NewExpression" and p["callee"] is cls:
            total += self.count(p)
        elif cls["type"] == "ClassExpression":
            return None  # passed on, returned or stored where the parse does not follow
        for b in bindings:
            if b is None or b.exported or b.writes:
                return None
            for r in b.reads:
                q = r["_p"]
                if q["type"] == "NewExpression" and q["callee"] is r:
                    total += self.count(q)
                elif (
                    q["type"] in ("ClassDeclaration", "ClassExpression")
                    and q["superClass"] is r
                ):
                    sub = self.constructions(q)
                    if sub is None:
                        return None
                    total += sub
                else:
                    return None
        return total

    def loop_factor(self, loop) -> int:
        return self._cached(
            ("loop", loop["_i"]), lambda: max(1, self._loop_factor(loop))
        )

    def _loop_factor(self, loop) -> int:
        t = loop["type"]
        if t == "PropertyDefinition":
            return self.field_runs(loop["_p"]["_p"])
        if t == "ForOfStatement":
            b = self.bound(loop["right"], loop)
            if self.unsettled(loop):
                return self.unbounded_high(
                    f"a loop over {self.text(loop['right'])} that grows it",
                    b.n if b.n is not None else b.floor,
                )
            return self.mult(b, loop["right"])
        if t == "ForInStatement":
            right = loop["right"]
            b = self.key_count(right, loop)
            if b.n is not None:
                return b.n
            return self.unbounded(f"for...in {self.text(right)}", b.floor)
        if t == "ForStatement":
            c = self.counter(loop)
            if c is not None:
                _b, start, cmp, limit, step = c
                inclusive = cmp == "<="
                v = self.const_num(step)
                n = self.const_num(limit)
                if n is not None:
                    return _passes(start, n, inclusive, v if v is not None else 1)
                if (
                    limit["type"] == "MemberExpression"
                    and not limit["computed"]
                    and limit["property"].get("name") == "length"
                ):
                    # Not divided by a step above 1: a window `X.slice(i, i + W)`
                    # inside it counts 1 per pass, so the pair is X in total.
                    step = min(1, v) if v is not None else 1
                    b = self.bound(limit["object"], loop)
                    if b.n is not None:
                        return _passes(start, b.n, inclusive, step)
                    width = max(b.floor, self.assumed)
                    if self.unsettled(loop):
                        return self.unbounded_high(
                            f"a loop over {self.text(limit['object'])} that grows it",
                            _passes(start, width, inclusive, step),
                        )
                    return self.unbounded(
                        self.text(limit["object"]),
                        _passes(start, width, inclusive, step),
                    )
            if self.always_true(loop["test"]):
                return self.no_exit(loop, "a for loop with no test")
            if self.unsettled(loop):
                return self.unbounded_high(
                    "a for loop that moves its counter back or grows its list",
                    self.stated_limit(loop),
                )
            return self.unbounded(
                "a for loop with no static bound", self.stated_limit(loop)
            )
        n = self.while_counter(loop)
        if n is not None:
            return n
        label = "a while loop" if t == "WhileStatement" else "a do...while loop"
        if self.always_true(loop["test"]):
            return self.no_exit(loop, f"{label} whose test is always true")
        if self.unsettled(loop):
            return self.unbounded_high(
                f"{label} that moves its counter back or grows its list",
                self.stated_limit(loop),
            )
        return self.unbounded(label, self.stated_limit(loop))

    def unsettled(self, loop) -> bool:
        """True when the loop itself undoes what would end it.

        A counter its test orders (`i < 3`, `n--`) that the loop, or a
        function it may call, moves both up and down or sets outright, as
        `if (r++ < 12) i--` does, or moves only away from where the test ends
        (`i < 3` with `i--`, a limit `N` the loop raises); or a list it runs
        over (`for...of X`, a test on `X.length` or `X.size`) that it grows.
        Each can repeat the loop any number of times, so no stated count is a
        bound. A flag the test reads (`!done`) is none of these.
        """
        counters, lists = {}, {}
        ends = {}  # binding id -> directions that move it toward ending the loop
        if loop["type"] == "ForOfStatement":
            b = self.binding_of(loop["right"])
            if b is not None:
                lists[id(b)] = b
        test = loop.get("test")
        if test is not None:
            for n in self.nodes:
                b = self.ref_binding.get(n["_i"]) if n["type"] == "Identifier" else None
                if b is None or not self.inside(n, test):
                    continue
                p = n["_p"]
                if (
                    p["type"] == "MemberExpression"
                    and p["object"] is n
                    and not p["computed"]
                    and p["property"].get("name") in ("length", "size")
                ):
                    lists[id(b)] = b
                    continue
                if p["type"] == "UpdateExpression":
                    n, p = p, p["_p"]
                    if n is test:
                        counters[id(b)] = b  # `while (n--)` ends counting down
                        ends.setdefault(id(b), set()).add("down")
                        continue
                if p["type"] == "BinaryExpression" and p["operator"] in (
                    "<",
                    "<=",
                    ">",
                    ">=",
                ):
                    counters[id(b)] = b
                    # `i < N` ends as i rises; `N > i`, or N itself, as it falls.
                    rising = (p["left"] is n) == (p["operator"] in ("<", "<="))
                    ends.setdefault(id(b), set()).add("up" if rising else "down")
        for key, b in counters.items():
            moves = {self.direction(w) for w in b.writes if self.runs_during(w, loop)}
            if "set" in moves or {"up", "down"} <= moves:
                return True
            if moves and not (moves & ends[key]):
                return True  # it only ever moves away from the end
        for b in lists.values():
            if any(self.grows(r) and self.runs_during(r, loop) for r in b.reads):
                return True
        return False

    def runs_during(self, node, loop) -> bool:
        """True where `node` can run while `loop` repeats: in it, or in another function."""
        if self.inside(node, loop):
            return loop["type"] != "ForStatement" or not self.inside(node, loop["init"])
        fn = self.enclosing_function(node)
        return fn["type"] in FUNCTIONS and not self.inside(loop, fn)

    def direction(self, w) -> str:
        """How a write moves a name: "up", "down", or "set" to a new value."""
        p = w["_p"]
        if p["type"] == "UpdateExpression":
            return "up" if p["operator"] == "++" else "down"
        if (
            p["type"] == "AssignmentExpression"
            and p["left"] is w
            and p["operator"] in ("+=", "-=")
        ):
            # A step that states no number is taken to be positive, as counter() does.
            v = self.const_num(p["right"])
            return "up" if (v is None or v > 0) == (p["operator"] == "+=") else "down"
        return "set"

    def grows(self, ref) -> bool:
        """True where a read of a list adds to it: push, unshift, splice, add, an index write."""
        q = ref["_p"]
        if q["type"] != "MemberExpression" or q["object"] is not ref:
            return False
        gp = q["_p"]
        if q["computed"]:
            return self._is_write(q)
        name = q["property"].get("name")
        if name in ("push", "unshift", "splice", "add"):
            return gp["type"] == "CallExpression" and gp["callee"] is q
        return name == "length" and self._is_write(q)

    @staticmethod
    def always_true(test) -> bool:
        """True for a loop test that never fails: none, or a truthy literal."""
        if test is None:
            return True
        return (
            test["type"] == "Literal"
            and bool(test.get("value"))
            and "regex" not in test
        )

    def no_exit(self, loop, label) -> int:
        """A loop only a `break` leaves: the count a break's test states, else HIGH.

        `while (true) { ...; if (++n >= 12) break }` states 12, costed like any
        stated count (never below ASSUMED). With no count stated, nothing in
        the text bounds it, so it is costed above the limit and the guard asks.
        """
        stated = self.stated_break(loop)
        if stated:
            return self.unbounded(label, stated)
        return self.unbounded_high(label)

    def stated_break(self, loop) -> int:
        """The largest count the test of an `if` holding a break out of `loop` states."""
        best = 0
        for n in self.nodes:
            if n["type"] != "BreakStatement" or not self.inside(n, loop["body"]):
                continue
            if self.break_target(n) is not loop:
                continue
            cur = n
            while cur is not loop:
                p = cur["_p"]
                if p["type"] == "IfStatement" and p["test"] is not cur:
                    best = max(best, self.stated_exit(p["test"]))
                    break
                cur = p
        return best

    @staticmethod
    def break_target(brk):
        """The loop or switch a `break` leaves, or None across a function."""
        name = brk["label"]["name"] if brk.get("label") else None
        cur = brk["_p"]
        while cur is not None and cur["type"] not in FUNCTIONS:
            if name is None:
                if cur["type"] in LOOP_HEADS or cur["type"] in (
                    "WhileStatement",
                    "DoWhileStatement",
                    "SwitchStatement",
                ):
                    return cur
            elif cur["type"] == "LabeledStatement" and cur["label"]["name"] == name:
                return cur["body"]
            cur = cur["_p"]
        return None

    def stated_exit(self, test) -> int:
        """The count an exit test states, plus the pass that meets it: `i >= 12` 13."""
        t = test["type"]
        if t == "LogicalExpression":
            return max(self.stated_exit(test["left"]), self.stated_exit(test["right"]))
        if t != "BinaryExpression":
            return 0
        op = test["operator"]
        if op not in ("<", "<=", ">", ">=", "==", "===", "!=", "!=="):
            return 0
        n = max(self.stated_int(test["left"]), self.stated_int(test["right"]))
        return n + 1 if n else 0

    def stated_limit(self, loop) -> int:
        """The largest count a refused loop's test states, or 0.

        Not a bound -- the counter may move any way -- but a loop that states
        20 is not costed at 8: the figure is a floor under ASSUMED's guess.
        Either side of a `<`, `<=`, `>`, `>=`, `!=` or `!==` test states it:
        a literal (`i < 12`, `i !== 12`), or a name declared with one, so that
        `for (let i = 20; i > 0; i--)`, `while (n-- > 0)` after `let n = 20`,
        and `i < N` after `let N = 20` each state 20. A `for` whose update
        moves a compared name by a literal step states that many times fewer:
        `for (let i = 100; i > 0; i -= 10)` states 10. A test that counts a
        name down to zero (`for (let i = 12; i--;)`, `while (n)`) states what
        the name was given.
        """
        test = loop.get("test")
        if test is not None and test["type"] in ("UpdateExpression", "Identifier"):
            return self.stated_int(test)
        if test is None or test["type"] != "BinaryExpression":
            return 0
        op = test["operator"]
        if op not in ("<", "<=", ">", ">=", "!=", "!=="):
            return 0
        n = max(self.stated_int(test["left"]), self.stated_int(test["right"]))
        if not n:
            return 0
        n += 1 if op in ("<=", ">=") else 0
        return math.ceil(n / self.stated_step(loop, test))

    def stated_step(self, loop, test) -> int:
        """The literal step a `for` update moves a name its test compares, else 1."""
        update = loop.get("update")
        if update is None:
            return 1
        step, target = 1, None
        if update["type"] == "AssignmentExpression":
            target, right = update["left"], update["right"]
            if update["operator"] in ("+=", "-="):
                step = self.const_num(right)
            elif (
                update["operator"] == "="
                and right["type"] == "BinaryExpression"
                and right["operator"] in ("+", "-")
                and self.binding_of(right["left"]) is self.binding_of(target)
            ):
                step = self.const_num(right["right"])
        compared = {
            id(self.binding_of(s["argument"] if s["type"] == "UpdateExpression" else s))
            for s in (test["left"], test["right"])
        }
        b = self.binding_of(target) if target is not None else None
        if b is None or id(b) not in compared or not step or step < 0:
            return 1
        # A counter the body or a closure also writes moves by more than the
        # step (`i--` in the body of `i += 2`), so its stated count stands.
        for w in b.writes:
            if not (self.inside(w, update) or self.inside(w, loop.get("init"))):
                return 1
        return step

    def stated_int(self, e) -> int:
        """The integer `e` states: a literal, or one its name was given.

        A name is given the literal it was declared or assigned with, or, for
        a parameter, its default and the literals plain calls pass it
        (`times(20, fn)`).
        """
        if e["type"] == "UpdateExpression":
            e = e["argument"]
        n = self.const_count(e)
        if n is not None:
            return n
        b = self.binding_of(e)
        if b is None:
            return 0
        if b.kind in ("let", "const", "var"):
            stated = [self.const_count(b.init) or 0]
            for w in b.writes:
                a = w["_p"]
                if a["type"] == "AssignmentExpression" and a["operator"] == "=":
                    stated.append(self.const_count(a["right"]) or 0)
            return max(stated)
        if b.param is None:
            return 0
        return self.stated_param(b.param)

    def stated_param(self, param) -> int:
        """The largest literal a parameter is given: its default, or a call's argument."""
        fn = param["_p"]
        idx = next(k for k, p in enumerate(fn["params"]) if p is param)
        stated = [0]
        if param["type"] == "AssignmentPattern":
            stated.append(self.const_count(param["right"]) or 0)
        for args in self.direct_calls(fn) or []:
            if idx < len(args) and not any(
                a["type"] == "SpreadElement" for a in args[: idx + 1]
            ):
                stated.append(self.const_count(args[idx]) or 0)
        return max(stated)

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
        start = self.const_num(b.init)
        limit = self.const_num(test["right"])
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
                target, step = e["left"], self.const_num(e["right"])
            else:
                continue
            if self.binding_of(target) is b and step and step > 0:
                steps.append((target, step))
        if not steps:
            return None
        if not all(any(w is t for t, _ in steps) for w in b.writes):
            return None
        for n in self.nodes:
            if n["type"] == "ContinueStatement" and self.inside(n, body):
                return None
        inclusive = test["operator"] == "<="
        n = _passes(start, limit, inclusive, sum(s for _, s in steps))
        return max(n, 1) if loop["type"] == "DoWhileStatement" else n

    def inv(self, fn) -> int:
        """How many times the function `fn` is invoked."""
        key = ("inv", fn["_i"])
        if key in self.memo:
            return self.memo[key]
        i = fn["_i"]
        if i in self.computing:
            # Reached again while its own count is pending: recursion. Worth
            # nothing, or one call while its branching is measured.
            self.events.append(i)
            return self.reentry.get(i, 0)
        self._tick()
        self.computing.add(i)
        mark = len(self.events)
        try:
            raw = self._raw_inv(fn)
            if i in self.events[mark:]:
                # Counted again with each re-entry worth one call, the
                # difference is how many calls one entry makes to itself.
                self.reentry[i] = 1
                try:
                    branching = max(1, self._raw_inv(fn) - raw)
                finally:
                    del self.reentry[i]
                raw = max(raw, 1) * self.recursion_entries(fn, branching)
        finally:
            self.computing.discard(i)
        later = self.events[mark:]
        if not any(t in self.computing for t in later):
            self.memo[key] = raw
        return raw

    def recursion_entries(self, fn, branching) -> int:
        """Entries per outside call of a function that calls itself `branching` times.

        A tree `depth` levels deep: 1 + b + b^2 + ... + b^depth, capped. The
        depth is what the text proves (see proven_depth), else ASSUMED or, if
        larger, the count the function's parameters are given or compared with
        (`go(20)`, `if (d < 20)`).
        """
        depth = self.proven_depth(fn)
        if depth is None:
            depth = max(self.assumed, self.stated_depth(fn))
            self.unbounded(f"recursion through {self.fn_name(fn)}")
        total, level = 1, 1
        for _ in range(depth):
            level *= branching
            total += level
            if total >= RECURSION_CAP:
                return RECURSION_CAP
        return total

    def proven_depth(self, fn):
        """Levels a recursion descends when its text proves it, else None.

        Proven when one parameter is given a number by every outside call,
        every call the function makes to itself passes that parameter moved
        by a constant step in one direction, and each such call runs only
        while a test of the parameter against a number allows it
        (`if (d < 3) rec(d + 1)`, or `if (n <= 0) return` ahead of it).
        """
        refs = self.call_refs(fn)
        if refs is None:
            return None
        inner = [(r, args) for r, args in refs if self.inside(r, fn)]
        outer = [args for r, args in refs if not self.inside(r, fn)]
        if not inner or not outer:
            return None
        for r, _args in refs:
            # An outside call from a function the recursion itself reaches
            # (`g` in f -> g -> f(5)) restarts it, so the depth is unproven.
            # That function's count waited on this one and was not kept.
            h = self.enclosing_function(r)
            if (
                not self.inside(r, fn)
                and h["type"] != "Program"
                and ("inv", h["_i"]) not in self.memo
            ):
                return None
        best = None
        for j, param in enumerate(fn["params"]):
            b = self.scopes_lookup(param) if param["type"] == "Identifier" else None
            if b is None or b.writes:
                continue
            starts = [
                self.const_num(args[j]) if j < len(args) else None for args in outer
            ]
            if any(v is None for v in starts) or any(
                a["type"] == "SpreadElement" for args in outer for a in args[: j + 1]
            ):
                continue
            levels = self._levels(fn, b, inner, j, starts)
            if levels is not None:
                best = levels if best is None else min(best, levels)
        return best

    def _levels(self, fn, pb, inner, j, starts):
        """Levels parameter `j` (binding `pb`) allows, or None where not proven."""
        up = step = None
        limits = []
        for r, args in inner:
            a = args[j] if j < len(args) else None
            if (
                a is None
                or any(x["type"] == "SpreadElement" for x in args[: j + 1])
                or a["type"] != "BinaryExpression"
                or a["operator"] not in ("+", "-")
                or self.binding_of(a["left"]) is not pb
            ):
                return None
            k = self.const_num(a["right"])
            if k is None or k <= 0 or (up is not None and up != (a["operator"] == "+")):
                return None
            up = a["operator"] == "+"
            step = k if step is None else min(step, k)
            limit = self.guard(r, fn, pb, up)
            if limit is None:
                return None
            limits.append(limit)
        levels = 0
        for bound, inclusive in limits:
            for start in starts:
                if up:
                    levels = max(levels, _passes(start, bound, inclusive, step))
                else:
                    levels = max(levels, _passes(bound, start, inclusive, step))
        return levels

    def guard(self, call_ref, fn, pb, up):
        """(limit, inclusive) of a test on `pb` that must hold for `call_ref` to run."""
        conds, cur = [], call_ref
        while cur is not fn:
            p = cur["_p"]
            t = p["type"]
            if t in ("IfStatement", "ConditionalExpression") and cur is not p["test"]:
                conds.append((p["test"], cur is p["consequent"]))
            elif (
                t == "LogicalExpression" and cur is p["right"] and p["operator"] != "??"
            ):
                conds.append((p["left"], p["operator"] == "&&"))
            if p is fn["body"] and t == "BlockStatement":
                # An early `if (test) return` ahead of the call.
                for stmt in p["body"]:
                    if stmt is cur:
                        break
                    if (
                        stmt["type"] == "IfStatement"
                        and stmt["alternate"] is None
                        and self.leaves(stmt["consequent"])
                    ):
                        conds.append((stmt["test"], False))
            cur = p
        for test, holds in conds:
            g = self.param_limit(test, pb, holds, up)
            if g is not None:
                return g
        return None

    @staticmethod
    def leaves(stmt) -> bool:
        """True for `return`/`throw`, or a block ending in one."""
        if stmt["type"] == "BlockStatement" and stmt["body"]:
            stmt = stmt["body"][-1]
        return stmt["type"] in ("ReturnStatement", "ThrowStatement")

    def param_limit(self, test, pb, holds, up):
        """(limit, inclusive) when `test` being `holds` keeps `pb` below (or above) a number."""
        t = test["type"]
        if t == "LogicalExpression":
            if (test["operator"] == "&&") == holds:
                for side in (test["left"], test["right"]):
                    g = self.param_limit(side, pb, holds, up)
                    if g is not None:
                        return g
            return None
        if t == "UnaryExpression" and test["operator"] == "!":
            return self.param_limit(test["argument"], pb, not holds, up)
        if t != "BinaryExpression" or test["operator"] not in ("<", "<=", ">", ">="):
            return None
        op = test["operator"]
        flip = {"<": ">", "<=": ">=", ">": "<", ">=": "<="}
        if self.binding_of(test["left"]) is pb:
            bound = self.const_num(test["right"])
        elif self.binding_of(test["right"]) is pb:
            bound, op = self.const_num(test["left"]), flip[op]
        else:
            return None
        if bound is None:
            return None
        if not holds:
            op = {"<": ">=", "<=": ">", ">": "<=", ">=": "<"}[op]
        if up and op in ("<", "<="):
            return bound, op == "<="
        if not up and op in (">", ">="):
            return bound, op == ">="
        return None

    def stated_depth(self, fn) -> int:
        """The largest count a function's parameters are given or compared with."""
        params = set()
        stated = 0
        for p in fn["params"]:
            for ident in _pattern_ids(p):
                b = self.scopes_lookup(ident)
                if b is not None:
                    params.add(id(b))
            stated = max(stated, self.stated_param(p))
        for n in self.nodes:
            if (
                n["type"] == "BinaryExpression"
                and n["operator"] in ("<", "<=", ">", ">=", "==", "===", "!=", "!==")
                and self.enclosing_function(n) is fn
            ):
                sides = [n["left"], n["right"]]
                names = [
                    self.binding_of(
                        s["argument"] if s["type"] == "UpdateExpression" else s
                    )
                    for s in sides
                ]
                if any(b is not None and id(b) in params for b in names):
                    stated = max(stated, self.stated_exit(n))
        return stated

    def by_name(self, prop, creations) -> int:
        """Invocations of a function reached only through the key of `prop`.

        Its callers are property reads (`o.run(f)`, a getter's `o.run`), which
        the parse does not resolve to an object, so it is unbounded: ASSUMED
        per function created. Every such read names the key, though, so the
        reads of that name are evidence too, and the larger figure is kept: a
        method a 12-pass loop calls costs 12, not 8. A destructuring read
        (`const { run } = o`) names it too, and a descriptor's `get`, `set` or
        `value` is named by the key `Object.defineProperty` gives it.

        A constructor runs once per instance where every instance is seen
        (see constructions). A method the language calls with no visible call
        (`toString`, `then`, `[Symbol.iterator]`, ...) is costed at HIGH.
        """
        if prop["type"] == "MethodDefinition" and prop["kind"] == "constructor":
            cls = prop["_p"]["_p"]
            made = self.constructions(cls)
            if made is not None:
                return made
            guess = creations * self.unbounded(
                "a method, getter, setter or property function"
            )
            name = cls["id"]["name"] if cls.get("id") else None
            evidence = sum(
                self.count(n)
                for n in self.nodes
                if n["type"] == "NewExpression"
                and n["callee"]["type"] == "Identifier"
                and n["callee"]["name"] == name
            )
            return max(guess, evidence)
        name = self.prop_name(prop)
        if name in IMPLICIT or (
            name is None
            and prop["computed"]
            and self.text(prop["key"]).startswith("Symbol.")
        ):
            guess = creations * self.unbounded_high(
                f"an implicitly called {name or self.text(prop['key'])}"
            )
        else:
            guess = creations * self.unbounded(
                "a method, getter, setter or property function"
            )
        if name is None:
            return guess
        reads = self.members.get(name, []) + self.pattern_keys.get(name, [])
        return max(guess, sum(self.count(m) for m in reads))

    def prop_name(self, prop):
        """The property name a method or property function is reached through."""
        name = _key_name(prop["key"], prop["computed"])
        obj = prop["_p"]
        if name not in ("get", "set", "value") or obj["type"] != "ObjectExpression":
            return name
        p = obj["_p"]
        if p["type"] == "CallExpression" and self.callee_text(p) in (
            "Object.defineProperty",
            "Reflect.defineProperty",
        ):
            args = p["arguments"]
            if len(args) >= 3 and args[2] is obj:
                return _key_name(args[1], True)
        if p["type"] == "Property" and p["value"] is obj:
            outer = p["_p"]
            call = outer["_p"]
            if (
                outer["type"] == "ObjectExpression"
                and call["type"] == "CallExpression"
                and self.callee_text(call)
                in ("Object.defineProperties", "Object.create")
                and len(call["arguments"]) > 1
                and call["arguments"][1] is outer
            ):
                return _key_name(p["key"], p["computed"])
        return name

    def callee_text(self, call) -> str:
        """`Object.defineProperty` for such a call, with the spacing removed."""
        return "".join(self.text(call["callee"]).split())

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
            if not c:
                return 0
            obj = parent["_p"]
            key = _key_name(parent["key"], parent["computed"])
            if (
                parent["type"] == "Property"
                and parent["kind"] == "init"
                and key is not None
                and obj["_p"]["type"] == "VariableDeclarator"
                and obj["_p"]["init"] is obj
                and obj["_p"]["id"]["type"] == "Identifier"
            ):
                # A method of a registry object: follow the object.
                k = self.prop_calls(self.scopes_lookup(obj["_p"]["id"]), key, fn)
                if k is not None:
                    return k * c
            return self.by_name(parent, c)
        else:
            c = self.count(fn)
            if c:
                total += c * self.calls_per_eval(fn)
        for binding in self.fn_bindings(fn):
            for r in binding.reads:
                c = self.count(r)
                if c:
                    total += c * self.calls_per_eval(r)
            if binding.exported:
                total += self.unbounded(f"exported function {binding.name}")
        return total

    def fn_bindings(self, fn):
        """The names a function is reached through: its own, and Annex B's."""
        if not fn.get("id"):
            return []
        scope = (
            fn if fn["type"] != "FunctionDeclaration" else self._scope_of(fn, BLOCKS)
        )
        out = []
        binding = self.scopes.get(scope["_i"], {}).get(fn["id"]["name"])
        if binding is not None and binding.fn is fn:
            out.append(binding)
        if fn["_i"] in self.annex_b:
            out.append(self.annex_b[fn["_i"]])
        return out

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
            k = self.member_store_calls(p)
            if k is not None:
                return k
            return self.unbounded(f"a function assigned to {self.text(p['left'])}")
        if t == "AssignmentPattern" and p["right"] is n:
            # A default: `(fn = () => agent()) => ...` calls it where it calls fn.
            if p["left"]["type"] == "Identifier":
                return self.var_calls(self.scopes_lookup(p["left"]), n, elem=False)
            return self.unbounded("a destructured default")
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
        if t == "TemplateLiteral":
            tagged = p["_p"]
            if tagged["type"] != "TaggedTemplateExpression" or tagged["quasi"] is not p:
                return 0  # interpolated as text
            # A tag receives each substitution as an argument after the strings.
            idx = 1 + next(k for k, e in enumerate(p["expressions"]) if e is n)
            via_param = self.param_calls(tagged, idx, elem=False)
            if via_param is not None:
                return via_param
            return self.unbounded(
                f"a function passed to the tag {self.text(tagged['tag'])}"
            )
        if t in ("ExpressionStatement", "BinaryExpression"):
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
        if t == "PropertyDefinition" and p["value"] is n:
            # A class field holding a function: called through the field's name.
            c = self.count(n)
            return c and math.ceil(self.by_name(p, c) / c)
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
            key = _key_name(p["key"], p["computed"])
            if (
                key is not None
                and decl["type"] == "VariableDeclarator"
                and decl["init"] is obj
                and decl["id"]["type"] == "Identifier"
            ):
                # A registry: `const reg = { run: () => agent() }; reg.run()`.
                k = self.prop_calls(self.scopes_lookup(decl["id"]), key, n)
                if k is not None:
                    return k
            c = self.count(n)
            return c and math.ceil(self.by_name(p, c) / c)
        return self.unbounded(f"a function used as {t}")

    def member_store_calls(self, assign):
        """Calls per evaluation of `o.key = fn` to fn, where the object o names is followed."""
        left = assign["left"]
        if assign["operator"] != "=" or left["type"] != "MemberExpression":
            return None
        key = _key_name(left["property"], left["computed"])
        if key is None:
            key = self.string_value(left["property"]) if left["computed"] else None
        holder = self.binding_of(left["object"])
        if key is None or holder is None:
            return None
        return self.prop_calls(holder, key, assign)

    def prop_calls(self, holder, key, at):
        """Calls per evaluation of `at` to the function it stores under `key`.

        `holder` is the binding of an object literal, followed through every
        read: `holder.key` and `holder[k]` (k unknown) may call it, another key
        does not, and destructuring hands it to a name. Any other read (the
        object passed on, spread, returned), or a method of it handing `this`
        on, hides callers, so it is None. Any other `x.key` in the script may
        be it too (`this.key` in a method, above all) and is charged.
        """
        if (
            holder is None
            or holder.exported
            or holder.writes
            or holder.kind not in ("const", "let", "var")
            or holder.init is None
            or holder.init["type"] != "ObjectExpression"
            or self.hands_on_this(holder.init)
        ):
            return None
        total = 0
        own = set()
        for r in holder.reads:
            q = r["_p"]
            if q["type"] == "MemberExpression" and q["object"] is r:
                own.add(q["_i"])
                name = _key_name(q["property"], q["computed"])
                if name is None and q["computed"]:
                    name = self.string_value(q["property"])
                if (name is not None and name != key) or self._is_write(q):
                    continue
                c = self.count(q)
                if c:
                    total += c * self.calls_per_eval(q)
            elif (
                q["type"] == "VariableDeclarator"
                and q["init"] is r
                and q["id"]["type"] == "ObjectPattern"
            ):
                total += self.count(q) * self._destructured(q, key, elem=False)
            else:
                return None
        for m in self.members.get(key, []):
            if m["_i"] not in own and not self._is_write(m):
                c = self.count(m)
                if c:
                    total += c * self.calls_per_eval(m)
        return math.ceil(total / max(self.count(at), 1))

    def hands_on_this(self, obj) -> bool:
        """True when a method of the object literal uses `this` other than as `this.x`."""
        methods = [
            p["value"]
            for p in obj["properties"]
            if p["type"] == "Property" and p["value"]["type"] == "FunctionExpression"
        ]
        for n in self.nodes:
            if n["type"] != "ThisExpression":
                continue
            p = n["_p"]
            if p["type"] == "MemberExpression" and p["object"] is n:
                continue
            fn = n["_p"]
            while fn is not None and fn["type"] not in (
                "FunctionExpression",
                "FunctionDeclaration",
            ):
                fn = fn["_p"]  # an arrow's `this` is its enclosing function's
            if any(fn is m for m in methods):
                return True
        return False

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
            if name in ("replace", "replaceAll") and idx == 1:
                return self.replacements(call)
            if name == "set" and idx == 1:
                k = self.map_calls(self.binding_of(obj), call)
                if k is not None:
                    return k
        if callee["type"] == "Identifier" and callee["name"] == "pipeline" and idx >= 1:
            return self.mult(self.bound(args[0], call), args[0])
        via_param = self.param_calls(call, idx, elem=False)
        if via_param is not None:
            return via_param
        return self.unbounded(f"a function passed to {self.text(callee)}()")

    def replacements(self, call) -> int:
        """Calls `s.replace(pattern, fn)` makes to fn: one per match."""
        callee = call["callee"]
        pattern = call["arguments"][0]
        regex = self.regex_of(pattern)
        text = self.string_value(pattern)
        if callee["property"]["name"] == "replace" and (
            text is not None
            or (regex is not None and "g" not in regex.get("flags", ""))
        ):
            return 1  # a string pattern, or a regex without /g, matches once
        s = self.string_value(callee["object"])
        if s is not None:
            if text:
                return s.count(text)
            return len(s) + 1  # a pattern matches at most once per position
        return self.unbounded(f"matches in {self.text(callee['object'])}")

    def map_calls(self, holder, at):
        """Calls per evaluation of `at` to each value of the Map `holder` names, or None.

        Followed through every read: `m.get(k)` hands a value on (called where
        its result is), `m.forEach` passes each to its callback, and `has`,
        `set`, `delete`, `clear`, `keys` and `size` call none. Any other read
        (iterated, spread, passed on) is None.
        """
        if (
            holder is None
            or holder.exported
            or holder.writes
            or holder.init is None
            or holder.init["type"] != "NewExpression"
            or holder.init["callee"]["type"] != "Identifier"
            or holder.init["callee"]["name"] != "Map"
            or self.binding_of(holder.init["callee"]) is not None
        ):
            return None
        total = 0
        for r in holder.reads:
            q = r["_p"]
            if q["type"] != "MemberExpression" or q["object"] is not r or q["computed"]:
                return None
            name = q["property"].get("name")
            gp = q["_p"]
            called = gp["type"] == "CallExpression" and gp["callee"] is q
            if name == "size" and not called:
                continue
            if not called:
                return None
            if name == "get":
                c = self.count(gp)
                if c:
                    total += c * self.calls_per_eval(gp)
            elif name == "forEach" and gp["arguments"]:
                k = self.element_param_calls(gp["arguments"][0], 0)
                if k is None:
                    return None
                total += self.count(gp) * k
            elif name not in ("has", "set", "delete", "clear", "keys"):
                return None
        return math.ceil(total / max(self.count(at), 1))

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

    def callee_function(self, callee, depth=0):
        """The function a plain-name callee always refers to, else None.

        Followed through a const alias (`const t = tag`).
        """
        b = self.binding_of(callee)
        if b is None or b.writes:
            return None
        if b.kind == "function" and b.fn is not None:
            return b.fn
        if b.kind == "const" and b.init is not None:
            if b.init["type"] in FUNCTIONS:
                return b.init
            if b.init["type"] == "Identifier" and depth < 8:
                return self.callee_function(b.init, depth + 1)
        return None

    def param_calls(self, call, idx, elem):
        """Calls per evaluation of `call` to what its argument `idx` passes.

        A helper the script defines (`retry(fn)`) calls its parameter where its
        body says so. Every call through that parameter, over all of the
        helper's invocations, is charged to each call site that passes a
        function in -- an upper bound when several sites share the helper.
        An argument that lands in a rest parameter (`(...fns) => ...`) is one
        element of that array, called as often as each of its elements is, and
        so is each element spread into it (`all(...thunks)`). A spread, and an
        argument after one, may land at any position from the fewest
        arguments ahead of it on, so it is charged the most any parameter
        there is called. `f.call(t, a)` passes its arguments from the second
        on, and `f.apply(t, xs)` spreads xs from the first position. An array
        in a rest parameter is unresolved (None). `call` is a call, or a
        tagged template, whose tag receives the substitutions from argument 1
        on.
        """
        tagged = call["type"] == "TaggedTemplateExpression"
        callee = call["tag"] if tagged else call["callee"]
        shift = applied = 0
        if (
            not tagged
            and callee["type"] == "MemberExpression"
            and not callee["computed"]
            and callee["property"].get("name") in ("call", "apply")
        ):
            shift, applied = 1, callee["property"]["name"] == "apply"
            callee = callee["object"]
        target = self.callee_function(callee)
        if target is None or idx < shift or self.reads_arguments(target):
            return None
        if tagged:
            first, exact, spread = idx, True, False
        elif applied:
            if idx != 1:
                return None
            first, exact, spread = (
                0,
                False,
                True,
            )  # the array's elements are the arguments
        else:
            args = call["arguments"]
            # The fewest positions ahead of the argument: a spread may be empty.
            first = sum(a["type"] != "SpreadElement" for a in args[shift:idx])
            spread = args[idx]["type"] == "SpreadElement"
            exact = first == idx - shift and not spread
        params = target["params"]
        rest = bool(params) and params[-1]["type"] == "RestElement"
        plain = len(params) - rest
        positions = (
            [first] if exact else list(range(first, plain)) + [max(first, plain)]
        )
        worst = 0
        for pos in positions:
            k = self._param_total(params, pos, plain, rest, elem and not spread)
            if k is None:
                return None
            worst = max(worst, k)
        return math.ceil(worst / max(self.count(call), 1))

    def _param_total(self, params, pos, plain, rest, elem):
        """Calls made through what lands at argument position `pos`, over every run."""
        per_read = self.elem_calls if elem else self.calls_per_eval
        if pos < plain:
            param = params[pos]
        elif rest:
            if elem:
                return None  # an array inside the rest array
            param, per_read = params[-1]["argument"], self.elem_calls
        else:
            return 0  # past every parameter
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
                total += c * per_read(r)
        return total

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
                args = gp["arguments"]
                # A reduce callback gets the element second, and first too when
                # there is no initial value, which is left unresolved.
                idx = 0
                if name in ("reduce", "reduceRight"):
                    idx = 1 if len(args) >= 2 else None
                if name in PER_ELEMENT and args and idx is not None:
                    k = self.element_param_calls(args[0], idx)
                    if k is not None:
                        # filter and find hand elements on in their result.
                        if name == "filter":
                            k += self.elem_calls(gp)
                        elif name in ("find", "findLast"):
                            k += self.calls_per_eval(gp)
                        return k
            return self.unbounded(f"functions read through .{name}")
        if t == "SpreadElement" and p["_p"]["type"] == "ArrayExpression":
            return self.elem_calls(p["_p"])
        if t == "SpreadElement" and p["_p"]["type"] == "CallExpression":
            # `all(...thunks)`: each element becomes one argument.
            call = p["_p"]
            idx = next(k for k, x in enumerate(call["arguments"]) if x is p)
            via_param = self.param_calls(call, idx, elem=False)
            if via_param is not None:
                return via_param
            return self.unbounded(
                f"functions spread into {self.text(call['callee'])}()"
            )
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
        if (
            t == "AssignmentPattern"
            and p["right"] is a
            and p["left"]["type"] == "Identifier"
        ):
            return self.var_calls(self.scopes_lookup(p["left"]), a, elem=True)
        if t == "ArrayExpression" and a["type"] == "ArrayExpression":
            # `new Map([[key, fn], ...])`: each pair is an entry of the Map.
            entries, new = p, p["_p"]
            if (
                new["type"] == "NewExpression"
                and new["arguments"]
                and new["arguments"][0] is entries
                and new["_p"]["type"] == "VariableDeclarator"
                and new["_p"]["init"] is new
                and new["_p"]["id"]["type"] == "Identifier"
            ):
                k = self.map_calls(self.scopes_lookup(new["_p"]["id"]), new)
                if k is not None:
                    return k
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

    def element_param_calls(self, cb, idx):
        """Calls an array method's inline callback makes to each element.

        `fns.map((fn) => fn())` hands each element to one invocation of the
        callback as parameter `idx`, so each element is called as often as one
        invocation calls that parameter (a returned element is followed where
        the result goes). Every invocation is also handed the whole array two
        parameters later (`(fn, i, arr) => arr[i]()`), and a call through that
        parameter may reach any element, so each element is charged every
        call made through it. A callback named by a function the script
        defines is read the same way (every invocation of it runs the same
        body), and `Boolean`, `String` and `Number` call nothing. None where the
        callback is anything else, or a parameter it sees an element through
        is not a plain name.
        """
        at = cb
        if cb["type"] == "Identifier":
            if self.binding_of(cb) is None and cb["name"] in NON_CALLING:
                return 0
            cb = self.callee_function(cb)
            if cb is None:
                return None
        if cb["type"] not in (
            "ArrowFunctionExpression",
            "FunctionExpression",
            "FunctionDeclaration",
        ):
            return None
        if self.reads_arguments(cb):
            return None
        params = cb["params"]
        # A rest parameter at or before the array's position collects it.
        if any(p["type"] == "RestElement" for p in params[: idx + 3]):
            return None
        per_element = per_array = 0
        for pos, elem in ((idx, False), (idx + 2, True)):
            if pos >= len(params):
                continue  # the callback never sees it
            param = params[pos]
            if param["type"] == "AssignmentPattern":
                param = param["left"]
            b = self.scopes_lookup(param) if param["type"] == "Identifier" else None
            if b is None or b.writes:
                return None
            total = 0
            for r in b.reads:
                c = self.count(r)
                if c:
                    total += c * (
                        self.elem_calls(r) if elem else self.calls_per_eval(r)
                    )
            if elem:
                # Over all invocations of one evaluation, not per invocation.
                per_array = math.ceil(total / max(self.count(at), 1))
            else:
                per_element = math.ceil(total / max(self.inv(cb), 1))
        return per_element + per_array

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
        for b in self.fn_bindings(fn):
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
        if t == "TemplateLiteral" and p["_p"]["type"] == "TaggedTemplateExpression":
            return [("unknown", "the result of a function passed to a template tag")]
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
        parts = []
        if self.labels:
            result["ASSUMED"] = self.assumed
            result["SOURCE"] = ", ".join(self.labels[:2])
            parts.append(
                f"{len(self.labels)} repetition(s) have no static bound "
                f"({result['SOURCE']}) and were costed at {self.assumed} each"
            )
        if self.high_labels:
            result["HIGH"] = self.high
            result["UNBOUNDED"] = ", ".join(self.high_labels[:2])
            parts.append(
                f"{len(self.high_labels)} repetition(s) have no bound at all "
                f"({result['UNBOUNDED']}) and were costed at {self.high}, over the limit"
            )
        if parts:
            result["DETAIL"] = (
                f"~{estimate} agents across {len(self.sites)} call site(s); "
                + "; ".join(parts)
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
        result = Analysis(parse(src), src, assumed, limit).run(limit)
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
        "HIGH",
        "UNBOUNDED",
        "PARSER",
        "FALLBACK",
        "DETAIL",
    ):
        if key in result:
            print(f"{key}={result[key]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

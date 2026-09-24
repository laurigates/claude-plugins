#!/usr/bin/env python3
"""Statically estimate how many agents a Workflow tool script will spawn.

Reads a workflow script on stdin, writes a KEY=VALUE rollup on stdout
(structured-script-output convention) so the calling hook reads a verdict
rather than recomputing the analysis:

    VERDICT=OK|OVER_LIMIT|NO_AGENTS|ERROR
    SITES=<int>            agent() call sites found
    ESTIMATE=<int>         agents the script is expected to spawn
    LIMIT=<int>            the threshold it was compared against
    ASSUMED=<int>          items each unbounded fan-out was costed at (if any)
    SOURCE=<expr>          the fan-out expression(s) that could not be bounded
    SANITIZER=structural|flat  which literal scan decided (see analyze())
    FALLBACK=<reason>      why the flat scan decided (flat only)
    DETAIL=<one line>      human-readable summary

Why static estimation at all: the Workflow tool hands the script to a runtime
that fans out agent() calls across map/parallel/pipeline. The cost of a run is
set almost entirely by how many agents it creates, and that number is knowable
from the script's shape *before* anything runs -- but only when the iteration
source has a literal bound. This module's whole job is to separate
"provably small", "provably large", and "cannot be bounded from the text".

How an unbounded fan-out is costed, and why it is not simply blocked: a
fan-out over a runtime-length list (`args.units`, `review.findings`) is both
extremely common and genuinely unknowable from the text. Refusing all of them
would tax nearly every legitimate workflow; waving them through is what let a
496-agent run start against a 10-agent guideline. So each unbounded fan-out is
costed at ASSUMED items (default 8) and the product is compared to the limit
like any other. One agent per runtime item passes; two or more per item, or a
fan-out nested inside another fan-out, does not -- which is the correct split,
because per-item agent count and nesting depth are exactly what turn a fan-out
into a runaway. The remedy is a visible cap (`.slice(0, N)`), which the bound
resolver recognizes, so the block clears on a one-token edit.

What bounds a fan-out, and what does not: a loop WINDOW is not a bound. A
`for (i = 0; i < xs.length; i += WAVE) { xs.slice(i, i + WAVE) ... }` runs
WAVE agents at a time but one per item in total, so `.slice(i, i + WAVE)`
resolves to the receiver (`xs`, unbounded) rather than to WAVE. Reading it as
WAVE would understate cost by the number of waves; cost is set by how many
agents are created, not by how many run at once (#2670).

Known gaps, deliberately fail-open (an unanalyzable script is NOT blocked):
  - Template-literal interpolations `${...}` are treated as string content, so
    an agent() call written inside one is invisible here. Prompts live in
    templates; calls do not. The interpolation's EXTENT is still parsed, so a
    template nested inside one cannot end the outer literal early. That walk
    can still misread a regex literal holding a quote or brace, so it never
    decides alone: the #2668 flat scan is costed too and the higher estimate
    is reported (see analyze()).
  - An abort guard (`if (xs.length > CAP) return ...`) is not read as a bound.
    The one shipped instance, evaluate-skill's cellCap, is caller-overridable
    (`INPUT.cellCap ?? 30`), so it is not a static bound anyway.
  - Indirection through a helper function (`const fan = xs => parallel(...)`)
    is not followed; the call site reads as a plain call and bounds as unknown.
  - Dynamic array construction (`arr.push(...)` in a loop) is not counted: an
    array grown in place reads as unbounded, costed at the larger of ASSUMED
    and its initializer length plus one (the push), never at the initializer
    length alone.
  - A saved workflow referenced by name has no script text to read at all.
"""

import re
import sys

# Characters that can precede a `(` and still leave it a call rather than a
# grouping paren. Used when walking backwards to find a `.map` receiver.
_IDENT = re.compile(r"[A-Za-z0-9_$]")


class _Unproven(Exception):
    """The structural walk reached text it cannot prove is a literal or comment."""


def _comment_end(src: str, i: int) -> int:
    """Index just past the comment opening at `i`, or `i` when none opens there."""
    if src.startswith("//", i):
        end = src.find("\n", i)
        return len(src) if end < 0 else end
    if src.startswith("/*", i):
        end = src.find("*/", i + 2)
        if end < 0:
            raise _Unproven("block comment runs to end of file")
        return end + 2
    return i


def _string_end(src: str, i: int, quote: str) -> int:
    """Index of the quote closing a literal whose body starts at `i`.

    A template literal's `${...}` interpolation is CODE, and that code may hold
    its own strings and templates -- a prompt with a conditional section is
    `${c ? `with` : `without`}`. Treating the inner backticks as the outer's
    close desyncs everything after it: the inner text is read as code, a stray
    apostrophe there opens a quote that never closes, and every later agent()
    call is blanked as string content (#2670 -- evaluate-skill's preflight call
    vanished this way). So an interpolation is walked with brace and nesting
    awareness to find its real end.

    Walking code means meeting what this scanner cannot parse, chiefly a regex
    literal holding a quote (`${s.replace(/'/g, "")}`): the quote opens a
    "string" that is not one. Raises _Unproven instead of guessing, on the two
    signals that expose it -- a '/" string reaching a newline, which JS forbids,
    or any literal reaching end of file.
    """
    n = len(src)
    while i < n:
        c = src[i]
        if c == "\\":
            i += 2
            continue
        if c == quote:
            return i
        if c == "\n" and quote != "`":
            raise _Unproven("quoted string crosses a newline")
        if quote == "`" and c == "$" and src.startswith("{", i + 1):
            i = _interpolation_end(src, i + 2)
            continue
        i += 1
    raise _Unproven("literal runs to end of file")


def _interpolation_end(src: str, i: int) -> int:
    """Index just past the `}` closing a `${` whose body starts at `i`."""
    n, depth = len(src), 0
    while i < n:
        after_comment = _comment_end(src, i)
        if after_comment != i:
            i = after_comment
            continue
        c = src[i]
        if c in "'\"`":
            i = _string_end(src, i + 1, c) + 1
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            if depth == 0:
                return i + 1
            depth -= 1
        i += 1
    raise _Unproven("interpolation runs to end of file")


def _flat_sanitize(src: str) -> str:
    """The #2668 scan: a literal ends at the next unescaped matching quote.

    Blind to `${...}` nesting, so a template holding a template ends early --
    but it never walks code as if it were a literal, so it cannot blank a whole
    file on a regex it misreads. Kept verbatim: whatever the structural walk
    cannot prove, this scan decides, and beside a proven walk analyze() still
    costs this reading and reports the higher of the two.
    """
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        # Line comment
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                out[i] = " "
                i += 1
            continue
        # Block comment
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            out[i] = out[i + 1] = " "
            i += 2
            while i < n and not (src[i] == "*" and i + 1 < n and src[i + 1] == "/"):
                if src[i] != "\n":
                    out[i] = " "
                i += 1
            if i < n:
                out[i] = " "
                if i + 1 < n:
                    out[i + 1] = " "
                i += 2
            continue
        # String or template literal: blank the body, keep the delimiters so
        # that `[` / `,` scanning still sees a well-formed expression shape.
        if c in "'\"`":
            quote = c
            i += 1
            while i < n:
                if src[i] == "\\":
                    if src[i] != "\n":
                        out[i] = " "
                    if i + 1 < n and src[i + 1] != "\n":
                        out[i + 1] = " "
                    i += 2
                    continue
                if src[i] == quote:
                    break
                if src[i] != "\n":
                    out[i] = " "
                i += 1
            i += 1
            continue
        i += 1
    return "".join(out)


def _structural_sanitize(src: str) -> str:
    """Blank comments and literals, finding each template's extent structurally.

    Raises _Unproven when any comment, string, template, or interpolation does
    not close where JS requires it to.
    """
    out = list(src)
    n = len(src)

    def blank(lo: int, hi: int) -> None:
        for j in range(lo, min(hi, n)):
            if src[j] != "\n":
                out[j] = " "

    i = 0
    while i < n:
        after_comment = _comment_end(src, i)
        if after_comment != i:
            blank(i, after_comment)
            i = after_comment
            continue
        c = src[i]
        if c in "'\"`":
            end = _string_end(src, i + 1, c)
            blank(i + 1, end)
            i = end + 1
            continue
        i += 1
    return "".join(out)


# The code tokens the estimate is computed from. Blanking one of them is the
# only way a sanitizer can LOWER the estimate: a lost agent() site, a lost
# fan-out multiplier, or a lost push() that marks a list as unbounded.
_LOAD_BEARING = re.compile(
    r"\bagent\s*\(|\b(?:parallel|pipeline)\s*\(|\.\s*(?:map|flatMap|push|unshift|splice)\s*\("
)


def _balanced(text: str) -> bool:
    """True when every bracket in `text` closes in order."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    stack = []
    for ch in text:
        if ch in pairs:
            stack.append(pairs[ch])
        elif ch in ")]}" and (not stack or stack.pop() != ch):
            return False
    return not stack


def sanitize(src: str):
    """Blank out comments and string/template bodies, preserving offsets.

    Returns (text, mode, reason). Every removed character becomes a space so that
    offsets computed on the sanitized text index correctly into the original.
    Without this a `//` in a URL or the word `agent(` inside a prompt string
    would be counted as code. A template literal is blanked whole,
    interpolations included (see the known-gaps note in the module docstring).

    The structural walk is returned only when it proves itself (mode
    "structural"); otherwise the #2668 flat scan is (mode "flat", with
    `reason` naming the check that failed): every literal and comment closed
    where JS requires, the remaining code's brackets balance, and every
    load-bearing token the flat scan leaves as code is still code. Those checks
    keep a garbled walk from being costed at all. They do NOT prove the walk
    kept every token that sets a BOUND -- a `{` regex in one template and a `}`
    regex in a later one blank the declaration between them and pass all four
    (#2670 review, round 3) -- which is why analyze() also costs the flat scan
    and keeps the higher figure.
    """
    flat = _flat_sanitize(src)
    try:
        text = _structural_sanitize(src)
    except _Unproven as exc:
        return flat, "flat", str(exc)
    if not _balanced(text):
        return flat, "flat", "brackets do not balance"
    for m in _LOAD_BEARING.finditer(flat):
        if text[m.start() : m.end()] != m.group():
            return (
                flat,
                "flat",
                f"would blank the code token {' '.join(m.group().split())}",
            )
    return text, "structural", ""


def match_forward(text: str, start: int) -> int:
    """Index just past the bracket group opening at `start`. -1 if unbalanced."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    if start >= len(text) or text[start] not in pairs:
        return -1
    stack = [pairs[text[start]]]
    i = start + 1
    while i < len(text) and stack:
        ch = text[i]
        if ch in pairs:
            stack.append(pairs[ch])
        elif ch in ")]}":
            if ch != stack[-1]:
                return -1
            stack.pop()
        i += 1
    return i if not stack else -1


def receiver_of(text: str, dot: int) -> str:
    """Expression to the left of a `.map`/`.flatMap` dot at index `dot`."""
    i = dot - 1
    while i >= 0 and text[i] in " \t\n":
        i -= 1
    end = i + 1
    closers = {")": "(", "]": "[", "}": "{"}
    while i >= 0:
        ch = text[i]
        if ch in closers:
            depth, opener = 1, closers[ch]
            i -= 1
            while i >= 0 and depth:
                if text[i] == ch:
                    depth += 1
                elif text[i] == opener:
                    depth -= 1
                i -= 1
            continue
        if _IDENT.match(ch) or ch in "._":
            i -= 1
            continue
        break
    return text[i + 1 : end].strip()


def top_level_items(inner: str, proven: bool = True) -> int:
    """Length of the array literal whose body is `inner`, as JS counts it.

    Every depth-0 comma ends an element, holes included (`[a, , b]` has length
    3). A final comma with nothing after it does not start one, so the trailing
    comma of a house-style multi-line array (`[a, b,]`) is not a third element
    (#2670). That is the only case where this is below the #2668 count, which
    added one for every comma, and it is the #2668 count that an unproven read
    gets (see analyze()).
    """
    depth, commas, last = 0, 0, ""
    for ch in inner:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            commas += 1
            last = ""
            continue
        last += ch
    if not proven:
        return commas + 1 if inner.strip() else 0
    return commas + (1 if last.strip() else 0)


def unwrap_tail(expr: str):
    """If expr ends in a balanced call .methodName(...), return (receiver, method, args)."""
    expr = expr.strip()
    if not expr.endswith(")"):
        return None
    depth = 0
    open_idx = -1
    for i in range(len(expr) - 1, -1, -1):
        if expr[i] == ")":
            depth += 1
        elif expr[i] == "(":
            depth -= 1
            if depth == 0:
                open_idx = i
                break
    if open_idx <= 0:
        return None
    prefix = expr[:open_idx].rstrip()
    dot_idx = prefix.rfind(".")
    if dot_idx <= 0:
        return None
    method = prefix[dot_idx + 1 :].strip()
    receiver = prefix[:dot_idx].strip()
    args = expr[open_idx + 1 : -1].strip()
    return receiver, method, args


class Grown:
    """A list grown in place: unbounded like None, but never costed below `floor`.

    `const items = [1, ..., 12]` followed by `items.push(x)` holds at least 13
    items on any run where the push executes. Reading it as unbounded alone
    costed it at ASSUMED (8), below the #2668 figure of 12, and the guard went
    silent on a script #2668 asked about (#2670 review, round 4). The fan-out is
    costed at max(floor, ASSUMED).
    """

    __slots__ = ("floor",)

    def __init__(self, floor: int):
        self.floor = floor


def bound_of(expr: str, text: str, seen=None, proven: bool = True):
    """Upper bound on the length of `expr`, or None when it cannot be bounded.

    A list grown by push()/unshift()/splice() returns a Grown: unbounded, with
    the floor its declaration shows. It passes through the same length-keeping
    operations None does, and an explicit `.slice(0, N)` caps it like any list.

    Operations that can only shrink a list (`filter`, `slice`, `flat`) or
    preserve its length (`map`, `reverse`, `sort`) keep the base's bound: an
    upper bound survives them. An explicit numeric slice `.slice(0, N)` or
    `.slice(start, end)` bounds an otherwise unbounded receiver. Single-arg
    `.slice(start)` does NOT bound an unbounded list (it drops `start` items and
    keeps the rest; `.slice(0)` is a shallow copy).
    """
    if seen is None:
        seen = set()
    expr = expr.strip()
    if not expr or expr in seen:
        return None
    seen.add(expr)

    # Method calls on a receiver:
    tail = unwrap_tail(expr)
    if tail is not None:
        receiver, method, args = tail
        if method == "slice":
            # Explicit cap: .slice(0, N) or .slice(start, end)
            m = re.match(r"^(\d+)\s*,\s*(\d+)$", args)
            if m:
                return max(0, int(m.group(2)) - int(m.group(1)))
            # Single-argument slice: drops items, bounded only if receiver is bounded
            return bound_of(receiver, text, seen, proven)
        if method in ("filter", "flat", "map", "reverse", "sort"):
            return bound_of(receiver, text, seen, proven)

    # Array.from({length: N})
    m = re.search(r"Array\.from\(\s*\{\s*length\s*:\s*(\d+)", expr)
    if m:
        return int(m.group(1))

    # Literal array
    if expr.startswith("["):
        close = match_forward(expr, 0)
        if close == len(expr):
            return top_level_items(expr[1:-1], proven)

    # Bare identifier: resolve a const/let/var array literal declaration.
    if re.fullmatch(r"[A-Za-z_$][A-Za-z0-9_$]*", expr):
        declared = _declared_bound(expr, text, seen, proven)
        # An array grown in place is as long as the code that grows it, not as
        # long as its initializer: `const CELLS = []` then `CELLS.push(...)` in a
        # loop read as ZERO items and costed a whole pipeline at nothing (#2670).
        # Its initializer still sets a floor: the push adds at least one item.
        if re.search(
            r"(?<![A-Za-z0-9_$.])"
            + re.escape(expr)
            + r"\s*\.\s*(?:push|unshift|splice)\s*\(",
            text,
        ):
            if declared is None:
                return None
            floor = declared.floor if isinstance(declared, Grown) else declared
            return Grown(floor + 1)
        return declared
    return None


def _declared_bound(name: str, text: str, seen: set, proven: bool):
    """Bound of the const/let/var declaration of `name`, or None."""
    d = re.search(r"\b(?:const|let|var)\s+" + re.escape(name) + r"\s*=\s*", text)
    if not d:
        return None
    rest = text[d.end() :].lstrip()
    if rest.startswith("["):
        close = match_forward(rest, 0)
        if close > 0:
            return top_level_items(rest[1 : close - 1], proven)
    # Non-literal initializer (a call, an await): try its tail form.
    stop = rest.find("\n")
    cand = rest[: stop if stop > 0 else len(rest)].rstrip().rstrip(";")
    if cand and cand != name:
        return bound_of(cand, text, seen, proven)
    return None


def fanouts(text: str):
    """Every fan-out construct.

    Returns (kind, source_expr, body_start, body_end, src_start, src_end); the
    last two span the iteration-source argument of a parallel/pipeline call
    (-1, -1 for `.map`, whose source is the receiver outside the parens).
    """
    found = []
    for m in re.finditer(r"\.(map|flatMap)\s*\(", text):
        open_paren = m.end() - 1
        close = match_forward(text, open_paren)
        if close < 0:
            continue
        found.append(
            (m.group(1), receiver_of(text, m.start()), open_paren, close, -1, -1)
        )

    for m in re.finditer(r"\b(parallel|pipeline)\s*\(", text):
        open_paren = m.end() - 1
        close = match_forward(text, open_paren)
        if close < 0:
            continue
        inner = text[open_paren + 1 : close - 1]
        # parallel(xs) fans over its single argument; pipeline(xs, ...stages)
        # fans over its first. In both cases the first top-level argument is
        # the iteration source.
        depth, cut = 0, len(inner)
        for i, ch in enumerate(inner):
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
            elif ch == "," and depth == 0:
                cut = i
                break
        found.append(
            (
                m.group(1),
                inner[:cut].strip(),
                open_paren,
                close,
                open_paren + 1,
                open_paren + 1 + cut,
            )
        )
    return found


def short(expr: str, width: int = 60) -> str:
    """One-line, length-capped rendering of an expression for messages.

    A fan-out source can be an entire multi-line arrow function; pasting that
    into a hook message buries the one thing the reader needs (which list is
    unbounded) under a wall of text.
    """
    flat = " ".join(expr.split())
    return flat if len(flat) <= width else flat[: width - 1] + "\u2026"


def is_wrapper(kind: str, source: str) -> bool:
    """True when a fan-out's source is itself a fan-out call that drives it.

    `parallel(xs.map(f))` produces a record for `parallel` whose source is
    `xs.map(f)` AND a record for `.map` whose source is `xs`. Both records
    enclose the same agent() site, so counting both multiplies the estimate by
    a phantom factor -- the bug that costed one real script at 4104 agents
    instead of 64. The outer `parallel` is the pass-through and is dropped.
    A `pipeline(xs.map(f), stage1, ...)` is NOT a wrapper: pipeline's stages
    lie outside its first argument, so dropping pipeline would leave stage
    agent() calls with no enclosing fan-out.
    """
    if kind != "parallel":
        return False
    src = source.strip()
    if not src:
        return False
    # `parallel(...)` spanning the whole expression.
    m = re.match(r"parallel\s*\(", src)
    if m and match_forward(src, m.end() - 1) == len(src):
        return True
    # A trailing `.map(...)` / `.flatMap(...)` call.
    for m in re.finditer(r"\.(map|flatMap)\s*\(", src):
        if match_forward(src, m.end() - 1) == len(src):
            return True
    return False


# The only two ways JS runs one code location more than once per evaluation of
# the expression holding it: a loop, or a function that something calls more
# than once. `_runs_once` refuses both unless the repetition is one this
# estimator already multiplies by.
_LOOP_KEYWORD = re.compile(r"\b(?:for|while|do)\b")


def _call_kind(text: str, open_paren: int) -> str:
    """Which modeled fan-out, if any, the `(` at `open_paren` calls."""
    before = text[:open_paren].rstrip()
    if re.search(r"\.\s*(?:map|flatMap)$", before):
        return "map"
    if re.search(r"(?<![A-Za-z0-9_$.])pipeline$", before):
        return "pipeline"
    return "call"


def _function_start(text: str, arrow: int) -> int:
    """Index where the arrow function whose `=>` is at `arrow` begins."""
    k = arrow - 1
    while k >= 0 and text[k] in " \t\n":
        k -= 1
    if k >= 0 and text[k] == ")":
        depth = 0
        while k >= 0:
            if text[k] == ")":
                depth += 1
            elif text[k] == "(":
                depth -= 1
                if depth == 0:
                    break
            k -= 1
    else:
        while k >= 0 and _IDENT.match(text[k]):
            k -= 1
        k += 1
    m = re.search(r"(?<![A-Za-z0-9_$])async\s*$", text[:k])
    return m.start() if m else k


def _skip_space(text: str, j: int, step: int) -> int:
    while 0 <= j < len(text) and text[j] in " \t\n\r":
        j += step
    return j


def _thunks_reach_parallel_once(text: str, frames: list, source_bracket: int) -> bool:
    """True when the thunks a `.map` call returns are each called once.

    `frames[-1]` is the `.map(` call's frame. Its thunks are called once only
    when the array it returns becomes parallel()'s own argument list: it is
    the whole argument of a `parallel(...)` call, a spread `...` element of
    the fan-out's source literal, or an argument of a `.concat(` chained on
    that literal. Kept in a name or indexed (`xs.map(...)[0]`), a returned
    thunk can be called any number of times (#2670 review, round 8).
    """
    map_open = frames[-1][1]
    end = match_forward(text, map_open)
    dot = re.search(r"\.\s*(?:map|flatMap)\s*$", text[:map_open])
    if end < 0 or dot is None or len(frames) < 2:
        return False
    head = text[: dot.start()].rstrip()
    receiver = receiver_of(text, dot.start())
    pre = head[: len(head) - len(receiver)].rstrip()
    j = _skip_space(text, end, 1)
    post = text[j] if j < len(text) else ""
    parent = frames[-2]
    # receiver_of() reads dots as part of a member chain, so a spread's `...`
    # can arrive at the front of the receiver rather than in `pre`.
    spread = receiver.startswith("...") or pre.endswith("...")
    if spread:
        # A spread element of the source literal, or of a `.concat(` argument.
        return post in ",])" and (
            parent[1] == source_bracket or parent is frames[1] and parent[2] == "call"
        )
    if pre[-1:] not in "(," or parent[2] != "call":
        return False
    if post == ",":
        j = _skip_space(text, j + 1, 1)
        post = text[j] if j < len(text) else ""
    callee = text[: parent[1]].rstrip()
    if re.search(r"\.\s*concat$", callee):
        # `[...].concat(xs.map(...))` at the source's top level.
        return parent is frames[1] and post in ",)"
    return (
        post == ")"
        and pre[-1:] == "("
        and re.search(r"(?<![A-Za-z0-9_$.])parallel$", callee) is not None
    )


def _called_once(text: str, start: int, frames: list, source_bracket: int) -> bool:
    """True when the function beginning at `start` runs once per modeled item.

    Only three placements qualify: an element of the fan-out's own source
    literal (a thunk that parallel() calls once), the callback of a
    `.map`/`.flatMap`, and a stage of a `pipeline` -- each of the last two is
    multiplied by its own fan-out. A thunk returned as the concise body of a
    `.map` callback (`xs.map(x => () => ...)`) qualifies only where
    `_thunks_reach_parallel_once` says parallel() calls it. Anything else --
    a callback to an unmodeled call such as `.filter()` or `Array.from()`, a
    function bound to a name and called by hand, a named function expression
    that can recurse, an element of some other array literal (`fs[0](f)` can
    call it any number of times, #2670 review, round 8) -- may run any number
    of times.
    """
    frame = frames[-1]
    prev = text[:start].rstrip()
    if prev.endswith("=>"):
        return (
            frame[2] == "map"
            and bool(frame[3])
            and frame[3][-1]
            and _thunks_reach_parallel_once(text, frames, source_bracket)
        )
    last = prev[-1:]
    kind = frame[2]
    return (
        (kind == "array" and frame[1] == source_bracket and last in "[,")
        or (kind == "map" and last == "(")
        or (kind == "pipeline" and last == ",")
    )


# Words whose `(...)` header may precede a `{` that is not a function body.
# Loop headers are refused earlier by _LOOP_KEYWORD, so only these remain.
_CONTROL_HEADER = re.compile(r"(?<![A-Za-z0-9_$.])(?:if|switch|catch|with)\s*$")
# `function`, optionally `*` and a name, before a parameter list's `(`.
_FUNCTION_HEADER = re.compile(
    r"(?<![A-Za-z0-9_$.])function\s*(?:\*\s*)?(?:[A-Za-z_$][A-Za-z0-9_$]*\s*)?$"
)


def _brace_kind(text: str, brace: int) -> str:
    """Classify the `{` at `brace` as "brace", or "method" for an unmodeled body.

    Every non-arrow function body in JS opens with `{` straight after the `)`
    of its parameter list: `function f(a) {`, a method `run(f) {`, a getter
    `get go() {`, a class method. So a `{` after `)` is a function body unless
    the `(` is a control header's (`if`, `switch`, `catch`, `with`) or
    belongs to a `function` keyword, which the walker already opens a frame
    for. What is left is a method, whose calls the estimator cannot see
    (#2670 review, round 8).
    """
    k = brace - 1
    while k >= 0 and text[k] in " \t\n\r":
        k -= 1
    if k < 0 or text[k] != ")":
        return "brace"
    depth = 0
    while k >= 0:
        if text[k] == ")":
            depth += 1
        elif text[k] == "(":
            depth -= 1
            if depth == 0:
                break
        k -= 1
    if k < 0:
        return "method"
    head = text[:k]
    if _CONTROL_HEADER.search(head) or _FUNCTION_HEADER.search(head):
        return "brace"
    return "method"


def _runs_once(text: str, site: int, lo: int) -> bool:
    """True when `site`, inside a literal-array source starting at `lo`, runs once.

    The literal-array rule drops the fan-out's multiplier, which is right only
    when nothing between the source and the site repeats it. Round 6 checked
    a list of iterating methods, and a `for` loop inside an element, or
    `Array.from({length: n}, fn)`, took #2668's 110 or 200 to 10 (#2670
    review, round 7). So the site runs once only when no loop keyword appears
    between `lo` and it, and every function enclosing it is one `_called_once`
    accepts. A loop or `.map` AFTER the site can repeat it only by calling a
    function that encloses it, so the function check is what covers that
    case, and it holds only as far as the walker recognizes every enclosing
    function: an arrow (`=>`), a `function`, and any other `{` after a `)` (a
    method, getter or class method, see `_brace_kind`). Round 7 missed the
    last, accepted a thunk in any array literal, and accepted a thunk a
    `.map` returned wherever it went (#2670 review, round 8). Refusing costs
    the site as #2668 did, so it never lowers.
    """
    if _LOOP_KEYWORD.search(text, lo, site):
        return False
    source_bracket = text.find("[", lo)
    # Each frame is [bracket, index, kind, open functions' _called_once answers].
    frames = [["", lo, "top", []]]
    i = lo
    while i < site:
        ch = text[i]
        if ch in "([{":
            prev = text[:i].rstrip()[-1:]
            if ch == "(":
                kind = _call_kind(text, i)
            elif ch == "[":
                kind = (
                    "index"
                    if prev and (_IDENT.match(prev) or prev in ")]")
                    else "array"
                )
            else:
                kind = _brace_kind(text, i)
            frames.append([ch, i, kind, []])
        elif ch in ")]}":
            if len(frames) == 1:
                return False
            frames.pop()
        elif ch in ",;":
            # A concise arrow body ends at the next comma or statement end.
            frames[-1][3].clear()
        elif text.startswith("=>", i):
            start = _function_start(text, i)
            frames[-1][3].append(_called_once(text, start, frames, source_bracket))
            i += 2
            continue
        elif text.startswith("function", i) and not (i and _IDENT.match(text[i - 1])):
            if not re.match(r"function\b", text[i:]):
                i += 1
                continue
            m = re.search(r"(?<![A-Za-z0-9_$])async\s*$", text[:i])
            start = m.start() if m else i
            anonymous = re.match(r"function\s*\(", text[i:]) is not None
            frames[-1][3].append(
                anonymous and _called_once(text, start, frames, source_bracket)
            )
            i += len("function")
            continue
        i += 1
    return all(kind != "method" and all(open_fns) for _b, _i, kind, open_fns in frames)


def _risk(result: dict) -> int:
    """Order two readings by what they make the guard do: NO_AGENTS lowest."""
    return result.get("ESTIMATE", -1)


# A regex literal whose body holds a quote or backtick (`/[{}`]/`, `/'/g`).
# Both literal scans read that quote as opening a string and can blank the
# agent code after it, yet the structural walk may still prove itself: its
# literals close and its brackets balance around the gap. The lowering rules
# then applied to BOTH readings of a file whose agent code neither scan saw,
# and a script #2668 asked about went silent (#2670 review, round 5). A `/` is
# read as a regex opener at the start of a line, after any punctuator that is
# not `]` (`)` and `}` included, since after a control header or a block a
# regex can follow), after a spread `...`, after a closing `*/`, after every
# keyword that takes an operand, and after a division `/` followed by
# whitespace (`a / /re/`; without the whitespace `//` opens a comment). Round
# 6's header alternative missed a header spanning lines or nesting parens three
# deep and `export default` (#2670 review, round 7); round 7's punctuator class
# left out `/` itself (round 8). Every listed position is one a regex can
# follow, but the list was built by enumeration and has had to grow three
# times, so a position this pattern misses gets no floor (see analyze()).
# Over-matching (a division after `)` followed by a quote on one line) only
# adds a reading, which can raise an estimate but never lower one. Matching
# every `/` instead would read path prose in 7 of the 8 bundled templates as
# regex and raise two of their budgets (20 -> 71, 49 -> 81).
_QUOTED_REGEX = re.compile(
    r"(?:^|[(),=:!&|?\[{};<>+\-*%~^]|\.\.\."
    r"|\b(?:return|typeof|instanceof|in|of|new|delete|void|throw|case|do|else"
    r"|yield|await|default|extends)"
    r"|\*/|(?<![/*])/(?=\s))"
    r"\s*/(?![/*])(?:\\.|\[(?:\\.|[^\]\n])*\]|[^/\n\\])*?"
    r"[`'\"](?:\\.|\[(?:\\.|[^\]\n])*\]|[^/\n\\])*/",
    re.MULTILINE,
)
_QUOTED_REGEX_REASON = "a regex literal holds a quote"


def analyze(src: str, limit: int, assumed: int = 8) -> dict:
    """Estimate the agent count and compare it to `limit`.

    Costs the proven structural reading AND the #2668 flat scan, and reports
    the higher estimate (ties go to the structural reading). A sanitizer can
    only lower an estimate by blanking code, and the review rounds on #2670
    each found code the structural walk blanked that its proof checks did not
    cover. Taking the maximum makes the guarantee structural rather than a
    list of cases: this estimator never costs a script below its own reading
    of the #2668 scan. The price is that a false positive the walk would have
    removed (prose inside a nested template read as code) is kept whenever
    the flat scan sees it.

    The rules that can cost a script BELOW #2668 (a literal-array element runs
    once; a trailing comma is not an element) apply only to a parse that proved
    itself. When the walk cannot prove itself, the file is one this estimator
    admits it cannot read, so the flat text is also costed with #2668's own
    bound logic and the higher figure is kept: on an unproven parse the
    estimate is never below #2668's. Without that, a regex holding a quote hid
    the code that put a script over the limit from both estimators, and
    dropping #2668's 3x over-count of a literal array beside it turned its
    accidental ask into silence (#2670 review, round 4).

    A parse that proves itself is not enough when _QUOTED_REGEX matches the
    source, i.e. it finds a regex literal with a quote in it: both scans can
    lose the same agent code there, so the flat text is also costed with the
    #2668 bound logic, and that figure is a floor too (#2670 review, round 5).
    A quoted regex that _QUOTED_REGEX does not recognize gets no floor.
    """
    text, mode, reason = sanitize(src)
    # (text, mode, reason, proven): `proven` enables the lowering rules.
    readings = [(text, mode, reason, True)]
    if mode == "structural":
        flat = _flat_sanitize(src)
        readings.append((flat, "flat", "", True))
        if _QUOTED_REGEX.search(src):
            readings.append((flat, "flat", _QUOTED_REGEX_REASON, False))
    else:
        readings.append((text, "flat", reason, False))
    results, failure = [], None
    for index, (text, mode, reason, proven) in enumerate(readings):
        try:
            result = estimate_text(text, src, limit, assumed, proven=proven)
        except Exception as exc:  # noqa: BLE001 - another reading may still succeed
            failure = failure or exc
            continue
        result["SANITIZER"] = mode
        if reason:
            result["FALLBACK"] = reason
        result["_reading"] = index
        results.append(result)
    if not results:
        raise failure
    best = max(results, key=_risk)  # max() keeps the first of equals
    first = results[0] if results[0]["_reading"] == 0 else None
    if first is None and readings[0][1] == "structural":
        best["FALLBACK"] = f"the structural reading raised {type(failure).__name__}"
    elif first is not None and best is not first:
        low = first.get("ESTIMATE", "NO_AGENTS")
        why = readings[best["_reading"]][2]
        if why:
            best["FALLBACK"] = (
                f"{why}; the #2668 bound logic costs it higher ({best.get('ESTIMATE')} > {low})"
            )
        else:
            best["FALLBACK"] = (
                f"the #2668 flat scan costs it higher ({best.get('ESTIMATE')} > {low})"
            )
    for result in results:
        del result["_reading"]
    return best


def estimate_text(
    text: str, src: str, limit: int, assumed: int = 8, proven: bool = True
) -> dict:
    """Cost one sanitized reading `text` of `src` against `limit`.

    `proven=False` costs it with the #2668 bound logic: no literal-array
    element rule and a trailing comma counted as an element (see analyze()).

    A fan-out whose length is only knowable at runtime is not waved through and
    is not hard-blocked either: it is costed at `assumed` items. That single
    mechanism replaces a tier ladder and keeps the limit governing every shape.
    Two agent() sites inside one runtime-length fan-out cost 2 * assumed, which
    is how a "flat" script still trips a limit of 10 -- the real 496-agent run
    was exactly that shape (`pipeline(args.units, editor, reviewer, repairer)`,
    four sites over a list the script never bounds).
    """
    sites = [m.start() for m in re.finditer(r"\bagent\s*\(", text)]
    if not sites:
        return {
            "VERDICT": "NO_AGENTS",
            "SITES": 0,
            "LIMIT": limit,
            "DETAIL": "no agent() call sites found",
        }

    fos = [f for f in fanouts(text) if not is_wrapper(f[0], f[1])]

    estimate = 0
    unknown_sources = []
    for site in sites:
        enclosing = [f for f in fos if f[2] < site < f[3]]
        product = 1
        for kind, source, _s, _e, src_lo, src_hi in enclosing:
            # A site INSIDE a literal-array source is one element of that array,
            # and each element runs once: `parallel([() => agent(a), () =>
            # agent(b)])` is two agents, not four. Multiplying it by the array
            # length costed blueprint-story-audit at 71 instead of 20 (#2670).
            # A site in a pipeline STAGE (outside the source span) still runs
            # once per element, and `.map` over a literal still multiplies. A
            # site under a loop or in a callback this estimator does not model
            # (`.filter()`, `Array.from(..., fn)`) may run any number of times,
            # so it keeps the multiplier (see _runs_once).
            b = None
            if proven and src_lo <= site < src_hi and source.startswith("["):
                if _runs_once(text, site, src_lo):
                    continue
                open_bracket = text.index("[", src_lo)
                if site < match_forward(text, open_bracket):
                    # Inside an element, but repeated by a loop or callback
                    # whose count is unknown: cost it as unbounded, and never
                    # below the literal's own length, which #2668 charged.
                    b = bound_of(source, text, proven=proven)
                    b = Grown(b.floor if isinstance(b, Grown) else (b or 0))
            if b is None:
                b = bound_of(source, text, proven=proven)
            if b is None or isinstance(b, Grown):
                product *= assumed if b is None else max(b.floor, assumed)
                label = short(source) or f"{kind}(...)"
                if label not in unknown_sources:
                    unknown_sources.append(label)
            else:
                product *= max(b, 0)
        estimate += product

    result = {
        "VERDICT": "OVER_LIMIT" if estimate > limit else "OK",
        "SITES": len(sites),
        "ESTIMATE": estimate,
        "LIMIT": limit,
    }
    name_match = re.search(r"\bname:\s*['\"]([^'\"]+)['\"]", src)
    if name_match:
        result["NAME"] = name_match.group(1)
    if unknown_sources:
        result["ASSUMED"] = assumed
        result["SOURCE"] = ", ".join(unknown_sources[:2])
        result["DETAIL"] = (
            f"~{estimate} agents across {len(sites)} call site(s); "
            f"{len(unknown_sources)} fan-out(s) have no static bound "
            f"({result['SOURCE']}) and were costed at {assumed} items each"
        )
    else:
        result["DETAIL"] = f"{estimate} agents across {len(sites)} call site(s)"
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
        src = sys.stdin.read()
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
        "SANITIZER",
        "FALLBACK",
        "DETAIL",
    ):
        if key in result:
            print(f"{key}={result[key]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

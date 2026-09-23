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
    array grown in place reads as unbounded (costed at ASSUMED), never as the
    length of its initializer.
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


def top_level_items(inner: str) -> int:
    """Count comma-separated items at depth 0 inside an array/arg body.

    Only non-empty segments are items: a trailing comma (`[a, b,]`, the house
    style for multi-line arrays) is not a third element (#2670).
    """
    depth, items, segment = 0, 0, ""
    for ch in inner + ",":
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            if segment.strip():
                items += 1
            segment = ""
            continue
        segment += ch
    return items


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


def bound_of(expr: str, text: str, seen=None):
    """Upper bound on the length of `expr`, or None when it cannot be bounded.

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
            return bound_of(receiver, text, seen)
        if method in ("filter", "flat", "map", "reverse", "sort"):
            return bound_of(receiver, text, seen)

    # Array.from({length: N})
    m = re.search(r"Array\.from\(\s*\{\s*length\s*:\s*(\d+)", expr)
    if m:
        return int(m.group(1))

    # Literal array
    if expr.startswith("["):
        close = match_forward(expr, 0)
        if close == len(expr):
            return top_level_items(expr[1:-1])

    # Bare identifier: resolve a const/let/var array literal declaration.
    if re.fullmatch(r"[A-Za-z_$][A-Za-z0-9_$]*", expr):
        # An array grown in place is as long as the code that grows it, not as
        # long as its initializer: `const CELLS = []` then `CELLS.push(...)` in a
        # loop read as ZERO items and costed a whole pipeline at nothing (#2670).
        if re.search(
            r"(?<![A-Za-z0-9_$.])"
            + re.escape(expr)
            + r"\s*\.\s*(?:push|unshift|splice)\s*\(",
            text,
        ):
            return None
        d = re.search(r"\b(?:const|let|var)\s+" + re.escape(expr) + r"\s*=\s*", text)
        if d:
            rest = text[d.end() :].lstrip()
            if rest.startswith("["):
                close = match_forward(rest, 0)
                if close > 0:
                    return top_level_items(rest[1 : close - 1])
            # Non-literal initializer (a call, an await): try its tail form.
            stop = rest.find("\n")
            cand = rest[: stop if stop > 0 else len(rest)].rstrip().rstrip(";")
            if cand and cand != expr:
                return bound_of(cand, text, seen)
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


def _risk(result: dict) -> int:
    """Order two readings by what they make the guard do: NO_AGENTS lowest."""
    return result.get("ESTIMATE", -1)


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
    """
    text, mode, reason = sanitize(src)
    readings = [(text, mode, reason)]
    if mode == "structural":
        readings.append((_flat_sanitize(src), "flat", ""))
    results, failure = [], None
    for text, mode, reason in readings:
        try:
            result = estimate_text(text, src, limit, assumed)
        except Exception as exc:  # noqa: BLE001 - the other reading may still succeed
            failure = exc
            continue
        result["SANITIZER"] = mode
        if reason:
            result["FALLBACK"] = reason
        results.append(result)
    if not results:
        raise failure
    best = max(results, key=_risk)  # max() keeps the first of equals
    if len(readings) == 2 and best["SANITIZER"] == "flat":
        if len(results) == 1:
            best["FALLBACK"] = f"the structural reading raised {type(failure).__name__}"
        else:
            low = results[0].get("ESTIMATE", "NO_AGENTS")
            best["FALLBACK"] = (
                f"the #2668 flat scan costs it higher ({best.get('ESTIMATE')} > {low})"
            )
    return best


def estimate_text(text: str, src: str, limit: int, assumed: int = 8) -> dict:
    """Cost one sanitized reading `text` of `src` against `limit`.

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
            # once per element, and `.map` over a literal still multiplies.
            if src_lo <= site < src_hi and source.startswith("["):
                continue
            b = bound_of(source, text)
            if b is None:
                product *= assumed
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

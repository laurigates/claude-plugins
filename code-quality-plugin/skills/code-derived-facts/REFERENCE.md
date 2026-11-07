# Code-Derived Facts - Reference

Supporting detail for [SKILL.md](SKILL.md) § 3.

## Registry and pattern traps

### A length bound on a pattern can decide a fact

A regex that both **matches a span** and **identifies who it belongs to** does
two jobs, and a bound written for the first silently governs the second. When
the text grows past the bound, the pattern stops matching, and a parser that
falls back to "whatever governed the previous span" reports a plausible, wrong
answer.

> Instance: an attribution pattern bounded a manner clause at 60 characters,
> `\((S\d+)\)\s+([a-z][^.:()]{0,60}?):`. A real clause was 71 characters, so
> that attribution never matched on any run. The span inherited the previous
> speaker, and the parser emitted well-formed output at exit 0 naming the wrong
> speaker, which then served as another tool's ground truth.

Three properties generalise:

- **The bound was redundant.** The character class `[^.:()]` already refused
  to cross a sentence end, a colon or another attribution, and the lazy `*?`
  stopped at the right colon. A magic number inside an already-tight character
  class is a liability with no upside; delete it rather than raising it.
- **It fails toward a plausible value, not toward an error.** A parser with a
  "carry the previous one" fallback cannot report *not found*. A parser that
  yields `None` at least shows a hole.
- **Nothing scales with the prose.** The bound was right when written and
  became wrong when someone wrote a longer string, an edit with no reason to
  think about a regex two files away.

The guard that fixes the class: count the sites with a deliberately looser,
independent pattern and refuse on a shortfall.

```python
ATTRIB_SITE = re.compile(r"\((S\d+)\)[^<>]*?:")   # every site, whatever its clause
...
if len(found) < len(sites):
    raise SystemExit(f"ATTRIB matched {len(found)} of {len(sites)} sites")
```

Verify the guard by re-imposing the old cap (it should report "matched 3 of 4
sites") and by breaking the pattern outright ("matched 0 of 1").

Where to look: any regex whose match also selects something (a speaker, an
owner, a type, a route), with a `{0,N}` or `.{,N}` in it, and a downstream
fallback that carries a previous value forward.

### A hand-listed subset goes stale silently

Code that names members of a collection literally (`FRAME`, `FRAME_WIDE`) misses
the member added later (`FRAME_CLOSE`). Iterate the collection
(`*FRAMES`), never re-list its members. `zip` over two lists of different
lengths truncates silently, so the extra element is processed by nothing and no
failure can reveal it; use `zip(..., strict=True)` or assert equal lengths.

### Two independent numbering systems over the same set must be asserted equal

When one component numbers items from a registry's order and another numbers
them from a schedule's order, a disagreement binds each item to the wrong
partner, and both labels still resolve, so the output looks clean. One
assertion at import time turns an unfalsifiable bug into a build failure.

## Provenance

The dated instances behind these traps (a builder whose tag lists gained set
and voice references, a dialogue format change, an attribution bound) are
recorded in the laurigates/comfyui-nodes repository.

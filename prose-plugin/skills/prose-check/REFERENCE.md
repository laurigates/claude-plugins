# prose-check - Reference

Background on the layered architecture and the tooling mechanics that bite when
adding or debugging a House rule.

## The Three Layers

Each layer exists because of a measured limit in the one above it.

| Layer | Covers | Why not the layer above |
|---|---|---|
| **vale** | token shapes, doc metrics, markdown scoping | code/table/heading skipping is free from its markdown parser; it has **no ordinal scope** — "No scopes select by ordinal position" (docs.vale.sh/topics/scopes) |
| **harper** | grammar, readability, sentence length | independent segmenter; a second opinion on length |
| **script** | paragraph-final position + tic shape, TL;DR footer | the position half of "position plus shape" |
| **model** | *is* this a chiasmus? an aphorism? | irreducibly judgment |

All three tool layers are **optional**. A missing `vale`, `harper-cli`, or `uv`
is reported as `AVAILABLE=false` and the remaining layers still run.

`PATH` alone does not find them. mise puts `vale` behind a shim that is only on
`PATH` in a mise-**activated** shell, and a hook shell is not one — so the
orchestrator probes the mise shim dir and the usual prefixes before giving up,
and reports the binary it settled on as `VALE_BIN=` / `HARPER_BIN=`. Without
that, a hook run on a machine with vale installed would silently drop the layer
that encodes the rubric.

## Three Mechanics That Bite

**A vale rule can fire on nothing and look exactly like a clean document.**
`TicketPlaceholder` shipped broken once: vale **concatenates** `raw:` list
entries into a single pattern rather than OR-ing them the way it does `tokens:`,
so five patterns became one impossible regex that matched nothing. Zero alerts
from a broken rule and zero alerts from clean prose are the same output. A
`raw:` rule therefore needs **one entry with explicit alternation**, and
`tokens:` cannot substitute — it wraps each entry in `\b` word boundaries, which
`[` and `<` can never match. (Angle-bracket placeholders are unreachable
regardless: vale's markdown parser strips them as HTML before any rule sees the
text.)

`fixtures/house-rule-control.md` exists to close this off — it trips every House
rule, and `scripts/check-prose-house-style.sh` asserts each one fires against it.
Do not "fix" the prose in that file. Add a tripping sentence to it whenever you
add a rule.

**The unwrapping step is load-bearing.** pysbd — and every other segmenter
benchmarked — treats a newline as a sentence boundary, and the rules tree is
hard-wrapped at ~76 columns. Without joining hard wraps first,
`communication.md` measures 78 sentences / 8.2 mean words instead of 46 / 15.2.
Those are wrong numbers that look entirely plausible, which is the failure mode
worth knowing about.

**`write-good.E-Prime` is disabled and stays disabled.** Loading `write-good`
wholesale produced 37 E-Prime alerts out of 47 total on `communication.md` — 79%
noise from one rule that flags every form of "to be". The style packages are a
**curated allowlist** in `styles/.vale.ini`, cherry-picked rule by rule. Add a
rule there only when it maps to a criterion the rubric actually states.

---
created: 2026-08-27
modified: 2026-08-27
reviewed: 2026-08-27
name: prose-check
description: "Self-evaluate outward-bound prose against the house rubric — the three tics, end-on-the-fact, TL;DR footer. Use when drafting a PR body, issue body, doc, rule, or commit body before it ships."
args: "[path to the draft] [--kind doc|answer|ticket]"
allowed-tools: Bash, Read, Edit, Grep, Glob
argument-hint: <path to the draft> [--kind doc|answer|ticket]
---

# /prose:check

Run a draft through the house prose rubric before it ships.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| A PR body, issue body, doc, rule, or commit body is drafted and about to ship | The text is already written and just needs shortening — use `prose-distill` |
| Checking whether a draft carries the three tics `communication.md` says to cut | Turning notes into a plan — use `prose-synthesize` |
| A long answer needs a TL;DR (ELI5) footer decision | The artifact must survive a zero-context reader — use `agent-patterns-plugin:cold-read-gate` |
| Wording a ticket body in the neutral register | Assembling the GitHub issue itself — use `git-plugin:github-issue-writing` |

Not for chat responses that never hit a file — there is nothing to lint. Draft
to a file first if you want the check.

## The Rubric This Encodes

`~/.claude/rules/communication.md` is the canonical source. It names three forms
to cut on sight:

| Form | Shape |
|---|---|
| **Chiasmus / mirrored clauses** | A-not-B, B-is-A — content mirrored across a pivot |
| **Significance-assertion** | telling the reader the fact matters instead of stating it |
| **Aphorism / general maxim** | a sentence that would work as a standalone epigram |

The tell is **position plus shape**: the sentence lands at the end of a
paragraph or section, *and* it generalizes past the specific claim.

Everything under `styles/House/` and in `scripts/` is a **derived encoding** of
that rule, not a second source of truth. Each rule file carries a `link:` back
to the rule that owns its criterion, and `scripts/check-prose-house-style.sh` in
the repo root pins the derived copy against drift.

## Execution

```bash
prose-plugin/skills/prose-check/scripts/prose-check.sh --kind doc path/to/draft.md
```

| Flag | Effect |
|---|---|
| `--kind doc` | default; the three tics plus token and grammar layers |
| `--kind answer` | adds the TL;DR (ELI5) footer check for a complex answer |
| `--kind ticket` | same checks; ticket rules (`TicketHype`, `TicketPlaceholder`) carry their own weight |
| `--long-words N` | paragraph-final sentence word threshold (default 40) |
| `--strict` | exit 1 when any candidate is found |

Read the rollup first — `=== PROSE CHECK ===` carries `STATUS=` and
`ISSUE_COUNT=`. Only open the per-layer sections when the count is non-zero.

## Reading the Output — Candidates, Not Verdicts

**Every line the script emits is a sentence to judge, not a defect to fix.**
Whether a mirrored clause is a chiasmus, or a general statement is an aphorism,
is irreducibly a judgment call. The deterministic layers exist to narrow the
candidate set so that judgment lands on a handful of flagged sentences instead
of a whole document — the split in
`.claude/rules/offload-to-deterministic-substrate.md`, applied to writing.

Two consequences worth internalising:

- **A hedge carrying real uncertainty is a true negative that still shows up
  here.** `communication.md` is explicit: hedges that carry real uncertainty,
  stated caveats, and explicit noise floors all stay — they are information.
  Do not strip a `Hedge` hit reflexively.
- **A document that discusses filler words will be flagged for containing
  them.** `prose-distill/SKILL.md` scores weak-word hits because listing filler
  words is its subject matter. That is not a defect in the document or in the
  check.

Verdict types the script layer emits:

| `TYPE=` | Means |
|---|---|
| `significance_assertion` | paragraph-final sentence carries a portentous noun from the rule's own list |
| `chiasmus` | paragraph-final sentence has a negation plus content mirrored across a pivot |
| `aphorism` | paragraph-final sentence restates its own subject in the predicate |
| `long_final_sentence` | paragraph closes on a sentence at or above the word threshold |
| `long_sentence` | any sentence at or above the threshold — position-independent |
| `missing_tldr_footer` | `--kind answer` only; complex enough to warrant a footer, none present |

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

## Fixing What You Confirm

`communication.md` gives the fix in one line: **end on the fact.** State the
mechanism or the number and stop. If the significance genuinely is not obvious
from the fact, add one plain clause — never a mirrored or generalizing one.

The script never rewrites. It locates; you decide.

## Hook

`hooks-plugin/hooks/prose-house-style-nudge.sh` runs the same check
automatically after a `Write`/`Edit` of a `.md` file and before
`gh pr create` / `gh issue create`. It **never blocks** — style is a nudge, per
`.claude/rules/hook-block-vs-nudge.md` — and is opt-in behind
`CLAUDE_HOOKS_ENABLE_PROSE_CHECK=1`.

## Agentic Optimizations

| Context | Approach |
|---|---|
| One draft file | `prose-check.sh --kind <kind> <file>`; read the rollup, open sections only if `ISSUE_COUNT` > 0 |
| Many files | pass them all in one invocation — the script batches and reports per file |
| Tool missing | check the `*_AVAILABLE=false` line before concluding a document is clean |
| Pre-commit / CI | add `--strict` to turn candidates into a non-zero exit |

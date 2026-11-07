# Git Issue Scoping — Incident Evidence

The observed failures behind each rule in [SKILL.md](SKILL.md). Each section
names the SKILL.md section it backs. Read the one for the rule you are about
to apply or argue with; the rules themselves stay in SKILL.md.

## The trap: jnv #114, a summary that dropped the design

Backs [The trap](SKILL.md#the-trap) and [The rule](SKILL.md#the-rule).

> Canonical break (jnv #114 → PR #116, 2026-06): a WebFetch summary presented the
> issue as "extend completion beyond JSON paths." The actual 33-comment thread was
> a design discussion in which the maintainer and the jaq author had converged on
> **token-based segmentation** (jaq's `load::lex` token trees) plus a new `yield`
> filter (an *unmerged* jaq PR) for the in-paren case, with an explicit scope
> ladder. We built a byte-scanner PoC and a PR body that re-litigated settled
> questions — caught only when the user asked "did we check all the comments?"
> The PR had to be reframed before it was safe to surface.

## A bot's recommendation: two PRs citing a decision nobody made

Backs [A bot's recommendation is not a maintainer decision](SKILL.md#a-bots-recommendation-is-not-a-maintainer-decision).

> Observed 2026-09-04 (`claude-plugins` #2441, #2568): two agents in one batch
> independently read a `<!-- routine:needs-decision v1 -->` comment's own
> "I'd default to A" as the maintainer's choice and wrote it into their PR
> bodies as settled. Both issues carried **exactly one comment** — that request
> — with no reply, no reactions, and no review. On #2441 the routine had
> recommended B, the agent shipped A, and the human's actual answer was B, so
> the PR was built on the wrong option *and* cited an authority that did not
> exist. Caught by an independent verifier running `--jq '.comments | length'`.

## Your own tracker: a duplicate and a reversed deferral, ten minutes apart

Backs [Your own tracker — search before filing, read before reversing](SKILL.md#your-own-tracker--search-before-filing-read-before-reversing).

> Observed 2026-08 (pal-mcp-server), ten minutes apart: filed a detailed issue
> duplicating a month-old one that had already diagnosed the same broken publish
> pipeline — then merged a PR doing the very migration that issue **explicitly
> deferred**. Neither was caught by review; both surfaced only from listing open
> issues afterwards.

## Cited evidence expires: thelma #1055, a control added after filing

Backs [An issue's cited evidence expires](SKILL.md#an-issues-cited-evidence-expires--re-verify-every-line-before-acting-on-it).

> Observed 2026-08-13 (thelma #1055). A security issue's central claim was
> "no `responseSchema` enforcement on the Gemini call — `gemini.ts:230` does
> not pass it." True when filed on 05-13; false by the time it was worked.
> #1060 had added it in between. The issue even listed *"`responseSchema`
> enforcement is deliberately removed (currently absent)"* as a trigger to
> re-evaluate — so writing the doc from the issue verbatim would have shipped
> a threat model asserting the absence of the control that was by then its
> primary defence, and inverted one of its own triggers.

# Closing Keywords: Past Tense and Quoted Forms

Moved verbatim from `SKILL.md` §5. Read before writing or auditing a PR body, issue comment, or rules file that mentions issue numbers.

### It is not only negation — plain past tense in a follow-ups section does it

The rule in [SKILL.md §5](../SKILL.md#5-a-negated-closing-keyword-still-closes-the-issue) reads as "watch out for the word *not*". The trap is wider: **any**
closing verb adjacent to a reference matches, including one merely *describing*
what already happened, and including a reference wrapped in a **markdown link**.

> Observed 2026-08-16 (comfyui-nodes fleet). A PR body's follow-ups section
> asked for an issue to be re-opened, describing it as one this bug had
> **closed** on a false premise. GitHub matched the closing verb against the
> bracketed cross-repo link that followed it and closed the issue on merge — a
> line whose entire purpose was to request a re-open. The author had cited this
> very rule earlier in the same session.

Three amplifiers:

- **A bracketed cross-repo link still matches.** A closing verb followed by a
  markdown-linked `owner/repo#N` is a match, and a naive audit regex like
  `keyword\s+[\w./-]*#\d+` misses it on the `[` — then reports the body clean.
- **A shared fleet body multiplies it.** The same text went into 13 sweep PRs, so
  13 merges each targeted the same issue.
- **The actor is *you*, not a bot** — the timeline reads `closed by <you>` seconds
  after the merge. Don't rule out a closing keyword because no bot appears.

### And not only assertion — a keyword you are *quoting* still fires

The two forms in [SKILL.md §5](../SKILL.md#5-a-negated-closing-keyword-still-closes-the-issue) and
[§ It is not only negation](#it-is-not-only-negation--plain-past-tense-in-a-follow-ups-section-does-it) are sentences that *mean* something about an issue. The
third means nothing about it at all: the keyword appears inside an **example, a
fixture, or a regex you are documenting**. GitHub does not care that the line is
inside backticks, a code fence, or a sentence whose subject is the audit itself.

> Observed 2026-08-17 (FVH `infrastructure` #2213). A PR body's verification
> section reported that a closing-keyword scan returned zero hits, and quoted
> its two control fixtures inline as evidence. The scan it was reporting on had
> genuinely passed — on the *ADR file*. Run against the PR body, the same regex
> matched the body's own worked examples, which would have closed an unrelated
> issue on merge. Caught only because the scan was re-run against the artefact
> about to be published, rather than the one it was describing.

Two things generalise:

- **Scan the artefact you are about to publish, not the one you were auditing.**
  A PR body, an issue comment, and a rules file each need their own pass; a clean
  result on one says nothing about the others.
- **Do not reproduce the fixture in prose that ships.** Describe it — "control-
  tested against a bare reference and a bracketed cross-repo link, both found" —
  and keep the literal strings in the throwaway file. Documenting the trap is
  the one context where you are *guaranteed* to type the trap.

**Audit the body before merging, with a control.** Scan every PR you are about to
merge for a closing verb adjacent to an issue reference, allowing an optional
`[` and an optional `owner/repo` between them, and prove the scan works by
confirming it finds a reference you *know* is there. A negative from an
unvalidated regex is worth nothing — the first audit run in the quoted-fixture case
([§ And not only assertion](#and-not-only-assertion--a-keyword-you-are-quoting-still-fires)) reported the fleet clean.

The damage is a **false status report**: 2026-08-05, a PR body written to
disclaim closure closed loractl #162 at merge, and the session reported it open
for two turns afterward. Like #2, GitHub does this silently — only re-reading
issue state from the API catches it.

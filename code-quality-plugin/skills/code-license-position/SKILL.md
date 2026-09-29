---
name: code-license-position
description: Check a vendor's licence FAQ and discussion threads before calling a LICENSE restriction a blocker. Use when a model or dependency licence seems to forbid use.
allowed-tools: Bash, Read, WebFetch, Grep, TodoWrite
created: 2026-09-29
modified: 2026-09-29
reviewed: 2026-09-29
---

# Verify the Licensing *Position*, Not Just the LICENSE File

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| A `LICENSE` for an open-weights model or source-available dependency seems to forbid your use (territory, entity, field-of-use carve-out) | Auditing a whole dependency tree for licence compatibility — use `code-quality-plugin:code-dep-audit` |
| A licence conclusion is about to land in a public issue, PR, or doc | Deciding whether to contribute upstream at all — use `git-plugin:git-issue-scoping` |

A `LICENSE` reads complete and authoritative, so a restriction found in it gets
reported as settled fact. But for source-available models and dependencies the
vendor's *actual* position routinely lives in two other places **in the same
repo**: a licence FAQ, and the discussion tab. Read the licence, then go find
those, before telling anyone a licence blocks the work.

> Canonical break (2026-08, `MiniMaxAI/MiniMax-H3`): `LICENSE` §I.5 excludes the
> EU, UK, South Korea and USA from the "Applicable Territory", and §V.4 bars use
> — even distribution of *Outputs* — outside it. That was reported as a hard
> blocker in a public issue. The same repo's `docs/QA-about-License.md` frames
> the carve-out as regulatory caution, *"not yet, not ever"*, and links an
> application form; a maintainer in HF discussion #12 wrote **"apply will auto
> get access"** and told individuals to put `Personal/None` in the mandatory
> Company Name field. The blocker was a form. Corrected twice, publicly.

## Execution

1. **List the repo's own licence docs** alongside `LICENSE`:

   ```
   curl -s https://huggingface.co/api/models/<owner>/<repo> | jq -r '.siblings[].rfilename' | grep -iE 'licen|faq|qa|terms'
   ```

   GitHub analogue: `gh api repos/<owner>/<repo>/contents` for a licence FAQ.

2. **Read the discussion threads** that mention the licence:

   ```
   curl -s https://huggingface.co/api/models/<owner>/<repo>/discussions/<n> | jq -r '.events[] | select(.type=="comment") | "=== \(.author.name)\n\(.data.latest.raw)\n"'
   ```

   GitHub analogue: the issue and Discussions tabs.

3. **Establish who speaks for the vendor.** HuggingFace's `isOwner` is **not**
   the authority test — it reads `false` for every human commenter, staff
   included. Check **commit authorship**; write access, especially authorship
   of the licence or FAQ commit itself, is the signal:

   ```
   curl -s https://huggingface.co/api/models/<owner>/<repo>/commits/main | jq -r '.[] | "\(.date)\t\(.authors[]?.user // "?")\t\(.title)"'
   ```

   GitHub analogue: `author_association` (`MEMBER` / `OWNER`) — not a field on
   `gh pr view --json`; read it from `gh api`.

4. **Act on the written grant, not the forum reply.** In the canonical case the
   informal replies were **looser than the documents they explained**: the QA
   doc said MiniMax *"may authorize"* after review, the maintainer said *"auto
   get access"*, and one reply ("you don't need apply" to distribute Outputs
   into excluded regions) contradicts §V.4 on its face. A reply is evidence a
   path exists, not the path. Report the divergence rather than silently
   adopting the permissive reading.

5. **Report the position**, not just the clause: licence text, FAQ framing,
   application path (if any), who said what with their authority, and where
   they diverge.

## When it bites

- Evaluating an open-weights model or source-available dependency as a project
  target — exactly where a "we can't use this" verdict gates real work.
- **Geography or entity carve-outs specifically.** These are usually regulatory
  caution with an application path attached (AI Act, pending litigation), not
  prohibition. Treat "Excluded Territories" as "ask", not "no".
- Any licence conclusion about to be written into a public artifact. The
  correction is public too.

Do not design around the restriction (jurisdiction shopping, hosting in a
non-excluded region) before checking whether the vendor simply grants
exceptions. The workaround is usually more effort *and* more risk than the form.

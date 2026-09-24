---
name: probe-input-integrity
description: Take probe identifiers from the system, run a known-good control, extract (never retype) the code under test, make stubs executable. Use when probing an endpoint, id, path or test harness.
allowed-tools: Read, Glob, Grep, Bash(gh *), Bash(curl *), Bash(sed *), Bash(chmod *), Bash(ls *), Bash(command *), TodoWrite
created: 2026-09-24
modified: 2026-09-24
reviewed: 2026-09-24
---

# Probe Input Integrity — Never Fabricate an Identifier You're About to Test Against

Promoted from the always-loaded `~/.claude/rules/never-fabricate-test-identifiers.md`
rule, whose stub keeps the gate lines. The body below is that rule's text.

When probing a system — an API endpoint, a URL, a record id, a file path, a
ticket number — **obtain the identifier from the system itself. Never invent a
plausible-looking one.** A fabricated identifier turns every subsequent
observation into a two-variable experiment ("is the endpoint blocking me, or
does this thing simply not exist?"), and the two failure modes are routinely
indistinguishable in the response.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| About to probe an endpoint, URL, record id, path or ticket number | An empty *search* result is about to gate an action → `tool-result-traps` |
| Building a harness around code that is awkward to run directly | A named entity in an error may be a zero/default sentinel → `code-quality-plugin:debugging-methodology` |
| Stubbing a CLI on `PATH` for a local test | Verifying premises before a wave dispatch → `verify-before-plan` |
| Your own target set is empty, so a sweep would be green by construction | |

## The trap

The fabricated value *looks* real, so it never gets questioned. Its failure then
gets attributed to the hypothesis actually under test.

> Canonical break (2026-07, a research repo): investigating whether Reddit's
> `.json` endpoint still worked, I made up a thread URL —
> `/r/LocalLLaMA/comments/1i6r9rp/deepseek_r1_is_now_available_on_azure` — a
> plausible id and slug, entirely invented. It returned `403 Blocked`, as did two
> further probes against the same fake thread. I reported the endpoint as
> IP-blocked. The user said "it works in my browser," and the *first* successful
> request revealed the truth: the endpoint returned a JSON **404** — the thread had
> never existed. The real discriminator was the client fingerprint, not the IP, and
> three "conclusive" probes had been testing a nonexistent resource.

The tell that should have fired: `403` and `404` mean very different things, and I
never established which I'd get for a *known-good* id.

## The rule

**Get a real identifier from the source before probing. List before you get.**

```
# Wrong — invent a plausible thread, then test against it
curl https://www.reddit.com/r/X/comments/<made-up-id>/<made-up-slug>.json

# Right — pull a real one out of the system first, then probe that
curl -s https://www.reddit.com/r/X/ | grep -o '/r/X/comments/[a-z0-9]*/[a-z0-9_]*/'
```

Generally: a listing/search call before an item call. `gh issue list` before
`gh issue view <n>`; `Glob`/`ls` before `Read`; a collection endpoint before an
item endpoint.

**Always run a known-good control.** When a probe fails, repeat it against an
identifier you *know* exists. Without a control you cannot separate "access
denied" from "not found" from "wrong shape" — and each implies a completely
different fix.

## Don't fabricate the *subject* either — extract the code, don't retype it

The same trap one level up. When you build a harness to exercise code that is
awkward to run directly, **a retyped copy of that code is not that code**. It
reads as identical in the transcript, and when it misbehaves the failure is
attributed to the code under test rather than to your transcription.

> Observed 2026-08 (a ComfyUI node-pack fleet): verifying new `just prs` / `just merge`
> recipes over a 14-repo fleet that happened to have **zero** open PRs. The
> harness retyped the kind comparison as `[ "$k" = "'release'" ]` — literal
> quotes, matching nothing — and reported `PLAN=0` for every kind. That is
> precisely what "no PR qualifies" looks like. Extracting the shipped loop
> straight out of the justfile with `sed` and re-running produced the correct
> per-kind plans and skip reasons.

- **Extract the shipped text**, e.g. `sed -n '/start/,/end/p' <file>`, and feed
  it the inputs. Never hand-paste the logic under test into the harness.
- **When your own target set is empty, borrow a control set.** A sweep over
  zero items is green by construction and asserts nothing. Point the extracted
  code at real objects from elsewhere that cover every branch — for the recipes
  above, live PRs from other repos spanning release (bot- *and* human-authored)
  / deps / mine / external, plus draft, `BLOCKED`, `UNSTABLE`, and
  failing-checks.

An empty run and a broken harness produce the same output. Only the control
tells them apart.

## Don't fabricate the *environment* either — an inert stub means the real tool ran

The third form. The subject is real and the inputs are real, but the harness
never took effect: a stubbed CLI placed on `PATH` that is **not executable** is
skipped by PATH lookup in silence, and the real binary runs instead. Nothing
warns. The run completes, prints plausible output, and — if the real tool has
side effects — performs them.

> Observed 2026-08 (an infrastructure repo): testing a workflow step that posts
> a PR comment, I wrote a fake `gh` onto `PATH` with the Write tool, which does
> not set the executable bit. The real `gh` ran, and what was framed as a local
> test **POSTed and then PATCHed a comment onto a live PR**. It surfaced only
> because the output carried a real comment ID where the stub's canned `12345`
> was expected. Re-running with `chmod +x` behaved correctly.

- **Set the bit and check it.** `chmod +x <stub>` via Bash after any Write, then
  `ls -l`. File-creation tools generally do not set the executable bit.
- **Assert the stub is the one in effect before trusting any case.**
  `command -v <tool>` at the top of the harness, or better, have the stub print
  a sentinel the real tool never would and fail the run if it is absent.
- **Make the stub's output impossible to mistake for the real thing** — a canned
  `12345` beats a realistic-looking id, so a discrepancy is visible at a glance
  rather than plausible.
- **Treat "it's only a local test" as a reason for more isolation, not less.**
  That framing is what suppresses the caution normally applied to a command that
  writes to shared state, and whether the writing tool runs is precisely what is
  in question.

Same law as the two forms above, one layer out: the harness was green while
measuring production.

## When it bites

- Diagnosing whether an endpoint, credential, or permission works — exactly where a
  wrong conclusion triggers a redesign that was never needed.
- Writing tests or repro cases against "example" ids nobody verified exist.
- Citing an issue/PR/commit number from memory instead of looking it up. A
  plausible-but-wrong `#162` is worse than no number: it reads as researched.

## Relationship to sibling rules

- `verify-upstream-before-patching.md`, `verify-machine-facts-before-publishing.md` —
  same instinct (consult the authoritative source before acting). This skill covers
  the *inputs to your own diagnostics*, not the code you patch or the facts you
  publish.
- `tool-result-traps` and `harness-tool-errors` (Read on a missing path; the `rg -r`
  fabrication trap) — siblings in the same family: a confidently-wrong output that
  looks exactly like a real one.

## Rationale

An invented identifier is a silent confound. It costs one extra lookup to obtain a
real one, and one extra probe to run a control; skipping both bought a wrong root
cause, a confidently-reported non-finding, and a diagnosis that unravelled only
because a human said "but it works for me." The model will not catch this on its
own — in the transcript, a fabricated value looks exactly as legitimate as a real
one.

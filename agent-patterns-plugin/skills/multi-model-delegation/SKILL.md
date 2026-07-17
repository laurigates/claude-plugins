---
name: multi-model-delegation
description: Multi-model design consults via PAL (kimi, glm, gemini, gpt). Use when asking other models to brainstorm a design or reconciling their split answers.
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite, mcp__pal__listmodels, mcp__pal__chat, mcp__pal__consensus, mcp__pal__thinkdeep
model: opus
created: 2026-07-17
modified: 2026-07-17
reviewed: 2026-07-17
---

# Multi-Model Delegation

Protocol for consulting *other* models — kimi, glm, gemini, gpt via the PAL
MCP gateway (`chat`, `consensus`) — on design and judgment work, and for
acting on what comes back. The core insight, which inverts the naive
approach:

> **The value is the disagreement, not the union.** Two competent models
> briefed identically converge on the obvious 80% — the part you'd have
> written anyway. Where they **split** is a precise pointer at the one
> decision that is genuinely load-bearing and underdetermined by the prompt.
> Resolve the split against **the codebase** — which usually already decided,
> and which the models structurally cannot see — never by picking the more
> confident model.

Treat delegated models as *idea generators*, never as *authorities*. Taking
the majority answer, or the more confident one, launders a coin-flip into a
decision that merely looks researched.

You — the orchestrating Claude session — run the whole consult: you dispatch
the PAL MCP calls, collect the replies, and do the judgment steps (diff,
adjudicate, synthesize) yourself in the main loop.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|---|---|
| Brainstorming an open design decision with foreign models (PAL `chat`/`consensus`) | Fanning out **Claude subagents** that do work → `parallel-agent-dispatch`, `agent-teams` |
| Reconciling two models' conflicting design proposals | Red-teaming a *finished* artifact → `adversarial-review` |
| Deciding whether a multi-model consult is worth the tokens | A lookup answers the question → PAL `apilookup`, official docs |

## The Protocol

Execute a multi-model consult in these steps:

### Step 1: Resolve model IDs first

Run `mcp__pal__listmodels` once at the start of the consult whenever a model
is named loosely ("kimi2.7", "glm5.2") — registry IDs (`kimi-k2.7-code`,
`glm-5.2`) and their aliases (`kimi`, `glm`) rarely match what anyone types
from memory.

### Step 2: Brief every model with the same prompt

Send the identical brief, verbatim, to each model — one `mcp__pal__chat`
call per model — and collect every reply before judging any of them.
Different prompts produce divergences that are artifacts of the framing, not
of the problem — and afterward you cannot tell a real design tension from a
wording accident. Pass code via the `absolute_file_paths` parameter rather
than pasting it into the prompt: it is what the parameter is for, and the
pasted copy risks truncation.

### Step 3: Keep round one independent

Withhold model A's answer from model B. You want independent draws, not an
echo. Cross-critique is a deliberate *later* round, never the first one.

### Step 4: Diff the answers for the split

With every reply collected, compare them point by point:

- **Convergence** → the safe default; adopt it and move on.
- **Divergence** → this is the actual decision, and it is now yours — not
  theirs. Don't ask "which answer do I take?" Ask "what did they disagree
  about, and what in my codebase already decides it?"

### Step 5: Adjudicate against the code, not taste

Go read the thing the decision turns on. Very often the codebase has
*already decided*, and the models couldn't know because they can't see it.
This is the step that makes the whole exercise worth its tokens.

### Step 6: Graft, never adopt wholesale

Even the winning proposal carries ideas that are wrong for your repo. Graft
the good parts from the runner-up; reject what doesn't fit and say why.

> Canonical case (gh-board priority grading, 2026-07): `kimi-k2.7-code` and
> `glm-5.2`, identical briefs. They converged on the module shape and
> config-first weights, and both independently proposed a contribution
> ledger — the one idea not already in hand, and the one convergent idea
> worth keeping. They split on exactly one question: does the triage bucket
> feed the priority score, or sit above it? One minute in
> `src/app/filter.rs` settled it — `build_rows` already groups into bucket
> sections *after* sorting, so a bucket baseline would double-count the
> grouping. Both models also proposed an A–F letter grade; **both were
> overruled** — grade bands stack a second set of magic thresholds on the
> weights and quantize away the fine ordering the score exists to produce.
> The models produced the *question*; the repo produced the *answer*.

## When It's Worth the Tokens

| Worth it | Skip it |
|---|---|
| Open design decision with a wide solution space and no conventional default — scoring models, architecture splits, API shape, migration strategy | Anything with a conventional default: pick it, state it, proceed |
| Genuinely underdetermined trade-offs where an independent draw adds information | A lookup or doc read answers it |
| | Seeking agreement on a decision already made — a model asked to validate **will** validate; you pay for confirmation, not information |

## PAL Mechanics That Bite

- **`kimi-k2.7-code` 400s whenever `temperature` is sent** (OpenCode Go
  provider). The error is opaque — `Error from provider (Console Go):
  Upstream request failed` — naming neither the parameter nor the
  constraint, so it reads as flakiness or as "prompt too long". Prompt
  length, file attachments, and `thinking_mode` are all innocent; `glm-5.2`
  accepts `temperature` fine. Omit `temperature` for kimi. Tracked:
  [laurigates/pal-mcp-server#67](https://github.com/laurigates/pal-mcp-server/issues/67).
- **Isolate a model failure with controlled probes before believing your
  first theory.** The intuitive suspects (big prompt, file attachments) were
  both innocent here, twice — a bug filed on either would have sent the
  maintainer down the wrong path. A two-word prompt plus the one suspect
  parameter settles it in a single call.

## Agentic Optimizations

| Context | Command |
|---|---|
| Resolve registry IDs and aliases | `mcp__pal__listmodels` |
| Independent round-one draw (repeat per model, same prompt) | `mcp__pal__chat` with `model` + `absolute_file_paths`; omit `temperature` for kimi |
| Structured multi-model verdict with per-model stances | `mcp__pal__consensus` |
| Deep single-model dig after the split is found | `mcp__pal__thinkdeep` |

## Related

- `parallel-agent-dispatch` — delegating *work* to Claude subagents: those
  are delegates producing output; this skill's models are second opinions
  producing judgment
- `agent-teams` — implicit-team / SendMessage mechanics for Claude teammates
- `adversarial-review` — inverted-objective second pass on a finished
  artifact, by an isolated Claude reviewer
- `verify-before-plan` — the same adjudicate-against-reality instinct,
  applied to orchestrator premises before a dispatch

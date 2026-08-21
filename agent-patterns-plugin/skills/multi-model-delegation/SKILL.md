---
name: multi-model-delegation
description: Multi-model design consults via PAL (kimi, glm, gemini, gpt). Use when asking other models to brainstorm a design or reconciling their split answers.
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite, mcp__pal-mcp-server__listmodels, mcp__pal-mcp-server__chat, mcp__pal-mcp-server__consensus, mcp__pal-mcp-server__thinkdeep
model: opus
created: 2026-07-17
modified: 2026-08-21
reviewed: 2026-08-21
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

## The Tool Prefix Is Derived, Not Fixed

PAL's tools are reachable as **`mcp__<server-name>__<tool>`**, where
`<server-name>` is the key the server is **registered under** — not the product
name, and not the binary. That key can live in any registration scope: a
project `.mcp.json`, a **user**-scope entry in `~/.claude.json`
(`claude mcp add -s user …`, which has no `.mcp.json` at all), or a local one.
So read the registration rather than a file — `claude mcp list` is
authoritative in every scope, and `claude mcp get` names the scope that owns it:

```bash
claude mcp list                 # "pal-mcp-server: pal-mcp-server  - ✔ Connected"
claude mcp get pal-mcp-server   # Scope: Project config (shared via .mcp.json)
```

With the common registration `pal-mcp-server`, `chat` is
`mcp__pal-mcp-server__chat`; a repo that registers the same binary under a
different key gets that key in the prefix instead. Every
`mcp__pal-mcp-server__*` name below assumes that registration — substitute the
key `claude mcp list` reports.

### `No matching deferred tools found` has two causes

Do not read that message as proof the prefix is wrong — under the **correct**
prefix it means something else entirely, and the two want different responses:

| What you observe | Cause | Do this |
|---|---|---|
| The prefix you tried is not the key `claude mcp list` reports | Wrong prefix | Retry with the reported key |
| The **correct** prefix also finds nothing, PAL's tools never appear in any deferred-tool reminder, yet `claude mcp list` says Connected | The server's tools were never registered *in this session* — likely it connected after session start | Restart the session, or drive the server directly over stdio JSON-RPC (issue #2437) |

One trap in that direct-stdio workaround, worth stating because its symptom
misleads: **keep stdin open until the response arrives.**
`subprocess.run(..., input=...)` closes stdin after writing, so the server shuts
down mid-call and returns an empty result that looks exactly like a hung or
non-responding model rather than a transport error.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|---|---|
| Brainstorming an open design decision with foreign models (PAL `chat`/`consensus`) | Fanning out **Claude subagents** that do work → `parallel-agent-dispatch`, `agent-teams` |
| Reconciling two models' conflicting design proposals | Red-teaming a *finished* artifact → `adversarial-review` |
| Deciding whether a multi-model consult is worth the tokens | A lookup answers the question → PAL `apilookup`, official docs |

## The Protocol

Execute a multi-model consult in these steps:

### Step 1: Resolve model IDs first

Run `mcp__pal-mcp-server__listmodels` once at the start of the consult
whenever a model is named loosely ("kimi2.7", "glm5.2") — registry IDs (`kimi-k2.7-code`,
`glm-5.2`) and their aliases (`kimi`, `glm`) rarely match what anyone types
from memory.

### Step 2: Brief every model with the same prompt

Send the identical brief, verbatim, to each model — one
`mcp__pal-mcp-server__chat` call per model — and collect every reply before
judging any of them.
Different prompts produce divergences that are artifacts of the framing, not
of the problem — and afterward you cannot tell a real design tension from a
wording accident. Pass code via the `absolute_file_paths` parameter rather
than pasting it into the prompt: it is what the parameter is for, and the
pasted copy risks truncation. Attachments carry a **per-model token budget**
that a multi-file set routinely exceeds — when it does, build one curated
excerpt bundle rather than trimming per model (see below).

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

### Step 7: When a claim is refuted, ask the second question

Step 5 adjudicates *"is this claim true?"* against the code. When the answer
is **no**, the instinct is to discard the claim and move on. Don't — ask the
second question first:

> **"Why couldn't the test suite answer this?"**

That question survives a wrong claim. A confident, specific, *false* finding
usually points at something real — not the defect it names, but the **absence
of a gate that would have settled it in seconds**. The claim dies; the gap it
exposed does not.

The move: add the gate that decides the question, then **kill-test it by
swapping in the reviewer's proposed value**. If the reviewer was right, the
gate goes red and you have found a real bug. If they were wrong, it goes red
on *their* version and green on yours — converting an argument into a
permanent, mechanical answer, so neither the next reviewer nor the next
session can re-litigate it.

> Canonical case (loractl verbosity review, 2026-07): `kimi-k2.7-code` claimed
> `flag_directives` emitted a `loractl=` tracing target matching nothing —
> because the *package* is `loractl-cli` — which would make the entire `-v`
> ladder inert. It was **wrong**: `[[bin]] name = "loractl"`, so `module_path!`
> roots at `loractl`, and a live `-v` run had already printed `INFO` lines. But
> the claim was *unfalsifiable from the suite*, because the unit test asserted
> the directive **string** and never that the filter matched a real event. Fix:
> a spawned-binary test pair (`-v` must show INFO, default must not), then a
> kill-test swapping in the reviewer's `loractl_cli=` — which fails it. Wrong
> claim, real gap, permanent gate.

The generalization beyond model reviews: **a test that asserts the shape of a
value rather than the behaviour it produces cannot settle a question about
that behaviour** — it passes whether the wiring works or not. Those are
exactly the tests an outside reviewer's wrong guess will find for you.

## When It's Worth the Tokens

| Worth it | Skip it |
|---|---|
| Open design decision with a wide solution space and no conventional default — scoring models, architecture splits, API shape, migration strategy | Anything with a conventional default: pick it, state it, proceed |
| Genuinely underdetermined trade-offs where an independent draw adds information | A lookup or doc read answers it |
| | Seeking agreement on a decision already made — a model asked to validate **will** validate; you pay for confirmation, not information |

## PAL Mechanics That Bite

| Mechanic | Symptom | Fix |
|---|---|---|
| `kimi-k2.7-code` 400s whenever `temperature` is sent (OpenCode Go) | Opaque `Error from provider (Console Go): Upstream request failed` — names neither parameter nor constraint, so it reads as flakiness or "prompt too long" | Omit `temperature` for kimi; `glm-5.2` accepts it fine. Prompt length, attachments, `thinking_mode` are all innocent. [pal#67](https://github.com/laurigates/pal-mcp-server/issues/67) |
| `absolute_file_paths` is capped at ~60% of context headroom, and the cap varies **wildly** by model | The attachment set is rejected for exceeding the budget. Observed on a 262K context: `gpt-5.3-codex` ≈ 76,800 tokens but `kimi-k2.7-code` only ≈ 28,311 — one ~84K, 7-file set bounced on **both** | Size attachments to the **smallest** target model's budget. Because the identical-briefs invariant is load-bearing, one model's ceiling trims the set for *all* of them — build a curated excerpt bundle instead |
| `working_directory_absolute_path` must live inside `PAL_WORKSPACE_ROOT` | A scratchpad path outside the repo is rejected: `must reside within the PAL workspace root` | Work in `<repo>/tmp/<consult>/`, never a system temp dir |
| `model_used` is **untrustworthy under concurrency** | Three *concurrent* `chat` calls returned `model_used` values rotated across each other while `provider_used` stayed request-consistent | Verify independence via `provider_used`, and pick models on **different providers** — a silently same-model pair breaks the disagreement-is-the-payload logic. [pal#68](https://github.com/laurigates/pal-mcp-server/issues/68) |
| Registry models get retired upstream mid-consult | A `listmodels`-listed id 404s ("no longer available") | Pick a same-provider fallback *before* dispatching, and re-send the **identical** brief — a reworded one breaks the invariant |

**Isolate a model failure with controlled probes before believing your first
theory.** The intuitive suspects (big prompt, file attachments) were innocent
twice — a bug filed on either would have sent the maintainer down the wrong
path. A two-word prompt plus the one suspect parameter settles it in one call.

## The Curated Excerpt Bundle

When the load-bearing code spans more than the smallest model's attachment
budget allows, **do not trim per model** — that silently un-identicals the
briefs. Build one file and attach *it* to every model:

1. Write it **inside the workspace**: `<repo>/tmp/<consult>/context-excerpts.md`.
2. Include **verbatim** excerpts of exactly the load-bearing regions — no
   paraphrase; the whole point is that the models read the real code.
3. Number the sections (`§1`…`§N`), each titled with its **real file path +
   line range**, so a cited `§7` resolves back to source.
4. **The smallest model's budget bounds the bundle.** Size the whole file
   under it, then attach that one path to every model.
5. Reference sections from the brief by number ("weigh §3 against §9").

> Canonical case (loractl #132, 2026-07): a 7-file, ~84K-token attachment set
> bounced on both `gpt-5.3-codex` and `kimi-k2.7-code`. An 11-section bundle
> at ~21K tokens fit all three budgets, kept the briefs byte-identical, and
> the models cited sections accurately.

## Agentic Optimizations

| Context | Command |
|---|---|
| Resolve registry IDs and aliases | `mcp__pal-mcp-server__listmodels` |
| Independent round-one draw (repeat per model, same prompt) | `mcp__pal-mcp-server__chat` with `model` + `absolute_file_paths`; omit `temperature` for kimi |
| Attachment set exceeds the smallest model's budget | One `<repo>/tmp/<consult>/context-excerpts.md` bundle, attached to every model |
| Structured multi-model verdict with per-model stances | `mcp__pal-mcp-server__consensus` |
| Deep single-model dig after the split is found | `mcp__pal-mcp-server__thinkdeep` |

## Related

- `parallel-agent-dispatch` — delegating *work* to Claude subagents: those
  are delegates producing output; this skill's models are second opinions
  producing judgment
- `agent-teams` — implicit-team / SendMessage mechanics for Claude teammates
- `adversarial-review` — inverted-objective second pass on a finished
  artifact, by an isolated Claude reviewer
- `verify-before-plan` — the same adjudicate-against-reality instinct,
  applied to orchestrator premises before a dispatch

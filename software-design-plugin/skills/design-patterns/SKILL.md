---
name: design-patterns
description: Select a design pattern from a symptom — strategy, observer, factory, adapter, decorator. Use when a structure resists change, or choosing between Gang-of-Four patterns.
args: "[symptom or target]"
argument-hint: "a code smell/requirement, or a file|diff to assess; omit for current change"
allowed-tools: Read, Grep, Glob, Bash(git diff *), TodoWrite
created: 2026-06-23
modified: 2026-06-23
reviewed: 2026-06-23
---

# Design Patterns: Symptom → Pattern

The Gang-of-Four patterns are answers to *recurring design problems*. Reaching
for a pattern by name invites over-engineering; reaching for one by **symptom**
keeps the design honest. This skill maps the pressure you're feeling — "this
`switch` grows every time we add a type", "callers keep re-implementing the same
multi-step setup" — to the pattern that relieves it, and just as importantly
says when **no pattern** is the right call.

For the per-pattern intent, structure, and a minimal recipe, see
[REFERENCE.md](REFERENCE.md). This body is the selector.

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|---|---|
| A structure resists a change that *should* be easy (new type, new behaviour) | Removing duplication with no design pressure → `code-quality-plugin:dry-consolidation` |
| Choosing between two patterns, or unsure a pattern is warranted | Mechanical refactor toward pure functions → `code-quality-plugin:code-refactor` |
| Naming the pattern already latent in a pile of conditionals | Complexity metrics on a function → `code-quality-plugin:code-complexity` |
| Teaching/justifying a pattern choice in review | UI/component composition patterns → `component-patterns-plugin` |

## Selector

Match the **symptom**, not the noun. Confirm the pressure is real before adopting
any pattern — each adds an indirection that a one-off conditional does not.

| Symptom you feel | Candidate pattern | Confirm before adopting |
|---|---|---|
| A `switch`/`if` on a type code grows with every new variant | **Strategy** / **State** | ≥2 variants exist *and* more are expected |
| Object behaviour changes with an internal mode, transitions are tangled | **State** | The modes have distinct transitions, not just a flag |
| Many objects must react when one changes | **Observer** | Reactors are genuinely decoupled from the source |
| Callers hard-code which concrete class to instantiate | **Factory Method** / **Abstract Factory** | The choice varies at runtime or by config |
| An interface you need ≠ the interface you have (3rd-party/legacy) | **Adapter** | You can't change the callee directly |
| Behaviour to add/remove per-instance at runtime, combinatorially | **Decorator** | Subclass explosion is the alternative |
| Constructing one object needs many ordered steps/options | **Builder** | The telescoping constructor actually hurts |
| A subsystem is too many moving parts for callers | **Facade** | Callers only need a common subset |
| An algorithm's skeleton is fixed but steps vary | **Template Method** / **Strategy** | The skeleton truly is stable |
| Traversal logic leaks across a collection's clients | **Iterator** | The collection's shape is non-trivial |
| Operations sprawl across a type hierarchy you can't grow | **Visitor** | The hierarchy is stable but operations churn |

When two fit: **Strategy** (composition) over **Template Method** (inheritance)
unless the skeleton must be enforced; **State** over **Strategy** when the
variants drive transitions between each other.

## Parameters

Parse `$ARGUMENTS`:

- **Symptom or target** (optional) — a free-text symptom/requirement, **or** a
  file/diff to assess for latent patterns. If absent, default to the current
  change (`git diff HEAD`) and scan it for the symptoms above.

## Execution

Execute this pattern selection:

### Step 1: Name the pressure

State, in one line, the *change* that is currently hard — the new type, the new
reactor, the runtime choice. If the target is code, locate the growing
conditional / hard-coded `new` / leaking interface that signals it. If nothing
resists change, **stop and say so**: no pattern is warranted.

### Step 2: Match symptom → candidate

Use the selector to pick 1-2 candidates. Read their intent in
[REFERENCE.md](REFERENCE.md) to confirm fit. State explicitly what each pattern
*costs* (an extra interface, an indirection, a new type to maintain).

### Step 3: Justify or reject

Apply the "confirm before adopting" gate for the chosen pattern. If the variants
don't yet exist (YAGNI) or only one ever will, recommend the simpler
conditional and **reject** the pattern with the reason. Patterns earn their cost
only against real, recurring variation.

### Step 4: Recommend

Emit: the symptom, the chosen pattern (or "no pattern — keep the conditional"),
the cost it adds, and the minimal shape from REFERENCE.md mapped onto the
target's own types. Keep it a recommendation; don't rewrite the code wholesale.

## Anti-patterns

| Mistake | Correct approach |
|---|---|
| Picking a pattern by its cool name | Start from the symptom; let it select the pattern |
| Adding Strategy for a single, stable behaviour | One implementation = no pattern; YAGNI |
| Abstract Factory where a function would do | Use the lightest construct that removes the pressure |
| Stacking patterns "to be enterprise-ready" | Each indirection is cost; adopt one only against real variation |

## Quick Reference

| Pressure | Pattern | Cost |
|---|---|---|
| Type-code `switch` grows | Strategy / State | One interface + N classes |
| Mode-driven behaviour & transitions | State | State classes + transition wiring |
| Fan-out reactions | Observer | Subscription lifecycle |
| Hard-coded `new` | Factory | An extra creation seam |
| Wrong interface, can't change callee | Adapter | A thin translation layer |
| Per-instance runtime behaviour | Decorator | Wrapper chain |

## Related

- [REFERENCE.md](REFERENCE.md) — per-pattern intent, structure, minimal recipe
- `code-quality-plugin:dry-consolidation` — when the pressure is duplication, not
  variation, dedupe instead of patterning
- `code-quality-plugin:code-refactor` — the mechanical moves that introduce the
  chosen pattern
- `software-design-plugin:design-deep-modules` — a pattern should *deepen* the
  interface, not add a shallow indirection layer

---
model: opus
name: prose-synthesize
description: |
  Synthesize unstructured thinking into a structured, actionable plan. Use when user provides
  stream-of-consciousness thoughts, scattered notes, or a brain dump and needs them organized
  into a coherent plan with goals, actions, and priorities. Trigger phrases: "synthesize",
  "organize my thoughts", "turn this into a plan", "make sense of this", "structure this",
  "formalize these notes", "what should I do with all this".
args: [prose to synthesize]
allowed-tools: Read, Edit, Write, Grep, Glob, TodoWrite
argument-hint: <unstructured thoughts or file path>
created: 2026-02-16
modified: 2026-02-16
reviewed: 2026-02-16
---

# /prose:synthesize

Synthesize unstructured thinking into a structured, actionable plan — impose order on chaos.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| User dumps stream-of-consciousness thoughts | Text is already structured but verbose → `/prose:distill` |
| Scattered notes need organizing into a plan | Need to capture session learnings → `/project:distill` |
| Brain dump needs goals, actions, priorities extracted | Need to write a plan from scratch with no input → `/blueprint:init` |
| User says "make sense of this", "organize this" | Document needs style/tone adjustment → `prose-tone` (planned) |

## Core Principles

Synthesis is the complement of analysis. Analysis breaks apart; synthesis combines fragments into a coherent whole. The input is scattered thinking — the output is structured intent.

### What Makes a Good Synthesized Plan

Each element answers a specific question:

| Element | Question it answers |
|---------|---------------------|
| Objective | What are we trying to achieve? |
| Key decisions | What needs deciding before acting? |
| Actions | What specific things need doing? |
| Dependencies | What blocks what? |
| Open questions | What's still unclear? |

## Parameters

Parse `$ARGUMENTS`:

- If prose is provided inline, synthesize it directly
- If a file path is provided, read and synthesize the file contents
- If no arguments, ask the user to provide their unstructured thinking

## Execution

Execute this synthesis workflow:

### Step 1: Absorb the input

Read all provided text without editing or filtering. Identify:

1. Total volume (rough word count)
2. Density of ideas — scattered vs. loosely organized
3. Whether there's an implicit goal or the user is still exploring
4. Tone — brainstorming, planning, venting, or exploring

### Step 2: Extract and tag ideas

Work through the input and internally classify each distinct idea:

- **GOAL** — something the user wants to achieve
- **CONSTRAINT** — a limitation or boundary condition
- **DECISION** — a choice that needs making
- **ACTION** — a concrete step that could be taken
- **QUESTION** — something unresolved or uncertain
- **CONTEXT** — background that informs the plan
- **ASIDE** — tangential thought (preserve but deprioritize)

Do not discard anything yet. Do not show tags to the user.

### Step 3: Cluster by theme

Group ideas into natural clusters:

1. Ideas addressing the same goal
2. Actions depending on the same decision
3. Questions blocking the same cluster of actions

Name each cluster with a short descriptive label.

### Step 4: Find the spine

Identify the core through-line — the primary objective connecting the most clusters. This becomes the plan's backbone. Other clusters are supporting or parallel tracks.

### Step 5: Build the plan

Structure the output using this format. Include only sections that have content:

```
## Objective

<1-2 sentence statement of what this plan achieves>

## Key Decisions

<Decisions that need making before or during execution. Note options if the user mentioned them.>

## Plan

<Ordered actions grouped by theme/phase. Numbered lists for sequences, bullets for parallel items.>

## Dependencies

<What blocks what — only if meaningful dependencies exist>

## Open Questions

<Unresolved items needing answers before the plan is complete>

## Parked Ideas

<Tangential thoughts worth preserving but outside the core plan>
```

### Step 6: Validate completeness

Check the plan against the original input:

1. Is every goal addressed?
2. Is every constraint respected?
3. Are the user's questions surfaced, not buried?
4. Did anything important get lost in synthesis?

If the input was exploratory (no clear goal), say so in the objective and frame the plan as "potential directions" rather than commitments.

## Handling Ambiguity

| Situation | Approach |
|-----------|----------|
| Multiple possible goals | Present as alternatives under Key Decisions |
| Contradictory ideas | Surface the contradiction explicitly |
| Vague but directional | Interpret the direction, note the interpretation |
| Pure exploration (no goal) | Organize by theme, suggest possible goals |

## Example

**Input:** "I need to fix the auth system. Also the tests are broken. Maybe we should move to JWT. The deployment pipeline keeps failing too. Sarah mentioned something about rate limiting. We should probably do a security audit at some point. Oh and the docs are out of date."

**Synthesized:**

> **Objective:** Stabilize and secure the authentication system while addressing related infrastructure issues.
>
> **Key Decisions:**
> 1. JWT migration — move to JWT or fix current auth? (Affects scope of all auth work)
>
> **Plan:**
> 1. Fix immediate blockers
>    - Fix broken tests (unblocks everything else)
>    - Fix deployment pipeline failures
> 2. Auth system
>    - Decide JWT migration
>    - Implement fix or migration based on decision
>    - Add rate limiting (per Sarah's input)
> 3. Hardening
>    - Security audit
>    - Update documentation
>
> **Open Questions:**
> - What specifically did Sarah say about rate limiting?
> - What's breaking in the deployment pipeline? (may be auth-related)

## Agentic Optimizations

| Context | Approach |
|---------|----------|
| Short input (< 200 words) | Synthesize inline, present plan directly |
| Medium input (200-1000 words) | Full synthesis workflow, structured plan output |
| Long input or file (> 1000 words) | Read file, full synthesis, write plan to file |
| Already semi-structured input | Preserve existing structure, fill gaps |
| No clear goal in input | Organize by theme, present as exploration map |

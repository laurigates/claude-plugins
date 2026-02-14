---
model: opus
name: prose-distill
description: |
  Distill verbose text to its concentrated essence. Compress without losing meaning —
  precis, condensation, verbal economy. Use when user says "distill", "condense",
  "tighten", "make concise", "shorten this", "too wordy", "omit needless words",
  or asks to reduce text length while preserving substance.
args: [text or file path]
allowed-tools: Read, Edit, Write, Grep, Glob, TodoWrite
argument-hint: <text to distill> or <path to file>
created: 2026-02-14
modified: 2026-02-14
reviewed: 2026-02-14
---

# /prose:distill

Distill verbose text to its concentrated essence — the art of compression without loss.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Text is wordy and needs tightening | You need to change tone or register (use prose-tone) |
| Redundant phrases need removing | You need to restructure document flow (use prose-structure) |
| User says "condense", "tighten", "shorten" | You need to adapt for a specific audience (use prose-audience) |
| Preserving all meaning while reducing length | Summarizing (lossy) rather than distilling (lossless) |

## Core Principles

Distillation is lossless compression of natural language. Every sentence in the output must preserve the information content of the input. The goal is approaching the Shannon limit of the message — boiling off redundancy to leave concentrated meaning.

### The Hierarchy of Cuts

Apply in this order. Each level removes less essential material:

1. **Redundant phrases** — saying the same thing twice in different words
2. **Filler words** — "actually", "basically", "essentially", "really", "very", "quite", "rather"
3. **Hedge words** — "somewhat", "arguably", "it could be said that", "in a sense"
4. **Throat-clearing** — opening phrases that delay the point ("It is worth noting that", "It should be mentioned that")
5. **Nominalizations** — noun forms where verbs are stronger ("make a decision" → "decide", "perform an analysis" → "analyze")
6. **Passive constructions** — where active is clearer and shorter
7. **Prepositional chains** — "the result of the analysis of the data" → "the data analysis result"
8. **Weak verbs + adverbs** — replace with a single precise verb ("moved quickly" → "darted")

### What to Preserve

- Technical precision and domain terminology
- Necessary qualifications and nuance
- Logical structure and argument flow
- Voice and character (distill the style, don't flatten it)
- Specific details, numbers, names, references

## Parameters

Parse `$ARGUMENTS`:

- If text is provided inline, distill it directly
- If a file path is provided, read and distill the file contents
- If no arguments, ask the user for text to distill

## Execution

Execute this distillation workflow:

### Step 1: Assess the input

Read the provided text. Identify:
- Approximate word count
- Density of redundancy (light, moderate, heavy)
- Whether the text has a distinctive voice worth preserving

### Step 2: Apply the hierarchy of cuts

Work through the text applying cuts in order from the hierarchy above. For each sentence:
1. Can two sentences merge into one without losing meaning?
2. Are there redundant phrases?
3. Can filler/hedge words be removed?
4. Can nominalizations become verbs?
5. Can passive become active without changing emphasis?
6. Can prepositional chains compress?

### Step 3: Verify lossless compression

Compare the distilled version against the original. Confirm:
- No information was lost
- No meaning was altered
- Qualifications and nuance survived
- The logical flow is intact

### Step 4: Present the result

Output the distilled text. Follow with a brief summary:

```
---
Original: ~N words
Distilled: ~N words
Reduction: ~N%
```

If any meaning was ambiguous and required interpretation, note it.

## Examples

### Filler and hedge removal

**Before:** "It is essentially worth noting that the system actually performs quite well in basically all of the scenarios that were tested."

**After:** "The system performs well in all tested scenarios."

### Nominalization to verb

**Before:** "We performed an investigation into the cause of the failure and made a determination that the configuration was incorrect."

**After:** "We investigated the failure and determined the configuration was incorrect."

### Redundancy elimination

**Before:** "The end result of this process is that each and every individual component is tested and verified to ensure and confirm that it meets the required specifications and standards."

**After:** "This process verifies each component meets the required specifications."

### Preserving necessary nuance

**Before:** "While the approach generally works well in most common scenarios, there are some edge cases, particularly those involving concurrent access patterns, where the current implementation may exhibit degraded performance characteristics."

**After:** "The approach works well in common scenarios but may degrade under concurrent access patterns."

Note: "may" is preserved — it's a genuine qualification, not a hedge.

## Agentic Optimizations

| Context | Approach |
|---------|----------|
| Short text (< 100 words) | Distill inline, show before/after |
| Medium text (100-500 words) | Distill in sections, show word count reduction |
| Long text or file (> 500 words) | Read file, distill, write result, show stats |
| Preserving technical accuracy | Flag any cuts that might alter technical meaning |

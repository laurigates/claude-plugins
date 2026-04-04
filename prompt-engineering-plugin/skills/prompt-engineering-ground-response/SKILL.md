---
name: ground-response
description: |
  Produce grounded, citation-backed responses from source documents. Use when analyzing
  long documents, answering questions about codebases or specs, or whenever response
  accuracy is critical. Applies three anti-hallucination techniques: permits uncertainty,
  extracts direct quotes, and verifies all claims against source material. Trigger phrases:
  "ground this", "cite sources", "no hallucination", "verify claims", "quote the source",
  "fact-check this against the doc", "reduce hallucination".
args: <question or task> [--source <file-or-path>]
allowed-tools: Read, Grep, Glob, TodoWrite
argument-hint: <question about a document or codebase>
created: 2026-03-22
modified: 2026-03-22
reviewed: 2026-03-22
---

# /prompt-engineering:ground-response

Produce a grounded, citation-backed response — every claim traced to a source quote, unsupported claims retracted, unknowns stated explicitly.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| You need factual accuracy grounded in source documents | Text needs style/tone adjustment → `/prose:distill` |
| Analyzing long documents (>20k tokens) where hallucination risk is high | You need code review → `/code-quality:code-review` |
| User asks to "cite sources" or "verify claims" | You need to synthesize scattered notes → `/prose:synthesize` |
| Answering questions about specs, policies, or technical docs | General coding task with no source verification needed |
| User wants auditable, traceable answers | Creative writing or brainstorming (accuracy not the goal) |

## Core Principles

These three techniques are from Anthropic's official documentation on reducing hallucination. Apply all three in every response.

### 1. Permit Uncertainty

You have explicit permission to say "I don't know" or "The source does not address this." Do not invent, speculate, or fill gaps with plausible-sounding information. When the source is silent on a topic, say so. When the source is ambiguous, state the ambiguity.

### 2. Extract Direct Quotes First

Before analyzing or answering, extract word-for-word quotes from the source material that are relevant to the task. This grounds your reasoning in actual text, not recalled impressions. For documents >20k tokens, this step is critical — extract before you analyze.

### 3. Verify Claims Against Quotes

After formulating your response, audit every claim. Each claim must have a supporting quote. If a claim lacks a supporting quote, retract it. Mark retracted claims with `[RETRACTED — no supporting quote found]`. This makes your response auditable.

## Parameters

Parse `$ARGUMENTS`:

- **Question/task**: The primary argument — what to analyze or answer
- **`--source <path>`**: Optional file path or glob pattern for source material
- If no `--source` is provided, look for source material in the conversation context
- If no source material is available anywhere, ask the user to provide it

## Execution

Execute this grounded analysis workflow:

### Step 1: Identify and Read Source Material

1. If `--source` is provided, read the file(s):
   - Single file: use `Read`
   - Glob pattern: use `Glob` to find files, then `Read` each
   - Directory: use `Glob` with `**/*` to discover relevant files
2. If no `--source`, check conversation context for documents, code, or prior content
3. If no source material is available, stop and ask: "What document or source should I ground my response in?"

Note the total size of source material. For large sources (>20k tokens), be especially rigorous about Step 2.

### Step 2: Extract Direct Quotes

Search the source material and extract word-for-word quotes relevant to the question/task.

For each quote, record:
- **Quote number**: Sequential identifier (`Q1`, `Q2`, etc.)
- **Exact text**: Word-for-word from the source — no paraphrasing
- **Location**: File path and line number, or document section

Extract comprehensively. It is better to extract too many quotes than too few — you can discard unused quotes later, but you cannot cite quotes you didn't extract.

If no relevant quotes are found, state: "No relevant quotes found in the provided source material. I cannot provide a grounded response to this question."

### Step 3: Formulate Claims

Answer the question or perform the task. Structure your response as a series of claims, each referencing one or more quotes:

- Tag each claim with its supporting quote(s): `[Q1]`, `[Q2, Q3]`
- Keep claims atomic — one assertion per claim
- Distinguish between what the source explicitly states and what you infer

### Step 4: Verify — Audit Every Claim

Walk through each claim in your response:

1. Does it have a tagged quote reference?
2. Does the referenced quote actually support this specific claim?
3. Is the claim a faithful representation of the quote, or does it overstate/distort?

For any claim that fails verification:
- If the claim overstates the quote → weaken it to match what the quote supports
- If no quote supports it → mark as `[RETRACTED — no supporting quote found]`
- If the quote is ambiguous → note the ambiguity explicitly

### Step 5: State Unknowns

After verification, explicitly list:

- **Questions the source does not address** — gaps in the material relevant to the task
- **Ambiguities** — where the source is unclear or contradictory
- **Limitations** — boundaries of what can be concluded from this source alone

Do not skip this step. Stating unknowns is as important as stating knowns.

### Step 6: Present Grounded Response

Deliver the final response using this structure:

```
## Grounded Analysis

<Your response with inline [QN] citations for each claim>

## Supporting Quotes

| # | Quote | Source |
|---|-------|--------|
| Q1 | "exact text from source" | file.md:42 |
| Q2 | "exact text from source" | file.md:78 |

## What the Source Does Not Address

- <Gap 1>
- <Gap 2>

## Retracted Claims (if any)

- <Claim that was removed and why>
```

## Handling Edge Cases

| Situation | Approach |
|-----------|----------|
| Source contradicts itself | Quote both passages, note the contradiction, do not resolve it |
| Question is partially answerable | Answer the answerable part with citations, list unanswerable parts in unknowns |
| Source is code, not prose | Extract relevant code blocks as quotes, cite file:line |
| Multiple sources disagree | Present each source's position with its quotes, note the disagreement |
| Source is very short (<1k tokens) | Still follow the full workflow — brevity doesn't eliminate hallucination risk |

## Agentic Optimizations

| Context | Approach |
|---------|----------|
| Short document (<5k tokens) | Read fully, extract quotes inline, present compact response |
| Long document (5k-50k tokens) | Use `Grep` to find relevant sections, then `Read` targeted ranges |
| Very long document (>50k tokens) | Use `Grep` with multiple patterns, read only matching regions |
| Codebase analysis | Use `Glob` + `Grep` to locate relevant files, extract code quotes with file:line |
| Multiple files | Process each file, merge quotes, deduplicate overlapping citations |
| No source provided | Ask user before proceeding — never ground in imagined sources |

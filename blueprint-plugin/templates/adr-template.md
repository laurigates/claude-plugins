---
id: ADR-0000
status: Proposed
created: YYYY-MM-DD
modified: YYYY-MM-DD
deciders: "{who made the decision}"
domain: architecture
relates-to: []
github-issues: []
---

# ADR-0000: {Decision Title}

<!--
Five-section ADR template (blueprint-plugin/templates/adr-template.md).
schemas/adr.schema.json requires Context, Decision and Consequences; it
leaves Options Considered and Related ADRs optional (ADR-0023). This
template carries all five so a new ADR records them when it is written.
No validator checks for the optional two, so delete a section only when
it has genuinely nothing to say.

Replace ADR-0000 with the next free number (frontmatter `id` and the H1),
fill the dates as YYYY-MM-DD, set `domain` (see skills/adr-relationships),
and drop any frontmatter field left empty.
-->

## Context

{The problem, the forces at play, and the constraints. What made a decision necessary now?}

## Decision

{The decision, stated in one or two sentences, then the details a reader needs to apply it.}

## Consequences

### Positive

- {benefit}

### Negative

- {cost or trade-off}

## Options Considered

### Option 1: {chosen option}

{What it is.} **Pros:** {…} **Cons:** {…}

### Option 2: {alternative}

{What it is.} **Pros:** {…} **Cons:** {…} **Rejected because:** {…}

## Related ADRs

- {[ADR-NNNN: Title](NNNN-title.md) — how it relates (supersedes, extends, constrains), or "None"}

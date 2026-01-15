# ADR-0010: Proactive Document Detection

**Date**: 2026-01-09
**Status**: Proposed
**Deciders**: Blueprint Plugin Maintainers

## Context

The blueprint-plugin currently operates in a reactive model where users must explicitly invoke commands like `/blueprint:prd`, `/blueprint:adr`, or `/blueprint:prp-create` to generate documentation. This approach has limitations:

1. **Lost context**: By the time users remember to create documentation, important context from the conversation has been lost or requires re-gathering
2. **Low discoverability**: Users may not know which document types are available or when they would be appropriate
3. **Workflow interruption**: Creating documentation becomes a separate task rather than a natural part of the conversation flow
4. **Incomplete capture**: Requirements discussed in conversation often go undocumented because the user moves directly to implementation

The blueprint-plugin needs to evolve from this reactive model to a proactive one where Claude detects when documents would be beneficial and offers to create them while context is fresh.

## Decision Drivers

- **User workflow preservation**: Avoid unnecessary interruptions that disrupt the user's train of thought
- **Document completeness**: Capture requirements, decisions, and context before they're lost in conversation history
- **Maintainability**: Keep the main conversation focused by delegating document writing to specialized subagents
- **Discoverability**: Help users learn about document types (PRD, ADR, PRP) through contextual prompts
- **Clean project structure**: Maintain organized project roots by directing all documentation to appropriate directories

## Considered Options

### Option 1: Reactive Only (Status Quo)

Maintain the current explicit command model where users must invoke documentation commands manually.

### Option 2: Fully Automatic

Automatically create documents without user confirmation when patterns are detected.

### Option 3: Proactive with Confirmation (Chosen)

Detect conversation patterns that indicate documentation opportunities, ask the user via AskUserQuestion, and delegate to subagents upon confirmation.

### Option 4: Keyword-Based Triggers

Use simple keyword matching (e.g., "new feature", "architecture decision") to trigger documentation prompts.

## Decision Outcome

**Chosen option**: "Proactive with Confirmation" because it balances automation with user control, ensures high-quality context capture, and educates users about documentation types without being intrusive.

### Implementation Architecture

1. **Pattern Matching Approach**: Use semantic understanding of conversation context rather than simple keyword matching. Analyze intent, scope, and complexity to determine document type appropriateness.

2. **Confidence Scoring**: Implement a confidence threshold of 0.7 minimum before prompting the user. Factors include:
   - Explicit feature/decision language
   - Scope indicators (multiple components, cross-cutting concerns)
   - Implementation signals (ready to code, need to plan)
   - Absence of existing documentation

3. **Clarifying Questions**: Use AskUserQuestion to gather necessary context before delegation:
   - Confirm document type appropriateness
   - Gather missing context (stakeholders, constraints, alternatives)
   - Determine urgency and priority

4. **Subagent Delegation**: Document writing is delegated to specialized agents:
   - `requirements-documentation` agent for PRDs
   - `architecture-decisions` agent for ADRs
   - `prp-preparation` agent for PRPs

5. **Root Directory Policy**: All generated documentation goes to `docs/` subdirectories. Only standard project files (README.md, LICENSE, etc.) belong in the project root.

### Detection Triggers

| Document Type | Trigger Patterns |
|--------------|------------------|
| PRD | New feature discussions, user stories, requirements gathering, "we need to..." |
| ADR | Technology choices, "should we use X or Y", architecture trade-offs, infrastructure decisions |
| PRP | Ready to implement, clear scope defined, "let's build...", post-PRD implementation |

### Positive Consequences

- Documents are created when conversational context is maximally available
- Users learn about document types organically through prompts
- Consistent document structure via subagent templates
- Clean project organization with clear documentation paths
- Reduced cognitive load on users to remember to document

### Negative Consequences

- Potential for unwanted interruptions if confidence threshold is too low
- Pattern matching requires tuning over time based on user feedback
- Adds complexity to the blueprint-plugin architecture
- Users may decline prompts repeatedly, leading to prompt fatigue

## Pros and Cons of Options

### Option 1: Reactive Only (Status Quo)

- ✅ No interruptions to user workflow
- ✅ Simple implementation (current state)
- ✅ User has full control
- ❌ Context lost between discussion and documentation
- ❌ Low discoverability of document types
- ❌ Documentation often skipped entirely

### Option 2: Fully Automatic

- ✅ Documents always created when relevant
- ✅ No user action required
- ❌ Creates unwanted documents
- ❌ No user control over timing
- ❌ May generate documents with incomplete context
- ❌ Disrupts conversation flow significantly

### Option 3: Proactive with Confirmation (Chosen)

- ✅ Captures context while fresh
- ✅ Educates users about document types
- ✅ User retains control via confirmation
- ✅ Subagent delegation keeps main conversation focused
- ❌ Requires confidence threshold tuning
- ❌ Additional complexity in pattern matching
- ❌ Potential for prompt fatigue

### Option 4: Keyword-Based Triggers

- ✅ Simple to implement
- ✅ Predictable behavior
- ❌ High false positive rate
- ❌ Misses nuanced opportunities
- ❌ Easy to game or accidentally trigger
- ❌ Cannot understand context

## Links

- [Blueprint Plugin README](/Users/lgates/repos/laurigates/claude-plugins/blueprint-plugin/README.md)
- [MADR Template](https://adr.github.io/madr/)
- [Blueprint ADR Command](/Users/lgates/repos/laurigates/claude-plugins/blueprint-plugin/commands/blueprint-adr.md)
- Related agents: `requirements-documentation`, `architecture-decisions`, `prp-preparation`

---
*Generated via /blueprint:adr*

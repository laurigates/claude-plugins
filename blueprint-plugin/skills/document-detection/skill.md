---
model: haiku
created: 2026-01-09
modified: 2026-01-15
reviewed: 2026-01-09
name: document-detection
description: "Detect PRD/ADR/PRP opportunities in conversations and prompt for document creation. Activates when users discuss features, architecture decisions, or implementation planning."
---

# Document Detection

Proactively identify when conversations should become structured documents (PRDs, ADRs, or PRPs) and guide users through the documentation workflow.

## When This Skill Activates

This skill is loaded when conversation context suggests documentation opportunities:
- Feature requirements being discussed
- Architecture decisions being made
- Implementation planning in progress
- Technology trade-offs being evaluated

## Prerequisites

Document detection requires:
1. Blueprint initialized in project (`docs/blueprint/manifest.json` exists)
2. `has_document_detection: true` in manifest structure
3. `docs/` directory structure created

Check prerequisites before prompting:
```bash
# Verify blueprint is initialized with document detection enabled
jq -r '.structure.has_document_detection // false' docs/blueprint/manifest.json 2>/dev/null
```

## Detection Patterns

### PRD Indicators (Product Requirements)

**Primary triggers** (confidence +0.5 each):
- Feature descriptions: "I want to build...", "The system should...", "We need a feature that..."
- User stories: "As a [user], I want...", "Users should be able to..."
- Requirements enumeration: Lists of features or capabilities
- Problem/solution framing: "The problem is... the solution is..."

**Confidence boosters** (+0.1-0.2 each):
- Multiple features mentioned (+0.2)
- User personas identified (+0.1)
- Success criteria discussed (+0.1)
- Priority levels mentioned (P0, P1, must-have, nice-to-have) (+0.1)
- Timeline or milestones mentioned (+0.1)

**Example triggers**:
> "I want to build a user authentication system with OAuth2 support, password reset, and MFA"

> "As an admin, I want to manage user permissions so that I can control access"

> "We need to implement: 1) user registration, 2) email verification, 3) profile management"

### ADR Indicators (Architecture Decisions)

**Primary triggers** (confidence +0.5 each):
- Technology comparisons: "Should we use X or Y?", "Which is better: X or Y?"
- Trade-off discussions: "The pros and cons of...", "The trade-offs between..."
- "Why did we choose..." questions
- Framework/library selection discussions
- Design pattern debates

**Confidence boosters** (+0.1-0.2 each):
- Multiple options explicitly compared (+0.2)
- Trade-offs listed with pros/cons (+0.1)
- Long-term impact discussed (+0.1)
- Team disagreement on approach (+0.1)
- Reversibility or commitment discussed (+0.1)

**Example triggers**:
> "Should we use PostgreSQL or MongoDB for the user data? We need to consider query patterns and scalability"

> "The pros of using microservices are scalability and team independence, but the cons are operational complexity"

> "Why did we choose React over Vue? Let me document the decision"

### PRP Indicators (Implementation Prompts)

**Primary triggers** (confidence +0.5 each):
- Implementation intent: "Let's implement...", "How do we build...", "Time to code..."
- Specific feature scope: "the authentication module", "the payment flow", "the dashboard component"
- Technical approach discussions: "We'll use X pattern to...", "The implementation will..."
- File/component planning: "We need to create files for...", "The components are..."

**Confidence boosters** (+0.1-0.2 each):
- File paths or component names mentioned (+0.2)
- Test approach discussed (+0.1)
- Clear scope boundaries defined (+0.1)
- Dependencies identified (+0.1)
- PRD reference made (+0.1)

**Example triggers**:
> "Let's implement the payment processing module with Stripe integration"

> "We need to create PaymentService.ts, add routes in /api/payments, and write integration tests"

> "Time to build the dashboard - it needs charts, filters, and export functionality"

## Confidence Calculation

**Threshold for prompting**: >= 0.7

```
Base confidence: 0.0
+ Primary trigger matched: +0.5
+ Additional primary trigger: +0.3
+ Each booster matched: +0.1 to +0.2

Total >= 0.7 → Prompt user
Total < 0.7 → Continue without prompting
```

**Examples**:
- "I want authentication" → 0.5 (single trigger, below threshold)
- "I want to build authentication with OAuth, MFA, and password reset" → 0.5 + 0.2 (multiple features) = 0.7 (meets threshold)
- "Should we use Postgres?" → 0.5 (single trigger, below threshold)
- "Should we use Postgres or MongoDB? Postgres has better querying but MongoDB scales easier" → 0.5 + 0.2 (comparison) + 0.1 (trade-offs) = 0.8 (exceeds threshold)

## Detection Flow

When confidence >= 0.7, execute this flow:

### Step 1: Prompt User

Use AskUserQuestion to confirm document creation:

```
question: "This looks like a [PRD/ADR/PRP] opportunity. Would you like to document it?"
options:
  - label: "Yes, create [document type]"
    description: "I'll gather context and create the document"
  - label: "Not now, remind me later"
    description: "Continue conversation, prompt again if topic expands"
  - label: "No, just continue"
    description: "Skip documentation for this topic"
```

### Step 2: Gather Clarification (if accepted)

Ask context-specific questions based on document type:

**For PRD**:
```
question: "Who are the primary users for this feature?"
options:
  - label: "End users"
    description: "Regular users of the application"
  - label: "Administrators"
    description: "Admin users with elevated access"
  - label: "Developers"
    description: "Internal development team"
  - label: "Multiple types"
    description: "I'll specify the user types"
```

**For ADR**:
```
question: "What constraints should I consider for this decision?"
options:
  - label: "Performance requirements"
    description: "Speed, latency, throughput constraints"
  - label: "Team expertise"
    description: "Team familiarity with technologies"
  - label: "Budget/cost"
    description: "Financial or resource constraints"
  - label: "Timeline"
    description: "Delivery deadline constraints"
  - label: "All of the above"
    description: "Consider all constraint types"
```

**For PRP**:
```
question: "What's the priority and scope for this implementation?"
options:
  - label: "High priority, narrow scope"
    description: "MVP implementation, ship quickly"
  - label: "High priority, full scope"
    description: "Complete implementation needed soon"
  - label: "Normal priority"
    description: "Standard development timeline"
  - label: "Exploratory"
    description: "Spike or proof of concept"
```

### Step 3: Prepare Context Package

Extract from conversation:
- Key requirements or decisions discussed
- Options considered (for ADR)
- Scope boundaries identified
- User clarifications from Step 2
- Related existing documents (check `docs/prds/`, `docs/adrs/`, `docs/prps/`)

**For ADR: Infer Domain**

Map discussion topics to ADR domains:

| Topic Keywords | Inferred Domain |
|----------------|-----------------|
| Redux, Zustand, MobX, useState, signals, store | `state-management` |
| Prisma, Drizzle, PostgreSQL, MongoDB, ORM, database | `data-layer` |
| REST, GraphQL, tRPC, OpenAPI, endpoints, API | `api-design` |
| OAuth, JWT, auth0, session, tokens, login | `authentication` |
| Vitest, Jest, Playwright, Cypress, coverage, testing | `testing` |
| Tailwind, styled-components, CSS modules, SCSS | `styling` |
| React, Vue, Svelte, Next.js, Nuxt, Angular | `frontend-framework` |
| Vite, Webpack, esbuild, turbopack, bundler | `build-tooling` |
| Docker, Kubernetes, Vercel, serverless, deploy | `deployment` |
| Sentry, DataDog, logging, metrics, monitoring | `monitoring` |

Include inferred domain in context package for `/blueprint:adr`.

### Step 4: Delegate to Documentation Agent

Launch appropriate documentation command:

**For PRD**:
```
Run /blueprint:prd with context:
- Feature description from conversation
- User types identified
- Requirements enumerated
- Success criteria discussed
```

**For ADR**:
```
Run /blueprint:adr with context:
- Decision being made
- Options compared
- Constraints identified
- Trade-offs discussed
- Inferred domain (for conflict analysis)
```

**For PRP**:
```
Run /blueprint:prp-create with context:
- Feature scope
- Implementation approach
- Test strategy discussed
- Files/components planned
```

### Step 5: Report Result

After document creation:
1. Show document location (`docs/prds/`, `docs/adrs/`, or `docs/prps/`)
2. Summarize key sections created
3. Suggest next steps:
   - For PRD: "Run `/blueprint:generate-rules` to create implementation patterns"
   - For ADR: "Consider linking to related PRDs"
   - For PRP: "Run `/blueprint:prp-execute` when ready to implement"

## Session Tracking

To avoid duplicate prompts, track detected topics:

**Track declined topics**: Don't re-prompt for explicitly declined documentation
**Track deferred topics**: Re-prompt if significant new context is added (new requirements, new trade-offs, etc.)
**Track created documents**: Don't re-prompt for topics with existing documents

Session tracking uses conversation memory - no persistent storage needed.

## Integration with Blueprint Commands

Document detection integrates with existing commands:

| Detection Type | Command Triggered | Document Location |
|----------------|-------------------|-------------------|
| PRD | `/blueprint:prd` | `docs/prds/{feature-name}.md` |
| ADR | `/blueprint:adr` | `docs/adrs/{number}-{title}.md` |
| PRP | `/blueprint:prp-create` | `docs/prps/{feature-name}.md` |

## Configuration

Document detection is controlled by manifest flag:

```json
{
  "structure": {
    "has_document_detection": true
  }
}
```

Enable during `/blueprint:init` or `/blueprint:upgrade`.

## False Positive Prevention

To minimize interruptions:

1. **Require high confidence** (>= 0.7) before prompting
2. **Don't prompt on vague statements**:
   - "We might need auth" (< 0.7)
   - "Maybe we should use Postgres" (< 0.7)
3. **Don't re-prompt for same topic** in same session
4. **Respect user choice**: "No, just continue" stops all prompts for that topic

## Quick Reference

| Document | Key Triggers | Confidence Threshold |
|----------|--------------|---------------------|
| PRD | Feature descriptions, user stories, requirements lists | >= 0.7 |
| ADR | Technology comparisons, trade-off discussions, "why" questions | >= 0.7 |
| PRP | Implementation intent, file planning, specific feature scope | >= 0.7 |

| User Response | Action |
|---------------|--------|
| "Yes, create" | Gather clarification, delegate to command |
| "Not now" | Track topic, re-prompt if expanded |
| "No, continue" | Mark declined, never re-prompt |

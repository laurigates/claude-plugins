---
created: 2025-12-22
modified: 2025-12-22
reviewed: 2025-12-22
description: "Generate Architecture Decision Records from existing project structure and documentation"
allowed_tools: [Read, Write, Glob, Grep, Bash, AskUserQuestion, Task]
---

Generate Architecture Decision Records (ADRs) for an existing project by analyzing code structure, dependencies, and documentation.

**Use Case**: Onboarding existing projects to Blueprint Development system, documenting implicit architecture decisions.

**Prerequisites**:
- Blueprint Development initialized (`.claude/blueprints/` exists)
- Ideally PRD exists (run `/blueprint:prd` first)

**Steps**:

## Phase 1: Discovery

### 1.1 Check Prerequisites
```bash
ls .claude/blueprints/.manifest.json
ls .claude/blueprints/prds/
```
If blueprint not initialized → suggest `/blueprint:init`
If no PRD → suggest `/blueprint:prd` first (recommended, not required)

### 1.2 Create ADR Directory
```bash
mkdir -p docs/adrs
```

### 1.3 Analyze Project Structure
Explore the codebase to identify architectural patterns:

Use Explore agent:
```
<Task subagent_type="Explore" prompt="Analyze project architecture: directory structure, major components, frameworks used, design patterns">
```

Key areas to examine:
- **Directory structure**: How code is organized
- **Entry points**: Main files, index files
- **Configuration**: Config files, environment handling
- **Dependencies**: Package manifests, imports
- **Data layer**: Database, ORM, data models
- **API layer**: Routes, controllers, handlers
- **Testing**: Test structure and frameworks

## Phase 2: Identify Architecture Decisions

### 2.1 Common Decision Categories

| Category | What to Look For | Example Decisions |
|----------|-----------------|-------------------|
| **Framework** | package.json, imports | React vs Vue, Express vs Fastify |
| **Language** | File extensions, tsconfig | TypeScript vs JavaScript |
| **State Management** | Store patterns, context | Redux vs Zustand vs Context |
| **Styling** | CSS files, styled imports | Tailwind vs CSS-in-JS vs SCSS |
| **Testing** | Test files, test config | Vitest vs Jest, Playwright vs Cypress |
| **Build** | Build config, bundlers | Vite vs Webpack, esbuild |
| **Database** | ORM config, migrations | PostgreSQL vs MongoDB, Prisma vs Drizzle |
| **API Style** | Route patterns, schemas | REST vs GraphQL, tRPC |
| **Deployment** | Docker, CI config | Container vs serverless |
| **Monorepo** | Workspace config | Turborepo vs Nx vs none |

### 2.2 Infer Decisions from Code
For each identified technology choice:
1. Note the current implementation
2. Consider common alternatives
3. Infer rationale from context/comments

### 2.3 Confirm with User
Use AskUserQuestion for key decisions:

```
question: "I found the project uses {technology}. Why was this chosen over alternatives?"
options:
  - "Performance requirements" → document performance rationale
  - "Team familiarity" → document team expertise factor
  - "Ecosystem/community" → document ecosystem benefits
  - "Specific feature needs" → ask for details
  - "Legacy/inherited decision" → document as inherited
  - "Other" → custom rationale
```

```
question: "Are there any architecture decisions you'd like to document that aren't visible in the code?"
options:
  - "Yes, let me describe" → capture additional decisions
  - "No, the inferred decisions are sufficient" → proceed
```

## Phase 3: ADR Generation

### 3.1 ADR Template (MADR format)
For each significant decision, create an ADR:

```markdown
# ADR-{number}: {Title}

**Date**: {date}
**Status**: Accepted | Superseded | Deprecated
**Deciders**: {who made the decision}

## Context

{Describe the issue motivating this decision}
{What is the problem we're trying to solve?}
{What constraints exist?}

## Decision Drivers

- {driver 1, e.g., "Performance under high load"}
- {driver 2, e.g., "Developer experience"}
- {driver 3, e.g., "Maintainability"}

## Considered Options

1. **{Option 1}** - {brief description}
2. **{Option 2}** - {brief description}
3. **{Option 3}** - {brief description}

## Decision Outcome

**Chosen option**: "{Option X}" because {justification}.

### Positive Consequences

- {positive outcome 1}
- {positive outcome 2}

### Negative Consequences

- {negative outcome / tradeoff 1}
- {negative outcome / tradeoff 2}

## Pros and Cons of Options

### {Option 1}

- ✅ {pro 1}
- ✅ {pro 2}
- ❌ {con 1}

### {Option 2}

- ✅ {pro 1}
- ❌ {con 1}
- ❌ {con 2}

## Links

- {Related ADRs}
- {External documentation}
- {Discussion threads}

---
*Generated from project analysis via /blueprint:adr*
```

### 3.2 Standard ADRs to Generate

Generate ADRs for these common decisions (if applicable):

| ADR | When to Create |
|-----|----------------|
| `0001-project-language.md` | Language/runtime choice |
| `0002-framework-choice.md` | Main framework selection |
| `0003-testing-strategy.md` | Test framework and approach |
| `0004-styling-approach.md` | CSS/styling methodology |
| `0005-state-management.md` | State handling (if applicable) |
| `0006-database-choice.md` | Database and ORM (if applicable) |
| `0007-api-design.md` | API style and patterns |
| `0008-deployment-strategy.md` | Deployment approach |

### 3.3 Create Index
Generate an ADR index file:

```markdown
# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) documenting significant technical decisions for this project.

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [0001](0001-project-language.md) | {Title} | Accepted | {date} |
| [0002](0002-framework-choice.md) | {Title} | Accepted | {date} |

## Template

New ADRs should follow the [MADR template](https://adr.github.io/madr/).

## Creating New ADRs

Use `/blueprint:adr` or the `architecture-decisions` agent to create new ADRs.
```

## Phase 4: Validation & Follow-up

### 4.1 Present Summary
```
✅ ADRs Generated: {count} records

**Location**: `docs/adrs/`

**Decisions documented**:
- ADR-0001: {title} - {status}
- ADR-0002: {title} - {status}
...

**Sources analyzed**:
- {list of analyzed files/patterns}

**Confidence levels**:
- High confidence: {list - clear from code}
- Inferred: {list - reasonable assumptions}
- Needs review: {list - uncertain}

**Recommended next steps**:
1. Review generated ADRs for accuracy
2. Add rationale where marked as "inferred"
3. Run `/blueprint:prp-create` for feature implementation
4. Run `/blueprint:generate-skills` for project skills
```

### 4.2 Suggest Next Steps
- If PRD missing → suggest `/blueprint:prd`
- If ready for implementation → suggest `/blueprint:prp-create`
- If architecture evolving → explain how to add new ADRs

## Phase 5: Update Manifest

Update `.claude/blueprints/.manifest.json`:
- Add `has_adrs: true` to structure
- Add ADRs to `generated_artifacts`
- Update `updated_at` timestamp

**Tips**:
- Focus on decisions with real alternatives (not obvious choices)
- Document inherited/legacy decisions as such
- Mark uncertain rationales for user review
- Keep ADRs concise - focus on "why", not implementation details
- Reference related ADRs when decisions are connected

### 4.3 Prompt for next action (use AskUserQuestion):

```
question: "ADRs generated. What would you like to do next?"
options:
  - label: "Create a PRP for feature work (Recommended)"
    description: "Start implementing a specific feature with /blueprint:prp-create"
  - label: "Generate project skills"
    description: "Create skills from PRDs for Claude context"
  - label: "Review and add rationale"
    description: "Edit ADRs marked as 'inferred' or 'needs rationale'"
  - label: "Document another architecture decision"
    description: "Manually add a new ADR"
  - label: "I'm done for now"
    description: "Exit - ADRs are saved"
```

**Based on selection:**
- "Create a PRP" → Run `/blueprint:prp-create` (ask for feature name)
- "Generate project skills" → Run `/blueprint:generate-skills`
- "Review and add rationale" → Show ADR files needing attention
- "Document another decision" → Restart Phase 2 for a specific decision
- "I'm done" → Exit

**Error Handling**:
- If minimal codebase → create fewer, broader ADRs
- If conflicting patterns → ask user which is intentional
- If rationale unclear → mark as "needs rationale" for user input

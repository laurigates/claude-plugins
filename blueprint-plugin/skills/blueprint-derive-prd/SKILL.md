---
model: opus
created: 2025-12-22
modified: 2026-02-06
reviewed: 2025-12-22
description: "Derive PRD from existing project documentation, README, and codebase analysis"
allowed-tools: Read, Write, Glob, Grep, Bash, AskUserQuestion, Task
name: blueprint-derive-prd
---

Generate a Product Requirements Document (PRD) for an existing project by analyzing README, documentation, and project structure.

**Use Case**: Onboarding existing projects to Blueprint Development system.

**Prerequisites**:
- Blueprint Development initialized (`docs/blueprint/` exists)
- Project has some existing documentation (README.md, docs/, etc.)

**Steps**:

## Phase 1: Discovery

### 1.1 Check Prerequisites
```bash
ls docs/blueprint/manifest.json
```
If not found → suggest running `/blueprint:init` first.

### 1.2 Gather Project Documentation
Search for existing documentation:
```bash
fd -e md -d 3 . | head -20
```

Key files to look for:
- `README.md` - Primary project description
- `docs/` - Documentation directory
- `CONTRIBUTING.md` - Contribution guidelines
- `ARCHITECTURE.md` - Architecture overview
- `package.json` / `pyproject.toml` / `Cargo.toml` - Project metadata

### 1.3 Read Primary Documentation
Read and analyze:
- README.md for project purpose, features, and usage
- Package manifest for dependencies and scripts
- Any existing architecture or design docs

## Phase 2: Analysis & Extraction

### 2.1 Extract Project Context
From documentation, identify:

| Aspect | Source | Questions if Missing |
|--------|--------|---------------------|
| Project name | Package manifest, README | Ask user |
| Purpose/Problem | README intro | "What problem does this project solve?" |
| Target users | README, docs | "Who are the primary users?" |
| Core features | README features section | "What are the main capabilities?" |
| Tech stack | Dependencies, file extensions | Infer from files |

### 2.2 Ask Clarifying Questions
Use AskUserQuestion for unclear items:

```
question: "What is the primary problem this project solves?"
options:
  - "[Inferred from docs]: {description}" → confirm inference
  - "Let me describe it" → free text input
```

```
question: "Who are the target users?"
options:
  - "Developers" → technical documentation focus
  - "End users" → user experience focus
  - "Both developers and end users" → balanced approach
  - "Other" → custom description
```

```
question: "What is the current project phase?"
options:
  - "Early development / MVP" → focus on core features
  - "Active development" → feature expansion
  - "Maintenance mode" → stability and bug fixes
  - "Planning major changes" → architectural considerations
```

### 2.3 Identify Stakeholders
Ask about stakeholders:
```
question: "Who are the key stakeholders for this project?"
options:
  - "Solo project (just me)" → simplified RACI
  - "Small team (2-5 people)" → team collaboration
  - "Larger organization" → formal stakeholder matrix
  - "Open source community" → contributor-focused
```

## Phase 3: PRD Generation

### 3.1 Generate Document ID

Before creating the PRD, generate a unique ID:

```bash
# Get next PRD ID from manifest
next_prd_id() {
  local manifest="docs/blueprint/manifest.json"
  local last=$(jq -r '.id_registry.last_prd // 0' "$manifest" 2>/dev/null || echo "0")
  local next=$((last + 1))
  printf "PRD-%03d" "$next"
}
```

Store the generated ID for use in the document and manifest update.

### 3.2 Create PRD File
Create the PRD in `docs/prds/`:
```
docs/prds/project-overview.md
```

### 3.3 PRD Template
Generate PRD with this structure:

```markdown
---
id: {PRD-NNN}
created: {YYYY-MM-DD}
modified: {YYYY-MM-DD}
status: Draft
version: "1.0"
relates-to: []
github-issues: []
name: blueprint-derive-prd
---

# {Project Name} - Product Requirements Document

## Executive Summary

### Problem Statement
{Extracted or confirmed problem description}

### Proposed Solution
{Project description and approach}

### Business Impact
{Value proposition and expected outcomes}

## Stakeholders & Personas

### Stakeholder Matrix
| Role | Name/Team | Responsibility | Contact |
|------|-----------|----------------|---------|
| {role} | {name} | {responsibility} | {contact} |

### User Personas

#### Primary: {Persona Name}
- **Description**: {who they are}
- **Needs**: {what they need}
- **Pain Points**: {current frustrations}
- **Goals**: {what success looks like}

## Functional Requirements

### Core Features
{List of main capabilities extracted from docs}

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR-001 | {feature} | {description} | {P0/P1/P2} |

### User Stories
{User stories derived from features}

- As a {user type}, I want to {action} so that {benefit}

## Non-Functional Requirements

### Performance
- {Response time expectations}
- {Throughput requirements}

### Security
- {Authentication requirements}
- {Data protection needs}

### Accessibility
- {Accessibility standards to follow}

### Compatibility
- {Browser/platform/version support}

## Technical Considerations

### Architecture
{High-level architecture from docs or inferred}

### Dependencies
{Key dependencies from package manifest}

### Integration Points
{External services, APIs, databases}

## Success Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| {metric} | {baseline} | {goal} | {how to measure} |

## Scope

### In Scope
- {Included features and capabilities}

### Out of Scope
- {Explicitly excluded items}
- {Future considerations}

## Timeline & Phases

### Current Phase: {phase name}
{Description of current work focus}

### Roadmap
| Phase | Focus | Status |
|-------|-------|--------|
| {phase} | {focus areas} | {status} |

---
*Generated from existing documentation via /blueprint:derive-prd*
*Review and update as project evolves*
```

## Phase 4: Validation & Follow-up

### 4.1 Present Summary
Show the user:
```
✅ PRD Generated: {Project Name}

**ID**: {PRD-NNN}
**Location**: `docs/prds/project-overview.md`

**Extracted from**:
- {list of source documents}

**Key sections**:
- Executive Summary: {status}
- Stakeholders: {count} identified
- Functional Requirements: {count} features
- Non-Functional Requirements: {status}

**Confidence**: {High/Medium/Low}
- {High confidence areas}
- {Areas needing review}

**Recommended next steps**:
1. Review and refine the generated PRD
2. Run `/blueprint:derive-adr` to document architecture decisions
3. Run `/blueprint:prp-create` for specific features
4. Run `/blueprint:generate-skills` to create project skills
```

### 4.2 Suggest Follow-up
Based on what was generated:
- If architecture unclear → suggest `/blueprint:derive-adr`
- If features identified → suggest `/blueprint:prp-create` for key features
- If PRD complete → suggest `/blueprint:generate-skills`

## Phase 5: Update Manifest

Update `docs/blueprint/manifest.json`:
- Add PRD to `generated_artifacts`
- Update `has_prds` to true
- Update `updated_at` timestamp
- **Update ID registry**:
  ```json
  {
    "id_registry": {
      "last_prd": {new_number},
      "documents": {
        "{PRD-NNN}": {
          "path": "docs/prds/{filename}.md",
          "title": "{Project Name}",
          "github_issues": [],
          "created": "{date}"
        }
      }
    }
  }
  ```

**Tips**:
- Be thorough in reading existing docs - they often contain valuable context
- Ask clarifying questions for ambiguous or missing information
- Infer from code structure when documentation is sparse
- Mark uncertain sections for user review
- Keep PRD focused on "what" and "why", not "how"

### 4.3 Prompt for GitHub Issue (use AskUserQuestion):

```
question: "Create a GitHub issue to track this PRD?"
options:
  - label: "Yes, create issue (Recommended)"
    description: "Creates issue with title '[PRD-NNN] {Project Name}'"
  - label: "No, skip for now"
    description: "Can link later by editing github-issues in frontmatter"
```

**If yes**, create GitHub issue:
```bash
gh issue create \
  --title "[{PRD-NNN}] {Project Name}" \
  --body "## Product Requirements Document

**Document**: \`docs/prds/{filename}.md\`
**ID**: {PRD-NNN}

### Summary
{Executive summary from PRD}

### Key Features
{List of FR-* features}

name: blueprint-derive-prd
---
*Auto-generated from PRD. See linked document for full requirements.*" \
  --label "prd,requirements"
```

Capture issue number and update:
1. PRD frontmatter: add issue number to `github-issues`
2. Manifest: add issue to `id_registry.documents[PRD-NNN].github_issues`
3. Manifest: add mapping to `id_registry.github_issues`

### 4.4 Prompt for next action (use AskUserQuestion):

```
question: "PRD generated. What would you like to do next?"
options:
  - label: "Document architecture decisions (Recommended)"
    description: "Run /blueprint:derive-adr to capture technical decisions"
  - label: "Generate project skills"
    description: "Extract skills from PRD for Claude context"
  - label: "Create a PRP for a feature"
    description: "Start implementing a specific feature"
  - label: "Review and refine PRD"
    description: "I want to edit the generated PRD first"
  - label: "I'm done for now"
    description: "Exit - PRD is saved"
```

**Based on selection:**
- "Document architecture decisions" → Run `/blueprint:derive-adr`
- "Generate project skills" → Run `/blueprint:generate-skills`
- "Create a PRP" → Run `/blueprint:prp-create` (ask for feature name)
- "Review and refine" → Show PRD file location and key sections needing attention
- "I'm done" → Exit

**Error Handling**:
- If no README.md → ask user for project description
- If blueprint not initialized → suggest `/blueprint:init`
- If conflicting information in docs → ask user to clarify

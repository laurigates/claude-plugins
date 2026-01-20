---
created: 2025-12-16
modified: 2026-01-17
reviewed: 2025-12-16
description: "Create a PRP (Product Requirement Prompt) with systematic research, curated context, and validation gates"
allowed_tools: [Read, Write, Glob, Bash, WebFetch, WebSearch, Task, AskUserQuestion]
---

Create a comprehensive PRP (Product Requirement Prompt) for a feature or component.

**What is a PRP?**
A PRP is PRD + Curated Codebase Intelligence + Implementation Blueprint + Validation Gates - the minimum viable packet an AI agent needs to deliver production code successfully on first attempt.

**Prerequisites**:
- Blueprint Development initialized (`docs/blueprint/` exists)
- Clear understanding of the feature to implement

**Steps**:

## Phase 1: Research

### 1.1 Understand Requirements
Ask the user or analyze context to understand:
- **Goal**: What needs to be accomplished?
- **Why**: What problem does this solve?
- **Success Criteria**: How do we know it's done?

### 1.2 Research Codebase
Explore the existing codebase to understand:
- **Existing patterns**: How similar features are implemented
- **Integration points**: Where this feature connects
- **Testing patterns**: How similar features are tested
- **File locations**: Where new code should go

Use the Explore agent:
```
<Task subagent_type="Explore" prompt="Research patterns for [feature type] implementation">
```

### 1.3 Research External Documentation
For any libraries/frameworks involved:
- Search for relevant documentation sections
- Look for known issues and gotchas
- Find best practices and patterns

Use WebSearch/WebFetch to gather:
- Official documentation for key libraries
- Stack Overflow discussions about common issues
- GitHub issues for known problems

### 1.4 Check/Create ai_docs
Look for existing ai_docs:
```bash
ls docs/blueprint/ai_docs/libraries/
ls docs/blueprint/ai_docs/project/
```

If relevant ai_docs don't exist, create them:
- Extract key patterns from documentation
- Document gotchas discovered in research
- Create curated, concise entries (< 200 lines)

## Phase 2: Draft PRP

### 2.1 Generate Document ID and Link to PRD

Before creating the PRP, generate a unique ID and link to source PRD:

```bash
# Get next PRP ID from manifest
next_prp_id() {
  local manifest="docs/blueprint/manifest.json"
  local last=$(jq -r '.id_registry.last_prp // 0' "$manifest" 2>/dev/null || echo "0")
  local next=$((last + 1))
  printf "PRP-%03d" "$next"
}

# List available PRDs for linking
list_prds() {
  jq -r '.id_registry.documents | to_entries[] | select(.key | startswith("PRD")) | "\(.key): \(.value.title)"' docs/blueprint/manifest.json
}
```

**Prompt user to select source PRD** (use AskUserQuestion):
```
question: "Which PRD does this PRP implement?"
options:
  - label: "{PRD-001}: {title}" (for each PRD in manifest)
  - label: "None / New feature"
    description: "This PRP doesn't implement an existing PRD"
```

Store the selected PRD ID for the `implements` field.

### 2.2 Create PRP File
Create the PRP in `docs/prps/`:
```
docs/prps/[feature-name].md
```

### 2.3 PRP Frontmatter

Include document ID and linking fields:

```yaml
---
id: {PRP-NNN}
created: {YYYY-MM-DD}
modified: {YYYY-MM-DD}
status: Draft
implements:                    # Source PRD(s) this PRP implements
  - {PRD-NNN}                  # or empty if standalone
relates-to:                    # Related ADRs, other PRPs
  - ADR-NNNN
github-issues: []              # Linked issues (populated later)
confidence: 0                  # Updated after scoring
---
```

### 2.4 Fill Sections

**Goal & Why**:
- One sentence goal
- Business justification
- Target users
- Priority

**Success Criteria**:
- Specific, testable acceptance criteria
- Performance baselines with metrics
- Security requirements

**Context**:
- **Documentation References**: URLs with specific sections
- **ai_docs References**: Links to curated docs
- **Codebase Intelligence**:
  - Relevant files with line numbers
  - Code snippets showing patterns to follow
  - Integration points
- **Known Gotchas**: Critical warnings with mitigations

**Implementation Blueprint**:
- Architecture decision with rationale
- Task breakdown with pseudocode (categorized by priority)
- Implementation order

**Task Categorization** (required for each task):

| Category | Description | Execution Behavior |
|----------|-------------|--------------------|
| **Required** | Must be implemented for MVP | Implemented in this PRP execution |
| **Deferred (Phase 2)** | Important but not blocking MVP | Logged and created as GitHub issues |
| **Nice-to-Have** | Optional enhancement | May be skipped, logged if deferred |

Example task breakdown:
```markdown
### Required Tasks
1. Implement core API endpoint
2. Add input validation
3. Write unit tests

### Deferred Tasks (Phase 2)
4. Add caching layer - Reason: requires Redis infrastructure decision
5. Add rate limiting - Reason: needs capacity planning

### Nice-to-Have
6. Add OpenAPI docs generation
7. Add request logging middleware
```

**Important**: All tasks must be explicitly categorized. During execution, any deferred or skipped items will be logged and Phase 2 items will automatically generate GitHub issues for tracking.

**TDD Requirements**:
- Test strategy (unit, integration, e2e)
- Critical test cases with code templates

**Validation Gates**:
- Executable commands for each quality gate
- Expected outcomes

## Phase 3: Assess Confidence

### 3.1 Score Each Dimension

| Dimension | Scoring Criteria |
|-----------|------------------|
| Context Completeness | 10: All file paths, snippets explicit. 7: Most provided. 4: Significant gaps |
| Implementation Clarity | 10: Pseudocode covers all cases. 7: Main path clear. 4: High-level only |
| Gotchas Documented | 10: All known pitfalls. 7: Major gotchas. 4: Some mentioned |
| Validation Coverage | 10: All gates have commands. 7: Main commands. 4: Incomplete |

### 3.2 Calculate Overall Score
- Average of all dimensions
- Target: 7+ for execution, 9+ for subagent delegation

### 3.3 If Score < 7
- [ ] Research missing context
- [ ] Add ai_docs entries
- [ ] Document more gotchas
- [ ] Add validation commands
- [ ] Clarify pseudocode

## Phase 4: Review

### 4.1 Self-Review Checklist
- [ ] Goal is clear and specific
- [ ] Success criteria are testable
- [ ] All file paths are explicit (not "somewhere in...")
- [ ] Code snippets show actual patterns (with line references)
- [ ] Gotchas include mitigations
- [ ] Validation commands are executable
- [ ] Confidence score is honest

### 4.2 Present to User
Show the user:
- PRP summary
- Key implementation approach
- Confidence score
- Any areas needing clarification

**Output Template**:
```
## PRP Created: [Feature Name]

**ID:** {PRP-NNN}
**Location:** `docs/prps/[feature-name].md`
**Implements:** {PRD-NNN} (or "Standalone")

**Summary:**
[1-2 sentence summary of what will be implemented]

**Approach:**
- [Key architectural decision]
- [Main implementation pattern]

**Context Collected:**
- [X] ai_docs entries: [list]
- [X] Codebase patterns identified
- [X] External documentation referenced
- [X] Known gotchas documented

**Linked Documents:**
- Source PRD: {PRD-NNN}
- Related ADRs: {list}

**Validation Gates:**
- Gate 1: [Linting command]
- Gate 2: [Type checking command]
- Gate 3: [Unit tests command]
- Gate 4: [Integration tests command]

**Confidence Score:** X/10
- Context: X/10
- Implementation: X/10
- Gotchas: X/10
- Validation: X/10

**Needs attention (if score < 7):**
- [List any gaps to address]
```

### 4.2.1 Update Manifest

Update `docs/blueprint/manifest.json` ID registry:

```json
{
  "id_registry": {
    "last_prp": {new_number},
    "documents": {
      "{PRP-NNN}": {
        "path": "docs/prps/{feature-name}.md",
        "title": "{Feature Name}",
        "implements": ["{PRD-NNN}"],
        "github_issues": [],
        "created": "{date}"
      }
    }
  }
}
```

If PRP implements a PRD, also update the PRD's registry entry to track the implementation relationship.

### 4.3 Prompt for next action (use AskUserQuestion):

**If confidence score >= 7:**
```
question: "PRP ready (confidence: X/10). What would you like to do?"
options:
  - label: "Execute PRP now (Recommended)"
    description: "Implement the feature with TDD workflow and validation gates"
  - label: "Create work-order for subagent"
    description: "Package this PRP for isolated execution by a subagent"
  - label: "Review and refine first"
    description: "I want to improve the PRP before executing"
  - label: "I'm done for now"
    description: "Save PRP and exit - execute later with /blueprint:prp-execute"
```

**If confidence score < 7:**
```
question: "PRP needs work (confidence: X/10). What would you like to do?"
options:
  - label: "Research more context"
    description: "Explore codebase and documentation to fill gaps"
  - label: "Create ai_docs entries"
    description: "Curate library documentation to improve context"
  - label: "Execute anyway (risky)"
    description: "Proceed with implementation despite low confidence"
  - label: "I'm done for now"
    description: "Save incomplete PRP and return later"
```

**Based on selection:**
- "Execute PRP now" → Run `/blueprint:prp-execute [feature-name]`
- "Create work-order" → Run `/blueprint:work-order`
- "Review and refine" → Show PRP file location and key gaps
- "Research more context" → Use Explore agent on identified gaps
- "Create ai_docs entries" → Run `/blueprint:curate-docs` for relevant libraries
- "Execute anyway" → Run `/blueprint:prp-execute [feature-name]` with warning
- "I'm done" → Exit

**Tips**:
- Be thorough in research phase - it saves implementation time
- Include code snippets with actual line numbers
- Document gotchas as you discover them
- Validation gates should be copy-pasteable commands
- Honest confidence scoring helps decide next steps

**Error Handling**:
- If `docs/blueprint/` doesn't exist → Run `/blueprint:init` first
- If libraries unfamiliar → Research documentation thoroughly
- If codebase patterns unclear → Use Explore agent extensively

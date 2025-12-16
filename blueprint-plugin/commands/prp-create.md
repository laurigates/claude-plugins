---
description: "Create a PRP (Product Requirement Prompt) with systematic research, curated context, and validation gates"
allowed_tools: [Read, Write, Glob, Bash, WebFetch, WebSearch, Task]
---

Create a comprehensive PRP (Product Requirement Prompt) for a feature or component.

**What is a PRP?**
A PRP is PRD + Curated Codebase Intelligence + Implementation Blueprint + Validation Gates - the minimum viable packet an AI agent needs to deliver production code successfully on first attempt.

**Prerequisites**:
- Blueprint Development initialized (`.claude/blueprints/` exists)
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
ls .claude/blueprints/ai_docs/libraries/
ls .claude/blueprints/ai_docs/project/
```

If relevant ai_docs don't exist, create them:
- Extract key patterns from documentation
- Document gotchas discovered in research
- Create curated, concise entries (< 200 lines)

## Phase 2: Draft PRP

### 2.1 Create PRP File
Create the PRP in `.claude/blueprints/prps/`:
```
.claude/blueprints/prps/[feature-name].md
```

### 2.2 Fill Sections

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
- Task breakdown with pseudocode
- Implementation order

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

**Location:** `.claude/blueprints/prps/[feature-name].md`

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

**Ready for:**
- [ ] Execution (`/prp:execute [feature-name]`)
- [ ] Work-order generation (`/blueprint:work-order`)

**Needs attention (if score < 7):**
- [List any gaps to address]
```

**Tips**:
- Be thorough in research phase - it saves implementation time
- Include code snippets with actual line numbers
- Document gotchas as you discover them
- Validation gates should be copy-pasteable commands
- Honest confidence scoring helps decide next steps

**Error Handling**:
- If `.claude/blueprints/` doesn't exist → Run `/blueprint:init` first
- If libraries unfamiliar → Research documentation thoroughly
- If codebase patterns unclear → Use Explore agent extensively

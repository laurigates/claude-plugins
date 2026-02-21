---
model: sonnet
description: "Create a PRP (Product Requirement Prompt) with systematic research, curated context, and validation gates"
args: "[feature-name]"
argument-hint: "Feature name for the PRP (e.g., auth-oauth2, api-rate-limiting)"
allowed-tools: Read, Write, Glob, Bash, WebFetch, WebSearch, Task, AskUserQuestion
created: 2025-12-16
modified: 2026-02-14
reviewed: 2026-02-14
name: blueprint-prp-create
---

# /blueprint:prp-create

Create a comprehensive PRP (Product Requirement Prompt) - a self-contained packet with all context an AI agent needs to deliver production code on first attempt.

**What is a PRP?** PRD + Curated Codebase Intelligence + Implementation Blueprint + Validation Gates = everything needed for reliable implementation.

**Usage**: `/blueprint:prp-create [feature-name]`

**Prerequisites**:
- Blueprint Development initialized (`docs/blueprint/` exists)
- Clear understanding of the feature to implement

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Creating new feature implementation packet | Executing an existing PRP (use `/blueprint:prp-execute`) |
| Want comprehensive research and documentation | Quick prototyping without formal requirements |
| Planning for AI agent or subagent execution | Solo developer implementing without research |
| Need to document implementation approach | Implementing based on existing codebase patterns |

## Context

- Blueprint initialized: !`test -f docs/blueprint/manifest.json 2>/dev/null`
- Last PRP ID: !`jq -r '.id_registry.last_prp // 0' docs/blueprint/manifest.json 2>/dev/null`
- ai_docs available: !`find docs/blueprint/ai_docs -type f -name "*.md" 2>/dev/null`
- Existing PRDs: !`find docs/prds -name "*.md" -type f 2>/dev/null`

## Parameters

Parse `$ARGUMENTS`:

- `feature-name` (required): Kebab-case name for PRP (e.g., `auth-oauth2`, `api-rate-limiting`)
  - Used for filename and document ID generation

## Execution

Execute the complete PRP creation workflow:

### Step 1: Verify prerequisites and understand requirements

1. If Blueprint not initialized → Error: "Run `/blueprint:init` first"
2. Ask user to describe the feature: "What feature needs to be implemented?"
   - Capture: Goal, why it matters, success criteria
3. Ask if this implements an existing PRD: "Does this implement an existing PRD or is it standalone?"
   - If PRD chosen → Store PRD ID for linking
4. Determine feature type (API endpoint, database, UI, integration, etc.)

### Step 2: Research codebase patterns

Use Explore agent to find existing patterns:

1. Similar features already implemented (identify existing patterns to follow)
2. Relevant file locations and integration points
3. Testing patterns used for similar features
4. Architecture decisions that affect this feature

Store findings with specific file paths and line numbers.

### Step 3: Research external documentation

For relevant libraries/frameworks, gather:

1. Official documentation sections (capture URLs with specific sections)
2. Known issues and gotchas from Stack Overflow / GitHub discussions
3. Best practices from documentation
4. Common implementation patterns

Use WebSearch/WebFetch as needed. Create or update ai_docs entries if needed (see [REFERENCE.md](REFERENCE.md#creating-ai-docs)).

### Step 4: Generate PRP document ID and structure

Generate next PRP ID from manifest:
- Extract `id_registry.last_prp` from manifest.json
- Next ID = last_prp + 1 (format: `PRP-NNN`)

Create `docs/prps/[feature-name].md` with frontmatter and sections (see [REFERENCE.md](REFERENCE.md#prp-structure)).

### Step 5: Draft PRP content with research findings

Fill all required sections (see [REFERENCE.md](REFERENCE.md#prp-sections)):

1. **Goal & Why**: One-sentence goal, business justification, target users, priority
2. **Success Criteria**: Specific, testable acceptance criteria with metrics
3. **Context**:
   - Documentation references (URLs with specific sections)
   - ai_docs references (links to curated library docs)
   - **Codebase Intelligence**: File paths, code snippets with line numbers, patterns to follow
   - **Known Gotchas**: Critical warnings with mitigations
4. **Implementation Blueprint**:
   - Architecture decision with rationale
   - Task breakdown (Required / Deferred / Nice-to-Have categories)
   - Order of implementation
5. **TDD Requirements**: Test strategy and critical test cases
6. **Validation Gates**: Executable commands (linting, type-checking, tests, coverage)

**Critical**: All tasks must be explicitly categorized (see [REFERENCE.md](REFERENCE.md#task-categorization)).

### Step 6: Score confidence across dimensions

Rate each dimension 1-10:

| Dimension | Criteria |
|-----------|----------|
| **Context Completeness** | Are all file paths, code snippets, and references explicit? |
| **Implementation Clarity** | Is pseudocode clear enough for AI to follow? |
| **Gotchas Documented** | Are all known pitfalls documented with mitigations? |
| **Validation Coverage** | Are all validation gates with executable commands? |

Calculate overall score as average of dimensions. Target: 7+ for execution, 9+ for subagent delegation.

If score < 7 → Return to Steps 2-3 to fill gaps.

### Step 7: Review and validate completeness

Verify checklist (see [REFERENCE.md](REFERENCE.md#review-checklist)):
- [ ] Goal is clear and specific
- [ ] Success criteria are testable
- [ ] All file paths are explicit (not "somewhere in...")
- [ ] Code snippets show actual patterns with line references
- [ ] Gotchas include mitigations
- [ ] Validation commands are copy-pasteable
- [ ] Confidence score is honest

Update `docs/blueprint/manifest.json` ID registry with new PRP entry.

### Step 8: Report PRP and prompt for next action

Display summary showing:
- PRP ID and location
- Feature summary and approach
- Context collected (ai_docs, patterns, documentation)
- Linked documents (source PRD if applicable)
- Confidence score with breakdown
- Any gaps if score < 7

**If confidence >= 7**, offer user choices:
- Execute PRP now → `/blueprint:prp-execute [feature-name]`
- Create work-order for subagent → `/blueprint:work-order`
- Review and refine → Show file location and gaps
- Done for now → Exit (save for later execution)

**If confidence < 7**, offer user choices:
- Research more context → Use Explore agent for gaps
- Create ai_docs entries → `/blueprint:curate-docs`
- Execute anyway (risky) → Proceed with warning
- Done for now → Save incomplete PRP

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check blueprint init | `test -f docs/blueprint/manifest.json && echo "YES" \|\| echo "NO"` |
| Next PRP ID | `jq -r '.id_registry.last_prp // 0' docs/blueprint/manifest.json \| awk '{print $1+1}'` |
| List existing PRPs | `ls -1 docs/prps/ 2>/dev/null \| wc -l` |
| Search for patterns | Use Explore agent instead of manual grep |
| Fast research | Use existing ai_docs rather than fetching docs again |

---

For PRP document structure, task categorization, review checklists, and ai_docs creation guidance, see [REFERENCE.md](REFERENCE.md).

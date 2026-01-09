# PRP: Automatic Document Management

**Created**: 2026-01-09
**Status**: Draft
**Priority**: P1 - High Impact Feature

---

## Goal

Implement proactive document detection and management in the blueprint-plugin so Claude automatically recognizes when conversations should become PRDs, ADRs, or PRPs, prompts the user for confirmation, and delegates document creation to the appropriate subagent.

### Why

Currently, users must explicitly invoke `/blueprint:prd`, `/blueprint:adr`, or `/blueprint:prp-create` to capture requirements or decisions. This creates friction:
- Valuable context gets lost in conversation history
- Users forget to document decisions in the moment
- Informal discussions bypass the structured documentation workflow

Automatic detection transforms the blueprint-plugin from a passive tool collection into an active documentation partner.

### Target Users

- Developers using blueprint-plugin for structured development
- Teams wanting consistent documentation without manual overhead
- Projects requiring auditable decision records

---

## Success Criteria

| Criterion | Measurement | Target |
|-----------|-------------|--------|
| Detection accuracy | True positives / (True positives + False positives) | >= 80% |
| User acceptance rate | Confirmations / Detections | >= 70% |
| Document quality | Confidence score of generated docs | >= 7/10 |
| Zero disruption | False positive rate causing workflow interruption | <= 10% |

### Acceptance Tests

1. **PRD Detection**: When user describes "I want to build a feature that...", Claude prompts to create PRD
2. **ADR Detection**: When user asks "Should we use X or Y?", Claude prompts to create ADR
3. **PRP Detection**: When user says "Let's implement the login system", Claude prompts to create PRP
4. **Confirmation Flow**: User can accept, reject, or defer document creation
5. **Subagent Delegation**: Accepted documents are created via documentation agent
6. **Migration Support**: `/blueprint:init` offers to migrate root-level docs to `docs/`

---

## Context

### Codebase Intelligence

#### Existing Document Commands

| Command | Location | Purpose |
|---------|----------|---------|
| `/blueprint:prd` | `blueprint-plugin/commands/blueprint-prd.md` | Generate PRD from existing docs |
| `/blueprint:adr` | `blueprint-plugin/commands/blueprint-adr.md` | Generate ADR from project analysis |
| `/blueprint:prp-create` | `blueprint-plugin/commands/blueprint-prp-create.md` | Create implementation PRP |
| `/blueprint:init` | `blueprint-plugin/commands/blueprint-init.md` | Initialize blueprint structure |
| `/blueprint:upgrade` | `blueprint-plugin/commands/blueprint-upgrade.md` | Migrate to latest format |

#### Directory Structure (v2.0.0)

```
docs/
├── prds/                        # Product Requirements Documents
├── adrs/                        # Architecture Decision Records
└── prps/                        # Product Requirement Prompts

.claude/
└── blueprints/
    ├── .manifest.json           # Version tracking and structure flags
    ├── work-orders/             # Task packages for subagents
    ├── ai_docs/                 # Curated documentation
    ├── generated/               # Auto-generated content
    └── work-overview.md         # Progress tracking
```

#### Manifest Schema (v2.0.0)

From `blueprint-init.md` lines 106-143:
```json
{
  "format_version": "2.0.0",
  "structure": {
    "has_prds": true,
    "has_adrs": true,
    "has_prps": true,
    "has_work_orders": true,
    "has_ai_docs": false,
    "has_modular_rules": false,
    "has_feature_tracker": false,
    "has_document_detection": false,  // NEW: Flag for this feature
    "claude_md_mode": "single"
  }
}
```

#### AskUserQuestion Pattern

From existing commands, the standard pattern:
```markdown
Use AskUserQuestion:
question: "Question text"
options:
  - label: "Option 1"
    description: "Description of what happens"
  - label: "Option 2"
    description: "Alternative action"
```

### Documentation References

- [Claude Code Skills Documentation](https://docs.anthropic.com/en/docs/claude-code/skills)
- [AskUserQuestion Tool Reference](https://docs.anthropic.com/en/docs/claude-code/tools#askuserquestion)
- [Task Subagent Pattern](https://docs.anthropic.com/en/docs/claude-code/subagents)

### Known Gotchas

| Gotcha | Impact | Mitigation |
|--------|--------|------------|
| Over-detection | Annoys users with constant prompts | Require high confidence threshold (>= 0.7) |
| Context loss | Detection happens but context not captured | Pass full conversation context to subagent |
| Duplicate detection | Same topic triggers multiple prompts | Track detected topics in session state |
| Skill load order | Detection skill may not load | Add explicit dependency check in skill |

---

## Implementation Blueprint

### Architecture Decision

**Approach**: Create a dedicated `document-detection` skill that pattern-matches conversation content and triggers the AskUserQuestion flow when confidence exceeds threshold.

**Rationale**:
- Skills are auto-loaded based on context (no manual invocation)
- Pattern matching in skill markdown provides transparency
- Subagent delegation keeps detection skill focused

**Alternative Considered**: Hook-based detection on every user message
- Rejected: Too intrusive, no established hook pattern for message analysis

### Component Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Document Detection Flow                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [User Message] ──▶ [Pattern Matching] ──▶ [Confidence Score]   │
│                           │                       │              │
│                           ▼                       ▼              │
│                    document-detection      threshold >= 0.7?     │
│                         skill                    │               │
│                                                  ▼               │
│                                    YES ──▶ [AskUserQuestion]     │
│                                                  │               │
│                                    ┌─────────────┴─────────────┐ │
│                                    ▼             ▼             ▼ │
│                              [Create Doc]  [Defer]   [Decline] │
│                                    │                            │
│                                    ▼                            │
│                          [Prepare Context]                      │
│                                    │                            │
│                                    ▼                            │
│                          [Launch Subagent]                      │
│                                    │                            │
│                                    ▼                            │
│                          [Report & Update Manifest]             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Task Breakdown

#### 1. Create `document-detection` Skill

**Location**: `blueprint-plugin/skills/document-detection/skill.md`

```yaml
---
name: document-detection
description: "Detect PRD/ADR/PRP opportunities in conversations and prompt for document creation"
allowed-tools: AskUserQuestion, Task, Read, Write, Bash
created: 2026-01-09
modified: 2026-01-09
reviewed: 2026-01-09
---
```

**Content Structure**:

```markdown
# Document Detection

Proactively identify when conversations should become structured documents.

## Detection Patterns

### PRD Indicators (Product Requirements)
- User describes features: "I want to build...", "The system should..."
- User stories mentioned: "As a user, I want..."
- Feature lists or requirements enumeration
- Problem/solution discussions
- Priority discussions (P0, P1, must-have, nice-to-have)

**Confidence boosters**:
- Multiple features mentioned (+0.2)
- User personas identified (+0.1)
- Success criteria discussed (+0.1)

### ADR Indicators (Architecture Decisions)
- Technology comparisons: "Should we use X or Y?"
- Trade-off discussions: "The pros and cons of..."
- "Why did we choose..." questions
- Framework/library selection
- Design pattern discussions
- Performance vs. maintainability debates

**Confidence boosters**:
- Multiple options compared (+0.2)
- Explicit trade-offs listed (+0.1)
- Long-term impact discussed (+0.1)

### PRP Indicators (Implementation Prompts)
- Implementation intent: "Let's implement...", "How do we build..."
- Specific scope: "the authentication module", "the payment flow"
- Technical approach discussions
- Test strategy mentions
- File/component planning

**Confidence boosters**:
- Files/paths mentioned (+0.2)
- Test approach discussed (+0.1)
- Clear scope boundaries (+0.1)

## Confidence Calculation

Base confidence starts at 0.5 when primary indicators match.
Apply boosters to reach threshold of 0.7 for prompting.

## Detection Flow

When confidence >= 0.7:

1. **Prompt User**:
   ```
   Use AskUserQuestion:
   question: "This looks like a [PRD/ADR/PRP] opportunity. Would you like to document it?"
   options:
     - label: "Yes, create [document type]"
       description: "I'll gather context and create the document"
     - label: "Not now, remind me later"
       description: "Continue conversation, prompt again if topic expands"
     - label: "No, just continue"
       description: "Skip documentation for this topic"
   ```

2. **If accepted, gather clarification**:
   ```
   Use AskUserQuestion:
   question: "[Context-specific question based on document type]"
   ```

   For PRD: "Who are the target users?"
   For ADR: "What constraints should I consider?"
   For PRP: "What's the priority and timeline?"

3. **Prepare context package**:
   - Extract key points from conversation
   - Include user's clarifying responses
   - Identify related existing documents

4. **Delegate to documentation agent**:
   ```
   <Task subagent_type="documentation" prompt="Create [document type] based on conversation context: [context summary]">
   ```

5. **Report result**:
   - Show document location
   - Summarize key sections
   - Suggest next steps

## Session Tracking

To avoid duplicate prompts:
- Track detected topics in conversation
- Don't re-prompt for declined topics
- Re-prompt for deferred topics after significant new context

## Integration with Commands

When detection leads to document creation, the underlying command logic is reused:
- PRD detection → triggers `/blueprint:prd` workflow
- ADR detection → triggers `/blueprint:adr` workflow
- PRP detection → triggers `/blueprint:prp-create` workflow
```

#### 2. Create Document Management Rule Template

**Location**: `blueprint-plugin/templates/document-management-rule.md`

This template is installed to target projects during `/blueprint:init`:

```markdown
# Document Management

## Document Types and Locations

| Document Type | Directory | Naming Convention |
|--------------|-----------|-------------------|
| PRD | `docs/prds/` | `{feature-name}.md` |
| ADR | `docs/adrs/` | `{number}-{title}.md` (e.g., `0001-database-choice.md`) |
| PRP | `docs/prps/` | `{feature-name}.md` |

## Root Directory Policy

The repository root should contain only:
- `README.md` - Project overview
- `CHANGELOG.md` - Release notes (auto-generated)
- `LICENSE` - License file
- `CONTRIBUTING.md` - Contribution guidelines (optional)
- Configuration files (package.json, Cargo.toml, etc.)

Documentation files (PRDs, ADRs, design docs) belong in `docs/`.

## Document Lifecycle

1. **Detection**: Claude identifies documentation opportunities in conversation
2. **Confirmation**: User approves document creation
3. **Generation**: Document created in appropriate location
4. **Review**: User reviews and refines
5. **Tracking**: Manifest updated with document metadata

## Automatic Detection

When enabled, Claude will prompt to create:
- **PRD** when feature requirements are discussed
- **ADR** when architecture decisions are debated
- **PRP** when implementation approach is planned

Configure in `.claude/blueprints/.manifest.json`:
```json
{
  "structure": {
    "has_document_detection": true
  }
}
```
```

#### 3. Modify `/blueprint:init` Command

**File**: `blueprint-plugin/commands/blueprint-init.md`

**Changes** (insert after step 4, before step 5):

```markdown
4.5. **Ask about document detection**:
   ```
   question: "Would you like to enable automatic document detection?"
   options:
     - label: "Yes - Detect PRD/ADR/PRP opportunities"
       description: "Claude will prompt when conversations should become documents"
     - label: "No - Manual commands only"
       description: "Use /blueprint:prd, /blueprint:adr, /blueprint:prp-create explicitly"
   ```

   Set `has_document_detection` in manifest based on response.

4.6. **Check for root documentation to migrate**:
   ```bash
   # Find markdown files in root that look like documentation
   fd -d 1 -e md . | grep -viE '^(README|CHANGELOG|CONTRIBUTING|LICENSE)'
   ```

   If documentation files found in root:
   ```
   question: "Found documentation files in root directory. Would you like to organize them?"
   options:
     - label: "Yes, move to docs/"
       description: "Migrate existing docs to proper structure"
     - label: "No, leave them"
       description: "Keep files in current location"
   ```

   **If "Yes" selected**:
   a. Analyze each file to determine type (PRD, ADR, design doc)
   b. Move to appropriate `docs/` subdirectory
   c. Update any internal links
   d. Report migration results
```

**Update manifest schema** (step 6):
```json
{
  "structure": {
    "has_document_detection": "[based on user choice]"
  }
}
```

#### 4. Modify `/blueprint:upgrade` Command

**File**: `blueprint-plugin/commands/blueprint-upgrade.md`

**Add to step 6** (migration overview):

```markdown
   f. **Enable document detection option**:
      ```
      question: "Would you like to enable automatic document detection? (New in v2.1)"
      options:
        - label: "Yes - Detect PRD/ADR/PRP opportunities"
          description: "Claude will prompt when conversations should become documents"
        - label: "No - Keep manual commands only"
          description: "Continue using explicit /blueprint: commands"
      ```

   g. **Migrate root documentation** (if any found):
      - Scan for markdown files in root
      - Offer to move to `docs/` structure
      - Update manifest with migration record
```

#### 5. Update Plugin Metadata

**File**: `blueprint-plugin/.claude-plugin/plugin.json`

Add to keywords:
```json
{
  "keywords": [
    "document-detection",
    "automatic-documentation",
    "proactive-documentation"
  ]
}
```

---

## TDD Requirements

### Test Strategy

| Level | Focus | Tools |
|-------|-------|-------|
| Unit | Pattern matching logic | Manual verification |
| Integration | AskUserQuestion flow | Interactive testing |
| E2E | Full detection → creation cycle | Project simulation |

### Critical Test Cases

#### 1. PRD Detection Tests

```markdown
**Test: PRD trigger on feature description**
Input: "I want to build a user authentication system with OAuth2 support, password reset, and MFA"
Expected: Confidence >= 0.7, PRD type detected
Verification: AskUserQuestion prompts for PRD creation

**Test: PRD trigger on user stories**
Input: "As an admin, I want to manage user permissions so that I can control access"
Expected: Confidence >= 0.7, PRD type detected

**Test: No PRD trigger on casual mention**
Input: "We might need auth eventually"
Expected: Confidence < 0.7, no prompt
```

#### 2. ADR Detection Tests

```markdown
**Test: ADR trigger on technology comparison**
Input: "Should we use PostgreSQL or MongoDB for the user data? We need to consider query patterns and scalability"
Expected: Confidence >= 0.7, ADR type detected
Verification: AskUserQuestion prompts for ADR creation

**Test: ADR trigger on trade-off discussion**
Input: "The pros of using microservices are scalability and team independence, but the cons are operational complexity"
Expected: Confidence >= 0.7, ADR type detected

**Test: No ADR trigger on simple question**
Input: "What database do we use?"
Expected: Confidence < 0.7, no prompt
```

#### 3. PRP Detection Tests

```markdown
**Test: PRP trigger on implementation intent**
Input: "Let's implement the payment processing module with Stripe integration"
Expected: Confidence >= 0.7, PRP type detected
Verification: AskUserQuestion prompts for PRP creation

**Test: PRP trigger on technical planning**
Input: "We need to create PaymentService.ts, add routes in /api/payments, and write integration tests"
Expected: Confidence >= 0.8 (file paths boost), PRP type detected

**Test: No PRP trigger on vague discussion**
Input: "We should probably do something with payments"
Expected: Confidence < 0.7, no prompt
```

#### 4. Flow Tests

```markdown
**Test: User accepts document creation**
Scenario: Detection triggers, user selects "Yes, create PRD"
Expected:
  - Clarifying question asked
  - Context prepared
  - Documentation subagent launched
  - Document created in docs/prds/
  - Location reported to user

**Test: User defers document creation**
Scenario: Detection triggers, user selects "Not now"
Expected:
  - No document created
  - Topic tracked in session
  - Re-prompt if topic expands significantly

**Test: User declines document creation**
Scenario: Detection triggers, user selects "No, just continue"
Expected:
  - No document created
  - Topic marked as declined
  - No re-prompt for this topic
```

#### 5. Migration Tests

```markdown
**Test: Root doc detection during init**
Setup: Project with `DESIGN.md` and `ARCHITECTURE.md` in root
Run: /blueprint:init
Expected: User prompted to migrate files

**Test: Root doc migration execution**
Setup: `DESIGN.md` in root contains PRD-like content
Action: User accepts migration
Expected:
  - File moved to docs/prds/design.md
  - Internal links updated if possible
  - Migration recorded in manifest

**Test: Upgrade enables detection option**
Setup: Project with v2.0.0 manifest, detection disabled
Run: /blueprint:upgrade
Expected: User prompted about enabling document detection
```

---

## Validation Gates

| Gate | Command | Expected Outcome |
|------|---------|------------------|
| Skill loads | `claude --print "list skills" \| grep document-detection` | Skill appears in list |
| Pattern file valid | `head -20 blueprint-plugin/skills/document-detection/skill.md` | Valid YAML frontmatter |
| Init modified | `grep -n "document detection" blueprint-plugin/commands/blueprint-init.md` | Section found |
| Upgrade modified | `grep -n "document detection" blueprint-plugin/commands/blueprint-upgrade.md` | Section found |
| Keywords updated | `jq '.keywords[]' blueprint-plugin/.claude-plugin/plugin.json \| grep -c document` | >= 1 |
| No syntax errors | `cat blueprint-plugin/skills/document-detection/skill.md \| head -5` | Valid YAML |

### Manual Validation Steps

1. **Test Detection Flow**:
   ```
   Start new Claude session with blueprint-plugin
   Say: "I want to build a notification system with email, SMS, and push notifications"
   Expected: Claude prompts to create PRD
   ```

2. **Test Init Migration**:
   ```
   Create test project with DESIGN.md in root
   Run: /blueprint:init
   Expected: Prompted to migrate DESIGN.md to docs/
   ```

3. **Test Subagent Delegation**:
   ```
   Accept document creation prompt
   Expected: Documentation agent creates document with conversation context
   ```

---

## Confidence Score

### Self-Assessment

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Context Completeness | 8/10 | All file paths explicit, command structures documented, manifest schema shown. Minor gap: exact subagent prompt format could be more detailed. |
| Implementation Clarity | 8/10 | Clear skill structure, pattern matching approach defined, flow diagrams included. Minor gap: session state tracking for deferrals not fully specified. |
| Gotchas Documented | 7/10 | Main gotchas (over-detection, context loss, duplicates) identified with mitigations. May discover more during implementation. |
| Validation Coverage | 9/10 | All gates have executable commands, test cases cover main scenarios. |

**Overall Score: 8/10**

### Areas Needing Attention

1. **Session state tracking**: How to persist deferred/declined topics across conversation turns
2. **Subagent context format**: Exact structure of context package for documentation agent
3. **Link updating during migration**: Regex patterns for updating internal doc links

### Recommendation

Score >= 7: Ready for execution. Address minor gaps during implementation.

---

## Files Summary

| File | Action | Lines Changed (Est.) |
|------|--------|---------------------|
| `blueprint-plugin/skills/document-detection/skill.md` | Create | ~150 |
| `blueprint-plugin/templates/document-management-rule.md` | Create | ~50 |
| `blueprint-plugin/commands/blueprint-init.md` | Modify | +40 |
| `blueprint-plugin/commands/blueprint-upgrade.md` | Modify | +25 |
| `blueprint-plugin/.claude-plugin/plugin.json` | Modify | +3 |
| `blueprint-plugin/README.md` | Modify | +15 |

---

*Generated via PRP template. Execute with `/blueprint:prp-execute automatic-document-management`*

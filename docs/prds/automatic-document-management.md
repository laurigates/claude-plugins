# Automatic Document Management - Product Requirements Document

**Created**: 2026-01-09
**Status**: Draft
**Version**: 1.0
**Author**: Blueprint Development Team

---

## Executive Summary

### Problem Statement

Users must explicitly invoke `/blueprint:prd`, `/blueprint:adr`, or `/blueprint:prp-create` commands to create documentation artifacts. This interrupts workflow and relies on users recognizing when documentation is needed. Valuable requirements discussions, architectural decisions, and implementation plans emerge naturally during conversations but are lost without explicit action.

### Proposed Solution

A proactive detection system where Claude monitors conversation patterns for emerging PRD/ADR/PRP content, prompts users with clarifying questions using `AskUserQuestion`, and delegates document creation to specialized subagents. The system ensures clean project structure by placing documents in `docs/{prds,adrs,prps}/` directories.

### Business Impact

- **Reduced cognitive load**: Users focus on discussing requirements rather than remembering to document them
- **Improved documentation coverage**: Capture valuable discussions that would otherwise be lost
- **Consistent project structure**: Automated enforcement of clean root directories
- **Better onboarding**: New contributors find documentation in expected locations

---

## Stakeholders & Personas

### Stakeholder Matrix

| Role | Name/Team | Responsibility | Contact |
|------|-----------|----------------|---------|
| Product Owner | Blueprint Plugin Team | Feature requirements and priorities | - |
| Developer | Plugin Contributors | Implementation and testing | - |
| End User | Claude Code Users | Validate workflow integration | - |

### User Personas

#### Primary: Solo Developer

- **Description**: Individual developer using Claude Code for personal or professional projects
- **Needs**: Minimal workflow interruption, automatic documentation capture
- **Pain Points**: Forgetting to create PRDs/ADRs, scattered documentation files
- **Goals**: Well-documented projects without manual overhead

#### Secondary: Team Lead

- **Description**: Developer responsible for project documentation standards
- **Needs**: Consistent documentation structure, easy review process
- **Pain Points**: Inconsistent documentation locations, missing architectural decisions
- **Goals**: Enforceable documentation standards across team projects

---

## Functional Requirements

### FR1: Document Pattern Detection in Conversations

Claude monitors conversation content and identifies patterns that indicate emerging documentation needs.

#### FR1.1: PRD Trigger Detection

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR1.1.1 | Feature discussion detection | Detect when users describe new features or capabilities | P0 |
| FR1.1.2 | Requirements enumeration | Identify numbered lists of requirements or user stories | P0 |
| FR1.1.3 | User story patterns | Recognize "As a [user], I want [feature]" patterns | P1 |
| FR1.1.4 | Success criteria discussion | Detect acceptance criteria and definition of done | P1 |
| FR1.1.5 | Stakeholder identification | Recognize discussion of target users or personas | P2 |

**Trigger keywords/patterns**:
- "the feature should...", "users need to be able to..."
- "requirements include...", "the system must..."
- "acceptance criteria:", "success looks like..."
- "target users are...", "personas include..."

#### FR1.2: ADR Trigger Detection

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR1.2.1 | Technology decision detection | Identify discussions comparing technologies | P0 |
| FR1.2.2 | Trade-off analysis | Detect pros/cons lists and comparisons | P0 |
| FR1.2.3 | Architecture patterns | Recognize discussion of design patterns or structures | P1 |
| FR1.2.4 | Decision rationale | Identify "we chose X because Y" statements | P1 |
| FR1.2.5 | Alternative evaluation | Detect "we considered but rejected" patterns | P2 |

**Trigger keywords/patterns**:
- "we should use X instead of Y because..."
- "the trade-offs are...", "pros and cons:"
- "architecturally, we need to..."
- "I decided to go with...", "the rationale is..."
- "we considered but rejected..."

#### FR1.3: PRP Trigger Detection

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR1.3.1 | Implementation planning | Detect detailed implementation discussions | P0 |
| FR1.3.2 | Task breakdown | Identify step-by-step implementation plans | P0 |
| FR1.3.3 | Code location references | Recognize file path and code location discussions | P1 |
| FR1.3.4 | Validation criteria | Detect test cases and validation requirements | P1 |
| FR1.3.5 | Dependency identification | Identify discussions of prerequisites | P2 |

**Trigger keywords/patterns**:
- "to implement this, we need to..."
- "the steps are: 1) ... 2) ... 3) ..."
- "the code should go in...", "modify the file at..."
- "we'll test this by...", "validation includes..."
- "this depends on...", "prerequisites:"

### FR2: AskUserQuestion Integration

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR2.1 | Document confirmation prompt | Ask user to confirm document creation intent | P0 |
| FR2.2 | Document type clarification | Clarify which document type best fits the content | P0 |
| FR2.3 | Scope clarification | Ask about document scope and boundaries | P1 |
| FR2.4 | Metadata gathering | Collect document title, stakeholders, priority | P1 |
| FR2.5 | Opt-out mechanism | Allow users to decline document creation | P0 |

**Question templates**:

```
question: "This discussion contains [requirements/architecture decisions/implementation details]. Would you like me to capture this as a [PRD/ADR/PRP]?"
options:
  - label: "Yes, create [document type]"
    description: "I'll organize this into a structured document in docs/[type]s/"
  - label: "Not now, but save for later"
    description: "I'll note this for potential documentation later"
  - label: "No, this is just exploratory"
    description: "Skip documentation for this discussion"
```

```
question: "What should this [PRD/ADR/PRP] be titled?"
options:
  - label: "[Auto-suggested title based on content]"
    description: "Use the inferred title"
  - label: "Let me specify"
    description: "I'll provide a custom title"
```

### FR3: Subagent Delegation for Document Writing

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR3.1 | Context packaging | Package conversation context for subagent | P0 |
| FR3.2 | Template application | Apply appropriate document template | P0 |
| FR3.3 | Content extraction | Extract relevant content from conversation | P0 |
| FR3.4 | Document generation | Generate structured document from context | P0 |
| FR3.5 | Review presentation | Present generated document for user review | P1 |
| FR3.6 | Iterative refinement | Allow user to request changes before saving | P2 |

**Subagent invocation pattern**:
```
<Task subagent_type="documentation" prompt="Create a [PRD/ADR/PRP] from the following conversation context: [packaged context]">
```

### FR4: Root Directory Cleanup Policy

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR4.1 | Document placement enforcement | Create documents in `docs/{prds,adrs,prps}/` only | P0 |
| FR4.2 | Root file detection | Identify documentation files incorrectly placed in root | P1 |
| FR4.3 | Migration suggestion | Suggest moving root docs to proper locations | P1 |
| FR4.4 | Automatic migration | Offer to move files during document creation | P2 |

**Cleanup rules**:
- PRDs: `docs/prds/{feature-name}.md`
- ADRs: `docs/adrs/{number}-{decision-name}.md`
- PRPs: `docs/prps/{feature-name}.md`
- Never create `PRD.md`, `ADR.md`, or similar in project root

### FR5: Document Migration During Onboarding/Upgrade

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR5.1 | Root document scanning | Scan root for migratable documentation files | P0 |
| FR5.2 | Document type classification | Classify found documents by type (PRD/ADR/PRP) | P1 |
| FR5.3 | Migration confirmation | Ask user before migrating each document | P0 |
| FR5.4 | Batch migration | Support migrating multiple documents at once | P2 |
| FR5.5 | Migration report | Report what was migrated and where | P1 |

**Files to detect**:
- `PRD*.md`, `REQUIREMENTS*.md`, `SPEC*.md` -> `docs/prds/`
- `ADR*.md`, `DECISION*.md`, `ARCHITECTURE*.md` -> `docs/adrs/`
- `PRP*.md`, `IMPLEMENTATION*.md`, `PLAN*.md` -> `docs/prps/`
- `README.md` (when it contains requirements) -> Extract to `docs/prds/`

### FR6: CLAUDE.md and .claude/rules/ Integration

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR6.1 | Rule file creation | Create rules for automatic document management | P1 |
| FR6.2 | CLAUDE.md documentation | Document feature in CLAUDE.md during init | P1 |
| FR6.3 | Confidence threshold config | Allow configuring detection sensitivity | P2 |
| FR6.4 | Trigger customization | Allow customizing trigger patterns | P2 |

**Rule file content** (`.claude/rules/documentation.md`):
```markdown
# Documentation Management

Automatic document management is enabled for this project.

## Behavior
- Claude monitors conversations for PRD/ADR/PRP content
- Documents are created in `docs/{prds,adrs,prps}/`
- User confirmation is required before creating documents

## Configuration
- Detection confidence threshold: 0.7
- Enabled document types: PRD, ADR, PRP
```

---

## Non-Functional Requirements

### NFR1: Performance

| Requirement | Target | Measurement |
|-------------|--------|-------------|
| Detection latency | < 500ms | Time from message receipt to pattern detection |
| Prompt response time | < 2s | Time from detection to AskUserQuestion display |
| Document generation | < 30s | Time for subagent to generate complete document |

### NFR2: User Experience

| Requirement | Target | Measurement |
|-------------|--------|-------------|
| Confidence threshold | 0.7 | Minimum confidence before prompting user |
| False positive rate | < 10% | Prompts for non-documentation content |
| Max clarifying questions | 3 | Questions before document creation |
| Interruption frequency | < 1 per 10 messages | Average prompts per conversation messages |

### NFR3: Reliability

| Requirement | Target | Measurement |
|-------------|--------|-------------|
| Document creation success | > 99% | Successfully saved documents / attempted |
| Migration success | 100% | Files correctly moved without data loss |
| Template compliance | 100% | Documents follow standard templates |

### NFR4: Compatibility

| Requirement | Description |
|-------------|-------------|
| Blueprint version | Compatible with Blueprint v2.0.0+ |
| Existing projects | Non-breaking for projects without feature enabled |
| Manual commands | Coexist with explicit `/blueprint:prd`, etc. commands |

---

## Technical Considerations

### Architecture

```
Conversation Input
       │
       ▼
┌─────────────────┐
│ Pattern Detector │ ◄── FR1.1, FR1.2, FR1.3 triggers
└────────┬────────┘
         │ confidence > 0.7
         ▼
┌─────────────────┐
│ AskUserQuestion │ ◄── FR2 integration
└────────┬────────┘
         │ user confirms
         ▼
┌─────────────────┐
│ Context Packager │ ◄── FR3.1 - extract relevant context
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Subagent Invoke │ ◄── FR3 - documentation subagent
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ File Writer     │ ◄── FR4 - enforce directory structure
└─────────────────┘
```

### Dependencies

- **AskUserQuestion tool**: Required for user confirmation flow
- **Task tool**: Required for subagent delegation
- **Write tool**: Required for document creation
- **Glob/Read tools**: Required for root directory scanning

### Integration Points

- **Blueprint init**: Enable feature during `/blueprint:init`
- **Blueprint upgrade**: Add migration during `/blueprint:upgrade`
- **Manifest**: Track feature enablement in `.manifest.json`
- **Rules**: Create `.claude/rules/documentation.md`

### Data Flow

1. **Detection**: Analyze incoming messages for document patterns
2. **Scoring**: Calculate confidence score for each document type
3. **Prompting**: Present AskUserQuestion if confidence > threshold
4. **Packaging**: Extract relevant context from conversation
5. **Delegation**: Invoke documentation subagent with context
6. **Writing**: Save document to appropriate `docs/` subdirectory
7. **Reporting**: Confirm document creation to user

---

## Success Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| Document capture rate | 0% (manual only) | > 80% | Discussions that become docs / discussions that should become docs |
| User interruption | N/A | < 3 questions | Clarifying questions before delegation |
| False positive rate | N/A | < 10% | Incorrect document type suggestions |
| Migration completeness | N/A | 100% | Root docs identified during init / total root docs |
| User satisfaction | N/A | > 4/5 | Post-feature survey rating |
| Adoption rate | N/A | > 50% | Projects enabling feature during init |

---

## Scope

### In Scope

- Pattern detection for PRD, ADR, and PRP content
- User confirmation via AskUserQuestion before document creation
- Subagent delegation for document writing
- Document placement in `docs/{prds,adrs,prps}/`
- Root directory migration during onboarding
- Configuration via `.claude/rules/` and manifest
- Integration with existing `/blueprint:*` commands

### Out of Scope

- Automatic document creation without user confirmation
- Detection of other document types (e.g., README, CONTRIBUTING)
- Version control integration (commits, PRs)
- External documentation systems (Confluence, Notion)
- Natural language processing beyond pattern matching
- Custom document templates per project
- Multi-language support for pattern detection

### Future Considerations

- Machine learning-based detection improvements
- Custom trigger pattern configuration
- Integration with issue trackers for requirement linking
- Automatic document updates when discussions continue
- Cross-document reference linking
- Documentation coverage reports

---

## Timeline & Phases

### Current Phase: Planning

PRD creation and stakeholder review.

### Roadmap

| Phase | Focus | Status | Target |
|-------|-------|--------|--------|
| Phase 1 | Core detection and prompting (FR1, FR2) | Not Started | v2.1.0 |
| Phase 2 | Subagent delegation and document creation (FR3, FR4) | Not Started | v2.1.0 |
| Phase 3 | Migration and onboarding integration (FR5) | Not Started | v2.2.0 |
| Phase 4 | Configuration and rules integration (FR6) | Not Started | v2.2.0 |

### Phase 1 Deliverables

- Pattern detection skill for PRD/ADR/PRP triggers
- Confidence scoring integration
- AskUserQuestion prompts for document confirmation
- Unit tests for pattern detection

### Phase 2 Deliverables

- Context packaging for subagent delegation
- Documentation subagent invocation
- File writing with directory enforcement
- Integration tests for document creation flow

### Phase 3 Deliverables

- Root directory scanner
- Document type classifier
- Migration workflow in `/blueprint:init`
- Migration workflow in `/blueprint:upgrade`

### Phase 4 Deliverables

- `.claude/rules/documentation.md` template
- Manifest configuration for feature enablement
- Threshold and trigger customization
- User documentation

---

## User Stories

### Detection and Prompting

- As a developer, I want Claude to recognize when I'm discussing requirements so I don't have to remember to create a PRD
- As a developer, I want Claude to ask before creating documents so I maintain control over my project structure
- As a developer, I want to decline document creation without interrupting my workflow

### Document Organization

- As a developer, I want my root directory clean of scattered documentation files
- As a team lead, I want consistent documentation locations across all team projects
- As a new contributor, I want to find documentation in standard locations

### Migration

- As a new project contributor, I want existing docs migrated to standard locations during onboarding
- As a project maintainer, I want to clean up legacy documentation placement during upgrade
- As a developer, I want migration to preserve my document content exactly

### Configuration

- As a power user, I want to adjust detection sensitivity to match my workflow
- As a team lead, I want to enforce documentation standards via rules files
- As a developer, I want to disable automatic detection if it doesn't fit my needs

---

*Generated via PRD-first development workflow*
*Review and update as project evolves*

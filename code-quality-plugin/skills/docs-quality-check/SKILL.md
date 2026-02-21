---
model: haiku
created: 2026-01-08
modified: 2026-02-03
reviewed: 2026-01-08
description: "Analyze codebase documentation quality - PRDs, ADRs, PRPs, CLAUDE.md, and .claude/rules/"
allowed-tools: Read, Glob, Grep, Bash(markdownlint *), Bash(vale *), TodoWrite, Task
args: "[PATH]"
argument-hint: "[PATH]"
name: docs-quality-check
---

Analyze and validate documentation quality for a codebase, ensuring PRDs, ADRs, PRPs, CLAUDE.md, and .claude/rules/ are up to standards and current.

## Context

- Target path: `$1` (defaults to current directory if not specified)
- Blueprint dir exists: !`test -d .claude/blueprints`
- CLAUDE.md exists: !`test -f CLAUDE.md`
- Rules directory: !`find .claude/rules -maxdepth 1 -name '*.md' 2>/dev/null`
- ADRs (docs/adr): !`find docs/adr -maxdepth 1 -name '*.md' 2>/dev/null`
- ADRs (docs/adrs): !`find docs/adrs -maxdepth 1 -name '*.md' 2>/dev/null`
- PRDs (docs/prds): !`find docs/prds -maxdepth 1 -name '*.md' 2>/dev/null`
- PRDs (blueprints): !`find .claude/blueprints/prds -maxdepth 1 -name '*.md' 2>/dev/null`
- PRPs (docs/prps): !`find docs/prps -maxdepth 1 -name '*.md' 2>/dev/null`
- PRPs (blueprints): !`find .claude/blueprints/prps -maxdepth 1 -name '*.md' 2>/dev/null`

## Parameters

- `$1`: Path to analyze (defaults to current directory)

## Your Task

Perform a comprehensive documentation quality analysis using the following methodology:

## Phase 1: Create Todo List

Create a structured todo list for tracking the analysis:

```
- Analyze CLAUDE.md structure and quality
- Check .claude/rules/ directory and standards
- Validate ADRs (Architecture Decision Records)
- Validate PRDs (Product Requirements Documents)
- Validate PRPs (Product Requirement Prompts)
- Check documentation freshness and git history
- Generate quality report with recommendations
```

## Phase 2: CLAUDE.md Analysis

### 2.1 Check Existence and Structure
- Verify `CLAUDE.md` exists at project root
- Check for required YAML frontmatter:
  ```yaml
  ---
  created: YYYY-MM-DD
  modified: YYYY-MM-DD
  reviewed: YYYY-MM-DD
  ---
  ```

### 2.2 Content Quality Checks
- **Completeness**: Does it provide clear project context?
  - Project structure overview
  - Development conventions
  - Key rules and guidelines
  - Plugin/tool references if applicable

- **Clarity**: Is it well-organized and readable?
  - Clear sections with headers
  - Proper markdown formatting
  - Tables for structured data
  - Examples where helpful

- **Accuracy**: Check for outdated information
  - Compare modified date with recent git commits
  - Look for references to deprecated patterns
  - Validate file paths and references exist

### 2.3 Best Practices
Check against CLAUDE.md standards:
- Should guide AI assistants on how to work with the codebase
- Include project structure explanation
- Reference key rules and conventions
- Point to additional documentation (ADRs, rules)
- Use tables for quick reference
- Keep focused and concise

## Phase 3: .claude/rules/ Analysis

### 3.1 Directory Structure
- Verify `.claude/rules/` directory exists
- List all rule files present
- Check for recommended core rules:
  - Architecture/design patterns
  - Coding standards
  - Development workflows
  - Testing requirements

### 3.2 Individual Rule Validation
For each rule file in `.claude/rules/`:

**Required Frontmatter**:
```yaml
---
created: YYYY-MM-DD
modified: YYYY-MM-DD
reviewed: YYYY-MM-DD
name: docs-quality-check
---
```

**Content Standards**:
- Clear title and purpose
- Well-defined scope
- Specific, actionable guidance
- Examples where appropriate
- Related rules cross-referenced

### 3.3 Rules Organization
- Are rules properly categorized?
- Are there too many/too few rules?
- Is there duplication or conflict between rules?
- Are rule names descriptive and consistent?

## Phase 4: ADR Validation

### 4.1 Check ADR Directory
- Verify `docs/adrs/` or `docs/adr/` exists
- Check for ADR index/README
- List all ADR files (should be numbered: 0001-title.md)

### 4.2 ADR Structure Validation
For each ADR, verify:

**Naming Convention**:
- Format: `NNNN-kebab-case-title.md` (e.g., `0001-plugin-architecture.md`)
- Sequential numbering
- Descriptive titles

**Required Sections** (MADR format):
```markdown
# ADR-NNNN: Title

**Date**: YYYY-MM
**Status**: Accepted | Superseded | Deprecated
**Deciders**: [who made the decision]

## Context
[The issue motivating this decision]

## Decision
[The change being proposed or made]

## Consequences
[What becomes easier or harder]
```

### 4.3 ADR Quality Checks
- **Status accuracy**: Are deprecated ADRs marked?
- **Completeness**: Do ADRs have all required sections?
- **Relevance**: Are ADRs still applicable to current codebase?
- **Index maintenance**: Is the ADR index up to date?

### 4.4 Coverage Analysis
- Do ADRs cover major architectural decisions?
- Are recent significant changes documented?
- Are there obvious undocumented decisions?

## Phase 5: PRD Validation

### 5.1 Check PRD Directory
- Verify `docs/prds/` or `.claude/blueprints/prds/` exists
- List all PRD files

### 5.2 PRD Structure Validation
For each PRD, verify:

**Frontmatter** (if using Blueprint methodology):
```yaml
---
created: YYYY-MM-DD
modified: YYYY-MM-DD
reviewed: YYYY-MM-DD
status: Draft | Active | Implemented | Archived
name: docs-quality-check
---
```

**Required Sections**:
- Executive Summary / Problem Statement
- Stakeholders & User Personas
- Functional Requirements
- Non-Functional Requirements
- Success Metrics
- Scope (In/Out of scope)
- Technical Considerations

### 5.3 PRD Quality Checks
- **Clarity**: Are requirements specific and measurable?
- **Completeness**: Are all key sections present?
- **Status**: Is the status field accurate?
- **Traceability**: Can requirements be traced to implementations?
- **User focus**: Are user needs clearly articulated?

## Phase 6: PRP Validation

### 6.1 Check PRP Directory
- Verify `docs/prps/` exists (Blueprint methodology)
- List all PRP files

### 6.2 PRP Structure Validation
For each PRP, verify:

**Required Sections**:
- Goal & Why
- Success Criteria (testable)
- Context (documentation refs, codebase intelligence, known gotchas)
- Implementation Blueprint (architecture, task breakdown)
- TDD Requirements (test strategy, critical test cases)
- Validation Gates (executable commands)
- Confidence Score (0-10 across dimensions)

### 6.3 PRP Quality Checks
- **Specificity**: Are file paths and code references explicit?
- **Testability**: Are success criteria measurable?
- **Completeness**: Does the confidence score match content quality?
- **Actionability**: Can this PRP be executed immediately?
- **Context**: Is there enough curated context for implementation?

## Phase 7: Freshness Analysis

### 7.1 Check Last Modified Dates
For all documentation:
- Compare `modified` frontmatter dates with git history
- Identify stale documents (>6 months without review)
- Flag documents that should be reviewed based on related code changes

Use git to check activity:
```bash
# Check recent commits affecting docs
git log --since="6 months ago" --oneline -- docs/ .claude/ CLAUDE.md 2>/dev/null || echo "Not a git repo or no history"

# Check when documentation was last touched
git log -1 --format="%ai %s" -- CLAUDE.md 2>/dev/null || echo "No git history"
```

### 7.2 Cross-Reference with Code Changes
- Have there been major code changes without doc updates?
- Are ADRs current with actual architecture?
- Do PRDs reflect implemented features accurately?

## Phase 8: Generate Quality Report

### 8.1 Documentation Inventory

Generate a summary table:

```markdown
## Documentation Inventory

| Document Type | Status | Count | Issues |
|---------------|--------|-------|--------|
| CLAUDE.md | ✅/❌ | 1 | [list issues] |
| .claude/rules/ | ✅/❌ | N files | [list issues] |
| ADRs | ✅/❌ | N files | [list issues] |
| PRDs | ✅/❌ | N files | [list issues] |
| PRPs | ✅/❌ | N files | [list issues] |
```

### 8.2 Quality Score

Calculate an overall quality score:

| Category | Score (0-10) | Notes |
|----------|--------------|-------|
| Structure | X | File organization, naming |
| Completeness | X | Required sections present |
| Freshness | X | Recent updates, git sync |
| Standards Compliance | X | Frontmatter, format |
| Content Quality | X | Clarity, specificity |
| **Overall** | **X** | Average score |

**Rating Guide**:
- 9-10: Excellent - Well-maintained, comprehensive
- 7-8: Good - Minor improvements needed
- 5-6: Fair - Several issues to address
- 3-4: Poor - Major gaps or outdated
- 0-2: Critical - Missing or severely lacking

### 8.3 Issues and Recommendations

Categorize findings:

**Critical Issues** (must fix):
- Missing required documentation
- Severe structural problems
- Completely outdated information

**Warnings** (should fix):
- Stale documentation (>6 months)
- Missing frontmatter
- Incomplete sections
- Minor structural issues

**Suggestions** (nice to have):
- Additional documentation that would help
- Improved organization
- Better cross-referencing
- Enhanced examples

### 8.4 Actionable Recommendations

For each issue, provide specific guidance:

```markdown
## Recommendations

### Immediate Actions
1. [ ] Fix [specific issue] in [file]
   - **Why**: [reason]
   - **How**: [specific steps]
   - **Command**: [if applicable]

2. [ ] Update [document]
   - **Why**: [reason]
   - **How**: [specific steps]

### Maintenance Tasks
1. [ ] Review and update stale documents:
   - [file1] - last modified [date]
   - [file2] - last modified [date]

2. [ ] Improve documentation coverage:
   - [ ] Document [undocumented decision]
   - [ ] Create ADR for [architectural choice]

### Best Practices
- Run `/docs:quality-check` monthly
- Update `modified` dates when editing docs
- Review `reviewed` dates quarterly
- Use `/blueprint:adr` for new architecture decisions
- Use `/blueprint:prd` for new features
```

## Phase 9: Present Results

### 9.1 Executive Summary
Show a clear, concise summary:

```
📊 Documentation Quality Report
═══════════════════════════════

Overall Score: X/10 ([Excellent/Good/Fair/Poor/Critical])

✅ Strengths:
- [strength 1]
- [strength 2]

⚠️  Issues Found:
- [issue 1]
- [issue 2]

📋 Recommendations:
- [top recommendation 1]
- [top recommendation 2]

See full report below for details.
```

### 9.2 Full Report
Present the complete analysis with:
- Documentation inventory
- Quality scores by category
- Detailed findings
- Actionable recommendations
- Maintenance checklist

### 9.3 Guidance for Improvement

Help the user understand next steps:
- If Blueprint not initialized → suggest `/blueprint:init`
- If ADRs missing → suggest `/blueprint:adr`
- If PRDs missing → suggest `/blueprint:prd`
- If documentation outdated → provide update checklist
- If standards not followed → show examples and templates

## Best Practices

### For the Analysis
- Be thorough but concise
- Focus on actionable issues
- Provide specific file/line references
- Include examples of good vs bad patterns
- Suggest concrete fixes, not just problems

### For Documentation Standards
- **Frontmatter**: Always include created/modified/reviewed dates
- **Structure**: Follow established templates (ADR, PRD, PRP)
- **Clarity**: Write for future maintainers and AI assistants
- **Maintenance**: Review quarterly, update modified dates
- **Cross-reference**: Link related documentation
- **Examples**: Include code snippets and real examples
- **Scope**: Keep focused - one concern per document

## Error Handling

- If not a git repository → skip git-based freshness checks
- If directories don't exist → note in report as missing
- If files malformed → flag specific parsing errors
- If unable to read file → note permission/access issues
- If Blueprint not initialized → suggest initialization before creating docs

## Output Format

Use clear markdown formatting:
- Tables for structured data
- Checkboxes for action items
- Code blocks for examples
- Emoji indicators (✅ ❌ ⚠️) for quick scanning
- Collapsible sections for detailed analysis (if supported)

**Remember**: The goal is to help users maintain high-quality, current documentation that serves both human developers and AI assistants effectively.

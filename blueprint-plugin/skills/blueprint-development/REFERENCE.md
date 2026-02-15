# blueprint-development REFERENCE

Reference material for rule generation, command creation, and detailed implementation guidance for Blueprint Development.

## Extraction Patterns

### Architecture Pattern Extraction

Extract from PRD "Technical Considerations" or "Architecture" sections:

- Project structure and module organization
- Dependency injection patterns
- Error handling approaches
- Module boundaries and layering conventions
- Code organization and file naming conventions
- Integration patterns for external services/databases

### Testing Strategy Extraction

Extract from PRD "TDD Requirements" or "Success Criteria" sections:

- TDD workflow specification (RED → GREEN → REFACTOR)
- Test types to implement (unit, integration, e2e)
- Test structure and directory organization
- Mocking patterns and isolation strategies
- Coverage requirements and minimum percentages
- Test command and runners

### Quality Standard Extraction

Extract from PRD "Success Criteria", "Code Review", or "Quality" sections:

- Code review checklist items
- Performance baselines and targets
- Security requirements (OWASP, validation, authentication)
- Style and formatting standards
- Documentation requirements
- Dependency management policies

### Implementation Guide Extraction

Extract from PRD "Functional Requirements" and "Technical" sections:

- API endpoint design patterns
- UI component architecture (if applicable)
- Database operation patterns
- External service integration patterns
- Data flow and state management patterns

## Rule Templates

### Architecture Patterns Rule Template

```markdown
# Architecture Patterns

> Architecture patterns and code organization for [project name]. Defines how code is structured, organized, and modularized in this project.

## Project Structure

[Describe directory organization, module boundaries, layering. Include file tree example.]

## Design Patterns

[Document architectural patterns used: MVC, layered, hexagonal, etc. Include code examples.]

## Dependency Management

[How dependencies are injected, managed, and organized. Show injection pattern examples.]

## Error Handling

[Centralized error handling, error types, error propagation. Show error handling pattern examples.]

## Code Organization

[File naming conventions, module boundaries, separation of concerns. Show example directory structure.]

## Integration Patterns

[How external services, databases, APIs are integrated. Include integration examples.]
```

### Testing Strategies Rule Template

```markdown
# Testing Strategies

> TDD workflow, testing patterns, and coverage requirements for [project name]. Enforces test-first development and defines testing standards.

## TDD Workflow

Follow strict RED → GREEN → REFACTOR:
1. Write failing test describing desired behavior
2. Run test suite to confirm failure
3. Write minimal implementation to pass
4. Run test suite to confirm success
5. Refactor while keeping tests green

## Test Structure

[Directory organization, naming conventions, test types.]

## Test Types

### Unit Tests
[What to unit test, mocking patterns, isolation strategies. Include example test.]

### Integration Tests
[What to integration test, test database setup, external service handling. Include example test.]

### End-to-End Tests
[User flows to test, test environment setup, data seeding. Include example test if applicable.]

## Mocking Patterns

[When to mock, what to mock, mocking libraries and conventions. Include mocking examples.]

## Coverage Requirements

[Minimum coverage percentages, critical path requirements, edge case coverage.]

## Test Commands

[How to run tests, watch mode, coverage reports, debugging tests.]

**Project test commands:**
- Run all tests: [command]
- Watch mode: [command]
- Coverage report: [command]
- Debug specific test: [command]
```

### Quality Standards Rule Template

```markdown
# Quality Standards

> Code review criteria, performance baselines, security standards, and quality gates for [project name]. Enforces project quality requirements.

## Code Review Checklist

- [ ] All functions have tests (unit and/or integration)
- [ ] Input validation on all external inputs
- [ ] Error handling doesn't leak sensitive information
- [ ] No hardcoded credentials or secrets
- [ ] [Project-specific checklist items]

## Performance Baselines

[Specific performance targets from PRD]
- [Metric 1]: [Target]
- [Metric 2]: [Target]

## Security Standards

[Security requirements from PRD]
- [Security requirement 1]
- [Security requirement 2]

## Code Style

[Formatting, naming conventions, documentation standards. Include examples.]

## Documentation Requirements

[When and what to document.]

## Dependency Management

[Versioning, security updates, license compliance.]
```

### Implementation Guides Rule Template

```markdown
# Implementation Guides

> Step-by-step guides for implementing specific feature types in [project name]. Provides patterns for APIs, UI, data access, and integrations.

## API Endpoint Implementation

### Step 1: Write Integration Test
[Template for API test - write test first]

### Step 2: Create Route
[Route definition pattern for your framework]

### Step 3: Implement Controller
[Controller pattern with error handling and validation]

### Step 4: Implement Service Logic
[Service layer pattern with business logic]

### Step 5: Add Data Access
[Repository/data access pattern]

## [Feature Type 2] Implementation

[Step-by-step pattern specific to project]

## Database Operations

[Pattern for database queries, transactions, migrations]

## External Service Integration

[Pattern for integrating with third-party APIs/services]

## [Additional Patterns]

[Any other common implementation patterns in the project]
```

## Command Templates

### Blueprint Init Command

```markdown
---
description: "Initialize Blueprint Development in this project"
allowed-tools: Bash, Write
---

Initialize Blueprint Development structure:

1. Create `docs/blueprint/` directory
2. Create `docs/prds/` for requirements
3. Create `docs/adrs/` for architecture decisions
4. Create `docs/prps/` for proposed work
5. Create `docs/blueprint/manifest.json` with initial structure
6. Add `docs/blueprint/work-orders/` directory (for task tracking)
7. Add `docs/blueprint/work-orders/completed/` directory

Report:
- Directories created
- Next steps: Write PRDs, then run `/blueprint:generate-rules`
```

### Generate Rules Command

```markdown
---
description: "Generate project-specific behavioral rules from PRDs in docs/prds/"
allowed-tools: Read, Write, Glob
---

Generate project-specific rules:

1. Read all PRD files in `docs/prds/`
2. Analyze PRDs to extract:
   - Architecture patterns and decisions
   - Testing strategies and requirements
   - Implementation guides and patterns
   - Quality standards and baselines
3. Generate four behavioral rules in `.claude/rules/`:
   - `architecture-patterns.md`
   - `testing-strategies.md`
   - `implementation-guides.md`
   - `quality-standards.md`
4. Update manifest tracking in `docs/blueprint/manifest.json`

Report:
- Rules generated
- Key patterns extracted
- Next steps: Review rules, run `/project:continue` to start development
```

### Generate Commands Command

```markdown
---
description: "Generate workflow commands based on project structure and PRDs"
allowed-tools: Read, Write, Bash, Glob
---

Generate workflow commands:

1. Analyze project structure (package.json, Makefile, etc.)
2. Detect test runner and commands
3. Detect build and development commands
4. Generate workflow commands:
   - `/project:continue` - Resume development
   - `/project:test-loop` - Run TDD cycle
   - [Project-specific commands based on stack]

Report:
- Commands generated
- Detected commands and tools
- Next steps: Review rules, then use `/project:continue` to start work
```

### Work Order Command

```markdown
---
description: "Create work-order with minimal context for isolated subagent execution"
args: "[--no-publish] [--from-issue N]"
allowed-tools: Read, Write, Glob, Bash
---

Generate work-order:

1. Analyze current project state:
   - Read feature-tracker.json if exists
   - Check git status
   - Read relevant PRDs
2. Identify next logical work unit
3. Determine minimal required context:
   - Only files that need modification
   - Only relevant code excerpts
   - Only relevant PRD sections
4. Generate work-order document:
   - Sequential number (find highest + 1)
   - Clear objective
   - Minimal context
   - TDD requirements
   - Implementation steps
   - Success criteria
5. Save to `docs/blueprint/work-orders/NNN-task-name.md`
6. Create GitHub issue (unless --no-publish):
   - Title: "Work-Order NNN: [Task Name]"
   - Label: `work-order`
   - Body: Summary with link to local file
7. Update work-order with issue number

Report:
- Work-order created
- Work-order number and objective
- GitHub issue number (if created)
```

### Continue Development Command

```markdown
---
description: "Analyze project state and continue development where left off"
allowed-tools: Read, Bash, Grep, Glob, Edit, Write
---

Continue project development:

1. Check current state:
   - Run `git status` (branch, uncommitted changes)
   - Run `git log -5 --oneline` (recent commits)
2. Read context:
   - All PRDs in `docs/prds/`
   - `feature-tracker.json` (current phase, tasks, progress)
   - Recent work-orders (completed and pending)
3. Identify next task:
   - Based on PRD requirements
   - Based on feature tracker progress
   - Based on git status
4. Begin work following TDD:
   - Apply project-specific rules
   - Follow RED → GREEN → REFACTOR workflow
   - Commit incrementally

Report before starting:
- Current project status summary
- Next task identified
- Approach and plan
```

### Test Loop Command

```markdown
---
description: "Run test → fix → refactor loop with TDD workflow"
allowed-tools: Read, Edit, Bash
---

Run TDD cycle:

1. Run test suite: [project-specific test command]
2. If tests fail:
   - Analyze failure output
   - Identify root cause
   - Make minimal fix to pass test
   - Re-run tests to confirm
3. If tests pass:
   - Check for refactoring opportunities
   - Refactor while keeping tests green
   - Re-run tests to confirm still passing
4. Repeat until:
   - All tests pass
   - No obvious refactoring needed
   - User intervention required

Report:
- Test results summary
- Fixes applied
- Refactorings performed
- Current status (all pass / needs work / blocked)
```

## Rule Generation Guidelines

### Be Specific and Actionable

Use precise, actionable guidance with concrete references:

**Good**: "Use constructor injection for services, following the pattern in `services/authService.js:15-20`"

**Good**: "All API endpoints must have integration tests with valid input, invalid input, and authorization test cases"

### Include Code Examples

Every pattern should include a code example showing:
- What the pattern looks like in practice
- File location reference
- Line number reference (if applicable)

### Document Rationale

For architecture and technical decisions, include:
- Why this pattern was chosen
- What alternatives were considered
- What trade-offs were made
- When to deviate from the pattern

### Use Imperative Language

Rules should be behavioral guidelines that Claude follows:
- Use imperative language: "Use...", "Follow...", "Ensure..."
- Be specific about when the rule applies
- Include examples of correct behavior

### Keep Rules Focused

Each rule file should have a single concern:
- **Architecture patterns**: Structure and organization
- **Testing strategies**: How to test
- **Implementation guides**: How to implement features
- **Quality standards**: What defines quality

## Command Generation Guidelines

### Make Commands Autonomous

Commands should:
- Run without user input (except explicit prompts)
- Read necessary context automatically
- Report clearly what was done
- Suggest next steps

### Provide Clear Output

Commands should report:
1. What was analyzed
2. What was done
3. What the results are
4. What to do next

### Handle Errors Gracefully

Commands should detect common issues:
- Missing files or directories
- No PRDs found
- Invalid project structure
- Test command not found

Report errors clearly and suggest fixes.

## Manifest Structure

```json
{
  "format_version": "3.0.0",
  "updated_at": "ISO-8601-timestamp",
  "structure": {
    "has_prds": true,
    "has_adrs": true,
    "has_prps": true
  },
  "generated": {
    "rules": [
      "architecture-patterns.md",
      "testing-strategies.md",
      "quality-standards.md",
      "implementation-guides.md"
    ],
    "commands": [
      "blueprint-init.md",
      "blueprint-generate-rules.md",
      "blueprint-generate-commands.md",
      "blueprint-work-order.md",
      "project-continue.md",
      "project-test-loop.md"
    ]
  },
  "source_prds": ["project-overview.md"],
  "last_generated": "ISO-8601-timestamp"
}
```

## GitHub Work Order Integration

Work orders can be linked to GitHub issues for transparency and cooperative development.

### Why GitHub Integration?

| Benefit | Description |
|---------|-------------|
| **Transparency** | Team members see work in progress via GitHub issues |
| **Collaboration** | Comments, mentions, and discussions on issues |
| **Traceability** | Commits and PRs link to issues automatically |
| **Project management** | Issues integrate with GitHub Projects, milestones |

### Workflow Modes

**Default (GitHub-first)**:
```bash
/blueprint:work-order
# Creates local markdown + GitHub issue
# Issue has `work-order` label
# Work-order links to issue number
```

**Local-only (offline/private)**:
```bash
/blueprint:work-order --no-publish
# Creates local markdown only
# Can publish later manually
```

**From existing issue**:
```bash
/blueprint:work-order --from-issue 123
# Fetches issue #123
# Creates local work-order with context
# Updates issue with work-order link
```

### Label Setup

Create the `work-order` label in repositories using this methodology:
```bash
gh label create work-order --description "AI-assisted work order" --color "0E8A16"
```

### Completion Workflow

1. **Execute work-order** following TDD workflow
2. **Create PR** with `Fixes #N` in title/body (where N = issue number)
3. **Merge PR** - Issue auto-closes
4. **Move work-order** to `completed/` directory

### Work Order File Format

```markdown
# Work-Order 003: [Task Name]

**GitHub Issue**: #42
**Status**: pending | in-progress | completed

## Objective
[One sentence]

## Context
[Minimal context for isolated execution]

## TDD Requirements
[Specific tests]

## Success Criteria
[Checkboxes]
```

### When to Use Each Mode

| Scenario | Mode |
|----------|------|
| Team project, need visibility | Default (creates issue) |
| Solo exploration, quick prototype | `--no-publish` |
| Issue already exists from discussion | `--from-issue N` |
| Offline development | `--no-publish` |

## Testing Generated Rules and Commands

### 1. Verify Rules Are Applied

Test that Claude applies rules in relevant contexts:
- When discussing architecture, architecture-patterns rule should guide behavior
- When writing tests, testing-strategies rule should guide behavior
- When implementing features, implementation-guides rule should guide behavior
- When reviewing code, quality-standards rule should guide behavior

### 2. Verify Commands Work

Test each command:
```bash
/blueprint:init              # Should create directory structure
/blueprint:generate-rules    # Should create four rules in .claude/rules/
/blueprint:generate-commands # Should create workflow commands
/project:continue            # Should analyze state and resume work
/blueprint:work-order        # Should create work-order document
/project:test-loop           # Should run tests and report
```

### 3. Verify Rules Guide Correctly

Manually check that:
- Architecture patterns match PRD technical decisions
- Testing strategies match PRD TDD requirements
- Implementation guides match PRD API/feature designs
- Quality standards match PRD success criteria

### 4. Refine as Needed

During initial project development:
- Rules may need refinement as patterns emerge
- Commands may need adjustment based on actual workflow
- Update rules and commands iteratively

---
name: blueprint-development
description: "Generate project-specific skills and commands from PRDs for Blueprint Development methodology. Use when generating skills for architecture patterns, testing strategies, implementation guides, or quality standards from requirements documents."
---

# Blueprint Development Skill Generator

This skill teaches Claude how to generate project-specific skills and commands from Product Requirements Documents (PRDs) as part of the Blueprint Development methodology.

## When to Use This Skill

Activate this skill when:
- User runs `/blueprint:generate-skills` command
- User runs `/blueprint:generate-commands` command
- User asks to "generate skills from PRDs"
- User asks to "create project-specific skills"
- User initializes Blueprint Development in a project

## Skill Generation Process

### Step 1: Analyze PRDs

Read all PRD files in `.claude/blueprints/prds/` and extract:

**Architecture Patterns**:
- Project structure and organization
- Dependency injection patterns
- Error handling approaches
- Module boundaries and layering
- Code organization conventions

**Testing Strategies**:
- TDD workflow (RED → GREEN → REFACTOR)
- Test types (unit, integration, e2e)
- Mocking patterns
- Coverage requirements
- Test structure and organization

**Implementation Guides**:
- How to implement specific feature types (API endpoints, UI components, etc.)
- Step-by-step patterns for common tasks
- Integration with external services
- Data flow patterns

**Quality Standards**:
- Code review checklist items
- Performance baselines and targets
- Security requirements (OWASP, validation, etc.)
- Style and formatting standards

### Step 2: Generate Four Domain Skills

Create project-specific skills in `.claude/skills/`:

#### 1. Architecture Patterns Skill

**Location**: `.claude/skills/architecture-patterns/SKILL.md`

**Structure**:
```yaml
---
name: architecture-patterns
description: "Architecture patterns and code organization for [project name]. Defines how code is structured, organized, and modularized in this project."
---

# Architecture Patterns

## Project Structure
[Describe directory organization, module boundaries, layering]

## Design Patterns
[Document architectural patterns used: MVC, layered, hexagonal, etc.]

## Dependency Management
[How dependencies are injected, managed, and organized]

## Error Handling
[Centralized error handling, error types, error propagation]

## Code Organization
[File naming conventions, module boundaries, separation of concerns]

## Integration Patterns
[How external services, databases, APIs are integrated]
```

**Guidelines**:
- Extract architecture decisions from PRD "Technical Decisions" sections
- Include code examples showing the patterns
- Reference specific directories and file structures
- Document rationale for architectural choices

#### 2. Testing Strategies Skill

**Location**: `.claude/skills/testing-strategies/SKILL.md`

**Structure**:
```yaml
---
name: testing-strategies
description: "TDD workflow, testing patterns, and coverage requirements for [project name]. Enforces test-first development and defines testing standards."
---

# Testing Strategies

## TDD Workflow
Follow strict RED → GREEN → REFACTOR:
1. Write failing test describing desired behavior
2. Run test suite to confirm failure
3. Write minimal implementation to pass
4. Run test suite to confirm success
5. Refactor while keeping tests green

## Test Structure
[Directory organization, naming conventions, test types]

## Test Types
### Unit Tests
[What to unit test, mocking patterns, isolation strategies]

### Integration Tests
[What to integration test, test database setup, external service handling]

### End-to-End Tests
[User flows to test, test environment setup, data seeding]

## Mocking Patterns
[When to mock, what to mock, mocking libraries and conventions]

## Coverage Requirements
[Minimum coverage percentages, critical path requirements, edge case coverage]

## Test Commands
[How to run tests, watch mode, coverage reports, debugging tests]
```

**Guidelines**:
- Extract TDD requirements from PRD "TDD Requirements" sections
- Extract coverage requirements from "Success Criteria"
- Include specific test commands for the project
- Document mocking patterns for external dependencies

#### 3. Implementation Guides Skill

**Location**: `.claude/skills/implementation-guides/SKILL.md`

**Structure**:
```yaml
---
name: implementation-guides
description: "Step-by-step guides for implementing specific feature types in [project name]. Provides patterns for APIs, UI, data access, and integrations."
---

# Implementation Guides

## API Endpoint Implementation
### Step 1: Write Integration Test
[Template for API test]

### Step 2: Create Route
[Route definition pattern]

### Step 3: Implement Controller
[Controller pattern with error handling]

### Step 4: Implement Service Logic
[Service layer pattern with business logic]

### Step 5: Add Data Access
[Repository/data access pattern]

## UI Component Implementation
[Pattern for UI components if relevant]

## Database Operations
[Pattern for database queries, transactions, migrations]

## External Service Integration
[Pattern for integrating with third-party APIs/services]

## Background Jobs
[Pattern for async jobs, queues, scheduled tasks if relevant]
```

**Guidelines**:
- Extract implementation patterns from PRD "API Design", "Data Model" sections
- Provide step-by-step TDD workflow for each feature type
- Include code examples showing the pattern
- Reference project-specific libraries and frameworks

#### 4. Quality Standards Skill

**Location**: `.claude/skills/quality-standards/SKILL.md`

**Structure**:
```yaml
---
name: quality-standards
description: "Code review criteria, performance baselines, security standards, and quality gates for [project name]. Enforces project quality requirements."
---

# Quality Standards

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
[Formatting, naming conventions, documentation standards]

## Documentation Requirements
[When and what to document]

## Dependency Management
[Versioning, security updates, license compliance]
```

**Guidelines**:
- Extract performance baselines from PRD "Performance Baselines"
- Extract security requirements from PRD "Security Compliance"
- Extract quality criteria from PRD "Success Criteria"
- Create specific, actionable checklist items

### Step 3: Add Supporting Documentation

For each skill, create a `reference.md` file with additional details:

**Location**: `.claude/skills/[skill-name]/reference.md`

**Content**:
- Detailed explanations of patterns
- Code examples (larger snippets)
- Common pitfalls and how to avoid them
- Links to external documentation
- Historical context and evolution of patterns

### Step 4: Create Skill Templates

Create reusable templates in `.claude/skills/blueprint-development/templates/`:

**Templates**:
- `architecture-skill-template.md` - Template for architecture skills
- `testing-skill-template.md` - Template for testing skills
- `implementation-skill-template.md` - Template for implementation skills
- `quality-skill-template.md` - Template for quality skills

These templates can be used to quickly generate skills for new projects.

## Command Generation Process

### Step 1: Analyze Project Structure

Determine:
- Project type (web app, CLI, library, etc.)
- Programming language and framework
- Test runner and commands
- Build and development commands
- Git workflow conventions

### Step 2: Generate Workflow Commands

Create commands in `.claude/commands/`:

#### 1. `/blueprint:init` Command

**Location**: `.claude/commands/blueprint-init.md`

**Purpose**: Initialize Blueprint Development structure in a project

**Generated Content**:
```markdown
---
description: "Initialize Blueprint Development in this project"
allowed_tools: [Bash, Write]
---

Initialize Blueprint Development structure:

1. Create `.claude/blueprints/` directory
2. Create `.claude/blueprints/prds/` for requirements
3. Create `.claude/blueprints/work-orders/` for task packages
4. Create `.claude/blueprints/work-orders/completed/` for completed work-orders
5. Create placeholder `work-overview.md`
6. Add `.claude/` to `.gitignore` (optional - ask user)

Report:
- Directories created
- Next steps: Write PRDs, then run `/blueprint:generate-skills`
```

#### 2. `/blueprint:generate-skills` Command

**Location**: `.claude/commands/blueprint-generate-skills.md`

**Purpose**: Generate project-specific skills from PRDs

**Generated Content**:
```markdown
---
description: "Generate project-specific skills from PRDs in .claude/blueprints/prds/"
allowed_tools: [Read, Write, Glob]
---

Generate project-specific skills:

1. Read all PRD files in `.claude/blueprints/prds/`
2. Analyze PRDs to extract:
   - Architecture patterns and decisions
   - Testing strategies and requirements
   - Implementation guides and patterns
   - Quality standards and baselines
3. Generate four domain skills:
   - `.claude/skills/architecture-patterns/`
   - `.claude/skills/testing-strategies/`
   - `.claude/skills/implementation-guides/`
   - `.claude/skills/quality-standards/`
4. Each skill includes:
   - SKILL.md with frontmatter and instructions
   - reference.md with detailed documentation
   - Code examples and patterns

Report:
- Skills generated
- Key patterns extracted
- Next steps: Review skills, run `/project:continue` to start development
```

#### 3. `/blueprint:generate-commands` Command

**Location**: `.claude/commands/blueprint-generate-commands.md`

**Purpose**: Generate workflow commands from project structure

**Generated Content**:
```markdown
---
description: "Generate workflow commands based on project structure and PRDs"
allowed_tools: [Read, Write, Bash, Glob]
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
- Next steps: Use `/project:continue` to start work
```

#### 4. `/blueprint:work-order` Command

**Location**: `.claude/commands/blueprint-work-order.md`

**Purpose**: Generate isolated work-order for subagent execution

**Generated Content**:
```markdown
---
description: "Create work-order with minimal context for isolated subagent execution"
allowed_tools: [Read, Write, Glob, Bash]
---

Generate work-order:

1. Analyze current project state:
   - Read work-overview.md
   - Check git status
   - Read relevant PRDs
2. Identify next logical work unit
3. Determine minimal required context:
   - Only files that need to be created/modified
   - Only relevant code excerpts (not full files)
   - Only relevant PRD sections
4. Generate work-order document:
   - Sequential number (find highest existing + 1)
   - Clear objective
   - Minimal context
   - TDD requirements (tests specified)
   - Implementation steps
   - Success criteria
5. Save to `.claude/blueprints/work-orders/NNN-task-name.md`

Report:
- Work-order created
- Work-order number and objective
- Ready for subagent execution
```

#### 5. `/project:continue` Command

**Location**: `.claude/commands/project-continue.md`

**Purpose**: Analyze state and resume development

**Generated Content**:
```markdown
---
description: "Analyze project state and continue development where left off"
allowed_tools: [Read, Bash, Grep, Glob, Edit, Write]
---

Continue project development:

1. Check current state:
   - Run `git status` (branch, uncommitted changes)
   - Run `git log -5 --oneline` (recent commits)
2. Read context:
   - All PRDs in `.claude/blueprints/prds/`
   - `work-overview.md` (current phase and progress)
   - Recent work-orders (completed and pending)
3. Identify next task:
   - Based on PRD requirements
   - Based on work-overview progress
   - Based on git status (resume if in progress)
4. Begin work following TDD:
   - Apply project-specific skills (architecture, testing, implementation, quality)
   - Follow RED → GREEN → REFACTOR workflow
   - Commit incrementally

Report before starting:
- Current project status summary
- Next task identified
- Approach and plan
```

#### 6. `/project:test-loop` Command

**Location**: `.claude/commands/project-test-loop.md`

**Purpose**: Run automated TDD cycle

**Generated Content**:
```markdown
---
description: "Run test → fix → refactor loop with TDD workflow"
allowed_tools: [Read, Edit, Bash]
---

Run TDD cycle:

1. Run test suite: [project-specific test command]
2. If tests fail:
   - Analyze failure output
   - Identify root cause
   - Make minimal fix to pass the test
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

### Step 3: Customize Commands for Project

Adapt command templates based on:
- **Programming language**: Adjust test commands, build commands
- **Framework**: Include framework-specific patterns
- **Project type**: CLI, web app, library have different workflows
- **Team conventions**: Match existing git workflow, commit conventions

## Skill Generation Guidelines

### Extract, Don't Invent

**DO**: Extract patterns, decisions, and requirements from PRDs
**DON'T**: Invent patterns not specified in PRDs

If PRDs don't specify a pattern, ask user or use sensible defaults.

### Be Specific, Not Generic

**DON'T**: "Write good code"
**DO**: "Use constructor injection for services, following the pattern in `services/authService.js:15-20`"

**DON'T**: "Test your code"
**DO**: "All API endpoints must have integration tests with valid input, invalid input, and authorization test cases"

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

### Make Skills Discoverable

Skill `description` field is critical for Claude's discovery:
- Be specific about when the skill applies
- Include key terms Claude should match on
- Mention the project or domain

**Good description**: "Testing strategies for Express.js API project. Defines TDD workflow, mocking patterns for passport.js auth, and coverage requirements."

**Bad description**: "Testing stuff"

### Keep Skills Focused

Each skill should have a single concern:
- **Architecture patterns**: Structure and organization
- **Testing strategies**: How to test
- **Implementation guides**: How to implement features
- **Quality standards**: What defines quality

Don't mix concerns across skills.

## Command Generation Guidelines

### Make Commands Autonomous

Commands should:
- Run without user input (except explicit prompts)
- Read necessary context automatically
- Report clearly what was done
- Suggest next steps

### Use Appropriate Tools

Specify `allowed_tools` in command frontmatter:
- `/blueprint:init`: [Bash, Write]
- `/blueprint:generate-skills`: [Read, Write, Glob]
- `/project:continue`: [Read, Bash, Grep, Glob, Edit, Write]
- `/project:test-loop`: [Read, Edit, Bash]

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

## Testing Generated Skills and Commands

After generating skills and commands:

### 1. Verify Skills Are Discoverable

Test that Claude discovers skills in relevant contexts:
- Mention "architecture" → architecture-patterns skill should activate
- Mention "testing" or "TDD" → testing-strategies skill should activate
- Mention "implement API" → implementation-guides skill should activate
- Mention "code review" → quality-standards skill should activate

### 2. Verify Commands Work

Test each command:
```bash
/blueprint:init              # Should create directory structure
/blueprint:generate-skills   # Should create four skills
/blueprint:generate-commands # Should create workflow commands
/project:continue            # Should analyze state and resume work
/blueprint:work-order        # Should create work-order document
/project:test-loop           # Should run tests and report
```

### 3. Verify Skills Guide Correctly

Manually check that:
- Architecture patterns match PRD technical decisions
- Testing strategies match PRD TDD requirements
- Implementation guides match PRD API/feature designs
- Quality standards match PRD success criteria

### 4. Refine as Needed

During initial project development:
- Skills may need refinement as patterns emerge
- Commands may need adjustment based on actual workflow
- Update skills and commands iteratively

## Examples

See `.claude/skills/blueprint-development/templates/` for complete skill templates.

See `.claude/docs/blueprint-development/` for complete workflow documentation and examples.

## Integration with Blueprint Development

This skill enables the core Blueprint Development workflow:

**PRDs** (requirements) → **Skills** (how to build) → **Commands** (workflow automation) → **Work-orders** (isolated tasks)

By generating project-specific skills and commands from PRDs, Blueprint Development creates a self-documenting, AI-native development environment where process, patterns, and quality standards are first-class citizens.

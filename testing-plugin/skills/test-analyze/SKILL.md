---
description: "Analyze test results and create a fix plan with subagent delegation. Use when triaging failing tests, analyzing JUnit XML or test-results dirs, planning fixes for accessibility/security findings, or categorizing flaky/perf/E2E failures."
args: "<results-path> [--type <test-type>] [--focus <area>]"
argument-hint: "Path to test results (e.g., ./test-results/), optional --type and --focus filters"
allowed-tools: Task, Read, Glob, Grep, TodoWrite
created: 2025-12-16
modified: 2026-05-09
reviewed: 2026-04-25
name: test-analyze
agent: general-purpose
---

# Test Analysis and Fix Planning

Analyzes test results from any testing framework, uses Zen planner to create a systematic fix strategy, and delegates fixes to appropriate subagents.

## When to Use This Skill

| Use this skill when... | Use test-report instead when... |
|---|---|
| Triaging a directory of failing-test results into a fix plan | You only need a quick cached status read |
| Categorizing flaky, performance, accessibility, or security failures | Running the tests in the first place (use test-run) |
| Delegating fixes to specialized subagents | Asking strategic "how should we test X?" questions (use test-consult) |
| Producing a structured plan from JUnit XML or coverage output | Iterating on a single failing spec (use test-focus) |

## Usage

```bash
/test:analyze <results-path> [--type <test-type>] [--focus <area>]
```

## Parameters

- `<results-path>`: Path to test results directory or file (required)
  - Examples: `./test-results/`, `./coverage/`, `pytest-report.xml`

- `--type <test-type>`: Type of tests (optional, auto-detected if omitted)
  - `accessibility` - Playwright a11y, axe-core
  - `unit` - Jest, pytest, cargo test
  - `integration` - API tests, database tests
  - `e2e` - Playwright, Cypress, Selenium
  - `security` - OWASP ZAP, Snyk, TruffleHog
  - `performance` - Lighthouse, k6, JMeter

- `--focus <area>`: Specific area to focus on (optional)
  - Examples: `authentication`, `api`, `ui-components`, `database`

## Examples

```bash
# Analyze Playwright accessibility test results
/test:analyze ./test-results/ --type accessibility

# Analyze unit test failures with focus on auth
/test:analyze ./coverage/junit.xml --type unit --focus authentication

# Auto-detect test type and analyze all issues
/test:analyze ./test-output/

# Analyze security scan results
/test:analyze ./security-report.json --type security
```

## Command Flow

1. **Analyze Test Results**
   - Parse test result files (XML, JSON, HTML, text)
   - Extract failures, errors, warnings
   - Categorize issues by type and severity
   - Identify patterns and root causes

2. **Plan Fixes with PAL Planner**
   - Use `mcp__pal__planner` for systematic planning
   - Break down complex fixes into actionable steps
   - Identify dependencies between fixes
   - Estimate effort and priority

3. **Delegate to Subagents**
   - **Accessibility issues** → `code-review` agent (WCAG compliance)
   - **Security vulnerabilities** → `security-audit` agent
   - **Performance problems** → `system-debugging` agent
   - **Code quality issues** → `code-refactoring` agent
   - **Test infrastructure** → `test-architecture` agent
   - **Integration failures** → `system-debugging` agent
   - **Documentation gaps** → `documentation` agent

4. **Execute Plan**
   - Sequential execution based on dependencies
   - Verification after each fix
   - Re-run tests to confirm resolution

## Subagent Selection Logic

The command uses this decision tree to delegate:

- **Accessibility violations** (WCAG, ARIA, contrast)
  → `code-review` agent with accessibility focus

- **Security issues** (XSS, SQLi, auth bypass)
  → `security-audit` agent with OWASP analysis

- **Performance bottlenecks** (slow queries, memory leaks)
  → `system-debugging` agent with profiling

- **Code smells** (duplicates, complexity, coupling)
  → `code-refactoring` agent with SOLID principles

- **Flaky tests** (race conditions, timing issues)
  → `test-architecture` agent with stability analysis

- **Build/CI failures** (pipeline errors, dependency issues)
  → `cicd-pipelines` agent with workflow optimization

## Output

The command produces:

1. **Summary Report**
   - Total issues found
   - Breakdown by category/severity
   - Top priorities

2. **Fix Plan** (from PAL planner)
   - Step-by-step remediation strategy
   - Dependency graph
   - Effort estimates

3. **Subagent Assignments**
   - Which agent handles which issues
   - Rationale for delegation
   - Execution order

4. **Actionable Next Steps**
   - Commands to run
   - Files to modify
   - Verification steps

## Notes

- Works with any test framework that produces structured output
- Auto-detects common test result formats (JUnit XML, JSON, TAP)
- Preserves test evidence for debugging
- Can be chained with `/git:smartcommit` for automated fixes
- Respects TDD workflow (RED → GREEN → REFACTOR)

## Related Commands

- `/test:run` - Run tests with framework detection
- `/code:review` - Manual code review for test files
- `/docs:update` - Update test documentation
- `/git:smartcommit` - Commit fixes with conventional messages

---

**Prompt:**

Analyze test results from {{ARG1}} and create a systematic fix plan.

{{#if ARG2}}
Test type: {{ARG2}}
{{else}}
Auto-detect test type from file formats and content.
{{/if}}

{{#if ARG3}}
Focus area: {{ARG3}}
{{/if}}

**Step 1: Analyze Test Results**

Read the test result files from {{ARG1}} and extract:
- Failed tests with error messages
- Warnings and deprecations
- Performance metrics (if available)
- Coverage gaps (if available)
- Categorize by: severity (critical/high/medium/low), type (functional/security/performance/accessibility)

**Step 2: Use PAL Planner**

Call `mcp__pal__planner` with model "gemini-2.5-pro" to create a systematic fix plan:
- Step 1: Summarize findings and identify root causes
- Step 2: Prioritize issues (impact × effort matrix)
- Step 3: Break down fixes into actionable tasks
- Step 4: Identify dependencies between fixes
- Step 5: Assign each fix category to appropriate subagent
- Continue planning steps as needed for complex scenarios

**Step 3: Subagent Delegation Strategy**

Based on the issue categories, delegate to:

- **Accessibility violations** (WCAG, ARIA, color contrast, keyboard nav)
  → Use `Task` tool with `subagent_type: code-review`
  → Focus: WCAG 2.1 compliance, semantic HTML, ARIA best practices

- **Security vulnerabilities** (XSS, SQLi, CSRF, auth issues)
  → Use `Task` tool with `subagent_type: security-audit`
  → Focus: OWASP Top 10, input validation, authentication

- **Performance issues** (slow tests, memory leaks, timeouts)
  → Use `Task` tool with `subagent_type: system-debugging`
  → Focus: Profiling, bottleneck identification, optimization

- **Code quality** (duplicates, complexity, maintainability)
  → Use `Task` tool with `subagent_type: code-refactoring`
  → Focus: SOLID principles, DRY, code smells

- **Flaky/unreliable tests** (race conditions, timing, dependencies)
  → Use `Task` tool with `subagent_type: test-architecture`
  → Focus: Test stability, isolation, determinism

- **CI/CD failures** (build errors, pipeline issues)
  → Use `Task` tool with `subagent_type: cicd-pipelines`
  → Focus: GitHub Actions, dependency management, caching

- **Documentation gaps** (missing docs, outdated examples)
  → Use `Task` tool with `subagent_type: documentation`
  → Focus: API docs, test documentation, migration guides

**Step 4: Create Execution Plan**

For each subagent assignment:
1. **Context**: What files/areas need attention
2. **Objective**: Specific fix goal
3. **Success Criteria**: How to verify the fix
4. **Dependencies**: What must be done first
5. **Verification**: Commands to re-run tests

**Step 5: Present Summary**

Provide:
- 📊 **Issue Breakdown**: Count by category and severity
- 🎯 **Priorities**: Top 3-5 issues to fix first
- 🤖 **Subagent Plan**: Which agents will handle what
- ✅ **Next Steps**: Concrete actions to take
- 🔍 **Verification**: How to confirm fixes worked

{{#if ARG3}}
**Additional focus on {{ARG3}}**: Prioritize issues related to this area and provide extra context for relevant subagents.
{{/if}}

**Documentation-First Reminder**: Before implementing fixes, research relevant documentation using context7 to verify:
- Test framework best practices
- Accessibility standards (WCAG 2.1)
- Security patterns (OWASP)
- Performance optimization techniques

**TDD Workflow**: Follow RED → GREEN → REFACTOR:
1. Verify tests fail (RED) ✓ (already done)
2. Implement minimal fix (GREEN)
3. Refactor for quality
4. Re-run tests to confirm

Do you want me to proceed with the analysis and planning, or would you like to review the plan first?

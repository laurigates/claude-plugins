---
description: "Analyze test results and create a fix plan with subagents. Use when triaging failing tests, analyzing JUnit XML, planning fixes for accessibility/security, or categorizing flaky/E2E failures."
args: "<results-path> [--type <test-type>] [--focus <area>]"
argument-hint: "Path to test results (e.g., ./test-results/), optional --type and --focus filters"
allowed-tools: Task, Read, Glob, Grep, TodoWrite
created: 2025-12-16
modified: 2026-07-28
reviewed: 2026-07-28
name: test-analyze
agent: general-purpose
context: fork
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
   - Route each issue category through the [Subagent Routing](#subagent-routing) table below — it is the single source of truth for every `subagent_type` this skill dispatches.

4. **Execute Plan**
   - Sequential execution based on dependencies
   - Verification after each fix
   - Re-run tests to confirm resolution

## Subagent Routing

**This table is the single source of truth for delegation.** Every `subagent_type` this skill dispatches is listed here; no other section restates it. The values are plugin-qualified `plugin:agent` IDs — the form the `Task`/`Agent` tool resolves for plugin-provided agents (a bare name only resolves for user- or project-level agents in `~/.claude/agents/` or `.claude/agents/`).

| Issue category | Triggers | Dispatch | Focus to pass |
|---|---|---|---|
| Accessibility violations | WCAG, ARIA, colour contrast, keyboard nav | `subagent_type: agents-plugin:review` | WCAG 2.1 compliance, semantic HTML, ARIA best practices |
| Security vulnerabilities | XSS, SQLi, CSRF, auth bypass | `subagent_type: agents-plugin:security-audit` | OWASP Top 10, input validation, authentication |
| Performance issues | Slow tests/queries, memory leaks, timeouts | `subagent_type: agents-plugin:performance` | Profiling, bottleneck identification, optimization |
| Code quality / smells | Duplication, complexity, coupling, maintainability | `subagent_type: agents-plugin:refactor` | SOLID principles, DRY, behaviour-preserving restructure |
| Flaky tests / test infrastructure | Race conditions, timing, shared state, isolation | `subagent_type: agents-plugin:test` | Test stability, isolation, determinism |
| Integration failures | Failing behaviour needing root-cause diagnosis | `subagent_type: agents-plugin:debug` | Root cause, minimal fix, verification |
| Build / CI failures | Pipeline errors, dependency issues | `subagent_type: agents-plugin:ci` | GitHub Actions, dependency management, caching |
| Documentation gaps | Missing docs, outdated examples | `subagent_type: agents-plugin:docs` | API docs, test documentation, migration guides |

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

For each issue category found, look it up in the **Subagent Routing** table above and dispatch a `Task` with that row's `subagent_type` (a plugin-qualified `plugin:agent` ID) and that row's focus. Do not invent a `subagent_type` that is absent from the table — an unlisted value does not resolve and the dispatch fails.

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

# Test Analysis — Examples, Command Flow, and Output

Supporting detail for [SKILL.md](../SKILL.md). The **Prompt** section of SKILL.md is the authoritative procedure; this file carries invocation examples, an overview of the flow, and the shape of the deliverable.

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
   - Use `mcp__pal-mcp-server__planner` for systematic planning
   - Break down complex fixes into actionable steps
   - Identify dependencies between fixes
   - Estimate effort and priority

3. **Delegate to Subagents**
   - Route each issue category through the [Subagent Routing](../SKILL.md#subagent-routing) table in SKILL.md — it is the single source of truth for every `subagent_type` this skill dispatches.

4. **Execute Plan**
   - Sequential execution based on dependencies
   - Verification after each fix
   - Re-run tests to confirm resolution

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
- Can be chained with `/git:commit` for automated fixes
- Respects TDD workflow (RED → GREEN → REFACTOR)

## Related Commands

- `/test:run` - Run tests with framework detection
- `/code:review` - Manual code review for test files
- `/docs:generate` - Update test documentation
- `/git:commit` - Commit fixes with conventional messages

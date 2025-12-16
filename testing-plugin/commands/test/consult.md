---
allowed-tools: Task, Read, Glob, Grep
argument-hint: "<topic> [--context <path>]"
description: Consult test-architecture agent for testing strategy and design
---

## Context

Explicit command to consult the `test-architecture` agent for strategic testing decisions.

**Use when:**
- Creating tests for NEW features
- Test strategy needs adjustment
- Coverage gaps identified
- Flaky tests detected
- Framework selection questions

## Topics

| Topic | What it covers |
|-------|----------------|
| `coverage` | Analyze gaps, recommend high-value tests to write |
| `strategy` | Review overall test architecture and pyramid |
| `framework` | Recommend testing tools for tech stack |
| `flaky` | Diagnose and remediate flaky tests |
| `pyramid` | Analyze test tier distribution |
| `new-feature` | Design test approach for new functionality |
| (free text) | Custom question about testing |

## Parameters

- `$1`: Topic keyword or natural language question
- `--context <path>`: Focus analysis on specific directory

## Behavior

1. **Gather Project Context**:
   - Find test directories and structure
   - Detect frameworks in use (pytest, vitest, playwright, etc.)
   - Read coverage reports if available
   - Check recent test failures

2. **Delegate to test-architecture Agent**:
   - Provide gathered context
   - Include specified topic
   - Request actionable recommendations

3. **Present Recommendations**:
   - Strategic advice
   - Specific action items
   - Offer to create issues/tasks

## Examples

```bash
# Coverage analysis
/test:consult coverage

# New feature testing strategy
/test:consult new-feature --context src/auth/

# Framework decision
/test:consult "Should we add property-based testing?"

# Flaky test investigation
/test:consult flaky

# Custom question
/test:consult "How should we structure tests for our API endpoints?"
```

## Agent Delegation

This command delegates to the `test-architecture` agent with:
- Project test structure analysis
- Coverage data (if available)
- Specified topic/question
- Context path (if provided)

The agent will provide:
- Strategic recommendations
- Specific actionable items
- Trade-off analysis
- Implementation guidance

---
name: confidence-scoring
description: "Assess quality of PRPs and work-orders using systematic confidence scoring. Use when evaluating readiness for execution or subagent delegation."
---

# Confidence Scoring for PRPs and Work-Orders

This skill provides systematic evaluation of PRPs (Product Requirement Prompts) and work-orders to determine their readiness for execution or delegation.

## When to Use This Skill

Activate this skill when:
- Creating a new PRP (`/prp:create`)
- Generating a work-order (`/blueprint:work-order`)
- Deciding whether to execute or refine a PRP
- Evaluating whether a task is ready for subagent delegation
- Reviewing PRPs/work-orders for quality

## Scoring Dimensions

### 1. Context Completeness (1-10)

Evaluates whether all necessary context is explicitly provided.

| Score | Criteria |
|-------|----------|
| **10** | All file paths explicit with line numbers, all code snippets included, library versions specified, integration points documented |
| **8-9** | Most context provided, minor gaps that can be inferred from codebase |
| **6-7** | Key context present but some discovery required |
| **4-5** | Significant context missing, will need exploration |
| **1-3** | Minimal context, extensive discovery needed |

**Checklist**:
- [ ] File paths are absolute or clearly relative to project root
- [ ] Code snippets include actual line numbers (e.g., `src/auth.py:45-60`)
- [ ] Library versions are specified
- [ ] Integration points are documented
- [ ] Patterns from codebase are shown with examples

### 2. Implementation Clarity (1-10)

Evaluates how clear the implementation approach is.

| Score | Criteria |
|-------|----------|
| **10** | Pseudocode covers all cases, step-by-step clear, edge cases addressed |
| **8-9** | Main path clear, most edge cases covered |
| **6-7** | Implementation approach clear, some details need discovery |
| **4-5** | High-level only, significant ambiguity |
| **1-3** | Vague requirements, unclear approach |

**Checklist**:
- [ ] Task breakdown is explicit
- [ ] Pseudocode is provided for complex logic
- [ ] Implementation order is specified
- [ ] Edge cases are identified
- [ ] Error handling approach is documented

### 3. Gotchas Documented (1-10)

Evaluates whether known pitfalls are documented with mitigations.

| Score | Criteria |
|-------|----------|
| **10** | All known pitfalls documented, each has mitigation, library-specific issues covered |
| **8-9** | Major gotchas covered, mitigations clear |
| **6-7** | Some gotchas documented, may discover more |
| **4-5** | Few gotchas mentioned, incomplete coverage |
| **1-3** | No gotchas documented |

**Checklist**:
- [ ] Library-specific gotchas documented
- [ ] Version-specific behaviors noted
- [ ] Common mistakes identified
- [ ] Each gotcha has a mitigation
- [ ] Race conditions/concurrency issues addressed

### 4. Validation Coverage (1-10)

Evaluates whether executable validation commands are provided.

| Score | Criteria |
|-------|----------|
| **10** | All quality gates have executable commands, expected outcomes specified |
| **8-9** | Main validation commands present, most outcomes specified |
| **6-7** | Some validation commands, gaps in coverage |
| **4-5** | Minimal validation commands |
| **1-3** | No executable validation |

**Checklist**:
- [ ] Linting command provided and executable
- [ ] Type checking command provided (if applicable)
- [ ] Unit test command with specific test files
- [ ] Integration test command (if applicable)
- [ ] Coverage check command with threshold
- [ ] Security scan command (if applicable)
- [ ] All commands include expected outcomes

### 5. Test Coverage (1-10) - Work-Orders Only

Evaluates whether test cases are specified.

| Score | Criteria |
|-------|----------|
| **10** | All test cases specified with assertions, edge cases covered |
| **8-9** | Main test cases specified, most assertions included |
| **6-7** | Key test cases present, some gaps |
| **4-5** | Few test cases, minimal detail |
| **1-3** | No test cases specified |

**Checklist**:
- [ ] Each test case has code template
- [ ] Assertions are explicit
- [ ] Happy path tested
- [ ] Error cases tested
- [ ] Edge cases tested

## Calculating Overall Score

### For PRPs
```
Overall = (Context + Implementation + Gotchas + Validation) / 4
```

### For Work-Orders
```
Overall = (Context + Gotchas + TestCoverage + Validation) / 4
```

## Score Thresholds

| Score | Readiness | Recommendation |
|-------|-----------|----------------|
| **9-10** | Excellent | Ready for autonomous subagent execution |
| **7-8** | Good | Ready for execution with some discovery |
| **5-6** | Fair | Needs refinement before execution |
| **3-4** | Poor | Significant gaps, recommend research phase |
| **1-2** | Inadequate | Restart with proper research |

## Response Templates

### High Confidence (7+)

```markdown
## Confidence Score: X.X/10

| Dimension | Score | Notes |
|-----------|-------|-------|
| Context Completeness | X/10 | [specific observation] |
| Implementation Clarity | X/10 | [specific observation] |
| Gotchas Documented | X/10 | [specific observation] |
| Validation Coverage | X/10 | [specific observation] |
| **Overall** | **X.X/10** | |

**Assessment:** Ready for execution

**Strengths:**
- [Key strength 1]
- [Key strength 2]

**Recommendations (optional):**
- [Minor improvement 1]
```

### Low Confidence (<7)

```markdown
## Confidence Score: X.X/10

| Dimension | Score | Notes |
|-----------|-------|-------|
| Context Completeness | X/10 | [specific gap] |
| Implementation Clarity | X/10 | [specific gap] |
| Gotchas Documented | X/10 | [specific gap] |
| Validation Coverage | X/10 | [specific gap] |
| **Overall** | **X.X/10** | |

**Assessment:** Needs refinement before execution

**Gaps to Address:**
- [ ] [Gap 1 with suggested action]
- [ ] [Gap 2 with suggested action]
- [ ] [Gap 3 with suggested action]

**Next Steps:**
1. [Specific research action]
2. [Specific documentation action]
3. [Specific validation action]
```

## Examples

### Example 1: Well-Prepared PRP

```markdown
## Confidence Score: 8.5/10

| Dimension | Score | Notes |
|-----------|-------|-------|
| Context Completeness | 9/10 | All files explicit, code snippets with line refs |
| Implementation Clarity | 8/10 | Pseudocode covers main path, one edge case unclear |
| Gotchas Documented | 8/10 | Redis connection pool, JWT format issues covered |
| Validation Coverage | 9/10 | All gates have commands, outcomes specified |
| **Overall** | **8.5/10** | |

**Assessment:** Ready for execution

**Strengths:**
- Comprehensive codebase intelligence with actual code snippets
- Validation gates are copy-pasteable
- Known library gotchas well-documented

**Recommendations:**
- Consider documenting concurrent token refresh edge case
```

### Example 2: Needs Work

```markdown
## Confidence Score: 5.0/10

| Dimension | Score | Notes |
|-----------|-------|-------|
| Context Completeness | 4/10 | File paths vague ("somewhere in auth/") |
| Implementation Clarity | 6/10 | High-level approach clear, no pseudocode |
| Gotchas Documented | 3/10 | No library-specific gotchas |
| Validation Coverage | 7/10 | Test command present, missing lint/type check |
| **Overall** | **5.0/10** | |

**Assessment:** Needs refinement before execution

**Gaps to Address:**
- [ ] Add explicit file paths (use `grep` to find them)
- [ ] Add pseudocode for token generation logic
- [ ] Research jsonwebtoken gotchas (check GitHub issues)
- [ ] Add linting and type checking commands

**Next Steps:**
1. Run `/prp:curate-docs jsonwebtoken` to create ai_docs entry
2. Use Explore agent to find exact file locations
3. Add validation gate commands from project's package.json
```

## Integration with Blueprint Development

This skill is automatically applied when:
- `/prp:create` generates a new PRP
- `/blueprint:work-order` generates a work-order
- Reviewing existing PRPs for execution readiness

The confidence score determines:
- **9+**: Proceed with subagent delegation
- **7-8**: Proceed with direct execution
- **< 7**: Refine before execution

## Tips for Improving Scores

### Context Completeness
- Use `grep` to find exact file locations
- Include actual line numbers in code snippets
- Reference ai_docs entries for library patterns

### Implementation Clarity
- Write pseudocode before describing approach
- Enumerate edge cases explicitly
- Define error handling strategy

### Gotchas Documented
- Search GitHub issues for library gotchas
- Check Stack Overflow for common problems
- Document team experience from past projects

### Validation Coverage
- Copy commands from project's config (package.json, pyproject.toml)
- Include specific file paths in test commands
- Specify expected outcomes for each gate

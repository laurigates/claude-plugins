# blueprint-prp-create REFERENCE

Reference material for PRP document structure, section templates, task categorization, and quality checklists.

## PRP Structure

```markdown
---
id: PRP-NNN
created: YYYY-MM-DD
modified: YYYY-MM-DD
status: Draft | Ready | Executed
implements: [PRD-NNN] or []
relates-to: [ADR-NNNN] or []
github-issues: []
confidence: X/10
---

# Feature Name

## Goal & Why

[One sentence goal]

### Problem Statement
[Business justification for this feature]

### Target Users
[Who will use this feature]

### Priority
[P0/P1/P2 - impact and urgency]

## Success Criteria

- [ ] Criterion 1: [Specific, testable condition]
- [ ] Criterion 2: [Specific, testable condition]
- [ ] Criterion 3: [Performance baseline with metric]
- [ ] Criterion 4: [Security requirement]

## Context

### Documentation References
- [Library Name](https://docs.example.com/section) - Specific section explaining [what]
- [Framework Name](https://docs.example.com/api) - API endpoint for [feature]

### ai_docs References
- `ai_docs/libraries/[library-name].md` - Patterns for [feature type]
- `ai_docs/project/patterns.md` - Integration pattern [X]

### Codebase Intelligence

**Existing Patterns to Follow:**
- File: `src/features/auth/routes.ts:23-45` - Shows authentication middleware pattern
- File: `test/features/auth/handlers.test.ts:1-30` - Shows testing pattern for routes

**Integration Points:**
- Route handler location: `src/features/[feature]/routes.ts`
- Test file location: `test/features/[feature]/handlers.test.ts`
- Middleware chain: Line 15-25 in `src/middleware.ts`

### Known Gotchas

| Gotcha | Impact | Mitigation |
|--------|--------|-----------|
| OAuth tokens expire in 1 hour | Feature breaks silently | Implement token refresh with 10-min buffer |
| Database connection pool limits | Performance degrades under load | Set pool size to CPU count * 4 |
| File upload size limit | Large files fail silently | Return 413 error with clear message |

## Implementation Blueprint

### Architecture Decision

**Chosen Approach**: [Pattern Name]

**Rationale**:
- [Why this approach]
- [What problem it solves]
- [Trade-offs considered]

### Required Tasks
1. Implement core API endpoint
   - Pseudocode: [High-level implementation outline]
   - Files: `src/features/[feature]/handlers.ts`
   - Dependencies: [List]

2. Add input validation
   - Patterns: Follow validation middleware from `src/middleware.ts`
   - Files: `src/features/[feature]/validators.ts`

3. Write unit tests
   - Strategy: [Specific test cases needed]
   - File: `test/features/[feature]/handlers.test.ts`

### Deferred Tasks (Phase 2)
4. Add caching layer
   - Reason: Requires Redis infrastructure decision
   - Follow-up: Create separate work-order after infrastructure ready

5. Add rate limiting
   - Reason: Needs capacity planning
   - Follow-up: Implement based on production metrics

### Nice-to-Have
6. Add OpenAPI docs generation
7. Add request logging middleware

## TDD Requirements

### Test Strategy
- **Unit tests**: Logic and error handling
- **Integration tests**: API endpoints with database
- **E2E tests**: User flows (if applicable)

### Critical Test Cases

```javascript
// Template for login endpoint tests
describe('POST /auth/login', () => {
  test('succeeds with valid credentials', async () => {
    // Arrange: Set up test data
    // Act: Make request
    // Assert: Verify response
  });

  test('fails with invalid credentials', async () => {
    // Validate error response
  });

  test('implements rate limiting', async () => {
    // Verify after 5 attempts within 1 minute, returns 429
  });
});
```

## Validation Gates

Execute these commands during and after implementation:

**Linting:**
```bash
npm run lint  # Expected: No errors
```

**Type Checking:**
```bash
npm run type-check  # Expected: No errors
```

**Unit Tests:**
```bash
npm test -- test/features/[feature]  # Expected: All pass
```

**Integration Tests:**
```bash
npm run test:integration -- test/features/[feature]  # Expected: All pass
```

**Coverage:**
```bash
npm run test:coverage  # Expected: >= 80% line coverage
```

**Security Scan:**
```bash
npm audit  # Expected: No vulnerabilities
```

## Task Categorization

### Required Tasks
- **Definition**: Must be implemented for MVP
- **Execution Behavior**: Fully implemented during PRP execution
- **Example**: Core API endpoint, authentication, input validation

### Deferred (Phase 2)
- **Definition**: Important but not blocking MVP
- **Execution Behavior**: Logged with reason, GitHub issue created
- **Example**: Caching, rate limiting, advanced features
- **When to Use**: Feature is valuable but:
  - Requires infrastructure decision
  - Needs capacity planning
  - Depends on other work
  - Time constraint

### Nice-to-Have
- **Definition**: Optional enhancement
- **Execution Behavior**: May be skipped, logged if deferred
- **Example**: OpenAPI docs, logging middleware, UI polish
- **When to Use**: Feature is "nice but not critical"

### Example Task List

```markdown
### Required Tasks
1. Implement authentication middleware
2. Create login endpoint
3. Create logout endpoint
4. Write unit tests for auth
5. Add input validation

### Deferred Tasks (Phase 2)
6. Add OAuth2 integration
   - Reason: OAuth provider not yet configured
   - Follow-up: Implement after infrastructure setup

7. Add session caching
   - Reason: Requires Redis evaluation
   - Follow-up: Implement based on performance metrics

### Nice-to-Have
8. Add two-factor authentication
9. Add authentication metrics dashboard
```

## Review Checklist

Before finalizing PRP:

- [ ] **Goal is clear and specific** - Can be understood without context
- [ ] **Success criteria are testable** - Each criterion has clear verification method
- [ ] **All file paths are explicit** - No "somewhere in..." references
- [ ] **Code snippets show actual patterns** - Include file path and line numbers
- [ ] **Gotchas include mitigations** - Don't just warn, provide solutions
- [ ] **Validation commands are executable** - Copy-paste ready
- [ ] **All tasks categorized** - Required/Deferred/Nice-to-Have explicit
- [ ] **Confidence score is honest** - Score reflects actual completeness

## Confidence Scoring

Rate each dimension 1-10:

### Context Completeness
- **10**: All file paths explicit, code snippets with line numbers, all documentation referenced
- **7**: Most context provided, some gaps acceptable
- **4**: Significant gaps, important details missing

### Implementation Clarity
- **10**: Pseudocode covers all cases, edge cases identified
- **7**: Main path clear, some edge cases may need discovery
- **4**: High-level only, implementation approach unclear

### Gotchas Documented
- **10**: All known pitfalls documented with mitigations
- **7**: Major gotchas documented, some minor ones may be missed
- **4**: Some gotchas mentioned, mitigations incomplete

### Validation Coverage
- **10**: All gates have executable commands, clear expectations
- **7**: Main validation commands provided, some gaps acceptable
- **4**: Incomplete validation gates, unclear expectations

### Overall Score Calculation
Average of all 4 dimensions.

**Decision Rules**:
- **9-10**: Ready for AI subagent execution (full autonomy)
- **7-8**: Ready for execution, some discovery expected
- **< 7**: Not ready, needs more research/context

## Creating ai_docs

If you discover new patterns during research, create ai_docs entries:

**Location**: `docs/blueprint/ai_docs/libraries/[library-name].md` or `docs/blueprint/ai_docs/project/patterns.md`

**Format**:
```markdown
# [Library Name] - [Pattern Name]

## What
[One sentence description]

## When to Use
[Specific use case]

## Pattern
[Code example with explanation]

## Gotchas
- [Gotcha 1]: [Mitigation]
- [Gotcha 2]: [Mitigation]

## References
- [Link to official docs](https://...)
```

**Guidelines**:
- Keep under 200 lines
- Include code examples
- Document gotchas explicitly
- Make it searchable and reusable

---
name: quality-standards
description: "Code review criteria, performance baselines, security standards, and quality gates for [PROJECT_NAME]. Enforces project quality requirements."
---

# Quality Standards

## Code Review Checklist

### Functionality
- [ ] Implementation matches requirements
- [ ] All edge cases handled
- [ ] Error handling appropriate
- [ ] No regressions introduced

### Tests
- [ ] All new code has tests (unit and/or integration)
- [ ] Tests follow TDD workflow (written first)
- [ ] Tests cover happy path and error cases
- [ ] Test coverage meets threshold ([X]%)
- [ ] All tests pass

### Code Quality
- [ ] Code is readable and maintainable
- [ ] Functions are small and focused
- [ ] No code duplication
- [ ] Appropriate abstractions used
- [ ] Follows project architecture patterns
- [ ] Naming is clear and consistent

### Security
- [ ] No hardcoded credentials or secrets
- [ ] Input validation on all external inputs
- [ ] SQL queries use parameterized statements
- [ ] Error messages don't leak sensitive info
- [ ] Authentication/authorization checked where needed
- [ ] Dependencies up-to-date (no known vulnerabilities)

### Performance
- [ ] No obvious performance issues
- [ ] Database queries optimized
- [ ] Appropriate caching where needed
- [ ] [Add project-specific performance criteria]

### Documentation
- [ ] Complex logic has comments
- [ ] Public APIs documented
- [ ] README updated if needed
- [ ] [Add project-specific documentation requirements]

## Performance Baselines

### Response Time
- [Endpoint/Operation 1]: [Target, e.g., "p95 < 200ms"]
- [Endpoint/Operation 2]: [Target]
- [Endpoint/Operation 3]: [Target]

### Throughput
- [Operation 1]: [Target, e.g., "1000 req/sec"]
- [Operation 2]: [Target]

### Resource Usage
- Memory: [Target, e.g., "< 512MB per process"]
- CPU: [Target, e.g., "< 70% under normal load"]
- Database connections: [Target, e.g., "< 10 per process"]

### Measuring Performance
```bash
# Performance test command
[performance_test_command]

# Profiling command
[profiling_command]
```

## Security Standards

### OWASP Top 10 Compliance
- [X] **Injection**: [How addressed]
- [X] **Broken Authentication**: [How addressed]
- [X] **Sensitive Data Exposure**: [How addressed]
- [X] **XML External Entities (XXE)**: [How addressed]
- [X] **Broken Access Control**: [How addressed]
- [X] **Security Misconfiguration**: [How addressed]
- [X] **Cross-Site Scripting (XSS)**: [How addressed]
- [X] **Insecure Deserialization**: [How addressed]
- [X] **Using Components with Known Vulnerabilities**: [How addressed]
- [X] **Insufficient Logging & Monitoring**: [How addressed]

### Authentication & Authorization
- [Requirement 1: e.g., "All protected endpoints require valid JWT"]
- [Requirement 2: e.g., "Role-based access control enforced"]
- [Requirement 3: e.g., "Failed auth attempts logged"]

### Data Protection
- [Requirement 1: e.g., "Passwords hashed with bcrypt (cost 12)"]
- [Requirement 2: e.g., "Sensitive data encrypted at rest"]
- [Requirement 3: e.g., "PII never logged"]

### Input Validation
- [Requirement 1: e.g., "All API inputs validated with schemas"]
- [Requirement 2: e.g., "File uploads restricted by type/size"]
- [Requirement 3: e.g., "SQL queries use parameterized statements"]

### Security Scanning
```bash
# Dependency vulnerability scan
[dependency_scan_command]

# Static analysis
[static_analysis_command]

# Secret scanning
[secret_scan_command]
```

## Code Style

### Formatting
**Tool**: [Prettier / Black / gofmt / etc.]

```bash
# Format code
[format_command]

# Check formatting
[format_check_command]
```

### Linting
**Tool**: [ESLint / Ruff / Clippy / etc.]

```bash
# Lint code
[lint_command]

# Auto-fix
[lint_fix_command]
```

### Naming Conventions
- Variables: [Convention]
- Functions: [Convention]
- Classes: [Convention]
- Files: [Convention]
- Constants: [Convention]

## Documentation Requirements

### Code Comments
**When to add comments**:
- [Scenario 1: e.g., "Complex algorithms"]
- [Scenario 2: e.g., "Non-obvious workarounds"]
- [Scenario 3: e.g., "Business logic rationale"]

**When NOT to add comments**:
- [Scenario 1: e.g., "Self-explanatory code"]
- [Scenario 2: e.g., "Redundant descriptions"]

### API Documentation
**Requirement**: [What needs documentation]

**Format**: [JSDoc / docstrings / etc.]

**Example**:
```[language]
/**
 * [Function description]
 * @param {[type]} [param] - [Description]
 * @returns {[type]} [Description]
 * @throws {[ErrorType]} [When thrown]
 */
[FUNCTION_EXAMPLE]
```

### README Requirements
**Must include**:
- [ ] Project description
- [ ] Setup instructions
- [ ] Running tests
- [ ] Development workflow
- [ ] Deployment instructions

## Dependency Management

### Versioning
- [Policy: e.g., "Pin exact versions in package.json"]
- [Policy: e.g., "Update dependencies monthly"]

### Security
```bash
# Check for vulnerabilities
[security_check_command]

# Update dependencies
[update_command]
```

### License Compliance
- [Policy: e.g., "Only MIT/Apache/BSD licenses allowed"]
- [Policy: e.g., "Review copyleft licenses before use"]

## Git Workflow

### Commit Messages
**Format**: [Conventional Commits / Other]

**Pattern**:
```
[type]([scope]): [subject]

[body]

[footer]
```

**Examples**:
- `feat(auth): add JWT token refresh`
- `fix(api): handle null user in validation`
- `refactor(db): extract query builder logic`

### Branch Naming
**Pattern**: [Pattern, e.g., "feature/feature-name", "fix/bug-description"]

### Pull Requests
**Requirements**:
- [ ] All tests pass
- [ ] Code review approved
- [ ] No merge conflicts
- [ ] [Add project-specific requirements]

**PR Template**: [Link to template or inline]

## Quality Gates

### Pre-Commit
**Checks**:
- [ ] Linting passes
- [ ] Formatting correct
- [ ] No secrets detected
- [ ] [Project-specific checks]

```bash
# Run pre-commit hooks
[pre_commit_command]
```

### Pre-Push
**Checks**:
- [ ] All tests pass
- [ ] Coverage threshold met
- [ ] [Project-specific checks]

### CI/CD
**Checks**:
- [ ] Build succeeds
- [ ] All tests pass
- [ ] Security scan passes
- [ ] Performance tests pass
- [ ] [Project-specific checks]

## Monitoring & Observability

### Logging
**Requirements**:
- [Requirement 1: e.g., "Structured logging (JSON)"]
- [Requirement 2: e.g., "Log levels used appropriately"]
- [Requirement 3: e.g., "No PII in logs"]

### Metrics
**Required metrics**:
- [Metric 1: e.g., "Request rate"]
- [Metric 2: e.g., "Error rate"]
- [Metric 3: e.g., "Response time (p50, p95, p99)"]

### Alerts
**Required alerts**:
- [Alert 1: e.g., "Error rate > 5%"]
- [Alert 2: e.g., "Response time p95 > 500ms"]
- [Alert 3: e.g., "Database connection pool exhausted"]

## Common Quality Issues

### Issue 1: [Description]
**Problem**: [What happens]
**How to detect**: [Linter / Test / Review]
**How to fix**: [Solution]

### Issue 2: [Description]
**Problem**: [What happens]
**How to detect**: [Linter / Test / Review]
**How to fix**: [Solution]

## References

- [Link to PRD success criteria]
- [Link to PRD performance baselines]
- [Link to PRD security requirements]
- [Link to architecture patterns skill]
- [Link to testing strategies skill]

---

**Note**: This skill is generated from PRDs. Update this file as quality standards evolve during development.

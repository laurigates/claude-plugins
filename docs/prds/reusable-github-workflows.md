# Reusable GitHub Action Workflows - Product Requirements Document

---
id: PRD-002
created: 2026-01-25
modified: 2026-01-25
status: Draft
version: "1.0"
relates-to:
  - ADR-0014
github-issues: []
---

## Executive Summary

### Problem Statement

Organizations using Claude Code lack standardized, reusable CI/CD workflows for common code quality, security, and accessibility checks. Teams repeatedly build similar GitHub Actions workflows from scratch, leading to inconsistent quality gates, missed security vulnerabilities, and duplicated effort across repositories.

### Proposed Solution

A collection of 22 reusable GitHub Action workflows powered by Claude Code's haiku model, organized by category (Security, Accessibility, Code Quality, Documentation, Testing, Infrastructure, Maintenance). These workflows are designed for low context usage, fast execution, and actionable output with file:line references.

### Business Impact

- **Reduced setup time**: Teams adopt pre-built workflows instead of creating from scratch
- **Consistent quality gates**: Standardized security and accessibility checks across repositories
- **Cost efficiency**: Haiku model with low turn counts minimizes API costs
- **Plugin leverage**: Workflows utilize existing claude-plugins skills for comprehensive analysis
- **Reusability**: Single source of truth with versioned releases for external consumption

---

## Stakeholders & Personas

### Stakeholder Matrix

| Role | Name/Team | Responsibility | Contact |
|------|-----------|----------------|---------|
| Product Owner | claude-plugins Team | Feature requirements and priorities | - |
| Developer | Plugin Contributors | Implementation and testing | - |
| Consumer | External Repository Owners | Adopt and customize workflows | - |

### User Personas

#### Primary: DevOps Engineer

- **Description**: Engineer responsible for CI/CD pipeline configuration
- **Needs**: Ready-to-use workflows with minimal configuration
- **Pain Points**: Building Claude integrations from scratch, inconsistent quality gates
- **Goals**: Standardized, maintainable CI/CD with Claude-powered analysis

#### Secondary: Security-Conscious Developer

- **Description**: Developer prioritizing security and accessibility in PRs
- **Needs**: Automated security scanning, WCAG compliance checks
- **Pain Points**: Manual security reviews, missed vulnerabilities
- **Goals**: Catch security issues before merge with actionable remediation

---

## Functional Requirements

### FR1: Security Workflows

Workflows that detect security vulnerabilities, secrets, and container security issues.

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR1.1 | OWASP Security Scan | Detect OWASP Top 10 vulnerabilities (injection, XSS, SSRF, etc.) | P0 |
| FR1.2 | Secrets Detection | Pre-merge gate for leaked API keys, tokens, passwords | P0 |
| FR1.3 | Dependency Security | Audit npm/pip/cargo for known CVEs | P1 |
| FR1.4 | Container Security | Dockerfile best practices (no root, pinned versions) | P1 |

### FR2: Accessibility Workflows

Workflows that enforce WCAG compliance and ARIA patterns.

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR2.1 | WCAG Compliance | Check WCAG 2.1 AA (alt text, contrast, keyboard) | P0 |
| FR2.2 | ARIA Patterns | Validate ARIA roles, states, and live regions | P1 |

### FR3: Code Quality Workflows

Workflows that detect code smells, enforce type safety, and validate patterns.

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR3.1 | Code Smell Detection | Long functions, deep nesting, magic numbers | P0 |
| FR3.2 | TypeScript Strict | `any` usage, non-null assertions, missing return types | P0 |
| FR3.3 | Async Patterns | Unhandled rejections, floating promises | P1 |
| FR3.4 | React/Vue Patterns | Missing keys, useEffect deps, props drilling | P1 |
| FR3.5 | API Contract | Request/response type mismatches, breaking changes | P2 |

### FR4: Documentation Workflows

Workflows that validate documentation accuracy and coverage.

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR4.1 | README Sync | Verify install instructions match package.json | P1 |
| FR4.2 | Changelog Validation | Enforce Keep a Changelog format | P2 |
| FR4.3 | API Docs Coverage | JSDoc/docstring coverage for exports | P2 |

### FR5: Testing Workflows

Workflows that enforce test quality and coverage.

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR5.1 | Test Coverage Gate | New code must have tests, no coverage regression | P1 |
| FR5.2 | Test Quality | Descriptive names, specific assertions, AAA pattern | P2 |
| FR5.3 | E2E Stability | Explicit waits, stable selectors, test isolation | P2 |

### FR6: Infrastructure Workflows

Workflows that validate IaC and CI/CD configurations.

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR6.1 | Dockerfile Best Practices | Multi-stage builds, layer optimization | P1 |
| FR6.2 | Terraform Validation | Format, variable descriptions, sensitive marking | P2 |
| FR6.3 | GitHub Actions Lint | Pinned versions, minimal permissions, caching | P1 |

### FR7: Maintenance Workflows

Scheduled workflows for codebase hygiene.

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR7.1 | Stale Code Detection | Unused exports, dead code, TODO age | P2 |
| FR7.2 | Dependency Freshness | Major updates, security patches, deprecated packages | P2 |

---

## Non-Functional Requirements

### Performance

| Requirement | Target | Rationale |
|-------------|--------|-----------|
| Max turns per workflow | 5-10 | Minimize context usage and API costs |
| Model | haiku | Cost-efficient, fast execution |
| File limit per analysis | 30-50 files | Prevent context overflow |

### Reusability

| Requirement | Target | Rationale |
|-------------|--------|-----------|
| Workflow location | `.github/workflows/reusable-*.yml` | GitHub requirement for reusable workflows |
| Input validation | Typed inputs with defaults | Consumer flexibility |
| Output consistency | Structured outputs (issues-found, critical-count) | Composable job dependencies |

### Security

| Requirement | Target | Rationale |
|-------------|--------|-----------|
| Secrets handling | `secrets: inherit` or explicit pass | Organization compatibility |
| Permissions | Minimal required (contents: read, pull-requests: write) | Least privilege |
| No secrets in logs | Masked outputs | Prevent leakage |

### Versioning

| Requirement | Target | Rationale |
|-------------|--------|-----------|
| Release tags | Semantic versioning (v2.0.0) | Breaking change communication |
| Compatibility | Workflow version matches plugin version | Coupled releases |

---

## Technical Considerations

### Architecture

Per [ADR-0014](../adrs/0014-reusable-workflows-in-repository.md), reusable workflows live in this repository alongside the plugins they use. This enables:
- Coupled versioning between workflows and plugins
- Single source of truth for consumers
- Easier testing of workflow changes against plugin changes

### GitHub Constraints

| Constraint | Limit |
|------------|-------|
| Max reusable workflows per caller | 50 unique workflows |
| Max nesting depth | 10 levels |
| Subdirectories | **Not supported** - all in `.github/workflows/` |
| Environment variables | Do **not** propagate from caller |

### Naming Convention

- `reusable-*` prefix = callable from other repositories
- No prefix = internal to this repository

### Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| anthropics/claude-code-action | v1 | Claude Code integration |
| actions/checkout | v4 | Repository checkout |
| code-quality-plugin | latest | Security and code smell patterns |
| accessibility-plugin | latest | WCAG and ARIA patterns |

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Workflow adoption | 10+ external repositories | GitHub referrers |
| Issue detection rate | 90%+ true positives | Manual validation sample |
| Execution time | < 5 minutes average | Workflow run duration |
| Cost per run | < $0.10 average | API usage tracking |

---

## Scope

### In Scope

- 22 reusable workflows across 7 categories
- Documentation for consumer adoption
- Test fixtures for workflow validation
- Versioning strategy and release tags

### Out of Scope

- Custom workflow builder UI
- Workflow metrics dashboard
- Automatic remediation (analysis only)
- Non-GitHub CI/CD platforms

---

## Timeline & Phases

### Phase 1: Security Foundation

Priority workflows for security scanning:
1. `reusable-security-secrets.yml` - Critical pre-merge gate
2. `reusable-security-owasp.yml` - Comprehensive security
3. `reusable-security-deps.yml` - Supply chain security

### Phase 2: Code Quality

Quality enforcement workflows:
4. `reusable-quality-code-smell.yml` - General quality
5. `reusable-quality-typescript.yml` - Type safety
6. `reusable-quality-async.yml` - Error handling

### Phase 3: Accessibility

WCAG compliance workflows:
7. `reusable-a11y-wcag.yml` - WCAG AA compliance
8. `reusable-a11y-aria.yml` - ARIA correctness

### Phase 4: Testing & Documentation

Coverage and documentation workflows:
9. `reusable-test-coverage.yml` - Coverage enforcement
10. `reusable-docs-api.yml` - Documentation quality

### Phase 5: Infrastructure & Maintenance

Final workflows:
11. `reusable-infra-actions.yml` - Workflow quality
12. `reusable-maintenance-stale.yml` - Code hygiene

---
description: "Curate library or project documentation for ai_docs to optimize AI context"
allowed_tools: [Read, Write, Glob, Bash, WebFetch, WebSearch]
---

Curate documentation for a library or project pattern into an ai_docs entry.

**Usage**: `/prp:curate-docs [library-name]` or `/prp:curate-docs project:[pattern-name]`

**What is ai_docs?**
ai_docs are curated documentation entries optimized for AI agents. Unlike raw documentation, they are:
- **Concise**: < 200 lines, only essential information
- **Actionable**: Code snippets that can be directly used
- **Gotcha-aware**: Common pitfalls with solutions
- **Version-specific**: Tied to specific library versions

**Prerequisites**:
- Blueprint Development initialized
- `.claude/blueprints/ai_docs/` directory exists

## Phase 1: Research

### 1.1 For Library Documentation

**Identify the library**:
```bash
# Check if already documented
ls .claude/blueprints/ai_docs/libraries/

# Check project dependencies for version
cat package.json | grep "[library-name]"
# or
cat pyproject.toml | grep "[library-name]"
# or
cat requirements.txt | grep "[library-name]"
```

**Gather documentation**:
1. Search for official documentation
2. Find the specific sections relevant to project use cases
3. Look for known issues and gotchas
4. Search for common problems on Stack Overflow/GitHub

Use WebSearch:
```
[library-name] documentation [specific topic]
[library-name] common issues
[library-name] gotchas
[library-name] best practices
```

Use WebFetch to extract key sections:
```
Fetch: [library documentation URL]
Extract: [specific pattern or topic]
```

### 1.2 For Project Patterns

**Identify existing patterns**:
```bash
# Search for pattern implementations
grep -r "[pattern keyword]" src/
grep -r "[pattern keyword]" lib/
```

**Analyze the pattern**:
- Where is it used?
- What are the conventions?
- What gotchas have been encountered?

## Phase 2: Extract Key Information

### 2.1 Determine Use Cases

Identify how this library/pattern is used in this project:
- What features depend on it?
- What are the common operations?
- What integrations exist?

### 2.2 Extract Patterns

From documentation and codebase:
- **Quick reference**: Most common operations
- **Patterns we use**: Project-specific implementations
- **Configuration**: How it's configured in this project

### 2.3 Document Gotchas

Compile known issues:
- Version-specific behaviors
- Common mistakes
- Performance pitfalls
- Security considerations

Sources for gotchas:
- Official documentation warnings
- GitHub issues
- Stack Overflow discussions
- Team experience

## Phase 3: Create ai_docs Entry

### 3.1 Choose Location

**For libraries**:
```
.claude/blueprints/ai_docs/libraries/[library-name].md
```

**For project patterns**:
```
.claude/blueprints/ai_docs/project/[pattern-name].md
```

### 3.2 Write Entry

Use the ai_docs template:

```markdown
# [Library/Pattern Name]

**Version:** X.Y.Z
**Last Updated:** YYYY-MM-DD
**Use Case:** [Why we use this in this project]

## Quick Reference

### [Common Operation 1]
```[language]
# Code snippet that can be directly copied
```

### [Common Operation 2]
```[language]
# Code snippet that can be directly copied
```

## Patterns We Use

### [Pattern Name]
[When to use this pattern]

```[language]
# Full example as used in this project
```

## Configuration

### Environment Variables
```bash
VAR_NAME=value
```

### Our Config Pattern
```[language]
# How we configure this in the project
```

## Gotchas

### Gotcha 1: [Title]
**Issue:** [What can go wrong]
**Solution:**
```[language]
# Correct approach
```

### Gotcha 2: [Title]
**Issue:** [What can go wrong]
**Solution:**
```[language]
# Correct approach
```

## Anti-Patterns

### Don't Do This
```[language]
# Bad example
```

### Do This Instead
```[language]
# Good example
```

## Testing

### How to Mock
```[language]
# Mocking pattern for tests
```

## References

- [Official Docs - Specific Section](url)
- [Relevant GitHub Issue](url)
```

### 3.3 Quality Checks

Before saving, verify:
- [ ] Entry is < 200 lines
- [ ] Code snippets are directly usable
- [ ] Gotchas include solutions
- [ ] Version is specified
- [ ] Use cases are clear
- [ ] Anti-patterns are shown

## Phase 4: Integrate

### 4.1 Save Entry

```bash
# Write to ai_docs
cat > .claude/blueprints/ai_docs/[type]/[name].md << 'EOF'
[content]
EOF
```

### 4.2 Update References

If PRPs reference this library/pattern:
- Add ai_docs reference to PRP
- Update context sections

### 4.3 Report

```markdown
## ai_docs Entry Created: [Name]

**Location:** `.claude/blueprints/ai_docs/[type]/[name].md`

**Version:** X.Y.Z

**Content Summary:**
- Quick Reference: [N operations]
- Patterns: [N patterns]
- Gotchas: [N documented]
- Anti-patterns: [N shown]

**Lines:** [count] (target: < 200)

**Use in PRPs:**
Reference with:
```markdown
### ai_docs References
- See `ai_docs/[type]/[name].md` - [Section]
```

**Linked PRPs:**
- [List any PRPs that should reference this]
```

## Templates by Type

### Library Template
Best for: External dependencies (Redis, Pydantic, FastAPI, etc.)

Focus on:
- Version-specific behavior
- Connection/initialization patterns
- Error handling
- Performance gotchas

### Framework Template
Best for: Web frameworks, ORMs, testing frameworks

Focus on:
- Project structure conventions
- Configuration patterns
- Extension points
- Testing integration

### Project Pattern Template
Best for: Internal patterns (Repository, Service Layer, etc.)

Focus on:
- When to use this pattern
- How it's implemented in this codebase
- Integration with other patterns
- Common mistakes

**Tips**:
- Be ruthless about conciseness - every line uses tokens
- Include actual line numbers from codebase examples
- Document gotchas immediately when discovered
- Update entries as patterns evolve
- Link to official docs for rarely-used features

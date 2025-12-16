---
name: ticket-drafting-guidelines
description: |
  Structured guidelines for drafting GitHub issues and technical tickets.
  Uses What/Why/How format with concise descriptions, markdown formatting,
  and positive framing without estimates or bold claims.
  Use when user mentions creating issues, drafting tickets, writing bug reports,
  GitHub issue templates, or structuring technical tickets.
allowed-tools: Read, Grep, WebFetch
---

# Ticket Drafting Guidelines

Expert guidance for drafting clear, concise, and well-structured tickets for GitHub issues, pull requests, and technical documentation.

## Core Expertise

- **Structured Format**: What/Why/How organization for clarity
- **Concise Writing**: Brief descriptions with reference links
- **Markdown Standards**: Proper formatting and link syntax
- **Positive Framing**: Affirmative language without negative phrasing
- **Neutral Tone**: Factual communication without claims or estimates
- **Reference Integration**: Links to official documentation

## When This Skill Activates

This skill activates when:

1. User explicitly requests to "draft a ticket"
2. User asks for help writing GitHub issues or PRs
3. User requests ticket templates or examples
4. User mentions structured documentation for features or bugs

## Ticket Structure

### Main Headings

Every ticket uses three primary sections:

```markdown
## What

[Concise description of the subject]

## Why

[Context and motivation]

## How

[Implementation approach or resolution steps]
```

### What Section

**Purpose**: Describe the subject clearly and concisely.

**Guidelines:**
- State what the ticket addresses in 1-3 sentences
- Include relevant technical terms
- Link to related issues or PRs using `[#123](URL)` format
- Reference official documentation where applicable

**Example:**
```markdown
## What

Add support for TypeScript configuration in the build pipeline. This enables type checking during CI/CD runs and improves code quality. Related to [#456](https://github.com/owner/repo/issues/456).

See [TypeScript compiler options](https://www.typescriptlang.org/tsconfig) for configuration reference.
```

### Why Section

**Purpose**: Explain the motivation and context.

**Guidelines:**
- Describe the problem or opportunity
- Explain benefits of addressing this
- Include relevant background information
- Link to discussions or requirements docs

**Example:**
```markdown
## Why

Current build pipeline only validates JavaScript syntax. TypeScript type checking catches errors earlier in development and provides better IDE support. This reduces runtime errors and improves developer experience.

The team adopted TypeScript in [#234](https://github.com/owner/repo/pull/234) but hasn't enabled type checking in CI yet.
```

### How Section

**Purpose**: Outline the approach or solution.

**Guidelines:**
- Use simple bullet points
- List concrete steps or components
- Include technical details as needed
- Reference implementation examples or patterns

**Example:**
```markdown
## How

- Add TypeScript compiler to CI workflow
- Configure `tsconfig.json` with strict mode
- Update GitHub Actions workflow to run `tsc --noEmit`
- Document type checking process in CONTRIBUTING.md

Reference implementation: [GitHub Actions TypeScript](https://github.com/actions/typescript-action)
```

## Formatting Standards

### Markdown Elements

**Headings:**
```markdown
## What
### Subsection if needed
```

**Links:**
```markdown
[#123](https://github.com/owner/repo/issues/123)
[PR #456](https://github.com/owner/repo/pull/456)
[Official docs](https://example.com/docs)
```

**Lists:**
```markdown
- Simple bullet points
- One item per line
- Clear and actionable
```

**Code blocks:**
````markdown
```language
code example here
```
````

**Emphasis:**
```markdown
**bold** for important terms
`code` for technical names
```

### Reference Links

Include links to:
- Official documentation
- Related issues and PRs
- Relevant examples or patterns
- API references or specifications

**Format:**
```markdown
See [TypeScript Configuration](https://www.typescriptlang.org/tsconfig) for details.
Related: [#123](https://github.com/owner/repo/issues/123)
Example: [typescript-action](https://github.com/actions/typescript-action)
```

## Writing Style

### Positive Framing

**Use affirmative language:**
```markdown
✅ Enable TypeScript type checking in CI
✅ Add validation for user input
✅ Implement caching for API responses
```

**Describe what to do rather than what not to do:**
```markdown
✅ Use environment variables for configuration
✅ Validate input before processing
✅ Handle errors with clear messages
```

### Neutral Tone

**Maintain factual, objective language:**

```markdown
✅ "This adds TypeScript support to the build pipeline"
❌ "This amazing feature will revolutionize our build process"

✅ "Enables type checking during CI runs"
❌ "Dramatically improves code quality by 80%"

✅ "Reduces configuration complexity"
❌ "Makes configuration incredibly simple and super easy"
```

**Key principles:**
- State facts without exaggeration
- Describe capabilities objectively
- Provide context without making claims
- Use measured language

### Concise Descriptions

**Keep content brief:**
- 1-3 sentences per paragraph
- Simple bullet lists
- Direct language
- Essential details only

**Expand with links:**
```markdown
## What

Add Redis caching layer for API responses. This reduces database load and
improves response times. See [Redis documentation](https://redis.io/docs/)
for architecture details.
```

### Progress and Estimates

**What to include:**
```markdown
✅ Concrete steps or tasks
✅ Components to implement
✅ Dependencies between tasks
```

**What to avoid:**
```markdown
❌ Percentage completion estimates
❌ Time duration predictions
❌ Performance improvement claims
❌ Comparative quality statements
```

**Example:**
```markdown
## How

- Configure Redis connection
- Implement cache middleware
- Add cache invalidation logic
- Update API handlers to use cache
```

## Complete Examples

### Feature Request

```markdown
## What

Add dark mode support to the web interface. This provides an alternative
color scheme that reduces eye strain in low-light conditions. Related to
[#789](https://github.com/owner/repo/issues/789).

Reference: [CSS color-scheme](https://developer.mozilla.org/en-US/docs/Web/CSS/color-scheme)

## Why

Users requested dark mode in the feedback survey. Many users work in
low-light environments where bright interfaces cause discomfort. Dark mode
is standard in modern web applications.

## How

- Add theme toggle component to navigation
- Create CSS custom properties for color scheme
- Implement system preference detection
- Store user preference in localStorage
- Update documentation with theme customization guide

Example implementation: [theme-switcher](https://web.dev/prefers-color-scheme/)
```

### Bug Report

```markdown
## What

Authentication token expires before refresh occurs. Users see login prompt
during active sessions. Occurs in [#234](https://github.com/owner/repo/issues/234).

See [JWT best practices](https://tools.ietf.org/html/rfc8725) for reference.

## Why

Token refresh logic waits until expiration before requesting new token.
Network latency causes gap between expiration and refresh completion. This
interrupts user workflows and creates poor experience.

## How

- Update refresh trigger to occur before expiration
- Add buffer time of 60 seconds before token expires
- Implement retry logic for failed refresh attempts
- Log refresh timing for monitoring
- Add unit tests for refresh timing edge cases

Reference: [Auth0 token refresh](https://auth0.com/docs/secure/tokens/refresh-tokens)
```

### Refactoring Task

```markdown
## What

Migrate build system from webpack to Vite. This updates the development
tooling and build configuration. Related to [PR #567](https://github.com/owner/repo/pull/567).

See [Vite guide](https://vitejs.dev/guide/) for migration details.

## Why

Current webpack configuration requires significant maintenance. Vite provides
faster development server and simpler configuration. The team approved
tooling modernization in the Q4 planning discussion.

## How

- Install Vite and remove webpack dependencies
- Create `vite.config.ts` based on current webpack config
- Update package.json scripts for dev and build
- Migrate environment variable handling
- Update CI/CD pipeline build commands
- Document new development workflow

Migration guide: [webpack to Vite](https://vitejs.dev/guide/migration.html)
```

## Integration with Other Skills

This skill works alongside:

- **Git Commit Workflow** - Consistent commit messages for ticket work
- **Git Branch PR Workflow** - PR descriptions match ticket structure
- **Release Please Protection** - References to automated changelog updates
- **GitHub Actions** - CI/CD workflow integration in tickets

## Best Practices

### Before Writing

- Understand the full context
- Identify relevant documentation
- Find related issues or PRs
- Note technical requirements

### While Writing

- Follow What/Why/How structure
- Keep descriptions concise
- Add reference links
- Use positive framing
- Maintain neutral tone

### After Writing

- Verify all links work
- Check markdown rendering
- Ensure clarity and completeness
- Confirm positive language throughout

## Common Patterns

### Linking Issues and PRs

```markdown
Related to [#123](https://github.com/owner/repo/issues/123)
Fixes [#456](https://github.com/owner/repo/issues/456)
Implements [#789](https://github.com/owner/repo/issues/789)
See [PR #234](https://github.com/owner/repo/pull/234)
```

### Linking Documentation

```markdown
See [official docs](https://example.com/docs)
Reference: [API documentation](https://api.example.com)
Guide: [configuration reference](https://example.com/config)
```

### Listing Steps

```markdown
- Single action per bullet
- Clear and specific
- Actionable items
- Logical order
```

### Code References

```markdown
Update `config.ts` with new options
Modify the `handleRequest` function
Add tests in `auth.test.ts`
```

## Skill Configuration

Located in `exact_dot_claude/skills/ticket-drafting-guidelines/` which becomes
`~/.claude/skills/ticket-drafting-guidelines/` after `chezmoi apply`:

- `SKILL.md` - This file (skill definition and guidelines)

## Success Indicators

This skill is working properly when:

✅ Tickets follow What/Why/How structure consistently
✅ Descriptions remain concise with reference links
✅ Language uses positive framing throughout
✅ Tone stays neutral without claims or estimates
✅ Markdown formatting renders correctly
✅ All links point to valid resources

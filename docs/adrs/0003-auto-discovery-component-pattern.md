# ADR-0003: Auto-Discovery Component Pattern

## Status

Accepted

## Date

2024-12 (retroactively documented 2025-12)

## Context

Each Claude Code plugin contains multiple component types: commands, skills, and agents. We needed to decide how these components would be registered and discovered by Claude Code.

Two primary approaches exist:

1. **Explicit registration**: List all components in `plugin.json`
2. **Convention-based discovery**: Place components in standard directories

The original dotfiles approach used file system conventions, which proved effective for organizing 100+ skills.

## Decision

Use **convention-based auto-discovery** where Claude Code automatically finds components based on directory structure:

### Directory Conventions

```
<plugin>/
├── .claude-plugin/
│   └── plugin.json          # Only manifest metadata (no component listings)
├── commands/                 # Auto-discovered
│   ├── commit.md            # → /commit
│   └── configure/           # Subdirectory grouping
│       ├── pre-commit.md    # → /configure:pre-commit
│       └── tests.md         # → /configure:tests
├── skills/                   # Auto-discovered
│   └── skill-name/
│       ├── SKILL.md         # Required: skill definition
│       ├── reference.md     # Optional: supporting docs
│       └── templates/       # Optional: templates
├── agents/                   # Auto-discovered
│   └── agent-name.md
└── hooks/                    # Optional
    └── hooks.json
```

### Discovery Rules

| Component        | Location              | Registration                       |
| ---------------- | --------------------- | ---------------------------------- |
| Commands         | `commands/*.md`       | `/command-name`                    |
| Grouped Commands | `commands/group/*.md` | `/group:command-name`              |
| Skills           | `skills/*/SKILL.md`   | Context-activated by description   |
| Agents           | `agents/*.md`         | Available via `/agents` or context |

### plugin.json Role

The manifest contains only metadata; it does **not** list components:

```json
{
  "name": "git-plugin",
  "version": "1.0.0",
  "description": "Git workflows, commits, PRs, and repository management",
  "keywords": ["git", "github", "commit", "pull-request"]
}
```

## Consequences

### Advantages

- **Reduced boilerplate**: No need to maintain component lists
- **Self-documenting structure**: File system shows what's available
- **Easy additions**: Add a file, get a command (no manifest updates)
- **Consistent organization**: All plugins use identical structure
- **IDE support**: File explorers show the full component inventory
- **Refactoring friendly**: Move/rename files without manifest sync issues

### Disadvantages

- **Implicit registration**: Components exist by convention, not declaration
- **Discovery overhead**: Claude Code must scan directories at load time
- **Strict conventions**: Files must follow exact naming patterns
- **No conditional inclusion**: Can't easily disable a component without removing the file

### Component Metadata

Each component type has its own metadata format:

**Commands** (YAML frontmatter):

```yaml
---
description: "Create a git commit with conventional format"
allowed-tools: [Bash, Read, Glob]
argument-hint: "[--amend] [--scope SCOPE]"
---
```

**Skills** (YAML frontmatter):

```yaml
---
name: git-commit-workflow
description: "When committing code. Conventional commits, co-authors."
---
```

**Agents** (YAML frontmatter):

```yaml
---
name: commit-review
model: opus
color: "#4CAF50"
description: "Review commits for quality and conventions"
tools: Bash, Read, Grep
---
```

## Alternatives Considered

### 1. Explicit Component Lists

List all components in `plugin.json`:

```json
{
  "commands": ["commands/commit.md", "commands/issue.md"],
  "skills": ["skills/git-commit-workflow"],
  "agents": ["agents/commit-review.md"]
}
```

**Rejected**: Maintenance burden; easy to forget adding new components.

### 2. Mixed Approach

Auto-discover by default but allow explicit overrides.

**Rejected**: Complexity; unclear which takes precedence.

### 3. Code-Based Registration

Define components in JavaScript/TypeScript.

**Rejected**: Against Claude Code's markdown-first philosophy; increases barrier to contribution.

## Related Decisions

- ADR-0001: Plugin-Based Architecture
- ADR-0007: Namespace-Based Command Organization
- Dotfiles ADR-0003: Skill Activation via Trigger Keywords

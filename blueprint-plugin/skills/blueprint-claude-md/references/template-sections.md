# blueprint-claude-md — Template Sections

The section skeleton for a generated CLAUDE.md, the per-project-type additions,
and the CLAUDE.local.md template. Entry point: [`../SKILL.md`](../SKILL.md) §
Step 4 (generate sections) and Step 6 (CLAUDE.local.md).

## Standard sections

Focused on team-shared instructions:

```markdown
# Project: {name}

## Overview
{Brief project description from PRDs or detection}

## Tech Stack
- Language: {detected}
- Framework: {detected}
- Build: {detected}
- Test: {detected}

## Development Workflow

### Getting Started
{Setup commands}

### Running Tests
{Test commands}

### Building
{Build commands}

## Architecture
{Key architectural decisions from PRDs — or use @import:}
@docs/prds/architecture-prd.md

## Conventions

### Code Style
{Detected or from PRDs}

### Commit Messages
{Conventional commits if detected}

### Testing Requirements
{From PRDs or rules}

## See Also
{If modular rules enabled:}
- `.claude/rules/` - Detailed rules by domain
- `docs/prds/` - Product requirements
```

## Sections to omit

Auto memory handles these automatically:

- "Current Focus" — Claude tracks this in auto memory
- "Key Files" — Claude learns file relationships automatically
- Debugging tips — Claude records these in auto memory topic files

## Per-project-type sections

Customize per project type:

| Project Type | Key Sections |
|--------------|--------------|
| Python | Virtual env, pytest, type hints |
| Node.js | Package manager, test runner, build |
| Rust | Cargo, clippy, unsafe usage rules |
| Monorepo | Workspace structure, shared deps |
| API | Endpoints, auth, error handling |
| Frontend | Components, state, styling |

## CLAUDE.local.md template

When the user selected "Create CLAUDE.local.md":

- Create `CLAUDE.local.md` in project root for personal preferences
- Add `CLAUDE.local.md` to `.gitignore` if not already present
- Template:
  ```markdown
  # Personal Preferences

  ## My Environment
  - IDE: {detected or ask}
  - Terminal: {detected or ask}

  ## My Workflow Preferences
  - {Personal conventions not shared with team}
  ```

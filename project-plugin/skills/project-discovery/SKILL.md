---
created: 2025-12-16
modified: 2026-05-09
reviewed: 2026-05-09
name: project-discovery
description: Project orientation for unfamiliar codebases. Use when entering a new project, exploring unknown repos, or working on shaky assumptions about build, test, lint, or CI setup.
user-invocable: false
allowed-tools: Bash(ls *), Bash(find *), Bash(wc *), Read, Grep, Glob, TodoWrite
---

# Project Discovery

## When to Use This Skill

| Use this skill when... | Use project-continue instead when... |
|---|---|
| Entering an unfamiliar codebase and need orientation on language/tooling | Resuming known work on a familiar project from PRDs and feature tracker |
| Reasoning shows uncertainty phrases ("not sure what this does") | Already have a clear next task and just need to continue executing |
| Onboarding a fresh clone where build/test commands are unknown | Use project-init instead when scaffolding a brand-new project from scratch |

Systematic project orientation to understand codebase state before making changes. Prevents working on incorrect assumptions by establishing clear context about git state, project structure, and development tooling.

## Core Expertise

**Automatic Activation Detection:**
- Detects uncertainty in Claude's reasoning or responses
- Activates on manual user requests for orientation
- Focuses on git repositories only

**Discovery Capabilities:**
- Git state analysis (branch, changes, remote sync, commit history)
- Project type identification (language, framework, monorepo detection)
- Development tooling discovery (build, test, lint, CI/CD)
- Documentation quick scan (README, setup instructions)
- Risk flag identification (uncommitted work, branch divergence)

**Output:**
- Structured summary of project state
- Critical risk flags highlighted
- Actionable next-step recommendations
- 2-3 minute discovery timeframe

## When This Skill Activates

### Automatic Triggers

This skill automatically activates when Claude's internal reasoning or responses contain uncertainty phrases like:

- "I should first understand..."
- "Let me check the project..."
- "Not sure about the structure..."
- "I need to understand..."
- "Before proceeding, let me..."
- "I'm uncertain about..."
- "Let me investigate the project..."

**Rationale:** These phrases indicate Claude is working on incomplete context, which can lead to incorrect assumptions, wrong commands, or inappropriate file edits.

### Manual Invocation

Users can explicitly request project discovery with keywords:

- "orient yourself"
- "discover the project"
- "understand this codebase"
- "what's the project state?"
- "analyze the project structure"
- "give me project context"

### When NOT to Activate

Do NOT activate this skill when:
- Claude has clear context and is confidently executing a specific task
- User is asking about specific code that Claude has already analyzed
- Current conversation already established project context
- Working in a non-git directory (this skill is git-focused)

## Quick Discovery (Recommended)

For fast, consistent project orientation, run the bundled discovery script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-discovery/scripts/discover.sh"
```

This replaces the manual 5-step process with a single execution that outputs structured data covering git state, project type, tooling, documentation, and risk assessment.

For the full manual workflow (5 steps with all commands, risk flags, the summary template, error handling for non-git / empty / large-monorepo / missing-docs cases, and the underlying rationale), see [REFERENCE.md](REFERENCE.md).

## Integration with Other Skills

### Related Skills
- **git-commit-workflow**: Use after discovering conventional commit patterns
- **chezmoi-expert**: If project is a dotfiles repo (detects chezmoi.toml)
- **git-security-checks**: Run if pre-commit hooks detected
- **Explore agent**: Delegate to this agent if deeper codebase exploration needed beyond initial orientation

### When to Delegate
After project discovery, if user asks for deeper investigation:
- "How does authentication work?" → Use `Explore` agent
- "Review this code for security" → Use `security-audit` agent
- "Understand the architecture" → Use `code-analysis` agent

Project discovery establishes **baseline context**; specialized skills handle **deep investigation**.

## Quick Reference: Discovery Commands

### Essential Git Commands
```bash
git branch --show-current                     # Current branch
git status --short --branch                   # Git state summary
git log --oneline -n 10                       # Recent commits
git rev-list --count HEAD...@{u}              # Commits ahead/behind remote
```

### Project Type Detection
```bash
ls -la | grep -E "(package\.json|Cargo\.toml|pyproject\.toml|go\.mod)"
find . -maxdepth 3 -name "package.json"       # Monorepo detection
```

### Tooling Discovery
```bash
jq -r '.scripts | keys[]' package.json        # npm scripts
grep "^[a-zA-Z0-9_-]*:" Makefile              # Make targets
ls -la .github/workflows/                      # GitHub Actions
```

### Documentation Scan
```bash
head -50 README.md                            # Project description
ls -la | grep -E "(README|CONTRIBUTING)"      # Key docs
```

---

## Example Output

See `examples.md` for complete discovery outputs for:
- Python project with pytest + ruff + GitHub Actions
- JavaScript/TypeScript project with npm + ESLint + Vitest
- Rust project with cargo + clippy + no CI
- Monorepo with multiple sub-projects
- Project with uncommitted changes (risk flags)
- Clean project ready for work

---

*For detailed command reference and more examples, see `discovery-commands.md` and `examples.md`.*

# Project Plugin

Project initialization and management plugin for Claude Code. Provides commands for project setup, changelog review, and continuous development workflows.

## Skills

### `/project:init`
Base project initialization that creates universal project structure for any project type (Python, Node, Rust, Go, or generic).

**Features:**
- Creates standard directory structure (src/, tests/, docs/, .github/)
- Initializes git repository
- Sets up base documentation (README, LICENSE, .gitignore)
- Configures EditorConfig for consistent formatting
- Sets up pre-commit hooks configuration
- Creates base GitHub Actions CI workflow
- Generates universal Makefile with common targets
- Optional GitHub repository creation

**Usage:**
```bash
/project:init my-project python --github --private
```

### `/project:continue`
Analyze project state and continue development where you left off.

**Features:**
- Checks git status, recent commits, current branch
- Reads project context (PRDs, work overview, work orders)
- Analyzes state and determines next task
- Reports project status before starting
- Begins work following TDD (RED → GREEN → REFACTOR)
- Updates feature tracker as work progresses

**Usage:**
```bash
/project:continue
```

**Note:** Generic skill. For blueprint-driven projects, `/blueprint:execute` can pick and run the next logical action; `/project:continue` resumes hands-on TDD coding.

### `/project:test-loop`
Run automated TDD cycle: test → fix → refactor.

**Features:**
- Detects test command from project structure
- Runs test suite continuously
- On failure: Makes minimal fix, re-runs tests
- On success: Identifies refactoring opportunities
- Reports results with fixes and refactorings applied

**Usage:**
```bash
/project:test-loop
```

**Note:** Generic skill. Configure project-specific test commands in `CLAUDE.md` or `.claude/rules/` for automatic detection.

### `/changelog:review`
Review Claude Code changelog for changes impacting plugin development.

**Features:**
- Fetches current Claude Code changelog from GitHub
- Compares against last checked version
- Identifies breaking changes, new features, and deprecations
- Maps changes to affected plugins
- Generates actionable report with recommendations
- Updates version tracking file

**Usage:**
```bash
/changelog:review                  # Review changes since last check
/changelog:review --full           # Review entire changelog
/changelog:review --since 2.0.0    # Review from specific version
/changelog:review --update         # Just update tracking
```

**Automated via GitHub Actions:** A weekly workflow automatically checks for new Claude Code versions and creates GitHub issues when updates are detected.

### `project-discovery`
Systematic project orientation for unfamiliar codebases.

**Automatically activates when Claude detects uncertainty** about project state, structure, or tooling.

**Capabilities:**
- **Phase 1**: Git state analysis (branch, changes, commits, remote sync)
- **Phase 2**: Project type detection (language, framework, monorepo)
- **Phase 3**: Development tooling discovery (build, test, lint, CI/CD)
- **Phase 4**: Documentation quick scan (README, setup instructions)
- **Phase 5**: State summary with risk flags and recommendations

**Output:**
- Structured project summary
- Risk flags highlighted (uncommitted changes, branch divergence, etc.)
- Actionable next-step recommendations
- 2-3 minute discovery timeframe

**Manual invocation:**
- "orient yourself"
- "discover the project"
- "understand this codebase"
- "what's the project state?"

See `skills/project-discovery/` for:
- `SKILL.md` - Complete skill documentation
- `discovery-commands.md` - Command reference
- `examples.md` - Example discovery outputs

### `/project:refocus`
Refresh the plan to focus on the task at hand when context has grown.

**Features:**
- Sorts the session into done / remaining / stale buckets
- Extracts load-bearing decisions and active boundaries that would be lost on a context clear
- Drafts a **self-contained** forward-only plan (restates files, decisions, and constraints — no back-references)
- Surfaces it via `ExitPlanMode` so the approval dialog offers "clear context and continue in auto mode"
- Prunes resolved tangents so the next stretch of work starts clean

**Manual invocation:**
- "refresh the plan"
- "refocus on the task at hand"
- "let's focus on what's left"
- "trim the context and continue in auto mode"

**Usage:**
```bash
/project:refocus
```

### `changelog-review`
Analyze Claude Code changelog for impacts on plugin development.

**Automatically activates when** reviewing Claude Code updates, checking for breaking changes, or analyzing new features for plugin opportunities.

**Capabilities:**
- Version comparison and change extraction
- Impact categorization (high/medium/low)
- Plugin mapping for affected areas
- Report generation with actionable items

**Key Areas Monitored:**
- Hook system changes
- Skill/command updates
- Agent capabilities
- Permission patterns
- MCP improvements
- SDK changes

**Manual invocation:**
- "review claude code changelog"
- "check for claude code updates"
- "analyze changelog impacts"

## Installation

This plugin is part of the claude-plugins repository. To use it:

1. Copy the `project-plugin` directory to your Claude plugins location
2. The plugin will be automatically discovered by Claude Code
3. Commands will be available as `/project:*`

## Dependencies

### Commands
- `git` - Version control operations
- `gh` - GitHub CLI (optional, for repository creation)
- `jq` - JSON parsing (for Node.js projects)
- `pre-commit` - Git hook management

## Best Practices

### Documentation-First
Always research relevant documentation using Context7 before implementation. Verify syntax, parameters, and breaking changes against official documentation.

### Test-Driven Development
Follow strict RED → GREEN → REFACTOR workflow:
1. Write tests before implementation
2. Ensure all tests pass before moving forward
3. Maintain test coverage for robust code

### Version Control
- Commit early and often
- Use conventional commits for clear history
- Always pull before creating a branch
- Run security checks before staging files

## Project Types Supported

- **Python**: pyproject.toml, uv, pytest, ruff, ty
- **JavaScript/TypeScript**: package.json, bun/pnpm/npm, Vitest/Jest, ESLint, Prettier
- **Rust**: Cargo.toml, cargo test, clippy, rustfmt
- **Go**: go.mod, go test, golangci-lint
- **Generic**: Makefile-based projects with custom tooling

## Integration

### With Blueprint Plugin
- `/blueprint:execute` - Determine and run the next logical blueprint action
- `/blueprint:work-order` - Create work orders before starting features

### With Git Plugin
- `/git:commit` - Conventional commits integration
- `/git:pr` - Pull request creation

### With Testing Plugin
- `/test:quick` - Run unit tests after changes
- `/test:full` - Run full test suite before commit

## License

MIT

## Contributing

See the main claude-plugins repository for contribution guidelines.

# Project Plugin

Project initialization and management plugin for Claude Code. Provides commands for project setup, modernization, and continuous development workflows.

## Commands

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

### `/project:new`
Comprehensive project initialization with language-specific configuration including pre-commit hooks, release workflows, Makefile, and Dockerfile.

**Features:**
- Detects or accepts project type (python, node, go, generic)
- Creates Makefile with colored output
- Generates Dockerfile with multi-stage builds
- Sets up .gitignore for language-specific patterns
- Configures release-please for automated releases
- Sets up comprehensive pre-commit hooks
- Creates pyproject.toml (Python projects)
- Configures .claude/settings.json with post-tool hooks

**Usage:**
```bash
/project:new python
/project:new node
/project:new  # Defaults to python
```

### `/project:modernize`
Systematically modernize applications to current standards and best practices.

**Features:**
- **Phase 1**: Application analysis (detect stack, dependencies, security audit)
- **Phase 2**: Package management modernization (uv for Python, bun/pnpm for Node.js)
- **Phase 3**: Security hardening (fix secrets, environment variables)
- **Phase 4**: Infrastructure modernization (Alpine Dockerfiles, docker-compose updates)
- **Phase 5**: 12-factor app compliance
- **Phase 6**: Documentation updates
- **Phase 7**: Testing & validation
- **Phase 8**: GitHub Actions workflows (CI/CD, release-please, security scanning)
- **Phase 9**: Pre-commit hooks setup

**Always uses Context7 MCP to fetch current best practices** before suggesting tool usage.

**Usage:**
```bash
/project:modernize                 # Full modernization
/project:modernize --security-only # Security fixes only
/project:modernize --dry-run       # Show changes without applying
```

### `/project:modernize-exp`
Experimental version of modernize with latest tooling recommendations. Same features as `/project:modernize` but may include bleeding-edge practices.

### `/project:continue`
Analyze project state and continue development where you left off.

**Features:**
- Checks git status, recent commits, current branch
- Reads project context (PRDs, work overview, work orders)
- Analyzes state and determines next task
- Reports project status before starting
- Begins work following TDD (RED → GREEN → REFACTOR)
- Updates work-overview as work progresses

**Usage:**
```bash
/project:continue
```

**Note:** Generic template that should be customized per project using `/blueprint-generate-commands`. Project-specific version is generated to `.claude/commands/project/continue.md`.

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

**Note:** Generic template that should be customized per project using `/blueprint-generate-commands`. Project-specific version is generated to `.claude/commands/project/test-loop.md`.

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

## Skills

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

### Modernization
- **Context7 MCP** - Required for fetching current best practices (mandatory before tool suggestions)
- `docker` - Container operations (optional)
- `trufflehog` - Secret detection (optional)
- Language-specific package managers (uv, npm, bun, cargo, etc.)

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

### Modernization
- **MANDATORY**: Use Context7 MCP for current best practices documentation before ANY tool usage
- For all package managers (uv, npm, bun, cargo, etc.): Always verify current best practices
- Never suggest package management commands without first checking Context7 documentation

## Project Types Supported

- **Python**: pyproject.toml, uv, pytest, ruff, mypy
- **JavaScript/TypeScript**: package.json, bun/pnpm/npm, Vitest/Jest, ESLint, Prettier
- **Rust**: Cargo.toml, cargo test, clippy, rustfmt
- **Go**: go.mod, go test, golangci-lint
- **Generic**: Makefile-based projects with custom tooling

## Integration

### With Blueprint Plugin
- `/blueprint-generate-commands` - Creates project-specific versions of generic commands
- `/blueprint-work-order` - Create work orders before starting features

### With Git Plugin
- `/git:smartcommit` - Conventional commits integration
- `/git:quickpr` - Pull request creation

### With Testing Plugin
- `/test:quick` - Run unit tests after changes
- `/test:full` - Run full test suite before commit

## License

MIT

## Contributing

See the main claude-plugins repository for contribution guidelines.

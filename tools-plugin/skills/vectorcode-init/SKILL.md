---
name: vectorcode-init
description: |
  Initialize VectorCode with automatic configuration generation. Installs git hooks,
  generates vectorcode.include and vectorcode.exclude patterns based on project type.
  Use when user mentions "initialize VectorCode", "set up VectorCode", vectorcode.include,
  vectorcode.exclude, or VectorCode configuration.
---

# VectorCode Initialization

Automate VectorCode setup with intelligent repository analysis and configuration generation.

## Capabilities

This skill provides automatic VectorCode initialization for code repositories:

1. **Git Hook Installation** - Automatically installs VectorCode git hooks via `vectorcode init --hooks`
2. **Smart Include Patterns** - Analyzes repository structure to generate `vectorcode.include` with relevant file patterns
3. **Smart Exclude Patterns** - Creates `vectorcode.exclude` to skip common non-code files (build artifacts, dependencies, etc.)
4. **Project Type Detection** - Recognizes Python, Node.js, Rust, Go, Java, and other project types
5. **Configuration Validation** - Checks existing VectorCode setup and offers improvements

## When to Use

Invoke this skill when:
- User asks to "initialize VectorCode" or "set up VectorCode"
- User mentions "vectorcode init", "vectorcode hooks", or "vectorcode configuration"
- User wants to create `vectorcode.include` or `vectorcode.exclude` files
- User asks about VectorCode setup or configuration

## Workflow

### 1. Repository Analysis
- Detect project type(s) by examining file extensions and structure
- Identify source code directories (src/, lib/, app/, etc.)
- Find test directories and documentation folders
- Detect package manager and build tool configurations

### 2. Generate Include Patterns
Based on project type, create patterns like:
- **Python**: `**/*.py`, `**/pyproject.toml`, `**/setup.py`
- **Node.js/TypeScript**: `**/*.js`, `**/*.ts`, `**/*.jsx`, `**/*.tsx`, `**/package.json`
- **Rust**: `**/*.rs`, `**/Cargo.toml`
- **Go**: `**/*.go`, `**/go.mod`
- **Configuration**: `**/*.yaml`, `**/*.yml`, `**/*.json`, `**/*.toml`
- **Documentation**: `**/*.md`, `**/*.rst`

### 3. Generate Exclude Patterns
Common exclusions:
- Node.js: `node_modules/`, `dist/`, `build/`, `.next/`
- Python: `__pycache__/`, `*.pyc`, `.venv/`, `venv/`, `.pytest_cache/`
- Build artifacts: `target/`, `out/`, `bin/`, `obj/`
- Dependencies: `vendor/`, `third_party/`
- IDE/editor: `.vscode/`, `.idea/`, `*.swp`
- Version control: `.git/`
- Package managers: `.cargo/`, `.npm/`, `pip-cache/`

### 4. Install Git Hooks
Run `vectorcode init --hooks` to install:
- **post-commit** - Automatically index changed files after commits
- **post-merge** - Update index after merging branches
- **post-checkout** - Refresh index when switching branches

### 5. Validate Configuration
After setup:
- Check that hooks are executable
- Verify include/exclude files are syntactically valid
- Test with `vectorcode ls` to confirm project is indexed
- Suggest running `vectorcode vectorise` for initial indexing

## Response Templates

### Success Response
```markdown
✓ VectorCode initialized successfully!

**Git hooks installed:**
- post-commit → auto-index changed files
- post-merge → update index after merge
- post-checkout → refresh index on branch switch

**Configuration created:**
- `vectorcode.include` ({count} patterns for {project_types})
- `vectorcode.exclude` ({count} exclusion patterns)

**Next steps:**
1. Review patterns in `vectorcode.include` and `vectorcode.exclude`
2. Run `vectorcode vectorise .` to perform initial indexing
3. Use `vectorcode ls` to verify project is indexed
4. Query code with `vectorcode query "your search"`
```

### Existing Configuration Response
```markdown
VectorCode is already configured in this repository.

**Current setup:**
- Git hooks: {installed/not installed}
- Include patterns: {count} patterns in `vectorcode.include`
- Exclude patterns: {count} patterns in `vectorcode.exclude`

**Suggested improvements:**
{list any recommendations based on current project structure}

Would you like me to:
1. Add missing patterns for {detected project types}
2. Install/update git hooks
3. Regenerate configuration from scratch
```

### Custom Configuration Response
When user has specific requirements:
```markdown
I'll create a custom VectorCode configuration for your needs.

**Include patterns:** {custom patterns}
**Exclude patterns:** {custom patterns}

{explain reasoning for pattern choices based on user's requirements}
```

## Implementation Notes

### Pattern Syntax
VectorCode uses gitignore-style patterns:
- `**/*.py` - All Python files recursively
- `src/**/*.ts` - TypeScript files under src/
- `!important.log` - Negation (include despite previous exclusion)
- `*.test.js` - Glob patterns supported

### Priority Order
1. Exclude patterns are evaluated first
2. Include patterns can override excludes using `!` prefix
3. More specific patterns take precedence

### Git Hook Behavior
Hooks only index files matching include patterns and not matching exclude patterns.
This keeps the index focused and performant.

## Error Handling

### VectorCode Not Installed
If `vectorcode` command is not found:
```markdown
VectorCode is not installed. Install it with:

**Using Homebrew:**
```bash
brew install vectorcode
```

**Using cargo:**
```bash
cargo install vectorcode
```

Then re-run initialization.
```

### Permission Issues
If hooks cannot be made executable:
```markdown
Failed to make git hooks executable. Run manually:
```bash
chmod +x .git/hooks/post-commit
chmod +x .git/hooks/post-merge
chmod +x .git/hooks/post-checkout
```
```

## Related Skills
- **VectorCode Search** - Semantic code search using VectorCode
- **Git Repo Detection** - Identify repository information
- **Shell Expert** - Shell scripting and command execution

## References
- [VectorCode Documentation](https://github.com/davidyz/vectorcode)
- [VectorCode MCP Server](https://github.com/modelcontextprotocol/servers/tree/main/src/vectorcode)
- `.claude/skills/vectorcode-init/patterns.md` - Common pattern reference

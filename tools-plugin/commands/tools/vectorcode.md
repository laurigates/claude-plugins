---
description: Initialize VectorCode with automatic configuration generation
tags: [vectorcode, setup, initialization, git-hooks]
---

# VectorCode Initialization Command

Automatically set up VectorCode for the current repository with intelligent pattern detection.

## Task

Initialize VectorCode in the current repository by:

1. **Analyzing repository structure** to detect project type(s)
2. **Generating `vectorcode.include`** with relevant file patterns
3. **Generating `vectorcode.exclude`** with common exclusions
4. **Installing git hooks** via `vectorcode init --hooks`
5. **Validating the setup** and providing next steps

## Requirements

### Repository Analysis

Detect project types by examining:
- File extensions in root and common source directories
- Package manager configuration files (package.json, Cargo.toml, pyproject.toml, etc.)
- Build tool configurations (CMakeLists.txt, Makefile, build.gradle, etc.)
- Directory structure (src/, lib/, app/, tests/, docs/)

### Include Pattern Generation

Based on detected project types, create patterns following this priority:

**Source code files** (highest priority):
- Language-specific extensions (*.py, *.ts, *.rs, *.go, etc.)
- Restrict to source directories when possible (src/**/*.ts)

**Configuration files**:
- Project configuration (package.json, Cargo.toml, pyproject.toml)
- Build configuration (tsconfig.json, CMakeLists.txt)
- CI/CD configuration (.github/workflows/*.yml)

**Documentation** (optional, ask user):
- Markdown files (**/*.md)
- ReStructuredText (**/*.rst)

### Exclude Pattern Generation

Always exclude:
- **Dependencies**: node_modules/, vendor/, third_party/
- **Build outputs**: dist/, build/, target/, out/
- **Caches**: __pycache__/, .pytest_cache/, .npm/
- **IDE files**: .vscode/, .idea/, *.swp
- **Version control**: .git/
- **Logs**: *.log, logs/

Language-specific exclusions:
- **Python**: *.pyc, .venv/, venv/, *.egg-info/
- **Node.js**: .next/, .nuxt/, .parcel-cache/
- **Rust**: target/, *.rs.bk
- **Go**: vendor/, *.test

### Git Hook Installation

Run `vectorcode init --hooks` to install hooks:
- **post-commit**: Index changed files after commits
- **post-merge**: Update index after merging
- **post-checkout**: Refresh index when switching branches

Verify hooks are executable and located in `.git/hooks/`

### Validation

After setup:
- Confirm `vectorcode.include` and `vectorcode.exclude` exist
- Check git hooks are installed and executable
- Run `vectorcode ls` to verify configuration
- Provide example query command

## Output Format

### Success Case

```markdown
✓ VectorCode initialized successfully!

**Detected project type(s):** {Python, TypeScript, etc.}

**Git hooks installed:**
- `.git/hooks/post-commit` → auto-index changed files
- `.git/hooks/post-merge` → update index after merge
- `.git/hooks/post-checkout` → refresh index on branch switch

**Configuration created:**

`vectorcode.include` ({N} patterns):
```
{show first 10 patterns}
```

`vectorcode.exclude` ({N} patterns):
```
{show first 10 patterns}
```

**Next steps:**
1. Review patterns in `vectorcode.include` and `vectorcode.exclude`
2. Run initial indexing: `vectorcode vectorise .`
3. Verify setup: `vectorcode ls`
4. Try a search: `vectorcode query "authentication"`

**Customization:**
Edit `vectorcode.include` and `vectorcode.exclude` to add/remove patterns as needed.
```

### Existing Configuration Case

```markdown
VectorCode is already configured in this repository.

**Current setup:**
- Git hooks: {✓ installed / ✗ not installed}
- Include patterns: {N} patterns in `vectorcode.include`
- Exclude patterns: {N} patterns in `vectorcode.exclude`

**Detected project type(s):** {list}

{If patterns are missing or hooks not installed}
**Suggestions:**
- Missing include patterns for {detected types}
- Git hooks not installed (run `vectorcode init --hooks`)
- Consider adding {specific patterns}

Would you like me to:
1. Add missing patterns for detected project types
2. Install/update git hooks
3. Regenerate configuration from scratch
4. Leave configuration as-is
```

### Error Cases

**VectorCode not installed:**
```markdown
❌ VectorCode is not installed.

Install VectorCode:

**Using Homebrew:**
```bash
brew install vectorcode
```

**Using cargo:**
```bash
cargo install vectorcode
```

After installation, re-run this command.
```

**Not a git repository:**
```markdown
❌ Current directory is not a git repository.

Initialize git first:
```bash
git init
```

Then re-run VectorCode initialization.
```

**Permission issues:**
```markdown
⚠ Warning: Could not make git hooks executable.

Run manually:
```bash
chmod +x .git/hooks/post-commit
chmod +x .git/hooks/post-merge
chmod +x .git/hooks/post-checkout
```
```

## Implementation Steps

1. **Check Prerequisites**
   - Verify `vectorcode` command exists
   - Confirm current directory is a git repository
   - Check if configuration already exists

2. **Analyze Repository**
   - Scan for project type indicators
   - Identify source directories
   - Detect package managers and build tools

3. **Generate Include Patterns**
   - Start with language-specific patterns
   - Add configuration files
   - Optionally include documentation (ask user)
   - Write to `vectorcode.include`

4. **Generate Exclude Patterns**
   - Add universal exclusions (node_modules/, .git/)
   - Add language-specific exclusions
   - Add build artifact patterns
   - Write to `vectorcode.exclude`

5. **Install Git Hooks**
   - Run `vectorcode init --hooks`
   - Verify hooks are created
   - Ensure hooks are executable

6. **Validate Setup**
   - Test with `vectorcode ls`
   - Confirm hooks exist in `.git/hooks/`
   - Provide usage examples

7. **Report Results**
   - Show created configuration
   - List installed hooks
   - Provide next steps

## Edge Cases

### Monorepo
For monorepos with multiple projects:
- Detect all project types across subdirectories
- Create patterns that target specific project directories
- Example: `packages/*/src/**/*.ts`, `apps/*/src/**/*.tsx`

### Mixed Language Projects
- Combine patterns from all detected languages
- Don't duplicate overlapping patterns
- Prioritize more specific patterns

### Minimal Projects
For small projects without clear indicators:
- Default to common extensions (*.js, *.py, *.md)
- Include configuration files (*.json, *.yaml, *.toml)
- Ask user if they want to add language-specific patterns

### Large Repositories
For very large repos:
- Warn about initial indexing time
- Suggest starting with specific directories
- Recommend excluding large binary/data directories

## User Interaction

### When to Ask Questions

**Include documentation?**
Ask: "Would you like to include documentation files (*.md, *.rst) in the index?"
Default: Yes

**Include tests?**
Ask: "Would you like to include test files in the index?"
Default: Yes (helps with comprehensive code search)

**Custom patterns?**
Ask: "Do you want to add any custom include/exclude patterns?"
Default: No (proceed with auto-detected patterns)

### When Configuration Exists

Always ask before overwriting:
- "VectorCode is already configured. Would you like to:"
  1. Keep existing configuration
  2. Add missing patterns (recommended)
  3. Regenerate from scratch
  4. Just install hooks

## Testing

After setup, recommend these verification steps:
```bash
# List indexed files
vectorcode ls

# Check if specific file is indexed
vectorcode query "filename:your-file.py"

# Try semantic search
vectorcode query "error handling"

# Verify hooks are working
git commit --allow-empty -m "test"
# Should see VectorCode indexing output
```

## References

- VectorCode documentation: https://github.com/davidyz/vectorcode
- Pattern reference: `.claude/skills/vectorcode-init/patterns.md`
- VectorCode search skill: `.claude/skills/vectorcode-search/`

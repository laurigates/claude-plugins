# Project Discovery — Reference

Detailed manual workflow, error-handling guidance, best practices, and rationale for `project-discovery`. The script `scripts/discover.sh` covers the same ground; this reference is the fallback when the script is unavailable.

## Systematic Discovery Workflow (Manual Alternative)

When the script is unavailable, execute this 5-step systematic discovery process. Complete all steps before providing the summary.

---

### Step 1: Analyze git state

**Goal:** Understand version control state to prevent data loss and branch confusion.

**Commands to Run:**

```bash
# Current branch and tracking info
git branch --show-current
git status --short --branch

# Uncommitted changes summary
git status --porcelain | wc -l
git diff --stat
git diff --staged --stat

# Remote sync status
git rev-list --left-right --count HEAD...@{u} 2>/dev/null || echo "No tracking branch"

# Recent commit history (last 10 commits)
git log --oneline --decorate -n 10

# Check for conventional commits pattern
git log --oneline -n 20 | grep -E "^[a-f0-9]+ (feat|fix|docs|style|refactor|test|chore|build|ci|perf|revert)(\(.+\))?:"
```

**What to Extract:**
- Current branch name
- Number of uncommitted files (staged + unstaged)
- Number of commits ahead/behind remote
- Recent commit messages (look for patterns, conventional commits)
- Last commit author and date
- Whether working tree is clean

**Risk Flags:**
- ⚠️ Uncommitted changes exist (risk of data loss)
- ⚠️ Branch diverged from remote (conflicts possible)
- ⚠️ On main/master branch (should work on feature branch)
- ⚠️ Detached HEAD state (not on any branch)

---

### Step 2: Detect project type

**Goal:** Identify language, framework, and project structure to use correct tooling.

**Commands to Run:**

```bash
# Check for project manifests (determines language/ecosystem)
ls -la | grep -E "(package\.json|Cargo\.toml|pyproject\.toml|go\.mod|Gemfile|pom\.xml|build\.gradle|composer\.json|mix\.exs)"

# Detect monorepo structure
find . -maxdepth 3 -name "package.json" -o -name "Cargo.toml" -o -name "pyproject.toml" | head -20

# Check directory structure
ls -d */ 2>/dev/null | head -20

# Find entry points (main files)
find . -maxdepth 2 -name "main.*" -o -name "index.*" -o -name "app.*" -o -name "__init__.py" 2>/dev/null | head -10
```

**Project Manifest Detection:**

| File | Language/Ecosystem | Common Frameworks |
|------|-------------------|-------------------|
| `package.json` | JavaScript/TypeScript | React, Vue, Next.js, Express, Node |
| `Cargo.toml` | Rust | Actix, Rocket, Tokio |
| `pyproject.toml` | Python | Django, FastAPI, Flask |
| `go.mod` | Go | Gin, Echo, Fiber |
| `Gemfile` | Ruby | Rails, Sinatra |
| `pom.xml` / `build.gradle` | Java | Spring, Quarkus |
| `composer.json` | PHP | Laravel, Symfony |
| `mix.exs` | Elixir | Phoenix |

**What to Extract:**
- Primary language(s) and version(s)
- Framework detected (check package.json dependencies, Cargo.toml deps, etc.)
- Monorepo vs single-project (multiple manifests = monorepo)
- Common directory patterns (src/, lib/, tests/, docs/)
- Entry point files

**Additional Framework Detection:**

```bash
# JavaScript/TypeScript frameworks
grep -E "(react|vue|next|nuxt|svelte|angular|express|fastify|nest)" package.json 2>/dev/null

# Python frameworks
grep -E "(django|fastapi|flask|pyramid)" pyproject.toml 2>/dev/null

# Check for specific config files
ls | grep -E "(next\.config|vite\.config|webpack\.config|tsconfig|jest\.config|pytest\.ini|setup\.py)"
```

---

### Step 3: Discover development tooling

**Goal:** Identify build system, test framework, linters, and CI/CD to run correct commands.

**Commands to Run:**

```bash
# Build system detection
ls -la | grep -E "(Makefile|Justfile|package\.json|Cargo\.toml|pyproject\.toml)"

# Check package.json scripts (if JS/TS project)
jq -r '.scripts | keys[]' package.json 2>/dev/null | head -20

# Check Makefile targets
grep "^[a-zA-Z0-9_-]*:" Makefile 2>/dev/null | cut -d: -f1 | head -20

# Test framework detection
find . -maxdepth 3 -name "*test*" -o -name "*spec*" 2>/dev/null | grep -E "\.(js|ts|py|rs|go)$" | head -10

# Linter/formatter detection
ls -la | grep -E "(\.eslintrc|\.prettierrc|ruff\.toml|\.flake8|rustfmt\.toml|\.golangci)"

# Pre-commit hooks
ls -la .git/hooks/ 2>/dev/null | grep -v sample
cat .pre-commit-config.yaml 2>/dev/null | head -20

# CI/CD detection
ls -la .github/workflows/ 2>/dev/null | grep "\.yml"
ls -la .gitlab-ci.yml 2>/dev/null
ls -la .circleci/config.yml 2>/dev/null
```

**What to Extract:**

**Build System:**
- npm scripts (if package.json)
- Make targets (if Makefile)
- Cargo commands (if Rust)
- Python build tools (setuptools, poetry, hatchling)

**Test Framework:**
- Jest, Vitest, Mocha (JS/TS)
- pytest, unittest (Python)
- cargo test (Rust)
- go test (Go)
- Test file naming conventions

**Linters/Formatters:**
- ESLint, Prettier (JS/TS)
- ruff, black, flake8 (Python)
- clippy, rustfmt (Rust)
- golangci-lint (Go)

**Pre-commit Hooks:**
- Present or absent
- Configured tools (from .pre-commit-config.yaml)

**CI/CD:**
- GitHub Actions (list workflow files)
- GitLab CI
- CircleCI
- Other CI systems

---

### Step 4: Scan documentation

**Goal:** Understand project purpose and setup requirements from documentation.

**Commands to Run:**

```bash
# README first section (project purpose)
head -50 README.md 2>/dev/null

# Check for common documentation files
ls -la | grep -E "(README|CONTRIBUTING|CHANGELOG|LICENSE|ARCHITECTURE|docs/)"

# Look for setup/installation instructions in README
grep -A 10 -i "install\|setup\|getting started" README.md 2>/dev/null | head -30

# Check for documentation directory
ls -la docs/ 2>/dev/null | head -20
```

**What to Extract:**
- Project name and one-sentence description
- Primary purpose (web app, library, tool, etc.)
- Key features or capabilities
- Setup/installation instructions present?
- CONTRIBUTING.md exists? (indicates contributor guidance)
- Documentation directory structure

**Documentation Quality Indicators:**
- ✅ README with clear description and setup steps
- ✅ CONTRIBUTING.md (good for contributions)
- ✅ CHANGELOG.md (indicates release management)
- ✅ docs/ directory (comprehensive documentation)
- ⚠️ Missing README or minimal content
- ⚠️ No setup instructions

---

### Step 5: Summarize state and recommend next actions

**Goal:** Synthesize all findings into actionable summary with risk flags.

**Output Format Template:**

```markdown
# Project Discovery Summary

## 📊 Project Overview
- **Type**: [Language] / [Framework] / [Monorepo or Single-project]
- **Purpose**: [One-sentence description from README]
- **Entry Point**: [Main file or startup command]

## 🔀 Git State
- **Branch**: [current-branch-name]
- **Status**: [X files changed, Y staged, Z unstaged] OR [Working tree clean]
- **Remote Sync**: [X commits ahead, Y commits behind] OR [In sync with origin]
- **Last Commit**: [Hash] - [Message] by [Author] ([Time ago])
- **Commit Style**: [Conventional commits detected] OR [Free-form commits]

### ⚠️ Risk Flags
[List any risk flags found in Phase 1, or state "None - safe to proceed"]

## 🛠️ Development Tooling

### Build System
- [Build command: npm run build / cargo build / make / etc.]

### Test Framework
- [Test command: npm test / pytest / cargo test / etc.]
- [Test file location: tests/ or src/__tests__/ or *_test.rs]

### Code Quality
- **Linters**: [ESLint / ruff / clippy / etc.]
- **Formatters**: [Prettier / black / rustfmt / etc.]
- **Pre-commit Hooks**: [Configured] OR [Not configured]

### CI/CD
- [GitHub Actions: X workflows] OR [No CI/CD detected]
- [Workflows: build.yml, test.yml, deploy.yml]

## 📚 Documentation
- **README**: [Present with setup instructions] OR [Missing or minimal]
- **CONTRIBUTING**: [Present] OR [Not present]
- **Other Docs**: [docs/ directory, ARCHITECTURE.md, etc.]

## ✅ Recommendations

[Based on findings, provide 2-4 actionable recommendations, such as:]

1. **Commit uncommitted work** - You have X unstaged files that could be lost
2. **Create feature branch** - Currently on main; create a feature branch before making changes
3. **Pull latest changes** - X commits behind origin/main
4. **Run tests before changes** - Use `[test-command]` to establish baseline
5. **Review setup instructions** - Check README.md for dependencies and setup steps
6. **Safe to proceed** - Working tree clean, branch in sync, tooling detected

---

**Discovery completed in [time]. Ready to work with clear context.**
```

**Risk Flag Priority:**
- 🔴 **Critical**: Uncommitted changes + on main branch + behind remote
- 🟡 **Warning**: Any single risk flag (uncommitted changes, diverged branch, etc.)
- 🟢 **Safe**: Clean working tree, feature branch, in sync with remote

## Error Handling & Edge Cases

### Non-Git Directory
If `git status` fails (not a git repository):

```markdown
⚠️ **Not a Git Repository**

This skill is designed for git repositories only. This directory does not have a `.git` folder.

**Recommendations:**
1. Initialize git: `git init`
2. Or navigate to a git repository
3. Or use manual exploration tools (ls, find, etc.) for non-git projects
```

### Empty Repository
If git repo exists but has no commits:

```markdown
ℹ️ **Empty Git Repository**

This is a newly initialized git repository with no commits yet.

**Recommendations:**
1. Make initial commit to establish git history
2. Check README.md for project purpose (if exists)
3. Proceed with caution - no version history to reference
```

### Large Monorepo Performance
If discovery takes >30 seconds (e.g., huge monorepo):

```markdown
ℹ️ **Large Repository Detected**

Discovery is taking longer than expected. For large monorepos, consider:

1. **Focus on specific subdirectory**: Navigate to relevant sub-project first
2. **Use targeted exploration**: Ask specific questions rather than full discovery
3. **Check monorepo docs**: Often have READMEs explaining structure
```

### Missing Documentation
If no README.md or minimal content:

```markdown
⚠️ **Documentation Sparse**

No README.md found or content is minimal.

**Recommendations:**
1. Check commit messages for context about project purpose
2. Examine directory structure and entry points
3. Look for inline code comments
4. Ask user for project context if available
```

## Best Practices

### Before Making Any Changes
1. **Always run project discovery** when entering an unfamiliar codebase
2. **Check git state** to preserve uncommitted work
3. **Identify tooling** to use correct build/test commands
4. **Read README** for setup requirements and project conventions

### Discovery Efficiency
1. **Complete all 5 steps** even if early steps reveal issues (comprehensive context prevents follow-up questions)
2. **Highlight risk flags** prominently in summary
3. **Provide actionable recommendations** specific to the project state
4. **Keep discovery focused** (2-3 minutes; defer deep investigation to specialized skills)

### Integration with Workflow
1. **Discovery first, then action** - Establish context before editing files
2. **Update mental model** - If discovery reveals surprises, re-evaluate planned approach
3. **Respect git state** - Don't ignore risk flags; address them before proceeding

## Rationale: Why Systematic Discovery Matters

**Problem:** Claude often works on incomplete assumptions:
- Editing wrong branch
- Using incorrect build commands
- Overwriting uncommitted work
- Missing critical tooling (tests, linters)

**Solution:** Systematic orientation establishes:
- ✅ Clear git state (prevent data loss)
- ✅ Correct project type (use right tools)
- ✅ Available tooling (run proper commands)
- ✅ Risk awareness (flag dangerous states)

**Result:** Confident, accurate work on solid foundation rather than shaky assumptions.

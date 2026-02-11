---
model: haiku
created: 2025-12-17
modified: 2026-02-11
reviewed: 2026-02-08
description: Check and configure README.md with logo, badges, features, tech stack, and project structure
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch
argument-hint: "[--check-only] [--fix] [--style <minimal|standard|detailed>] [--badges <shields|custom>]"
name: configure-readme
---

## Context

- Project root: !`pwd`
- Project name: !`basename $(pwd)`
- README exists: !`find . -maxdepth 1 -name 'README.md' 2>/dev/null`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \) 2>/dev/null`
- Git remote: !`git remote get-url origin 2>/dev/null`
- License file: !`find . -maxdepth 1 -name 'LICENSE*' 2>/dev/null`
- Assets directory: !`find . -maxdepth 2 -type d \( -name 'assets' -o -name 'public' -o -name 'images' \) 2>/dev/null`
- Logo files: !`find . -maxdepth 3 -type f \( -name 'logo*' -o -name 'icon*' \) 2>/dev/null`

## Parameters

Parse from command arguments:

- `--check-only`: Report README compliance status without modifications (CI/CD mode)
- `--fix`: Apply fixes automatically without prompting
- `--style <minimal|standard|detailed>`: README detail level (default: standard)
- `--badges <shields|custom>`: Badge style preference (default: shields)
- `--no-logo`: Skip logo section even if assets exist

**Style Levels:**
- `minimal`: Title, description, badges, basic install/usage
- `standard`: Logo, badges, features, tech stack, getting started, license (recommended)
- `detailed`: All of standard plus: architecture diagram, API reference, contributing guide, changelog link

## Execution

Execute this README configuration workflow:

### Step 1: Detect project metadata

Read project metadata from the detected package files:

1. **package.json** (JavaScript/TypeScript): Extract name, description, version, license, repository, keywords
2. **pyproject.toml** (Python): Extract project name, description, version, license, keywords, URLs
3. **Cargo.toml** (Rust): Extract package name, description, version, license, repository, keywords
4. **go.mod** (Go): Extract module path for owner/repo

**Fallback detection** when no package file matches:
- Project name: directory name
- Description: first line of existing README or ask user
- Repository: git remote URL
- License: LICENSE file content

For detailed package file format examples, see [REFERENCE.md](REFERENCE.md).

### Step 2: Analyze current README state

Check existing README.md for these sections:

- [ ] Logo/icon present (centered image at top)
- [ ] Project title (h1)
- [ ] Description/tagline
- [ ] Badges row (license, version, CI status, coverage)
- [ ] Features section
- [ ] Tech Stack section
- [ ] Prerequisites section
- [ ] Installation instructions
- [ ] Usage examples
- [ ] Project structure
- [ ] Contributing guidelines
- [ ] License section

Discover logo/icon assets in common locations:
- `assets/logo.png`, `assets/icon.png`, `assets/logo.svg`
- `public/logo.png`, `public/icon.svg`
- `images/logo.png`, `docs/assets/logo.png`
- `.github/logo.png`, `.github/images/logo.png`

### Step 3: Generate compliance report

Print a section-by-section compliance report showing PASS/MISSING/PARTIAL status for each README section. Include content quality checks (code examples, command correctness, link validity).

If `--check-only` is set, stop here.

For the compliance report format, see [REFERENCE.md](REFERENCE.md).

### Step 4: Apply configuration (if --fix or user confirms)

Generate README.md following the standard template structure:

1. Centered logo section (if assets exist and `--no-logo` not set)
2. Project title and tagline
3. Badge row with shields.io URLs
4. Features section with key highlights
5. Tech Stack table
6. Getting Started (prerequisites, installation, usage)
7. Project Structure
8. Development commands
9. Contributing section
10. License section

For the full README template and badge URL patterns, see [REFERENCE.md](REFERENCE.md).

### Step 5: Handle logo and assets

If no logo exists but user wants one:

1. Check for existing assets in standard locations
2. Suggest creating a simple text-based placeholder or using emoji heading
3. Create assets directory if needed: `mkdir -p assets`
4. Suggest tools: Shields.io for custom badges, Simple Icons for technology icons

### Step 6: Detect project commands

Auto-detect project commands based on package manager/build tool:

| Package Manager | Install | Run | Test | Build |
|----------------|---------|-----|------|-------|
| npm/bun (package.json) | Read `scripts` from package.json | `npm run dev` | `npm test` | `npm run build` |
| uv/poetry (pyproject.toml) | `uv sync` / `poetry install` | `uv run python -m pkg` | `uv run pytest` | - |
| cargo (Cargo.toml) | `cargo build` | `cargo run` | `cargo test` | `cargo build --release` |
| go (go.mod) | `go build` | `go run .` | `go test ./...` | `go build` |

### Step 7: Generate project structure

Run `tree -L 2 -I 'node_modules|target|__pycache__|.git|dist|build' --dirsfirst` to generate accurate project structure. Skip common generated directories (node_modules, vendor, target, dist, build, __pycache__, .pytest_cache, .git, .venv, venv).

### Step 8: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  readme: "2025.1"
  readme_style: "[minimal|standard|detailed]"
  readme_has_logo: true|false
  readme_badges: ["license", "stars", "ci", "version"]
```

### Step 9: Validate generated README

After generating README, validate:

1. Check for markdown syntax errors
2. Verify all links are accessible (warn only)
3. Ensure shields.io URLs are correctly formatted
4. Verify logo/image paths exist

### Step 10: Report configuration results

Print a summary of changes made, the README location, and recommended next steps (customize feature descriptions, add logo, run other configure commands).

For the results report format, see [REFERENCE.md](REFERENCE.md).

When `--style detailed` is specified, also include architecture section with mermaid diagram, API reference link, and changelog link. For detailed style templates, see [REFERENCE.md](REFERENCE.md).

## Output

Provide:
1. Compliance report with section-by-section status
2. Generated or updated README.md content
3. List of detected project metadata
4. Suggestions for improvement (logo, more features, etc.)

## See Also

- `/configure:docs` - Configure code documentation standards
- `/configure:github-pages` - Set up documentation hosting
- `/configure:all` - Run all compliance checks
- **readme-standards** skill for README templates and examples

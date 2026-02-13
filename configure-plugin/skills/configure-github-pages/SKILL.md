---
model: haiku
created: 2025-12-16
modified: 2026-02-11
reviewed: 2025-12-16
description: Check and configure GitHub Pages deployment
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--source <docs|site|custom>]"
name: configure-github-pages
---

# /configure:github-pages

Check and configure GitHub Pages deployment.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up GitHub Pages deployment for a documentation site | Configuring documentation standards or generators (`/configure:docs` instead) |
| Creating or updating a GitHub Actions workflow for Pages deployment | Debugging a failed GitHub Actions workflow (`/configure:workflows` instead) |
| Migrating from `peaceiris/actions-gh-pages` to official `actions/deploy-pages` | Editing documentation content or markdown files |
| Auditing Pages workflow for outdated action versions or missing permissions | Setting up a custom domain via DNS (manual repository settings) |
| Adding Pages deployment to a project with an existing doc generator | Configuring CI/CD workflows unrelated to documentation |

## Context

- GitHub workflows: !`find .github/workflows -maxdepth 1 \( -name '*doc*.yml' -o -name '*pages*.yml' \) 2>/dev/null`
- Documentation config: !`find . -maxdepth 1 \( -name 'mkdocs.yml' -o -name 'typedoc.json' -o -name 'docusaurus.config.*' \) 2>/dev/null`
- Docs directory: !`find . -maxdepth 1 -type d \( -name 'docs' -o -name 'site' \) 2>/dev/null`
- CNAME file: !`find . -maxdepth 1 -name 'CNAME' 2>/dev/null`
- Project standards: !`find . -maxdepth 1 -name '.project-standards.yaml' 2>/dev/null`

## Parameters

Parse from command arguments:

- `--check-only`: Report compliance status without modifications (CI/CD mode)
- `--fix`: Apply fixes automatically without prompting
- `--source <docs|site|custom>`: Override source directory detection

## Execution

Execute this GitHub Pages deployment configuration check:

### Step 1: Detect documentation state

Identify existing documentation configuration:

| Config File | Generator | Output Directory |
|-------------|-----------|------------------|
| `typedoc.json` | TypeDoc | `docs/` or configured |
| `mkdocs.yml` | MkDocs | `site/` |
| `docs/conf.py` | Sphinx | `docs/_build/html/` |
| `docusaurus.config.js` | Docusaurus | `build/` |
| `Cargo.toml` (with rustdoc) | rustdoc | `target/doc/` |
| None | Static | `docs/` |

If no documentation configured, report:
```
No documentation generator detected.

Consider running /configure:docs first to:
  - Set up documentation linting standards
  - Configure a documentation generator

Would you like to:
  [A] Configure documentation first (/configure:docs)
  [B] Set up static HTML hosting for existing docs/ directory
  [C] Skip - I'll configure docs later
```

### Step 2: Analyze existing workflow

Check for existing GitHub Pages workflows by searching for:
- `actions/deploy-pages`
- `actions/upload-pages-artifact`
- `peaceiris/actions-gh-pages`

Extract from existing workflow: current action versions, permissions, build steps, source directory.

### Step 3: Check compliance against standards

Validate GitHub Actions workflow against standards:

| Check | Standard | Severity |
|-------|----------|----------|
| `actions/deploy-pages` | v4+ | WARN if older |
| `actions/configure-pages` | v5+ | WARN if missing |
| `actions/upload-pages-artifact` | v3+ | WARN if older |
| Permissions | `pages: write`, `id-token: write` | FAIL if missing |
| Environment | `github-pages` | WARN if missing |
| Concurrency | Group defined | INFO |

### Step 4: Generate compliance report

Print a formatted compliance report:

```
GitHub Pages Compliance Report
==============================
Project: [name]

Documentation Status:
  Generator           [typedoc|mkdocs|sphinx|rustdoc|static|not configured]
  Source directory    [docs/|site/|custom]
  Build command       [detected command or "not configured"]

GitHub Pages Workflow:
  Workflow file       .github/workflows/docs.yml    [EXISTS | MISSING]

Workflow Checks (if exists):
  deploy-pages        v4                            [PASS | OUTDATED | MISSING]
  configure-pages     v5                            [PASS | MISSING]
  upload-artifact     v3                            [PASS | OUTDATED]
  Permissions         pages: write, id-token        [PASS | MISSING]
  Environment         github-pages                  [PASS | MISSING]

Overall: [X issues found]

Recommendations:
  [List specific fixes needed]
```

If `--check-only`, stop here.

### Step 5: Create or update workflow (if --fix or user confirms)

Create `.github/workflows/docs.yml` based on detected generator. Use the appropriate workflow template from [REFERENCE.md](REFERENCE.md):

- **TypeDoc**: Node.js setup, npm ci, npm run docs:build, upload `./docs`
- **MkDocs**: Python setup, pip install, mkdocs build, upload `./site`
- **Sphinx**: Python setup, pip install, make html, upload `./docs/_build/html`
- **rustdoc**: Rust toolchain, cargo doc, create index redirect, upload `./target/doc`
- **Static HTML**: Direct upload from `./docs` directory

All workflows include:
- Required permissions (`pages: write`, `id-token: write`)
- Concurrency group to prevent conflicts
- `workflow_dispatch` for manual triggers
- Path-based triggers for relevant source files

### Step 6: Update standards tracking

Update `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  github-pages: "2025.1"
  github-pages-generator: "[typedoc|mkdocs|sphinx|rustdoc|static]"
  github-pages-source: "[docs/|site/|custom]"
```

### Step 7: Print post-configuration instructions

```
GitHub Pages Configuration Complete
===================================

Workflow created: .github/workflows/docs.yml

Next Steps:
  1. Enable GitHub Pages in repository settings:
     Settings -> Pages -> Source: GitHub Actions

  2. Push to main branch to trigger deployment:
     git add .github/workflows/docs.yml
     git commit -m "ci(docs): add GitHub Pages deployment workflow"
     git push

  3. After deployment, your docs will be available at:
     https://OWNER.github.io/REPO/

Optional:
  - Add custom domain: Create CNAME file with your domain
  - Protect deployment: Configure environment protection rules
```

For detailed workflow templates, see [REFERENCE.md](REFERENCE.md).

## Output

Provide:
1. Compliance report with documentation and workflow status
2. List of changes made (if --fix) or proposed (if interactive)
3. Post-configuration instructions
4. URL where docs will be deployed

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:github-pages --check-only` |
| Auto-fix all issues | `/configure:github-pages --fix` |
| Check Pages workflow exists | `find .github/workflows -name '*pages*' -o -name '*doc*' 2>/dev/null` |
| Check Pages action versions | `grep -E 'deploy-pages|upload-pages-artifact|configure-pages' .github/workflows/*.yml` |
| Verify Pages enabled | `gh api repos/{owner}/{repo}/pages --jq '.status'` |
| Check deployment status | `gh api repos/{owner}/{repo}/pages/builds --jq '.[0].status'` |

## See Also

- `/configure:docs` - Set up documentation standards and generators
- `/configure:workflows` - GitHub Actions workflow standards
- `/configure:all` - Run all compliance checks
- `/configure:status` - Quick compliance overview

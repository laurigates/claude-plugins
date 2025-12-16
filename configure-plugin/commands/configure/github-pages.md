---
description: Check and configure GitHub Pages deployment
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--source <docs|site|custom>]"
---

## Context

- GitHub workflows: !`ls -la .github/workflows/*doc*.yml .github/workflows/*pages*.yml 2>/dev/null || echo "None found"`
- Documentation config: !`ls -la mkdocs.yml typedoc.json docs/conf.py docusaurus.config.* 2>/dev/null || echo "None found"`
- Docs directory: !`ls -d docs/ site/ 2>/dev/null || echo "Not found"`
- CNAME file: !`ls -la CNAME 2>/dev/null || echo "None found"`
- FVH standards: !`ls -la .fvh-standards.yaml 2>/dev/null || echo "None found"`

## Parameters

Parse from command arguments:

- `--check-only`: Report compliance status without modifications (CI/CD mode)
- `--fix`: Apply fixes automatically without prompting
- `--source <docs|site|custom>`: Override source directory detection

## Your Task

Configure GitHub Pages deployment infrastructure for documentation.

### Phase 1: Documentation State Detection

Detect existing documentation configuration:

| Config File | Generator | Output Directory |
|-------------|-----------|------------------|
| `typedoc.json` | TypeDoc | `docs/` or configured |
| `mkdocs.yml` | MkDocs | `site/` |
| `docs/conf.py` | Sphinx | `docs/_build/html/` |
| `docusaurus.config.js` | Docusaurus | `build/` |
| `Cargo.toml` (with rustdoc) | rustdoc | `target/doc/` |
| None | Static | `docs/` |

**If no documentation configured:**
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

### Phase 2: Existing Workflow Analysis

Check for existing GitHub Pages workflows:

**Search patterns:**
- `actions/deploy-pages`
- `actions/upload-pages-artifact`
- `peaceiris/actions-gh-pages`

**Extract from existing workflow:**
- Current action versions
- Permissions configuration
- Build steps
- Source directory

### Phase 3: Compliance Analysis

Check GitHub Actions workflow against standards:

| Check | Standard | Severity |
|-------|----------|----------|
| `actions/deploy-pages` | v4+ | WARN if older |
| `actions/configure-pages` | v5+ | WARN if missing |
| `actions/upload-pages-artifact` | v3+ | WARN if older |
| Permissions | `pages: write`, `id-token: write` | FAIL if missing |
| Environment | `github-pages` | WARN if missing |
| Concurrency | Group defined | INFO |

### Phase 4: Compliance Report

```
GitHub Pages Compliance Report
==============================
Project: [name]

Documentation Status:
  Generator           [typedoc|mkdocs|sphinx|rustdoc|static|not configured]
  Source directory    [docs/|site/|custom]
  Build command       [detected command or "not configured"]

GitHub Pages Workflow:
  Workflow file       .github/workflows/docs.yml    [✅ EXISTS | ❌ MISSING]

Workflow Checks (if exists):
  deploy-pages        v4                            [✅ PASS | ⚠️ OUTDATED | ❌ MISSING]
  configure-pages     v5                            [✅ PASS | ⚠️ MISSING]
  upload-artifact     v3                            [✅ PASS | ⚠️ OUTDATED]
  Permissions         pages: write, id-token        [✅ PASS | ❌ MISSING]
  Environment         github-pages                  [✅ PASS | ⚠️ MISSING]

Overall: [X issues found]

Recommendations:
  [List specific fixes needed]
```

### Phase 5: Configuration (if --fix or user confirms)

Create `.github/workflows/docs.yml` based on detected generator:

#### TypeDoc (TypeScript/JavaScript)

```yaml
name: Documentation

on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'typedoc.json'
      - 'package.json'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'

      - run: npm ci
      - run: npm run docs:build

      - uses: actions/configure-pages@v5

      - uses: actions/upload-pages-artifact@v3
        with:
          path: './docs'

  deploy:
    needs: build
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

#### MkDocs (Python)

```yaml
name: Documentation

on:
  push:
    branches: [main]
    paths:
      - 'docs/**'
      - 'mkdocs.yml'
      - 'src/**/*.py'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        run: |
          pip install mkdocs mkdocs-material mkdocstrings[python]

      - run: mkdocs build

      - uses: actions/configure-pages@v5

      - uses: actions/upload-pages-artifact@v3
        with:
          path: './site'

  deploy:
    needs: build
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

#### Sphinx (Python)

```yaml
name: Documentation

on:
  push:
    branches: [main]
    paths:
      - 'docs/**'
      - 'src/**/*.py'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        run: |
          pip install sphinx sphinx-rtd-theme sphinx-autodoc-typehints myst-parser

      - name: Build documentation
        run: |
          cd docs && make html

      - uses: actions/configure-pages@v5

      - uses: actions/upload-pages-artifact@v3
        with:
          path: './docs/_build/html'

  deploy:
    needs: build
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

#### rustdoc (Rust)

```yaml
name: Documentation

on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'Cargo.toml'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: dtolnay/rust-toolchain@stable

      - name: Build documentation
        run: cargo doc --no-deps --all-features

      - name: Create index redirect
        run: |
          echo '<meta http-equiv="refresh" content="0; url=CRATE_NAME/index.html">' > target/doc/index.html

      - uses: actions/configure-pages@v5

      - uses: actions/upload-pages-artifact@v3
        with:
          path: './target/doc'

  deploy:
    needs: build
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

#### Static HTML (No Generator)

```yaml
name: Deploy GitHub Pages

on:
  push:
    branches: [main]
    paths:
      - 'docs/**'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/configure-pages@v5

      - uses: actions/upload-pages-artifact@v3
        with:
          path: './docs'

      - id: deployment
        uses: actions/deploy-pages@v4
```

### Phase 6: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  github-pages: "2025.1"
  github-pages-generator: "[typedoc|mkdocs|sphinx|rustdoc|static]"
  github-pages-source: "[docs/|site/|custom]"
```

### Phase 7: Post-Configuration Instructions

```
GitHub Pages Configuration Complete
===================================

Workflow created: .github/workflows/docs.yml

Next Steps:
  1. Enable GitHub Pages in repository settings:
     Settings → Pages → Source: GitHub Actions

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

## Output

Provide:
1. Compliance report with documentation and workflow status
2. List of changes made (if --fix) or proposed (if interactive)
3. Post-configuration instructions
4. URL where docs will be deployed

## See Also

- `/configure:docs` - Set up documentation standards and generators
- `/configure:workflows` - GitHub Actions workflow standards
- `/configure:all` - Run all compliance checks
- `/configure:status` - Quick compliance overview

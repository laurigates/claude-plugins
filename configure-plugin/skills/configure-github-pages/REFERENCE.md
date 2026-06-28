# GitHub Pages Reference

Workflow templates for deploying documentation to GitHub Pages.

## TypeDoc (TypeScript/JavaScript)

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
      - uses: actions/checkout@v6.0.3

      - uses: actions/setup-node@v6.4.0
        with:
          node-version: '24'
          cache: 'npm'

      - run: npm ci
      - run: npm run docs:build

      - uses: actions/configure-pages@v6

      - uses: actions/upload-pages-artifact@v5
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
        uses: actions/deploy-pages@v5
```

## MkDocs (Python)

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
      - uses: actions/checkout@v6.0.3

      - uses: actions/setup-python@v6.3.0
        with:
          python-version: '3.13'

      - name: Install dependencies
        run: |
          pip install mkdocs mkdocs-material mkdocstrings[python]

      - run: mkdocs build

      - uses: actions/configure-pages@v6

      - uses: actions/upload-pages-artifact@v5
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
        uses: actions/deploy-pages@v5
```

## Sphinx (Python)

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
      - uses: actions/checkout@v6.0.3

      - uses: actions/setup-python@v6.3.0
        with:
          python-version: '3.13'

      - name: Install dependencies
        run: |
          pip install sphinx sphinx-rtd-theme sphinx-autodoc-typehints myst-parser

      - name: Build documentation
        run: |
          cd docs && make html

      - uses: actions/configure-pages@v6

      - uses: actions/upload-pages-artifact@v5
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
        uses: actions/deploy-pages@v5
```

## rustdoc (Rust)

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
      - uses: actions/checkout@v6.0.3

      - uses: dtolnay/rust-toolchain@stable

      - name: Build documentation
        run: cargo doc --no-deps --all-features

      - name: Create index redirect
        run: |
          echo '<meta http-equiv="refresh" content="0; url=CRATE_NAME/index.html">' > target/doc/index.html

      - uses: actions/configure-pages@v6

      - uses: actions/upload-pages-artifact@v5
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
        uses: actions/deploy-pages@v5
```

## Static HTML (No Generator)

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
      - uses: actions/checkout@v6.0.3

      - uses: actions/configure-pages@v6

      - uses: actions/upload-pages-artifact@v5
        with:
          path: './docs'

      - id: deployment
        uses: actions/deploy-pages@v5
```

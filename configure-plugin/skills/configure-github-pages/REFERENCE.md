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
      - uses: actions/checkout@v6.1.0

      - uses: actions/setup-node@v6.5.0
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
        uses: actions/deploy-pages@v5.0.1
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
      - uses: actions/checkout@v6.1.0

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
        uses: actions/deploy-pages@v5.0.1
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
      - uses: actions/checkout@v6.1.0

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
        uses: actions/deploy-pages@v5.0.1
```

## rustdoc (Rust)

The build step installs the toolchain a root `rust-toolchain.toml` names, with its components. `dtolnay/rust-toolchain@stable` moves to every new release; `cargo doc` only fails on that if the job sets `RUSTDOCFLAGS="-D warnings"`, but a pinned file keeps the docs build on the same compiler as the rest of CI. See `rust-plugin:clippy-advanced` § Pin the toolchain for the file and the Renovate rule that bumps it.

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
      - uses: actions/checkout@v6.1.0

      - name: Install the pinned toolchain
        run: rustup toolchain install --no-self-update

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
        uses: actions/deploy-pages@v5.0.1
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
      - uses: actions/checkout@v6.1.0

      - uses: actions/configure-pages@v6

      - uses: actions/upload-pages-artifact@v5
        with:
          path: './docs'

      - id: deployment
        uses: actions/deploy-pages@v5.0.1
```

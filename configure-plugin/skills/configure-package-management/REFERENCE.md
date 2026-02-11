# Package Management Reference

Configuration templates, migration guides, and CI/CD integration for modern package managers.

## Python with uv

### Installation

```bash
# Via mise (recommended)
mise use uv@latest

# Or via curl
curl -LsSf https://astral.sh/uv/install.sh | sh

# Or via homebrew
brew install uv
```

### `pyproject.toml` Template

```toml
[project]
name = "my-project"
version = "0.1.0"
description = "Project description"
readme = "README.md"
requires-python = ">=3.12"
license = { text = "MIT" }
authors = [
    { name = "Your Name", email = "you@example.com" }
]
dependencies = [
    # Production dependencies
]

[project.optional-dependencies]
dev = [
    "ruff>=0.8.0",
    "basedpyright>=1.22.0",
]
test = [
    "pytest>=8.0",
    "pytest-cov>=6.0",
    "pytest-asyncio>=0.24",
]
docs = [
    "mkdocs>=1.6",
    "mkdocs-material>=9.5",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.uv]
dev-dependencies = [
    # Dev dependencies installed with `uv sync`
    "ruff>=0.8.0",
    "basedpyright>=1.22.0",
    "pytest>=8.0",
]

[tool.hatch.build.targets.wheel]
packages = ["src/my_project"]
```

### Common uv Commands

```bash
# Install dependencies
uv sync

# Add production dependency
uv add httpx

# Add dev dependency
uv add --group dev pytest

# Run script
uv run python script.py
uv run pytest

# Create virtual environment
uv venv

# Pin Python version
uv python pin 3.12

# Update dependencies
uv lock --upgrade
uv sync
```

### Python `.gitignore` Additions

```gitignore
# Python
.venv/
__pycache__/
*.pyc
.pytest_cache/
.ruff_cache/
dist/
*.egg-info/
```

## JavaScript/TypeScript with bun

### Installation

```bash
# Via mise (recommended)
mise use bun@latest

# Or via curl
curl -fsSL https://bun.sh/install | bash

# Or via homebrew
brew install bun
```

### `package.json` Template

```json
{
  "name": "my-project",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "bun run --watch src/index.ts",
    "build": "bun build src/index.ts --outdir dist",
    "test": "bun test",
    "lint": "biome check .",
    "lint:fix": "biome check --write .",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {},
  "devDependencies": {
    "@biomejs/biome": "^1.9.0",
    "@types/bun": "latest",
    "typescript": "^5.7.0"
  },
  "engines": {
    "bun": ">=1.1.0"
  }
}
```

### `tsconfig.json` Template

```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "skipLibCheck": true,
    "noEmit": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "types": ["bun-types"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

### Common bun Commands

```bash
# Install dependencies
bun install

# Add dependency
bun add zod

# Add dev dependency
bun add --dev @types/node

# Run script
bun run dev
bun run build

# Run TypeScript directly
bun src/index.ts

# Run tests
bun test

# Update dependencies
bun update
```

### JavaScript `.gitignore` Additions

```gitignore
# JavaScript/TypeScript
node_modules/
dist/
.turbo/
*.tsbuildinfo
```

## Migration: pip/poetry to uv

### Step 1: Install uv

```bash
mise use uv@latest
```

### Step 2: Initialize uv project

```bash
uv init
```

### Step 3: Migrate dependencies

From `requirements.txt`:
```bash
uv add -r requirements.txt
rm requirements.txt
```

From `poetry` (`pyproject.toml`):
```bash
# Extract dependencies from [tool.poetry.dependencies]
uv add httpx fastapi pydantic
uv add --group dev pytest ruff
```

### Step 4: Remove old files

```bash
rm -f requirements.txt requirements-dev.txt
rm -f Pipfile Pipfile.lock
rm -f poetry.lock
# Update pyproject.toml to remove [tool.poetry] section
```

### Step 5: Update CI/CD

```yaml
# GitHub Actions
- name: Install uv
  uses: astral-sh/setup-uv@v4

- name: Install dependencies
  run: uv sync

- name: Run tests
  run: uv run pytest
```

## Migration: npm/yarn/pnpm to bun

### Step 1: Install bun

```bash
mise use bun@latest
```

### Step 2: Remove old lock files

```bash
rm -rf node_modules
rm -f package-lock.json yarn.lock pnpm-lock.yaml
```

### Step 3: Install with bun

```bash
bun install
```

### Step 4: Update scripts

```json
{
  "scripts": {
    "dev": "bun run --watch src/index.ts",
    "build": "bun build src/index.ts --outdir dist",
    "test": "bun test"
  }
}
```

### Step 5: Update CI/CD

```yaml
# GitHub Actions
- name: Setup Bun
  uses: oven-sh/setup-bun@v2

- name: Install dependencies
  run: bun install

- name: Run tests
  run: bun test
```

## CI/CD Integration

### GitHub Actions - uv

```yaml
- name: Install uv
  uses: astral-sh/setup-uv@v4
  with:
    enable-cache: true

- name: Set up Python
  run: uv python install

- name: Install dependencies
  run: uv sync --all-extras

- name: Run tests
  run: uv run pytest
```

### GitHub Actions - bun

```yaml
- name: Setup Bun
  uses: oven-sh/setup-bun@v2
  with:
    bun-version: latest

- name: Install dependencies
  run: bun install --frozen-lockfile

- name: Run tests
  run: bun test
```

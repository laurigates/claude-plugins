# migration-patterns-plugin

Migration patterns for safe, zero-downtime transitions — both data migrations and tooling migrations.

## Skills

### Data Migration Patterns

| Skill | Description |
|-------|-------------|
| `dual-write` | Dual write (double write) pattern for keeping two data stores in sync during migration |
| `shadow-mode` | Shadow mode (dark launching) pattern for validating new systems under production traffic |

### Automated Tooling Migrations

| Skill | Invocation | Description |
|-------|-----------|-------------|
| `mypy-to-ty` | `/migration-patterns:mypy-to-ty` | Migrate from mypy to ty (Astral's type checker) |
| `black-to-ruff-format` | `/migration-patterns:black-to-ruff-format` | Migrate from black to ruff's formatter |
| `flake8-to-ruff` | `/migration-patterns:flake8-to-ruff` | Migrate from flake8/isort to ruff linting |
| `eslint-to-biome` | `/migration-patterns:eslint-to-biome` | Migrate from ESLint/Prettier to Biome |

## Data Migration Patterns

### Dual Write

During a database migration, the application writes to both the old and new system simultaneously. Reads can be compared between them to validate consistency before cutting over.

**Use when:** Migrating databases, switching storage backends, zero-downtime schema changes.

### Shadow Mode

Production requests are mirrored to a shadow deployment in the background. The shadow's responses are discarded (only the production response reaches the user), but responses are logged and compared to verify the new system behaves correctly under real traffic.

**Use when:** Validating replacement services, testing under production load, comparing response correctness.

### Combined Usage

These patterns are complementary tactics within the Strangler Fig migration strategy:
- Shadow mode validates read behavior
- Dual write keeps both systems in sync
- Together they enable safe, gradual migration with rollback at every phase

## Tooling Migration Skills

These skills automate common Python and TypeScript tooling migrations. Each migration:
- Audits the current state
- Updates `.pre-commit-config.yaml`
- Migrates configuration in `pyproject.toml` / `biome.json`
- Removes old dependencies
- Verifies the migration with a dry run

All four skills are invoked by `/configure:repo` via `AskUserQuestion` when the corresponding migration pattern is detected — they are not run automatically.

### mypy → ty

Replaces the `mirrors-mypy` pre-commit hook with a `repo: local` hook running `uvx ty check`. Converts `[tool.mypy]` config to `[tool.ty]`.

**Note:** `astral-sh/ty-pre-commit` does not yet exist; `repo: local` with `entry: uvx ty check` is the correct pattern.

### black → ruff-format

Replaces `psf/black` pre-commit hook with `ruff-format`. Migrates `[tool.black]` config to `[tool.ruff.format]`. Drop-in compatible output.

### flake8/isort → ruff

Replaces `pycqa/flake8` and `PyCQA/isort` hooks with a single `ruff` hook. Migrates rule configuration and import-sort settings.

### ESLint → Biome

Replaces `.eslintrc*` and Prettier configs with `biome.json`. Updates pre-commit hooks and `package.json` scripts. Flags plugins without Biome equivalents (e.g., `eslint-plugin-jsx-a11y`) for manual review.

## Integration with /configure:repo

The end-to-end driver `/configure:repo` detects migratable patterns and offers each migration via `AskUserQuestion`. Users choose which migrations to apply.

## Installation

Add to your Claude Code plugin registry or install from the marketplace.

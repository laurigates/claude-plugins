# Justfile Expert — Common Patterns

Task-shaped recipe patterns for [SKILL.md](../SKILL.md).

## Common Patterns

**Setup/Bootstrap Recipe**
```just
# Initial project setup
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing dependencies..."
    uv sync
    echo "Setting up pre-commit..."
    pre-commit install
    echo "Done!"
```

**Docker Integration**
```just
# Build container image
docker-build tag="latest":
    docker build -t {{project}}:{{tag}} .

# Run container
docker-run tag="latest" *args:
    docker run --rm -it {{project}}:{{tag}} {{args}}

# Push to registry
docker-push tag="latest":
    docker push {{registry}}/{{project}}:{{tag}}
```

**Database Operations**
```just
# Run database migrations
db-migrate:
    uv run alembic upgrade head

# Create new migration
db-revision message:
    uv run alembic revision --autogenerate -m "{{message}}"

# Reset database
db-reset:
    uv run alembic downgrade base
    uv run alembic upgrade head
```

**CI/CD Recipes**
```just
# Full CI check (lint + test + build)
ci: lint test build
    @echo "CI passed!"

# Release workflow
release version:
    git tag -a "v{{version}}" -m "Release {{version}}"
    git push origin "v{{version}}"
```

**Shared imports + modules: pass per-project values as recipe parameters**

When a monorepo registers submodules (`mod name 'path'`) whose justfiles `import`
a shared recipe file, hand per-project values to the shared recipes as recipe
**parameters** — not via a shared *variable*. Two `just` behaviours make the
variable approach fail:

- An `import` that *defaults* a variable a module also assigns is a **conflict**,
  not an override: `error: variable `X` has multiple definitions`.
- An imported recipe that references `{{X}}` is resolved at **load time**, so it
  forces *every* importing module to define `X` (else `error: variable `X` not
  defined`) — even modules that never run that recipe.

Passing the value as a recipe argument sidesteps both and keeps it explicit at the
call site:

```just
# shared.just — take the value as a parameter, not a shared variable
[private]
_flash bin:
    esptool ... 0x10000 build/{{bin}}.bin

# project justfile
import 'shared.just'
bin_name := "my-app"          # this module's own variable
flash: (_flash bin_name)      # pass it as an argument
```

# configure-workflows Reference

## Compliance Report Format

```
GitHub Workflows Compliance Report
======================================
Project Type: frontend (detected)
Workflows Directory: .github/workflows/ (found)

Workflow Status:
  container-build.yml   [PASS | MISSING]
  release-please.yml    [PASS | MISSING]
  test.yml              [PASS | MISSING]

container-build.yml Checks:
  checkout              v4              [PASS | OUTDATED]
  build-push-action     v6              [PASS | OUTDATED]
  Multi-platform        amd64,arm64     [PASS | MISSING]
  Caching               GHA cache       [PASS | MISSING]
  Permissions           Explicit        [PASS | MISSING]

release-please.yml Checks:
  Action version        v4              [PASS | OUTDATED]
  Token                 MY_RELEASE...   [PASS | WRONG TOKEN]

Missing Workflows:
  - test.yml (recommended for frontend projects)

Overall: X issues found
```

## Container Build Template

```yaml
name: Build Container

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  release:
    types: [published]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        if: github.event_name != 'pull_request'
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}

      - uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

## Test Workflow Template (Node)

```yaml
name: Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'

      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck
      - run: npm run test:coverage
```

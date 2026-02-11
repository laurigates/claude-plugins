# configure-reusable-workflows Reference

## Security Caller Workflows

### `.github/workflows/claude-security-secrets.yml`

```yaml
name: Claude Security - Secrets Detection

on:
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  scan:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-secrets.yml@main
    with:
      file-patterns: '**/*'
      max-turns: 5
    secrets: inherit
```

### `.github/workflows/claude-security-owasp.yml`

```yaml
name: Claude Security - OWASP

on:
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  scan:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-owasp.yml@main
    with:
      file-patterns: '**/*.{js,ts,jsx,tsx,py}'
      max-turns: 6
      fail-on-critical: true
    secrets: inherit
```

### `.github/workflows/claude-security-deps.yml`

```yaml
name: Claude Security - Dependencies

on:
  pull_request:
    branches: [main]
    paths:
      - 'package*.json'
      - 'requirements*.txt'
      - 'Pipfile*'
      - 'poetry.lock'
      - 'go.sum'
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  audit:
    uses: laurigates/claude-plugins/.github/workflows/reusable-security-deps.yml@main
    with:
      package-manager: 'auto'
      max-turns: 5
      fail-on-high: true
    secrets: inherit
```

## Quality Caller Workflows

### `.github/workflows/claude-quality-typescript.yml`

```yaml
name: Claude Quality - TypeScript

on:
  pull_request:
    branches: [main]
    paths:
      - '**/*.ts'
      - '**/*.tsx'
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  analyze:
    uses: laurigates/claude-plugins/.github/workflows/reusable-quality-typescript.yml@main
    with:
      file-patterns: '**/*.{ts,tsx}'
      max-turns: 6
      strict-mode: true
    secrets: inherit
```

### `.github/workflows/claude-quality-code-smell.yml`

```yaml
name: Claude Quality - Code Smell

on:
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  analyze:
    uses: laurigates/claude-plugins/.github/workflows/reusable-quality-code-smell.yml@main
    with:
      file-patterns: '**/*.{js,ts,jsx,tsx,py}'
      max-turns: 5
      severity-threshold: 'medium'
    secrets: inherit
```

### `.github/workflows/claude-quality-async.yml`

```yaml
name: Claude Quality - Async Patterns

on:
  pull_request:
    branches: [main]
    paths:
      - '**/*.ts'
      - '**/*.tsx'
      - '**/*.js'
      - '**/*.jsx'
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  analyze:
    uses: laurigates/claude-plugins/.github/workflows/reusable-quality-async.yml@main
    with:
      file-patterns: '**/*.{js,ts,jsx,tsx}'
      max-turns: 5
    secrets: inherit
```

## Accessibility Caller Workflows

### `.github/workflows/claude-a11y-wcag.yml`

```yaml
name: Claude A11y - WCAG

on:
  pull_request:
    branches: [main]
    paths:
      - '**/*.tsx'
      - '**/*.jsx'
      - '**/*.vue'
      - '**/*.svelte'
      - '**/*.html'
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  check:
    uses: laurigates/claude-plugins/.github/workflows/reusable-a11y-wcag.yml@main
    with:
      file-patterns: '**/*.{tsx,jsx,vue,svelte,html}'
      max-turns: 6
      wcag-level: 'AA'
    secrets: inherit
```

### `.github/workflows/claude-a11y-aria.yml`

```yaml
name: Claude A11y - ARIA

on:
  pull_request:
    branches: [main]
    paths:
      - '**/*.tsx'
      - '**/*.jsx'
      - '**/*.vue'
      - '**/*.svelte'
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  check:
    uses: laurigates/claude-plugins/.github/workflows/reusable-a11y-aria.yml@main
    with:
      file-patterns: '**/*.{tsx,jsx,vue,svelte}'
      max-turns: 5
    secrets: inherit
```

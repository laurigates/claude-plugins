# Common Permission Sets

Read when composing a `permissions.allow` list for a typical workflow (read-only, full git, CI/CD, testing/linting, security scanning) and you want a ready-made starting set.

## Read-Only Development

```json
{
  "permissions": {
    "allow": [
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git branch *)",
      "Bash(npm list *)",
      "Bash(bun pm ls *)"
    ]
  }
}
```

## Full Git Workflow

```json
{
  "permissions": {
    "allow": [
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git branch *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git push *)",
      "Bash(git pull *)",
      "Bash(git fetch *)",
      "Bash(git checkout *)",
      "Bash(git merge *)",
      "Bash(git rebase *)"
    ]
  }
}
```

## CI/CD Operations

```json
{
  "permissions": {
    "allow": [
      "Bash(gh pr *)",
      "Bash(gh run *)",
      "Bash(gh issue *)",
      "Bash(gh workflow *)"
    ]
  }
}
```

## Testing & Linting

```json
{
  "permissions": {
    "allow": [
      "Bash(bun test *)",
      "Bash(npm test *)",
      "Bash(vitest *)",
      "Bash(jest *)",
      "Bash(biome *)",
      "Bash(eslint *)",
      "Bash(prettier *)"
    ]
  }
}
```

## Security Scanning

```json
{
  "permissions": {
    "allow": [
      "Bash(pre-commit *)",
      "Bash(gitleaks *)",
      "Bash(trivy *)"
    ]
  }
}
```

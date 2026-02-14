---
model: haiku
name: skaffold-testing
description: |
  Container image validation with Skaffold test and verify stages. Covers container-structure-tests
  for image hygiene, custom tests for security scanning, and post-deployment verification.
  Use when configuring pre-deploy tests, security scans, or integration tests in Skaffold pipelines.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2025-12-23
modified: 2025-12-23
reviewed: 2025-12-23
---

# Skaffold Testing

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|-----------------------------------|
| Configuring container-structure-tests | Writing Dockerfiles (use container skills) |
| Adding security scans to Skaffold pipelines | General Skaffold build/deploy (use skaffold-development) |
| Setting up post-deploy verification | Unit testing application code |
| Validating image contents pre-deploy | Kubernetes manifest authoring |

## Testing Lifecycle

```
Build -> Test -> Deploy -> Verify
          ^                  ^
     Pre-deploy         Post-deploy
```

| Stage | Purpose | Runs During |
|-------|---------|-------------|
| **test** | Validate images before deployment | `dev`, `run`, `test` |
| **verify** | Validate deployment works correctly | `dev`, `run`, `verify` |

Failed tests block deployment. Use `--skip-tests` to bypass.

## Test Stage Overview

Two mechanisms for pre-deploy validation:

| Type | Purpose | Tool Required |
|------|---------|---------------|
| **structureTests** | Validate image contents | `container-structure-test` binary |
| **custom** | Run arbitrary commands | None (uses `$IMAGE` env var) |

## Container Structure Tests

Validate image contents without running the container.

### Configuration

```yaml
apiVersion: skaffold/v4beta11
kind: Config
test:
  - image: my-app
    structureTests:
      - ./tests/structure/*.yaml
    structureTestsArgs:
      - --driver=tar      # Faster, no Docker daemon needed
      - -q                # Quiet output
```

### Test Types Summary

| Type | Purpose | Key Fields |
|------|---------|------------|
| **commandTests** | Verify binaries work | `command`, `args`, `expectedOutput`, `exitCode` |
| **fileExistenceTests** | Verify files present/absent | `path`, `shouldExist`, `permissions`, `uid`, `gid` |
| **fileContentTests** | Validate file contents | `path`, `expectedContents`, `excludedContents` |
| **metadataTest** | Validate image config | `envVars`, `user`, `entrypoint`, `cmd`, `exposedPorts`, `workdir` |

## Custom Tests

Run arbitrary commands with access to built image via `$IMAGE` env var.

```yaml
test:
  - image: my-app
    custom:
      - command: grype $IMAGE --fail-on high --only-fixed
        timeoutSeconds: 300
      - command: trivy image --exit-code 1 --severity HIGH,CRITICAL $IMAGE
        timeoutSeconds: 300
```

### Dependencies

Control when tests re-run:

```yaml
custom:
  - command: ./scripts/integration-test.sh
    timeoutSeconds: 600
    dependencies:
      paths:
        - "src/**/*.go"
        - "go.mod"
      ignore:
        - "**/*_test.go"
```

## Verify Stage (Post-Deploy)

Run integration tests after deployment succeeds.

### Execution Modes

| Mode | Environment | Use Case |
|------|-------------|----------|
| `local` (default) | Docker on host | Quick tests, local dev |
| `kubernetesCluster` | K8s Job | Integration tests needing cluster access |

### Basic Configuration

```yaml
verify:
  - name: health-check
    container:
      name: curl-test
      image: curlimages/curl:latest
      command: ["/bin/sh"]
      args: ["-c", "curl -f http://my-app.default.svc:8080/health"]
    executionMode:
      kubernetesCluster: {}
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick structure test | `container-structure-test test --driver=tar -q --image $IMAGE --config tests/structure/security.yaml` |
| Security scan (critical only) | `grype $IMAGE --fail-on critical -q` |
| Skip tests in dev | `skaffold dev --skip-tests` |
| Run only tests | `skaffold test` |
| Run only verify | `skaffold verify` |
| CI with JUnit output | `container-structure-test test --image $IMAGE --config test.yaml --test-report junit.xml` |

## Quick Reference

### Container Structure Test Flags

| Flag | Description |
|------|-------------|
| `--driver=tar` | Use tar driver (faster, no Docker daemon) |
| `--driver=docker` | Use Docker driver (default) |
| `-q` | Quiet output |
| `--test-report FILE` | Generate test report |
| `--output json` | JSON output format |

### Skaffold Test Flags

| Flag | Description |
|------|-------------|
| `--skip-tests` | Skip test phase |
| `-p PROFILE` | Use specific profile |
| `--build-artifacts FILE` | Use pre-built artifacts |

### Custom Test Environment

| Variable | Description |
|----------|-------------|
| `$IMAGE` | Built image with tag/digest |

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

---
model: haiku
name: Skaffold Testing
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

## Testing Lifecycle

```
Build → Test → Deploy → Verify
         ↑               ↑
    Pre-deploy      Post-deploy
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

### Test Types

#### 1. Command Tests

Verify binaries work and produce expected output:

```yaml
schemaVersion: '2.0.0'
commandTests:
  - name: "Python version"
    command: "python"
    args: ["--version"]
    expectedOutput: ["Python 3.12"]
    exitCode: 0

  - name: "App starts without error"
    command: "/app/bin/server"
    args: ["--help"]
    exitCode: 0

  - name: "No root shell access"
    command: "sh"
    args: ["-c", "whoami"]
    excludedOutput: ["root"]
```

**Multi-line commands:**

```yaml
commandTests:
  - name: "Health check passes"
    command: "bash"
    args:
      - -c
      - |
        /app/bin/server &
        sleep 2
        curl -f http://localhost:8080/health
```

#### 2. File Existence Tests

Verify files present with correct permissions:

```yaml
fileExistenceTests:
  # Required files exist
  - name: "Config file present"
    path: /app/config.yaml
    shouldExist: true
    permissions: "-rw-r--r--"

  # Security: Sensitive files removed
  - name: "No .env file shipped"
    path: /app/.env
    shouldExist: false

  - name: "No git history shipped"
    path: /app/.git
    shouldExist: false

  # Correct ownership (non-root)
  - name: "App owned by appuser"
    path: /app
    shouldExist: true
    uid: 1000
    gid: 1000
```

#### 3. File Content Tests

Validate file contents with regex:

```yaml
fileContentTests:
  - name: "Logging configured correctly"
    path: /app/config.yaml
    expectedContents:
      - "level: info"
      - "format: json"
    excludedContents:
      - "level: debug"    # No debug in prod images
      - "password:"       # No hardcoded secrets

  - name: "Terraform checkpoint disabled"
    path: /root/.terraformrc
    expectedContents:
      - "disable_checkpoint = true"
```

#### 4. Metadata Test

Validate image configuration:

```yaml
metadataTest:
  # Environment variables set
  envVars:
    - key: NODE_ENV
      value: production
    - key: TZ
      value: UTC

  # Security: Non-root user
  user: appuser

  # Correct entrypoint
  entrypoint: ["/app/bin/server"]
  cmd: ["--config", "/app/config.yaml"]

  # Expected ports exposed
  exposedPorts: ["8080", "9090"]

  # Working directory set
  workdir: /app

  # Labels present
  labels:
    - key: org.opencontainers.image.source
      value: "https://github.com/.*"
      isRegex: true
```

## Custom Tests

Run arbitrary commands with access to built image.

### Security Scanning

```yaml
test:
  - image: my-app
    custom:
      # Vulnerability scanning with Grype
      - command: grype $IMAGE --fail-on high --only-fixed
        timeoutSeconds: 300

      # Alternative: Trivy
      - command: trivy image --exit-code 1 --severity HIGH,CRITICAL $IMAGE
        timeoutSeconds: 300

      # SBOM generation (doesn't fail, just generates)
      - command: syft $IMAGE -o spdx-json > sbom.json
        timeoutSeconds: 120
```

### Unit Tests Against Image

```yaml
test:
  - image: my-app
    custom:
      - command: docker run --rm $IMAGE npm test
        timeoutSeconds: 300
        dependencies:
          paths:
            - "src/**/*.ts"
            - "test/**/*.ts"
            - "package.json"
```

### Linting and Validation

```yaml
test:
  - image: my-app
    custom:
      # Dockerfile linting
      - command: hadolint Dockerfile
        dependencies:
          paths:
            - "Dockerfile"

      # Kubernetes manifest validation
      - command: kubeval k8s/*.yaml
        dependencies:
          paths:
            - "k8s/*.yaml"
```

### Dependencies Configuration

Control when tests re-run:

```yaml
custom:
  - command: ./scripts/integration-test.sh
    timeoutSeconds: 600
    dependencies:
      # Static paths - re-run when these change
      paths:
        - "src/**/*.go"
        - "go.mod"
        - "go.sum"
      # Ignore patterns
      ignore:
        - "**/*_test.go"

  # Dynamic dependencies from command
  - command: ./scripts/e2e-test.sh
    dependencies:
      command: echo '["test/e2e/**/*.ts"]'
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
apiVersion: skaffold/v4beta11
kind: Config
verify:
  # Health check with external image
  - name: health-check
    container:
      name: curl-test
      image: curlimages/curl:latest
      command: ["/bin/sh"]
      args: ["-c", "curl -f http://my-app.default.svc:8080/health"]
    executionMode:
      kubernetesCluster: {}

  # Integration tests with built image
  - name: integration-tests
    container:
      name: integration-tests
      image: my-app-tests  # Built by Skaffold
      command: ["npm", "run", "test:integration"]
    executionMode:
      kubernetesCluster: {}
```

### Kubernetes Job Customization

```yaml
verify:
  - name: integration-tests
    container:
      name: tests
      image: my-app-tests
    executionMode:
      kubernetesCluster:
        # Inline overrides (kubectl run --overrides style)
        overrides: |
          {
            "spec": {
              "serviceAccountName": "test-runner",
              "activeDeadlineSeconds": 600
            }
          }

  - name: e2e-tests
    container:
      name: e2e
      image: my-e2e-tests
    executionMode:
      kubernetesCluster:
        # Use custom Job manifest
        jobManifestPath: ./k8s/e2e-job.yaml
```

### E2E Job Manifest Example

```yaml
# k8s/e2e-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: e2e-tests
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 900
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: e2e-runner
      containers: []  # Skaffold replaces this
      volumes:
        - name: test-config
          configMap:
            name: e2e-config
```

## Profile-Based Testing

### Quick vs Thorough

```yaml
test:
  - image: my-app
    structureTests:
      - ./tests/structure/security.yaml
      - ./tests/structure/config.yaml
    custom:
      - command: grype $IMAGE --fail-on critical
        timeoutSeconds: 120

profiles:
  # Fast tests for dev loop
  - name: quick
    test:
      - image: my-app
        structureTests:
          - ./tests/structure/security.yaml  # Essential only
        # No vulnerability scan - too slow

  # Thorough tests for CI
  - name: ci
    test:
      - image: my-app
        structureTests:
          - ./tests/structure/*.yaml
        custom:
          - command: grype $IMAGE --fail-on high --only-fixed
            timeoutSeconds: 600
          - command: trivy image --scanners vuln,secret $IMAGE
            timeoutSeconds: 300
    verify:
      - name: full-integration
        container:
          name: integration
          image: my-app-tests
        executionMode:
          kubernetesCluster: {}
```

## Essential Security Tests

Every production image should validate:

### Security Structure Test Template

```yaml
# tests/structure/security.yaml
schemaVersion: '2.0.0'

# 1. Non-root user
metadataTest:
  user: "appuser"  # or numeric UID like "1000"

# 2. No sensitive files shipped
fileExistenceTests:
  - name: "No .env file"
    path: /app/.env
    shouldExist: false
  - name: "No .git directory"
    path: /app/.git
    shouldExist: false
  - name: "No private keys"
    path: /app/id_rsa
    shouldExist: false
  - name: "No credentials files"
    path: /app/credentials.json
    shouldExist: false

# 3. No secrets in config files
fileContentTests:
  - name: "No hardcoded passwords"
    path: /app/config.yaml
    excludedContents:
      - "password:"
      - "secret:"
      - "api_key:"
      - "BEGIN RSA PRIVATE KEY"
      - "BEGIN OPENSSH PRIVATE KEY"

# 4. Correct file permissions
fileExistenceTests:
  - name: "Config not world-writable"
    path: /app/config.yaml
    shouldExist: true
    permissions: "-rw-r--r--"

# 5. Shell access removed (distroless)
commandTests:
  - name: "No shell available"
    command: "/bin/sh"
    exitCode: 127  # Command not found
```

## Directory Structure

```
project/
├── skaffold.yaml
├── Dockerfile
├── tests/
│   ├── structure/
│   │   ├── security.yaml      # Security validations
│   │   ├── config.yaml        # Configuration checks
│   │   └── runtime.yaml       # Runtime requirements
│   └── integration/
│       └── run.sh             # Integration test script
└── k8s/
    ├── deployment.yaml
    └── e2e-job.yaml           # Verify stage job manifest
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

## Common Patterns

### Fail Fast in CI

```yaml
test:
  - image: my-app
    custom:
      # Security gate first - fastest to fail
      - command: grype $IMAGE --fail-on critical -q
        timeoutSeconds: 60
    structureTests:
      # Then structure tests
      - ./tests/structure/security.yaml
```

### Multi-Architecture Testing

```yaml
test:
  - image: my-app-amd64
    structureTests:
      - ./tests/structure/*.yaml
  - image: my-app-arm64
    structureTests:
      - ./tests/structure/*.yaml
```

### Test Image Separately from App

```yaml
build:
  artifacts:
    - image: my-app
    - image: my-app-tests
      docker:
        dockerfile: Dockerfile.test

test:
  - image: my-app
    structureTests:
      - ./tests/structure/*.yaml

verify:
  - name: integration
    container:
      name: tests
      image: my-app-tests
    executionMode:
      kubernetesCluster: {}
```

## Troubleshooting

### container-structure-test not found

```bash
# Install on macOS
brew install container-structure-test

# Install on Linux
curl -LO https://storage.googleapis.com/container-structure-test/latest/container-structure-test-linux-amd64
chmod +x container-structure-test-linux-amd64
sudo mv container-structure-test-linux-amd64 /usr/local/bin/container-structure-test
```

### Tests Pass Locally, Fail in CI

Check:
1. Docker daemon running in CI
2. Use `--driver=tar` if no daemon available
3. Image exists (not just built, but accessible)

### Verify Tests Can't Reach Services

In Kubernetes mode:
1. Verify test pod can resolve service DNS
2. Check NetworkPolicies allow test pod traffic
3. Ensure services are ready before tests run (use `statusCheck: true`)

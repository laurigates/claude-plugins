# Skaffold Testing - Reference

Detailed reference material for Skaffold testing and verification stages.

## Container Structure Test Types - Detailed Examples

### Command Tests

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

### File Existence Tests

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

### File Content Tests

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

### Metadata Test

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

## Custom Test Patterns

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

## Verify Stage - Advanced Configuration

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

## Essential Security Tests Template

Every production image should validate:

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

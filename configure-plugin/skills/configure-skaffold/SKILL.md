---
model: haiku
created: 2025-12-16
modified: 2026-02-10
reviewed: 2025-12-16
description: Check and configure Skaffold for project standards
allowed-tools: Glob, Grep, Read, Write, Edit, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix]"
name: configure-skaffold
---

# /configure:skaffold

Check and configure Skaffold against project standards.

## Context

- K8s/Helm directories: !`find . -maxdepth 1 -type d \( -name 'k8s' -o -name 'helm' \) 2>/dev/null`
- Skaffold config: !`test -f skaffold.yaml && echo "EXISTS" || echo "MISSING"`
- Skaffold API version: !`head -5 skaffold.yaml 2>/dev/null | grep apiVersion`
- Port forward config: !`grep -A2 'portForward' skaffold.yaml 2>/dev/null | grep address`
- Profiles defined: !`grep 'name:' skaffold.yaml 2>/dev/null | grep -v 'metadata' | head -10`
- Generate-secrets script: !`test -f scripts/generate-secrets.sh && echo "EXISTS" || echo "MISSING"`
- Dotenvx available: !`command -v dotenvx 2>/dev/null && echo "INSTALLED" || echo "MISSING"`
- Project standards: !`head -20 .project-standards.yaml 2>/dev/null`

**Skills referenced**: `skaffold-standards`, `container-development`, `skaffold-orbstack`

**Applicability**: Only for projects with Kubernetes deployment (k8s/, helm/ directories)

## Parameters

Parse these from `$ARGUMENTS`:

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply fixes automatically |

## Version Checking

**CRITICAL**: Before configuring Skaffold, verify latest versions:

1. **Skaffold**: Check [skaffold.dev](https://skaffold.dev/) or [GitHub releases](https://github.com/GoogleContainerTools/skaffold/releases)
2. **API version**: Current recommended is `skaffold/v4beta13`
3. **dotenvx**: Check [dotenvx.com](https://dotenvx.com/) for latest patterns

Use WebSearch or WebFetch to verify current Skaffold version and API version.

## Execution

Execute this Skaffold compliance check:

### Step 1: Check applicability

Check for `k8s/` or `helm/` directories. If neither is found, report "SKIP: Skaffold not applicable (no Kubernetes manifests)" and stop. If found, proceed to check for `skaffold.yaml`.

### Step 2: Parse configuration

Read `skaffold.yaml` and extract:
- API version
- Build configuration (local.push, useBuildkit)
- Deploy configuration (kubeContext, statusCheck)
- Port forwarding (addresses)
- Profiles defined
- Hooks (dotenvx integration)

### Step 3: Analyze compliance

Check each setting against these standards:

| Check | Standard | Severity |
|-------|----------|----------|
| API version | `skaffold/v4beta13` | WARN if older |
| local.push | `false` | FAIL if true |
| portForward.address | `127.0.0.1` | FAIL if missing/0.0.0.0 |
| useBuildkit | `true` | WARN if false |
| kubeContext | `orbstack` | INFO (recommended for local dev) |
| dotenvx hooks | Build or deploy hooks | INFO (recommended for secrets) |

**Security-critical**: Port forwarding MUST bind to localhost only (`127.0.0.1`). Never allow `0.0.0.0` or missing address.

**Recommended settings**:
- `db-only` or `services-only` profile for local dev workflow
- `statusCheck: true` with reasonable deadline (180s for init containers)
- `tolerateFailuresUntilDeadline: true` for graceful pod initialization
- JSON log parsing for structured application logs
- dotenvx hooks for secrets generation from .env files

### Step 4: Report results

Print a compliance report with:
- Skaffold file location and API version
- Each configuration check result (PASS/WARN/FAIL)
- Profiles found
- Scripts status (generate-secrets.sh)
- Overall compliance status

If `--check-only`, stop here.

### Step 5: Apply fixes (if --fix or user confirms)

1. **Missing skaffold.yaml**: Create from standard template in [REFERENCE.md](REFERENCE.md)
2. **Security issues**: Fix port forwarding addresses to `127.0.0.1`
3. **Missing profiles**: Add `db-only` profile template
4. **Outdated API**: Update apiVersion to v4beta13
5. **Missing dotenvx hooks**: Add secrets generation hook
6. **Missing scripts**: Create `scripts/generate-secrets.sh` from template in [REFERENCE.md](REFERENCE.md)
7. **Missing kubeContext**: Add `orbstack` for local development

### Step 6: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  skaffold: "2025.1"
```

## Security Note

Port forwarding without `address: 127.0.0.1` exposes services to the network. This is a **FAIL** condition that should always be fixed.

For the standard Skaffold template, dotenvx integration patterns, and generate-secrets script template, see [REFERENCE.md](REFERENCE.md).

## See Also

- `/configure:dockerfile` - Container configuration
- `/configure:all` - Run all compliance checks
- `skaffold-standards` skill - Skaffold patterns

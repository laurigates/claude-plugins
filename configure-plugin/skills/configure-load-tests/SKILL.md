---
model: haiku
created: 2025-12-16
modified: 2026-02-10
reviewed: 2025-12-16
description: Check and configure load and performance testing with k6, Artillery, or Locust
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--framework <k6|artillery|locust>]"
name: configure-load-tests
---

# /configure:load-tests

Check and configure load and performance testing infrastructure for stress testing, benchmarking, and capacity planning.

## Context

- Project root: !`pwd`
- k6 tests: !`find . -maxdepth 3 \( -name '*.k6.js' -o -name '*.k6.ts' \) 2>/dev/null`
- Load test directory: !`find . -maxdepth 2 -type d -name 'load' 2>/dev/null`
- Artillery config: !`find . -maxdepth 2 -name 'artillery.yml' -o -name 'artillery.yaml' 2>/dev/null`
- Locust files: !`find . -maxdepth 2 -name 'locustfile.py' 2>/dev/null`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' \) 2>/dev/null`
- CI workflows: !`find .github/workflows -maxdepth 1 -name '*load*' -o -name '*perf*' 2>/dev/null`
- k6 binary: !`command -v k6 2>/dev/null`

## Parameters

Parse from `$ARGUMENTS`:

- `--check-only`: Report load testing compliance status without modifications
- `--fix`: Apply all fixes automatically without prompting
- `--framework <k6|artillery|locust>`: Override framework detection

**Framework preferences:**

| Framework | Best For |
|-----------|----------|
| k6 (recommended) | Complex scenarios, CI/CD integration, TypeScript support |
| Artillery | Quick YAML configs, simple API testing |
| Locust | Python teams, distributed testing, custom behavior |

## Execution

Execute this load testing configuration check:

### Step 1: Detect existing load testing infrastructure

Read the context values above and identify:

| Indicator | Component | Status |
|-----------|-----------|--------|
| `k6` binary or `@grafana/k6` | k6 | Installed |
| `*.k6.js` or `load-tests/` | k6 tests | Present |
| `artillery.yml` | Artillery config | Present |
| `locustfile.py` | Locust tests | Present |
| `.github/workflows/*load*` | CI integration | Configured |

If `--framework` flag is set, use that framework regardless of detection.

### Step 2: Analyze current load testing setup

Check for complete setup coverage:

**Installation:** k6 installed (binary or npm), TypeScript support if applicable.

**Test Scenarios:** Check which test types exist:
- Smoke tests (minimal load validation)
- Load tests (normal load)
- Stress tests (peak load)
- Spike tests (burst traffic)
- Soak tests (endurance)

**Configuration:** Thresholds, environment-specific configs, data files.

**Reporting:** Console output, JSON/HTML reports, trend tracking.

**CI/CD:** GitHub Actions workflow, scheduled runs, PR gate.

### Step 3: Generate compliance report

Print a compliance report covering:
- Framework installation status and version
- Test scenario coverage (smoke, load, stress, spike, soak)
- Threshold configuration (response time, error rate)
- Environment configuration (staging, production)
- CI/CD integration (workflow, schedule, PR gate)
- Reporting setup (console, JSON, HTML, Grafana Cloud)

End with overall issue count and recommendations.

If `--check-only` is set, stop here.

### Step 4: Configure load testing framework (if --fix or user confirms)

Apply configuration using templates from [REFERENCE.md](REFERENCE.md):

1. Install k6 (or chosen framework)
2. Create directory structure: `tests/load/{config,scenarios,helpers,data}`
3. Create base configuration with shared thresholds and headers
4. Create test scenarios (smoke, load, stress, spike)
5. Add npm/package scripts for running tests

### Step 5: Configure CI/CD integration

1. Create `.github/workflows/load-tests.yml` with:
   - Smoke tests on PRs
   - Full load tests via workflow_dispatch
   - Scheduled weekly runs
   - Results artifact upload
2. Add HTML reporting via k6-reporter
3. Use templates from [REFERENCE.md](REFERENCE.md)

### Step 6: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  load_tests: "2025.1"
  load_tests_framework: "k6"
  load_tests_scenarios: ["smoke", "load", "stress"]
  load_tests_ci: true
  load_tests_thresholds: true
```

### Step 7: Print final compliance report

Print a summary of framework installed, scenarios created, scripts added, CI/CD configured, thresholds set, and next steps for the user.

For detailed k6 test scripts, CI workflow templates, and reporting configuration, see [REFERENCE.md](REFERENCE.md).

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--framework <framework>` | Override framework (k6, artillery, locust) |

## Examples

```bash
# Check compliance and offer fixes
/configure:load-tests

# Check only, no modifications
/configure:load-tests --check-only

# Auto-fix all issues
/configure:load-tests --fix

# Force specific framework
/configure:load-tests --fix --framework artillery
```

## Error Handling

- **k6 not installed**: Provide installation instructions for platform
- **No target URL**: Prompt for BASE_URL configuration
- **Docker not available**: Suggest local app startup
- **CI secrets missing**: Provide setup instructions for k6 Cloud

## See Also

- `/configure:tests` - Unit testing configuration
- `/configure:integration-tests` - Integration testing
- `/configure:api-tests` - API contract testing
- `/configure:all` - Run all compliance checks
- **k6 documentation**: https://k6.io/docs
- **k6 examples**: https://github.com/grafana/k6/tree/master/examples
- **Grafana k6 Cloud**: https://grafana.com/products/cloud/k6

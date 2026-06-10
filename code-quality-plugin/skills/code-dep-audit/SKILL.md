---
name: code-dep-audit
description: Audit dependencies for security vulnerabilities, outdated packages, and license compliance. Use when checking supply chain security, preparing releases, or responding to CVEs.
args: "[--type <security|outdated|licenses|all>] [--fix]"
argument-hint: --type security to check vulnerabilities, --type outdated for updates
allowed-tools: Bash(bash *), Bash(npm audit *), Bash(npx *), Bash(pip-audit *), Bash(cargo audit *), Bash(pip *), Bash(uv *), Bash(cargo *), Read, Grep, Glob, TodoWrite
created: 2026-04-10
modified: 2026-06-10
reviewed: 2026-06-10
---

# /code:dep-audit

Audit project dependencies for vulnerabilities and freshness.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Checking for known CVEs in dependencies | Setting up security scanning CI → /configure:security |
| Preparing a release and need dep health check | Looking for code-level security issues → /code:antipatterns |
| Responding to a vulnerability advisory | Reviewing code quality → /code:review |
| Auditing license compliance | Configuring dependency management → /configure:package-management |

## Context

- Package files: !`find . -maxdepth 1 \( -name "package.json" -o -name "package-lock.json" -o -name "yarn.lock" -o -name "bun.lockb" -o -name "pyproject.toml" -o -name "requirements.txt" -o -name "Cargo.toml" -o -name "Cargo.lock" -o -name "go.mod" -o -name "go.sum" \) -type f`

## Parameters

- `--type`: Audit type — `security` (default), `outdated`, `licenses`, or `all`
- `--fix`: Automatically apply safe updates for vulnerable packages

## Execution

Execute this dependency audit workflow:

### Step 1: Gather audit data

Run the extracted audit script — it detects the package ecosystem, dispatches the matching audit tool, and parses severity / outdated / license-denylist counts into a structured rollup:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/code-dep-audit.sh" --home-dir "$HOME" --project-dir "$(pwd)"
```

Parse `STATUS=` and `ISSUES:` from the output. The script emits `ECOSYSTEM=`, `AUDIT_TOOL=`, `VULN_CRITICAL/HIGH/MEDIUM/LOW`, `OUTDATED_COUNT=`, `LICENSE_ISSUES=`, and an `ISSUES:` block flagging GPL/AGPL licenses (problematic in proprietary projects). When `AUDIT_TOOL_AVAILABLE=false`, the ecosystem's audit tool is missing — run it via the command in `AUDIT_TOOL=` if installed, otherwise suggest `/configure:security`.

### Step 2: Apply fixes (if --fix)

For security vulnerabilities:
1. Run `npm audit fix` / `cargo update` / `pip install --upgrade` for safe updates
2. Report which vulnerabilities were fixed and which require manual intervention
3. Run project tests to verify nothing broke

### Step 3: Report results

Print summary:
```
Dependency Audit Report
=======================
Ecosystem: [JS/TS | Python | Rust | Go]

Security:
  Critical: N
  High: N
  Medium: N
  Low: N

Outdated: N packages behind latest
License issues: N flagged

Top actions:
1. [package@version] - critical CVE-XXXX-XXXX
2. [package] - N major versions behind
```

## Post-Actions

- If many vulnerabilities found → suggest `npm audit fix` or equivalent
- If audit tools not configured → suggest `/configure:security`
- If outdated packages found → suggest updating in a separate branch

## Agentic Optimizations

| Context | Command |
|---|---|
| Quick JS audit | `npm audit --json` |
| Python audit | `pip-audit --format json` |
| Rust audit | `cargo audit --json` |
| Outdated check | `npm outdated --json` |
| License check | `npx license-checker --json --summary` |
| CI mode | `npm audit --audit-level=critical --json` |

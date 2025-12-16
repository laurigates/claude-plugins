---
name: bun-lockfile-update
description: |
  Update Bun lockfiles (bun.lockb) with proper dependency management. Covers
  bun update, bun install, lockfile regeneration, and security audits.
  Use when user mentions bun lockfile, bun update, bun.lockb, updating Bun
  dependencies, or resolving Bun lockfile conflicts.
---

# Bun Lockfile Update

Comprehensive guidance for updating Bun lockfiles (`bun.lockb`) with proper dependency management practices.

## When to Use

Use this skill automatically when:
- User requests lockfile update or dependency refresh
- User mentions outdated dependencies or security vulnerabilities
- User wants to update specific packages or all dependencies
- Lockfile conflicts occur during git operations
- User needs to audit or verify dependency integrity

## Core Commands

### Update All Dependencies
```bash
# Update all dependencies to latest versions (respecting semver ranges in package.json)
bun update

# Update all dependencies AND modify package.json to latest versions
bun update --latest
```

### Update Specific Dependencies
```bash
# Update specific package(s) to latest compatible version
bun update <package-name>
bun update <package1> <package2>

# Update specific package to latest version (ignoring semver range)
bun update --latest <package-name>
```

### Regenerate Lockfile
```bash
# Regenerate lockfile from package.json (clean install)
rm bun.lockb
bun install

# Or force regeneration
bun install --force
```

## Update Strategies

### 1. Safe Update (Recommended)
Respects semver ranges in `package.json`:

```bash
# Updates within semver constraints (^1.2.3 → 1.x.x, ~1.2.3 → 1.2.x)
bun update

# Review changes
git diff bun.lockb package.json

# Test thoroughly
bun test
bun run build
```

**When to use:**
- Regular maintenance updates
- CI/CD pipeline updates
- Production deployments
- When stability is priority

### 2. Aggressive Update
Updates to absolute latest versions:

```bash
# Updates AND modifies package.json to latest versions
bun update --latest

# Review ALL changes carefully
git diff bun.lockb package.json

# Test exhaustively (breaking changes likely)
bun test
bun run build
bun run lint
```

**When to use:**
- Major version upgrades
- Modernization efforts
- Security vulnerability fixes requiring latest versions
- Development/experimental branches

### 3. Selective Update
Updates specific packages only:

```bash
# Update one critical package
bun update lodash

# Update multiple related packages
bun update @types/node @types/react @types/react-dom

# Update to latest version (ignore semver)
bun update --latest typescript
```

**When to use:**
- Targeted security patches
- Specific bug fixes
- Gradual migration strategies
- Reducing blast radius of changes

## Best Practices Workflow

### Pre-Update Checklist
1. **Commit current state:** Ensure clean working directory
   ```bash
   git status
   git add .
   git commit -m "chore: checkpoint before dependency update"
   ```

2. **Check for outdated packages:**
   ```bash
   bun outdated
   ```

3. **Review security advisories:**
   ```bash
   bun audit
   ```

### Update Process
1. **Choose strategy:** Safe, aggressive, or selective
2. **Execute update command**
3. **Review changes:**
   ```bash
   git diff bun.lockb package.json
   ```

### Post-Update Validation
1. **Verify installation:**
   ```bash
   rm -rf node_modules
   bun install
   ```

2. **Run test suite:**
   ```bash
   bun test
   ```

3. **Run build:**
   ```bash
   bun run build
   ```

4. **Run linting:**
   ```bash
   bun run lint
   ```

5. **Check bundle size:**
   ```bash
   bun run build --analyze  # If available
   ```

6. **Test application manually:**
   - Critical user flows
   - Edge cases
   - Cross-browser testing (if web app)

### Commit Changes
```bash
# For safe updates
git add bun.lockb
git commit -m "chore(deps): update dependencies

Updates all dependencies to latest compatible versions.
All tests passing."

# For aggressive updates
git add bun.lockb package.json
git commit -m "chore(deps): upgrade dependencies to latest

BREAKING CHANGES:
- Updated React 17 → 18
- Updated TypeScript 4.9 → 5.3
- Updated Vite 4 → 5

See CHANGELOG for migration notes.
All tests passing."
```

## Common Scenarios

### Scenario 1: Regular Maintenance
**Goal:** Keep dependencies fresh without breaking changes

```bash
# Weekly/monthly routine
bun update
bun test
git add bun.lockb
git commit -m "chore(deps): update dependencies"
```

### Scenario 2: Security Vulnerability
**Goal:** Patch specific vulnerable package

```bash
# Check vulnerability report
bun audit

# Update vulnerable package to latest (may require --latest)
bun update --latest <vulnerable-package>

# Verify fix
bun audit

# Test and commit
bun test
git add bun.lockb package.json
git commit -m "fix(deps): patch security vulnerability in <package>

Fixes: CVE-XXXX-XXXXX"
```

### Scenario 3: Major Version Upgrade
**Goal:** Migrate to new major version of framework/library

```bash
# 1. Create feature branch
git checkout -b chore/upgrade-react-18

# 2. Update target package
bun update --latest react react-dom

# 3. Update related packages
bun update --latest @types/react @types/react-dom

# 4. Review breaking changes documentation
# (Check official migration guide)

# 5. Update code for breaking changes
# (Fix deprecated APIs, adjust imports, etc.)

# 6. Run comprehensive tests
bun test
bun run build
bun run lint

# 7. Manual testing
# (Test all critical flows)

# 8. Commit and create PR
git add .
git commit -m "chore(deps): upgrade React 17 → 18

BREAKING CHANGES:
- Automatic batching changes render behavior
- Updated ReactDOM.render to createRoot
- Removed IE 11 support

See docs/migration/react-18.md for details."
```

### Scenario 4: Lockfile Conflict Resolution
**Goal:** Resolve merge conflict in `bun.lockb`

```bash
# 1. Accept either version (doesn't matter which)
git checkout --theirs bun.lockb  # Or --ours

# 2. Regenerate lockfile from package.json
rm bun.lockb
bun install

# 3. Verify installation
bun test

# 4. Commit resolution
git add bun.lockb
git commit -m "chore: resolve lockfile merge conflict"
```

### Scenario 5: Dependency Audit & Cleanup
**Goal:** Remove unused dependencies and update remaining

```bash
# 1. Audit dependencies
bun pm ls  # List installed packages

# 2. Check for unused dependencies
npx depcheck  # Or manual review of package.json

# 3. Remove unused packages
bun remove <unused-package>

# 4. Update remaining dependencies
bun update

# 5. Verify everything still works
bun test
bun run build
```

## Bun-Specific Features

### Binary Lockfile
- Bun uses binary lockfile format (`bun.lockb`)
- Much faster to parse than `package-lock.json` or `yarn.lock`
- Not human-readable (use `bun pm ls` to inspect)

### Workspaces
```bash
# Update all workspace packages
bun update

# Update specific workspace
bun update --filter <workspace-name>
```

### Compatibility
```bash
# Install with npm/yarn compatibility
bun install --backend=npm

# Generate package-lock.json for compatibility
bun install --lockfile-only
```

## Troubleshooting

### Lockfile Corruption
```bash
# Symptoms: Install errors, checksum mismatches
# Solution: Regenerate lockfile
rm bun.lockb
bun install
```

### Peer Dependency Conflicts
```bash
# Symptoms: Peer dependency warnings during install
# Solution: Update peer dependencies or use --force
bun install --force

# Or resolve conflicts manually in package.json
```

### Cache Issues
```bash
# Clear Bun cache
rm -rf ~/.bun/install/cache

# Reinstall
rm -rf node_modules bun.lockb
bun install
```

### Version Mismatch Errors
```bash
# Symptoms: Package version doesn't match expectations
# Solution: Verify package.json and regenerate lockfile
cat package.json  # Check version ranges
rm bun.lockb
bun install
```

## Security Best Practices

### Regular Audits
```bash
# Check for vulnerabilities
bun audit

# Get detailed report
bun audit --json > audit-report.json
```

### Automated Updates
```bash
# Use Renovate or Dependabot for automated PRs
# Configure in .github/renovate.json or .github/dependabot.yml
```

### Review Dependencies
```bash
# Before updating, review package reputation
# Check npm package page, GitHub stars, maintenance status
bun pm ls <package-name>
```

### Lockfile Integrity
```bash
# Verify lockfile matches package.json
bun install --frozen-lockfile  # CI/CD
bun install --production --frozen-lockfile  # Production
```

## Integration with CI/CD

### GitHub Actions Example
```yaml
- name: Install dependencies
  run: bun install --frozen-lockfile

- name: Run tests
  run: bun test

- name: Update lockfile (scheduled job)
  run: |
    bun update
    bun test
  if: github.event_name == 'schedule'
```

### Pre-commit Hook
```bash
# .husky/pre-commit or similar
#!/bin/sh
bun install --frozen-lockfile
bun test
```

## Related Skills

- **Node.js Development** - Modern JavaScript/TypeScript patterns with Bun
- **Git Branch PR Workflow** - Managing dependency update PRs
- **GitHub Actions Inspection** - Debugging CI/CD lockfile issues

## References

- [Bun CLI Documentation](https://bun.sh/docs/cli/install)
- [Bun Package Manager](https://bun.sh/docs/cli/pm)
- [Bun Workspaces](https://bun.sh/docs/install/workspaces)
- [Semantic Versioning](https://semver.org/)

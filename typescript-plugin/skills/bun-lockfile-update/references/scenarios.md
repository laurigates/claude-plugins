# bun-lockfile-update — Common Scenarios

Open this for the end-to-end command sequence of a specific update situation:
routine maintenance, a security patch, a major version upgrade, a `bun.lock`
merge conflict, or a dependency audit and cleanup.

## Common Scenarios

### Scenario 1: Regular Maintenance
**Goal:** Keep dependencies fresh without breaking changes

```bash
# Weekly/monthly routine
bun update
bun test
git add bun.lock
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
git add bun.lock package.json
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
**Goal:** Resolve merge conflict in `bun.lock`

```bash
# 1. Accept either version (doesn't matter which)
git checkout --theirs bun.lock  # Or --ours

# 2. Regenerate lockfile from package.json
rm bun.lock
bun install

# 3. Verify installation
bun test

# 4. Commit resolution
git add bun.lock
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

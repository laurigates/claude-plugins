# bun-lockfile-update — Troubleshooting

Open this when `bun install` fails after an update: checksum mismatches, peer
dependency warnings, cache problems, or versions that do not match expectations.

## Troubleshooting

### Lockfile Corruption
```bash
# Symptoms: Install errors, checksum mismatches
# Solution: Regenerate lockfile
rm bun.lock
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
rm -rf node_modules bun.lock
bun install
```

### Version Mismatch Errors
```bash
# Symptoms: Package version doesn't match expectations
# Solution: Verify package.json and regenerate lockfile
cat package.json  # Check version ranges
rm bun.lock
bun install
```

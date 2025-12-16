# Protected File Patterns Reference

Comprehensive reference of file patterns managed by release-please automation.

## Hard Protection (Permission System Blocks)

These files are **completely blocked** from Edit/Write/MultiEdit operations via Claude Code's permission system in `~/.claude/settings.json`:

### CHANGELOG Files
```
Pattern: **/CHANGELOG.md
Regex:   .*CHANGELOG\.md$
```

**Locations in dotfiles:**
- `/Users/lgates/.local/share/chezmoi/plugins/dotfiles-core/CHANGELOG.md`
- `/Users/lgates/.local/share/chezmoi/plugins/dotfiles-toolkit/CHANGELOG.md`
- Any future plugin CHANGELOG.md files

**Protection Level:** HARD (cannot be bypassed by Claude)
**Read Access:** Allowed (for analysis)
**Why Protected:** Release-please generates these from conventional commits

## Soft Protection (Skill Detection & Warning)

These files trigger **warnings** when version fields are modified:

### Node.js / npm

**File:** `package.json`

**Version Pattern:**
```json
{
  "version": "1.2.3",
  ...
}
```

**Detection Regex:** `"version"\s*:\s*"[\d]+\.[\d]+\.[\d]+"`

**Other Protected Fields (if present):**
- None - only version field is release-please managed

**Safe to Edit:**
- `dependencies`, `devDependencies`
- `scripts`
- `name`, `description`, `keywords`
- All other fields

---

### Python / uv / pip

**File:** `pyproject.toml`

**Version Pattern:**
```toml
[project]
version = "0.2.0"
```

**Detection Regex:** `^\s*version\s*=\s*"[\d]+\.[\d]+\.[\d]+"`

**Example Location:**
- `/Users/lgates/.local/share/chezmoi/plugins/dotfiles-ui-hooks/hooks/voice-notify/pyproject.toml`

**Safe to Edit:**
- `[project.dependencies]`
- `[project.optional-dependencies]`
- `[build-system]`
- `name`, `description`, `authors`
- All other fields

---

### Rust / Cargo

**File:** `Cargo.toml`

**Version Pattern:**
```toml
[package]
name = "my-crate"
version = "0.1.0"
```

**Detection Regex:** `^\s*version\s*=\s*"[\d]+\.[\d]+\.[\d]+"`

**Safe to Edit:**
- `[dependencies]`
- `[dev-dependencies]`
- `[[bin]]`, `[lib]`
- `authors`, `description`, `license`
- All other fields

---

### Claude Code Plugins

**File:** `.claude-plugin/plugin.json`

**Version Pattern:**
```json
{
  "name": "dotfiles-core",
  "version": "3.0.0",
  ...
}
```

**Detection Regex:** `"version"\s*:\s*"[\d]+\.[\d]+\.[\d]+"`

**Example Locations:**
- `/Users/lgates/.local/share/chezmoi/plugins/dotfiles-core/.claude-plugin/plugin.json`
- `/Users/lgates/.local/share/chezmoi/plugins/dotfiles-toolkit/.claude-plugin/plugin.json`
- `/Users/lgates/.local/share/chezmoi/plugins/*/. claude-plugin/plugin.json`

**Safe to Edit:**
- `displayName`, `description`
- `publisher`, `categories`
- `agents`, `commands`, `skills`
- All other fields

---

### Maven / Java

**File:** `pom.xml`

**Version Pattern:**
```xml
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>my-app</artifactId>
  <version>1.0.0</version>
</project>
```

**Detection Regex:** `<version>[\d]+\.[\d]+\.[\d]+</version>`

**Safe to Edit:**
- `<dependencies>`
- `<build>`, `<plugins>`
- `<properties>`
- All other elements

---

### Gradle / Kotlin

**File:** `build.gradle` or `build.gradle.kts`

**Version Pattern:**
```gradle
version = '1.0.0'
```

**Detection Regex:** `version\s*=\s*['"][\d]+\.[\d]+\.[\d]+['"]`

**Safe to Edit:**
- `dependencies { }`
- `plugins { }`
- `repositories { }`
- All other blocks

---

### Dart / Flutter

**File:** `pubspec.yaml`

**Version Pattern:**
```yaml
name: my_app
version: 1.0.0+1
```

**Detection Regex:** `^version:\s*[\d]+\.[\d]+\.[\d]+`

**Safe to Edit:**
- `dependencies:`
- `dev_dependencies:`
- `flutter:`, `assets:`
- All other fields

---

## Marketplace Registry

**File:** `.claude-plugin/marketplace.json`

**Pattern:** Contains version references for all registered plugins

**Protection Level:** SOFT (version references only)

**Why:** This file aggregates plugin versions and shouldn't be manually edited as release-please updates it via plugin updates

---

## Release Workflow Files

**Potential Files (if present):**
- `.github/workflows/release-please.yml`
- `.github/workflows/release.yml`
- `.release-please-config.json`
- `.release-please-manifest.json`

**Protection:** Skill warns when editing these to ensure workflow integrity

**Safe to Edit:**
- Workflow trigger conditions
- Additional CI steps
- Notification configurations

**Unsafe to Edit:**
- release-please action versions
- Manifest configuration paths
- Release type configurations (without understanding impact)

---

## Detection Strategy by Request Type

### "Update dependencies"
- ✅ Allow: editing `dependencies` sections
- ⚠️ Warn: if version field is in diff
- 🛑 Block: CHANGELOG.md modifications

### "Bump version to X.Y.Z"
- ⚠️ Intercept: suggest conventional commit instead
- 📚 Explain: release-please workflow
- 🔧 Offer: create conventional commit template

### "Fix all linting issues"
- ✅ Allow: most file modifications
- ⚠️ Skip: version fields if touched
- 🛑 Block: CHANGELOG.md formatting

### "Refactor codebase"
- ✅ Allow: code file modifications
- ⚠️ Warn: if package manifests in scope
- 🛑 Block: CHANGELOG.md, explain workaround

### "Update documentation"
- ✅ Allow: README.md, docs/ folder
- 🛑 Block: CHANGELOG.md modifications
- 💡 Suggest: include in PR description instead

---

## Pattern Matching Priority

When detecting protected files, use this priority order:

1. **Exact filename match** (highest priority)
   - `CHANGELOG.md` → Hard block

2. **Extension + content pattern**
   - `.json` + `"version":` → Check if package.json or plugin.json

3. **Path pattern**
   - `**/.claude-plugin/plugin.json` → Plugin manifest
   - `**/pyproject.toml` → Python project

4. **Content-only pattern** (lowest priority)
   - Any file with version field regex → Soft warn

---

## False Positive Handling

Some files may contain version-like strings but aren't managed by release-please:

### Safe Version References
- `package-lock.json` (auto-generated, safe to regenerate)
- `Cargo.lock` (auto-generated, safe to regenerate)
- `uv.lock` (auto-generated, safe to regenerate)
- `VERSION.txt` (if not in release-please config)
- Documentation examples with version numbers
- Test fixtures with hardcoded versions

### Detection Heuristic
```
if file ends with ".lock" or "-lock.json":
    → Skip version field detection
if file in docs/ or examples/ or tests/:
    → Lower warning severity
if version number in comment or string literal:
    → Context-dependent (check if it's a config value)
```

---

## Regex Patterns Summary

For implementation reference:

```regex
# CHANGELOG.md (hard block)
.*CHANGELOG\.md$

# package.json version
"version"\s*:\s*"[\d]+\.[\d]+\.[\d]+(-.+)?"

# pyproject.toml version
^\s*version\s*=\s*"[\d]+\.[\d]+\.[\d]+(-.+)?"

# Cargo.toml version
^\s*version\s*=\s*"[\d]+\.[\d]+\.[\d]+(-.+)?"

# pom.xml version
<version>[\d]+\.[\d]+\.[\d]+(-.+)?</version>

# build.gradle version
version\s*=\s*['"][\d]+\.[\d]+\.[\d]+(-.+)?['"]

# pubspec.yaml version
^version:\s*[\d]+\.[\d]+\.[\d]+(\+\d+)?

# plugin.json version (same as package.json)
"version"\s*:\s*"[\d]+\.[\d]+\.[\d]+(-.+)?"
```

**Note:** Patterns include optional pre-release suffixes (`-alpha`, `-beta.1`, etc.) and build metadata.

---

## Testing Protection

To verify patterns are working:

```bash
# Test CHANGELOG.md hard block
echo "test" >> CHANGELOG.md  # Should be blocked by permission system

# Test version field detection (skill should warn)
# Via Claude: "Update the version in package.json to 2.0.0"

# Test conventional commit suggestion
# Via Claude: "Bump the version for a new feature"
```

---

## Customization

To add additional protected patterns:

1. **For hard blocks:** Edit `~/.claude/settings.json` deny rules
2. **For soft blocks:** Update this patterns.md file with new detection logic
3. **For custom workflows:** Extend SKILL.md response templates

---

## Pattern Maintenance

This patterns reference should be updated when:

- New package managers are added to your projects
- Claude Code introduces new manifest types
- Release-please adds support for new file formats
- Project structure changes significantly
- False positives/negatives are discovered

**Last updated:** 2025-10-29
**Maintained by:** Dotfiles release-please-protection skill

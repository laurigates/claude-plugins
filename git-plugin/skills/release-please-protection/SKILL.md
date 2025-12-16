---
name: release-please-protection
description: |
  Detects and prevents manual edits to release-please managed files (CHANGELOG.md,
  version fields in package.json, pyproject.toml, Cargo.toml). Provides conventional
  commit templates. Use when editing changelogs, version bumps, release files, or
  when user mentions "release", "changelog", "version bump", or "conventional commits".
---

# Release-Please Protection

Automatically detects and prevents manual edits to release-please managed files across all projects.

## Overview

This skill provides proactive detection and warnings for files managed by Google's release-please automation tool. It helps prevent merge conflicts and workflow disruptions by identifying problematic edit attempts before they occur.

## When This Skill Activates

The skill automatically activates in these scenarios:

1. **Direct edit requests** to protected files
2. **User mentions** of version bumps, releases, or changelog updates
3. **Broad refactoring** that might touch version-controlled files
4. **Documentation updates** that could include CHANGELOG.md
5. **"Fix all issues"** or similar sweeping requests

## Protected Files

### Hard Protection (Permission System)
These files are **completely blocked** from editing by Claude Code's permission system:

- `**/CHANGELOG.md` - All changelog files in any location

**Operations blocked:** Edit, Write, MultiEdit
**Operations allowed:** Read (for analysis and context)

### Soft Protection (Skill Detection)
These files trigger **warnings and suggestions** before edits:

#### Package Manager Manifests (Version Fields)
- `package.json` → `"version": "x.y.z"` (npm/Node.js)
- `pyproject.toml` → `version = "x.y.z"` (Python/uv)
- `Cargo.toml` → `version = "x.y.z"` (Rust/cargo)
- `.claude-plugin/plugin.json` → `"version": "x.y.z"` (Claude Code plugins)
- `pom.xml` → `<version>x.y.z</version>` (Maven/Java)
- `build.gradle` → `version = 'x.y.z'` (Gradle)
- `pubspec.yaml` → `version: x.y.z` (Dart/Flutter)

**Why soft protection?** Claude Code's permission system operates at the file level, not field level. Blocking entire manifest files would prevent legitimate dependency updates via automated tools (npm, cargo, uv, etc.).

## Detection Logic

Before attempting any edit, the skill checks:

### 1. File Path Analysis
```
if file_path ends with "CHANGELOG.md":
    → Inform user of hard permission block
    → Explain release-please workflow
    → Suggest conventional commit approach
```

### 2. Content Pattern Matching
```
if file is package manifest AND edit touches version field:
    → Warn about release-please management
    → Explain why manual edits cause conflicts
    → Offer to edit OTHER fields (but not version)
    → Provide conventional commit template
```

### 3. Intent Recognition
```
if user request contains keywords: "version", "release", "bump", "changelog":
    → Proactively explain release-please workflow
    → Check if files in scope are protected
    → Suggest proper approach before attempting edits
```

## Response Templates

### When CHANGELOG.md Edit Attempted

```
⚠️ CHANGELOG.md Protection Active

I cannot edit CHANGELOG.md files - they're protected by Claude Code's permission
system because they're managed by release-please automation.

**Why this matters:**
Manual edits to CHANGELOG.md cause merge conflicts with automated release PRs,
breaking your release workflow.

**Proper workflow:**
1. Make your changes with conventional commit messages:
   - feat: adds new features (minor version bump)
   - fix: bug fixes (patch version bump)
   - chore: maintenance tasks (no version bump)
   - BREAKING CHANGE: breaking changes (major version bump)

2. Release-please automatically:
   - Detects conventional commits
   - Generates CHANGELOG entries
   - Creates a release PR with version bumps
   - Tags releases when PR is merged

**Example commit:**
```
feat(auth): add OAuth2 support

Implements OAuth2 authentication flow with PKCE.
Includes refresh token rotation and session management.
```

**Need to override?**
For emergency fixes, temporarily edit ~/.claude/settings.json:
1. Comment out the CHANGELOG.md deny rules
2. Make your edits
3. Re-enable protection
```

### When Version Field Edit Detected

```
⚠️ Version Field Protection Warning

I notice you're asking me to modify the version field in [file_name]. This field
is typically managed by release-please automation.

**Current version:** [current_version]
**Requested change:** [requested_change]

**Why manual edits are problematic:**
- Creates merge conflicts with release-please PRs
- Can cause version numbering inconsistencies
- Bypasses conventional commit history tracking

**I can help in two ways:**

1. **Automated approach (recommended):**
   I'll help you craft a conventional commit message that will trigger the
   appropriate version bump when release-please creates its next release PR.

   For [requested_change], you should use:
   - `feat:` for minor version bump
   - `fix:` for patch version bump
   - `feat!:` or `BREAKING CHANGE:` for major version bump

2. **Manual override (emergency only):**
   If you absolutely need to manually set the version (e.g., aligning with
   external requirements), I can edit other fields in [file_name] but will
   skip the version field. You'll need to edit that manually or temporarily
   disable the skill protection.

Which approach would you prefer?
```

### When Broad Refactoring Requested

```
📋 Release-Please Files Detected

I've identified several release-please managed files in the scope of this
refactoring:

**Protected files found:**
- plugins/dotfiles-core/CHANGELOG.md (hard block)
- plugins/dotfiles-toolkit/.claude-plugin/plugin.json (version field)
- [other files...]

**My approach:**
✅ I'll refactor all other files as requested
⚠️ I'll skip protected files and explain why
📝 I'll provide a summary of skipped changes

**If you need version/changelog updates:**
I'll generate appropriate conventional commit messages that will trigger
release-please to make those changes automatically.

Should I proceed with this approach?
```

## Conventional Commit Guide

The skill provides instant conventional commit templates based on the type of change:

### Feature Addition
```
feat(scope): brief description

Detailed explanation of what was added and why.
Can be multiple paragraphs.

Refs: #issue-number
```

### Bug Fix
```
fix(scope): brief description

Explanation of the bug and how it was fixed.

Fixes: #issue-number
```

### Breaking Change
```
feat(scope)!: brief description

BREAKING CHANGE: Explanation of what breaks and migration path.

Details about the new behavior.

Refs: #issue-number
```

### Chore (No Version Bump)
```
chore(scope): brief description

Maintenance work that doesn't affect functionality.
Examples: dependency updates, refactoring, docs.
```

## Integration with Other Skills

This skill works alongside:

- **Chezmoi Expert** - Ensures dotfiles templates don't manually edit versions
- **Git Workflow** - Enforces conventional commits before creating PRs
- **GitHub Actions** - Aware of release-please workflow configurations

## Skill Configuration

Located in `dot_claude/skills/release-please-protection/` (source) which becomes `~/.claude/skills/release-please-protection/` after chezmoi apply:

- `SKILL.md` - This file (skill definition)
- `patterns.md` - Protected file pattern reference
- `workflow.md` - Detailed release-please workflow guide

## Limitations

### What This Skill Cannot Prevent

1. **Explicit overrides** - If you explicitly instruct me to edit despite warnings
2. **Out-of-context files** - Files not in the current context window
3. **External tools** - Commands like `sed`, `awk`, or direct bash edits
4. **Git operations** - Manual `git commit` with modified protected files

### What This Skill DOES Prevent

1. **Accidental edits** - Catching mistakes before they happen
2. **Workflow violations** - Explaining proper release-please patterns
3. **Merge conflicts** - Preventing automated PR conflicts
4. **Version inconsistencies** - Maintaining semantic versioning discipline

## Emergency Overrides

If you absolutely must manually edit protected files:

### Temporary Permission Override
```bash
# 1. Edit global settings
vim ~/.claude/settings.json

# 2. Comment out deny rules
"deny": [
  "Bash(git add .)",
  "Bash(git add -A)",
  "Bash(git add --all)",
  // "Edit(**/CHANGELOG.md)",
  // "Write(**/CHANGELOG.md)",
  // "MultiEdit(**/CHANGELOG.md)"
]

# 3. Make your edits

# 4. Re-enable protection (uncomment the lines)

# 5. Verify with chezmoi
chezmoi diff ~/.claude/settings.json
chezmoi apply  # If template is out of sync
```

### Skill Bypass (Not Recommended)
```bash
# Temporarily disable skill
mv .claude/skills/release-please-protection .claude/skills/release-please-protection.disabled

# Make edits

# Re-enable
mv .claude/skills/release-please-protection.disabled .claude/skills/release-please-protection
```

## Success Metrics

This skill is working properly when:

✅ All CHANGELOG.md edit attempts are blocked with helpful explanations
✅ Version field modifications trigger warnings and alternatives
✅ Conventional commit suggestions match the requested changes
✅ Users understand the release-please workflow after first warning
✅ No merge conflicts occur with automated release PRs
✅ Version numbers follow semantic versioning consistently

## Further Reading

- See `patterns.md` for complete list of protected file patterns
- See `workflow.md` for detailed release-please workflow documentation
- Release-please docs: https://github.com/googleapis/release-please
- Conventional commits: https://www.conventionalcommits.org/

# Emergency Override Steps

Moved verbatim from `SKILL.md` § Emergency Overrides. These steps are for the human operator to run in their own editor/shell — surface them, never perform them.

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

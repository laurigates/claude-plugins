# Project Setup Guide

Read when creating `.claude/settings.json` / `.claude/settings.local.json` for a project from scratch.

## 1. Create Settings Directory

```bash
mkdir -p .claude
```

## 2. Create Project Settings

```bash
cat > .claude/settings.json << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(npm run *)"
    ]
  }
}
EOF
```

## 3. Add to .gitignore (for local settings)

```bash
echo ".claude/settings.local.json" >> .gitignore
```

## 4. Create Local Settings (optional)

```bash
cat > .claude/settings.local.json << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(docker *)"
    ]
  }
}
EOF
```

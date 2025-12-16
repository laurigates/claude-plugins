# Chezmoi Expert Reference

Comprehensive reference documentation for advanced chezmoi operations, troubleshooting, and best practices.

## Advanced Commands

### Orphan Management

Files renamed or deleted in source need to be tracked:

```bash
# Add to .chezmoiremove
~/.config/app/old-config.yaml

# Workflow for renaming
1. Rename in source directory
2. Add old path to .chezmoiremove
3. Preview: chezmoi apply --dry-run
4. Apply: chezmoi apply
```

### State Management

```bash
# Reset state for file
chezmoi state delete-bucket --bucket=entryState --key=~/.bashrc

# Dump state for debugging
chezmoi state dump

# Force re-run of run_once scripts
chezmoi state reset
```

### External Files

```toml
# .chezmoiexternal.toml
[".oh-my-zsh"]
  type = "archive"
  url = "https://github.com/ohmyzsh/ohmyzsh/archive/master.tar.gz"
  stripComponents = 1

[".config/nvim/autoload/plug.vim"]
  type = "file"
  url = "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
```

## Template Functions

### Built-in Functions

```go
# Environment variables
{{ env "HOME" }}
{{ env "PATH" | split ":" | first }}

# Command execution
{{ output "uname" "-m" | trim }}

# File operations
{{ include "~/.config/includes/aliases.sh" }}
{{ includeTemplate "~/.config/templates/prompt.sh" . }}

# Path checking
{{ lookPath "docker" }}  # Returns path or empty if not found
```

### Password Manager Integration

```go
# 1Password
{{ onepasswordDocument "vault-id" }}
{{ (onepasswordItemFields "GitHub" "credential").token.value }}

# Bitwarden
{{ bitwarden "item" "github-token" }}

# gopass
{{ gopass "path/to/secret" }}
```

### JSON Processing

```go
{{ $config := include "~/.config/app/config.json" | fromJson }}
{{ $config.theme }}
{{ $config.settings.editor }}
```

## Cross-Platform Patterns

### Homebrew Path Handling

```go
{{- if eq .chezmoi.os "darwin" -}}
{{-   if eq .chezmoi.arch "arm64" -}}
export HOMEBREW_PREFIX="/opt/homebrew"
{{-   else -}}
export HOMEBREW_PREFIX="/usr/local"
{{-   end -}}
{{- else if eq .chezmoi.os "linux" -}}
export HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
{{- end -}}

# Add to PATH
export PATH="${HOMEBREW_PREFIX}/bin:${PATH}"
```

### Conditional Package Installation

```toml
# .chezmoi.toml.tmpl
[data.packages]
  npm = ["typescript", "prettier", "eslint"]
  pip = ["black", "ruff", "mypy"]
  cargo = ["ripgrep", "fd-find", "bat"]
```

```bash
# run_onchange_install-packages.sh.tmpl
#!/bin/bash
{{ range .packages.npm }}
npm install -g {{ . }}
{{ end }}
```

## .chezmoiignore Patterns

```
# Documentation files
README.md
LICENSE
.git

# Platform-specific exclusions
{{- if ne .chezmoi.os "darwin" }}
.config/karabiner     # macOS only
.config/hammerspoon   # macOS only
{{- end }}

{{- if ne .chezmoi.os "linux" }}
.config/systemd       # Linux only
.config/i3            # Linux only
{{- end }}

# Hostname-specific exclusions
{{- if ne .chezmoi.hostname "work-laptop" }}
.work-config
{{- end }}
```

## Security Best Practices

### Never Commit Secrets

```bash
# Add to .chezmoiignore
.env
*.key
*.pem
*_token
*_secret
```

### Encrypted Files

```bash
# Configure encryption
[encryption]
  recipient = "your-gpg-id"

# Add encrypted file
chezmoi add --encrypt ~/.ssh/id_rsa

# Results in: encrypted_private_dot_ssh/private_id_rsa.asc
```

### Environment Variable Secrets

```go
# Store in environment, reference in templates
{{ env "GITHUB_TOKEN" }}
{{ env "AWS_SECRET_KEY" }}
```

## Multi-Machine Configuration

### Machine-Specific Variables

```toml
# ~/.config/chezmoi/chezmoi.toml
[data]
  machine_type = "personal"  # or "work", "server"

[data.git]
  email = "personal@email.com"

[data.work]
  vpn = "company-vpn.example.com"
```

```go
# In templates
{{ if eq .machine_type "work" }}
export GIT_AUTHOR_EMAIL="{{ .work.email }}"
source ~/.work-specific
{{ else }}
export GIT_AUTHOR_EMAIL="{{ .git.email }}"
{{ end }}
```

## CI/CD Integration

### GitHub Actions Validation

```yaml
name: Validate Dotfiles
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install chezmoi
        run: sh -c "$(curl -fsLS get.chezmoi.io)"
      - name: Validate
        run: |
          chezmoi init --source .
          chezmoi verify
          chezmoi apply --dry-run
```

### Pre-commit Hooks

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: chezmoi-diff
        name: Check chezmoi diff
        entry: chezmoi diff
        language: system
        pass_filenames: false
```

## Migration Guides

### From GNU Stow

```bash
# Move stow directory contents
cp -r ~/dotfiles/* ~/.local/share/chezmoi/

# Rename directories (remove dot prefix)
cd ~/.local/share/chezmoi
for dir in .*; do
  [[ -d "$dir" ]] && mv "$dir" "dot_${dir#.}"
done
```

### From Bare Git Repo

```bash
# Clone existing repo
git clone --bare https://github.com/user/dotfiles.git ~/.dotfiles

# Initialize chezmoi from it
chezmoi init --source ~/.dotfiles

# Add files
chezmoi add $(git --git-dir=$HOME/.dotfiles --work-tree=$HOME ls-files)
```

## Bootstrap Script

```bash
#!/bin/sh
# bootstrap.sh - Setup new machine with chezmoi

# Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin

# Initialize from repo
~/.local/bin/chezmoi init --apply https://github.com/user/dotfiles.git

# Verify
~/.local/bin/chezmoi verify
```

## Debugging Checklist

1. **File not updating?**
   - Check if managed: `chezmoi managed | grep <file>`
   - Check .chezmoiignore: `grep <file> .chezmoiignore`
   - Force apply: `chezmoi apply --force <file>`

2. **Template errors?**
   - Test rendering: `chezmoi execute-template < file.tmpl`
   - Check variables: `chezmoi data`
   - Debug output: `chezmoi apply -v --debug <file>`

3. **Wrong permissions?**
   - Check source prefix: Should use `private_` for 0600
   - Verify: `ls -la $(chezmoi source-path <file>)`

4. **Merge conflicts?**
   - Three-way merge: `chezmoi merge <file>`
   - Manual resolution: Edit source, then `chezmoi apply <file>`

## Performance Tips

- Use `chezmoi apply <specific-path>` instead of applying everything
- Run `chezmoi diff | head -50` to preview large changesets
- Use `--exclude` to skip large directories: `chezmoi apply --exclude ~/.cache`
- For bulk operations, use `find` with xargs: `chezmoi managed --include=files | xargs -n 10 chezmoi apply`

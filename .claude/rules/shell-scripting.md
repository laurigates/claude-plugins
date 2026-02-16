---
created: 2026-01-18
modified: 2026-02-16
reviewed: 2026-02-16
requires: bash 5+
---

# Shell Scripting Patterns

Safe, portable shell scripting patterns for use in skills and commands.

## Reserved Variable Names

These variables are read-only or have special meaning in bash/zsh. Use prefixed alternatives instead.

| Reserved | Shell | Reason | Use Instead |
|----------|-------|--------|-------------|
| `status` | zsh | Read-only exit status | `item_status`, `doc_status` |
| `name` | both | Common collision | `item_name`, `file_name` |
| `type` | both | Common collision | `item_type`, `doc_type` |
| `path` | both | Common collision | `file_path`, `doc_path` |
| `PWD` | both | Read-only current directory | - |
| `OLDPWD` | both | Read-only previous directory | - |
| `UID` | both | Read-only user ID | - |
| `EUID` | both | Read-only effective user ID | - |
| `PPID` | both | Read-only parent process ID | - |
| `RANDOM` | both | Special, generates random numbers | - |
| `SECONDS` | both | Special, time since shell start | - |
| `LINENO` | both | Special, current line number | - |
| `HISTCMD` | both | Read-only history number | - |
| `HOSTNAME` | both | May be read-only | - |
| `HOSTTYPE` | both | May be read-only | - |
| `OSTYPE` | both | May be read-only | - |

**Convention**: Prefix variables with descriptive context (e.g., `prp_`, `adr_`, `doc_`).

## YAML Frontmatter Extraction

### Standard Pattern

Use this consistent pattern for extracting YAML frontmatter fields:

```bash
# Safe frontmatter field extraction
# Pattern: grep for field at start of line, extract value, trim whitespace
extract_field() {
  local file="$1"
  local field="$2"
  head -50 "$file" | grep -m1 "^${field}:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r'
}

# Usage
doc_status=$(extract_field "$file" "status")
confidence=$(extract_field "$file" "confidence")
```

### Inline Extraction (for loops)

```bash
# Safe inline extraction - prefix all variables
for prp in docs/prps/*.md; do
  prp_name=$(basename "$prp")
  prp_status=$(head -50 "$prp" | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//')
  prp_confidence=$(head -50 "$prp" | grep -m1 "^confidence:" | sed 's/^[^:]*:[[:space:]]*//')
  echo "$prp_name | $prp_status | $prp_confidence"
done
```

### Key Patterns

| Purpose | Pattern |
|---------|---------|
| First match only | `grep -m1` |
| Case-insensitive | `grep -im1` |
| Anchor to line start | `^fieldname:` |
| Extract value after colon | `sed 's/^[^:]*:[[:space:]]*//'` |
| Limit to frontmatter | `head -50` (generous) or `head -20` (strict) |
| Remove carriage returns | `tr -d '\r'` |

### Multi-Value Fields (Arrays)

For YAML arrays like `related:`, extract and parse separately:

```bash
# Extract array items (assumes - prefix format)
get_array_field() {
  local file="$1"
  local field="$2"
  awk -v field="$field" '
    /^---$/ { in_front = !in_front; next }
    in_front && $0 ~ "^"field":" { capture = 1; next }
    capture && /^[[:space:]]*-/ { gsub(/^[[:space:]]*-[[:space:]]*/, ""); print }
    capture && /^[a-z]/ { exit }
  ' "$file"
}

# Usage
related_items=$(get_array_field "$file" "related")
```

## Error Handling

### Standard Fallback Pattern

```bash
# Always provide a fallback for missing fields
prp_status=$(head -50 "$prp" | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//' || true)

# With default value
prp_status=${prp_status:-"unknown"}
```

### Silent Errors for Optional Fields

```bash
# Suppress errors for missing files or fields
confidence=$(head -50 "$prp" 2>/dev/null | grep -m1 "^confidence:" | sed 's/^[^:]*:[[:space:]]*//' || echo "")
```

### Check Before Use

```bash
# Validate required fields
if [ -z "$prp_status" ]; then
  echo "Warning: $prp_name missing status field"
  continue
fi
```

## File Iteration Patterns

### Safe Glob Iteration

```bash
# Use nullglob behavior - handle empty directories
shopt -s nullglob 2>/dev/null  # bash
setopt null_glob 2>/dev/null   # zsh

# Or check for files first
if ls docs/prps/*.md >/dev/null 2>&1; then
  for prp in docs/prps/*.md; do
    # ...
  done
else
  echo "No PRPs found"
fi
```

### With find (more portable)

```bash
# Use find with -print0 for safe filename handling
find docs/prps -name "*.md" -type f -print0 2>/dev/null | while IFS= read -r -d '' prp; do
  prp_name=$(basename "$prp")
  # ...
done
```

## Output Formatting

### Table Output

```bash
# Consistent table format with pipes
printf "%-30s | %-12s | %s\n" "Name" "Status" "Confidence"
printf "%-30s | %-12s | %s\n" "----" "------" "----------"
for prp in docs/prps/*.md; do
  prp_name=$(basename "$prp" .md)
  prp_status=$(head -50 "$prp" | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//' || true)
  prp_confidence=$(head -50 "$prp" | grep -m1 "^confidence:" | sed 's/^[^:]*:[[:space:]]*//' || true)
  printf "%-30s | %-12s | %s\n" "$prp_name" "${prp_status:-N/A}" "${prp_confidence:-N/A}"
done
```

### JSON Output (for parsing)

```bash
# Generate JSON array for machine consumption
echo "["
first=true
for prp in docs/prps/*.md; do
  prp_name=$(basename "$prp" .md)
  prp_status=$(head -50 "$prp" | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//' || true)

  $first || echo ","
  first=false
  printf '  {"name": "%s", "status": "%s"}' "$prp_name" "${prp_status:-unknown}"
done
echo ""
echo "]"
```

## Quick Reference

### Frontmatter Extraction One-Liner

```bash
# Template - replace FIELD and use safe variable name
item_FIELD=$(head -50 "$file" | grep -m1 "^FIELD:" | sed 's/^[^:]*:[[:space:]]*//' || true)
```

### Common Extractions

| Field | Safe Variable | Pattern |
|-------|---------------|---------|
| status | `doc_status` | `head -50 "$f" \| grep -m1 "^status:" \| sed 's/^[^:]*:[[:space:]]*//'` |
| confidence | `confidence` | `head -50 "$f" \| grep -m1 "^confidence:" \| sed 's/^[^:]*:[[:space:]]*//'` |
| domain | `doc_domain` | `head -50 "$f" \| grep -m1 "^domain:" \| sed 's/^[^:]*:[[:space:]]*//'` |
| created | `created_date` | `head -50 "$f" \| grep -m1 "^created:" \| sed 's/^[^:]*:[[:space:]]*//'` |
| modified | `modified_date` | `head -50 "$f" \| grep -m1 "^modified:" \| sed 's/^[^:]*:[[:space:]]*//'` |

## Bash Version Requirement

Scripts require **bash 5+**. macOS ships bash 3.2 (GPLv2); install a modern version via Homebrew:

```bash
brew install bash
```

Homebrew bash installs to `/opt/homebrew/bin/bash` and takes priority in `$PATH`. All scripts use `#!/usr/bin/env bash` shebangs, so no system replacement is needed.

### Bash 5+ Features Available

These features are safe to use in all project scripts:

| Feature | Example |
|---------|---------|
| Associative arrays | `declare -A map=([key]=value)` |
| `mapfile` / `readarray` | `mapfile -t lines < file.txt` |
| `${var,,}` / `${var^^}` | Lowercase/uppercase without `tr` |
| `${var@Q}` | Shell-quoted expansion |
| Nameref variables | `declare -n ref=varname` |

### Plugin Directory Discovery

Exclude `.claude-plugin` (hidden metadata directory) from `*-plugin` globs:

```bash
find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0
```

### GNU vs BSD Tool Differences

Even with bash 5+, some CLI tools differ between macOS (BSD) and Linux (GNU). Use portable patterns for:

| Tool | macOS (BSD) | Linux (GNU) | Portable |
|------|-------------|-------------|----------|
| `date` | `date -j -f "%Y-%m-%d"` | `date -d "2024-01-01"` | Detect with fallback |
| `sed -i` | `sed -i ''` | `sed -i` | Use `sed -i.bak` + `rm` |
| `grep -P` | Not available | PCRE support | Use `grep -E` (extended regex) |

```bash
# Cross-platform date comparison
if date -j -f "%Y-%m-%d" "$past_date" "+%s" >/dev/null 2>&1; then
  past_ts=$(date -j -f "%Y-%m-%d" "$past_date" "+%s")
elif date -d "$past_date" "+%s" >/dev/null 2>&1; then
  past_ts=$(date -d "$past_date" "+%s")
fi
```
## Checklist for New Commands

- [ ] Variable names use prefixed form (e.g., `doc_status` instead of `status`)
- [ ] Frontmatter extraction uses `head -50 | grep -m1 "^field:" | sed ...` pattern
- [ ] Error handling with `|| true` or `|| echo ""`
- [ ] Default values with `${var:-default}`
- [ ] File iteration handles empty directories
- [ ] Output format is consistent (table or JSON)
- [ ] Plugin discovery excludes `.claude-plugin` directory

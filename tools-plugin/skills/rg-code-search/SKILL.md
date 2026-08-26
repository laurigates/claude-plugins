---
created: 2025-12-16
modified: 2026-08-26
reviewed: 2026-04-25
name: rg-code-search
description: "ripgrep (rg) fast code search: smart defaults, regex, file filtering. Use when searching for text patterns, code snippets, or doing multi-file analysis."
user-invocable: false
allowed-tools: Bash(rg *), Read, Grep, Glob
model: sonnet
---

# rg Code Search

Expert knowledge for using `rg` (ripgrep) as a blazingly fast code search tool with powerful filtering and pattern matching.

## When to Use This Skill

| Use this skill when... | Use fd-file-finding instead when... |
|---|---|
| Searching file contents for text or regex patterns | Searching for files by name, extension, or path |
| Filtering matches by file type (`-t py`, `-t js`) | Filtering files by mtime, size, or `-type` |
| Multi-line pattern matching across source files | Locating files to feed into another tool |

| Use this skill when... | Use binary-analysis instead when... |
|---|---|
| Searching source code or text-encoded files | Extracting strings from compiled binaries or firmware |
| Auditing repos for hardcoded patterns in tracked files | Hunting for credentials inside ELF, Mach-O, or `.bin` blobs |

## Core Expertise

**ripgrep Advantages**
- Extremely fast (written in Rust)
- Respects `.gitignore` automatically
- Smart case-insensitive search
- Recursive by default
- Colorized output
- Multi-line search support
- Replace functionality

## Basic Usage

### Simple Search
```bash
# Basic search
rg pattern                  # Search in current directory
rg "import numpy"           # Search for exact phrase
rg function_name            # Search for function name

# Case-sensitive search
rg -s Pattern               # Force case-sensitive
rg -i PATTERN               # Force case-insensitive
```

### File Type Filtering
```bash
# Search specific file types
rg pattern -t py            # Python files only
rg pattern -t rs            # Rust files only
rg pattern -t js            # JavaScript files
rg pattern -t md            # Markdown files

# Multiple types
rg pattern -t py -t rs      # Python and Rust

# List available types
rg --type-list              # Show all known types
```

### Extension Filtering
```bash
# Filter by extension
rg pattern -g '*.rs'        # Rust files
rg pattern -g '*.{js,ts}'   # JavaScript and TypeScript
rg pattern -g '!*.min.js'   # Exclude minified files
```

## Advanced Filtering

### Path Filtering
```bash
# Search in specific directories
rg pattern src/             # Only src/ directory
rg pattern src/ tests/      # Multiple directories

# Exclude paths
rg pattern -g '!target/'    # Exclude target/
rg pattern -g '!{dist,build,node_modules}/'  # Exclude multiple

# Full path matching
rg pattern -g '**/test/**'  # Only test directories
```

**A glob with no `/` matches the *basename* only.** So `-g '*name*'` can never
match a **directory** called `name` — it tests `SKILL.md`, not
`skills/name/SKILL.md`. Add a `/` and the glob anchors to the full path from the
search root instead, where `*` does not cross `/`; only `**` spans depth.

```bash
rg --files -g '*sentry-triage*'      # nothing — basename is SKILL.md
rg --files -g '*sentry-triage*/**'   # nothing — now anchored at the root
rg --files -g '**/sentry-triage/**'  # skills/sentry-triage/SKILL.md ← the only form that works
```

It fails *quietly*: `-g '*name*'` still matches sibling files like
`name-notes.md`, so a partial hit reads as a working search. When hunting a name
rather than content, prefer `rg -l <pattern>` or `find -type d -name <name>`.

### Content Filtering
```bash
# Search only in files containing pattern
rg --files-with-matches "import.*React" | xargs rg "useState"

# Exclude files by content
rg pattern --type-not markdown

# Search only uncommitted files
rg pattern $(git diff --name-only)
```

### Size and Hidden Files
```bash
# Include hidden files
rg pattern -u               # Include hidden
rg pattern -uu              # Include hidden + .gitignore'd
rg pattern -uuu             # Unrestricted: everything

# Exclude by size
rg pattern --max-filesize 1M  # Skip files over 1MB
```

## Quick Reference

### Essential Options

| Option | Purpose | Example |
|--------|---------|---------|
| `-t TYPE` | File type filter | `rg -t py pattern` |
| `-g GLOB` | Glob pattern | `rg -g '*.rs' pattern` |
| `-i` | Case-insensitive | `rg -i pattern` |
| `-s` | Case-sensitive | `rg -s Pattern` |
| `-w` | Match whole words | `rg -w word` |
| `-l` | Files with matches | `rg -l pattern` |
| `-c` | Count per file | `rg -c pattern` |
| `-A N` | Lines after | `rg -A 5 pattern` |
| `-B N` | Lines before | `rg -B 3 pattern` |
| `-C N` | Context lines | `rg -C 2 pattern` |
| `-U` | Multi-line | `rg -U 'pattern.*'` |
| `-u` | Include hidden | `rg -u pattern` |
| `--replace` | Replace text | `rg pattern --replace new` |

This makes rg the preferred tool for fast, powerful code search in development workflows.

For the full regex and multi-line recipes, output formatting, language-specific search patterns, tool integrations, performance tuning, and the complete file-type table, see [REFERENCE.md](REFERENCE.md).

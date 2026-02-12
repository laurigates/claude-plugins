---
model: haiku
created: 2025-12-16
modified: 2026-01-21
reviewed: 2025-12-16
name: rg-code-search
description: Fast code search using ripgrep (rg) with smart defaults, regex patterns, and file filtering. Use when searching for text patterns, code snippets, or performing multi-file code analysis.
allowed-tools: Bash(rg *), Read, Grep, Glob
---

# rg Code Search

Expert knowledge for using `rg` (ripgrep) as a blazingly fast code search tool with powerful filtering and pattern matching.

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

## Advanced Patterns

### Regular Expressions
```bash
# Word boundaries
rg '\bfunction\b'           # Match whole word "function"
rg '\btest_\w+'             # Words starting with test_

# Line anchors
rg '^import'                # Lines starting with import
rg 'return$'                # Lines ending with return
rg '^class \w+:'            # Python class definitions

# Character classes
rg 'TODO|FIXME|XXX'         # Find markers
rg '[Ee]rror'               # Error or error
rg '\d{3}-\d{4}'            # Phone numbers
```

### Multi-line Search
```bash
# Multi-line patterns
rg -U 'fn.*\{.*\}'          # Function definitions (Rust)
rg -U 'struct.*{[^}]*}'     # Struct definitions

# Context lines
rg -A 5 pattern             # Show 5 lines after
rg -B 3 pattern             # Show 3 lines before
rg -C 2 pattern             # Show 2 lines before and after
```

### Output Formatting
```bash
# Control output
rg -l pattern               # List files with matches only
rg -c pattern               # Count matches per file
rg --count-matches pattern  # Total match count

# Show context
rg -n pattern               # Show line numbers (default)
rg -N pattern               # Don't show line numbers
rg --heading pattern        # Group by file (default)
rg --no-heading pattern     # Don't group by file

# Customize output
rg --vimgrep pattern        # Vim-compatible format
rg --json pattern           # JSON output
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

## Code Search Patterns

### Finding Definitions
```bash
# Function definitions
rg '^def \w+\('             # Python functions
rg 'fn \w+\('               # Rust functions
rg '^function \w+\('        # JavaScript functions
rg '^\s*class \w+'          # Class definitions

# Interface/type definitions
rg '^interface \w+'         # TypeScript interfaces
rg '^type \w+ ='            # Type aliases
rg '^struct \w+'            # Struct definitions (Rust/Go)
```

### Finding Usage
```bash
# Find function calls
rg 'functionName\('         # Direct calls
rg '\.methodName\('         # Method calls

# Find imports
rg '^import.*module_name'   # Python imports
rg '^use.*crate_name'       # Rust uses
rg "^import.*'package'"     # JavaScript imports
```

### Code Quality Checks
```bash
# Find TODOs and FIXMEs
rg 'TODO|FIXME|XXX|HACK'    # Find all markers
rg -t py '#\s*TODO'         # Python TODOs
rg -t rs '//\s*TODO'        # Rust TODOs

# Find debug statements
rg 'console\.log'           # JavaScript
rg 'println!'               # Rust
rg 'print\('                # Python

# Find security issues
rg 'password.*=|api_key.*=' # Potential secrets
rg 'eval\('                 # Eval usage
rg 'exec\('                 # Exec usage
```

### Testing Patterns
```bash
# Find tests
rg '^def test_' -t py       # Python tests
rg '#\[test\]' -t rs        # Rust tests
rg "describe\(|it\(" -t js  # JavaScript tests

# Find skipped tests
rg '@skip|@pytest.mark.skip' -t py
rg '#\[ignore\]' -t rs
rg 'test\.skip|it\.skip' -t js
```

## File Operations

### Search and Replace
```bash
# Preview replacements
rg pattern --replace replacement

# Perform replacement (requires external tool)
rg pattern -l | xargs sed -i 's/pattern/replacement/g'

# With confirmation (using fd and interactive)
fd -e rs | xargs rg pattern --files-with-matches | xargs -I {} sh -c 'vim -c "%s/pattern/replacement/gc" -c "wq" {}'
```

### Integration with Other Tools
```bash
# Pipe to other commands
rg -l "TODO" | xargs wc -l          # Count lines with TODOs
rg "function" --files-with-matches | xargs nvim  # Open files in editor

# Combine with fd (prefer fd's native -x execution)
fd -e py -x rg "class.*Test" {}     # Find test classes
fd -e rs -x rg "unsafe" {}          # Find unsafe blocks

# Count occurrences
rg -c pattern | awk -F: '{sum+=$2} END {print sum}'
```

### Stats and Analysis
```bash
# Count total matches
rg pattern --count-matches --no-filename | awk '{sum+=$1} END {print sum}'

# Find most common matches
rg pattern -o | sort | uniq -c | sort -rn

# Files with most matches
rg pattern -c | sort -t: -k2 -rn | head -10
```

## Performance Optimization

### Speed Tips
```bash
# Limit search
rg pattern --max-depth 3    # Limit directory depth
rg pattern -g '*.rs' -t rust  # Use type filters

# Parallel processing (default)
rg pattern -j 4             # Use 4 threads

# Memory management
rg pattern --mmap           # Use memory maps (faster)
rg pattern --no-mmap        # Don't use memory maps
```

### Large Codebase Strategies
```bash
# Narrow scope first
rg pattern src/             # Specific directory
rg pattern -t py -g '!test*'  # Specific type, exclude tests

# Use file list caching
rg --files > /tmp/files.txt
rg pattern $(cat /tmp/files.txt)

# Exclude large directories
rg pattern -g '!{target,node_modules,dist,build}/'
```

## Best Practices

**When to Use rg**
- Searching code for patterns
- Finding function/class definitions
- Code analysis and auditing
- Refactoring support
- Security scanning

**When to Use grep Instead**
- POSIX compatibility required
- Simple one-off searches
- Piped input (stdin)
- System administration tasks

**Tips for Effective Searches**
- Escape regex special characters in patterns
- Use `-u` flags when searching ignored/hidden files
- Exclude large binary/generated files with `--glob '!vendor'`
- Prefer rg over grep for speed and smart defaults

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

### File Types (Common)

| Type | Extensions |
|------|------------|
| `-t py` | Python (.py, .pyi) |
| `-t rs` | Rust (.rs) |
| `-t js` | JavaScript (.js, .jsx) |
| `-t ts` | TypeScript (.ts, .tsx) |
| `-t go` | Go (.go) |
| `-t md` | Markdown (.md, .markdown) |
| `-t yaml` | YAML (.yaml, .yml) |
| `-t json` | JSON (.json) |

### Common Command Patterns

```bash
# Find function definitions across codebase
rg '^\s*(def|fn|function)\s+\w+' -t py -t rs -t js

# Find all imports
rg '^(import|use|require)' -t py -t rs -t js

# Find potential bugs
rg 'TODO|FIXME|XXX|HACK|BUG'

# Find test files and count tests
rg -t py '^def test_' -c

# Find large functions (50+ lines)
rg -U 'def \w+.*\n(.*\n){50,}' -t py

# Security audit
rg 'password|api_key|secret|token' -i -g '!*.{lock,log}'
```

This makes rg the preferred tool for fast, powerful code search in development workflows.

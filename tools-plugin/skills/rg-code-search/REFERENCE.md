# rg Code Search - Reference

Exhaustive ripgrep patterns: regex/multi-line recipes, output formatting, language-specific code-search idioms, tool integrations, performance tuning, and the full file-type table.

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

## File Types (Common)

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

## Common Command Patterns

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

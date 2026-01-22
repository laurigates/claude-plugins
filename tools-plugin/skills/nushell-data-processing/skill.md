---
model: haiku
created: 2025-12-25
modified: 2025-12-25
reviewed: 2025-12-25
name: Nushell Data Processing
description: Structured data processing with nushell - native table handling, multi-format parsing (JSON, YAML, TOML, CSV), and pipeline operations. Preferred over jq/yq for complex transformations.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# Nushell Data Processing

Expert knowledge for structured data processing using nushell, a shell that treats data as tables rather than text streams.

## Core Advantages Over jq/yq

| Feature | nushell | jq/yq |
|---------|---------|-------|
| Native tables | Yes - visual output | No - text-based |
| Multi-format | JSON, YAML, TOML, CSV, XML | Single format each |
| Type awareness | Rich type system | Limited |
| Shell integration | Full shell capabilities | Filter only |
| Complex transforms | Natural syntax | Complex expressions |

## Essential Commands

### Opening Data Files

```nushell
# Auto-detect format from extension
open data.json
open config.yaml
open settings.toml
open report.csv

# Explicit parsing
"[1, 2, 3]" | from json
"name: value" | from yaml
"a,b,c\n1,2,3" | from csv
```

### Format Conversion

```nushell
# Convert between formats
open data.json | to yaml
open config.yaml | to json
open data.csv | to json

# Compact JSON output (for piping)
open data.json | to json -r
```

### Table Operations

```nushell
# Select columns
open data.json | select name email

# Filter rows
open data.json | where age > 18
open data.json | where status == "active"
open data.json | where name =~ "^A"  # regex match

# Sort
open data.json | sort-by name
open data.json | sort-by age --reverse

# Limit results
open data.json | first 10
open data.json | last 5
open data.json | skip 2 | first 3
```

### Transformations

```nushell
# Add/update columns
open data.json | insert full_name {|row| $"($row.first) ($row.last)"}
open data.json | update name {|row| $row.name | str upcase}
open data.json | upsert status "active"

# Rename columns
open data.json | rename old_name new_name

# Remove columns
open data.json | reject password secret_key

# Transpose (pivot)
open data.json | transpose key value
```

### Aggregations

```nushell
# Group by
open data.json | group-by category

# Group with aggregation
open data.json | group-by --to-table category | update items {|row| $row.items | length}

# Math operations
open data.json | get prices | math sum
open data.json | get scores | math avg
open data.json | get values | math max
open data.json | get values | math min

# Count
open data.json | length
open data.json | where active | length
```

### Iteration with `each`

```nushell
# Transform each row
open data.json | each {|row| $"($row.name): ($row.value)"}

# Parallel processing
open data.json | par-each {|row| expensive_operation $row}

# With index
open data.json | enumerate | each {|item| $"($item.index): ($item.item.name)"}
```

### Reduce Operations

```nushell
# Sum values
[1 2 3 4 5] | reduce {|it, acc| $acc + $it}

# Build string
["a" "b" "c"] | reduce {|it, acc| $"($acc),($it)"}

# With initial value
open data.json | get prices | reduce --fold 0 {|it, acc| $acc + $it}
```

### Merging Data

```nushell
# Merge records
{a: 1} | merge {b: 2}

# Deep merge (nested structures)
{a: {foo: 1}} | merge deep {a: {bar: 2}}

# Append to list
[1 2 3] | append [4 5 6]
```

## Real-World Examples

### Compare Manifest Versions

```nushell
# Cross-reference versions between files
open .release-please-manifest.json
| transpose plugin manifest_ver
| each {|row|
    let pjson = $"($row.plugin)/.claude-plugin/plugin.json"
    let pjson_ver = if ($pjson | path exists) {
        (open $pjson).version? | default "NOT SET"
    } else {
        "MISSING"
    }
    let status = if $row.manifest_ver == $pjson_ver { "OK" } else { "MISMATCH" }
    {plugin: $row.plugin, manifest: $row.manifest_ver, plugin_json: $pjson_ver, status: $status}
}
| sort-by plugin
```

### Process API Response

```nushell
# GitHub API - list repos with stats
http get "https://api.github.com/users/octocat/repos"
| select name stargazers_count forks_count
| sort-by stargazers_count --reverse
| first 10
```

### Analyze Package Dependencies

```nushell
# List all dependencies with versions
open package.json
| get dependencies
| transpose name version
| sort-by name
```

### Aggregate Log Data

```nushell
# Count errors by type
open logs.json
| where level == "error"
| group-by --to-table error_type
| update items {|row| $row.items | length}
| rename error_type count
| sort-by count --reverse
```

### Multi-File Analysis

```nushell
# Find all package.json files and extract versions
glob "**/package.json"
| each {|f| {file: $f, version: (open $f | get version? | default "none")}}
| sort-by file
```

### CSV Processing

```nushell
# Read CSV with headers
open data.csv
| where amount > 100
| select date description amount
| sort-by date

# Write CSV
open data.json | to csv | save output.csv
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Compact JSON | `nu -c 'open data.json \| to json -r'` |
| Quick filter | `nu -c 'open data.json \| where status == "active" \| length'` |
| Version check | `nu -c 'open package.json \| get version'` |
| Format convert | `nu -c 'open config.yaml \| to json'` |
| One-liner | `nu -c '<command>'` |

## Quick Reference

### Common Flags

| Flag | Description |
|------|-------------|
| `-c` | Execute command string |
| `-r` | Raw output (no formatting) |
| `--reverse` | Reverse sort order |
| `--to-table` | Output as table (group-by) |

### Type Conversions

| From | To | Command |
|------|-----|---------|
| String | Int | `"42" \| into int` |
| String | Float | `"3.14" \| into float` |
| Int | String | `42 \| into string` |
| List | Table | `[[a b]; [1 2] [3 4]]` |

### String Operations

```nushell
"hello" | str upcase           # HELLO
"HELLO" | str downcase         # hello
"  trim  " | str trim          # trim
"hello world" | split row " "  # [hello, world]
["a" "b"] | str join ","       # a,b
"hello" | str contains "ell"   # true
"hello" | str replace "l" "L"  # heLLo
```

### Path Operations

```nushell
"/path/to/file.txt" | path basename    # file.txt
"/path/to/file.txt" | path dirname     # /path/to
"/path/to/file.txt" | path extension   # txt
"relative/path" | path expand          # /absolute/path
"/some/path" | path exists             # true/false
```

## When to Use Nushell vs jq/yq

| Use Case | Tool |
|----------|------|
| Simple JSON field extraction | jq (faster startup) |
| Simple YAML field extraction | yq (faster startup) |
| Complex multi-step transforms | nushell |
| Multi-format processing | nushell |
| Visual data exploration | nushell |
| Cross-file operations | nushell |
| Aggregations/grouping | nushell |

## Installation

```bash
# macOS
brew install nushell

# Verify
nu --version
```

## Resources

- **Official Book**: https://www.nushell.sh/book/
- **Command Reference**: https://www.nushell.sh/commands/
- **Cookbook**: https://www.nushell.sh/cookbook/

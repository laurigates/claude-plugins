---
created: 2025-12-16
modified: 2026-08-15
reviewed: 2025-12-16
name: yq-yaml-processing
description: "yq YAML processing: query, filter, transform YAML. Use when parsing configs, modifying Kubernetes manifests or GitHub Actions workflows, or transforming YAML."
user-invocable: false
allowed-tools: Bash(yq *), Read, Write, Edit, Grep, Glob
model: sonnet
---

# yq YAML Processing

Expert knowledge for processing, querying, and transforming YAML data using yq v4+, the lightweight command-line YAML processor with jq-like syntax.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|----------------------------------|
| Querying or modifying YAML files | The input is JSON only — use `jq-json-processing` |
| Editing YAML in place while preserving comments and key order | Multi-step transforms spanning YAML, JSON, CSV, TOML — use `nushell-data-processing` |
| Targeted updates to a Kubernetes manifest or Actions workflow | Full Kubernetes management (use kubectl); XML (use xmlstarlet) |
| Merging YAML configurations | Aggregating or grouping across many files — use `nushell-data-processing` |

## Core Expertise

**YAML Operations**
- Query and filter YAML with path expressions
- Transform YAML structure and shape
- Multi-document YAML support
- Convert between YAML, JSON, XML, and other formats

**Configuration Management**
- Modify Kubernetes manifests
- Update GitHub Actions workflows
- Process Helm values files
- Manage application configurations

## Essential Commands

### Basic Querying

```bash
# Pretty-print YAML
yq '.' file.yaml

# Extract specific field
yq '.fieldName' file.yaml

# Extract nested field
yq '.spec.containers[0].name' pod.yaml

# Access array element
yq '.[0]' array.yaml
yq '.items[2]' data.yaml
```

### Reading YAML

```bash
# Read specific field
yq '.metadata.name' deployment.yaml

# Read nested structure
yq '.spec.template.spec.containers[].image' deployment.yaml

# Read with default value
yq '.optional // "default"' file.yaml

# Check if field exists
yq 'has("fieldName")' file.yaml
```

### Modifying YAML (In-Place)

```bash
# Update field value
yq -i '.metadata.name = "new-name"' file.yaml

# Update nested field
yq -i '.spec.replicas = 3' deployment.yaml

# Add new field
yq -i '.metadata.labels.app = "myapp"' file.yaml

# Delete field
yq -i 'del(.spec.nodeSelector)' file.yaml

# Append to array
yq -i '.items += {"name": "new-item"}' file.yaml

# Update all matching elements
yq -i '(.items[] | select(.name == "foo")).status = "active"' file.yaml
```

### Multi-Document YAML

```bash
# Split multi-document YAML
yq -s '.metadata.name' multi-doc.yaml

# Select specific document (0-indexed)
yq 'select(document_index == 0)' multi-doc.yaml

# Process all documents
yq eval-all '.' multi-doc.yaml

# Filter documents
yq 'select(.kind == "Deployment")' k8s-resources.yaml

# Combine YAML files
yq eval-all '. as $item ireduce ({}; . * $item)' file1.yaml file2.yaml
```

### Object Operations

```bash
# Get all keys
yq 'keys' file.yaml

# Select specific fields
yq '{name, version}' file.yaml

# Merge objects
yq '. * {"updated": true}' file.yaml
yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' base.yaml override.yaml

# Deep merge
yq eval-all '. as $item ireduce ({}; . *+ $item)' base.yaml override.yaml
```

### JSON Output (for piping)

```bash
# YAML to JSON
yq -o=json '.' file.yaml

# Compact single-line JSON — the form to pipe into jq or a tool that reads stdin
yq -o=json -I=0 '.' file.yaml
```

## Quick Reference

### Operators
- `.field` - Access field
- `.[]` - Iterate array/object
- `|` - Pipe (chain operations)
- `,` - Multiple outputs
- `//` - Alternative operator (default value)
- `*` - Merge objects (shallow)
- `*+` - Deep merge objects

### Functions
- `keys`, `values` - Object keys/values
- `length` - Array/object/string length
- `select()` - Filter
- `sort_by()` - Sort
- `group_by()` - Group
- `unique` - Remove duplicates
- `has()` - Check field existence
- `type` - Get value type
- `add` - Sum or concatenate
- `del()` - Delete field

### Flags

| Flag | Description |
|------|-------------|
| `-i` | In-place edit |
| `-o` | Output format (json, yaml, xml, csv, tsv, props) |
| `-p` | Input format (json, yaml, xml) |
| `-I` | Indent (default: 2) |
| `-r` | Raw output (no quotes) |
| `-n` | Null input (create from scratch) |
| `-s` | Split multi-document YAML |

### String Functions
- `split()`, `join()` - String/array conversion
- `contains()` - String/array contains
- `test()` - Regex match
- `sub()`, `gsub()` - String substitution
- `upcase`, `downcase` - Case conversion

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## Resources

- **Official Documentation**: https://mikefarah.gitbook.io/yq/
- **GitHub Repository**: https://github.com/mikefarah/yq
- **Try with Docker**: `docker run --rm -i mikefarah/yq '.key' <<< 'key: value'`
- **Operators Reference**: https://mikefarah.gitbook.io/yq/operators/

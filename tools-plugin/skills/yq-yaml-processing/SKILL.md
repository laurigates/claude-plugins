---
name: yq YAML Processing
description: YAML querying, filtering, and transformation with yq command-line tool. Use when working with YAML files, parsing YAML configuration, modifying Kubernetes manifests, GitHub Actions workflows, or transforming YAML structures.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# yq YAML Processing

Expert knowledge for processing, querying, and transforming YAML data using yq v4+, the lightweight command-line YAML processor with jq-like syntax.

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

# Evaluate and format
yq eval '.' file.yaml

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

### Array Operations

```bash
# Get array length
yq '.items | length' file.yaml

# Map over array
yq '.items[].name' file.yaml

# Filter array
yq '.items[] | select(.active == true)' file.yaml
yq '.users[] | select(.age > 18)' file.yaml

# Sort array
yq '.items | sort_by(.name)' file.yaml
yq '.items | sort_by(.date) | reverse' file.yaml

# Get first/last elements
yq '.items | first' file.yaml
yq '.items | last' file.yaml

# Unique values
yq '.tags | unique' file.yaml

# Filter and collect
yq '[.items[] | select(.status == "active")]' file.yaml
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

# Update array element
yq -i '.items[0].status = "updated"' file.yaml

# Update all matching elements
yq -i '(.items[] | select(.name == "foo")).status = "active"' file.yaml
```

### Multi-Document YAML

```bash
# Split multi-document YAML
yq -s '.metadata.name' multi-doc.yaml
# Creates files: doc-0.yaml, doc-1.yaml, etc.

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

# Rename field
yq '{newName: .oldName, other: .other}' file.yaml

# Merge objects
yq '. * {"updated": true}' file.yaml
yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' base.yaml override.yaml

# Deep merge
yq eval-all '. as $item ireduce ({}; . *+ $item)' base.yaml override.yaml
```

### Filtering and Conditions

```bash
# Select with conditions
yq 'select(.status == "active")' file.yaml
yq '.[] | select(.price < 100)' file.yaml

# Multiple conditions (AND)
yq '.[] | select(.active and .verified)' file.yaml
yq '.[] | select(.age > 18 and .country == "US")' file.yaml

# Multiple conditions (OR)
yq '.[] | select(.type == "admin" or .type == "moderator")' file.yaml

# Has field
yq '.[] | select(has("email"))' file.yaml

# Field not null
yq 'select(.optional != null)' file.yaml

# Not condition
yq '.[] | select(.status != "deleted")' file.yaml

# Contains (arrays)
yq '.tags | contains(["important"])' file.yaml
```

### String Operations

```bash
# String interpolation
yq '"Hello, \(.name)"' file.yaml

# Convert to string
yq '.port | tostring' file.yaml

# String contains
yq '.[] | select(.email | contains("@gmail.com"))' file.yaml

# String starts/ends with
yq '.[] | select(.name | test("^A"))' file.yaml
yq '.[] | select(.file | test("\\.yaml$"))' file.yaml

# Split string
yq '.path | split("/")' file.yaml

# Join array to string
yq '.tags | join(", ")' file.yaml

# Lowercase/uppercase
yq '.name | downcase' file.yaml
yq '.name | upcase' file.yaml

# String substitution
yq '.image | sub("v1.0"; "v2.0")' file.yaml
```

### Format Conversion

```bash
# YAML to JSON
yq -o=json '.' file.yaml

# JSON to YAML
yq -p=json '.' file.json

# YAML to XML
yq -o=xml '.' file.yaml

# YAML to CSV/TSV
yq -o=csv '.' file.yaml
yq -o=tsv '.' file.yaml

# Properties format
yq -o=props '.' file.yaml

# Compact JSON
yq -o=json -I=0 '.' file.yaml
```

### Output Formatting

```bash
# Compact output
yq -o=yaml -I=0 '.' file.yaml

# Custom indentation
yq -I=4 '.' file.yaml

# No colors
yq --no-colors '.' file.yaml

# Raw output (no quotes)
yq -r '.message' file.yaml

# Null input (create YAML from scratch)
yq -n '.name = "example" | .version = "1.0"'
```

### Real-World Examples

```bash
# Kubernetes: Get all container images
yq '.spec.template.spec.containers[].image' deployment.yaml

# Kubernetes: Update image version
yq -i '.spec.template.spec.containers[0].image = "myapp:v2.0"' deployment.yaml

# Kubernetes: Add label to all deployments
yq -i '(.metadata.labels.environment = "production")' deployment.yaml

# GitHub Actions: Extract job names
yq '.jobs | keys' .github/workflows/ci.yml

# GitHub Actions: Update checkout action version
yq -i '(.jobs.*.steps[] | select(.uses == "actions/checkout*")).uses = "actions/checkout@v5"' workflow.yml

# Docker Compose: Get all service names
yq '.services | keys' docker-compose.yml

# Docker Compose: Update service image
yq -i '.services.web.image = "nginx:latest"' docker-compose.yml

# Helm: Override values
yq -i '.replicaCount = 5 | .image.tag = "v2.0"' values.yaml

# Config: Merge environment-specific configs
yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' base-config.yaml prod-config.yaml

# Extract all environment variables
yq '.spec.template.spec.containers[].env[].name' deployment.yaml

# Create ConfigMap from key-value pairs
yq -n '.apiVersion = "v1" | .kind = "ConfigMap" | .metadata.name = "myconfig" |
  .data.key1 = "value1" | .data.key2 = "value2"'

# Batch update: Change all port references
yq -i '(.. | select(has("port"))).port = 8080' config.yaml
```

### Advanced Patterns

```bash
# Recursive descent (find all images)
yq '.. | select(has("image")) | .image' file.yaml

# Variable assignment
yq '.items[] | . as $item | $item.name + " - " + ($item.price | tostring)' file.yaml

# Conditional updates
yq -i '(.spec.replicas) |= if . < 3 then 3 else . end' deployment.yaml

# Reduce (sum, accumulate)
yq '[.items[].price] | add' file.yaml

# Group by
yq 'group_by(.category)' items.yaml

# Flatten nested arrays
yq '.items | flatten' file.yaml

# Alternative operator (default values)
yq '.optional // "default-value"' file.yaml

# Error handling with alternative
yq '.mayNotExist // empty' file.yaml
```

## Best Practices

**Query Construction**
- Use `yq eval` for complex expressions
- Test on small files first before modifying production configs
- Use `-i` flag carefully (always backup first)
- Prefer specific paths over recursive descent for performance

**Configuration Management**
- Version control before in-place edits
- Use `yq eval-all` for merging configurations
- Validate YAML after modifications
- Document complex transformations in scripts

**Multi-Document YAML**
- Use `select(document_index == N)` for specific documents
- Use `eval-all` when processing multiple documents together
- Split large multi-doc files with `-s` for easier management

**Performance**
- Use targeted queries for large files (instead of `..` recursive descent)
- Use specific paths when possible
- Process files in parallel when operating on multiple files
- Stream large files if yq supports it

## Common Patterns

### Kubernetes Manifests

```bash
# Update deployment image
yq -i '.spec.template.spec.containers[0].image = "app:v2.0"' deployment.yaml

# Scale deployment
yq -i '.spec.replicas = 5' deployment.yaml

# Add environment variable
yq -i '.spec.template.spec.containers[0].env += [{"name": "DEBUG", "value": "true"}]' deployment.yaml

# Get all resource names
yq '.metadata.name' *.yaml

# Filter by kind
yq 'select(.kind == "Service")' *.yaml

# Extract all namespaces
yq '.metadata.namespace' *.yaml | sort -u
```

### GitHub Actions Workflows

```bash
# List all jobs
yq '.jobs | keys' .github/workflows/ci.yml

# Get job steps
yq '.jobs.build.steps[].name' .github/workflows/ci.yml

# Update action version
yq -i '(.jobs.*.steps[] | select(.uses | test("actions/checkout"))).uses = "actions/checkout@v5"' workflow.yml

# Add environment variable to job
yq -i '.jobs.build.env.NODE_ENV = "production"' .github/workflows/ci.yml

# Extract trigger events
yq '.on | keys' .github/workflows/*.yml
```

### Configuration Files

```bash
# Environment-specific config merge
yq eval-all 'select(fileIndex == 0) *+ select(fileIndex == 1)' base.yaml production.yaml

# Update nested configuration
yq -i '.database.host = "prod-db.example.com"' config.yaml

# Add to array configuration
yq -i '.allowed_hosts += ["example.com"]' config.yaml

# Remove sensitive fields
yq -i 'del(.secrets)' config.yaml
```

### Docker Compose

```bash
# List services
yq '.services | keys' docker-compose.yml

# Update service image
yq -i '.services.app.image = "myapp:latest"' docker-compose.yml

# Add port mapping
yq -i '.services.web.ports += ["8080:80"]' docker-compose.yml

# Set environment variables
yq -i '.services.app.environment.DEBUG = "true"' docker-compose.yml
```

## Troubleshooting

### Invalid YAML
```bash
# Validate YAML syntax
yq '.' file.yaml  # Will show parse errors

# Check YAML structure
yq eval '.' file.yaml
```

### Empty Results
```bash
# Debug: Show entire structure
yq '.' file.yaml

# Debug: Check keys
yq 'keys' file.yaml

# Debug: Check type
yq 'type' file.yaml

# Debug: Show all scalar values
yq '.. | select(tag == "!!str")' file.yaml
```

### Unexpected In-Place Edits
```bash
# Preview changes (without -i)
yq '.field = "new-value"' file.yaml

# Backup before edit
cp file.yaml file.yaml.bak
yq -i '.field = "new-value"' file.yaml

# Use version control
git diff file.yaml
```

### Multi-Document Issues
```bash
# Count documents
yq 'document_index' multi-doc.yaml | sort -u | wc -l

# Process specific document
yq 'select(document_index == 0)' multi-doc.yaml

# Process all documents
yq eval-all '.' multi-doc.yaml
```

## Integration with Other Tools

```bash
# With kubectl (Kubernetes)
kubectl get deployment myapp -o yaml | yq '.spec.replicas'

# With helm
helm template myapp ./chart | yq 'select(.kind == "Service")'

# With git (version control)
git diff deployment.yaml | grep '^+' | yq -p yaml '.'

# With find (batch processing)
find . -name "*.yaml" -exec yq '.version' {} \;

# With jq (JSON processing)
yq -o=json '.' file.yaml | jq '.specific.field'

# With envsubst (environment variable substitution)
yq '.database.host = strenv(DB_HOST)' config.yaml
```

## yq vs jq Comparison

| Operation | jq | yq |
|-----------|----|----|
| Read field | `jq '.field'` | `yq '.field'` |
| Update in-place | Not supported | `yq -i '.field = "value"'` |
| Format output | `jq .` | `yq .` |
| Multi-file merge | `jq -s` | `yq eval-all` |
| String interpolation | `"\(.var)"` | `"\(.var)"` |
| Convert to JSON | N/A | `yq -o=json` |

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
- `-i` - In-place edit
- `-o` - Output format (json, yaml, xml, csv, tsv, props)
- `-p` - Input format (json, yaml, xml)
- `-I` - Indent (default: 2)
- `-r` - Raw output (no quotes)
- `-n` - Null input (create from scratch)
- `-s` - Split multi-document YAML

### String Functions
- `split()`, `join()` - String/array conversion
- `contains()` - String/array contains
- `test()` - Regex match
- `sub()`, `gsub()` - String substitution
- `upcase`, `downcase` - Case conversion

## Installation

```bash
# macOS (Homebrew)
brew install yq

# Note: Install mikefarah/yq (v4+), not the Python yq
brew install yq

# Ubuntu/Debian (snap)
sudo snap install yq

# Verify installation (should be v4+)
yq --version
```

**Important**: This skill assumes yq v4+ (mikefarah/yq). The older Python-based yq has different syntax.

## Resources

- **Official Documentation**: https://mikefarah.gitbook.io/yq/
- **GitHub Repository**: https://github.com/mikefarah/yq
- **Try with Docker**: `docker run --rm -i mikefarah/yq '.key' <<< 'key: value'`
- **Operators Reference**: https://mikefarah.gitbook.io/yq/operators/

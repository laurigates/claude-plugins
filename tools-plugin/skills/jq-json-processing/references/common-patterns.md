# jq — Common Patterns

Task-shaped recipes for [SKILL.md](../SKILL.md): API responses, configuration files, log analysis, and data transformation.

## Common Patterns

### API Response Processing
```bash
# GitHub API: Get PR titles and authors
gh pr list --json title,author,number | \
  jq -r '.[] | "#\(.number) - \(.title) by @\(.author.login)"'

# REST API: Extract and flatten pagination
curl -s "https://api.example.com/items" | \
  jq '.data.items[] | {id, name, status}'
```

### Configuration Files
```bash
# Extract environment-specific config
jq '.environments.production' config.json

# Update configuration value
jq '.settings.timeout = 30' config.json > config.updated.json

# Merge base config with environment overrides
jq -s '.[0] * .[1]' base-config.json prod-config.json
```

### Log Analysis
```bash
# Count errors by type
jq 'select(.level == "error") | .type' logs.json | sort | uniq -c

# Extract error messages with timestamps
jq -r 'select(.level == "error") | "\(.timestamp) - \(.message)"' logs.json

# Group by hour and count
jq -r '.timestamp | split("T")[1] | split(":")[0]' logs.json | sort | uniq -c
```

### Data Transformation
```bash
# CSV to JSON (with headers)
jq -R -s 'split("\n") | .[1:] | map(split(",")) |
  map({name: .[0], age: .[1], email: .[2]})' data.csv

# JSON to CSV
jq -r '.[] | [.name, .age, .email] | @csv' data.json

# Flatten nested structure
jq '[.items[] | {id, name, category: .meta.category}]' nested.json
```

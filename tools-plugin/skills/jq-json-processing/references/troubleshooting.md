# jq — Troubleshooting

Debugging recipes for [SKILL.md](../SKILL.md).

## Troubleshooting

### Invalid JSON
```bash
# Validate JSON syntax
jq empty file.json  # Returns exit code 0 if valid

# Find syntax errors
jq '.' file.json 2>&1 | grep "parse error"
```

### Empty Results
```bash
# Debug: Print entire structure
jq '.' file.json

# Debug: Check field existence
jq 'keys' file.json
jq 'type' file.json  # Check if array, object, etc.

# Debug: Show all values
jq '.. | scalars' file.json
```

### Type Errors
```bash
# Check field types
jq '.field | type' file.json

# Convert types safely
jq '.id | tonumber' file.json
jq '.count | tostring' file.json

# Handle mixed types
jq '.items[] | if type == "array" then .[] else . end' file.json
```

### Performance Issues
```bash
# Stream large files
jq --stream '.' large-file.json

# Process line by line
cat large.json | jq -c '.[]' | while read -r line; do
  echo "$line" | jq '.field'
done
```

---
model: haiku
description: Validate Home Assistant YAML configuration files for syntax and structure errors
args: "[path]"
allowed-tools: Bash(python3 *), Bash(docker exec *), Bash(ha *), Read, Grep, Glob
argument-hint: "Optional path to config directory (defaults to current directory)"
created: 2025-02-01
modified: 2026-02-03
reviewed: 2025-02-01
---

# /ha:validate

Validate Home Assistant configuration files for YAML syntax errors and common issues.

## Context

- Config path: `{{ path or '.' }}`
- YAML files: !`find {{ path or '.' }} -name "*.yaml" -type f 2>/dev/null`

## Validation Steps

### 1. YAML Syntax Validation

Validate all YAML files for proper syntax:

```bash
find {{ path or '.' }} -name "*.yaml" -type f -exec python3 -c "
import yaml
import sys
try:
    with open('{}', 'r') as f:
        yaml.safe_load(f)
    print('OK: {}')
except yaml.YAMLError as e:
    print('ERROR: {}')
    print(str(e)[:200])
    sys.exit(1)
" \; 2>&1 | head -50
```

### 2. Check for Common Issues

**Check for undefined secrets:**
```bash
# Find secret references
grep -rh "!secret [a-z_]*" {{ path or '.' }} --include="*.yaml" 2>/dev/null | \
  sed 's/.*!secret //' | sort -u > /tmp/used_secrets.txt

# Check if secrets.yaml exists
if [ -f "{{ path or '.' }}/secrets.yaml" ]; then
  echo "secrets.yaml found"
  # List defined secrets
  grep "^[a-z_]*:" {{ path or '.' }}/secrets.yaml | sed 's/:.*//' | sort -u > /tmp/defined_secrets.txt
  echo "Undefined secrets:"
  comm -23 /tmp/used_secrets.txt /tmp/defined_secrets.txt
else
  echo "WARNING: secrets.yaml not found"
fi
```

**Check for duplicate keys:**
```bash
python3 -c "
import yaml
import sys
from collections import Counter

class DuplicateKeyChecker(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        keys = [k.value for k, v in node.value if isinstance(k, yaml.ScalarNode)]
        duplicates = [k for k, count in Counter(keys).items() if count > 1]
        if duplicates:
            print(f'Duplicate keys in {node.start_mark}: {duplicates}')
        return super().construct_mapping(node, deep)

for f in ['configuration.yaml', 'automations.yaml', 'scripts.yaml', 'scenes.yaml']:
    path = '{{ path or '.' }}/' + f
    try:
        with open(path) as file:
            yaml.load(file, Loader=DuplicateKeyChecker)
            print(f'OK: {f}')
    except FileNotFoundError:
        pass
    except yaml.YAMLError as e:
        print(f'ERROR in {f}: {e}')
" 2>&1
```

### 3. Docker-based Full Validation (if available)

If Home Assistant is running in Docker:

```bash
docker exec homeassistant hass --script check_config 2>&1 | head -100 || echo "Docker validation not available"
```

### 4. Home Assistant OS Validation (if available)

```bash
ha core check 2>&1 || echo "HA OS validation not available"
```

## Post-Validation

Report validation results:
- List any YAML syntax errors with file and line numbers
- List any undefined secret references
- List any duplicate keys
- Suggest fixes for common issues

## Common Fixes

| Issue | Fix |
|-------|-----|
| `found undefined alias` | Add missing entry to secrets.yaml |
| `could not determine a constructor` | Check YAML indentation |
| `duplicate key` | Remove or rename duplicate key |
| `expected <block end>` | Fix indentation alignment |
| `mapping values are not allowed` | Add space after colon |

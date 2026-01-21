# P1: Stale Content Detection Hook

**Priority**: P1 (Important)
**Type**: PreToolUse (on Read)
**Status**: Planned

## Overview

Warn when reading ai_docs that haven't been updated recently, suggesting they may contain outdated information.

## Trigger

```json
{
  "matcher": "Read(docs/blueprint/ai_docs/**)",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/check-stale-ai-docs.sh",
      "timeout": 3000,
      "continueOnError": true
    }
  ]
}
```

## Behavior

### Input

JSON from PreToolUse containing:
- `tool_input.file_path`: Path to the ai_doc being read

### Processing

1. **Extract file modification date**
   ```bash
   # Get modification date from filesystem or frontmatter
   get_modification_date() {
     local file="$1"
     # First try frontmatter
     local fm_date=$(head -50 "$file" | grep -m1 "^modified:" | sed 's/^[^:]*:[[:space:]]*//')
     if [ -n "$fm_date" ]; then
       echo "$fm_date"
     else
       # Fall back to file mtime
       stat -f "%Sm" -t "%Y-%m-%d" "$file" 2>/dev/null || stat -c "%y" "$file" 2>/dev/null | cut -d' ' -f1
     fi
   }
   ```

2. **Calculate age in days**
   ```bash
   calculate_age_days() {
     local date_str="$1"
     local then_epoch=$(date -j -f "%Y-%m-%d" "$date_str" "+%s" 2>/dev/null || date -d "$date_str" "+%s")
     local now_epoch=$(date "+%s")
     echo $(( (now_epoch - then_epoch) / 86400 ))
   }
   ```

3. **Check staleness threshold** (90 days)

4. **Warn if stale**
   ```
   WARNING: ai_docs/libraries/react.md is 95 days old. Consider running /blueprint:curate-docs to refresh
   ```

### Output (Warning Only)

```
WARNING: docs/blueprint/ai_docs/libraries/react.md is 127 days old
INFO: Consider running /blueprint:curate-docs to refresh this documentation
```

## Staleness Threshold

**Default**: 90 days

ai_docs older than 90 days may reference:
- Deprecated API patterns
- Outdated library versions
- Changed best practices

## Implementation Notes

### Date Parsing Compatibility

macOS and Linux have different `date` and `stat` syntax:

```bash
# Cross-platform modification date
get_file_mtime() {
  local file="$1"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    stat -f "%Sm" -t "%Y-%m-%d" "$file"
  else
    stat -c "%y" "$file" | cut -d' ' -f1
  fi
}

# Cross-platform date parsing
parse_date_to_epoch() {
  local date_str="$1"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    date -j -f "%Y-%m-%d" "$date_str" "+%s" 2>/dev/null
  else
    date -d "$date_str" "+%s" 2>/dev/null
  fi
}
```

### Suggested Action

Always suggest `/blueprint:curate-docs` as the remediation action:

```bash
suggest_action() {
  local file="$1"
  local lib_name=$(basename "$file" .md)
  echo "INFO: Consider running /blueprint:curate-docs to refresh documentation for: $lib_name"
}
```

### Error Handling

- Non-blocking (warn only, `continueOnError: true`)
- Skip files without parseable dates
- Skip non-ai_docs files (shouldn't match, but safe to check)

## Testing Strategy

### Test Cases

1. **Fresh ai_doc (< 90 days)**
   - Input: Read ai_doc modified 30 days ago
   - Expected: No warning, read proceeds

2. **Stale ai_doc (> 90 days)**
   - Input: Read ai_doc modified 120 days ago
   - Expected: WARNING logged, read proceeds

3. **ai_doc without modified date**
   - Input: ai_doc with no frontmatter
   - Expected: Use file mtime, then apply threshold

4. **Non-ai_doc file**
   - Input: Read from docs/prps/
   - Expected: Hook shouldn't trigger (matcher mismatch)

### ShellSpec Tests

```shell
Describe "check-stale-ai-docs.sh"
  Describe "fresh content"
    It "allows read without warning for recent files"
      # Create fresh ai_doc
      mkdir -p docs/blueprint/ai_docs/libraries
      echo -e "---\nmodified: $(date +%Y-%m-%d)\n---\n# React" > docs/blueprint/ai_docs/libraries/react.md

      input='{"tool_input": {"file_path": "docs/blueprint/ai_docs/libraries/react.md"}}'
      When call bash -c "echo '$input' | bash $HOOK_SCRIPT"
      The status should equal 0
      The stderr should not include "WARNING"
    End
  End

  Describe "stale content"
    It "warns for files older than 90 days"
      mkdir -p docs/blueprint/ai_docs/libraries
      echo -e "---\nmodified: 2024-01-01\n---\n# Old React" > docs/blueprint/ai_docs/libraries/react.md

      input='{"tool_input": {"file_path": "docs/blueprint/ai_docs/libraries/react.md"}}'
      When call bash -c "echo '$input' | bash $HOOK_SCRIPT"
      The status should equal 0  # Non-blocking
      The stderr should include "WARNING"
      The stderr should include "curate-docs"
    End
  End
End
```

## Configuration

### Per-Project Override

Projects can customize the staleness threshold via `.blueprint/hooks.json`:

```json
{
  "overrides": {
    "stale_content_days": 60
  }
}
```

The hook checks for this config:

```bash
get_staleness_threshold() {
  local config=".blueprint/hooks.json"
  if [ -f "$config" ]; then
    local threshold=$(jq -r '.overrides.stale_content_days // empty' "$config")
    if [ -n "$threshold" ]; then
      echo "$threshold"
      return
    fi
  fi
  echo "90"  # Default
}
```

## Dependencies

- `jq` for config parsing (optional)
- Cross-platform date utilities

## Estimated Effort

- Implementation: Low
- Testing: Low
- Documentation: Low

## Open Questions

1. Should we track which ai_docs have been warned about to avoid repeated warnings?
   - **Decision**: No. Each read operation is independent. Users can refresh docs to clear warnings.

2. Should staleness check library version from package.json?
   - **Decision**: P3 scope (Dependency Change Watcher). This hook just checks age.

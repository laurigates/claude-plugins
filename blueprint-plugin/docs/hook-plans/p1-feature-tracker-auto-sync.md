# P1: Feature Tracker Auto-Sync Hook

**Priority**: P1 (Important)
**Type**: PostToolUse
**Status**: Planned

## Overview

Automatically synchronize the feature tracker (`docs/blueprint/feature-tracker.json`) when documents in the `docs/` directory change.

## Trigger

```json
{
  "matcher": "Write(docs/**)|Edit(docs/**)",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/sync-feature-tracker.sh",
      "timeout": 5000,
      "continueOnError": true
    }
  ]
}
```

**Rationale for trigger scope**: "On any docs/* change" - broader than just PRPs because:
- PRDs may add new feature codes
- ADRs may reference features
- Work overviews track feature progress

## Behavior

### Input

JSON from PostToolUse containing:
- `tool_input.file_path`: Path to the modified file
- `tool_input.content` (for Write) or `tool_input.old_string`/`tool_input.new_string` (for Edit)

### Processing

1. **Check if feature tracker exists**
   ```bash
   if [ ! -f "docs/blueprint/feature-tracker.json" ]; then
     echo "INFO: Feature tracker not found, skipping sync"
     exit 0
   fi
   ```

2. **Extract feature codes from changed file**
   - Look for patterns: `FR1.1`, `FR2.1.1`, etc.
   - Parse from frontmatter `feature-codes:` array
   - Parse from inline references

3. **Compare with current tracker state**
   - Load existing feature-tracker.json
   - Identify features that need status updates

4. **Update tracker**
   - Update `modified` timestamp
   - Recalculate completion statistics
   - Write back to feature-tracker.json

5. **Sync dependent docs** (optional)
   - Update `TODO.md` checkboxes

### Output

```
INFO: Feature tracker updated: 2 features modified
INFO: Completion: 12/25 (48%)
```

## Implementation Notes

### Feature Code Extraction

```bash
# Extract from frontmatter
extract_feature_codes() {
  local file="$1"
  head -50 "$file" | awk '
    /^feature-codes:/ { in_codes = 1; next }
    in_codes && /^[[:space:]]*-/ { gsub(/^[[:space:]]*-[[:space:]]*/, ""); print }
    in_codes && /^[a-z]/ { exit }
  '
}

# Extract from inline references
extract_inline_codes() {
  local file="$1"
  grep -oE 'FR[0-9]+(\.[0-9]+)*' "$file" | sort -u
}
```

### Tracker Update Logic

```bash
# Update feature status using jq
update_tracker() {
  local feature_code="$1"
  local new_status="$2"

  jq --arg code "$feature_code" --arg status "$new_status" '
    .features[$code].status = $status |
    .features[$code].modified = (now | strftime("%Y-%m-%d"))
  ' docs/blueprint/feature-tracker.json > tmp.json && \
  mv tmp.json docs/blueprint/feature-tracker.json
}
```

### Error Handling

- Non-blocking (warn only)
- Skip if feature-tracker.json doesn't exist
- Skip if file doesn't contain feature codes
- Log errors but don't interrupt workflow

## Testing Strategy

### Test Cases

1. **PRP with new feature codes**
   - Input: Write PRP with FR codes not in tracker
   - Expected: Tracker unchanged (codes need explicit addition)

2. **PRP with existing feature codes**
   - Input: Write PRP referencing tracked features
   - Expected: Tracker shows modified timestamp updated

3. **No feature tracker**
   - Input: Write PRP in project without tracker
   - Expected: Hook exits silently with INFO message

4. **Malformed tracker JSON**
   - Input: Corrupted feature-tracker.json
   - Expected: Warning logged, no changes made

### ShellSpec Tests

```shell
Describe "sync-feature-tracker.sh"
  Describe "feature tracker exists"
    It "updates tracker when PRP changes"
      # Setup
      mkdir -p docs/blueprint
      echo '{"features": {"FR1.1": {"status": "not_started"}}}' > docs/blueprint/feature-tracker.json
      echo -e "---\nfeature-codes:\n  - FR1.1\n---" > docs/prps/test.md

      input='{"tool_input": {"file_path": "docs/prps/test.md"}}'
      When call bash -c "echo '$input' | bash $HOOK_SCRIPT"
      The status should equal 0
      The stderr should include "Feature tracker updated"
    End
  End
End
```

## Dependencies

- `jq` for JSON manipulation
- Feature tracker schema (docs/blueprint/feature-tracker.json)

## Estimated Effort

- Implementation: Medium
- Testing: Medium
- Documentation: Low

## Open Questions

1. Should the hook create missing feature codes in the tracker, or just update existing ones?
   - **Decision**: Only update existing codes. New codes require explicit addition via /blueprint:feature-tracker-sync.

2. How should partial completions be detected?
   - **Decision**: Parse PRP status field and success criteria to infer completion level.

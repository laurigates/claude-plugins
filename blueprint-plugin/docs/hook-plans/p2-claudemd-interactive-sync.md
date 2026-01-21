# P2: CLAUDE.md Interactive Sync Hook

**Priority**: P2 (Nice to Have)
**Type**: PostToolUse
**Status**: Planned

## Overview

When PRD documents change, analyze the diff and present selectable options to the user for updating CLAUDE.md. Uses the `AskUserQuestion` tool for interactive selection.

## Trigger

```json
{
  "matcher": "Write(docs/prds/**)|Edit(docs/prds/**)",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/suggest-claudemd-updates.sh",
      "timeout": 5000,
      "continueOnError": true
    }
  ]
}
```

## Behavior

### Input

JSON from PostToolUse containing:
- `tool_input.file_path`: Path to the modified PRD
- `tool_input.content` (for Write) or changes (for Edit)

### Processing Flow

1. **Detect PRD changes**
   - Parse the modified PRD
   - Extract key sections that may affect CLAUDE.md

2. **Analyze impact on CLAUDE.md**
   - Compare PRD sections with CLAUDE.md content
   - Identify potential updates needed

3. **Generate diff hints**
   - Create concise descriptions of suggested changes
   - Format as selectable options

4. **Present via AskUserQuestion**
   - Show diff hints as multi-select options
   - Include "No changes needed" option
   - User selects which updates to apply

5. **Apply selected changes**
   - Only update CLAUDE.md for selected options
   - If no selections, make no changes

### AskUserQuestion Integration

This hook uses a special pattern - it outputs a structured response that Claude can interpret to invoke `AskUserQuestion`:

```json
{
  "action": "ask_user",
  "questions": [
    {
      "question": "PRD 'user-authentication' was updated. Which changes should be reflected in CLAUDE.md?",
      "header": "CLAUDE.md Sync",
      "multiSelect": true,
      "options": [
        {
          "label": "Add JWT authentication section",
          "description": "PRD added JWT token handling requirements"
        },
        {
          "label": "Update API endpoints list",
          "description": "PRD added /auth/login and /auth/refresh endpoints"
        },
        {
          "label": "Add security considerations",
          "description": "PRD includes new security requirements section"
        },
        {
          "label": "Skip this time",
          "description": "Don't update CLAUDE.md now"
        }
      ]
    }
  ]
}
```

### Output Handling

The hook outputs a structured response. The skill/command that invokes this hook should:

1. Check if output contains `"action": "ask_user"`
2. If yes, invoke AskUserQuestion with the provided questions
3. Based on user selection, apply the corresponding CLAUDE.md updates

## Diff Analysis Logic

### Sections to Compare

| PRD Section | CLAUDE.md Impact |
|-------------|------------------|
| ## Features | Update feature list |
| ## API | Update endpoints/API section |
| ## Architecture | Update project structure |
| ## Security | Update security guidelines |
| ## Dependencies | Update tech stack |

### Diff Detection

```bash
# Extract sections from PRD
extract_sections() {
  local file="$1"
  grep -E "^##\s+" "$file" | sed 's/^##\s*//'
}

# Compare with CLAUDE.md
detect_missing_sections() {
  local prd_sections=$(extract_sections "$PRD_FILE")
  local claude_sections=$(extract_sections "CLAUDE.md")

  # Find sections in PRD not adequately covered in CLAUDE.md
  for section in $prd_sections; do
    if ! echo "$claude_sections" | grep -qi "$section"; then
      echo "$section"
    fi
  done
}
```

### Change Impact Analysis

```bash
# Analyze what changed and its impact
analyze_impact() {
  local prd="$1"
  local impacts=()

  # Check for new API endpoints
  if grep -q "^###.*endpoint" "$prd" || grep -q "POST\|GET\|PUT\|DELETE" "$prd"; then
    impacts+=("api_endpoints")
  fi

  # Check for security requirements
  if grep -qi "security\|authentication\|authorization\|jwt\|oauth" "$prd"; then
    impacts+=("security")
  fi

  # Check for dependency changes
  if grep -qi "dependency\|package\|library\|framework" "$prd"; then
    impacts+=("dependencies")
  fi

  printf '%s\n' "${impacts[@]}"
}
```

## Implementation Architecture

Since shell hooks can't directly invoke `AskUserQuestion`, this hook uses a two-phase approach:

### Phase 1: Hook Script (suggest-claudemd-updates.sh)

```bash
#!/bin/bash
# Outputs structured JSON for the caller to interpret

# Analyze changes...
# ...

# Output structured response
cat << EOF
{
  "action": "ask_user",
  "context": {
    "prd_file": "$PRD_FILE",
    "changes_detected": $CHANGES_JSON
  },
  "questions": [
    {
      "question": "...",
      "options": [...]
    }
  ]
}
EOF
```

### Phase 2: Skill Integration

The `/blueprint:sync` or similar command should:

1. Check hook output for `"action": "ask_user"`
2. Extract questions and invoke AskUserQuestion tool
3. Process user selections
4. Apply corresponding CLAUDE.md updates

```markdown
## Execution (in skill)

After PRD modification, check for sync suggestions:
1. If hook output contains `"action": "ask_user"`:
   - Present options to user via AskUserQuestion
   - Apply selected updates to CLAUDE.md
2. If no action needed:
   - Continue normally
```

## Update Templates

For each change type, define an update template:

### API Endpoints

```markdown
## API Endpoints (Auto-synced from PRD)

| Endpoint | Method | Description |
|----------|--------|-------------|
| /auth/login | POST | User authentication |
| /auth/refresh | POST | Token refresh |
```

### Security Section

```markdown
## Security Considerations

- JWT tokens for authentication (see PRD: user-authentication)
- Rate limiting on auth endpoints
- HTTPS required for all auth operations
```

## Testing Strategy

### Test Cases

1. **PRD with new API endpoints**
   - Input: PRD adds /api/users endpoint
   - Expected: Hook suggests adding API section to CLAUDE.md

2. **PRD with security requirements**
   - Input: PRD adds JWT authentication
   - Expected: Hook suggests security section update

3. **No significant changes**
   - Input: PRD with minor wording changes
   - Expected: No suggestions (skip sync)

4. **User selects no options**
   - Input: User chooses "Skip this time"
   - Expected: CLAUDE.md unchanged

### Integration Testing

Test the full flow:
1. Modify a PRD
2. Hook detects changes
3. AskUserQuestion presented
4. User makes selection
5. CLAUDE.md updated accordingly

## Dependencies

- `jq` for JSON generation
- AskUserQuestion tool (via Claude Code)
- Skill/command to interpret hook output

## Estimated Effort

- Implementation: High (requires skill integration)
- Testing: High (interactive component)
- Documentation: Medium

## Open Questions

1. How to handle cases where CLAUDE.md doesn't exist yet?
   - **Decision**: Suggest creating it via `/blueprint:claude-md` first.

2. Should updates be cumulative or replace existing sections?
   - **Decision**: Cumulative by default, with option to replace.

3. How to track which PRD changes have already been synced?
   - **Decision**: Use CLAUDE.md frontmatter or comments to track sync state.

## Alternative Implementation

If shell hook + skill integration is too complex, consider:

**Skill-only approach**: Instead of a PostToolUse hook, create a `/blueprint:sync-claude-md` command that:
1. Detects recent PRD changes via git diff
2. Presents AskUserQuestion directly
3. Applies updates

This is simpler but requires manual invocation rather than automatic triggering.

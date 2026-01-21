# P2: ADR Conflict Detection Hook

**Priority**: P2 (Nice to Have)
**Type**: PostToolUse
**Status**: Planned

## Overview

Detect potential conflicts when creating or modifying ADRs. Warn when two ADRs share the same domain and both have `status: Accepted`, as this may indicate conflicting architecture decisions.

## Trigger

```json
{
  "matcher": "Write(docs/adrs/**)",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/detect-adr-conflicts.sh",
      "timeout": 5000,
      "continueOnError": true
    }
  ]
}
```

## Behavior

### Input

JSON from PostToolUse containing:
- `tool_input.file_path`: Path to the new/modified ADR
- `tool_input.content`: Content of the ADR

### Processing

1. **Extract domain from new ADR**
   ```bash
   get_domain() {
     local content="$1"
     echo "$content" | head -50 | grep -m1 "^domain:" | sed 's/^[^:]*:[[:space:]]*//'
   }
   ```

2. **Extract status from new ADR**
   ```bash
   get_status() {
     local content="$1"
     echo "$content" | head -50 | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//'
   }
   ```

3. **Scan existing ADRs for same domain + Accepted status**
   ```bash
   find_conflicting_adrs() {
     local domain="$1"
     local current_file="$2"

     for adr in docs/adrs/*.md; do
       [ "$adr" = "$current_file" ] && continue

       local adr_domain=$(head -50 "$adr" | grep -m1 "^domain:" | sed 's/^[^:]*:[[:space:]]*//')
       local adr_status=$(head -50 "$adr" | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//')

       if [ "$adr_domain" = "$domain" ] && [ "$adr_status" = "Accepted" ]; then
         echo "$adr"
       fi
     done
   }
   ```

4. **Warn if conflicts found**

### Output

**No conflict:**
```
INFO: ADR domain 'authentication' - no conflicts detected
```

**Conflict detected:**
```
WARNING: ADR conflict detected in domain 'authentication'
WARNING: Existing Accepted ADR: docs/adrs/0003-jwt-auth.md
INFO: Consider:
INFO:   - Adding 'supersedes: 0003' to indicate replacement
INFO:   - Updating 0003 to 'status: Superseded' with 'superseded-by: 0007'
INFO:   - Clarifying scope difference if both decisions are valid
```

## Conflict Definition

A conflict is detected when:

| New ADR | Existing ADR | Conflict? |
|---------|--------------|-----------|
| domain: auth, status: Accepted | domain: auth, status: Accepted | **YES** |
| domain: auth, status: Proposed | domain: auth, status: Accepted | No (review in progress) |
| domain: auth, status: Accepted | domain: auth, status: Superseded | No (replaced) |
| domain: auth, status: Accepted | domain: database, status: Accepted | No (different domain) |

**Key rule**: Same domain + both status: Accepted = potential conflict

## Implementation

### detect-adr-conflicts.sh

```bash
#!/bin/bash
set -euo pipefail

# Check for bypass
if [ "${BLUEPRINT_SKIP_HOOKS:-0}" = "1" ]; then
    exit 0
fi

INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# If no content, skip (read operation)
[ -z "$CONTENT" ] && exit 0

# Extract domain and status from new ADR
NEW_DOMAIN=$(echo "$CONTENT" | head -50 | grep -m1 "^domain:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
NEW_STATUS=$(echo "$CONTENT" | head -50 | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')

# If no domain, skip conflict detection
if [ -z "$NEW_DOMAIN" ]; then
    echo "INFO: ADR has no domain field - skipping conflict detection" >&2
    exit 0
fi

# Only check for conflicts if new ADR is Accepted
if [ "$NEW_STATUS" != "Accepted" ]; then
    echo "INFO: ADR status is '$NEW_STATUS' - conflict check applies to Accepted ADRs" >&2
    exit 0
fi

# Find conflicting ADRs
CONFLICTS=()
for adr in docs/adrs/*.md; do
    [ ! -f "$adr" ] && continue
    [ "$adr" = "$FILE_PATH" ] && continue

    adr_domain=$(head -50 "$adr" | grep -m1 "^domain:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
    adr_status=$(head -50 "$adr" | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')

    if [ "$adr_domain" = "$NEW_DOMAIN" ] && [ "$adr_status" = "Accepted" ]; then
        CONFLICTS+=("$adr")
    fi
done

# Report conflicts
if [ ${#CONFLICTS[@]} -gt 0 ]; then
    echo "WARNING: ADR conflict detected in domain '$NEW_DOMAIN'" >&2
    for conflict in "${CONFLICTS[@]}"; do
        echo "WARNING: Existing Accepted ADR: $conflict" >&2
    done
    echo "INFO: Consider:" >&2
    echo "INFO:   - Adding 'supersedes:' to indicate this replaces the existing ADR" >&2
    echo "INFO:   - Updating existing ADR to 'status: Superseded'" >&2
    echo "INFO:   - Clarifying scope difference if both decisions are valid" >&2
else
    echo "INFO: ADR domain '$NEW_DOMAIN' - no conflicts detected" >&2
fi

exit 0
```

## Domain Taxonomy

For conflict detection to work well, projects should use consistent domain names:

| Domain | Covers |
|--------|--------|
| `authentication` | Auth methods, tokens, sessions |
| `authorization` | Permissions, roles, access control |
| `database` | Data storage, ORMs, migrations |
| `api` | API design, versioning, protocols |
| `frontend` | UI framework, state management |
| `testing` | Test strategy, frameworks, coverage |
| `deployment` | CI/CD, hosting, infrastructure |
| `security` | Security practices, encryption |

Projects can define their own domains. The key is consistency.

## Testing Strategy

### Test Cases

1. **No conflict - different domain**
   - Input: New ADR with domain: api
   - Existing: ADR with domain: database, status: Accepted
   - Expected: No warning

2. **No conflict - existing not Accepted**
   - Input: New ADR with domain: auth, status: Accepted
   - Existing: ADR with domain: auth, status: Superseded
   - Expected: No warning

3. **Conflict detected**
   - Input: New ADR with domain: auth, status: Accepted
   - Existing: ADR with domain: auth, status: Accepted
   - Expected: WARNING with conflict details

4. **New ADR not Accepted**
   - Input: New ADR with domain: auth, status: Proposed
   - Existing: ADR with domain: auth, status: Accepted
   - Expected: No warning (review in progress)

5. **No domain field**
   - Input: New ADR without domain frontmatter
   - Expected: INFO message, skip conflict check

### ShellSpec Tests

```shell
Describe "detect-adr-conflicts.sh"
  BeforeEach() {
    export TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/docs/adrs"
    cd "$TEST_DIR"
  }

  AfterEach() {
    cd /
    rm -rf "$TEST_DIR"
  }

  Describe "conflict detection"
    It "warns when same domain both Accepted"
      # Create existing ADR
      cat > docs/adrs/0001-existing.md << 'EOF'
---
status: Accepted
domain: authentication
---
# Existing Auth ADR
EOF

      # New ADR content
      input='{"tool_input": {"file_path": "docs/adrs/0002-new.md", "content": "---\nstatus: Accepted\ndomain: authentication\n---\n# New Auth ADR"}}'

      When call bash -c "echo '$input' | bash $HOOK_SCRIPT"
      The status should equal 0
      The stderr should include "WARNING: ADR conflict detected"
      The stderr should include "0001-existing.md"
    End

    It "no warning for different domains"
      cat > docs/adrs/0001-db.md << 'EOF'
---
status: Accepted
domain: database
---
# Database ADR
EOF

      input='{"tool_input": {"file_path": "docs/adrs/0002-api.md", "content": "---\nstatus: Accepted\ndomain: api\n---\n# API ADR"}}'

      When call bash -c "echo '$input' | bash $HOOK_SCRIPT"
      The status should equal 0
      The stderr should not include "WARNING"
    End
  End
End
```

## Dependencies

- `jq` for JSON parsing
- Consistent use of `domain:` frontmatter field in ADRs

## Estimated Effort

- Implementation: Low
- Testing: Medium
- Documentation: Low

## Open Questions

1. Should conflicts block ADR creation or just warn?
   - **Decision**: Warn only (non-blocking). Conflicts may be intentional during transition periods.

2. Should we detect conflicts for Proposed ADRs?
   - **Decision**: No. Proposed ADRs are still under review; conflicts will be resolved during acceptance.

3. How to handle multiple existing conflicts?
   - **Decision**: List all conflicting ADRs in the warning.

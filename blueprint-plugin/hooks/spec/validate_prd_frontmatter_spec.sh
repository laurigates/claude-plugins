#!/usr/bin/env bash
# ShellSpec tests for validate-prd-frontmatter.sh

Describe "validate-prd-frontmatter.sh"
  HOOK_SCRIPT="$SHELLSPEC_PROJECT_ROOT/validate-prd-frontmatter.sh"

  Describe "valid PRD"
    It "passes validation for a complete PRD"
      Data
        #|{"tool_input": {"content": "---\nid: PRD-001\ntitle: User Auth\nstatus: Active\ncreated: 2025-01-20\nmodified: 2025-01-20\n---\n\n# User Auth\n\nContent here."}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 0
      The stderr should include "INFO: PRD frontmatter validation passed"
    End
  End

  Describe "missing id field"
    It "blocks when id field is missing"
      Data
        #|{"tool_input": {"content": "---\ntitle: No ID\nstatus: Draft\ncreated: 2025-01-20\nmodified: 2025-01-20\n---\n\n# No ID"}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 2
      The stderr should include "ERROR: Missing required frontmatter field: id"
    End
  End

  Describe "invalid id format"
    It "blocks when id format is wrong"
      Data
        #|{"tool_input": {"content": "---\nid: PRD1\nstatus: Draft\ncreated: 2025-01-20\nmodified: 2025-01-20\n---\n\n# Bad ID"}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 2
      The stderr should include "ERROR: Invalid PRD id format"
    End
  End

  Describe "invalid status"
    It "blocks when status is not in valid set"
      Data
        #|{"tool_input": {"content": "---\nid: PRD-001\nstatus: Pending\ncreated: 2025-01-20\nmodified: 2025-01-20\n---\n\n# Bad Status"}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 2
      The stderr should include "ERROR: Invalid PRD status"
    End
  End

  Describe "valid statuses"
    Parameters
      "Draft"
      "Active"
      "Completed"
      "Deprecated"
      "Proposed"
    End

    It "accepts valid status: $1"
      input="{\"tool_input\": {\"content\": \"---\\nid: PRD-001\\nstatus: $1\\ncreated: 2025-01-20\\nmodified: 2025-01-20\\n---\\n\\n# PRD\"}}"
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The stderr should include "PRD frontmatter validation passed"
    End
  End

  Describe "missing required field"
    It "blocks when status field is missing"
      Data
        #|{"tool_input": {"content": "---\nid: PRD-001\ncreated: 2025-01-20\nmodified: 2025-01-20\n---\n\n# PRD"}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 2
      The stderr should include "ERROR: Missing required frontmatter field: status"
    End
  End

  Describe "bypass mode"
    It "skips validation when BLUEPRINT_SKIP_HOOKS=1"
      export BLUEPRINT_SKIP_HOOKS=1
      Data
        #|{}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 0
    End
  End

  Describe "empty content"
    It "allows empty content (read operations)"
      Data
        #|{"tool_input": {}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 0
    End
  End

  Describe "missing title warning"
    It "warns when title field is missing but doesn't block"
      Data
        #|{"tool_input": {"content": "---\nid: PRD-001\nstatus: Draft\ncreated: 2025-01-20\nmodified: 2025-01-20\n---\n\n# PRD"}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 0
      The stderr should include "WARNING: Missing 'title' field"
    End
  End
End

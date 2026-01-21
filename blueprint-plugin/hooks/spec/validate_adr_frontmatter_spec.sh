#!/bin/bash
# ShellSpec tests for validate-adr-frontmatter.sh

Describe "validate-adr-frontmatter.sh"
  HOOK_SCRIPT="$SHELLSPEC_PROJECT_ROOT/validate-adr-frontmatter.sh"

  Describe "valid ADR"
    It "passes validation for a complete ADR"
      Data
        #|{"tool_input": {"content": "---\nstatus: Accepted\ncreated: 2025-01-20\nmodified: 2025-01-20\ndomain: authentication\n---\n\n# ADR 0001\n\n## Context\n\nContext here.\n\n## Decision\n\nDecision here.\n\n## Consequences\n\nConsequences here.\n\n## Options Considered\n\n1. Option A\n\n## Related ADRs\n\nNone."}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 0
      The stderr should include "INFO: ADR frontmatter validation passed"
    End
  End

  Describe "invalid status"
    It "blocks when status is not in valid set"
      Data
        #|{"tool_input": {"content": "---\nstatus: Pending\ncreated: 2025-01-20\nmodified: 2025-01-20\ndomain: api\n---\n\n## Context\n\n## Decision\n\n## Consequences\n\n## Options Considered\n\n## Related ADRs\n"}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 2
      The stderr should include "ERROR: Invalid ADR status"
    End
  End

  Describe "valid statuses"
    Parameters
      "Draft"
      "Proposed"
      "Accepted"
      "Rejected"
      "Withdrawn"
      "Superseded"
      "Deprecated"
    End

    It "accepts valid status: $1"
      input="{\"tool_input\": {\"content\": \"---\\nstatus: $1\\ncreated: 2025-01-20\\nmodified: 2025-01-20\\ndomain: test\\n---\\n\\n## Context\\n\\n## Decision\\n\\n## Consequences\\n\\n## Options Considered\\n\\n## Related ADRs\\n\"}}"
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The stderr should include "ADR frontmatter validation passed"
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

  Describe "missing required section"
    It "blocks when Decision section is missing"
      Data
        #|{"tool_input": {"content": "---\nstatus: Proposed\ncreated: 2025-01-20\nmodified: 2025-01-20\n---\n\n## Context\n\nSome context.\n\n## Consequences\n\n## Options Considered\n\n## Related ADRs\n"}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 2
      The stderr should include "ERROR: Missing required section: ## Decision"
    End
  End

  Describe "missing domain warning"
    It "warns when domain field is missing but doesn't block"
      Data
        #|{"tool_input": {"content": "---\nstatus: Proposed\ncreated: 2025-01-20\nmodified: 2025-01-20\n---\n\n## Context\n\n## Decision\n\n## Consequences\n\n## Options Considered\n\n## Related ADRs\n"}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 0
      The stderr should include "WARNING: Missing 'domain' field"
    End
  End
End

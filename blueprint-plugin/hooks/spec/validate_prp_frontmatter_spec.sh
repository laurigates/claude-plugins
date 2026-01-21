#!/bin/bash
# ShellSpec tests for validate-prp-frontmatter.sh

Describe "validate-prp-frontmatter.sh"
  HOOK_SCRIPT="$SHELLSPEC_PROJECT_ROOT/validate-prp-frontmatter.sh"
  FIXTURES="$SHELLSPEC_PROJECT_ROOT/spec/fixtures"

  Describe "valid PRP"
    It "passes validation for a complete PRP"
      Data
        #|{"tool_input": {"content": "---\ncreated: 2025-01-20\nmodified: 2025-01-20\nreviewed: 2025-01-20\nstatus: ready\nconfidence: 8/10\ndomain: auth\nfeature-codes:\n  - FR1.1\nrelated:\n  - docs/adrs/0001.md\n---\n\n# PRP\n\n## Context Framing\n\nContext.\n\n## AI Documentation\n\nDocs.\n\n## Implementation Blueprint\n\nSteps.\n\n## Test Strategy\n\nTests.\n\n## Validation Gates\n\nGates.\n\n## Success Criteria\n\nCriteria."}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 0
      The stderr should include "INFO: PRP frontmatter validation passed"
    End
  End

  Describe "missing required field"
    It "blocks when status field is missing"
      Data
        #|{"tool_input": {"content": "---\ncreated: 2025-01-20\nmodified: 2025-01-20\nreviewed: 2025-01-20\nconfidence: 7/10\ndomain: auth\nfeature-codes: []\nrelated: []\n---\n\n# PRP\n\n## Context Framing\n\n## AI Documentation\n\n## Implementation Blueprint\n\n## Test Strategy\n\n## Validation Gates\n\n## Success Criteria\n"}}
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

  Describe "invalid confidence format"
    It "blocks on invalid confidence format"
      Data
        #|{"tool_input": {"content": "---\ncreated: 2025-01-20\nmodified: 2025-01-20\nreviewed: 2025-01-20\nstatus: draft\nconfidence: high\ndomain: api\nfeature-codes: []\nrelated: []\n---\n\n## Context Framing\n\n## AI Documentation\n\n## Implementation Blueprint\n\n## Test Strategy\n\n## Validation Gates\n\n## Success Criteria\n"}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 2
      The stderr should include "ERROR: Invalid confidence format"
    End
  End

  Describe "missing section"
    It "blocks when required section is missing"
      Data
        #|{"tool_input": {"content": "---\ncreated: 2025-01-20\nmodified: 2025-01-20\nreviewed: 2025-01-20\nstatus: draft\nconfidence: 7/10\ndomain: api\nfeature-codes: []\nrelated: []\n---\n\n## Context Framing\n\n## AI Documentation\n\n## Implementation Blueprint\n\n## Test Strategy\n\n## Validation Gates\n"}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 2
      The stderr should include "ERROR: Missing required section: ## Success Criteria"
    End
  End
End

#!/bin/bash
# ShellSpec tests for check-prp-readiness.sh

Describe "check-prp-readiness.sh"
  HOOK_SCRIPT="$SHELLSPEC_PROJECT_ROOT/check-prp-readiness.sh"

  setup() {
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/docs/prps"
    cd "$TEST_DIR"
  }

  cleanup() {
    cd /
    rm -rf "$TEST_DIR"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  Describe "valid PRP"
    It "passes readiness check for valid PRP with confidence >= 7"
      # Create valid PRP
      cat > "$TEST_DIR/docs/prps/test-feature.md" << 'PRPEOF'
---
created: 2025-01-20
modified: 2025-01-20
reviewed: 2025-01-20
status: ready
confidence: 8/10
domain: auth
feature-codes:
  - FR1.1
related: []
---

# PRP

## Context Framing

Context.

## AI Documentation

Docs.

## Implementation Blueprint

Steps.

## Test Strategy

Tests.

## Validation Gates

Gates.

## Success Criteria

Criteria.
PRPEOF
      input='{"tool_input": {"args": "test-feature"}}'
      When call bash -c "cd '$TEST_DIR' && echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The stderr should include "INFO: PRP readiness check passed"
    End
  End

  Describe "low confidence"
    It "blocks execution for PRP with confidence < 7"
      cat > "$TEST_DIR/docs/prps/low-conf.md" << 'PRPEOF'
---
created: 2025-01-20
modified: 2025-01-20
reviewed: 2025-01-20
status: ready
confidence: 5/10
domain: api
feature-codes: []
related: []
---

# PRP

## Context Framing

## AI Documentation

## Implementation Blueprint

## Test Strategy

## Validation Gates

## Success Criteria
PRPEOF
      input='{"tool_input": {"args": "low-conf"}}'
      When call bash -c "cd '$TEST_DIR' && echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 2
      The stderr should include "ERROR: Confidence score"
    End
  End

  Describe "missing PRP"
    It "blocks when PRP file does not exist"
      input='{"tool_input": {"args": "nonexistent"}}'
      When call bash -c "cd '$TEST_DIR' && echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 2
      The stderr should include "ERROR: PRP file not found"
    End
  End

  Describe "no arguments"
    It "allows operation when no args provided (let skill handle)"
      Data
        #|{"tool_input": {}}
      End
      When call bash "$HOOK_SCRIPT"
      The status should equal 0
    End
  End

  Describe "bypass mode"
    It "skips validation when BLUEPRINT_SKIP_HOOKS=1"
      export BLUEPRINT_SKIP_HOOKS=1
      input='{"tool_input": {"args": "nonexistent"}}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
    End
  End
End

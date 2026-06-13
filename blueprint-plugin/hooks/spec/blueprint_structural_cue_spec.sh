#!/usr/bin/env bash
# ShellSpec tests for blueprint-structural-cue.sh (ADR-0017 behavioral cue).

Describe "blueprint-structural-cue.sh"
  HOOK_SCRIPT="$SHELLSPEC_PROJECT_ROOT/blueprint-structural-cue.sh"

  setup() {
    CACHE_DIR=$(mktemp -d)
    export BLUEPRINT_STRUCTURAL_CUE_CACHE_DIR="$CACHE_DIR"
  }

  cleanup() {
    rm -rf "$CACHE_DIR"
    unset BLUEPRINT_STRUCTURAL_CUE_CACHE_DIR
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  Describe "structural edits fire a cue"
    It "fires on a plugin.json manifest edit"
      input='{"tool_name":"Edit","session_id":"s1","tool_input":{"file_path":"foo-plugin/.claude-plugin/plugin.json","new_string":"x"},"tool_response":"File edited successfully"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "derive-plans"
      The output should include "updatedToolOutput"
    End

    It "fires on a marketplace.json edit"
      input='{"tool_name":"Edit","session_id":"s2","tool_input":{"file_path":".claude-plugin/marketplace.json","new_string":"x"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "adr-validate"
    End

    It "fires on an export-line write"
      input='{"tool_name":"Write","session_id":"s3","tool_input":{"file_path":"src/index.ts","content":"export function foo() {}"},"tool_response":"written"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
    End

    It "preserves the original tool_response in the output"
      input='{"tool_name":"Write","session_id":"s4","tool_input":{"file_path":"lib.rs","content":"pub fn bar() {}"},"tool_response":"ORIGINAL-OUTPUT-XYZ"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "ORIGINAL-OUTPUT-XYZ"
    End
  End

  Describe "non-structural edits stay silent"
    It "is silent on a trivial README edit"
      input='{"tool_name":"Edit","session_id":"s5","tool_input":{"file_path":"README.md","new_string":"fixed a typo"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should equal ""
    End

    It "excludes docs/adrs paths (covered by other blueprint hooks)"
      input='{"tool_name":"Edit","session_id":"s6","tool_input":{"file_path":"docs/adrs/0001-x.md","new_string":"export note"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should equal ""
    End

    It "ignores non-Edit/Write tools"
      input='{"tool_name":"Bash","session_id":"s7","tool_input":{"command":"export FOO=1"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should equal ""
    End
  End

  Describe "dedup and bypass"
    It "fires only once per session"
      input='{"tool_name":"Edit","session_id":"dup","tool_input":{"file_path":"a/plugin.json","new_string":"x"},"tool_response":"ok"}'
      # First call sets the per-session marker.
      echo "$input" | bash "$HOOK_SCRIPT" >/dev/null 2>&1
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should equal ""
    End

    It "skips when BLUEPRINT_SKIP_HOOKS=1"
      export BLUEPRINT_SKIP_HOOKS=1
      input='{"tool_name":"Edit","session_id":"s8","tool_input":{"file_path":"a/plugin.json","new_string":"x"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should equal ""
    End
  End

  Describe "graceful edge cases"
    It "emits without a session_id and does not crash"
      input='{"tool_name":"Write","tool_input":{"file_path":"lib.rs","content":"pub fn bar() {}"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
    End
  End
End

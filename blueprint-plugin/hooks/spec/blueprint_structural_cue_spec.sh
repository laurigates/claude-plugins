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

    It "fires on a TypeScript exported interface declaration"
      input='{"tool_name":"Edit","session_id":"s10","tool_input":{"file_path":"src/types.ts","new_string":"export interface MyConfig { host: string; }"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
    End

    It "fires on a TypeScript exported type alias"
      input='{"tool_name":"Write","session_id":"s11","tool_input":{"file_path":"src/api.ts","content":"export type RequestId = string;"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
    End

    It "fires on a Go exported struct declaration"
      input='{"tool_name":"Edit","session_id":"s12","tool_input":{"file_path":"pkg/server.go","new_string":"type Server struct { addr string }"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
    End

    It "fires on a Go exported interface declaration"
      input='{"tool_name":"Edit","session_id":"s13","tool_input":{"file_path":"pkg/handler.go","new_string":"type Handler interface { ServeHTTP() }"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
    End

    It "fires on a Rust pub struct declaration"
      input='{"tool_name":"Edit","session_id":"s14","tool_input":{"file_path":"src/lib.rs","new_string":"pub struct Config { pub host: String }"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
    End

    It "fires on a Rust pub enum declaration"
      input='{"tool_name":"Edit","session_id":"s15","tool_input":{"file_path":"src/error.rs","new_string":"pub enum AppError { NotFound, BadRequest }"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
    End

    It "fires on a Rust pub trait declaration"
      input='{"tool_name":"Edit","session_id":"s16","tool_input":{"file_path":"src/traits.rs","new_string":"pub trait Processor { fn process(&self); }"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
    End

    It "fires on an Express route registration"
      input='{"tool_name":"Edit","session_id":"s17","tool_input":{"file_path":"src/routes.js","new_string":"app.get(\"/health\", handler);"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
    End

    It "fires on a Flask route decorator"
      input='{"tool_name":"Edit","session_id":"s18","tool_input":{"file_path":"app.py","new_string":"@app.route(\"/users\")"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
    End

    It "fires on a .proto schema file write"
      input='{"tool_name":"Write","session_id":"s19","tool_input":{"file_path":"proto/service.proto","content":"syntax = \"proto3\";"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
    End

    It "fires on a .graphql schema file write"
      input='{"tool_name":"Write","session_id":"s20","tool_input":{"file_path":"schema/api.graphql","content":"type Query { users: [User] }"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
    End

    It "fires on a Prisma schema file write"
      input='{"tool_name":"Write","session_id":"s21","tool_input":{"file_path":"prisma/schema.prisma","content":"model User { id Int }"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
    End

    It "fires on an openapi.yaml write"
      input='{"tool_name":"Write","session_id":"s22","tool_input":{"file_path":"docs/openapi.yaml","content":"openapi: 3.0.0"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should include "Structural change detected"
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

    It "is silent on a lowercase Go struct (unexported)"
      input='{"tool_name":"Edit","session_id":"s30","tool_input":{"file_path":"internal/server.go","new_string":"type server struct { addr string }"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should equal ""
    End

    It "is silent on a TypeScript non-exported interface"
      input='{"tool_name":"Edit","session_id":"s31","tool_input":{"file_path":"src/internal.ts","new_string":"interface internalConfig { debug: boolean }"},"tool_response":"ok"}'
      When call bash -c "echo '$input' | bash '$HOOK_SCRIPT'"
      The status should equal 0
      The output should equal ""
    End

    It "is silent on a plain YAML config file (not openapi)"
      input='{"tool_name":"Edit","session_id":"s32","tool_input":{"file_path":"config/settings.yaml","new_string":"debug: true"},"tool_response":"ok"}'
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

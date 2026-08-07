#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # file-level: fixture bodies deliberately contain literal `{{`/`$` in single quotes
# Regression test for scripts/check-unrendered-templates.sh
#
# The defect this guards (issue #2265): `code-quality-plugin:code-lint` shipped
# `{{ if PROJECT_TYPE == "python" }}` / `{{ endif }}` blocks. Claude Code renders
# nothing in a skill body, so all four language branches reached the agent
# verbatim and `PROJECT_TYPE` was never bound. Four sibling skills had it too.
#
# Guards:
#   A. the real repo is clean (exit 0) and actually scanned something
#   B. the VERBATIM pre-fix code-lint block is rejected, with every marker named
#      (guard integrity: a guard that cannot fail on the original defect is not
#      a guard)
#   C. the other four pre-fix shapes are each rejected — Handlebars `{{#if}}` /
#      `{{/if}}`, an inline `{{ if DEV }}` inside a fenced command, a shell
#      positional condition `{{ if $3 == "--github" }}`, and `PACKAGE_MANAGER`
#   D. the FIXED shape (detection step + lookup table) passes
#   E. Go / Helm chart templates are NOT flagged (false-positive integrity) —
#      trim markers, `{{ end }}`, `$.Values`
#   F. a file declaring the render directive is exempt, and the declaration is
#      what does it (an otherwise-identical file without it still fails)
#   G. the literal ellipsis form `{{ if ... }}` is prose, not a conditional
#   H. .claude/worktrees/ and dist/ copies are pruned (#1492 / #2214 parity)
#   I. an unknown argument exits 2 rather than being swallowed (#2057)
#   J. zero-scan is distinguishable from clean-scan (#2219 / #2290): plugin dirs
#      present but nothing discovered is STATUS=ERROR TYPE=nothing_scanned; a
#      genuinely empty tree stays STATUS=OK + SCANNED_EMPTY=true
#   K. a worktree-SHAPED scan root still scans (#2219): the prune must not match
#      the root itself when the root's own absolute path contains
#      `/.claude/worktrees/`
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-unrendered-templates.sh"

pass_count=0
fail_count=0

assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

contains() { printf '%s' "$1" | grep -qF -- "$2" && echo true || echo false; }
lacks() { [ "$(contains "$1" "$2")" = "false" ] && echo true || echo false; }

# make_skill <path> <body>
make_skill() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
}

run() {
  local dir="$1"; shift
  OUT="$(bash "$checker" --project-dir "$dir" "$@" 2>&1)"
  RC=$?
}

# --- TEST A: the real repo is clean ------------------------------------------
echo "=== TEST A: real repo has no unrendered template conditionals ==="
run "$repo_root"
assert "real repo exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "real repo reports UNRENDERED_CONDITIONALS=0" "$(contains "$OUT" 'UNRENDERED_CONDITIONALS=0')"
# Guard integrity: without this, every "clean" assertion above is vacuous.
assert "real repo scanned some skill files" "$(lacks "$OUT" 'FILES_SCANNED=0')"

fx_b=""; fx_c=""; fx_d=""; fx_e=""; fx_f=""; fx_g=""; fx_h=""; fx_j=""; fx_k=""; fx_n=""
cleanup() { rm -rf "$fx_b" "$fx_c" "$fx_d" "$fx_e" "$fx_f" "$fx_g" "$fx_h" "$fx_j" "$fx_k" "$fx_n"; }
trap cleanup EXIT

# --- TEST B: the verbatim pre-fix code-lint block is rejected ----------------
echo "=== TEST B: pre-fix code-lint conditionals are rejected, each named ==="
fx_b="$(mktemp -d)"
[ -n "$fx_b" ] || { echo "mktemp failed" >&2; exit 1; }
make_skill "$fx_b/code-quality-plugin/skills/code-lint/SKILL.md" '## Linting Execution

### Python
{{ if PROJECT_TYPE == "python" }}
Run Python linters:
1. Ruff check: `uv run ruff check ${1:-.} --output-format=concise ${2:+--fix}`
{{ endif }}

### JavaScript/TypeScript
{{ if PROJECT_TYPE == "node" }}
1. ESLint: `npm run lint ${1:-.} ${2:+-- --fix}`
{{ endif }}

### Rust
{{ if PROJECT_TYPE == "rust" }}
1. Clippy: `cargo clippy --message-format=short -- -D warnings`
{{ endif }}

### Go
{{ if PROJECT_TYPE == "go" }}
1. Go vet: `go vet ./...`
{{ endif }}'
run "$fx_b"
assert "pre-fix code-lint exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "pre-fix code-lint reports 8 conditionals" "$(contains "$OUT" 'UNRENDERED_CONDITIONALS=8')"
assert "pre-fix code-lint is STATUS=ERROR" "$(contains "$OUT" 'STATUS=ERROR')"
for lang in python node rust go; do
  assert "pre-fix code-lint names the $lang branch" \
    "$(contains "$OUT" "TOKEN={{ if PROJECT_TYPE == \"$lang\" }}")"
done
assert "pre-fix code-lint names the file" "$(contains "$OUT" 'FILE=code-quality-plugin/skills/code-lint/SKILL.md')"

# --- TEST C: the four sibling pre-fix shapes ---------------------------------
echo "=== TEST C: sibling defect shapes are each rejected ==="
fx_c="$(mktemp -d)"
[ -n "$fx_c" ] || { echo "mktemp failed" >&2; exit 1; }
# Handlebars (test-analyze)
make_skill "$fx_c/testing-plugin/skills/test-analyze/SKILL.md" 'Analyze results.

{{#if ARG2}}
Test type: {{ARG2}}
{{/if}}'
# Inline conditional inside a fenced command (bun-add)
make_skill "$fx_c/typescript-plugin/skills/bun-add/SKILL.md" '## Execution

```bash
bun add {{ if DEV }}--dev {{ endif }}{{ if EXACT }}--exact {{ endif }}$PACKAGE
```'
# Shell positional as the condition (project-init) — the `$` must NOT be
# mistaken for Go's `$.` root context.
make_skill "$fx_c/project-plugin/skills/project-init/SKILL.md" '## GitHub Repository Creation

{{ if $3 == "--github" }}
Create GitHub repository.
{{ endif }}'
# PACKAGE_MANAGER (deps-install)
make_skill "$fx_c/tools-plugin/skills/deps-install/SKILL.md" '### Python (uv)
{{ if PACKAGE_MANAGER == "uv" }}
- Install all: `uv sync`
{{ endif }}'
run "$fx_c"
assert "sibling shapes exit 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "handlebars open is flagged" "$(contains "$OUT" 'TOKEN={{#if ARG2}}')"
assert "handlebars close is flagged" "$(contains "$OUT" 'TOKEN={{/if}}')"
assert "inline fenced conditional is flagged" "$(contains "$OUT" 'TOKEN={{ if DEV }}')"
assert "shell positional condition is flagged (not read as Go \$.)" \
  "$(contains "$OUT" 'TOKEN={{ if $3 == "--github" }}')"
assert "PACKAGE_MANAGER condition is flagged" "$(contains "$OUT" 'TOKEN={{ if PACKAGE_MANAGER == "uv" }}')"

# --- TEST D: the fixed shape passes ------------------------------------------
echo "=== TEST D: detection step + lookup table passes ==="
fx_d="$(mktemp -d)"
[ -n "$fx_d" ] || { echo "mktemp failed" >&2; exit 1; }
make_skill "$fx_d/code-quality-plugin/skills/code-lint/SKILL.md" '### Step 1: Detect the project language

| Marker file present in the repo root | Language |
|---|---|
| `pyproject.toml` | Python |
| `package.json` | JavaScript / TypeScript |

### Step 2: Run the row for each detected language

| Language | Lint | Lint with `--fix` |
|---|---|---|
| Python | `uv run ruff check PATH` | `uv run ruff check PATH --fix` |
| JavaScript / TypeScript | `npx eslint PATH` | `npx eslint PATH --fix` |'
run "$fx_d"
assert "fixed shape exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "fixed shape is STATUS=OK" "$(contains "$OUT" 'STATUS=OK')"
# Guard integrity: prove the file was actually looked at, not skipped.
assert "fixed shape was scanned, not exempted" "$(contains "$OUT" 'FILES_SCANNED=1')"
assert "fixed shape claimed no exemption" "$(contains "$OUT" 'FILES_EXEMPT=0')"

# --- TEST E: Go / Helm templates are not flagged -----------------------------
echo "=== TEST E: Go/Helm chart templates are not flagged ==="
fx_e="$(mktemp -d)"
[ -n "$fx_e" ] || { echo "mktemp failed" >&2; exit 1; }
make_skill "$fx_e/kubernetes-plugin/skills/helm-chart-development/REFERENCE.md" '```yaml
{{- if .Values.ingress.enabled -}}
{{- if contains $name .Release.Name }}
  http{{ if $.Values.ingress.tls }}s{{ end }}://{{ .host }}
{{- else }}
{{- end }}
{{ end }}
```'
run "$fx_e"
assert "helm templates exit 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "helm templates are STATUS=OK" "$(contains "$OUT" 'STATUS=OK')"
assert "helm file was scanned, not exempted" "$(contains "$OUT" 'FILES_EXEMPT=0')"

# --- TEST F: the render directive is what exempts ----------------------------
echo "=== TEST F: the declared render directive exempts; absence still fails ==="
fx_f="$(mktemp -d)"
[ -n "$fx_f" ] || { echo "mktemp failed" >&2; exit 1; }
generator_body='Adapt per detected stack. Remove all `{{ if ... }}` / `{{ endif }}` markers after substitution.

```bash
{{ if Python detected }}
uv sync
{{ endif }}
```'
undeclared_body='Adapt per detected stack.

```bash
{{ if Python detected }}
uv sync
{{ endif }}
```'
make_skill "$fx_f/hooks-plugin/skills/hooks-session-start-hook/REFERENCE.md" "$generator_body"
run "$fx_f"
assert "declared generator template exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "declared generator template is exempt" "$(contains "$OUT" 'FILES_EXEMPT=1')"
# Guard integrity: the SAME markers without the declaration must still fail,
# or the exemption is really "hooks-plugin is never checked".
make_skill "$fx_f/hooks-plugin/skills/hooks-session-start-hook/REFERENCE.md" "$undeclared_body"
run "$fx_f"
assert "undeclared identical markers exit 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "undeclared identical markers are flagged" "$(contains "$OUT" 'TOKEN={{ if Python detected }}')"

# --- TEST G: the ellipsis meta-reference is prose ----------------------------
echo "=== TEST G: the literal {{ if ... }} form is prose, not a conditional ==="
fx_g="$(mktemp -d)"
[ -n "$fx_g" ] || { echo "mktemp failed" >&2; exit 1; }
make_skill "$fx_g/hooks-plugin/skills/hooks-permission-request-hook/SKILL.md" \
  'Include only sections for detected languages (remove `{{ if ... }}` markers).'
run "$fx_g"
assert "ellipsis meta-reference exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "ellipsis meta-reference is not exempted wholesale" "$(contains "$OUT" 'FILES_EXEMPT=0')"
assert "ellipsis meta-reference is STATUS=OK" "$(contains "$OUT" 'STATUS=OK')"

# --- TEST H: worktree / dist copies are pruned -------------------------------
echo "=== TEST H: .claude/worktrees/ and dist/ copies are pruned ==="
fx_h="$(mktemp -d)"
[ -n "$fx_h" ] || { echo "mktemp failed" >&2; exit 1; }
make_skill "$fx_h/demo-plugin/skills/thing/SKILL.md" 'A clean skill with a table.'
make_skill "$fx_h/demo-plugin/.claude/worktrees/agent-deadbeef/skills/leak/SKILL.md" '{{ if X }}a{{ endif }}'
make_skill "$fx_h/demo-plugin/dist/opencode/skills/leak/SKILL.md" '{{ if X }}a{{ endif }}'
run "$fx_h"
assert "pruned copies exit 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "only the real skill was scanned" "$(contains "$OUT" 'FILES_SCANNED=1')"
assert "no .claude/worktrees/ path leaks into output" "$(lacks "$OUT" '.claude/worktrees/')"
assert "no dist/ path leaks into output" "$(lacks "$OUT" 'dist/opencode')"

# --- TEST I: an unknown argument is rejected, not swallowed (#2057) ----------
echo "=== TEST I: unknown argument exits 2 with usage ==="
OUT="$(bash "$checker" --projekt-dir "$fx_h" 2>&1)"
RC=$?
assert "unknown argument exits 2" "$([ "$RC" -eq 2 ] && echo true || echo false)"
assert "unknown argument is named" "$(contains "$OUT" 'unknown argument: --projekt-dir')"
assert "unknown argument prints usage" "$(contains "$OUT" 'Usage: check-unrendered-templates.sh')"
assert "unknown argument scans nothing" "$(lacks "$OUT" 'FILES_SCANNED=')"

# --- TEST N: loop forms are conditionals too; Go `range` is not --------------
# Credited to the concurrent PR #2284, whose narrower guard covered `for`/
# `endfor` where an earlier draft of this one did not. `range` is deliberately
# EXCLUDED: it is the one loop keyword with a legitimate rendered use here (four
# Helm chart examples), so including it would buy a hypothetical catch at the
# cost of real false positives.
echo "=== TEST N: for/endfor and #each/-/each flagged; Go range is not ==="
fx_n="$(mktemp -d)"
[ -n "$fx_n" ] || { echo "mktemp failed" >&2; exit 1; }
make_skill "$fx_n/demo-plugin/skills/loops/SKILL.md" '{{ for lang in LANGUAGES }}
Run the {{ lang }} linter.
{{ endfor }}

{{#each PACKAGES}}
Install {{ this }}.
{{/each}}'
run "$fx_n"
assert "loop forms exit 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "{{ for }} is flagged" "$(contains "$OUT" 'TOKEN={{ for lang in LANGUAGES }}')"
assert "{{ endfor }} is flagged" "$(contains "$OUT" 'TOKEN={{ endfor }}')"
assert "handlebars {{#each}} is flagged" "$(contains "$OUT" 'TOKEN={{#each PACKAGES}}')"
assert "handlebars {{/each}} is flagged" "$(contains "$OUT" 'TOKEN={{/each}}')"
# False-positive integrity: the real Helm range forms from the corpus, PLUS a
# BARE `{{ range $k, $v := … }}` with no trim marker and a `$`-rooted (not
# `$.`-rooted) binding. The trim-marker forms are skipped structurally whatever
# the keyword set is, so only the bare form actually falsifies the decision to
# leave `range` out — without it, adding `range` back would pass this test.
make_skill "$fx_n/demo-plugin/skills/loops/SKILL.md" '```yaml
{{- range $key, $value := .Values.config }}
{{ $key }}: {{ $value }}
{{- end }}
{{ range $key, $value := .Values.config }}
{{ $key }}: {{ $value }}
{{ end }}
{{- range .Values.ingress.hosts }}
- host: {{ .host }}
{{- end }}
```'
run "$fx_n"
assert "Go range forms exit 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "Go range forms are STATUS=OK" "$(contains "$OUT" 'STATUS=OK')"
assert "Go range file was scanned, not exempted" "$(contains "$OUT" 'FILES_EXEMPT=0')"

# --- TEST J: zero-scan is not clean-scan (#2219 / #2290) ---------------------
echo "=== TEST J: nothing_scanned vs a genuinely empty tree ==="
fx_j="$(mktemp -d)"
[ -n "$fx_j" ] || { echo "mktemp failed" >&2; exit 1; }
# A tree with NO plugin dirs is legitimately empty — erroring here gets the
# guard disabled, so it must stay green and say so.
run "$fx_j"
assert "empty tree exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "empty tree is STATUS=OK" "$(contains "$OUT" 'STATUS=OK')"
assert "empty tree marks SCANNED_EMPTY=true" "$(contains "$OUT" 'SCANNED_EMPTY=true')"
assert "empty tree reports PLUGIN_DIRS=0" "$(contains "$OUT" 'PLUGIN_DIRS=0')"
# A plugin dir with no skills under it means discovery misfired — that must be
# loud, or a guard that scanned nothing is indistinguishable from a clean pass.
mkdir -p "$fx_j/demo-plugin/agents"
run "$fx_j"
assert "plugin dirs but zero skills exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "plugin dirs but zero skills is STATUS=ERROR" "$(contains "$OUT" 'STATUS=ERROR')"
assert "plugin dirs but zero skills reports TYPE=nothing_scanned" "$(contains "$OUT" 'TYPE=nothing_scanned')"
assert "misfire does NOT claim SCANNED_EMPTY" "$(lacks "$OUT" 'SCANNED_EMPTY=true')"

# --- TEST K: a worktree-shaped scan root still scans (#2219) -----------------
# The exact defect #2290 fixed in four sibling guards: with an ABSOLUTE scan
# base, a bare `*/.claude/worktrees/*` prune matches every descendant of a root
# whose own path contains that segment, so the guard silently scans nothing —
# which is precisely the situation of every worktree-isolated agent verifying
# its own change. Discovery therefore runs from INSIDE the root on relative
# paths, and this test pins that by shaping the root's path like a worktree.
echo "=== TEST K: worktree-shaped scan root is not self-pruned ==="
fx_k="$(mktemp -d)"
[ -n "$fx_k" ] || { echo "mktemp failed" >&2; exit 1; }
wt_root="$fx_k/repo/.claude/worktrees/agent-abc123"
make_skill "$wt_root/demo-plugin/skills/thing/SKILL.md" 'A clean skill with a table.'
make_skill "$wt_root/demo-plugin/skills/broken/SKILL.md" '{{ if X }}a{{ endif }}'
run "$wt_root"
assert "worktree-shaped root scanned both skills" "$(contains "$OUT" 'FILES_SCANNED=2')"
assert "worktree-shaped root still flags the defect" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "worktree-shaped root did not report nothing_scanned" "$(lacks "$OUT" 'TYPE=nothing_scanned')"

# --- Summary -----------------------------------------------------------------
echo ""
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]

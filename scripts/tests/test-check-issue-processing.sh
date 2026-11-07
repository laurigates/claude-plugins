#!/usr/bin/env bash
# Regression test for scripts/check-issue-processing.sh (#3346).
#
# Machine-filed issues did not say who processes them or when they close, so
# they piled up open. Every issue-body template now carries `## Processing`;
# the check keeps it that way. Each case pairs a failing fixture with the
# passing shape, so a check hardwired to pass or to fail is caught:
#
#   A  the real repository passes
#   B  a script-to-issue caller without `processing` fails; with it, passes
#   C  a Claude prompt that files an issue without `## Processing` fails
#   D  a `run:` step that files an issue without `## Processing` fails
#   E  a label on the exempt list missing from docs/issue-lifecycle.md fails
#   F  the feedback-session template without `## Processing` fails
#   G  a project with no generators at all is an error, not a pass
#   H  the failing output satisfies the structured-output contract
#   I  a prompt that names `gh issue create` only in prose is a filing site
#   J  a job on the EXEMPT_SITES list is counted as exempt, not checked
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
check="$repo_root/scripts/check-issue-processing.sh"
contract="$repo_root/scripts/check-structured-output-contract.sh"

python3 -c 'import yaml' 2>/dev/null || { echo "SKIP: PyYAML not available"; exit 0; }

tmp="$(mktemp -d)" || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then echo "FAIL: mktemp -d returned no dir" >&2; exit 1; fi
trap 'rm -rf "$tmp"' EXIT

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
contains() { grep -q -- "$2" <<<"$1" && echo true || echo false; }

run() { # <project-dir> -- sets OUT, RC
  OUT="$(bash "$check" --project-dir "$1" 2>&1)"
  RC=$?
}

# A fixture project that passes: one generator of each kind, a lifecycle doc
# naming every exempt label, and a feedback template with the section.
make_project() { # <dir>
  local d="$1"
  mkdir -p "$d/.github/workflows" "$d/scripts" "$d/docs" \
    "$d/feedback-plugin/skills/feedback-session/references"
  cat > "$d/scripts/issue-grouping-exempt.txt" <<'EOF'
# comment
label epic
label weekly-report
title ^Dependency Dashboard$
EOF
  cat > "$d/docs/issue-lifecycle.md" <<'EOF'
| `weekly-report` | x | x | x | x |
| Dependency Dashboard (title) | Renovate | x | x | x |
EOF
  cat > "$d/feedback-plugin/skills/feedback-session/references/issue-format.md" <<'EOF'
**Body template**:
```markdown
## Skill
## Processing
- **Processed by:** x
```
EOF
  cat > "$d/.github/workflows/report.yml" <<'YAML'
name: "Plugin: Report"
on: workflow_dispatch
jobs:
  scripted:
    runs-on: ubuntu-slim
    steps:
      - name: Audit
        uses: ./.github/actions/script-to-issue
        with:
          label: weekly-report
          script: bash scripts/x.sh
          title: 'Report: {date}'
          processing: |
            ## Processing

            - **Processed by:** Lauri.
      - name: Guard only
        uses: ./.github/actions/script-to-issue
        with:
          label: weekly-report
  claude:
    runs-on: ubuntu-latest
    steps:
      - name: Claude
        uses: anthropics/claude-code-action@v1
        with:
          prompt: |
            gh issue create --title "x" --body "$(cat <<'EOF'
            ## Processing
            EOF
            )"
  shell:
    runs-on: ubuntu-slim
    steps:
      - name: File
        run: |
          echo "## Processing" >> body.md
          gh issue create --title x --body-file body.md
YAML
}

# --- A: the real repository ---------------------------------------------------
run "$repo_root"
assert "A real repository passes (got: $(grep -m1 '^REASON=' <<<"$OUT"))" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "A real repository reports STATUS=OK" "$(contains "$OUT" '^STATUS=OK$')"

# --- the passing fixture ------------------------------------------------------
make_project "$tmp/ok"
run "$tmp/ok"
assert "fixture passes" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "fixture counts three generator sites" "$(contains "$OUT" '^SITES_CHECKED=3$')"

# --- B: script-to-issue caller without processing -----------------------------
make_project "$tmp/b"
python3 - "$tmp/b/.github/workflows/report.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
start = s.index("          processing: |")
end = s.index("      - name: Guard only")
open(p, "w").write(s[:start] + s[end:])
PY
run "$tmp/b"
assert "B missing processing exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "B names the site" "$(contains "$OUT" 'TYPE=missing_processing.*report.yml:scripted:Audit')"
B_OUT="$OUT"

# --- C: prompt without the section --------------------------------------------
make_project "$tmp/c"
python3 - "$tmp/c/.github/workflows/report.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("            ## Processing\n            EOF", "            ## Summary\n            EOF")
open(p, "w").write(s)
PY
run "$tmp/c"
assert "C prompt without section exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "C names the prompt site" "$(contains "$OUT" 'TYPE=missing_processing.*report.yml:claude:Claude')"

# --- D: run step without the section ------------------------------------------
make_project "$tmp/d"
python3 - "$tmp/d/.github/workflows/report.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace('echo "## Processing" >> body.md', 'echo "body" >> body.md')
open(p, "w").write(s)
PY
run "$tmp/d"
assert "D run step without section exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "D names the run site" "$(contains "$OUT" 'TYPE=missing_processing.*report.yml:shell:File')"

# --- E: exempt label missing from the lifecycle doc ---------------------------
make_project "$tmp/e"
echo "label monthly-report" >> "$tmp/e/scripts/issue-grouping-exempt.txt"
run "$tmp/e"
assert "E undocumented label exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "E names the label" "$(contains "$OUT" 'TYPE=undocumented_type.*monthly-report')"

# --- F: feedback template without the section ---------------------------------
make_project "$tmp/f"
printf '## Skill\n' > "$tmp/f/feedback-plugin/skills/feedback-session/references/issue-format.md"
run "$tmp/f"
assert "F feedback template without section exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "F names the feedback template" "$(contains "$OUT" 'TYPE=missing_processing.*issue-format.md')"

# --- G: nothing scanned -------------------------------------------------------
make_project "$tmp/g"
rm "$tmp/g/.github/workflows/report.yml"
run "$tmp/g"
assert "G no generators is an error" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "G reports nothing_scanned" "$(contains "$OUT" 'TYPE=nothing_scanned')"

# --- I: a prompt that files issues in prose -----------------------------------
# "open an issue via `gh issue create`" files issues as surely as a code block.
make_project "$tmp/i"
cat >> "$tmp/i/.github/workflows/report.yml" <<'YAML'
  prose:
    runs-on: ubuntu-latest
    steps:
      - name: Prose
        uses: anthropics/claude-code-action@v1
        with:
          prompt: |
            Open a GitHub issue per follow-up via `gh issue create` with label `x`.
YAML
run "$tmp/i"
assert "I prose prompt without section exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "I names the prose site" "$(contains "$OUT" 'TYPE=missing_processing.*report.yml:prose:Prose')"

# --- J: an exempt job is counted, not checked ---------------------------------
make_project "$tmp/j"
cat > "$tmp/j/.github/workflows/github-workflow-auto-fix.yml" <<'YAML'
name: "CI: Auto-fix"
on: workflow_dispatch
jobs:
  auto-fix:
    runs-on: ubuntu-latest
    steps:
      - name: File
        run: |
          gh issue create --title x --body y
YAML
run "$tmp/j"
assert "J exempt job passes" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "J exempt job is counted" "$(contains "$OUT" '^SITES_EXEMPT=1$')"

# --- H: structured-output contract --------------------------------------------
if [ -f "$contract" ]; then
  valid() { if bash "$contract" --validate - <<<"$1" >/dev/null 2>&1; then echo true; else echo false; fi; }
  assert "H failing output passes --validate" "$(valid "$B_OUT")"
  run "$tmp/ok"
  assert "H passing output passes --validate" "$(valid "$OUT")"
fi

echo "PASS=$pass_count FAIL=$fail_count"
[ "$fail_count" -eq 0 ] || exit 1
echo "PASS: check-issue-processing ($pass_count assertions)"

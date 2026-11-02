#!/usr/bin/env bash
# Fixture test: obsidian-cli-changelog.yml uploads a redacted transcript of its
# Claude step (#2765).
#
# The weekly Obsidian CLI review ran past `--max-turns 40` on its two most
# recent model-reaching runs (41 turns / 7 denials, 72 turns / 8 denials), but
# the step uploaded no `claude-execution-*` artifact, so the denied calls could
# not be named, and by the time the issue was triaged the run logs had expired.
# The recorded decision keeps the cap at 40 and makes the step upload a
# redacted transcript (the golden-set-evaluation.yml pattern), so the next
# overrun names its denials and the grants-vs-cap call can rest on evidence.
#
# scripts/check-comment-deliverable-assertions.sh enforces the same upload only
# for comment-posting grants, and this step's `Bash(gh pr *)` wildcard is not
# one of its literal grants, so this test pins the workflow directly.
#
# Usage: bash scripts/tests/test-obsidian-cli-changelog-transcript.sh [workflow-file]
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
WORKFLOW="${1:-$repo_root/.github/workflows/obsidian-cli-changelog.yml}"

command -v python3 >/dev/null || { echo "FATAL: python3 not found on PATH" >&2; exit 1; }
python3 -c 'import yaml' 2>/dev/null || { echo "FATAL: PyYAML is required to read the workflow" >&2; exit 1; }

echo "=== OBSIDIAN CLI CHANGELOG TRANSCRIPT ==="
set +e
python3 - "$WORKFLOW" <<'PY'
import re
import sys

import yaml

path = sys.argv[1]
steps = yaml.safe_load(open(path, encoding="utf-8"))["jobs"]["claude-review"]["steps"]
passed = failed = 0


def check(label, ok):
    global passed, failed
    if ok:
        passed += 1
        print(f"PASS: {label}")
    else:
        failed += 1
        print(f"FAIL: {label}")


claude = [i for i, s in enumerate(steps) if "anthropics/claude-code-action" in str(s.get("uses", ""))]
check("the claude-review job has exactly one Claude step", len(claude) == 1)
idx = claude[0] if claude else 0
step = steps[idx] if claude else {}
sid = step.get("id")
check("the Claude step has an id", isinstance(sid, str) and sid != "")

args = str((step.get("with") or {}).get("claude_args", ""))
check("the turn cap stays at --max-turns 40 (decision on #2765)", re.search(r"--max-turns 40\b", args) is not None)

later = steps[idx + 1:]
ref = f"steps.{sid}.outputs.execution_file"
redact = [s for s in later if ref in yaml.safe_dump(s)]
check(f"a later step reads {ref}", len(redact) == 1)
r = redact[0] if redact else {}
check("that step has id: redact", r.get("id") == "redact")
check("the redact step runs on failure too (always())", "always()" in str(r.get("if", "")))
check("the redact step does not fail the job (continue-on-error)", r.get("continue-on-error") is True)
env = r.get("env") or {}
check("the redact step scrubs the OAuth token by value", "secrets.CLAUDE_CODE_OAUTH_TOKEN" in str(env.values()))
check("the redact step scrubs the github token by value", "github.token" in str(env.values()))
# The job checks out with this PAT, and actions/checkout persists it in
# .git/config, which the step's Bash(cat *) grant can read.
check("the redact step scrubs the checkout PAT by value", "secrets.MY_RELEASE_PLEASE_TOKEN" in str(env.values()))
check("the redact step also scrubs the base64 basic-auth form checkout writes", "b64encode" in str(r.get("run", "")))

uploads = [s for s in later if "actions/upload-artifact" in str(s.get("uses", ""))]
check("a later step uploads an artifact", len(uploads) == 1)
u = uploads[0] if uploads else {}
w = u.get("with") or {}
check("the upload reads the redacted path, never the raw transcript", str(w.get("path", "")) == "${{ steps.redact.outputs.path }}")
check("the upload is gated on always() and a non-empty redacted path",
      "always()" in str(u.get("if", "")) and "steps.redact.outputs.path != ''" in str(u.get("if", "")))
check("the artifact is named claude-execution-*-<run_id>-<run_attempt>",
      re.fullmatch(r"claude-execution-[a-z-]+-\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}", str(w.get("name", ""))) is not None)
if redact and uploads:
    check("the redact step precedes the upload", later.index(r) < later.index(u))

print(f"PASSED={passed}")
print(f"FAILED={failed}")
sys.exit(1 if failed else 0)
PY
rc=$?
set -e
echo "=== END OBSIDIAN CLI CHANGELOG TRANSCRIPT ==="
if [ "$rc" -ne 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"

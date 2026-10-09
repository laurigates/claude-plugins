#!/usr/bin/env bash
# shellcheck disable=SC2016  # the issue body's literal markdown backticks are matched verbatim
# test-registry-health.sh — regression test for the registry-health.yml
# "Evaluate registry status" step that scaffold.py emits (REGISTRY_HEALTH_YML).
#
# The step reports a pack's registry verdict as a commit status and a tracking
# issue. Its Flagged arm used to say "Clean installs resolve to an older version
# until this clears" — false: the registry's /install resolver returns the
# newest NON-BANNED version, and Flagged is not banned (laurigates/
# comfyui-image-browser#111, measured 2026-08-27: a Flagged 0.1.32 resolved to
# 0.1.32; a Banned 0.1.30 resolved to 0.1.7). And a Banned version, the case
# that genuinely breaks installs, had no arm at all: it fell through to
# "Active in registry" and closed the tracking issue.
#
# This test is SEMANTIC: it extracts the shipped step from the generator and
# EXECUTES it against canned registry API responses, with `curl`, `gh` and
# `sleep` stubbed on PATH. The fleet-drift audit holds every pack's copy
# byte-identical to this template, so pinning the template pins the fleet.
#
# Cases:
#   0. GUARD INTEGRITY: the extracted script is non-empty and the stubs were
#      the ones executed (a sentinel only the stub writes). Without this a
#      broken extraction makes every assertion below vacuous.
#   1. Active      -> exit 0, success status, no issue body.
#   2. Flagged     -> exit 1, failure status "flagged", body reports the
#                     resolved /install version and does NOT claim installs
#                     fall back to an older version.
#   3. Banned      -> exit 1, failure status "banned" (never "Active"), body
#                     names the version /install actually resolves to and
#                     whether that fallback is deprecated.
#   4. Banned with /install unreachable -> still banned, body says the
#                     resolved version could not be read (no empty backticks).
#
# Requires python3 and jq; SKIPs cleanly when unavailable.

set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
    GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCAFFOLD="${SKILL_DIR}/scaffold.py"

pass=0
fail=0
check() { # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
    fi
}

for tool in python3 jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "SKIP: $tool not available" >&2
        exit 0
    fi
done
[ -f "$SCAFFOLD" ] || { echo "FAIL: missing $SCAFFOLD" >&2; exit 1; }

WORK="$(mktemp -d)"
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
    echo "FAIL: mktemp -d produced no directory" >&2
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT

# --------------------------------------------------------------------------- #
# Extract the shipped step (never a retyped copy).
# --------------------------------------------------------------------------- #
STEP="${WORK}/step.sh"
python3 - "$SCAFFOLD" "$STEP" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("scaffold", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
lines = mod.REGISTRY_HEALTH_YML.splitlines()
start = next(i for i, l in enumerate(lines) if l.strip() == "- name: Evaluate registry status")
run = next(i for i in range(start, len(lines)) if lines[i].strip() == "run: |")
indent = len(lines[run + 1]) - len(lines[run + 1].lstrip())
out = []
for l in lines[run + 1:]:
    if l.strip() and len(l) - len(l.lstrip()) < indent:
        break
    out.append(l[indent:])
open(sys.argv[2], "w").write("\n".join(out) + "\n")
PY

# --------------------------------------------------------------------------- #
# Stubs: curl serves canned JSON by URL shape; gh records what it was asked.
# --------------------------------------------------------------------------- #
BIN="${WORK}/bin"
mkdir -p "$BIN"
cat >"${BIN}/curl" <<'SH'
#!/usr/bin/env bash
echo stub >"${STUB_LOG}/curl.sentinel"
out=""; url=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        http*) url="$1"; shift ;;
        *) shift ;;
    esac
done
case "$url" in
    */versions*) src="${FIXTURE}/versions.json" ;;
    */install)   src="${FIXTURE}/install.json" ;;
    */nodes/*)   src="${FIXTURE}/node.json" ;;
    *) exit 22 ;;
esac
[ -f "$src" ] || exit 22   # curl -f on an HTTP error
if [ -n "$out" ]; then cp "$src" "$out"; else cat "$src"; fi
SH
cat >"${BIN}/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >>"${STUB_LOG}/gh.log"
if [ "$1" = "api" ]; then
    for a in "$@"; do
        case "$a" in state=*) echo "${a#state=}" >"${STUB_LOG}/status.state" ;;
                     description=*) echo "${a#description=}" >"${STUB_LOG}/status.desc" ;; esac
    done
    exit 0
fi
if [ "$1" = "issue" ]; then
    case "$2" in
        list) exit 0 ;;   # no open tracking issue
        create|comment)
            while [ $# -gt 0 ]; do
                [ "$1" = "--body-file" ] && cp "$2" "${STUB_LOG}/body.md"
                shift
            done ;;
    esac
fi
exit 0
SH
printf '#!/usr/bin/env bash\nexit 0\n' >"${BIN}/sleep"
chmod +x "${BIN}/curl" "${BIN}/gh" "${BIN}/sleep"

# run_case runs inside $(...), so it cannot set CASE_DIR for the caller; each
# case sets CASE_DIR itself, and run_case reads it.
run_case() { # run_case <declared-version> -> prints rc
    local ver="$1"
    mkdir -p "${CASE_DIR}/repo" "${CASE_DIR}/log"
    printf '[project]\nname = "comfyui-fixture"\nversion = "%s"\n' "$ver" \
        >"${CASE_DIR}/repo/pyproject.toml"
    (
        cd "${CASE_DIR}/repo" || exit 99
        PATH="${BIN}:${PATH}" FIXTURE="${CASE_DIR}/fixture" STUB_LOG="${CASE_DIR}/log" \
            GH_TOKEN=x GITHUB_REPOSITORY=laurigates/comfyui-fixture \
            GITHUB_EVENT_NAME=schedule STATUS_SHA=0000000 \
            STATUS_CONTEXT="Comfy Registry / scan" ISSUE_LABEL=registry-health \
            PENDING_GRACE_HOURS=6 POLL_ATTEMPTS=1 POLL_INTERVAL_SECS=0 \
            bash "$STEP" >"${CASE_DIR}/log/stdout" 2>&1
        echo "$?"
    )
}

fixture() { # fixture <case> <versions-json> [install-json] [node-json]
    mkdir -p "${WORK}/$1/fixture"
    printf '%s\n' "$2" >"${WORK}/$1/fixture/versions.json"
    [ -n "${3:-}" ] && printf '%s\n' "$3" >"${WORK}/$1/fixture/install.json"
    [ -n "${4:-}" ] && printf '%s\n' "$4" >"${WORK}/$1/fixture/node.json"
    return 0
}

state() { cat "${CASE_DIR}/log/status.state" 2>/dev/null || echo "<none>"; }
desc() { cat "${CASE_DIR}/log/status.desc" 2>/dev/null || echo "<none>"; }
# 1 if the issue body contains the literal text, else 0 (also 0 with no body).
body_has() { grep -qF -- "$1" "${CASE_DIR}/log/body.md" 2>/dev/null && echo 1 || echo 0; }

# --------------------------------------------------------------------------- #
# 0 + 1. Active (also the guard-integrity anchor)
# --------------------------------------------------------------------------- #
fixture active \
    '[{"version":"1.2.0","status":"NodeVersionStatusActive","createdAt":"2026-08-01T00:00:00Z"},
      {"version":"1.1.0","status":"NodeVersionStatusActive","createdAt":"2026-07-01T00:00:00Z"}]' \
    '{"version":"1.2.0","deprecated":false,"status":"NodeVersionStatusActive","createdAt":"2026-08-01T00:00:00Z"}' \
    '{"latest_version":{"version":"1.2.0"}}'
CASE_DIR="${WORK}/active"
rc="$(run_case 1.2.0)"
check "0: extracted step is non-empty" "1" "$([ -s "$STEP" ] && echo 1 || echo 0)"
check "0: the curl stub (not the real curl) served the run" "stub" \
    "$(cat "${CASE_DIR}/log/curl.sentinel" 2>/dev/null || echo '<absent>')"
check "1: Active exits 0" "0" "$rc"
check "1: Active sets a success status" "success" "$(state)"
check "1: Active writes no issue body" "0" "$([ -f "${CASE_DIR}/log/body.md" ] && echo 1 || echo 0)"

# --------------------------------------------------------------------------- #
# 2. Flagged — installs unaffected; say so, with the resolved version
# --------------------------------------------------------------------------- #
fixture flagged \
    '[{"version":"0.1.33","status":"NodeVersionStatusFlagged","createdAt":"2026-09-28T10:46:18Z","status_reason":"[{\"issue_type\":\"complex-dependency\",\"scanner\":\"x\",\"file_path\":\"web/dist/index.js\",\"description\":\"JS in dist/ directory\"}]"},
      {"version":"0.1.32","status":"NodeVersionStatusFlagged","createdAt":"2026-08-27T00:00:00Z"}]' \
    '{"version":"0.1.33","deprecated":false,"status":"NodeVersionStatusFlagged","createdAt":"2026-09-28T10:46:18Z"}' \
    '{"latest_version":null}'
CASE_DIR="${WORK}/flagged"
rc="$(run_case 0.1.33)"
check "2: Flagged exits 1" "1" "$rc"
check "2: Flagged sets a failure status" "failure" "$(state)"
check "2: the status names the flagged problem" "flagged: v0.1.33" "$(desc)"
check "2: the body does NOT claim installs fall back to an older version" "0" \
    "$(body_has 'resolve to an older version')"
check "2: the body reports the version /install resolves to" "1" \
    "$(body_has 'resolves to **`0.1.33`**')"
check "2: the body states installs are unaffected" "1" "$(body_has 'Installs are unaffected')"
check "2: the body names the real consequence (Active-only listing)" "1" \
    "$(body_has 'latest_version')"
check "2: scan findings are still reported" "1" "$(body_has 'web/dist/index.js')"

# --------------------------------------------------------------------------- #
# 3. Banned — installs skip it; report what they get instead
# --------------------------------------------------------------------------- #
fixture banned \
    '[{"version":"0.1.30","status":"NodeVersionStatusBanned","createdAt":"2026-08-20T00:00:00Z"},
      {"version":"0.1.7","status":"NodeVersionStatusActive","createdAt":"2026-06-08T00:00:00Z"}]' \
    '{"version":"0.1.7","deprecated":true,"status":"NodeVersionStatusActive","createdAt":"2026-06-08T00:00:00Z"}' \
    '{"latest_version":{"version":"0.1.7"}}'
CASE_DIR="${WORK}/banned"
rc="$(run_case 0.1.30)"
check "3: Banned exits 1" "1" "$rc"
check "3: Banned sets a failure status (never success/Active)" "failure" "$(state)"
check "3: the status names the banned problem" "banned: v0.1.30" "$(desc)"
check "3: the body says the version is Banned" "1" "$(body_has '**Banned**')"
check "3: the body names the version /install actually resolves to" "1" \
    "$(body_has 'resolves to **`0.1.7`**')"
check "3: the body flags the fallback as deprecated" "1" "$(body_has 'deprecated')"
check "3: the tracking issue is not closed as Active" "0" \
    "$(grep -q 'issue close' "${CASE_DIR}/log/gh.log" 2>/dev/null && echo 1 || echo 0)"

# --------------------------------------------------------------------------- #
# 4. Banned, /install unreachable — degrade to an explicit "could not read"
# --------------------------------------------------------------------------- #
fixture banned-noinstall \
    '[{"version":"0.1.30","status":"NodeVersionStatusBanned","createdAt":"2026-08-20T00:00:00Z"}]'
CASE_DIR="${WORK}/banned-noinstall"
rc="$(run_case 0.1.30)"
check "4: still exits 1 when /install fails" "1" "$rc"
check "4: still reports banned" "banned: v0.1.30" "$(desc)"
check "4: no empty backticks for the resolved version" "0" "$(body_has '**``**')"
check "4: says the resolved version could not be read" "1" "$(body_has 'could not be read')"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0

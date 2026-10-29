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
#   5. Deleted     -> exit 1, failure status "deleted" (never "Active"), body
#                     says Deleted and names the version /install resolves to
#                     (#2994: Deleted fell through to "Active in registry").
#                     No scan-findings section (deletion is not a scan
#                     verdict), and the fallback is worded as expected, not
#                     verified — no Deleted version is publicly listed to test.
#   6. Flagged with no status_reason -> no bare "  - " findings bullet; the
#                     list says "(none reported)" instead (#2994).
#   7. Docs        -> every doc sentence that says installs fall back and names
#                     Banned, or gives Banned's install-impact verdict ("Banned:
#                     yes|no"), also names Deleted (the follow-up to #2994: the
#                     docs still said only Banned falls back). Units are sentences,
#                     list items, blockquote lines and paragraphs (a blank line, a
#                     new list item or blockquote line ends one; a heading is a unit
#                     of its own), and each table row whole. A status-table row is
#                     exempt only while its other cells name no other status.
#                     Semantic: it pins the claim sentence, so a reword passes and
#                     a sentence that drops Deleted fails. The scan must also exit
#                     0: a crash in it cannot read as zero offenders. CI runs this
#                     test on doc changes via test-skill-scripts.yml.
#   8-13. Repeat runs against an open tracking issue, whose body is the alert an
#                     earlier case really wrote. Unchanged Flagged -> no comment,
#                     exit 0, status still failure (8), also with a human comment
#                     after the alert (9). A new version -> one comment, retitle,
#                     exit 1 (10). Unchanged Banned -> no comment, exit 1 (11). An
#                     issue with no marker yet -> one comment (12). A failed issue
#                     lookup fails the run without opening a duplicate (13).
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
        list)   # the open tracking issue number, if the case has one
            if [ -f "${FIXTURE}/list.fail" ]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi
            cat "${FIXTURE}/existing" 2>/dev/null
            exit 0 ;;
        view)   # apply the caller's --jq to the case's canned issue JSON, as gh does
            filter=""
            while [ $# -gt 0 ]; do
                [ "$1" = "--jq" ] && filter="$2"
                shift
            done
            jq -r "$filter" "${FIXTURE}/issue.json"
            exit $? ;;
        edit)
            while [ $# -gt 0 ]; do
                [ "$1" = "--title" ] && printf '%s\n' "$2" >"${STUB_LOG}/title"
                shift
            done ;;
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
check "3: Banned with no status_reason still lists scan findings" "1" \
    "$(body_has 'Scan findings')"
check "3: ...and says none were reported" "1" "$(body_has '(none reported)')"
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

# --------------------------------------------------------------------------- #
# 5. Deleted — must never be reported Active (#2994)
# --------------------------------------------------------------------------- #
fixture deleted \
    '[{"version":"0.2.4","status":"NodeVersionStatusDeleted","createdAt":"2026-09-30T00:00:00Z"},
      {"version":"0.2.3","status":"NodeVersionStatusActive","createdAt":"2026-09-01T00:00:00Z"}]' \
    '{"version":"0.2.3","deprecated":false,"status":"NodeVersionStatusActive","createdAt":"2026-09-01T00:00:00Z"}' \
    '{"latest_version":{"version":"0.2.3"}}'
CASE_DIR="${WORK}/deleted"
rc="$(run_case 0.2.4)"
check "5: Deleted exits 1" "1" "$rc"
check "5: Deleted sets a failure status (never success/Active)" "failure" "$(state)"
check "5: the status names the deleted problem" "deleted: v0.2.4" "$(desc)"
check "5: the body says the version is Deleted" "1" "$(body_has '**Deleted**')"
check "5: the body names the version /install actually resolves to" "1" \
    "$(body_has 'resolves to **`0.2.3`**')"
check "5: deletion is not a scan verdict — no scan-findings header" "0" \
    "$(body_has 'Scan findings')"
check "5: ...and no '(none reported)' placeholder" "0" "$(body_has '(none reported)')"
check "5: the fallback is stated as expected, not verified" "1" \
    "$(body_has 'not yet verified against')"
check "5: the remedy line still follows the impact" "1" "$(body_has 'to supersede it')"
check "5: the tracking issue is not closed as Active" "0" \
    "$(grep -q 'issue close' "${CASE_DIR}/log/gh.log" 2>/dev/null && echo 1 || echo 0)"

# --------------------------------------------------------------------------- #
# 6. Flagged with no status_reason — no bare "  - " findings bullet (#2994)
# --------------------------------------------------------------------------- #
fixture flagged-noreason \
    '[{"version":"0.1.40","status":"NodeVersionStatusFlagged","createdAt":"2026-10-01T00:00:00Z"}]' \
    '{"version":"0.1.40","deprecated":false,"status":"NodeVersionStatusFlagged","createdAt":"2026-10-01T00:00:00Z"}' \
    '{"latest_version":null}'
CASE_DIR="${WORK}/flagged-noreason"
rc="$(run_case 0.1.40)"
check "6: Flagged without a reason still exits 1" "1" "$rc"
check "6: no bare '  - ' bullet in the findings list" "0" \
    "$(grep -qxE '[[:space:]]*-[[:space:]]*' "${CASE_DIR}/log/body.md" 2>/dev/null && echo 1 || echo 0)"
check "6: the scan-findings header is still printed" "1" "$(body_has 'Scan findings')"
check "6: the findings list says none were reported" "1" "$(body_has '(none reported)')"

# --------------------------------------------------------------------------- #
# 7. Docs — every sentence that says installs fall back and names Banned, or gives
#    Banned's install-impact verdict, must also name Deleted. The scaffold's Deleted
#    arm was fixed in #3053, but the docs still said only Banned falls back (#2994
#    follow-up). Pinned on the claim sentence: a reword passes, a sentence that names
#    Banned without Deleted fails.
# --------------------------------------------------------------------------- #
DOCS_SCAN="${WORK}/docs-scan.py"
cat >"$DOCS_SCAN" <<'PY'
import os, re, sys
# "installs fall back", "falls back", "falling back", "fall-back", "fell back"
FALL_BACK = re.compile(r"\bfall(?:s|ing)?[ -]?back\b|\bfell back\b")
IMPACT = re.compile(r"Banned: (?:yes|no)")   # "(Flagged: no; Banned: yes)" verdict list
# A status-table row ("| `NodeVersionStatusBanned` | ... |") names its status in the
# first cell. It is exempt only while its other cells name no status besides that one:
# a row that also names Banned, Deleted or Flagged makes a claim about that status too.
STATUS_ROW = re.compile(r"^\s*\|\s*`NodeVersionStatus(\w+)`\s*\|(.*)$")
# Capitalised on purpose: the lower-case "non-banned" in a Banned row is not a claim.
# The lookbehind takes the spelling `NodeVersionStatusBanned`: there is no word
# boundary between "Status" and "Banned", so \b alone would miss it.
STATUS_WORD = re.compile(r"(?:\b|(?<=NodeVersionStatus))(?:Banned|Deleted|Flagged)\b")
LIST_ITEM = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s")
BLOCKQUOTE = re.compile(r"^\s*>")
HEADING = re.compile(r"^\s*#{1,6}\s")


def blocks(lines):
    """Yield each unit of prose: a paragraph, a list item or a blockquote line (its
    continuation lines joined), a heading, or one table row. A blank line, or the
    start of a list item or blockquote line, ends the paragraph before it. A heading
    ends the paragraph before it and is a unit of its own."""
    buf = []
    for line in lines:
        if not line.strip():
            if buf:
                yield " ".join(buf)
                buf = []
        elif line.lstrip().startswith("|"):
            if buf:
                yield " ".join(buf)
                buf = []
            yield line
        elif HEADING.match(line):
            if buf:
                yield " ".join(buf)
                buf = []
            yield line
        else:
            if (LIST_ITEM.match(line) or BLOCKQUOTE.match(line)) and buf:
                yield " ".join(buf)
                buf = []
            buf.append(line)
    if buf:
        yield " ".join(buf)


offenders, empty = [], []
for path in sys.argv[1:]:
    if not os.path.isfile(path):
        empty.append(path)
        continue
    claims = 0
    for block in blocks(open(path, encoding="utf-8").read().splitlines()):
        row = STATUS_ROW.match(block)
        if row and not (set(STATUS_WORD.findall(row.group(2))) - {row.group(1)}):
            continue  # names only its own status: exempt
        if block.lstrip().startswith("|"):
            units = [block]  # a table row is one unit, never split into sentences
        else:
            units = re.split(r"(?<=\.)\s", re.sub(r"\s+", " ", block))
        for unit in units:
            text = re.sub(r"\s+", " ", unit).strip()
            if not text:
                continue
            if (FALL_BACK.search(text) and "Banned" in text) or IMPACT.search(text):
                claims += 1
                if "Deleted" not in text:
                    offenders.append(f"{path}: {text[:200]}")
    if claims == 0:
        empty.append(path)
for path in empty:
    print(f"EMPTY {path}")
for line in offenders:
    print(f"OFFENDER {line}")
PY
DOCS_PIN_OUT="${WORK}/docs-pin.txt"
python3 "$DOCS_SCAN" "${SKILL_DIR}/../comfy-cli/references/pitfalls.md" \
    "${SKILL_DIR}/references/registry-readiness.md" \
    "${SKILL_DIR}/../comfy-registry-lifecycle/SKILL.md" >"$DOCS_PIN_OUT"
docs_rc=$?   # the python exit status, read before the next command overwrites $?
grep '^OFFENDER ' "$DOCS_PIN_OUT" >&2 || true
docs_offenders=$(grep -c '^OFFENDER ' "$DOCS_PIN_OUT" || true)
docs_empty=$(grep -c '^EMPTY ' "$DOCS_PIN_OUT" || true)
check "7: the docs scan runs to completion (a crash must not read as zero offenders)" "0" "$docs_rc"
check "7: every install-fallback claim in the docs names Deleted beside Banned" "0" "$docs_offenders"
check "7: each doc file carries at least one install-fallback claim (not vacuous)" "0" "$docs_empty"

# Fixture docs run through the same scan, so each shape the scan must judge is
# pinned on its own. doc_offenders <name> <markdown> prints the OFFENDER count;
# a crashed scan prints "scan-crash" so it can never equal an expected 0 or 1.
doc_offenders() {
    local f="${WORK}/doc-fixtures/$1.md" out rc
    mkdir -p "${WORK}/doc-fixtures"
    printf '%s\n' "$2" >"$f"
    out="$(python3 "$DOCS_SCAN" "$f")"
    rc=$?
    if [ "$rc" -ne 0 ]; then echo "scan-crash"; return; fi
    grep -c '^OFFENDER ' <<<"$out" || true
}

# A Flagged status row that also names Banned's fall-back makes a claim about Banned.
FLAGGED_ROW='| Status | Install impact |
|---|---|
| `NodeVersionStatusFlagged` | Still installable; only a Banned version makes installs fall back; |'
check "7: a Flagged status row naming Banned's fall-back is checked, not exempt" "1" \
    "$(doc_offenders flagged-row "$FLAGGED_ROW")"

# The spelling `NodeVersionStatusBanned` has no word boundary before "Banned", so a
# status-word search that relies on \b alone misses it and exempts the row.
FLAGGED_ROW_SPELLED='| Status | Install impact |
|---|---|
| `NodeVersionStatusFlagged` | Still installable; only a `NodeVersionStatusBanned` version makes installs fall back |'
check "7: a Flagged row naming Banned as NodeVersionStatusBanned is checked, not exempt" "1" \
    "$(doc_offenders flagged-row-spelled "$FLAGGED_ROW_SPELLED")"

# Consecutive list items without trailing periods are separate units.
LIST_ITEMS='- Only a **Banned** version makes installs fall back to an older one
- A **Deleted** version is removed from the listing'
check "7: list items without trailing periods are separate units" "1" \
    "$(doc_offenders list-items "$LIST_ITEMS")"

# A blank line ends a paragraph: a Deleted line after it does not excuse Banned.
BLANK_SPLIT='Only a **Banned** version makes installs fall back to an older one

A **Deleted** version is removed from the listing'
check "7: a blank line ends a paragraph before the next Deleted line" "1" \
    "$(doc_offenders blank-line "$BLANK_SPLIT")"

# A heading is a unit of its own: with no blank line after it, its Banned claim must
# not borrow the paragraph's Deleted.
HEADING_MERGE='## Only a **Banned** version makes installs fall back
A **Deleted** version is removed from the listing'
check "7: a heading with no blank line before the paragraph is its own unit" "1" \
    "$(doc_offenders heading-merge "$HEADING_MERGE")"

# Consecutive blockquote lines are separate units, as consecutive list items are.
BLOCKQUOTE_LINES='> Only a **Banned** version makes installs fall back to an older one
> A **Deleted** version is removed from the listing'
check "7: consecutive blockquote lines without trailing periods are separate units" "1" \
    "$(doc_offenders blockquote-lines "$BLOCKQUOTE_LINES")"

# Controls: must pass before and after the fix.
SAME_SENTENCE='- A **Banned** version makes installs fall back; a **Deleted** version is expected to do the same.'
check "7: a Banned fall-back claim that names Deleted in its sentence passes" "0" \
    "$(doc_offenders same-sentence "$SAME_SENTENCE")"
OWN_STATUS_ROW='| `NodeVersionStatusBanned` | not installable; installs fall back to an older version |'
check "7: a status row naming only its own status stays exempt" "0" \
    "$(doc_offenders own-status-row "$OWN_STATUS_ROW")"

# --------------------------------------------------------------------------- #
# 8-13. Repeat runs against an OPEN tracking issue. Every scheduled day used to
#    re-comment and exit 1 with nothing new (comfyui-image-browser#113: 26
#    identical "0.1.33 is Flagged" comments). Each "previous alert" below is the
#    body an earlier case actually wrote, so the marker is never retyped here.
# --------------------------------------------------------------------------- #
gh_called() { grep -c -- "$1" "${CASE_DIR}/log/gh.log" 2>/dev/null || true; }
# open_issue <case> <number> <body-file> [comment-text...]: the case's open issue
open_issue() {
    local case_name="$1" number="$2" body_file="$3"
    shift 3
    printf '%s\n' "$number" >"${WORK}/${case_name}/fixture/existing"
    jq -n --rawfile b "$body_file" '{body: $b, comments: ($ARGS.positional | map({body: .}))}' \
        --args "$@" >"${WORK}/${case_name}/fixture/issue.json"
}
FLAGGED_ALERT="${WORK}/flagged/log/body.md"
BANNED_ALERT="${WORK}/banned/log/body.md"
check "8: the first alert carries a registry-health marker (guards 8-12 from vacuity)" "1" \
    "$(grep -c '^<!-- registry-health .*-->$' "$FLAGGED_ALERT" 2>/dev/null || true)"

# 8. Same Flagged verdict as the open issue's alert: no comment, exit 0, still red status.
mkdir -p "${WORK}/flagged-repeat" && cp -R "${WORK}/flagged/fixture" "${WORK}/flagged-repeat/fixture"
open_issue flagged-repeat 113 "$FLAGGED_ALERT"
CASE_DIR="${WORK}/flagged-repeat"
rc="$(run_case 0.1.33)"
check "8: an unchanged Flagged verdict exits 0" "0" "$rc"
check "8: ...and posts no comment" "0" "$(gh_called 'issue comment')"
check "8: ...opens no new issue" "0" "$(gh_called 'issue create')"
check "8: ...leaves the title alone" "0" "$(gh_called 'issue edit')"
check "8: the commit status still reports the verdict" "failure" "$(state)"
check "8: the run says why it passed" "1" \
    "$(grep -c '::warning::release 0.1.33 is still flagged' "${CASE_DIR}/log/stdout" 2>/dev/null || true)"

# 9. A person commented after the last alert: still unchanged (newest MARKER, not
#    newest comment, decides).
mkdir -p "${WORK}/flagged-triaged" && cp -R "${WORK}/flagged/fixture" "${WORK}/flagged-triaged/fixture"
open_issue flagged-triaged 113 "$FLAGGED_ALERT" "Triage: real finding, fixed in #122; clears on the next release."
CASE_DIR="${WORK}/flagged-triaged"
rc="$(run_case 0.1.33)"
check "9: a human comment after the alert does not trigger a repeat" "0" "$(gh_called 'issue comment')"
check "9: ...and the run still exits 0" "0" "$rc"

# 10. The open issue's alert is for an older version: comment once, retitle, exit 1.
fixture flagged-old \
    '[{"version":"0.1.32","status":"NodeVersionStatusFlagged","createdAt":"2026-08-27T00:00:00Z"}]' \
    '{"version":"0.1.32","deprecated":false,"status":"NodeVersionStatusFlagged","createdAt":"2026-08-27T00:00:00Z"}' \
    '{"latest_version":null}'
CASE_DIR="${WORK}/flagged-old"
rc="$(run_case 0.1.32)"
check "10: control: the 0.1.32 first alert was written" "1" "$([ -s "${CASE_DIR}/log/body.md" ] && echo 1 || echo 0)"
mkdir -p "${WORK}/flagged-newver" && cp -R "${WORK}/flagged/fixture" "${WORK}/flagged-newver/fixture"
open_issue flagged-newver 113 "${WORK}/flagged-old/log/body.md"
CASE_DIR="${WORK}/flagged-newver"
rc="$(run_case 0.1.33)"
check "10: a new flagged version comments on the open issue" "1" "$(gh_called 'issue comment')"
check "10: ...retitles it to the current version" "Registry: release 0.1.33 not healthy (flagged)" \
    "$(cat "${CASE_DIR}/log/title" 2>/dev/null || echo '<none>')"
check "10: ...and exits 1, since it is news" "1" "$rc"

# 11. Unchanged Banned: no repeat comment, but still exit 1 (installs are broken).
mkdir -p "${WORK}/banned-repeat" && cp -R "${WORK}/banned/fixture" "${WORK}/banned-repeat/fixture"
open_issue banned-repeat 49 "$BANNED_ALERT"
CASE_DIR="${WORK}/banned-repeat"
rc="$(run_case 0.1.30)"
check "11: an unchanged Banned verdict posts no comment" "0" "$(gh_called 'issue comment')"
check "11: ...and still exits 1" "1" "$rc"

# 12. Legacy issue: comments written before the marker existed. Comment once.
mkdir -p "${WORK}/flagged-legacy" && cp -R "${WORK}/flagged/fixture" "${WORK}/flagged-legacy/fixture"
printf '%s\n' "Declared version **\`0.1.33\`** is **Flagged** by Comfy-Org registry moderation." >"${WORK}/legacy-body.md"
open_issue flagged-legacy 113 "${WORK}/legacy-body.md" "Declared version **\`0.1.33\`** is **Flagged** by Comfy-Org registry moderation."
CASE_DIR="${WORK}/flagged-legacy"
rc="$(run_case 0.1.33)"
check "12: an issue with no marker yet gets one marked comment" "1" "$(gh_called 'issue comment')"
check "12: ...and that run exits 1" "1" "$rc"

# 13. The open-issue lookup fails: the run must fail, not open a duplicate issue.
mkdir -p "${WORK}/list-fail" && cp -R "${WORK}/flagged/fixture" "${WORK}/list-fail/fixture"
: >"${WORK}/list-fail/fixture/list.fail"
CASE_DIR="${WORK}/list-fail"
rc="$(run_case 0.1.33)"
check "13: a failed issue lookup fails the run" "1" "$([ "$rc" != "0" ] && echo 1 || echo 0)"
check "13: ...without opening a duplicate issue" "0" "$(gh_called 'issue create')"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0

#!/usr/bin/env bash
# Regression tests for check-issue-draft.sh — the draft scanner
# session-workflow-capture runs before filing an issue.
#
# Every leak class is paired with a clean counterpart so the suite fails both a
# scanner that misses the class and one that flags everything: home paths vs
# ~/.claude config paths, real emails vs noreply/example, private IPs vs the
# documentation ranges, the calling repo vs the same repo as target. Also:
# audience severities (public vs project), private terms from settings (inline
# and block lists) and a deny file, a stubbed gitleaks (rows added, duplicates
# with the regex set suppressed), usage errors, and the structured-output
# contract via check-structured-output-contract.sh --validate.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SCRIPT_DIR/../check-issue-draft.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONTRACT="$REPO_ROOT/scripts/check-structured-output-contract.sh"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

pass=0
fail=0
check() {
  local label="$1" haystack="$2" needle="$3"
  if grep -qF -e "$needle" <<<"$haystack"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $label"
    echo "  expected to find: $needle"
  fi
}
check_absent() {
  local label="$1" haystack="$2" needle="$3"
  if grep -qF -e "$needle" <<<"$haystack"; then
    fail=$((fail + 1))
    echo "FAIL: $label (unexpected: $needle)"
  else
    pass=$((pass + 1))
  fi
}

SANDBOX="$(mktemp -d)" || { echo "mktemp failed"; exit 1; }
[ -n "$SANDBOX" ] || { echo "empty sandbox path"; exit 1; }
trap 'rm -rf "$SANDBOX"' EXIT

HOME_DIR="$SANDBOX/home"
PROJ="$SANDBOX/acme-checkout"
mkdir -p "$HOME_DIR/.claude" "$PROJ/.claude"
git -C "$PROJ" init -q
git -C "$PROJ" remote add origin git@github.com:me/widgets.git

# Hermetic by default: no real gitleaks.
export CHECK_ISSUE_DRAFT_GITLEAKS_BIN="$SANDBOX/no-such-gitleaks"

scan() { # audience draft [extra args...]
  local aud="$1" d="$2"; shift 2
  bash "$SCANNER" --draft "$d" --audience "$aud" --project-dir "$PROJ" --home-dir "$HOME_DIR" "$@"
}
draft() { printf '%s\n' "$@" > "$SANDBOX/draft.md"; echo "$SANDBOX/draft.md"; }

# === TEST A: a clean generic draft passes ==========================================
D=$(draft "## What" "A fan-out over the caller's file list, one verifier per finding." \
  "Save it under ~/.claude/workflows/<name>.js so it runs by name." \
  "Example: https://example.com/doc and someone@example.com, noreply@github.com, 192.0.2.10.")
OUT=$(scan public "$D" --target-repo acme/plugs); rc=$?
check "A clean exit 0" "rc=$rc" "rc=0"
check "A clean status" "$OUT" "STATUS=OK"
check "A clean count" "$OUT" "ISSUE_COUNT=0"
check_absent "A no reason on OK" "$OUT" "REASON="

# === TEST B: each public leak class ================================================
D=$(draft \
  "line1 /home/alice/src/thing" \
  "line2 C:\\Users\\bob\\work" \
  "line3 ~/.claude/projects/-home-alice-acme/abc.jsonl" \
  "line4 session 3f2504e0-4f89-41d3-9a0c-0305e82c3301 run wf_42a5cdac-1f4 tool toolu_01AtWK84VzE4cRRE2HBdKy" \
  "line5 mail carol@corp.io" \
  "line6 see me/widgets for details" \
  "line7 token ghp_abcdefghijklmnopqrstuvwxyz0123456789" \
  "line8 host db.internal at 10.20.30.40" \
  "line9 [rule](../.claude/rules/x.md)" \
  "line10 checkout ~/repos/widgets" \
  "line11 the acme-checkout dir")
OUT=$(scan public "$D" --target-repo acme/plugs); rc=$?
check "B exit 1 on ERROR" "rc=$rc" "rc=1"
check "B status" "$OUT" "STATUS=ERROR"
check "B home path posix" "$OUT" "TYPE=home_path LINE=1"
check "B home path windows" "$OUT" "TYPE=home_path LINE=2"
check "B transcript path" "$OUT" "TYPE=session_artifact LINE=3"
check "B uuid" "$OUT" "MSG=session or object UUID"
check "B run id" "$OUT" "MSG=Workflow run id (wf_42a5cdac-1f4)"
check "B tool-use id" "$OUT" "MSG=tool-use id"
check "B email" "$OUT" "SEVERITY=ERROR TYPE=email LINE=5"
check "B calling repo" "$OUT" "SEVERITY=ERROR TYPE=calling_repo LINE=6"
check "B secret redacted" "$OUT" "TYPE=secret LINE=7 MSG=GitHub token (ghp_...)"
check_absent "B secret value never printed" "$OUT" "abcdefghijklmnop"
check "B internal host warn" "$OUT" "SEVERITY=WARN TYPE=internal_host LINE=8"
check "B ip warn" "$OUT" "SEVERITY=WARN TYPE=ip_address LINE=8 MSG=IPv4 address (10.20.30.40)"
check "B relative link warn" "$OUT" "SEVERITY=WARN TYPE=relative_link LINE=9"
check "B checkout layout warn" "$OUT" "SEVERITY=WARN TYPE=checkout_layout LINE=10"
check "B repo name warn" "$OUT" "SEVERITY=WARN TYPE=repo_name LINE=10"
check "B checkout dir warn" "$OUT" "SEVERITY=WARN TYPE=checkout_dir LINE=11"
check "B reason names first error" "$OUT" "REASON=home_path: line 1"

# === TEST C: the same repo as target drops the calling-repo checks ==================
D=$(draft "Seen in me/widgets, in the widgets repo.")
OUT=$(scan public "$D" --target-repo ME/Widgets)
check "C same repo flagged" "$OUT" "SAME_REPO=true"
check "C same repo ok" "$OUT" "STATUS=OK"
OUT=$(scan public "$D" --target-repo acme/plugs)
check "C other repo errors" "$OUT" "TYPE=calling_repo"

# === TEST D: a private git host ======================================================
PROJ2="$SANDBOX/proj2"; mkdir -p "$PROJ2"
git -C "$PROJ2" init -q
git -C "$PROJ2" remote add origin ssh://git@git.corp.example/team/svc.git
D=$(draft "Cloned from git.corp.example yesterday.")
OUT=$(bash "$SCANNER" --draft "$D" --audience public --project-dir "$PROJ2" --home-dir "$HOME_DIR" --target-repo acme/plugs)
check "D private host" "$OUT" "SEVERITY=ERROR TYPE=remote_host"
check "D calling repo parsed" "$OUT" "CALLING_REPO=team/svc"

# === TEST E: private terms from settings and a deny file =============================
printf -- '---\nprivate_terms: [Zephyr, "Project Kite"]\n---\n' > "$PROJ/.claude/session-plugin.local.md"
printf -- '---\njournal: x\nprivate_terms:\n  - bluefin\n  - "Oriole"\nother: 1\n---\n' > "$HOME_DIR/.claude/session-plugin.local.md"
printf '# comment\nfalcon-db\n\n' > "$SANDBOX/deny.txt"
D=$(draft "zephyr rollout" "for project kite" "the BLUEFIN host" "oriole team" "falcon-db cluster" "a falconry hobby")
OUT=$(scan public "$D" --target-repo acme/plugs --deny-file "$SANDBOX/deny.txt")
check "E inline list term" "$OUT" "TYPE=private_term LINE=1"
check "E quoted multi-word term" "$OUT" "TYPE=private_term LINE=2"
check "E block list term" "$OUT" "TYPE=private_term LINE=3"
check "E quoted block term" "$OUT" "TYPE=private_term LINE=4"
check "E deny file term" "$OUT" "TYPE=private_term LINE=5"
check_absent "E word-bounded (falconry)" "$OUT" "LINE=6"
check "E term count" "$OUT" "PRIVATE_TERM_COUNT=5"
OUT=$(scan project "$D" --target-repo me/widgets --deny-file "$SANDBOX/deny.txt")
check_absent "E project audience skips private terms" "$OUT" "TYPE=private_term"
rm -f "$PROJ/.claude/session-plugin.local.md" "$HOME_DIR/.claude/session-plugin.local.md"

# === TEST F: project audience severities ===============================================
D=$(draft "path /home/alice/x" "repo me/widgets" "id wf_42a5cdac-1f4" "mail carol@corp.io")
OUT=$(scan project "$D" --target-repo me/widgets); rc=$?
check "F project exit 0 on WARN" "rc=$rc" "rc=0"
check "F project status WARN" "$OUT" "STATUS=WARN"
check "F home path warn" "$OUT" "SEVERITY=WARN TYPE=home_path"
check "F run id warn" "$OUT" "SEVERITY=WARN TYPE=session_artifact"
check "F email warn" "$OUT" "SEVERITY=WARN TYPE=email"
check_absent "F repo identity not checked" "$OUT" "TYPE=calling_repo"
D=$(draft "key sk-ant-api03-abcdefghijklmnopqrstuvwxyz")
OUT=$(scan project "$D" --target-repo me/widgets); rc=$?
check "F secret still ERROR for project" "$OUT" "SEVERITY=ERROR TYPE=secret"
check "F secret exit 1" "rc=$rc" "rc=1"

# === TEST G: stubbed gitleaks ==========================================================
STUB="$SANDBOX/bin"; mkdir -p "$STUB"
cat > "$STUB/gitleaks" <<'EOF'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do
  case "$1" in --report-path) out="$2"; shift 2 ;; *) shift ;; esac
done
printf '[{"StartLine":2,"RuleID":"generic-api-key"},{"StartLine":1,"RuleID":"github-pat"}]\n' > "$out"
EOF
chmod +x "$STUB/gitleaks"
[ -x "$STUB/gitleaks" ] || { echo "FAIL: gitleaks stub not executable"; exit 1; }
D=$(draft "token ghp_abcdefghijklmnopqrstuvwxyz0123456789" "apikey = 'q8Zr2...long'")
OUT=$(CHECK_ISSUE_DRAFT_GITLEAKS_BIN="$STUB/gitleaks" scan public "$D" --target-repo acme/plugs)
check "G gitleaks row added" "$OUT" "TYPE=secret LINE=2 MSG=gitleaks rule generic-api-key"
check_absent "G duplicate of regex hit suppressed" "$OUT" "gitleaks rule github-pat"
check "G regex hit kept" "$OUT" "TYPE=secret LINE=1 MSG=GitHub token"

# === TEST H: usage errors ================================================================
OUT=$(bash "$SCANNER" --audience public); rc=$?
check "H missing draft exit 2" "rc=$rc" "rc=2"
check "H missing draft reason" "$OUT" "REASON=usage: --draft <file> is required"
OUT=$(bash "$SCANNER" --draft "$SANDBOX/draft.md" --audience world); rc=$?
check "H bad audience exit 2" "rc=$rc" "rc=2"
OUT=$(bash "$SCANNER" --draft "$SANDBOX/nope.md" --audience public); rc=$?
check "H absent draft exit 2" "rc=$rc" "rc=2"

# === TEST J: review-hardening rules (each paired with a clean counterpart) ===============
D=$(draft \
  "j1 OPENAI_API_KEY=sk-proj-AbCd_EfGh-IjKlMnOpQrStUvWxYz0123" \
  "j2 the file is under /Users/lauri." \
  "j3 open \\\\wsl\$\\Ubuntu\\home\\jdoe\\work" \
  "j4 slug -home-jdoe-work-ledger/abc.jsonl" \
  "j5 role arn:aws:iam::123456789012:role/deployer" \
  "j6 AWS account id: 123456789012" \
  "j7 seen in the me org" \
  "j8 clone https://ghp_abcdefghijklmnopqrstuvwxyz0123456789@github.com/acme/x" \
  "j9 see https://jira.acme.io/browse/PAY-123 and https://acme.slack.com/archives/C0123" \
  "j10 db.internal.")
OUT=$(scan public "$D" --target-repo acme/plugs)
check "J sk-proj key" "$OUT" "TYPE=secret LINE=1 MSG=OpenAI project or service key (sk-p...)"
check "J home path at sentence end" "$OUT" "SEVERITY=ERROR TYPE=home_path LINE=2"
check "J WSL home path" "$OUT" "TYPE=home_path LINE=3 MSG=WSL home path"
check "J transcript slug" "$OUT" "TYPE=session_artifact LINE=4 MSG=Claude transcript slug"
check "J ARN" "$OUT" "TYPE=cloud_account LINE=5"
check "J account id" "$OUT" "TYPE=cloud_account LINE=6 MSG=AWS account id"
check_absent "J owner too short to scan (me)" "$OUT" "TYPE=calling_owner LINE=7"
check "J URL credential flagged as secret" "$OUT" "TYPE=secret LINE=8"
check_absent "J URL credential not printed via email" "$OUT" "TYPE=email LINE=8"
check_absent "J token never printed" "$OUT" "abcdefghijklmnop"
check "J ticket link" "$OUT" "SEVERITY=WARN TYPE=ticket_link LINE=9"
check "J chat link" "$OUT" "SEVERITY=WARN TYPE=chat_link LINE=9"
check "J sentence-final internal host" "$OUT" "TYPE=internal_host LINE=10"

# Clean counterparts: none of these may raise a row.
D=$(draft \
  "Clone with git clone git@github.com:acme/plugs.git" \
  "Edit .claude/session-plugin.local.md and settings.local.json" \
  "An id looks like 123e4567-e89b-12d3-a456-426614174000 or 00000000-0000-0000-0000-000000000000" \
  "Work from home - office hours" \
  "The ~/.claude/workflows/<name>.js file")
OUT=$(scan public "$D" --target-repo acme/plugs)
check "J clean counterparts OK" "$OUT" "STATUS=OK"

# The calling owner, when the target belongs to someone else.
PROJ3="$SANDBOX/proj3"; mkdir -p "$PROJ3"
git -C "$PROJ3" init -q
git -C "$PROJ3" remote add upstream git@github.com:acme-corp/payments-api.git
D=$(draft "Seen in the acme-corp org.")
OUT=$(bash "$SCANNER" --draft "$D" --audience public --project-dir "$PROJ3" --home-dir "$HOME_DIR" --target-repo laurigates/claude-plugins)
check "J non-origin remote is read" "$OUT" "CALLING_REPO=acme-corp/payments-api"
check "J calling owner flagged" "$OUT" "SEVERITY=ERROR TYPE=calling_owner LINE=1"
OUT=$(bash "$SCANNER" --draft "$D" --audience public --project-dir "$PROJ3" --home-dir "$HOME_DIR" --target-repo acme-corp/other)
check_absent "J same owner as target is not flagged" "$OUT" "TYPE=calling_owner"

# No remote at all: the repo checks could not run, and the report says so.
PROJ4="$SANDBOX/proj4"; mkdir -p "$PROJ4"
D=$(draft "nothing here")
OUT=$(bash "$SCANNER" --draft "$D" --audience public --project-dir "$PROJ4" --home-dir "$HOME_DIR" --target-repo acme/plugs)
check "J no remote warns" "$OUT" "SEVERITY=WARN TYPE=calling_repo_unknown"
OUT=$(bash "$SCANNER" --draft "$D" --audience project --project-dir "$PROJ4" --home-dir "$HOME_DIR" --target-repo acme/plugs)
check_absent "J no remote: project audience silent" "$OUT" "calling_repo_unknown"

# === TEST I: structured-output contract ==================================================
if [ -f "$CONTRACT" ]; then
  for case_name in ok warn error; do
    case "$case_name" in
      ok) D=$(draft "nothing to see") ;;
      warn) D=$(draft "host db.internal") ;;
      error) D=$(draft "mail carol@corp.io" "host db.internal" "path /home/alice/x") ;;
    esac
    OUT=$(scan public "$D" --target-repo acme/plugs)
    V=$(bash "$CONTRACT" --validate - <<<"$OUT"); vrc=$?
    check "I contract $case_name exit" "vrc=$vrc" "vrc=0"
    check "I contract $case_name status" "$V" "STATUS=OK"
  done
else
  echo "SKIP: $CONTRACT not found (contract validation runs in the marketplace repo)"
fi

echo ""
echo "check-issue-draft: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

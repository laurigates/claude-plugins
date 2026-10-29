#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixtures are the LITERAL, unexpanded command text a hook receives
# Regression tests for public-repo-leak-gate.sh and repo-visibility.sh
#
# Run: bash documentation-plugin/hooks/test-public-repo-leak-gate.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# The hook always exits 0 and signals a nudge with a PreToolUse
# permissionDecision:"ask" envelope on stdout, so tests assert on stdout. Every
# behaviour is paired: an ask where a leak reaches a public destination, and
# silence for the private / clean / exempt / opted-out counterpart, so the suite
# fails both an over-firing gate and a permanently silent one. gh is mocked.
set -uo pipefail

# Neutralize any inherited git context before building sandbox repos (issues #1745, #3080).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

for dep in jq git rg; do
    command -v "$dep" >/dev/null 2>&1 || { echo "SKIP: $dep not installed"; exit 0; }
done

HOOK="$(cd "$(dirname "$0")" && pwd)/public-repo-leak-gate.sh"
RESOLVER="$(cd "$(dirname "$0")" && pwd)/repo-visibility.sh"
PASS=0
FAIL=0

ROOT=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "$ROOT" ] || { echo "mktemp -d returned no dir" >&2; exit 1; }
trap 'rm -rf "$ROOT"' EXIT

MOCK_BIN="$ROOT/bin"
VIS_DIR="$ROOT/vis"          # one file per owner__repo holding the mocked visibility
CALLS="$ROOT/gh-calls"       # one line per mocked gh invocation
CACHE="$ROOT/cache"
PORTFOLIO="$ROOT/portfolio"
mkdir -p "$MOCK_BIN" "$VIS_DIR" "$CACHE" "$PORTFOLIO/.claude"
: >"$CALLS"

cat >"$MOCK_BIN/gh" <<'MOCK_EOF'
#!/usr/bin/env bash
# gh api repos/<owner>/<repo> --jq .visibility  →  contents of $VIS_DIR/<owner>__<repo>
echo "$*" >>"$CALLS"
if [ "${1:-}" = "api" ]; then
    slug=${2#repos/}
    f="$VIS_DIR/${slug%%/*}__${slug#*/}"
    [ -f "$f" ] && { cat "$f"; exit 0; }
    echo "HTTP 404" >&2
    exit 1
fi
exit 0
MOCK_EOF
chmod +x "$MOCK_BIN/gh"
[ -x "$MOCK_BIN/gh" ] || { echo "mock gh not executable" >&2; exit 1; }

printf '%s\n' 'Acme project id::\bacme-[a-z][a-z0-9-]{2,}\b' >"$PORTFOLIO/.claude/public-export.patterns"
printf '%s\n' '# owners whose own public repos may carry the org identifiers' 'exemptco' \
    >"$PORTFOLIO/.claude/public-export.exempt-owners"

echo public >"$VIS_DIR/octo__pub"
echo private >"$VIS_DIR/octo__priv"
echo public >"$VIS_DIR/exemptco__pub2"
# octo/flaky has no file: the lookup fails → visibility unknown

make_repo() {   # make_repo <dir> [origin-url]
    git init -q "$1"
    git -C "$1" config commit.gpgsign false
    git -C "$1" config user.email t@example.com
    git -C "$1" config user.name Test
    git -C "$1" config core.hooksPath /dev/null   # keep the host's global commit hooks out
    [ -n "${2:-}" ] && git -C "$1" remote add origin "$2"
    printf 'seed\n' >"$1/tracked.txt"
    git -C "$1" add tracked.txt
    git -C "$1" commit -q -m init
}
PUB="$PORTFOLIO/pub";     make_repo "$PUB" "https://github.com/octo/pub.git"
PRIV="$PORTFOLIO/priv";   make_repo "$PRIV" "git@github.com:octo/priv.git"
FLAKY="$PORTFOLIO/flaky"; make_repo "$FLAKY" "https://github.com/octo/flaky"
EXEMPT="$PORTFOLIO/pub2"; make_repo "$EXEMPT" "https://github.com/exemptco/pub2.git"
LOCAL="$PORTFOLIO/local"; make_repo "$LOCAL"

bash_json() {   # bash_json <command> <cwd>
    jq -n --arg c "$1" --arg d "$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d,session_id:"t"}'
}
mcp_json() {    # mcp_json <tool> <owner> <repo> <body> <cwd>
    jq -n --arg t "$1" --arg o "$2" --arg r "$3" --arg b "$4" --arg d "$5" \
        '{tool_name:$t,tool_input:{owner:$o,repo:$r,issue_number:1,body:$b},cwd:$d,session_id:"t"}'
}
run_hook() {
    printf '%s' "$1" | PATH="$MOCK_BIN:$PATH" VIS_DIR="$VIS_DIR" CALLS="$CALLS" \
        XDG_CACHE_HOME="$CACHE" CLAUDE_PUBLIC_EXPORT_PATTERNS="" CLAUDE_PUBLIC_EXPORT_EXEMPT_OWNERS="" \
        bash "$HOOK" 2>/dev/null
}
stage() {       # stage <repo> <content> — replaces the staged change with one new file
    git -C "$1" reset -q
    git -C "$1" checkout -q -- tracked.txt
    rm -f "$1/new.txt"
    printf '%s\n' "$2" >"$1/new.txt"
    git -C "$1" add new.txt
}

expect_ask() {  # expect_ask <name> <output> <substring>
    local decision
    decision=$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$2" 2>/dev/null)
    if [ "$decision" = ask ] && grep -qF -- "$3" <<<"$2"; then
        PASS=$((PASS + 1)); echo "PASS: $1"
    else
        FAIL=$((FAIL + 1)); echo "FAIL: $1 — expected ask containing '$3', got: ${2:-<empty>}"
    fi
}
expect_silent() {
    if [ -z "$2" ]; then
        PASS=$((PASS + 1)); echo "PASS: $1"
    else
        FAIL=$((FAIL + 1)); echo "FAIL: $1 — expected no output, got: $2"
    fi
}

# ── Trigger scope ─────────────────────────────────────────────────────────────
stage "$PUB" "db: acme-prod-db"
expect_silent "non-write command is ignored" "$(run_hook "$(bash_json 'git status' "$PUB")")"

# ── git commit: destination visibility decides ────────────────────────────────
out=$(run_hook "$(bash_json 'git commit -m "add config"' "$PUB")")
expect_ask "public repo + staged org id → ask" "$out" "octo/pub is a PUBLIC repository"
expect_ask "ask names the matched pattern" "$out" "Acme project id"

stage "$PRIV" "db: acme-prod-db"
expect_silent "private repo + staged org id → silent" "$(run_hook "$(bash_json 'git commit -m x' "$PRIV")")"

stage "$PUB" "nothing internal here"
expect_silent "public repo + clean diff → silent" "$(run_hook "$(bash_json 'git commit -m x' "$PUB")")"

stage "$FLAKY" "db: acme-prod-db"
expect_ask "unknown visibility fails closed and says so" \
    "$(run_hook "$(bash_json 'git commit -m x' "$FLAKY")")" "could not be determined"

stage "$LOCAL" "db: acme-prod-db"
expect_silent "no origin remote (local-only) → silent" "$(run_hook "$(bash_json 'git commit -m x' "$LOCAL")")"

stage "$PUB" "nothing internal here"
expect_ask "commit message carrying an org id → ask" \
    "$(run_hook "$(bash_json 'git commit -m "migrate acme-prod-db"' "$PUB")")" "Acme project id"

# The cd / -C operands are paths, not published text: a home path there must not flag.
expect_silent "cd/-C path operands are not scanned" \
    "$(run_hook "$(bash_json "cd /Users/nobody/x && git -C \"$PUB\" commit -m ok" "$ROOT")")"
expect_ask "home path in the commit message itself still flags" \
    "$(run_hook "$(bash_json 'git commit -m "see /Users/nobody/notes"' "$PUB")")" "Absolute home path"

git -C "$PUB" reset -q
rm -f "$PUB/new.txt"
printf 'acme-prod-db\n' >>"$PUB/tracked.txt"
expect_ask "commit -a scans the unstaged tracked change" \
    "$(run_hook "$(bash_json 'git commit -am x' "$PUB")")" "Acme project id"
expect_silent "plain commit does not scan unstaged changes" \
    "$(run_hook "$(bash_json 'git commit -m x' "$PUB")")"
git -C "$PUB" checkout -q -- tracked.txt

# ── Exempt owners skip org patterns, keep the built-ins ──────────────────────
stage "$EXEMPT" "db: acme-prod-db"
expect_silent "exempt owner + org id → silent" "$(run_hook "$(bash_json 'git commit -m x' "$EXEMPT")")"
stage "$EXEMPT" "sa: deployer@proj-123.iam.gserviceaccount.com"
expect_ask "exempt owner still gets built-in patterns" \
    "$(run_hook "$(bash_json 'git commit -m x' "$EXEMPT")")" "GCP service-account email"

# ── Cache: a hit within the TTL skips the network ─────────────────────────────
stage "$PUB" "db: acme-prod-db"
before=$(grep -c '' "$CALLS")
rm -f "$VIS_DIR/octo__pub"   # the network would now say "unknown"
out=$(run_hook "$(bash_json 'git commit -m x' "$PUB")")
after=$(grep -c '' "$CALLS")
expect_ask "cached visibility is used" "$out" "octo/pub is a PUBLIC repository"
if [ "$before" = "$after" ]; then
    PASS=$((PASS + 1)); echo "PASS: cache hit makes no gh call"
else
    FAIL=$((FAIL + 1)); echo "FAIL: cache hit made $((after - before)) gh call(s)"
fi
echo public >"$VIS_DIR/octo__pub"
rv=$(PATH="$MOCK_BIN:$PATH" VIS_DIR="$VIS_DIR" CALLS="$CALLS" XDG_CACHE_HOME="$CACHE" bash "$RESOLVER" --repo octo/flaky)
if [ "$rv" = "unknown octo/flaky" ] && [ ! -f "$CACHE/claude-repo-visibility/octo__flaky" ]; then
    PASS=$((PASS + 1)); echo "PASS: unknown is reported and never cached"
else
    FAIL=$((FAIL + 1)); echo "FAIL: resolver gave '$rv' or cached an unknown"
fi

# ── gh pr / issue ─────────────────────────────────────────────────────────────
expect_ask "gh pr comment -R public + body id → ask" \
    "$(run_hook "$(bash_json 'gh pr comment 5 -R octo/pub --body "see acme-prod-db"' "$PORTFOLIO")")" "octo/pub"
expect_silent "gh pr comment -R private → silent" \
    "$(run_hook "$(bash_json 'gh pr comment 5 -R octo/priv --body "see acme-prod-db"' "$PORTFOLIO")")"
expect_ask "gh issue comment by URL resolves the destination" \
    "$(run_hook "$(bash_json 'gh issue comment https://github.com/octo/pub/issues/9 --body "acme-prod-db"' "$PORTFOLIO")")" "octo/pub"
printf 'Rolls out acme-prod-db\n' >"$ROOT/body.md"
expect_ask "gh pr create --body-file content is scanned" \
    "$(run_hook "$(bash_json "gh pr create --title t --body-file $ROOT/body.md" "$PUB")")" "Acme project id"

# ── GitHub MCP writes ─────────────────────────────────────────────────────────
expect_ask "MCP comment to public repo + id → ask" \
    "$(run_hook "$(mcp_json mcp__github__add_issue_comment octo pub 'see acme-prod-db' "$PORTFOLIO")")" "octo/pub"
expect_silent "MCP comment to private repo → silent" \
    "$(run_hook "$(mcp_json mcp__github__add_issue_comment octo priv 'see acme-prod-db' "$PORTFOLIO")")"
expect_silent "non-GitHub MCP tool is ignored" \
    "$(run_hook "$(mcp_json mcp__other__write octo pub 'see acme-prod-db' "$PORTFOLIO")")"

# ── Opt-out ───────────────────────────────────────────────────────────────────
stage "$PUB" "db: acme-prod-db"
out=$(printf '%s' "$(bash_json 'git commit -m x' "$PUB")" | CLAUDE_HOOKS_DISABLE_PUBLIC_LEAK_GATE=1 \
    PATH="$MOCK_BIN:$PATH" VIS_DIR="$VIS_DIR" CALLS="$CALLS" XDG_CACHE_HOME="$CACHE" bash "$HOOK" 2>/dev/null)
expect_silent "opt-out env disables the gate" "$out"

echo
echo "PASSED=$PASS FAILED=$FAIL"
[ "$FAIL" -eq 0 ]

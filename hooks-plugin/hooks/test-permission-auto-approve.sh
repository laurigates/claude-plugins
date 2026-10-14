#!/usr/bin/env bash
# shellcheck disable=SC2016   # single quotes are the point: every fixture is the
# LITERAL text handed to the hook. Letting this shell expand `$(…)` or `$HOME`
# would test the harness, not the hook.
# Regression tests for permission-auto-approve.sh (#2733)
#
# Run: bash hooks-plugin/hooks/test-permission-auto-approve.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Every case pipes PermissionRequest JSON into the SHIPPED hook. It is an ALLOW
# hook, so the property under test is that it never emits {"decision":"approve"}
# for a command containing a statement no approve rule covers.
#
#   A. The issue's table: each row gets NO decision.
#   B. Plain read-only commands are still approved (the hook is not a no-op).
#   C. Shapes outside a plain list/pipeline of plain commands get NO decision.
#   D. Deny rules fire even behind an approved prefix.
#   E. Parser absent / broken / timing out, and tree-sitter ERROR nodes: never
#      approve.
#   F. Generated compound probe: approved A + non-approved B over every
#      separator, both orders: never approve; A + A' still approves.
#   H. #2885: git branch/remote/diff/log/show bypasses (mutating subcommands,
#      --output, --ext-diff, quote/brace/glob spellings) get NO decision;
#      read-only git still approves.
#   I. #2885: deny rules catch respellings (rm -r -f /, rm -rf -- /,
#      git push -f origin main, git push origin +main); near-misses do not deny.
#   J. #2886: runner/linter/gh word boundaries, writer and executor flags,
#      out-of-tree paths get NO decision; plain invocations still approve.
#   G. SUBSET differential: everything the new hook approves in this corpus was
#      approved by the pre-fix hook (pinned commit, embedded verbatim copy for
#      shallow clones; byte-compared when both exist).
#
# Without a working ast-grep only D and the parser-absent half of E can run;
# the suite then ends on one unindented SKIP line so
# scripts/run-skill-script-tests.sh reports it as skipped (an ERROR there,
# because this suite is listed in scripts/required-to-run-tests.txt).
set -uo pipefail

# Neutralize any inherited git context before building sandbox repos (issues #1745, #3080).
# Neutralize any inherited git context before building sandbox repos (issue
# #1745). Under pre-commit, GIT_DIR/GIT_INDEX_FILE point at the real repo and
# override `git -C`, so sandbox git commands would act on the shared clone.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${PERMISSION_AUTO_APPROVE_HOOK:-$HOOK_DIR/permission-auto-approve.sh}"
PINNED_BASELINE_REF=785b0d9802399823dffcda7cfb86f883e2524584
PASS=0
FAIL=0

WORK=$(mktemp -d) || {
    echo "mktemp -d failed" >&2
    exit 1
}
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
    echo "bad work dir" >&2
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT

BASH_BIN=$(command -v bash)

pass() { PASS=$((PASS + 1)); }
fail() {
    FAIL=$((FAIL + 1))
    printf '  FAIL: %s (%s)\n' "$1" "$2"
}

# Every command run with the default environment, with the decision it got, so
# section G can replay the approved ones through the pre-fix hook.
CORPUS=()
CORPUS_DECISION=()

# Sets DECISION (approve / deny / none / invalid) and RC.
# $1 = hook path, $2 = command, rest = env assignments for the hook process.
DECISION=""
RC=0
decide_with() {
    local hook=$1 cmd=$2 json out
    shift 2
    json=$(jq -nc --arg c "$cmd" '{tool_name: "Bash", tool_input: {command: $c}}')
    out=$(printf '%s' "$json" | env "$@" "$BASH_BIN" "$hook" 2>/dev/null)
    RC=$?
    if [ -z "$out" ]; then
        DECISION=none
    else
        DECISION=$(jq -r '.decision // "invalid"' <<<"$out" 2>/dev/null) || DECISION=invalid
        [ -n "$DECISION" ] || DECISION=invalid
    fi
}

# expect <approve|deny|none> <label> <command> [env assignments…]
expect() {
    local want=$1 label=$2 cmd=$3
    shift 3
    decide_with "$HOOK" "$cmd" "$@"
    if [ "$#" -eq 0 ]; then
        CORPUS+=("$cmd")
        CORPUS_DECISION+=("$DECISION")
    fi
    if [ "$RC" -ne 0 ]; then
        fail "$label" "hook exited $RC"
    elif [ "$DECISION" = "$want" ]; then
        pass
    else
        fail "$label" "want $want, got $DECISION"
    fi
}

# /usr/bin/sg is shadow-utils on Debian/Ubuntu, so only `ast-grep` counts here.
HAVE_ASTGREP=false
if command -v ast-grep >/dev/null 2>&1 &&
    printf 'true' | ast-grep scan --inline-rules 'id: c
language: bash
rule: { kind: command }' --stdin --json=compact 2>/dev/null | jq -e 'length == 1' >/dev/null 2>&1; then
    HAVE_ASTGREP=true
fi

echo "  Running permission-auto-approve regression tests (#2733)..."

# ── D. Deny rules, ahead of approve ──────────────────────────────────────────
echo "  == D. deny rules fire, including behind an approved prefix =="
expect deny "rm -rf /" 'rm -rf /'
expect deny "git status && rm -rf /" 'git status && rm -rf /'
expect deny "npm test; rm -rf ~/" 'npm test; rm -rf ~/'
expect deny "git log newline rm -rf \$HOME" $'git log -1\nrm -rf $HOME'
expect deny "git status && force-push main" 'git status && git push --force origin main'

# ── E (parser-absent half). Runs with or without ast-grep installed. ─────────
echo "  == E. parser absent or broken: no approve =="
# A PATH holding only what the hook needs, no ast-grep, and a shadow-utils
# style `sg` (usage on stderr, non-zero exit) that must not pass for ast-grep.
TOOLS="$WORK/tools"
mkdir -p "$TOOLS"
for t in bash jq grep cat env timeout; do
    p=$(command -v "$t") || continue
    ln -sf "$p" "$TOOLS/$t"
done
printf '#!/bin/sh\necho "Usage: sg group -c command" >&2\nexit 1\n' >"$TOOLS/sg"
chmod +x "$TOOLS/sg"
if PATH="$TOOLS" command -v ast-grep >/dev/null 2>&1; then
    fail "PATH-stripped setup" "ast-grep still resolves"
fi
for cmd in 'git status' 'git log --oneline -3' 'npm test' 'gh pr view 1'; do
    expect none "no ast-grep on PATH: $cmd" "$cmd" "PATH=$TOOLS"
done
expect deny "no ast-grep on PATH: deny behind an approved prefix" 'npm test; rm -rf ~/' "PATH=$TOOLS"

# Broken parsers, each the only ast-grep on PATH. `hangs` uses exec so the
# sleeping process IS the parser and a timeout reaches it.
FAKES="$WORK/fakes"
for kind in fails garbage empty hangs; do
    mkdir -p "$FAKES/$kind"
    case $kind in
        fails) printf '#!/bin/sh\ncat >/dev/null\necho boom >&2\nexit 1\n' ;;
        garbage) printf '#!/bin/sh\ncat >/dev/null\necho "{not json"\n' ;;
        empty) printf '#!/bin/sh\ncat >/dev/null\necho "[]"\n' ;;
        hangs) printf '#!/bin/sh\ncat >/dev/null\nexec sleep 30\n' ;;
    esac >"$FAKES/$kind/ast-grep"
    chmod +x "$FAKES/$kind/ast-grep"
    start=$(date +%s)
    expect none "broken parser ($kind): git status" 'git status' "PATH=$FAKES/$kind:$TOOLS"
    elapsed=$(($(date +%s) - start))
    if [ "$elapsed" -gt 15 ]; then
        fail "broken parser ($kind): hook returns promptly" "took ${elapsed}s"
    fi
done

if [ "$HAVE_ASTGREP" = false ]; then
    echo "  Results: $PASS passed, $FAIL failed (parser sections not run)"
    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
    echo "SKIP: no working ast-grep on PATH; sections A, B, C, F, G and the parser half of E require it."
    exit 0
fi

# A parser that LIES, reporting the whole input as one command node: the hook's
# own check of each node's bytes must still refuse what the node hides.
mkdir -p "$FAKES/lies"
cat >"$FAKES/lies/ast-grep" <<'FAKE'
#!/usr/bin/env bash
n=$(($(LC_ALL=C wc -c)))
printf '[{"ruleId":"command","text":"","range":{"byteOffset":{"start":0,"end":%d}}}]\n' "$n"
FAKE
chmod +x "$FAKES/lies/ast-grep"
LIES_PATH="$FAKES/lies:$PATH"
expect approve "lying parser: git status (the path is live)" 'git status' "PATH=$LIES_PATH"
expect none "lying parser: git status; touch" 'git status; touch /tmp/m' "PATH=$LIES_PATH"
expect none "lying parser: git status && touch" 'git status && touch /tmp/m' "PATH=$LIES_PATH"
expect none "lying parser: newline" $'git status\ntouch /tmp/m' "PATH=$LIES_PATH"
expect none "lying parser: git log \$(touch)" 'git log $(touch /tmp/m)' "PATH=$LIES_PATH"
expect none "lying parser: git log > file" 'git log > /tmp/m' "PATH=$LIES_PATH"

# No coreutils `timeout` (stock macOS): the parse still runs, unbounded.
NOTIMEOUT="$WORK/notimeout"
mkdir -p "$NOTIMEOUT"
for t in bash jq grep cat env ast-grep; do
    ln -sf "$(command -v "$t")" "$NOTIMEOUT/$t"
done
expect approve "no timeout binary: git status" 'git status' "PATH=$NOTIMEOUT"
expect none "no timeout binary: git status; touch" 'git status; touch /tmp/m' "PATH=$NOTIMEOUT"

echo "  == E. tree-sitter ERROR node: no approve =="
expect none "unterminated double quote" 'git log "unterminated'
expect none "unterminated if" 'if true; then git status'
expect none "unbalanced paren" 'git status )'
expect none "dangling pipe" 'git status | '

# ── A. The issue's table ─────────────────────────────────────────────────────
echo "  == A. issue #2733 table: no decision =="
expect none "control: touch" 'touch /tmp/marker-2652'
expect none "git status && touch" 'git status && touch /tmp/marker-2652'
expect none "npm test; chmod -R 777 ." 'npm test; chmod -R 777 .'
expect none "git log -1 newline touch" $'git log -1\ntouch /tmp/marker-2652'

# ── B. Plain read-only commands still approve ────────────────────────────────
echo "  == B. plain read-only commands approve =="
for cmd in \
    'git status' \
    '  git status --short' \
    'git log --oneline -5' \
    'git diff HEAD~1 -- README.md' \
    'git show HEAD:README.md' \
    'git rev-parse --show-toplevel' \
    "git log --format='%H %s' -3" \
    'git log --grep "fix: x" -1' \
    'npm test' \
    'npx vitest run' \
    'bun test' \
    'pytest -x tests/' \
    'cargo test' \
    'go test ./...' \
    'make test' \
    'npx eslint src' \
    'bun run lint' \
    'ruff check .' \
    'mypy src' \
    'tsc --noEmit' \
    'gh pr view 12' \
    'gh pr checks 12' \
    'gh issue list --state open' \
    'gh run view 123' \
    'git status && git log -1' \
    'git status; npm test' \
    $'git status\ngit diff' \
    'git log --oneline | git status' \
    'git status &'; do
    expect approve "approve: $(printf '%s' "$cmd" | tr '\n' '~')" "$cmd"
done
# The reason string is the one the matching rule always carried.
out=$(printf '%s' "$(jq -nc --arg c 'npm test' '{tool_name: "Bash", tool_input: {command: $c}}')" | "$BASH_BIN" "$HOOK")
if [ "$(jq -r .reason <<<"$out")" = "Test execution" ]; then
    pass
else
    fail "npm test reason" "got: $out"
fi
# Mixed rules: each node may match a DIFFERENT approve rule.
expect approve "git status && npm test && gh pr view 1" 'git status && npm test && gh pr view 1'

# ── C. Anything but plain commands in a plain list/pipeline ─────────────────
echo "  == C. non-plain shapes: no decision =="
for cmd in \
    'git log $(touch /tmp/m)' \
    'git log `touch /tmp/m`' \
    'git log "$(touch /tmp/m)"' \
    'git diff <(touch /tmp/m)' \
    'git log $REF' \
    'git log "${REF}"' \
    '(git status)' \
    '{ git status; }' \
    'f() { touch /tmp/m; }; git status' \
    'for x in a; do git status; done' \
    'while git status; do touch /tmp/m; done' \
    'if git status; then touch /tmp/m; fi' \
    'git log > /tmp/m' \
    'git log >> /tmp/m' \
    'git status 2>&1' \
    $'git log <<EOF\nhi\nEOF' \
    'git log <<< x' \
    'FOO=1 git status' \
    'GIT_EXTERNAL_DIFF=/tmp/x git diff' \
    'X=1; git status' \
    'export X=1; git status' \
    '! git status' \
    'git status # trailing comment' \
    'git log --grep=a\;b' \
    $'git log --grep "a\nb"' \
    'git status && bash' \
    'npm test || sh -c "touch /tmp/m"'; do
    expect none "non-plain: $(printf '%s' "$cmd" | tr '\n' '~')" "$cmd"
done

# ── F. Generated compound probe ──────────────────────────────────────────────
echo "  == F. compound probe: approved A + non-approved B never approves =="
APPROVED_STMTS=('git status' 'git log -1' 'npm test' 'gh pr view 1' 'ruff check .' 'tsc --noEmit')
UNREVIEWED_STMTS=(
    'touch /tmp/marker-2733'
    'chmod -R 777 .'
    'rm -rf ./src'
    'git push origin HEAD'
    'curl https://example.invalid'
    "python3 -c 'import os'"
    'sh'
)
SEPS=('&&' ' && ' '||' ' || ' ';' '; ' '|' ' | ' '&' ' & ' $'\n' $'\n\n')

N_SPELL=0
PROBE_FAIL=0
for a in "${APPROVED_STMTS[@]}"; do
    for b in "${UNREVIEWED_STMTS[@]}"; do
        for s in "${SEPS[@]}"; do
            for c in "$a$s$b" "$b$s$a"; do
                N_SPELL=$((N_SPELL + 1))
                decide_with "$HOOK" "$c"
                CORPUS+=("$c")
                CORPUS_DECISION+=("$DECISION")
                if [ "$DECISION" = approve ] || [ "$DECISION" = invalid ] || [ "$RC" -ne 0 ]; then
                    PROBE_FAIL=$((PROBE_FAIL + 1))
                    fail "compound probe" "got $DECISION (exit $RC) for: $(printf '%s' "$c" | tr '\n' '~')"
                fi
            done
        done
    done
done
if [ "$PROBE_FAIL" -eq 0 ]; then
    pass
    echo "  compound probe: none of $N_SPELL generated spellings approved"
fi
# Non-vacuity: the same separators between two approved statements approve.
for s in "${SEPS[@]}"; do
    expect approve "approved<sep>approved, sep='$(printf '%s' "$s" | tr '\n' '~')'" "git status${s}git log -1"
done

# expect_each <approve|deny|none> <label prefix> <command>…
expect_each() {
    local want=$1 prefix=$2 cmd
    shift 2
    for cmd in "$@"; do
        expect "$want" "$prefix: $cmd" "$cmd"
    done
}

# ── H. #2885: the read-only git rule checks argv, not just the subcommand ────
echo "  == H. #2885 git bypasses: no decision =="
expect_each none "#2885 git" \
    'git branch -D release' \
    'git branch -f release HEAD~3' \
    'git branch -m foo bar' \
    'git remote add evil https://x' \
    'git remote set-url origin https://x' \
    'git remote remove origin' \
    'git diff --output=/tmp/pwned' \
    'git show --output=/home/u/.bashrc HEAD' \
    'git log --output=/tmp/o' \
    'git diff --no-index a b --output=/etc/x' \
    'git diff --ext-diff' \
    'git diff --textconv' \
    'git statusfoo' \
    'git branch "-D" main' \
    'git diff {--output=/tmp/x,}' \
    'git diff *'
# Adversarial respellings found reviewing the fix.
expect_each none "#2885 git respelled" \
    'git diff --output /tmp/x' \
    'git log --out=/tmp/x' \
    'git show --textconv HEAD' \
    'git log -p --ext-diff' \
    "git branch '-'D main" \
    "git 'branch' -D main" \
    'git branch newbranch' \
    'git branch -d release' \
    'git branch --delete release' \
    'git branch -avD release' \
    'git branch -l release' \
    'git branch --set-upstream-to=origin/x' \
    'git branch -u origin/x' \
    'git branch --unset-upstream' \
    'git branch --edit-description' \
    'git branch -c a b' \
    'git branch --contains HEAD -D release' \
    'git remote -v add evil https://x' \
    'git remote rename origin evil' \
    'git remote prune origin' \
    'git remote update' \
    'git remote set-head origin -a' \
    'git remote show -v origin' \
    'git -C /tmp status' \
    'git -c core.pager=x log' \
    'git diff a?' \
    'git diff [ab]' \
    'git log "--output=/tmp/x"' \
    "git diff '--ext-diff'" \
    'git status	--output=/tmp/x'

echo "  == H. read-only git still approves =="
expect_each approve "git control" \
    'git diff' \
    'git diff --stat HEAD~1' \
    'git diff --no-ext-diff --no-textconv' \
    'git log --output-indicator-new=+ -1 -p' \
    'git branch' \
    'git branch -a' \
    'git branch -vv' \
    'git branch --show-current' \
    'git branch --list release' \
    'git branch --contains HEAD' \
    'git branch --merged main' \
    'git branch --no-merged=main -r' \
    'git remote' \
    'git remote -v' \
    'git remote show origin' \
    'git remote get-url --push origin' \
    'git shortlog -sn' \
    'git blame README.md' \
    'git describe --tags' \
    'git ls-files' \
    'git rev-list --count HEAD' \
    "git log --format='%H %s' -3"

# ── I. #2885: deny rules catch respellings ───────────────────────────────────
echo "  == I. #2885 deny respellings =="
expect_each deny "#2885 deny" \
    'rm -r -f /' \
    'rm -rf -- /' \
    'git push -f origin main' \
    'git push origin +main' \
    'rm -fr ~' \
    'rm -Rf "$HOME"' \
    'rm --recursive --force /' \
    'rm -rf /*' \
    "rm -rf '~/'" \
    'sudo rm -rf /' \
    '/bin/rm -rf ${HOME}/' \
    'rm -rf --no-preserve-root /' \
    'git status && rm -r -f /' \
    'git push --force-with-lease origin main' \
    'git push -fu origin master' \
    'git push origin +HEAD:refs/heads/main' \
    'git push origin feature:main --force' \
    'git -C . push -f origin main' \
    'git push --force origin master'
# Not every rm or push is denied: these stay with the user (no decision).
expect_each none "#2885 deny control" \
    'rm -rf ./build' \
    'rm -r /tmp/x' \
    'git push -f origin feature' \
    'git push origin main' \
    'git push -u origin feat/main-menu'

# ── J. #2886: runner / linter / gh rules check argv ──────────────────────────
echo "  == J. #2886 runner, linter and gh bypasses: no decision =="
expect_each none "#2886 word boundary" \
    'pytest=1 touch /tmp/x' \
    'mypy=1 rm -rf build' \
    'pytestx' \
    'pytest-evil' \
    'mypyx' \
    'npx jest-evil' \
    'npx vitest-evil' \
    'npx eslint-evil' \
    'make test-and-deploy' \
    'make testx' \
    'cargo testx' \
    'gh pr listx'
expect_each none "#2886 writer flags" \
    'npx eslint --fix .' \
    'npx prettier --write .' \
    'npx biome check --write' \
    'ruff check --fix' \
    'mypy --install-types --non-interactive' \
    'tsc --noEmit --outDir x' \
    'bun run lint:fix' \
    'bun run format'
expect_each none "#2886 runner flags" \
    'go test -exec /tmp/x ./...' \
    'go test -o /tmp/bin ./...' \
    'pytest -p evilplugin' \
    'cargo test --config build.rustc-wrapper="/tmp/x"' \
    'pytest --basetemp=/' \
    'npm test -- --updateSnapshot' \
    "pytest '--basetemp=/'" \
    'pytest "-p" evil' \
    'npx eslint {--fix,} .'
# Adversarial respellings found reviewing the fix.
expect_each none "#2886 respelled" \
    'pytest -pevil' \
    'pytest -xp evil' \
    'pytest -k x -p evil' \
    'pytest -k -p evil' \
    'pytest @args.txt' \
    'pytest -c evil.ini' \
    'pytest -W error::evil.Warning' \
    'pytest --base=/' \
    'pytest --rootdir=/tmp' \
    'npm test --script-shell=/tmp/x' \
    'npm test -- -u' \
    'npx vitest -u' \
    'npx vitest --update' \
    'npx vitest init' \
    'npx jest --config evil.js' \
    'npx --yes jest-evil' \
    'bun test --preload ./x.ts' \
    'bun test -u' \
    'go test -toolexec /tmp/x ./...' \
    'go test -exec=/tmp/x ./...' \
    'go test --exec /tmp/x ./...' \
    'go test ./... -args -x' \
    'cargo test --manifest-path /tmp/x/Cargo.toml' \
    'cargo test -Zunstable-options' \
    'cargo test -- --logfile /tmp/x' \
    'make test SHELL=/tmp/x' \
    'make test -f evil.mk' \
    'make test deploy' \
    'make test -C /tmp' \
    'make test -j deploy' \
    'npx eslint -c evil.js .' \
    'npx eslint --rulesdir x .' \
    'npx eslint -o out.txt .' \
    "npx eslint '--fix' ." \
    'npx prettier -w .' \
    'npx prettier --plugin=./evil.js --check .' \
    'npx biome check --apply' \
    'npx biome check --apply-unsafe' \
    'npx biome lint --fix --unsafe' \
    'npx biome migrate --write' \
    'ruff check --fix-only' \
    'ruff check --unsafe-fixes --fix' \
    'ruff check --add-noqa' \
    'ruff check -o x' \
    'mypy --config-file evil.ini src' \
    'mypy --python-executable /tmp/x src' \
    'mypy --junit-xml /tmp/x src' \
    'tsc --noEmit --generateTrace /tmp/x' \
    'tsc --noEmit --build' \
    'tsc --outDir x --noEmit' \
    'bun run lint -- --fix' \
    'bun run check:fix' \
    'MYPYPATH=x mypy src' \
    'pytest	-p evil' \
    'pytest /tmp/evil_test.py' \
    'pytest ~/evil_test.py' \
    'pytest tests/../../evil_test.py' \
    'bun test /tmp/x.test.ts' \
    'npx vitest run ../other-repo' \
    'go test /tmp/pkg' \
    'npm test -- /tmp/x.test.js'

echo "  == J. plain runner, linter and gh invocations still approve =="
expect_each approve "runner/linter control" \
    'pytest' \
    'pytest -xvs tests/test_a.py' \
    'pytest -k "foo and bar" -q' \
    'pytest tests/test_x.py::test_y --tb=short' \
    'pytest --maxfail 1 -rA' \
    'npm test -- --run' \
    'npx vitest' \
    'npx jest' \
    'npx jest src/a.test.ts --ci' \
    'bun test --bail' \
    'cargo test --workspace' \
    'cargo test -p core -- --nocapture' \
    'go test -v -race ./...' \
    'go test -run TestX -count=1 ./pkg' \
    'npx eslint .' \
    'npx eslint --max-warnings 0 .' \
    'npx eslint --fix-dry-run .' \
    'npx prettier --check .' \
    'npx biome check' \
    'npx biome lint src' \
    'bun run check' \
    'ruff check --select E501 src' \
    'mypy --strict src' \
    'tsc --noEmit -p tsconfig.json' \
    'gh pr list --state open' \
    'gh pr diff 12' \
    'gh issue view 3 --comments' \
    'gh run list --limit 5'

# ── K. PR #3051 review: value-flag values and unknown flags ──────────────────
# A value flag's value (`-p v` or `-p=v`) passes the same path gates as a
# positional: no absolute, ~, .. or @file value. `-t`/`-k` take a test-name
# pattern, not a path, but a pattern spelled like an absolute path going to the
# prompt is the safe polarity.
echo "  == K. value-flag values are path-gated; unknown flags refused =="
expect_each none "value-flag path gate" \
    'tsc --noEmit -p /tmp/evil-config' \
    'npx jest -t /tmp/evil' \
    'pytest --durations /tmp/x' \
    'mypy -p /tmp/evil' \
    'tsc --noEmit --project=/tmp/evil' \
    'tsc --noEmit -p ~/evil' \
    'tsc --noEmit -p ../evil/tsconfig.json' \
    'mypy --package=../evil' \
    'pytest --deselect=/tmp/x' \
    'pytest --ignore ../x' \
    'pytest -k @args.txt' \
    'cargo test -p /tmp/x' \
    'go test -run /tmp/x ./...' \
    'npx eslint --ext=~/x .' \
    'npm test -- -t /tmp/evil'
# A `-`-prefixed word no flag/value treatment matched is refused.
expect_each none "unknown flag" \
    'git remote show --eh origin' \
    'git remote get-url --eh origin' \
    'git remote show -n --eh origin' \
    'pytest --eh' \
    'tsc --noEmit --eh'
expect_each approve "value-flag control" \
    'pytest -k test_foo' \
    'npx jest -t "adds numbers"' \
    'tsc --noEmit -p tsconfig.json' \
    'tsc --noEmit --project=tsconfig.json' \
    'mypy -p mypkg' \
    'pytest --durations 5' \
    'pytest --deselect=tests/test_a.py::test_b' \
    'cargo test -p core' \
    'go test -run TestX ./...' \
    'git remote show -n origin' \
    'git remote get-url --push origin'

# ── G. Subset differential against the pre-fix hook ──────────────────────────
echo "  == G. subset differential: new approvals are a subset of pre-fix approvals =="
BASELINE="$WORK/baseline.sh"
cat >"$BASELINE" <<'PREFIX_HOOK'
#!/usr/bin/env bash
# PermissionRequest hook — auto-approve safe operations, auto-deny dangerous ones
#
# Toggle: set CLAUDE_HOOKS_DISABLE_PERMISSION_AUTO=1 to skip this hook
#
# Matches: Bash (and optionally all tools)
# Approves: read-only git, test runners, linters
# Denies: destructive filesystem ops, force push to protected branches
# Passes through: everything else (user decides)
#
# Customize the APPROVE and DENY patterns below for your project.

set -euo pipefail

# Toggle off
[ "${CLAUDE_HOOKS_DISABLE_PERMISSION_AUTO:-}" = "1" ] && exit 0

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only handle Bash commands
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

[ -z "$COMMAND" ] && exit 0

# --- AUTO-APPROVE: Safe, read-only operations ---

# Read-only git operations
if echo "$COMMAND" | grep -Eq '^\s*git\s+(status|log|diff|branch|remote|show|blame|shortlog|describe|ls-files|rev-parse|rev-list)'; then
  echo '{"decision": "approve", "reason": "Read-only git operation"}'
  exit 0
fi

# Test runners (read-only, fail-fast)
if echo "$COMMAND" | grep -Eq '^\s*(npm\s+test|npx\s+(vitest|jest)|bun\s+test|pytest|cargo\s+test|go\s+test|make\s+test)'; then
  echo '{"decision": "approve", "reason": "Test execution"}'
  exit 0
fi

# Linters and formatters (read-only check mode)
if echo "$COMMAND" | grep -Eq '^\s*(npx\s+(biome|eslint|prettier)|bun\s+run\s+(lint|check|format)|ruff\s+check|mypy|tsc\s+--noEmit)'; then
  echo '{"decision": "approve", "reason": "Linter/formatter check"}'
  exit 0
fi

# gh CLI read operations
if echo "$COMMAND" | grep -Eq '^\s*gh\s+(pr\s+(view|checks|list|diff)|issue\s+(view|list)|run\s+(view|list))'; then
  echo '{"decision": "approve", "reason": "GitHub CLI read operation"}'
  exit 0
fi

# --- AUTO-DENY: Dangerous operations ---

# Destructive filesystem operations on root or home
# shellcheck disable=SC2016  # $HOME is a grep pattern, not shell expansion
if echo "$COMMAND" | grep -Eq 'rm\s+(-rf|-fr)\s+(/|~/|\$HOME)'; then
  echo '{"decision": "deny", "reason": "Destructive operation on root or home directory"}'
  exit 0
fi

# Force push to protected branches
if echo "$COMMAND" | grep -Eq 'git\s+push\s+.*--force.*\s(main|master)\b'; then
  echo '{"decision": "deny", "reason": "Force push to protected branch"}'
  exit 0
fi

# --- PASS THROUGH: Everything else requires user decision ---
exit 0
PREFIX_HOOK

PINNED="$WORK/pinned.sh"
if git -C "$HOOK_DIR" show "$PINNED_BASELINE_REF:./permission-auto-approve.sh" >"$PINNED" 2>/dev/null; then
    if cmp -s "$PINNED" "$BASELINE"; then
        pass
        echo "  baseline: git show ${PINNED_BASELINE_REF:0:8} (embedded copy is byte-identical)"
    else
        fail "embedded pre-fix hook matches git show $PINNED_BASELINE_REF" "the copies differ"
    fi
else
    echo "  baseline: embedded verbatim copy (${PINNED_BASELINE_REF:0:8} is not in this clone)"
fi

N_APPROVED=0
N_LOST=0
for ((i = 0; i < ${#CORPUS[@]}; i++)); do
    [ "${CORPUS_DECISION[i]}" = approve ] || continue
    N_APPROVED=$((N_APPROVED + 1))
    decide_with "$BASELINE" "${CORPUS[i]}"
    if [ "$DECISION" != approve ]; then
        N_LOST=$((N_LOST + 1))
        fail "subset differential: approved now, not by the pre-fix hook" \
            "pre-fix said $DECISION for: $(printf '%s' "${CORPUS[i]}" | tr '\n' '~')"
    fi
done
if [ "$N_APPROVED" -lt 30 ]; then
    fail "subset differential is not vacuous" "only $N_APPROVED of ${#CORPUS[@]} corpus commands approved"
elif [ "$N_LOST" -eq 0 ]; then
    pass
    echo "  subset differential: all $N_APPROVED approvals (of ${#CORPUS[@]} commands) were pre-fix approvals"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0

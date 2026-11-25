#!/usr/bin/env bash
# shellcheck disable=SC2016  # single-quoted literals are fixed-string patterns holding backticks, not expansions
# test-rebase-or-squash-gate.sh — semantic regression test for the "Rebase or
# squash" section of the git-merge-hazards skill (#3644).
#
# A summary that says "two or more independent conventional commits rebase"
# reads a PR with two commits sharing one type(scope) as rebase-eligible, but
# git-plugin/scripts/pr-merge-method.py classifies it single_concern and
# squashes it. The section must name that case, point at the decision's source,
# and fit SKILL.md inside the 10,000-character band test-no-force-stack.sh pins.
#
# The §2 auto-close audit bullets moved to references/stranded-child-audit.md
# to make room; the last block pins that they are still reachable and intact.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL_FILE="${SKILL_DIR}/SKILL.md"
METHOD_PY="${SKILL_DIR}/../../scripts/pr-merge-method.py"
STRATEGIES="${SKILL_DIR}/../github-pr-title/merge-strategies.md"
AUDIT_REF="${SKILL_DIR}/references/stranded-child-audit.md"

pass=0
fail=0
check() { # check <description> <yes|no actual>
    if [ "$2" = "yes" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $1" >&2
    fi
}

# has <text> <fixed-string>: yes when the text contains the string.
has() { if grep -qF -- "$2" <<<"$1"; then echo yes; else echo no; fi; }

# section <file> <heading>: the lines from "## <heading>" to the next "## ".
section() {
    awk -v h="## $2" '
        $0 == h { on = 1; print; next }
        on && /^## / { exit }
        on { print }
    ' "$1"
}

for f in "$SKILL_FILE" "$METHOD_PY" "$STRATEGIES"; do
    if [ ! -f "$f" ]; then
        echo "FAIL: missing $f" >&2
        exit 1
    fi
done

skill_text="$(<"$SKILL_FILE")"
sec="$(section "$SKILL_FILE" "Rebase or squash")"

check "SKILL.md has a '## Rebase or squash' section" "$( [ -n "$sec" ] && echo yes || echo no)"
check "section: two or more independent conventional commits rebase" \
    "$(has "$sec" 'Two or more independent conventional commits rebase')"
check "section: everything else squashes" "$(has "$sec" 'everything else squashes')"
for item in 'single commits' 'merge-synced branches' 'fixups' 'bot PRs'; do
    check "section: names '$item' among the squash cases" "$(has "$sec" "$item")"
done
check "section: one shared type(scope) counts as a single concern and squashes" \
    "$(has "$sec" 'Commits that all share one `type(scope)` count as a single concern and squash')"
check "section: names the single_concern rule" "$(has "$sec" 'single_concern')"
check "section: points at pr-merge-method.py" "$(has "$sec" 'pr-merge-method.py')"
check "section: links merge-strategies.md" \
    "$(has "$sec" '(../github-pr-title/merge-strategies.md)')"

# The clause must agree with its source, not just exist: the script still
# emits single_concern for one shared (type, scope), and the table still has
# that row. A rename there makes this section stale.
check "pr-merge-method.py still emits the single_concern rule" \
    "$(has "$(<"$METHOD_PY")" '"single_concern"')"
check "merge-strategies.md still squashes on one shared (type, scope)" \
    "$(has "$(<"$STRATEGIES")" 'Every commit has the same `(type, scope)`')"

# Control: the pre-#3644 summary sentence alone fails the single-concern pin.
control="Two or more independent conventional commits rebase; everything else squashes, including single commits, merge-synced branches, fixups and bot PRs."
check "control: the summary without the single_concern clause fails the pin" \
    "$( [ "$(has "$control" 'count as a single concern and squash')" = "no" ] && echo yes || echo no)"

chars="$(python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "$SKILL_FILE")"
check "SKILL.md is within the 10,000-character band (is ${chars})" \
    "$( [ "$chars" -le 10000 ] && echo yes || echo no)"

# The §2 audit bullets moved out of SKILL.md, not away.
check "SKILL.md links references/stranded-child-audit.md" \
    "$(has "$skill_text" '(references/stranded-child-audit.md)')"
if [ -f "$AUDIT_REF" ]; then
    audit_text="$(<"$AUDIT_REF")"
    check "audit reference names scripts/check-stranded-work.sh" \
        "$(has "$audit_text" 'scripts/check-stranded-work.sh')"
    check "audit reference keeps the base-ref 404 discriminator" \
        "$(has "$audit_text" '**404s** was auto-closed')"
    check "audit reference keeps the scheduled-sweep reasoning" \
        "$(has "$audit_text" 'A scheduled sweep is the only thing that finds this class')"
else
    check "references/stranded-child-audit.md exists" no
fi

echo "PASS=${pass} FAIL=${fail}"
[ "$fail" -eq 0 ]

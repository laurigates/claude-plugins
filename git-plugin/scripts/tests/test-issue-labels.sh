#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
# SC2015: `cond && ok … || notok …` is this repo's assertion idiom.
# SC2016: the single-quoted fixtures hold Markdown backticks, not expansions.
#
# Regression tests for git-plugin/scripts/issue-labels.py — the label taxonomy
# script behind the github-labels skill and the issue-labels reusable workflow.
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
#
# Fixtures (fixtures/issue-labels/):
#   issues.json       25 open issues of laurigates/mcu-tinkering-lab, fetched
#                     2026-11-10 with `gh issue list --state open --limit 300
#                     --json number,title,body,labels`. Titles, bodies and label
#                     names are verbatim, except #346's body (cut to 600
#                     characters). They cover the three title forms: "[Bug] x:",
#                     conventional "fix(x):", and neither.
#   repo-labels.json  that repo's labels from `gh label list --limit 500 --json
#                     name,color,description`, the same day (48 labels).
#   taxonomy.json     written for this suite; see its _comment.
#   gh                a stub. No test reaches GitHub: the first section fails the
#                     whole run unless that stub is the gh on PATH.
#
# What the suite must catch: a model-proposed label outside the allowlist being
# accepted, a needs label kept without a quote from the issue, a label added
# over one a person already set, a blocked label cleared while a blocker is
# still open or when no dependency link exists, a word in an issue body
# ("the docs") read as a repo path, and the #3587 gaps: a type word read as a
# scope, a scope hit on a missing label hiding the body paths, uncapped PR
# routing labels, an absent taxonomy reported as empty, a merge:/dependencies
# label renamed into build:/area:, an unmapped [Bench]/hw( keyword, a malformed
# unblock response losing the handled rows, and a trailing backslash on a path;
# a bare docs:/ci: title falling to its body (#3768), an unmapped [Task] keyword
# and feedback-session filing without a type label (#3783), and apply-audit or
# backfill writing what they should not, or a batch of unclassifiable issues
# holding the backfill queue (#3761).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="${SCRIPT_DIR}/../issue-labels.py"
FX="${SCRIPT_DIR}/fixtures/issue-labels"
SKILLS="${SCRIPT_DIR}/../../skills"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
notok() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }

# is <description> <got> <want>
is() { [ "$2" = "$3" ] && ok "$1" || notok "$1: wanted '$3', got '$2'"; }
# has / hasnt <description> <haystack> <fixed string>
has() { grep -qF -- "$3" <<<"$2" && ok "$1" || notok "$1: '$3' not in: $(tr '\n' ' ' <<<"$2" | cut -c1-300)"; }
hasnt() { grep -qF -- "$3" <<<"$2" && notok "$1: '$3' found" || ok "$1"; }

TMP=$(mktemp -d)
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
STUB="$TMP/stub"
LOG="$TMP/gh.log"
export GH_STUB_DIR="$STUB" GH_STUB_LOG="$LOG"
PATH="$FX:$PATH"
export PATH

stub_reset() {
    rm -rf "$STUB"
    mkdir -p "$STUB"
    : >"$LOG"
}
# writes: every non-GET call the stub logged.
writes() { grep -E -- '-X (POST|PATCH|DELETE|PUT)' "$LOG" || true; }

echo "=== the stub is the gh on PATH ==="
if [ "$(command -v gh)" = "$FX/gh" ] && [ -x "$FX/gh" ] &&
    [ "$(gh --stub-sentinel 2>/dev/null)" = "STUB_GH_ISSUE_LABELS" ]; then
    ok "gh resolves to the stub and it is executable"
else
    notok "gh is '$(command -v gh)', not the stub: refusing to run against the real gh"
    echo "PASSED=$PASS FAILED=$FAIL"
    exit 1
fi

# ── classify ──────────────────────────────────────────────────────────────────

# real <issue number> [flags...] — classify one fixture issue; prints form|labels.
real() {
    local n=$1
    shift
    python3 "$TOOL" classify --fixture "$FX/issues.json" --issue "$n" \
        --taxonomy "$FX/taxonomy.json" --repo-labels "$FX/repo-labels.json" "$@" |
        jq -r '"\(.title_form)|\(.add | join(","))"'
}
# expect <issue number> <form> <labels> <title, for the log>
expect() { is "#$1 $4 -> $2 [$3]" "$(real "$1" --ignore-existing)" "$2|$3"; }

# item <title> <body> [labels json] [files json] — a synthetic item in $TMP/item.json.
item() {
    jq -n --arg t "$1" --arg b "$2" --argjson l "${3:-[]}" --argjson f "${4:-null}" \
        '{number: 1, title: $t, body: $b, labels: $l}
         + (if $f then {is_pr: true, files: $f} else {} end)' >"$TMP/item.json"
}
# cls [flags...] — classify $TMP/item.json; prints the added labels, comma-joined.
cls() {
    python3 "$TOOL" classify --fixture "$TMP/item.json" --taxonomy "$FX/taxonomy.json" \
        --repo-labels "$FX/repo-labels.json" "$@" | jq -r '.add | join(",")'
}

echo "=== real titles: bracket form ==="
expect 1060 bracket "bug,area:cad" "[Bug] enclosure:"
expect 1055 bracket "bug,build:robocar" "[Bug] robocar-unified:"
expect 1051 bracket "enhancement,area:cad" "[Feature] mechanism:"
expect 969 bracket "enhancement,build:robocar" "[Enhancement] robocar carriers:"
expect 918 bracket "chore,core:ci" "[Chore] ci:"
expect 896 bracket "docs,area:sourcing" "[Docs] PRD-016:"
expect 1027 bracket "chore,build:robocar" "[Test] robocar-unified:"
# [Bench] maps to enhancement (#3587 gap 8); the scope still routes.
expect 1008 bracket "enhancement,build:robocar" "[Bench] robocar-unified:"

echo "=== real titles: conventional form ==="
expect 1064 conventional "bug,area:carrier-pcb" "fix(kicad):"
expect 1049 conventional "enhancement,area:labels" "feat(labels):"
expect 1036 conventional "chore,build:balancebot" "chore(balancebot):"
expect 825 conventional "chore,area:carrier-pcb" "test(kicad):"
# A type word is not a scope unless the taxonomy sets type_words_as_scope
# (#3587 gap 1): ci(balancebot) selects only the balancebot entry.
expect 1065 conventional "chore,build:balancebot" "ci(balancebot):"
# A bare type word with no parenthesised scope is the title's only scope, so it
# routes even with type_words_as_scope off (#3768): both were labelled core:docs
# / core:ci by hand, and before the fix fell to their bodies (build:robocar, and
# a three-way core:agent,core:ci,core:quality tie).
expect 704 conventional "docs,core:docs" "docs:"
expect 693 conventional "chore,core:ci" "ci:"
# hw maps to enhancement (#3587 gap 8); the parenthesised scope still routes.
expect 352 conventional "enhancement,build:lego-boost" "hw(lego-boost-xbox-fw):"

echo "=== real titles: neither form ==="
expect 747 scope "build:balancebot" "balancebot:"
expect 729 scope "area:schematics" "schematics:"
expect 710 scope "build:thinkpack" "thinkpack-brainbox:"
expect 268 scope "" "gamepad-synth: (scope the taxonomy does not know)"
expect 346 none "" "Dependency Dashboard"
# No scope match, so the body decides: #830 cites one balancebot path, #922
# cites two docs/decisions paths.
expect 830 none "build:balancebot" "Check a printout of perfboard-print.svg"
expect 922 scope "core:docs" "NotebookLM refresh:"

echo "=== a bracket followed by a conventional title ==="
item "[Bug] fix(robocar-unified): wheel stalls" ""
is "the parenthesised scope after a bracket still routes" "$(cls)" "bug,build:robocar"
item "[Chore] ci(balancebot): cache the toolchain" ""
is "the conventional type word there is not a scope by default" "$(cls)" "chore,build:balancebot"

echo "=== type words as title scopes: the type_words_as_scope switch (#3587 gap 1) ==="
jq '. + {type_words_as_scope: true}' "$FX/taxonomy.json" >"$TMP/tax-typewords.json"
item "docs(robocar-unified): document the wheel map" ""
is "docs(robocar-unified) derives no core:docs from the type word by default" "$(cls)" "docs,build:robocar"
is "control: type_words_as_scope true offers the type word as a scope" \
    "$(cls --taxonomy "$TMP/tax-typewords.json")" "docs,build:robocar,core:docs"
item "[Chore] ci(balancebot): cache the toolchain" ""
is "control: and after a bracket" "$(cls --taxonomy "$TMP/tax-typewords.json")" "chore,build:balancebot,core:ci"
is "#1065 with the switch on selects the ci entry too" \
    "$(real 1065 --ignore-existing --taxonomy "$TMP/tax-typewords.json")" "conventional|chore,build:balancebot,core:ci"
is "#704 with the switch on: docs: routes to core:docs, the body unread" \
    "$(real 704 --ignore-existing --taxonomy "$TMP/tax-typewords.json")" "conventional|docs,core:docs"
is "#693 with the switch on: ci: routes to core:ci" \
    "$(real 693 --ignore-existing --taxonomy "$TMP/tax-typewords.json")" "conventional|chore,core:ci"
item "chore(ci): bump the runner" ""
is "a type word inside the parentheses is the author's scope and still routes" "$(cls)" "chore,core:ci"
# After a bracket the word before the colon sits where the scope goes
# ("[Type] scope: ..."), so it stays a scope even when it is a type word.
item "[Chore] ci: bump the runner" ""
is "a bare word after a bracket is the scope, type word or not" "$(cls)" "chore,core:ci"
echo '{"type_words_as_scope": "yes"}' >"$TMP/tax-badswitch.json"
rc=0
out=$(python3 "$TOOL" classify --fixture "$TMP/item.json" --taxonomy "$TMP/tax-badswitch.json" \
    --repo-labels "$FX/repo-labels.json") || rc=$?
is "a non-boolean type_words_as_scope is a malformed taxonomy" "$rc|$(jq -r .status <<<"$out")" "1|ERROR"
has "and the reason names the key" "$(jq -r .reason <<<"$out")" "type_words_as_scope"

echo "=== a bracketed title prefix routes as a scope (#3737) ==="
# Issue forms that set "[GitHub Repo]: X" carry no scope after the bracket, and
# their bodies quote no paths, so only the bracket word can route them.
jq '. + {area: (.area + {"dns": {"color": "0e8a16", "scopes": ["dns"]},
                         "github-repo": {"color": "0e8a16", "scopes": ["github repo"]},
                         "triage": {"color": "0e8a16", "scopes": ["bug"]}})}' \
    "$FX/taxonomy.json" >"$TMP/tax-bracket.json"
jq '. + {type_words_as_scope: true}' "$TMP/tax-bracket.json" >"$TMP/tax-bracket-words.json"
jq '. + [{"name": "area:dns"}, {"name": "area:github-repo"}, {"name": "area:triage"}]' \
    "$FX/repo-labels.json" >"$TMP/labels-bracket.json"
brk() { cls --taxonomy "${1:-$TMP/tax-bracket.json}" --repo-labels "$TMP/labels-bracket.json"; }
item "[DNS]: add a record for the dashboard" ""
is "[DNS]: routes through a dns scope entry" "$(brk)" "area:dns"
item "[GitHub Repo]: create foo-service" ""
is "[GitHub Repo]: is normalised and routes through 'github repo'" "$(brk)" "area:github-repo"
item "[DNS] robocar-unified: point the OTA host" ""
is "the bracket word is offered beside the scope after it" "$(brk)" "build:robocar,area:dns"
item "[Bug]: lid does not close" ""
is "a type-word bracket is not a scope by default" "$(brk)" "bug"
is "control: type_words_as_scope offers it" "$(brk "$TMP/tax-bracket-words.json")" "bug,area:triage"

echo "=== bare type-word titles route by that word (#3768) ==="
item "ci: run the check" 'Touches `.claude/rules/a.md` and `.pre-commit-config.yaml`.'
is "bare ci: routes to core:ci and the body is not read" "$(cls)" "chore,core:ci"
item "docs: refresh the board notes" 'See `packages/robocar/a.c`.'
is "bare docs: routes to core:docs" "$(cls)" "docs,core:docs"
item "docs(robocar-unified): document the wheel map" ""
is "control: with a parenthesised scope the type word is still not a scope" "$(cls)" "docs,build:robocar"
item "docs: refresh the board notes" 'See `packages/robocar/a.c`.' '["core:ci"]'
is "a bare type word adds nothing over a routing label already set" "$(cls)" "docs"

echo "=== task and feedback title keywords (#3783) ==="
item "[Task] robocar-unified: map the wheels" ""
is "[Task] -> chore by default" "$(cls)" "chore,build:robocar"
item "task(balancebot): reflow the carrier" ""
is "task(...) -> chore by default" "$(cls)" "chore,build:balancebot"
# feedback-session adds the type label itself when it files (#3783 option 1),
# because a feedback(...) title can be a defect, an enhancement or a success
# report; one fixed type would be wrong for part of them.
item "feedback(git-plugin): merge-chain.sh cannot run in cloud sessions" ""
out=$(python3 "$TOOL" classify --fixture "$TMP/item.json" --taxonomy "$FX/taxonomy.json" --repo-labels "$FX/repo-labels.json")
is "feedback(...) derives no type label" \
    "$(jq -r '[.derived[] | select(.source | startswith("title:"))] | length' <<<"$out")" "0"
is "feedback(...) adds nothing from its title" "$(jq -r '.add | join(",")' <<<"$out")" ""

echo "=== bench and hw title keywords map to a type (#3587 gap 8) ==="
item "[Bench] robocar-unified: measure the mic" ""
is "[Bench] -> enhancement" "$(cls)" "enhancement,build:robocar"
item "hw(balancebot): reflow the carrier" ""
is "hw(...) -> enhancement" "$(cls)" "enhancement,build:balancebot"

echo "=== security is never derived from a title ==="
for title in "[Security] auth: token printed in logs" "security(auth): token printed in logs" "security: token printed in logs"; do
    item "$title" ""
    hasnt "no security from '$title'" "$(cls)" "security"
done
item "[Vuln] auth: token printed in logs" ""
MAP='bug=bug,fix;security=security,vuln'
hasnt "a --type-map entry for security is still not derived" "$(cls --type-map "$MAP")" "security"
# Control: the same map derives it once --never-derive is emptied, so the flag
# is what holds it back, not a missing label or a parse failure.
is "control: --never-derive '' lets that map through" "$(cls --type-map "$MAP" --never-derive '')" "security"

echo "=== body paths: only without a routing label, most-cited wins ==="
item "Boards fail the check" 'See `tools/kicad/boardcheck.py:12-40` and (tools/kicad/stamp.py). Follows `.claude/rules/testing.md`.'
is "two kicad paths beat one .claude path" "$(cls)" "area:carrier-pcb"
item "Two tools disagree" 'Compare `tools/kicad/a.py` with `tools/labels/b.py`.'
is "a tie keeps both labels" "$(cls)" "area:carrier-pcb,area:labels"
item "Linked only" "See https://example.com/tools/kicad/a.py for the file."
is "a URL is not a repo path" "$(cls)" ""
item "Boards fail the check" 'See `tools/kicad/a.py` and `tools/kicad/b.py`.' '["build:thinkpack"]'
is "an existing routing label switches the body fallback off" "$(cls)" ""
# A title scope whose label the repository lacks routes nothing, so it must not
# switch the body fallback off (#3587 gap 2).
jq '[.[] | select(.name != "area:cad")]' "$FX/repo-labels.json" >"$TMP/labels-no-cad.json"
item "[Bug] enclosure: lid does not close" 'See `tools/kicad/a.py` and `tools/kicad/b.py`.'
is "a scope hit on a label the repo lacks still reads the body" \
    "$(cls --repo-labels "$TMP/labels-no-cad.json")" "bug,area:carrier-pcb"
is "control: with the label in the repo the scope routes and the body is not read" "$(cls)" "bug,area:cad"
# #729's title scope selects area:schematics; its body also cites
# .claude/rules/schematic-layout.md, which must not add core:agent.
hasnt "#729: a path cited in passing adds nothing once the scope routed" "$(real 729 --ignore-existing)" "core:agent"

echo "=== pull requests: changed files, not body paths ==="
item "feat(labels): add a sheet" 'Mirrors `tools/kicad/x.py`.' '[]' \
    '["tools/labels/a.py", ".github/workflows/x.yml", "packages/robocar/unified/main/a.c", "packages/x/justfile", "justfile"]'
# Four routing labels match; the default cap is 3 (#3587 gap 3). The title's
# area:labels counts toward it, and of the one-file ties the first two stay.
is "labels from the title and the changed files, capped at 3 routing labels" "$(cls)" "enhancement,area:labels,core:ci,build:robocar"
hasnt "a path only the PR body mentions adds nothing" "$(cls)" "area:carrier-pcb"
jq '. + {max_routing_labels: 5}' "$FX/taxonomy.json" >"$TMP/tax-cap5.json"
is "max_routing_labels in the taxonomy raises the cap" "$(cls --taxonomy "$TMP/tax-cap5.json")" \
    "enhancement,area:labels,core:ci,build:robocar,core:build"
item "Update the boards" "" '[]' \
    '[".github/workflows/x.yml", "packages/robocar/a.c", "tools/kicad/a.py", "justfile", "tools/kicad/b.py", "packages/robocar/b.c", "tools/kicad/c.py", "tools/labels/a.py"]'
out=$(python3 "$TOOL" classify --fixture "$TMP/item.json" --taxonomy "$FX/taxonomy.json" --repo-labels "$FX/repo-labels.json")
is "the cap keeps the globs with the most matched files, in derived order" \
    "$(jq -r '.add | join(",")' <<<"$out")" "core:ci,build:robocar,area:carrier-pcb"
is "and reports what it dropped" "$(jq -r '[.capped[].label] | join(",")' <<<"$out")" "core:build,area:labels"
for bad in 0 '"3"' true; do
    printf '{"max_routing_labels": %s}' "$bad" >"$TMP/tax-badcap.json"
    rc=0
    out=$(python3 "$TOOL" classify --fixture "$TMP/item.json" --taxonomy "$TMP/tax-badcap.json" \
        --repo-labels "$FX/repo-labels.json") || rc=$?
    is "max_routing_labels $bad is a malformed taxonomy" "$rc|$(jq -r .status <<<"$out")" "1|ERROR"
done

echo "=== built-in core globs, and the taxonomy overriding them ==="
echo '{}' >"$TMP/empty.json"
core() { # core <file> [taxonomy] — labels a PR touching one file gets
    item "Update" "" '[]' "[\"$1\"]"
    python3 "$TOOL" classify --fixture "$TMP/item.json" --taxonomy "${2:-$TMP/empty.json}" \
        --repo-labels "$FX/repo-labels.json" | jq -r '.add | join(",")'
}
is ".github/** -> core:ci" "$(core .github/workflows/build.yml)" "core:ci"
is ".claude/** -> core:agent" "$(core .claude/rules/a.md)" "core:agent"
is ".mcp.json -> core:agent" "$(core .mcp.json)" "core:agent"
is "justfile -> core:build" "$(core justfile)" "core:build"
is "*.just at the root -> core:build" "$(core esp32.just)" "core:build"
is "a nested justfile is not core:build" "$(core packages/x/justfile)" ""
is ".pre-commit-config.yaml -> core:quality" "$(core .pre-commit-config.yaml)" "core:quality"
is "docs/** -> core:docs by default" "$(core docs/reference/boards/x.md)" "core:docs"
is "the taxonomy's core.docs paths replace the default" "$(core docs/reference/boards/x.md "$FX/taxonomy.json")" ""
is "the taxonomy's core.docs paths apply" "$(core docs/decisions/ADR-001.md "$FX/taxonomy.json")" "core:docs"
is "a core entry the taxonomy adds" "$(core packages/components/improv-wifi/a.c "$FX/taxonomy.json")" "area:connectivity,core:components"
is "an untouched default survives the override" "$(core .github/workflows/build.yml "$FX/taxonomy.json")" "core:ci"

echo "=== body paths: a word is not a path ==="
# With no taxonomy file only the built-in globs apply. A directory or file name
# used as a word matched them: `docs` in a sentence gave core:docs.
# bodycls <body> [taxonomy] — labels an unlabelled issue with no title scope takes from its body.
bodycls() {
    item "Sensor reads zero after reset" "$1"
    python3 "$TOOL" classify --fixture "$TMP/item.json" --taxonomy "${2:-$TMP/empty.json}" \
        --repo-labels "$FX/repo-labels.json" | jq -r '.add | join(",")'
}
is "the word docs in a sentence is not docs/**" "$(bodycls "According to the upstream docs the register clears on read.")" ""
is "nor at the end of a sentence, in backticks or in brackets" "$(bodycls 'See the docs. The `docs` moved; (docs) too.')" ""
is "the word justfile is not the root justfile" "$(bodycls "Add a justfile recipe for the sweep.")" ""
# Controls: the same globs match once the token is written as a path, so the
# cases above are empty because of the token's shape and nothing else.
is "control: docs/ with its slash is the directory" "$(bodycls 'Everything under `docs/` is stale.')" "core:docs"
is "control: a file under docs/" "$(bodycls "See docs/guide.md for the steps.")" "core:docs"
is "control: ./justfile is the root justfile" "$(bodycls 'The recipe is in `./justfile`.')" "core:build"
is "control: a dotted root file" "$(bodycls "Register the server in .mcp.json first.")" "core:agent"
is "control: a directory cited without a trailing slash" \
    "$(bodycls 'The fault is in `packages/robocar`.' "$FX/taxonomy.json")" "build:robocar"

echo "=== additive only ==="
# #1055 carries bug, build:robocar and area:ota by hand.
out=$(python3 "$TOOL" classify --fixture "$FX/issues.json" --issue 1055 \
    --taxonomy "$FX/taxonomy.json" --repo-labels "$FX/repo-labels.json")
is "#1055 as labelled: nothing to add" "$(jq -r '.add | length' <<<"$out")" "0"
is "#1055: both derived labels reported already_set" \
    "$(jq -r '[.skipped[] | "\(.label)=\(.reason)"] | join(",")' <<<"$out")" "bug=already_set,build:robocar=already_set"
item "[Bug] robocar-unified: wheel stalls" "" '["build:thinkpack"]'
out=$(python3 "$TOOL" classify --fixture "$TMP/item.json" --taxonomy "$FX/taxonomy.json" --repo-labels "$FX/repo-labels.json")
is "a build: label set by hand keeps the derived build: label out" "$(jq -r '.add | join(",")' <<<"$out")" "bug"
is "and it is reported as prefix_present" \
    "$(jq -r '.skipped[] | select(.label == "build:robocar") | .reason' <<<"$out")" "prefix_present"
item "[Bug] robocar-unified: wheel stalls" "" '["enhancement"]'
is "a type set by hand keeps the derived type out" "$(cls)" "build:robocar"
item "[Bug] robocar-unified: wheel stalls" "" '["needs:hardware", "blocked", "epic"]'
is "labels outside the type and routing groups block nothing" "$(cls)" "bug,build:robocar"
jq '[.[] | select(.name != "core:ci")]' "$FX/repo-labels.json" >"$TMP/labels-no-ci.json"
item "[Chore] ci: bump the runner" ""
out=$(python3 "$TOOL" classify --fixture "$TMP/item.json" --taxonomy "$FX/taxonomy.json" --repo-labels "$TMP/labels-no-ci.json")
is "a derived label the repo lacks is not added" "$(jq -r '.add | join(",")' <<<"$out")" "chore"
is "and it is reported as missing_in_repo" "$(jq -r '.skipped[0] | "\(.label)=\(.reason)"' <<<"$out")" "core:ci=missing_in_repo"

echo "=== the label vocabulary comes from flags ==="
jq '. + [{"name": "project:robocar"}, {"name": "defect"}]' "$FX/repo-labels.json" >"$TMP/labels-alt.json"
item "[Bug] robocar-unified: wheel stalls" ""
out=$(python3 "$TOOL" classify --fixture "$TMP/item.json" --taxonomy "$FX/taxonomy.json" \
    --repo-labels "$TMP/labels-alt.json" --build-prefix "project:" \
    --type-labels "defect,enhancement" --type-map "defect=bug" | jq -r '.add | join(",")')
is "--build-prefix, --type-labels and --type-map rename what is derived" "$out" "defect,project:robocar"
rc=0
out=$(python3 "$TOOL" classify --fixture "$TMP/item.json" --taxonomy "$FX/taxonomy.json" \
    --repo-labels "$FX/repo-labels.json" --build-prefix "") || rc=$?
is "an empty prefix is refused (it would match every label)" "$rc|$(jq -r .status <<<"$out")" "1|ERROR"

echo "=== classify through gh (stubbed) ==="
stub_reset
cp "$FX/repo-labels.json" "$STUB/labels.json"
jq '.[] | select(.number == 1064) | .labels = []' "$FX/issues.json" >"$STUB/issues-1064.json"
cp "$FX/taxonomy.json" "$STUB/contents-.github-issue-labels.json.json"
out=$(python3 "$TOOL" classify --repo o/r --issue 1064)
is "issue, labels and taxonomy read through gh" "$(jq -r '.add | join(",")' <<<"$out")" "bug,area:carrier-pcb"
has "the label listing asks for 500" "$(cat "$LOG")" "label list -R o/r --limit 500"
has "the taxonomy is read through the contents API" "$(cat "$LOG")" "api repos/o/r/contents/.github/issue-labels.json"
rm "$STUB/contents-.github-issue-labels.json.json"
out=$(python3 "$TOOL" classify --repo o/r --issue 1064)
is "no taxonomy in the repo: the type is still derived" "$(jq -r '.add | join(",")' <<<"$out")" "bug"
jq -n '{number: 7, title: "fix(kicad): close a gap", body: "", labels: []}' >"$STUB/issues-7.json"
# Two pages back to back, as `gh api --paginate` prints them.
printf '%s%s' '[{"filename": "tools/kicad/a.py"}]' '[{"filename": ".github/workflows/x.yml"}]' >"$STUB/pulls-7-files.json"
cp "$FX/taxonomy.json" "$STUB/contents-.github-issue-labels.json.json"
out=$(python3 "$TOOL" classify --repo o/r --pr 7)
is "a PR's changed files are read across pages" "$(jq -r '"\(.kind)|\(.add | join(","))"' <<<"$out")" "pr|bug,area:carrier-pcb,core:ci"
rc=0
out=$(python3 "$TOOL" classify --repo o/r --issue 999) || rc=$?
is "an unreadable issue is an ERROR, not an empty result" "$rc|$(jq -r .status <<<"$out")" "1|ERROR"
is "classify wrote nothing" "$(writes)" ""

# ── validate ──────────────────────────────────────────────────────────────────

# #1050 "[Feature] cadstd: print the calibration coupons …", with its labels
# removed so that only the gates under test can drop a proposal.
jq '.[] | select(.number == 1050) | .labels = []' "$FX/issues.json" >"$TMP/unlabelled.json"
# Every name the allowlist must reject exists in this label list, so existence
# cannot be what drops it.
jq '. + [{"name": "agent-ready"}]' "$FX/repo-labels.json" >"$TMP/labels-agent.json"
# val <labels file> [item] [flags...] — prints validate's JSON.
val() {
    local file=$1 it=${2:-$TMP/unlabelled.json}
    shift
    [ $# -gt 0 ] && shift
    python3 "$TOOL" validate --fixture "$it" --labels-file "$file" --repo-labels "$TMP/labels-agent.json" "$@"
}
reason() { jq -r --arg l "$2" '.dropped[] | select(.label == $l) | .reason' <<<"$1"; }

echo "=== validate: the allowlist ==="
cat >"$TMP/model.json" <<'JSON'
{"labels": ["agent-ready", "wontfix", "merge:squash", "blocked", "autorelease: pending",
            "epic", "dependencies", "enhancement", "area:cad", "core:quality", "build:robocar"]}
JSON
out=$(val "$TMP/model.json")
is "only type and build:/area:/core: names are kept" "$(jq -r '.add | join(",")' <<<"$out")" "enhancement,area:cad,core:quality,build:robocar"
for label in agent-ready wontfix merge:squash blocked "autorelease: pending" epic dependencies; do
    is "'$label' exists in the repo and is still dropped" "$(reason "$out" "$label")" "not_allowlisted"
done
echo '["security"]' >"$TMP/model.json"
is "security is a type label a model may propose" "$(val "$TMP/model.json" | jq -r '.add | join(",")')" "security"
# A blocked label that sits under an allowed prefix is still not a model's to set.
jq '. + [{"name": "needs:blocker"}]' "$FX/repo-labels.json" >"$TMP/labels-nb.json"
echo '{"labels": [{"name": "needs:blocker", "evidence": "replace the starting fit values with measured ones"}]}' >"$TMP/model.json"
is "--blocked-label under the needs: prefix is still refused" \
    "$(python3 "$TOOL" validate --fixture "$TMP/unlabelled.json" --labels-file "$TMP/model.json" \
        --repo-labels "$TMP/labels-nb.json" --blocked-label needs:blocker | jq -r '.dropped[0].reason')" "not_allowlisted"
echo '{"labels": ["area:nonexistent", {"name": "needs:human", "evidence": "replace the starting fit values with measured ones"}]}' >"$TMP/model.json"
out=$(val "$TMP/model.json")
is "allowlisted names the repo lacks are dropped" \
    "$(jq -r '[.dropped[] | "\(.label)=\(.reason)"] | join(",")' <<<"$out")" "area:nonexistent=missing_in_repo,needs:human=missing_in_repo"

echo "=== validate: a needs label needs a quote from the issue ==="
needs() { # needs <evidence json value> — the drop reason, or "kept"
    jq -n --argjson e "$1" '{labels: [{name: "needs:hardware", evidence: $e}]}' >"$TMP/model.json"
    val "$TMP/model.json" | jq -r 'if .add == ["needs:hardware"] then "kept" else .dropped[0].reason end'
}
is "a verbatim quote is kept" "$(needs '"Print the `tools/cadstd` calibration coupon on each process"')" "kept"
is "line breaks and runs of spaces in the quote do not matter" \
    "$(needs '"Print the `tools/cadstd`\n   calibration coupon   on each\tprocess"')" "kept"
is "a quote spanning the title is kept" "$(needs '"print the calibration coupons and record measured fits"')" "kept"
is "a paraphrase is dropped" "$(needs '"Print the cadstd calibration coupon on every process"')" "evidence_not_in_issue"
is "different capitalisation is not a quote" "$(needs '"PRINT THE `TOOLS/CADSTD` CALIBRATION COUPON"')" "evidence_not_in_issue"
is "no evidence is dropped" "$(needs '""')" "no_evidence"
is "a missing evidence field is dropped" "$(needs 'null')" "no_evidence"
is "a quote under 12 characters is dropped" "$(needs '"the coupon"')" "evidence_too_short"
echo '["needs:hardware"]' >"$TMP/model.json"
is "a bare needs name carries no evidence" "$(val "$TMP/model.json" | jq -r '.dropped[0].reason')" "no_evidence"

echo "=== validate: additive only, and malformed input ==="
jq '.[] | select(.number == 1050)' "$FX/issues.json" >"$TMP/labelled.json" # enhancement, area:cad, needs:hardware
echo '{"labels": ["bug", "area:ota", "core:ci", {"name": "needs:decision", "evidence": "replace the starting fit values with measured ones"}, "enhancement"]}' >"$TMP/model.json"
out=$(val "$TMP/model.json" "$TMP/labelled.json")
is "only a group with no label yet takes one" "$(jq -r '.add | join(",")' <<<"$out")" "core:ci"
is "a second type is refused" "$(reason "$out" bug)" "prefix_present"
is "a second area: label is refused" "$(reason "$out" area:ota)" "prefix_present"
is "a second needs: label is refused, quote or not" "$(reason "$out" needs:decision)" "prefix_present"
is "a label already on the issue is reported" "$(reason "$out" enhancement)" "already_set"
echo '{"labels": ["bug", "enhancement", "bug", "area:cad", "area:ota"]}' >"$TMP/model.json"
out=$(val "$TMP/model.json")
is "of two types in one file the first is kept; routing labels may be several" \
    "$(jq -r '.add | join(",")' <<<"$out")" "bug,area:cad,area:ota"
is "the second type is reported, a repeated name is not" \
    "$(jq -r '[.dropped[] | "\(.label)=\(.reason)"] | join(",")' <<<"$out")" "enhancement=second_type"
echo '{"labels": [42, {"evidence": "x"}, "bug"]}' >"$TMP/model.json"
out=$(val "$TMP/model.json")
is "malformed entries are dropped, the rest kept" "$(jq -r '"\(.add | join(","))|\([.dropped[].reason] | join(","))"' <<<"$out")" "bug|malformed,malformed"
for bad in '"just a string"' '{"labels": "bug"}' 'not json'; do
    printf '%s' "$bad" >"$TMP/model.json"
    rc=0
    out=$(val "$TMP/model.json") || rc=$?
    is "a labels file that is $bad is an ERROR with nothing accepted" "$rc|$(jq -r '"\(.status)|\(.add)"' <<<"$out")" "1|ERROR|null"
done

# ── provision ─────────────────────────────────────────────────────────────────

echo "=== provision: create, update, rename; never delete ==="
cat >"$TMP/tax.json" <<'JSON'
{"build": {"robocar": {"description": "Robot car", "color": "1d76db"},
           "lego": {"description": "LEGO", "color": "1d76db", "renamed_from": "project:lego"}},
 "area": {"ota": {"description": "OTA updates", "color": "0e8a16"},
          "cad": {"description": "Printed parts", "color": "0e8a16"},
          "new": {"description": "New area", "color": "5319e7"}},
 "core": {"components": {"paths": ["packages/components/**"]}}}
JSON
provision_labels() {
    cat >"$STUB/labels.json" <<'JSON'
[{"name": "build:robocar", "color": "1d76db", "description": "Robot car"},
 {"name": "project:lego", "color": "ffffff", "description": "old"},
 {"name": "area:ota", "color": "0e8a16", "description": "Over the air"},
 {"name": "area:cad", "color": "0E8A16", "description": "Printed parts"},
 {"name": "area:retired", "color": "0e8a16", "description": "no longer in the taxonomy"},
 {"name": "bug", "color": "d73a4a", "description": ""},
 {"name": "merge:squash", "color": "ededed", "description": ""},
 {"name": "Dependencies", "color": "0366d6", "description": ""},
 {"name": "robot", "color": "ffffff", "description": "unprefixed"},
 {"name": "wontfix", "color": "ffffff", "description": ""}]
JSON
}
stub_reset
provision_labels
out=$(python3 "$TOOL" provision --repo o/r --taxonomy "$TMP/tax.json")
rc=$?
is "provision exits 0" "$rc" "0"
for kv in CREATE=1 UPDATE=1 RENAME=1 UNCHANGED=2 APPLIED=3 STATUS=OK DRY_RUN=false; do
    grep -qx "$kv" <<<"$out" && ok "$kv" || notok "$kv not in: $(tr '\n' ' ' <<<"$out")"
done
has "labels are listed past the first page" "$(cat "$LOG")" "label list -R o/r --limit 500 --json name,color,description"
is "exactly the three writes, in taxonomy order" "$(writes)" \
    "api -X PATCH repos/o/r/labels/project%3Alego -f new_name=build:lego -f color=1d76db -f description=LEGO
api -X PATCH repos/o/r/labels/area%3Aota -f color=0e8a16 -f description=OTA updates
api -X POST repos/o/r/labels -f name=area:new -f color=5319e7 -f description=New area"
hasnt "nothing is deleted" "$(cat "$LOG")" "DELETE"
hasnt "a label that left the taxonomy is not touched" "$(cat "$LOG")" "area%3Aretired"
hasnt "core entries are not provisioned" "$(cat "$LOG")" "core"

stub_reset
provision_labels
out=$(python3 "$TOOL" provision --repo o/r --taxonomy "$TMP/tax.json" --dry-run)
is "--dry-run writes nothing" "$(writes)" ""
has "--dry-run still lists the actions" "$out" "OP=rename LABEL=build:lego FROM=project:lego"
has "--dry-run reports APPLIED=0" "$out" "APPLIED=0"

echo "=== provision: an entry with no description leaves the label's alone ==="
stub_reset
provision_labels
echo '{"area": {"ota": {"color": "0e8a16"}, "cad": {"color": "ffffff"}, "new": {"color": "5319e7"}}}' >"$TMP/nodesc.json"
out=$(python3 "$TOOL" provision --repo o/r --taxonomy "$TMP/nodesc.json")
is "the colour is written; no description is sent" "$(writes)" \
    "api -X PATCH repos/o/r/labels/area%3Acad -f color=ffffff
api -X POST repos/o/r/labels -f name=area:new -f color=5319e7"
has "a matching colour is unchanged whatever the label's description" "$out" "OP=unchanged LABEL=area:ota"

echo "=== provision: refusals stop before any write ==="
# refuse <description> <taxonomy json> <text the REASON must carry>
refuse() {
    stub_reset
    provision_labels
    printf '%s' "$2" >"$TMP/bad.json"
    local rc=0 out
    out=$(python3 "$TOOL" provision --repo o/r --taxonomy "$TMP/bad.json") || rc=$?
    if [ "$rc" -eq 1 ] && grep -qx 'STATUS=ERROR' <<<"$out" && grep -q "^REASON=.*$3" <<<"$out" && [ -z "$(writes)" ]; then
        ok "$1"
    else
        notok "$1: rc=$rc writes='$(writes)' out=$(tr '\n' ' ' <<<"$out" | cut -c1-300)"
    fi
}
refuse "a needs section" '{"needs": {"human": {"description": "x", "color": "d93f0b"}}}' "section 'needs'"
refuse "a top-level label list" '{"labels": {"blocked": {"color": "b60205"}}}' "section 'labels'"
refuse "a key that is not a label suffix" '{"build": {"Bad Key": {"color": "1d76db"}}}' "key must match"
refuse "a definition on a core entry" '{"core": {"ci": {"description": "x", "color": "5319e7"}}, "area": {"ota": {"color": "0e8a16"}}}' "not allowed here"
refuse "a colour written as a number" '{"area": {"new": {"color": 123456}}}' "six hex digits"
refuse "a missing colour" '{"area": {"new": {"description": "x"}}}' "color is required"
refuse "a misspelt field" '{"area": {"new": {"color": "0e8a16", "path": ["a/**"]}}}' "field 'path'"
refuse "renaming a type label away" '{"build": {"x": {"color": "1d76db", "renamed_from": "bug"}}}' "cannot be renamed"
refuse "two entries renaming one label" \
    '{"build": {"a": {"color": "1d76db", "renamed_from": "project:lego"}, "b": {"color": "1d76db", "renamed_from": "Project:Lego"}}}' \
    "already renamed by build.a"
# #3587 gap 7: a reserved family outside the type/core/needs/blocked set.
refuse "renaming merge:squash into a build: label" \
    '{"build": {"x": {"color": "1d76db", "renamed_from": "merge:squash"}}}' "cannot be renamed"
refuse "renaming dependencies into an area: label, any case" \
    '{"area": {"deps": {"color": "0e8a16", "renamed_from": "dependencies"}}}' "cannot be renamed"
# #3587 gap 5: an empty file and an absent one are reported apart.
refuse "an empty taxonomy" '{}' "taxonomy_empty"

stub_reset
provision_labels
rc=0
out=$(python3 "$TOOL" provision --repo o/r --dry-run) || rc=$?
is "a taxonomy absent from the repo is an ERROR" "$rc|$(grep -c '^STATUS=ERROR$' <<<"$out")" "1|1"
has "and says absent, not empty" "$out" "REASON=taxonomy_missing: .github/issue-labels.json is absent"
echo '{}' >"$STUB/contents-.github-issue-labels.json.json"
rc=0
out=$(python3 "$TOOL" provision --repo o/r --dry-run) || rc=$?
has "control: an empty taxonomy in the repo says empty" "$out" "REASON=taxonomy_empty: .github/issue-labels.json"

stub_reset
provision_labels
echo '{"build": {"robot": {"color": "1d76db", "renamed_from": "robot"}}}' >"$TMP/unprefixed.json"
out=$(python3 "$TOOL" provision --repo o/r --taxonomy "$TMP/unprefixed.json" --dry-run)
has "an unprefixed label may still be renamed into build:" "$out" "OP=rename LABEL=build:robot FROM=robot"

stub_reset
provision_labels
touch "$STUB/fail-writes"
rc=0
out=$(python3 "$TOOL" provision --repo o/r --taxonomy "$TMP/tax.json") || rc=$?
is "a failed write is an ERROR" "$rc|$(grep -c '^STATUS=ERROR$' <<<"$out")" "1|1"
has "and names the label" "$out" "REASON=write_failed: build:lego"
stub_reset
jq -n '[range(500) | {name: "label-\(.)", color: "000000", description: ""}]' >"$STUB/labels.json"
rc=0
out=$(python3 "$TOOL" provision --repo o/r --taxonomy "$TMP/tax.json") || rc=$?
is "a listing that fills the limit is refused as truncated" "$rc|$(grep -c 'REASON=label_list_truncated' <<<"$out")|$(writes)" "1|1|"

# ── unblock ───────────────────────────────────────────────────────────────────

# dep <number> <state> <repo> <labels json> — one issue as the dependency API lists it.
dep() {
    jq -cn --argjson n "$1" --arg s "$2" --arg r "$3" --argjson l "${4:-[]}" \
        '{number: $n, state: $s, repository_url: "https://api.github.com/repos/\($r)", labels: [$l[] | {name: .}]}'
}
unblock_scenario() { # unblock_scenario <state of #10> [blocked label]
    local label=${2:-blocked}
    stub_reset
    jq -n --arg s "$1" '{number: 10, state: $s}' >"$STUB/issues-10.json"
    # What #10 blocks, in two pages back to back.
    {
        printf '[%s,%s,%s]' "$(dep 11 open o/r "[\"$label\", \"bug\"]")" "$(dep 12 open o/r "[\"$label\"]")" "$(dep 13 closed o/r "[\"$label\"]")"
        printf '[%s,%s,%s]' "$(dep 14 open o/r '["bug"]')" "$(dep 15 open other/repo "[\"$label\"]")" "$(dep 16 open o/r "[\"$label\"]")"
    } >"$STUB/issues-10-dependencies-blocking.json"
    printf '[%s,%s]' "$(dep 10 closed o/r)" "$(dep 9 closed o/r)" >"$STUB/issues-11-dependencies-blocked_by.json"
    printf '[%s,%s]' "$(dep 10 closed o/r)" "$(dep 8 open o/r)" >"$STUB/issues-12-dependencies-blocked_by.json"
    echo '[]' >"$STUB/issues-16-dependencies-blocked_by.json" # labelled blocked, no link
}

echo "=== unblock: only when every blocker is closed ==="
unblock_scenario closed
out=$(python3 "$TOOL" unblock --repo o/r --issue 10)
is "one label removed: #11, whose blockers are all closed" "$(writes)" "api -X DELETE repos/o/r/issues/11/labels/blocked"
for row in "NUMBER=11 ACTION=unblock REASON=all_blockers_closed" \
    "NUMBER=12 ACTION=keep REASON=open_blocker:#8" \
    "NUMBER=13 ACTION=skip REASON=closed" \
    "NUMBER=14 ACTION=skip REASON=no_blocked_label" \
    "NUMBER=15 ACTION=skip REASON=other_repo" \
    "NUMBER=16 ACTION=skip REASON=no_link"; do
    has "$row" "$out" "$row"
done
has "both pages of dependents were read" "$out" "DEPENDENTS=6"
has "UNBLOCKED=1" "$out" "UNBLOCKED=1"
hasnt "#12, with an open blocker, keeps its label" "$(writes)" "issues/12/"
hasnt "#16, blocked with no link, keeps its label" "$(writes)" "issues/16/"
hasnt "another repo's issue is not read further" "$(cat "$LOG")" "issues/15/"

unblock_scenario closed
out=$(python3 "$TOOL" unblock --repo o/r --issue 10 --dry-run)
is "--dry-run removes nothing" "$(writes)" ""
has "--dry-run still reports the decision" "$out" "NUMBER=11 ACTION=unblock"

unblock_scenario open
out=$(python3 "$TOOL" unblock --repo o/r --issue 10)
is "an issue that is still open unblocks nothing" "$(writes)|$(grep -c '^DEPENDENTS=0$' <<<"$out")" "|1"
hasnt "and its dependents are not read" "$(cat "$LOG")" "dependencies"

unblock_scenario closed "on hold"
python3 "$TOOL" unblock --repo o/r --issue 10 --blocked-label "on hold" >/dev/null
is "--blocked-label names the label, URL-encoded" "$(writes)" "api -X DELETE repos/o/r/issues/11/labels/on%20hold"

stub_reset
rc=0
out=$(python3 "$TOOL" unblock --repo o/r --issue 10) || rc=$?
is "an unreadable issue is an ERROR" "$rc|$(grep -c '^STATUS=ERROR$' <<<"$out")|$(writes)" "1|1|"

echo "=== unblock: a blocker with no state keeps the label ==="
unblock_scenario closed
echo '[{"number": 9}]' >"$STUB/issues-11-dependencies-blocked_by.json"
out=$(python3 "$TOOL" unblock --repo o/r --issue 10)
is "a blocker that does not say closed is not read as closed" "$(writes)" ""
has "and is reported as open" "$out" "NUMBER=11 ACTION=keep REASON=open_blocker:#9"

echo "=== unblock: a failed call still reports what was removed ==="
unblock_scenario closed
rm "$STUB/issues-12-dependencies-blocked_by.json" # #12's blockers cannot be read
rc=0
out=$(python3 "$TOOL" unblock --repo o/r --issue 10) || rc=$?
is "a failed read after one removal exits 1" "$rc" "1"
for row in "NUMBER=11 ACTION=unblock REASON=all_blockers_closed" "NUMBER=12 ACTION=error REASON=gh_failed" \
    "UNBLOCKED=1" "STATUS=ERROR" "TYPE=dependent_failed NUMBER=12 "; do
    has "$row" "$out" "$row"
done
is "the removal made before the failure is the only write" "$(writes)" "api -X DELETE repos/o/r/issues/11/labels/blocked"
hasnt "the run stops at the failure" "$out" "NUMBER=13 "
unblock_scenario closed
touch "$STUB/fail-writes"
rc=0
out=$(python3 "$TOOL" unblock --repo o/r --issue 10) || rc=$?
is "a failed removal exits 1 and counts nothing as removed" \
    "$rc|$(grep -c '^UNBLOCKED=0$' <<<"$out")|$(grep -c '^STATUS=ERROR$' <<<"$out")" "1|1|1"
has "and names the issue" "$out" "TYPE=dependent_failed NUMBER=11 "

echo "=== unblock: a malformed response still reports what was removed (#3587 gap 9) ==="
unblock_scenario closed
printf '[{"number": 10, "state": "clo' >"$STUB/issues-12-dependencies-blocked_by.json"
rc=0
out=$(python3 "$TOOL" unblock --repo o/r --issue 10) || rc=$?
is "a malformed response after one removal exits 1" "$rc" "1"
for row in "NUMBER=11 ACTION=unblock REASON=all_blockers_closed" "NUMBER=12 ACTION=error REASON=malformed_response" \
    "UNBLOCKED=1" "STATUS=ERROR" "TYPE=dependent_failed NUMBER=12 "; do
    has "$row" "$out" "$row"
done
hasnt "the run stops at the malformed response" "$out" "NUMBER=13 "
is "the removal made before it is the only write" "$(writes)" "api -X DELETE repos/o/r/issues/11/labels/blocked"

echo "=== unblock: a label another run already removed ==="
# Two blockers of #11 close together, and each run's job sees every blocker
# closed. The first run removes the label; GitHub answers the second run's
# DELETE with 404. #10 blocks #11 and #12, both with every blocker closed.
race_scenario() { # race_scenario <DELETE stderr for #11> <#11's labels json, or "" for unreadable>
    stub_reset
    jq -n '{number: 10, state: "closed"}' >"$STUB/issues-10.json"
    printf '[%s,%s]' "$(dep 11 open o/r '["blocked", "bug"]')" "$(dep 12 open o/r '["blocked"]')" \
        >"$STUB/issues-10-dependencies-blocking.json"
    printf '[%s,%s]' "$(dep 10 closed o/r)" "$(dep 9 closed o/r)" >"$STUB/issues-11-dependencies-blocked_by.json"
    printf '[%s]' "$(dep 10 closed o/r)" >"$STUB/issues-12-dependencies-blocked_by.json"
    printf '%s\n' "$1" >"$STUB/fail-DELETE-issues-11-labels-blocked"
    [ -z "$2" ] || jq -n --argjson l "$2" '[$l[] | {name: .}]' >"$STUB/issues-11-labels.json"
}
race_scenario 'gh: Label does not exist (HTTP 404)' '["bug"]'
rc=0
out=$(python3 "$TOOL" unblock --repo o/r --issue 10) || rc=$?
is "a label already gone is not an error: exit 0" "$rc" "0"
for row in "NUMBER=11 ACTION=skip REASON=already_removed" \
    "NUMBER=12 ACTION=unblock REASON=all_blockers_closed" "UNBLOCKED=1" "STATUS=OK"; do
    has "$row" "$out" "$row"
done
hasnt "and no error row" "$out" "ACTION=error"
is "the next dependent is still processed" "$(writes)" \
    "api -X DELETE repos/o/r/issues/11/labels/blocked
api -X DELETE repos/o/r/issues/12/labels/blocked"
has "the label's absence is read back, not inferred from the error" "$(cat "$LOG")" "api --paginate repos/o/r/issues/11/labels"

# Controls: a failed DELETE with the label still on the issue, or whose
# labels cannot be read back, keeps the stop-and-report behaviour.
for case in 'gh: Server Error (HTTP 500)|["blocked", "bug"]|a 500 with the label still present' \
    'gh: Resource not accessible by integration (HTTP 403)|["blocked", "bug"]|a 403 with the label still present' \
    'gh: Label does not exist (HTTP 404)||a 404 whose labels cannot be read back'; do
    IFS='|' read -r err labels what <<<"$case"
    race_scenario "$err" "$labels"
    rc=0
    out=$(python3 "$TOOL" unblock --repo o/r --issue 10) || rc=$?
    is "$what: exits 1" "$rc|$(grep -c '^STATUS=ERROR$' <<<"$out")|$(grep -c '^UNBLOCKED=0$' <<<"$out")" "1|1|1"
    has "$what: reports #11 as the error" "$out" "NUMBER=11 ACTION=error REASON=gh_failed"
    has "$what: with the DELETE's own error" "$out" "REASON=dependent_failed: gh api -X DELETE failed: $err"
    hasnt "$what: stops before #12" "$out" "NUMBER=12 "
    hasnt "$what: and writes nothing to #12" "$(writes)" "issues/12/"
done

# ── audit ─────────────────────────────────────────────────────────────────────

# open_issue <number> <labels json> <created_at> <total_blocked_by | null> [pr]
open_issue() {
    jq -cn --argjson n "$1" --argjson l "$2" --arg c "$3" --argjson t "$4" --arg pr "${5:-}" \
        '{number: $n, title: "t", created_at: $c, labels: [$l[] | {name: .}]}
         + (if $t == null then {} else {issue_dependencies_summary: {total_blocked_by: $t}} end)
         + (if $pr == "" then {} else {pull_request: {}} end)'
}
labeled() { jq -cn --arg e "$1" --arg l "$2" --arg c "$3" '{event: $e, label: {name: $l}, created_at: $c}'; }
audit_scenario() {
    stub_reset
    local ok_labels='["bug", "build:x"]'
    {
        printf '[%s,' "$(open_issue 1 "$ok_labels" 2026-11-01T00:00:00Z 0)"
        printf '%s,' "$(open_issue 2 '["build:x"]' 2026-11-01T00:00:00Z 0)"            # no type
        printf '%s,' "$(open_issue 3 '["bug", "needs-triage"]' 2026-11-01T00:00:00Z 0)" # no routing
        printf '%s,' "$(open_issue 4 '["bug", "build:x", "blocked"]' 2026-11-01T00:00:00Z 0)"
        printf '%s,' "$(open_issue 5 '["bug", "build:x", "blocked"]' 2026-11-01T00:00:00Z 1)"
        printf '%s,' "$(open_issue 6 "$ok_labels" 2026-11-01T00:00:00Z 1)"
        printf '%s]' "$(open_issue 7 '["bug", "build:x", "blocked"]' 2026-11-01T00:00:00Z 1)"
        # second page
        printf '[%s,' "$(open_issue 8 '["bug", "area:y", "needs:hardware"]' 2026-06-01T00:00:00Z 0)"
        printf '%s,' "$(open_issue 9 '["bug", "area:y", "needs:decision"]' 2026-06-01T00:00:00Z 0)"
        printf '%s,' "$(open_issue 10 '["bug", "core:z", "needs:human"]' 2026-08-01T00:00:00Z 0)"
        printf '%s,' "$(open_issue 11 '["bug", "core:z", "needs:hardware"]' 2026-06-01T00:00:00Z 0)"
        printf '%s,' "$(open_issue 12 '[]' 2026-11-01T00:00:00Z 0 pr)" # a PR: not an issue
        printf '%s]' "$(open_issue 13 "$ok_labels" 2026-11-01T00:00:00Z null)"
    } >"$STUB/issues.json"
    echo '[]' >"$STUB/issues-4-dependencies-blocked_by.json"
    printf '[%s]' "$(dep 90 closed o/r)" >"$STUB/issues-5-dependencies-blocked_by.json"
    printf '[%s]' "$(dep 91 open o/r)" >"$STUB/issues-6-dependencies-blocked_by.json"
    printf '[%s,%s]' "$(dep 92 closed o/r)" "$(dep 93 open o/r)" >"$STUB/issues-7-dependencies-blocked_by.json"
    printf '[%s]' "$(dep 94 open other/repo)" >"$STUB/issues-13-dependencies-blocked_by.json"
    printf '[%s]' "$(labeled labeled needs:hardware 2026-09-01T00:00:00Z)" >"$STUB/issues-8-events.json"
    printf '[%s]' "$(labeled labeled needs:decision 2026-11-01T00:00:00Z)" >"$STUB/issues-9-events.json"
    # The label was renamed after it was applied: the event keeps the old name.
    printf '[%s]' "$(labeled labeled needs-human 2026-11-05T00:00:00Z)" >"$STUB/issues-10-events.json"
    printf '[%s,%s,%s]' "$(labeled labeled needs:hardware 2026-08-01T00:00:00Z)" \
        "$(labeled unlabeled needs:hardware 2026-09-01T00:00:00Z)" \
        "$(labeled labeled needs:hardware 2026-11-05T00:00:00Z)" >"$STUB/issues-11-events.json"
}
NOW=2026-11-10T00:00:00Z

echo "=== audit: findings ==="
audit_scenario
out=$(python3 "$TOOL" audit --repo o/r --now "$NOW")
rc=$?
is "findings exit 0 (STATUS=WARN carries them)" "$rc" "0"
for kv in OPEN_ISSUES=12 MISSING_TYPE=1 MISSING_ROUTING=1 BLOCKED_NO_LINK=1 BLOCKED_RESOLVED=1 \
    OPEN_LINK_NOT_BLOCKED=2 NEEDS_STALE=2 STATUS=WARN ISSUE_COUNT=8; do
    grep -qx "$kv" <<<"$out" && ok "$kv" || notok "$kv not in: $(grep -E '^[A-Z_]+=' <<<"$out" | tr '\n' ' ')"
done
for row in "TYPE=missing_type NUMBER=2 " "TYPE=missing_routing NUMBER=3 " "TYPE=blocked_no_link NUMBER=4 " \
    "TYPE=blocked_resolved NUMBER=5 " "TYPE=open_link_not_blocked NUMBER=6 " \
    "TYPE=open_link_not_blocked NUMBER=13 " "TYPE=needs_stale NUMBER=8 " "TYPE=needs_stale NUMBER=10 "; do
    has "row $row" "$out" "$row"
done
has "REASON names the first finding and counts the rest" "$out" "REASON=missing_type: #2 no type label"
has "REASON tail" "$out" "(+7 more)"
has "staleness is measured from the labeled event" "$out" "NUMBER=8 MSG=needs:hardware set 70 days ago (2026-09-01)"
has "a renamed label falls back to the issue's creation, and says so" "$out" "NUMBER=10 MSG=needs:human set 101 days ago (2026-08-01, from issue creation"
hasnt "a blocked issue with an open blocker is in order" "$out" "NUMBER=7 "
hasnt "a needs label applied 9 days ago is not stale" "$out" "NUMBER=9 "
hasnt "a needs label re-applied 5 days ago is not stale" "$out" "NUMBER=11 "
hasnt "a pull request in the listing is not audited" "$out" "NUMBER=12 "
is "audit wrote nothing" "$(writes)" ""
hasnt "issues with no link and no blocked label are not read one by one" "$(cat "$LOG")" "issues/1/dependencies"

audit_scenario
out=$(python3 "$TOOL" audit --repo o/r --now "$NOW" --needs-stale-days 100)
has "--needs-stale-days moves the threshold" "$out" "NEEDS_STALE=1"

audit_scenario
rc=0
out=$(python3 "$TOOL" audit --repo o/r --now "$NOW" --json --exit-code) || rc=$?
is "--exit-code: findings exit 2" "$rc" "2"
is "--json carries the same findings" "$(jq -r '"\(.status)|\(.open_issues)|\(.findings | length)|\(.counts.needs_stale)"' <<<"$out")" "WARN|12|8|2"

echo "=== audit: clean, and error ==="
stub_reset
printf '[%s]' "$(open_issue 1 '["bug", "build:x"]' 2026-11-01T00:00:00Z 0)" >"$STUB/issues.json"
rc=0
out=$(python3 "$TOOL" audit --repo o/r --now "$NOW" --exit-code) || rc=$?
is "no findings: exit 0 even with --exit-code" "$rc" "0"
for kv in STATUS=OK ISSUE_COUNT=0 OPEN_ISSUES=1; do
    grep -qx "$kv" <<<"$out" && ok "$kv" || notok "$kv not in: $(tr '\n' ' ' <<<"$out")"
done
hasnt "no REASON on OK" "$out" "REASON="
stub_reset
rc=0
out=$(python3 "$TOOL" audit --repo o/r --now "$NOW" --exit-code) || rc=$?
is "an unreadable issue list exits 1, not 0 or 2" "$rc" "1"
has "and is STATUS=ERROR, not a clean report" "$out" "STATUS=ERROR"
hasnt "with no OPEN_ISSUES=0 that could read as a clean repo" "$out" "OPEN_ISSUES="
rc=0
out=$(python3 "$TOOL" audit --repo o/r --now "$NOW" --json) || rc=$?
is "with --json the error is JSON too" "$rc|$(jq -r '"\(.status)|\(.findings)"' <<<"$out")" "1|ERROR|null"

# ── apply-audit ───────────────────────────────────────────────────────────────

echo "=== apply-audit: blocked follows the open dependency links (#3761) ==="
# audit_scenario: #5 is blocked with every blocker closed (blocked_resolved);
# #6 and #13 have an open blocker and no blocked label (open_link_not_blocked);
# #4 is blocked with no link, which stays a person's call.
audit_scenario
cp "$FX/repo-labels.json" "$STUB/labels.json"
rc=0
out=$(python3 "$TOOL" apply-audit --repo o/r) || rc=$?
is "apply-audit exits 0" "$rc" "0"
is "it removes blocked from #5 and adds it to #6 and #13, nothing else" "$(writes)" \
    "api -X DELETE repos/o/r/issues/5/labels/blocked
api -X POST repos/o/r/issues/6/labels -f labels[]=blocked
api -X POST repos/o/r/issues/13/labels -f labels[]=blocked"
for row in "NUMBER=5 ACTION=remove REASON=blocked_resolved" "NUMBER=6 ACTION=add REASON=open_link_not_blocked" \
    "NUMBER=13 ACTION=add REASON=open_link_not_blocked" "ADD=2" "REMOVE=1" "APPLIED=3" "STATUS=OK" "DRY_RUN=false"; do
    has "$row" "$out" "$row"
done
hasnt "a blocked label with no link is left alone" "$(writes)" "issues/4/"
hasnt "a blocked issue with an open blocker is left alone" "$(writes)" "issues/7/"
hasnt "needs: labels are not read: no events are fetched" "$(cat "$LOG")" "/events"

audit_scenario
cp "$FX/repo-labels.json" "$STUB/labels.json"
out=$(python3 "$TOOL" apply-audit --repo o/r --dry-run)
is "--dry-run writes nothing" "$(writes)" ""
has "--dry-run still lists the actions" "$out" "NUMBER=6 ACTION=add REASON=open_link_not_blocked"
has "--dry-run reports APPLIED=0" "$out" "APPLIED=0"

audit_scenario
cp "$FX/repo-labels.json" "$STUB/labels.json"
python3 "$TOOL" audit --repo o/r --now "$NOW" >/dev/null
is "control: audit itself stays read-only" "$(writes)" ""

echo "=== apply-audit: refusals and failures ==="
audit_scenario
jq '[.[] | select(.name != "blocked")]' "$FX/repo-labels.json" >"$STUB/labels.json"
out=$(python3 "$TOOL" apply-audit --repo o/r)
hasnt "a blocked label the repo lacks is not added (the API would create it)" "$(writes)" "POST"
has "and the add is reported as skipped" "$out" "NUMBER=6 ACTION=skip REASON=missing_in_repo"

audit_scenario
cp "$FX/repo-labels.json" "$STUB/labels.json"
printf '%s\n' 'gh: Label does not exist (HTTP 404)' >"$STUB/fail-DELETE-issues-5-labels-blocked"
echo '[{"name": "bug"}, {"name": "build:x"}]' >"$STUB/issues-5-labels.json"
rc=0
out=$(python3 "$TOOL" apply-audit --repo o/r) || rc=$?
is "a label another run already removed is not an error" "$rc" "0"
has "and is reported as already_removed" "$out" "NUMBER=5 ACTION=skip REASON=already_removed"
has "the adds after it still run" "$(writes)" "api -X POST repos/o/r/issues/13/labels -f labels[]=blocked"

audit_scenario
cp "$FX/repo-labels.json" "$STUB/labels.json"
touch "$STUB/fail-writes"
rc=0
out=$(python3 "$TOOL" apply-audit --repo o/r) || rc=$?
is "a failed write exits 1 with STATUS=ERROR and APPLIED=0" \
    "$rc|$(grep -c '^STATUS=ERROR$' <<<"$out")|$(grep -c '^APPLIED=0$' <<<"$out")" "1|1|1"
has "and names the issue" "$out" "TYPE=write_failed NUMBER=5 "
hasnt "the run stops at the failure" "$out" "NUMBER=6 "

stub_reset
rc=0
out=$(python3 "$TOOL" apply-audit --repo o/r) || rc=$?
is "an unreadable issue list is an ERROR and writes nothing" "$rc|$(grep -c '^STATUS=ERROR$' <<<"$out")|$(writes)" "1|1|"

# ── backfill ──────────────────────────────────────────────────────────────────

echo "=== backfill: unlabelled issues, oldest first; unclassifiable ones do not hold the queue (#3761) ==="
# bf_issue <number> <title> <labels json> <created_at> [pr]
bf_issue() {
    jq -cn --argjson n "$1" --arg t "$2" --argjson l "$3" --arg c "$4" --arg pr "${5:-}" \
        '{number: $n, title: $t, body: "", created_at: $c, labels: [$l[] | {name: .}]}
         + (if $pr == "" then {} else {pull_request: {}} end)'
}
backfill_scenario() {
    stub_reset
    cp "$FX/repo-labels.json" "$STUB/labels.json"
    {
        printf '[%s,' "$(bf_issue 21 '[Bug] robocar-unified: wheel stalls' '[]' 2026-03-01T00:00:00Z)"
        printf '%s,' "$(bf_issue 22 'Dependency Dashboard' '[]' 2026-01-01T00:00:00Z)"
        printf '%s,' "$(bf_issue 23 'fix(kicad): close the gaps' '["bug"]' 2026-02-01T00:00:00Z)"
        printf '%s]' "$(bf_issue 24 'fix(kicad): labelled' '["bug", "area:cad"]' 2025-11-01T00:00:00Z)"
        printf '[%s,' "$(bf_issue 25 'fix(kicad): a pull request' '[]' 2025-10-01T00:00:00Z pr)"
        printf '%s,' "$(bf_issue 26 'chore(balancebot): bump' '[]' 2026-04-01T00:00:00Z)"
        printf '%s]' "$(bf_issue 27 'Notes from the call' '[]' 2025-12-01T00:00:00Z)"
    } >"$STUB/issues.json"
}
backfill_scenario
rc=0
out=$(python3 "$TOOL" backfill --repo o/r --taxonomy "$FX/taxonomy.json" --max-issues 2) || rc=$?
is "backfill exits 0" "$rc" "0"
for kv in OPEN_ISSUES=6 UNLABELLED=5 MAX_ISSUES=2 CANDIDATES=2 UNCLASSIFIABLE=2 REMAINING=1 STATUS=OK; do
    grep -qx "$kv" <<<"$out" && ok "$kv" || notok "$kv not in: $(grep -E '^[A-Z_]+=' <<<"$out" | tr '\n' ' ')"
done
is "candidates are the oldest classifiable ones, past two older unclassifiable issues" \
    "$(grep -E '^  - NUMBER=' <<<"$(sed -n '/^CANDIDATES_DETAIL:/,/^UNCLASSIFIABLE_DETAIL:/p' <<<"$out")")" \
    "  - NUMBER=23 MISSING=routing ADD=area:carrier-pcb
  - NUMBER=21 MISSING=type,routing ADD=bug,build:robocar"
is "the unclassifiable issues are listed once, apart, oldest first" \
    "$(grep -E '^  - NUMBER=' <<<"$(sed -n '/^UNCLASSIFIABLE_DETAIL:/,/^STATUS=/p' <<<"$out")")" \
    "  - NUMBER=27 MISSING=type,routing
  - NUMBER=22 MISSING=type,routing"
hasnt "a fully labelled issue is not listed" "$out" "NUMBER=24 "
hasnt "a pull request is not listed" "$out" "NUMBER=25 "
hasnt "the run stops once max-issues candidates are found" "$out" "NUMBER=26 "
is "backfill writes nothing" "$(writes)" ""
hasnt "it classifies from the listing, with no read per issue" "$(cat "$LOG")" "issues/2"

backfill_scenario
out=$(python3 "$TOOL" backfill --repo o/r --taxonomy "$FX/taxonomy.json" --json)
is "--json, default max-issues: every candidate in age order" \
    "$(jq -r '"\(.status)|\(.max_issues)|\([.candidates[].number] | join(","))|\([.unclassifiable[].number] | join(","))|\(.remaining)"' <<<"$out")" \
    "OK|25|23,21,26|27,22|0"
is "--json carries the labels to add" "$(jq -r '.candidates[0].add | join(",")' <<<"$out")" "area:carrier-pcb"

stub_reset
rc=0
out=$(python3 "$TOOL" backfill --repo o/r --taxonomy "$FX/taxonomy.json" --json) || rc=$?
is "an unreadable issue list is an ERROR, not an empty list" "$rc|$(jq -r '"\(.status)|\(.candidates)"' <<<"$out")" "1|ERROR|null"

# ── pure functions ────────────────────────────────────────────────────────────

echo "=== path candidates and globs ==="
out=$(python3 - "$TOOL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("il", sys.argv[1])
m = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = m  # before exec_module (#3805)
spec.loader.exec_module(m)
body = (
    "See `main/ota.c:245-247`, [the doc](docs/a/b.md) and tools/x.py.\n"
    "Not https://example.com/tools/y.py, #12 or @org/team. Again: `tools/x.py`.\n"
    "The docs, a justfile and `Makefile` are words; docs/ and ./justfile and .mcp.json are paths."
)
print(m.path_candidates(body))
print(m.path_candidates("The fault is in packages/robocar\\ and tools/x.py\\."))
cases = [
    ("docs/**", "docs/a/b.md"), ("docs/**", "docs"), ("docs/**", "docsx/a"),
    ("*.just", "a.just"), ("*.just", "tools/a.just"), ("**/*.just", "tools/a.just"),
    ("packages/*/main/**", "packages/x/main/a.c"), ("packages/*/main/**", "packages/x/y/main/a.c"),
    ("a/**/c.md", "a/c.md"), ("a/**/c.md", "a/b/b/c.md"), ("a/?.md", "a/b.md"), ("a/?.md", "a/bb.md"),
]
print("".join("y" if m.path_matches(p, g) else "n" for g, p in cases))
cfg = m.config_from(m.build_parser().parse_args(["audit"]))
stateless = [{"number": 3}]
print(m.blockers_verdict(stateless))
blocked = {"number": 1, "labels": ["bug", "build:x", "blocked"]}
print([f["type"] for f in m.audit_issue(blocked, stateless, {}, 0.0, 30, cfg)])
PY
)
is "paths keep their order, lose line suffixes and duplicates; URLs, mentions and words are skipped" \
    "$(sed -n 1p <<<"$out")" "['main/ota.c', 'docs/a/b.md', 'tools/x.py', 'docs/', 'justfile', '.mcp.json']"
is "a trailing backslash is not part of a path (#3587 gap 10)" "$(sed -n 2p <<<"$out")" "['packages/robocar', 'tools/x.py']"
is "glob semantics: * stays in a segment, ** crosses, /** takes the directory" "$(sed -n 3p <<<"$out")" "yynynyynyyyn"
is "a blocker with no state counts as open" "$(sed -n 4p <<<"$out")" "('keep', 'open_blocker:#3')"
is "so audit does not report its blocked issue as resolved" "$(sed -n 5p <<<"$out")" "[]"

# ── the skills that document this script ──────────────────────────────────────

echo "=== skills name the taxonomy, not a stock vocabulary ==="
labels_skill=$(cat "$SKILLS/github-labels/SKILL.md")
writing_skill=$(cat "$SKILLS/github-issue-writing/SKILL.md")
for needle in ".github/issue-labels.json" "gh label list --limit 500" "issue-labels.py" \
    "build:" "area:" "core:" "needs:hardware" "needs:decision" "needs:human" "blocked" \
    "provision" "classify" "validate" "unblock" "audit" "apply-audit" "backfill"; do
    has "github-labels names $needle" "$labels_skill" "$needle"
done
for needle in ".github/issue-labels.json" "gh label list --limit 500"; do
    has "github-issue-writing names $needle" "$writing_skill" "$needle"
done
has "github-labels says which body tokens are paths" "$labels_skill" 'A body token is a path only when it has a'
hasnt "github-labels dropped the priority: vocabulary" "$labels_skill" "priority:"
# The old body listed with --limit 50, under the label count of a large repo.
grep -Eq -- '--limit [0-9]{1,2}([^0-9]|$)' <<<"$labels_skill$writing_skill" &&
    notok "a label listing under 100 is back in a skill" || ok "no skill lists labels with a limit under 100"
grep -F 'gh label list -' <<<"$labels_skill$writing_skill" | grep -vqF -- '--limit 500' &&
    notok "a 'gh label list' command without --limit 500 is in a skill" || ok "every 'gh label list' command in the two skills passes --limit 500"
hasnt "github-issue-writing dropped the priority: example" "$writing_skill" "priority:"

echo "=== feedback-session sets the type label classify will not derive (#3783) ==="
# classify derives no type from a feedback(<plugin>): title, so the filer is the
# only source of one; this pins the half of #3783 that lives in feedback-plugin.
feedback_format=$(cat "$SCRIPT_DIR/../../../feedback-plugin/skills/feedback-session/references/issue-format.md")
has "feedback-session names the type label as required" "$feedback_format" 'Every issue carries the type label of its `## Category`'
for pair in 'Bug → `bug`' 'Enhancement → `enhancement`' 'Positive feedback → `positive-feedback`'; do
    has "feedback-session maps $pair" "$feedback_format" "$pair"
done
skip_block=$(sed -n '/when `$SKIP_SESSION_LABELS=true`/,/^$/p' <<<"$feedback_format")
has "the skip-session-labels case still sets bug" "$skip_block" '- Bugs: `bug`'
has "and enhancement" "$skip_block" '- Enhancements: `enhancement`'
has "and positive-feedback where the repo has it" "$skip_block" '- Positive: `positive-feedback` when the repo already has it'

echo "PASSED=$PASS FAILED=$FAIL"
[ "$FAIL" -eq 0 ]

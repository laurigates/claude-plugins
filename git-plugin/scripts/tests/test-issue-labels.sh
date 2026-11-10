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
# still open or when no dependency link exists, and a word in an issue body
# ("the docs") read as a repo path.
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
# [Bench] is not a type keyword: the scope still routes, no type is guessed.
expect 1008 bracket "build:robocar" "[Bench] robocar-unified:"

echo "=== real titles: conventional form ==="
expect 1064 conventional "bug,area:carrier-pcb" "fix(kicad):"
expect 1049 conventional "enhancement,area:labels" "feat(labels):"
expect 1036 conventional "chore,build:balancebot" "chore(balancebot):"
expect 825 conventional "chore,area:carrier-pcb" "test(kicad):"
# The type word is a scope too: ci(balancebot) selects the ci entry as well.
expect 1065 conventional "chore,build:balancebot,core:ci" "ci(balancebot):"
expect 704 conventional "docs,core:docs" "docs:"
expect 693 conventional "chore,core:ci" "ci:"
# hw is not a type keyword; the parenthesised scope still routes.
expect 352 conventional "build:lego-boost" "hw(lego-boost-xbox-fw):"

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
is "and the conventional word is a scope there too" "$(cls)" "chore,build:balancebot,core:ci"

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
# #729's title scope selects area:schematics; its body also cites
# .claude/rules/schematic-layout.md, which must not add core:agent.
hasnt "#729: a path cited in passing adds nothing once the scope routed" "$(real 729 --ignore-existing)" "core:agent"

echo "=== pull requests: changed files, not body paths ==="
item "feat(labels): add a sheet" 'Mirrors `tools/kicad/x.py`.' '[]' \
    '["tools/labels/a.py", ".github/workflows/x.yml", "packages/robocar/unified/main/a.c", "packages/x/justfile", "justfile"]'
is "labels from the title and the changed files" "$(cls)" "enhancement,area:labels,core:ci,build:robocar,core:build"
hasnt "a path only the PR body mentions adds nothing" "$(cls)" "area:carrier-pcb"

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
refuse "an empty taxonomy" '{}' "taxonomy_missing"

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

# ── pure functions ────────────────────────────────────────────────────────────

echo "=== path candidates and globs ==="
out=$(python3 - "$TOOL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("il", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
body = (
    "See `main/ota.c:245-247`, [the doc](docs/a/b.md) and tools/x.py.\n"
    "Not https://example.com/tools/y.py, #12 or @org/team. Again: `tools/x.py`.\n"
    "The docs, a justfile and `Makefile` are words; docs/ and ./justfile and .mcp.json are paths."
)
print(m.path_candidates(body))
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
is "glob semantics: * stays in a segment, ** crosses, /** takes the directory" "$(sed -n 2p <<<"$out")" "yynynyynyyyn"
is "a blocker with no state counts as open" "$(sed -n 3p <<<"$out")" "('keep', 'open_blocker:#3')"
is "so audit does not report its blocked issue as resolved" "$(sed -n 4p <<<"$out")" "[]"

# ── the skills that document this script ──────────────────────────────────────

echo "=== skills name the taxonomy, not a stock vocabulary ==="
labels_skill=$(cat "$SKILLS/github-labels/SKILL.md")
writing_skill=$(cat "$SKILLS/github-issue-writing/SKILL.md")
for needle in ".github/issue-labels.json" "gh label list --limit 500" "issue-labels.py" \
    "build:" "area:" "core:" "needs:hardware" "needs:decision" "needs:human" "blocked" \
    "provision" "classify" "validate" "unblock" "audit"; do
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

echo "PASSED=$PASS FAILED=$FAIL"
[ "$FAIL" -eq 0 ]

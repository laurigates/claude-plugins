#!/usr/bin/env bash
# shellcheck disable=SC2015   # file-level: `cond && ok … || notok …` is the
# deliberate assertion idiom (ok/notok both exit 0) — see test-check-schema.sh.
# Regression tests for blueprint-autorun.sh (ADR-0020 level-1 runner).
#
# Pins the semantic contract:
#   - no manifest / disabled env / jq path are silent no-ops (exit 0)
#   - level 0 never executes (due deterministic tasks report STATE=due)
#   - level 1 executes a due deterministic task (sync-ids sweep), registers
#     documents in id_registry, and writes back last_completed_at/stats
#   - --report never writes back
#   - agent-judgment due tasks are surfaced in DUE_AGENT_TASKS, never executed
#   - enabled:false always wins over auto_run:true
#   - on-change/on-demand schedules are never runner-due
#   - a run killed mid-sweep (SIGTERM) leaves no manifest work copy (#3169)
#   - the batched sweep builds the same id_registry as the per-document
#     registration did, with a jq call count independent of doc count (#3169)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTORUN="${SCRIPT_DIR}/../blueprint-autorun.sh"

pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

assert_contains() {
    # assert_contains <label> <needle> <haystack>
    if printf '%s' "$3" | grep -qF -- "$2"; then
        ok "$1"
    else
        notok "$1 (missing: $2)"
    fi
}

assert_not_contains() {
    if printf '%s' "$3" | grep -qF -- "$2"; then
        notok "$1 (unexpected: $2)"
    else
        ok "$1"
    fi
}

make_sandbox() {
    local sb
    sb=$(mktemp -d)
    if [ -z "$sb" ] || [ ! -d "$sb" ]; then
        echo "FATAL: mktemp failed" >&2
        exit 1
    fi
    printf '%s' "$sb"
}

write_manifest() {
    # write_manifest <dir> <autonomy_level> <sync_auto> <sync_schedule> <sync_last> <sync_enabled>
    local dir="$1" lvl="$2" sync_auto="$3" sync_sched="$4" sync_last="$5" sync_enabled="${6:-true}"
    mkdir -p "$dir/docs/blueprint"
    local last_json="null"
    [ "$sync_last" != "null" ] && last_json="\"$sync_last\""
    cat > "$dir/docs/blueprint/manifest.json" <<EOF
{
  "format_version": "3.4.0",
  "automation": {
    "autonomy_level": $lvl,
    "interaction_mode": "normal",
    "work_orders": { "auto_draft": false, "auto_execute": false }
  },
  "task_registry": {
    "sync-ids": {
      "enabled": $sync_enabled,
      "auto_run": $sync_auto,
      "last_completed_at": $last_json,
      "last_result": null,
      "schedule": "$sync_sched",
      "stats": {}
    },
    "adr-validate": {
      "enabled": true,
      "auto_run": true,
      "last_completed_at": null,
      "last_result": null,
      "schedule": "weekly",
      "stats": {}
    },
    "curate-docs": {
      "enabled": true,
      "auto_run": true,
      "last_completed_at": null,
      "last_result": null,
      "schedule": "on-demand",
      "stats": {}
    },
    "claude-md": {
      "enabled": true,
      "auto_run": true,
      "last_completed_at": null,
      "last_result": null,
      "schedule": "on-change",
      "stats": {}
    }
  }
}
EOF
}

write_doc() {
    # write_doc <dir> <relpath> <id>
    local dir="$1" rel="$2" doc_id="$3"
    mkdir -p "$dir/$(dirname "$rel")"
    cat > "$dir/$rel" <<EOF
---
id: $doc_id
status: Accepted
created: 2026-07-01
---

# Fixture doc $doc_id
EOF
}

# ---- Test A: no manifest -> silent no-op ----
sb=$(make_sandbox)
out=$(bash "$AUTORUN" --project-dir "$sb")
rc=$?
[ "$rc" -eq 0 ] && ok "A: exit 0 without manifest" || notok "A: exit $rc without manifest"
assert_contains "A: reports no_manifest" "AUTORUN=no_manifest" "$out"
rm -rf "$sb"

# ---- Test B: level 0 never executes ----
sb=$(make_sandbox)
write_manifest "$sb" 0 true daily null
write_doc "$sb" "docs/adrs/0001-test.md" "ADR-0001"
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "B: level 0 reports due, does not run" "TASK=sync-ids KIND=deterministic SCHEDULE=daily STATE=due" "$out"
last=$(jq -r '.task_registry["sync-ids"].last_completed_at' "$sb/docs/blueprint/manifest.json")
[ "$last" = "null" ] && ok "B: no writeback at level 0" || notok "B: writeback happened at level 0 ($last)"
rm -rf "$sb"

# ---- Test C: level 1 executes due sync-ids sweep + writeback ----
sb=$(make_sandbox)
write_manifest "$sb" 1 true daily null
write_doc "$sb" "docs/adrs/0001-test.md" "ADR-0001"
write_doc "$sb" "docs/prds/0002-feature.md" "PRD-0002"
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "C: sync-ids ran" "TASK=sync-ids KIND=deterministic SCHEDULE=daily STATE=ran DOCS=2" "$out"
assert_contains "C: ran count" "RAN_COUNT=1" "$out"
reg_path=$(jq -r '.id_registry.documents["ADR-0001"].path' "$sb/docs/blueprint/manifest.json")
[ "$reg_path" = "docs/adrs/0001-test.md" ] && ok "C: ADR registered with relative path" || notok "C: ADR registration ($reg_path)"
last_prd=$(jq -r '.id_registry.last_prd' "$sb/docs/blueprint/manifest.json")
[ "$last_prd" = "2" ] && ok "C: last_prd counter updated" || notok "C: last_prd counter ($last_prd)"
last=$(jq -r '.task_registry["sync-ids"].last_completed_at' "$sb/docs/blueprint/manifest.json")
[ "$last" != "null" ] && ok "C: last_completed_at written" || notok "C: last_completed_at not written"
runs=$(jq -r '.task_registry["sync-ids"].stats.runs' "$sb/docs/blueprint/manifest.json")
[ "$runs" = "1" ] && ok "C: stats.runs incremented" || notok "C: stats.runs ($runs)"

# ---- Test D: fresh last_completed_at -> not due ----
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "D: fresh task not due" "TASK=sync-ids SCHEDULE=daily STATE=not_due" "$out"
rm -rf "$sb"

# ---- Test E: --report never writes back ----
sb=$(make_sandbox)
write_manifest "$sb" 1 true daily null
write_doc "$sb" "docs/adrs/0001-test.md" "ADR-0001"
out=$(bash "$AUTORUN" --project-dir "$sb" --report)
assert_contains "E: report mode reports due" "TASK=sync-ids KIND=deterministic SCHEDULE=daily STATE=due" "$out"
last=$(jq -r '.task_registry["sync-ids"].last_completed_at' "$sb/docs/blueprint/manifest.json")
[ "$last" = "null" ] && ok "E: report mode no writeback" || notok "E: report mode wrote back"
if jq -e '.id_registry' "$sb/docs/blueprint/manifest.json" >/dev/null 2>&1; then
    notok "E: report mode initialized id_registry"
else
    ok "E: report mode left manifest untouched"
fi
rm -rf "$sb"

# ---- Test F: agent-judgment tasks surfaced, never executed ----
sb=$(make_sandbox)
write_manifest "$sb" 1 false daily null
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "F: adr-validate due as agent task" "TASK=adr-validate KIND=agent SCHEDULE=weekly STATE=due REMEDIATION=/blueprint:adr-validate" "$out"
assert_contains "F: DUE_AGENT_TASKS lists adr-validate" "DUE_AGENT_TASKS=adr-validate" "$out"
adr_last=$(jq -r '.task_registry["adr-validate"].last_completed_at' "$sb/docs/blueprint/manifest.json")
[ "$adr_last" = "null" ] && ok "F: agent task not marked completed" || notok "F: agent task falsely completed"
rm -rf "$sb"

# ---- Test G: enabled:false always wins; on-change/on-demand never due ----
sb=$(make_sandbox)
write_manifest "$sb" 1 true daily null false
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "G: disabled task skipped" "TASK=sync-ids STATE=skipped REASON=disabled" "$out"
assert_contains "G: on-demand never due" "TASK=curate-docs SCHEDULE=on-demand STATE=on_demand" "$out"
assert_contains "G: on-change is event-driven" "TASK=claude-md SCHEDULE=on-change STATE=event_driven" "$out"
assert_not_contains "G: curate-docs not in due list" "curate-docs" "$(printf '%s' "$out" | grep '^DUE_AGENT_TASKS=')"
rm -rf "$sb"

# ---- Test H: BLUEPRINT_AUTORUN_DISABLE=1 is a no-op ----
sb=$(make_sandbox)
write_manifest "$sb" 1 true daily null
out=$(BLUEPRINT_AUTORUN_DISABLE=1 bash "$AUTORUN" --project-dir "$sb")
assert_contains "H: env opt-out" "AUTORUN=disabled_by_env" "$out"
last=$(jq -r '.task_registry["sync-ids"].last_completed_at' "$sb/docs/blueprint/manifest.json")
[ "$last" = "null" ] && ok "H: opt-out mutates nothing" || notok "H: opt-out wrote back"
rm -rf "$sb"

# ---- Test I: on-change deterministic task reconciles; no-op leaves bytes ----
# The on-change signal (PostToolUse) misses Bash edits outside the change list
# and every edit made outside Claude Code, so sync-ids also reconciles at each
# run. It must not rewrite an unchanged manifest: jq re-serialises the whole
# file, which would dirty a hand-formatted manifest on every session start.
sb=$(make_sandbox)
write_manifest "$sb" 1 true on-change null
write_doc "$sb" "docs/adrs/0001-test.md" "ADR-0001"
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "I: on-change sync-ids reconciles and reports a change" \
    "TASK=sync-ids KIND=deterministic SCHEDULE=on-change STATE=ran DOCS=1 CHANGED=true" "$out"
reg=$(jq -r '.id_registry.documents["ADR-0001"].path // "NONE"' "$sb/docs/blueprint/manifest.json")
[ "$reg" = "docs/adrs/0001-test.md" ] && ok "I: missed ADR registered" || notok "I: missed ADR not registered (got $reg)"
last=$(jq -r '.task_registry["sync-ids"].last_completed_at' "$sb/docs/blueprint/manifest.json")
[ "$last" != "null" ] && ok "I: a reconcile that changed the registry records its run" || notok "I: changed reconcile did not record"

# Hand-format the manifest (4-space indent — any layout jq would not produce).
python3 -c '
import json, sys
p = sys.argv[1]
d = json.load(open(p))
open(p, "w").write(json.dumps(d, indent=4) + "\n")
' "$sb/docs/blueprint/manifest.json"
before=$(cat "$sb/docs/blueprint/manifest.json")
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "I: second run finds nothing to change" "STATE=ran DOCS=1 CHANGED=false" "$out"
[ "$(cat "$sb/docs/blueprint/manifest.json")" = "$before" ] \
    && ok "I: an unchanged reconcile leaves the manifest byte-identical" \
    || notok "I: an unchanged reconcile rewrote the manifest"
leftover=$(find "$sb/docs/blueprint" -name 'manifest.json.autorun.*' | wc -l | tr -d ' ')
[ "$leftover" = "0" ] && ok "I: no work copy left behind" || notok "I: $leftover work copies left behind"
rm -rf "$sb"

# ---- Test J: reconcile respects level 0 and --report ----
sb=$(make_sandbox)
write_manifest "$sb" 0 true on-change null
write_doc "$sb" "docs/adrs/0001-test.md" "ADR-0001"
before=$(cat "$sb/docs/blueprint/manifest.json")
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "J: level 0 reports the reconcile without running it" \
    "TASK=sync-ids KIND=deterministic SCHEDULE=on-change STATE=reconcile" "$out"
[ "$(cat "$sb/docs/blueprint/manifest.json")" = "$before" ] && ok "J: level 0 mutates nothing" || notok "J: level 0 wrote back"
write_manifest "$sb" 1 true on-change null
before=$(cat "$sb/docs/blueprint/manifest.json")
out=$(bash "$AUTORUN" --project-dir "$sb" --report)
assert_contains "J: report mode reports the reconcile" "STATE=reconcile" "$out"
[ "$(cat "$sb/docs/blueprint/manifest.json")" = "$before" ] && ok "J: report mode mutates nothing" || notok "J: report mode wrote back"
rm -rf "$sb"

# ---- Test K: a killed sweep leaves no work copy behind (#3169) ----
# The SessionStart probe runs the autorun under a 5 s hook timeout; on a big
# repo the sweep outlives it and the harness kills the run. The work copy
# (manifest.json.autorun.<pid>) must not survive the kill.
#
# Deterministic: a PATH-stubbed jq parks inside the batched registration call
# (the only jq call carrying `--arg pfx`) until a release file appears, so
# the run is provably mid-sweep when the signal lands — no timing sleeps.
real_jq=$(command -v jq)
stub_dir=$(make_sandbox)
cat > "$stub_dir/jq" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
    if [ "$a" = "pfx" ]; then
        : > "$STUB_MARK"
        i=0
        while [ ! -f "$STUB_RELEASE" ] && [ "$i" -lt 200 ]; do
            sleep 0.1
            i=$((i + 1))
        done
        break
    fi
done
exec "$REAL_JQ" "$@"
EOF
chmod +x "$stub_dir/jq"

wait_for_file() {
    # wait_for_file <path> — bounded poll (10 s); returns 1 on timeout
    local i=0
    while [ ! -e "$1" ] && [ "$i" -lt 100 ]; do
        sleep 0.1
        i=$((i + 1))
    done
    [ -e "$1" ]
}

wait_for_group_exit() {
    # wait_for_group_exit <pgid> — bounded poll (10 s) until no process in the group remains
    local i=0
    while kill -0 -- "-$1" 2>/dev/null && [ "$i" -lt 100 ]; do
        sleep 0.1
        i=$((i + 1))
    done
}

run_killed_sweep() {
    # run_killed_sweep <label> <kill-target: group|parent>
    local label="$1" target="$2" sb pid before leftover
    sb=$(make_sandbox)
    write_manifest "$sb" 1 true daily null
    write_doc "$sb" "docs/adrs/0001-test.md" "ADR-0001"
    before=$(cat "$sb/docs/blueprint/manifest.json")
    # set -m gives the background run its own process group (pgid == pid), so
    # a group kill reaches the run, its sweep subshell, and the stub — the
    # shape of a harness tearing down a timed-out hook.
    set -m
    PATH="$stub_dir:$PATH" REAL_JQ="$real_jq" \
        STUB_MARK="$sb/mark" STUB_RELEASE="$sb/release" \
        bash "$AUTORUN" --project-dir "$sb" >/dev/null 2>&1 &
    pid=$!
    set +m
    if ! wait_for_file "$sb/mark"; then
        notok "K($label): sweep never reached the registration jq call"
        : > "$sb/release"
        wait "$pid" 2>/dev/null
        rm -rf "$sb"
        return
    fi
    leftover=$(find "$sb/docs/blueprint" -name 'manifest.json.autorun.*' | wc -l | tr -d ' ')
    [ "$leftover" != "0" ] && ok "K($label): work copy exists mid-sweep (test reaches the window)" \
        || notok "K($label): no work copy mid-sweep — test no longer exercises the window"
    if [ "$target" = "group" ]; then
        kill -TERM -- "-$pid" 2>/dev/null
    else
        kill -TERM "$pid" 2>/dev/null
        # The orphaned sweep runs on; let it finish.
        : > "$sb/release"
    fi
    wait "$pid" 2>/dev/null
    wait_for_group_exit "$pid"
    : > "$sb/release"
    leftover=$(find "$sb/docs/blueprint" -name 'manifest.json.autorun.*' | wc -l | tr -d ' ')
    [ "$leftover" = "0" ] && ok "K($label): no work copy left behind after SIGTERM" \
        || notok "K($label): $leftover work copies left behind after SIGTERM"
    "$real_jq" -e . "$sb/docs/blueprint/manifest.json" >/dev/null 2>&1 \
        && ok "K($label): live manifest is still valid JSON" \
        || notok "K($label): live manifest is not valid JSON"
    if [ "$target" = "group" ]; then
        [ "$(cat "$sb/docs/blueprint/manifest.json")" = "$before" ] \
            && ok "K($label): killed sweep left the live manifest unchanged" \
            || notok "K($label): killed sweep modified the live manifest"
    fi
    rm -rf "$sb"
}

run_killed_sweep group group
run_killed_sweep parent parent
rm -rf "$stub_dir"

# ---- Test L: batched sweep builds the per-document id_registry (#3169) ----
# The sweep reads every document's frontmatter in one awk pass and registers
# them in one jq call. Pin the registry it must produce, field for field, on
# a fixture covering each per-document rule the old loop applied: first
# `key:` line wins, `title:` falls back to the first `# ` heading, then
# "untitled"; missing status -> "unknown"; missing created -> run time; no id
# or no frontmatter -> skipped; an existing entry keeps created/relates_to/
# github_issues; last_prd/last_prp take the max numeric suffix.
sb=$(make_sandbox)
write_manifest "$sb" 1 true daily null
mf="$sb/docs/blueprint/manifest.json"
"$real_jq" '. + {id_registry: {last_prd: 4, last_prp: 0, github_issues: {"7": "PRD-0003"},
    documents: {"PRD-0003": {created: "2020-01-01", relates_to: ["ADR-0001"], github_issues: [7],
                             path: "old/path.md", status: "Draft", title: "Old title"}}}}' \
    "$mf" > "$mf.new" && mv "$mf.new" "$mf"
mkdir -p "$sb/docs/prds" "$sb/docs/adrs" "$sb/docs/prps" "$sb/docs/blueprint/work-orders"
printf -- '---\nid: PRD-0003\nstatus: Accepted\ntitle: Search\ncreated: 2026-01-02\n---\n\n# Heading ignored\n' > "$sb/docs/prds/0003-search.md"
printf -- '---\nid: PRD-0010\nstatus: Draft\ncreated: 2026-02-03\n---\n\n# Ten from heading\n' > "$sb/docs/prds/0010 spaced name.md"
printf -- '---\nid:    PRP-0007\ntitle: Tab\there "quoted" \\back\nstatus: Ready\r\ncreated: 2026-03-04\n---\n' > "$sb/docs/prps/0007-prp.md"
printf -- '---\nid: PRP-0002\ncreated: 2026-03-05\n---\nno heading here\n' > "$sb/docs/prps/0002-prp.md"
printf -- '---\nid: ADR-0001\nid: ADR-9999\nstatus: Accepted\n---\n# First heading\n# Second heading\n' > "$sb/docs/adrs/0001-adr.md"
printf -- '---\nid: WO-001\nstatus: open\ntitle:\n---\n# WO heading\n' > "$sb/docs/blueprint/work-orders/001-wo.md"
printf -- '---\nstatus: Accepted\ntitle: No id\n---\n' > "$sb/docs/adrs/0002-noid.md"
printf -- '# No frontmatter\nid: ADR-0003\n' > "$sb/docs/adrs/0003-nofm.md"
# An index README with no frontmatter whose fenced format example opens with
# `---`: the fence is body text, not frontmatter. Before the fix the sweep
# took the first two `---` lines anywhere in the file and registered the
# template as a junk ADR-NNNN entry (the write-time hook already required
# frontmatter to open the file).
# shellcheck disable=SC2016  # the backticks are a literal markdown fence
printf -- '# ADR index\n\nTemplate:\n\n```markdown\n---\nid: ADR-NNNN\ntitle: "ADR-NNNN: Title"\nstatus: Proposed        # Draft | Proposed\ncreated: YYYY-MM-DD\n---\n```\n' > "$sb/docs/adrs/README.md"
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "L: sweep registered the six id-bearing docs" "STATE=ran DOCS=6 CHANGED=true" "$out"
expected='{
  "github_issues": {"7": "PRD-0003"},
  "last_prd": 10,
  "last_prp": 7,
  "documents": {
    "PRD-0003": {"created": "2020-01-01", "relates_to": ["ADR-0001"], "github_issues": [7],
                 "path": "docs/prds/0003-search.md", "status": "Accepted", "title": "Search"},
    "PRD-0010": {"created": "2026-02-03", "relates_to": [], "github_issues": [],
                 "path": "docs/prds/0010 spaced name.md", "status": "Draft", "title": "Ten from heading"},
    "PRP-0007": {"created": "2026-03-04", "relates_to": [], "github_issues": [],
                 "path": "docs/prps/0007-prp.md", "status": "Ready", "title": "Tab\there \"quoted\" \\back"},
    "PRP-0002": {"created": "2026-03-05", "relates_to": [], "github_issues": [],
                 "path": "docs/prps/0002-prp.md", "status": "unknown", "title": "untitled"},
    "ADR-0001": {"created": "RUNTIME", "relates_to": [], "github_issues": [],
                 "path": "docs/adrs/0001-adr.md", "status": "Accepted", "title": "First heading"},
    "WO-001": {"created": "RUNTIME", "relates_to": [], "github_issues": [],
               "path": "docs/blueprint/work-orders/001-wo.md", "status": "open", "title": "WO heading"}
  }
}'
actual=$("$real_jq" -S '.id_registry
    | .documents |= with_entries(if (.value.created | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")) then .value.created = "RUNTIME" else . end)' "$mf")
if [ "$actual" = "$(printf '%s' "$expected" | "$real_jq" -S .)" ]; then
    ok "L: id_registry matches the per-document registration semantics"
else
    notok "L: id_registry differs: $(diff <(printf '%s' "$expected" | "$real_jq" -S .) <(printf '%s\n' "$actual") | head -20)"
fi
rm -rf "$sb"

# ---- Test M: jq calls do not grow with the number of documents (#3169) ----
# 88 docs at several forks each took 6.3 s, past the probe's 5 s hook budget.
# Count jq invocations for a 2-doc and a 40-doc tree; they must be equal.
count_dir=$(make_sandbox)
cat > "$count_dir/jq" <<'EOF'
#!/usr/bin/env bash
echo x >> "$JQ_COUNT_LOG"
exec "$REAL_JQ" "$@"
EOF
chmod +x "$count_dir/jq"
jq_calls_for() {
    # jq_calls_for <doc_count> — prints the jq invocation count of one run
    local n="$1" sb i
    sb=$(make_sandbox)
    write_manifest "$sb" 1 true daily null
    i=1
    while [ "$i" -le "$n" ]; do
        write_doc "$sb" "docs/adrs/$(printf '%04d' "$i")-doc.md" "ADR-$(printf '%04d' "$i")"
        i=$((i + 1))
    done
    : > "$sb/count.log"
    PATH="$count_dir:$PATH" REAL_JQ="$real_jq" JQ_COUNT_LOG="$sb/count.log" \
        bash "$AUTORUN" --project-dir "$sb" >/dev/null 2>&1
    wc -l < "$sb/count.log" | tr -d ' '
    rm -rf "$sb"
}
calls_small=$(jq_calls_for 2)
calls_large=$(jq_calls_for 40)
[ "$calls_small" = "$calls_large" ] && [ "$calls_small" -gt 0 ] \
    && ok "M: jq calls independent of doc count ($calls_small for 2 and 40 docs)" \
    || notok "M: jq calls grow with doc count (2 docs: $calls_small, 40 docs: $calls_large)"
rm -rf "$count_dir"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0

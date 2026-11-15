#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016   # file-level: `cond && ok … || notok …` is the
# deliberate assertion idiom (ok/notok both exit 0) — see test-check-schema.sh;
# single-quoted `$t`/backticks are literal fixture text, not expansions.
# Regression tests for blueprint-autorun.sh (ADR-0020 level-1 runner).
#
# Pins the semantic contract:
#   - no manifest / disabled env / jq path are silent no-ops (exit 0)
#   - level 0 never executes (deterministic tasks report STATE=reconcile)
#   - level 1 executes a deterministic task (sync-ids sweep) on every run,
#     registers documents in id_registry, and writes no task_registry run
#     state (#3548): a no-change run, a registry-changing run and a failed run
#     leave everything but id_registry byte-identical
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
    sb=$(mktemp -d) || { echo 'FATAL: mktemp failed' >&2; exit 1; }
    [ -n "$sb" ] && [ -d "$sb" ] || { echo 'FATAL: bad sandbox dir' >&2; exit 1; }
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
assert_contains "B: level 0 reports the reconcile, does not run" "TASK=sync-ids KIND=deterministic SCHEDULE=daily STATE=reconcile" "$out"
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
tr_after=$(jq -S '.task_registry' "$sb/docs/blueprint/manifest.json")
tr_fresh=$(sb2=$(make_sandbox); write_manifest "$sb2" 1 true daily null; jq -S '.task_registry' "$sb2/docs/blueprint/manifest.json"; rm -rf "$sb2")
[ "$tr_after" = "$tr_fresh" ] && ok "C: no task_registry run state written (#3548)" || notok "C: task_registry changed by the run"

# ---- Test D: a second run reconciles again and changes nothing ----
before=$(cat "$sb/docs/blueprint/manifest.json")
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "D: daily deterministic task reconciles every run" "TASK=sync-ids KIND=deterministic SCHEDULE=daily STATE=ran DOCS=2 CHANGED=false" "$out"
[ "$(cat "$sb/docs/blueprint/manifest.json")" = "$before" ] && ok "D: no-change run leaves the manifest byte-identical" || notok "D: no-change run rewrote the manifest"
rm -rf "$sb"

# ---- Test E: --report never writes back ----
sb=$(make_sandbox)
write_manifest "$sb" 1 true daily null
write_doc "$sb" "docs/adrs/0001-test.md" "ADR-0001"
out=$(bash "$AUTORUN" --project-dir "$sb" --report)
assert_contains "E: report mode reports the reconcile" "TASK=sync-ids KIND=deterministic SCHEDULE=daily STATE=reconcile" "$out"
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
[ "$last" = "null" ] && ok "I: a reconcile that changed the registry records no run state (#3548)" || notok "I: changed reconcile wrote last_completed_at ($last)"

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
leftover=$(find "$sb/docs/blueprint" -name 'manifest.json.reconcile.*' -o -name 'manifest.json.lock.d' | wc -l | tr -d ' ')
[ "$leftover" = "0" ] && ok "I: no lock or temp file left behind" || notok "I: $leftover lock/temp files left behind"
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
# repo the sweep outlives it and the harness kills the run. The engine's lock
# (manifest.json.lock.d) and temp files must not survive the kill (#3550).
#
# Deterministic: a PATH-stubbed jq parks inside the engine's compute call
# (the only jq call carrying `--arg reconcile_compute`) until a release file appears, so
# the run is provably mid-sweep when the signal lands — no timing sleeps.
real_jq=$(command -v jq)
stub_dir=$(make_sandbox)
cat > "$stub_dir/jq" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
    if [ "$a" = "reconcile_compute" ]; then
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
    [ -d "$sb/docs/blueprint/manifest.json.lock.d" ] && ok "K($label): lock held mid-sweep (test reaches the window)" \
        || notok "K($label): no lock mid-sweep — test no longer exercises the window"
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
    leftover=$(find "$sb/docs/blueprint" -name 'manifest.json.reconcile.*' -o -name 'manifest.json.lock.d' | wc -l | tr -d ' ')
    [ "$leftover" = "0" ] && ok "K($label): no lock or temp file left behind after SIGTERM" \
        || notok "K($label): $leftover lock/temp files left behind after SIGTERM"
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
# "untitled"; missing status -> "unknown"; no id or no frontmatter -> skipped;
# last_prd/last_prp take the max numeric suffix. Since the engine (#3550):
# missing created -> omitted, never the clock; an existing entry keeps its
# created when frontmatter has none; relates_to/github_issues are derived
# from frontmatter, and the reverse index is rebuilt from the entries.
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
  "github_issues": {},
  "last_prd": 10,
  "last_prp": 7,
  "documents": {
    "PRD-0003": {"created": "2026-01-02", "relates_to": [], "github_issues": [],
                 "path": "docs/prds/0003-search.md", "status": "Accepted", "title": "Search"},
    "PRD-0010": {"created": "2026-02-03", "relates_to": [], "github_issues": [],
                 "path": "docs/prds/0010 spaced name.md", "status": "Draft", "title": "Ten from heading"},
    "PRP-0007": {"created": "2026-03-04", "relates_to": [], "github_issues": [],
                 "path": "docs/prps/0007-prp.md", "status": "Ready", "title": "Tab\there \"quoted\" \\back"},
    "PRP-0002": {"created": "2026-03-05", "relates_to": [], "github_issues": [],
                 "path": "docs/prps/0002-prp.md", "status": "unknown", "title": "untitled"},
    "ADR-0001": {"relates_to": [], "github_issues": [],
                 "path": "docs/adrs/0001-adr.md", "status": "Accepted", "title": "First heading"},
    "WO-001": {"relates_to": [], "github_issues": [],
               "path": "docs/blueprint/work-orders/001-wo.md", "status": "open", "title": "WO heading"}
  }
}'
actual=$("$real_jq" -S '.id_registry' "$mf")
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

# ---- Test O: deterministic tasks keep no run state (#3548) ----
# record_task_result ran on a due run even when nothing changed, so a fresh
# clone with a weekly sync-ids went dirty (last_completed_at, stats.runs).
mf_of() { printf '%s/docs/blueprint/manifest.json' "$1"; }
sb=$(make_sandbox)
write_manifest "$sb" 1 true weekly "2020-01-01T00:00:00Z"
write_doc "$sb" "docs/adrs/0001-test.md" "ADR-0001"
bash "$AUTORUN" --project-dir "$sb" >/dev/null
cp "$(mf_of "$sb")" "$sb/before.json"
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "O: overdue weekly sync-ids reconciles with no change" "SCHEDULE=weekly STATE=ran DOCS=1 CHANGED=false" "$out"
cmp -s "$sb/before.json" "$(mf_of "$sb")" && ok "O: no-change run leaves manifest.json byte-identical (cmp)" || notok "O: no-change run modified manifest.json"

write_doc "$sb" "docs/adrs/0002-new.md" "ADR-0002"
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "O: new document registered" "STATE=ran DOCS=2 CHANGED=true" "$out"
[ "$("$real_jq" -S 'del(.id_registry)' "$sb/before.json")" = "$("$real_jq" -S 'del(.id_registry)' "$(mf_of "$sb")")" ] \
    && ok "O: a registering run changes only .id_registry" || notok "O: a registering run changed more than .id_registry"

# Forced sweep failure: the engine's compute jq call (the one carrying --arg reconcile_compute) fails.
fail_dir=$(make_sandbox)
cat > "$fail_dir/jq" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = "reconcile_compute" ] && exit 5; done
exec "$REAL_JQ" "$@"
EOF
chmod +x "$fail_dir/jq"
write_doc "$sb" "docs/adrs/0003-newer.md" "ADR-0003"
cp "$(mf_of "$sb")" "$sb/before.json"
out=$(PATH="$fail_dir:$PATH" REAL_JQ="$real_jq" bash "$AUTORUN" --project-dir "$sb")
assert_contains "O: a failed sweep prints STATE=error" "TASK=sync-ids KIND=deterministic SCHEDULE=weekly STATE=error" "$out"
cmp -s "$sb/before.json" "$(mf_of "$sb")" && ok "O: a failed sweep leaves manifest.json byte-identical" || notok "O: a failed sweep modified manifest.json"
rm -rf "$fail_dir" "$sb"

# No id_registry and no id-bearing document: never create an empty registry.
sb=$(make_sandbox)
write_manifest "$sb" 1 true weekly null
mkdir -p "$sb/docs/adrs"
printf '# Notes without frontmatter\n' > "$sb/docs/adrs/README.md"
cp "$(mf_of "$sb")" "$sb/before.json"
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "O: no documents, nothing changed" "STATE=ran DOCS=0 CHANGED=false" "$out"
cmp -s "$sb/before.json" "$(mf_of "$sb")" && ok "O: no id_registry is created without id-bearing documents" || notok "O: an empty id_registry was written"
rm -rf "$sb"

# Fresh clone with a weekly config: commit a reconciled tree, run, tree is clean.
sb=$(make_sandbox)
write_manifest "$sb" 1 true weekly null
write_doc "$sb" "docs/adrs/0001-test.md" "ADR-0001"
bash "$AUTORUN" --project-dir "$sb" >/dev/null
git -C "$sb" init -q
git -C "$sb" add -- docs
git -C "$sb" -c user.name=t -c user.email=t@example.invalid commit -q -m fixture
bash "$AUTORUN" --project-dir "$sb" >/dev/null
porcelain=$(git -C "$sb" status --porcelain)
[ -z "$porcelain" ] && ok "O: a fresh clone stays clean after a session-start run" || notok "O: fresh clone dirty: $porcelain"
rm -rf "$sb"

# ---- Test P: the skills agree that deterministic tasks keep no run state ----
# The runner change alone is not enough: /blueprint:sync-ids wrote the
# sync-ids run state itself, and /blueprint:execute saw a weekly sync-ids with
# no last_completed_at as due on every run (#3548).
SKILLS_DIR="${SCRIPT_DIR}/../../skills"
grep -q 'task_registry\["sync-ids"\]\.last_completed_at *=' "$SKILLS_DIR/blueprint-sync-ids/SKILL.md" \
    && notok "P: blueprint-sync-ids still writes sync-ids run state" \
    || ok "P: blueprint-sync-ids has no task_registry writeback"
grep -q 'deterministic task (`sync-ids`) is never due' "$SKILLS_DIR/blueprint-execute/SKILL.md" \
    && ok "P: blueprint-execute states deterministic tasks are never due" \
    || notok "P: blueprint-execute does not exempt deterministic tasks from due-ness"
grep -q 'reconciled each session' "$SKILLS_DIR/blueprint-status/SKILL.md" \
    && ok "P: blueprint-status reports a deterministic task as reconciled each session" \
    || notok "P: blueprint-status lacks the deterministic-task state"

# ---- Test Q: no session-start writer of task_registry; no run counters (#3553) ----
# Agent-task run state is written only after an explicit run; the run
# counters stats.runs / stats.runs_total are no longer incremented anywhere.
# Canonical: an uncanonicalised root keeps `/scripts/tests/../..` in every path
# grep prints, and the `/tests/` exclusion below would then drop every hit.
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
assign_re='\.task_registry\[[^]]*\][.A-Za-z0-9_"]*[[:space:]]*[|+-]?=[^=]'
# Control: the pattern matches an assignment and ignores a comparison.
[ "$(printf '%s\n' '.task_registry[$t].last_result = $r' '.task_registry[$t].x == 1' | grep -cE "$assign_re")" = "1" ] \
    && ok "Q: assignment pattern control" || notok "Q: assignment pattern does not discriminate"
session_writers=$(grep -nE "$assign_re" \
    "$PLUGIN_ROOT/hooks/blueprint-autorun-probe.sh" \
    "$PLUGIN_ROOT/hooks/blueprint-drift-probe.sh" \
    "$PLUGIN_ROOT/scripts/blueprint-autorun.sh")
[ -z "$session_writers" ] && ok "Q: SessionStart scripts assign no task_registry field" \
    || notok "Q: SessionStart scripts write task_registry: $session_writers"
counter_re='stats\.runs(_total)? // 0\) \+ 1'
# The increment is assembled from two pieces so this file never holds it on one
# line: #3553's acceptance command greps skills/ and scripts/ for it, tests
# included, and must find nothing.
counter_increment='((.task_registry[$t].stats.'"runs // 0) + 1)"
[ "$(printf '%s\n' "$counter_increment" | grep -cE "$counter_re")" = "1" ] \
    && ok "Q: counter pattern control" || notok "Q: counter pattern does not match an increment"
find_counter_increments() {
    # find_counter_increments <plugin-root> — increments in skills/ and
    # scripts/, test files excluded. grep runs on paths relative to the root,
    # so the `/tests/` filter sees only the plugin's own layout.
    (cd "$1" && grep -rnE --include='*.md' --include='*.sh' "$counter_re" skills scripts) \
        | grep -v '/tests/'
}
# Pipeline control: a planted increment in a skill is reported, one in a test
# file is not.
sb_q=$(make_sandbox)
mkdir -p "$sb_q/skills/planted" "$sb_q/scripts/tests"
printf 'x = %s\n' "$counter_increment" > "$sb_q/skills/planted/SKILL.md"
printf 'x = %s\n' "$counter_increment" > "$sb_q/scripts/tests/test-planted.sh"
planted=$(find_counter_increments "$sb_q")
[ "$planted" = "skills/planted/SKILL.md:1:x = $counter_increment" ] \
    && ok "Q: counter search reports a planted skill increment and skips tests/" \
    || notok "Q: counter search control got: ${planted:-<nothing>}"
rm -rf "$sb_q"
counters=$(find_counter_increments "$PLUGIN_ROOT")
[ -z "$counters" ] && ok "Q: no stats.runs / stats.runs_total increment in skills or scripts" \
    || notok "Q: run counter increments remain: $counters"

# ---- Test N: hook and sweep read frontmatter one way (#3549) ----
# The write-time hook and the session-start sweep call one parser
# (--frontmatter-rows). Before, both stored an inline comment verbatim
# (`id: ADR-9004  # c` registered under that whole string), both skipped a
# CRLF document, and a frontmatter `# comment` line could become the title.
HOOK="${SCRIPT_DIR}/../../hooks/auto-sync-id-registry.sh"
write_fixture_docs() {
    # write_fixture_docs <dir>
    local d="$1"
    mkdir -p "$d/docs/adrs" "$d/docs/prds" "$d/docs/prps"
    printf -- '---\nid: ADR-9004  # c\nstatus: Accepted # was Proposed\ntitle: "ADR-9004: Quoted: title"\ncreated: 2026-07-01\n---\n' > "$d/docs/adrs/9004-comment.md"
    printf -- '---\r\nid: ADR-9008\r\nstatus: Accepted\r\ntitle: CRLF document\r\ncreated: 2026-07-02\r\n---\r\n' > "$d/docs/adrs/9008-crlf.md"
    printf -- '---\n# a comment line\nid: ADR-9009\nstatus: Draft   \ncreated: 2026-07-03\n---\n\n# Heading title\n' > "$d/docs/adrs/9009-comment-line.md"
    printf -- "---\nid: PRD-0012\ntitle: 'It''s quoted'\nstatus: Draft\ncreated: 2026-07-04\n---\n" > "$d/docs/prds/0012-quoted.md"
    printf -- '---\nid: PRP-0003\ntitle: Fix #123\nstatus: Ready\ncreated: 2026-07-05\n---\n' > "$d/docs/prps/0003-hash.md"
}
registry_view() {
    "$real_jq" -S '.id_registry.documents | map_values({path, status, title, created})' "$1"
}
sb_sweep=$(make_sandbox)
write_manifest "$sb_sweep" 1 true daily null
write_fixture_docs "$sb_sweep"
bash "$AUTORUN" --project-dir "$sb_sweep" >/dev/null
sb_hook=$(make_sandbox)
write_manifest "$sb_hook" 1 true daily null
write_fixture_docs "$sb_hook"
for f in "$sb_hook"/docs/*/*.md; do
    printf '{"tool_input": {"file_path": "%s"}}' "$f" \
        | (cd "$sb_hook" && CLAUDE_PROJECT_DIR="$sb_hook" bash "$HOOK" 2>/dev/null)
done
sweep_view=$(registry_view "$sb_sweep/docs/blueprint/manifest.json")
hook_view=$(registry_view "$sb_hook/docs/blueprint/manifest.json")
[ "$sweep_view" = "$hook_view" ] && ok "N: hook and sweep register the same path/status/title/created" \
    || notok "N: hook and sweep differ: $(diff <(printf '%s\n' "$sweep_view") <(printf '%s\n' "$hook_view") | head -10)"
for view_label in sweep hook; do
    view=$sweep_view
    [ "$view_label" = "hook" ] && view=$hook_view
    [ "$(printf '%s' "$view" | "$real_jq" -r '.["ADR-9004"].status // "MISSING"')" = "Accepted" ] \
        && ok "N($view_label): \`id: ADR-9004  # c\` registers as ADR-9004" || notok "N($view_label): ADR-9004 not registered cleanly"
    [ "$(printf '%s' "$view" | "$real_jq" -r '.["ADR-9008"].path // "MISSING"')" = "docs/adrs/9008-crlf.md" ] \
        && ok "N($view_label): CRLF document registered" || notok "N($view_label): CRLF document not registered"
    [ "$(printf '%s' "$view" | "$real_jq" -r '.["ADR-9009"].title // "MISSING"')" = "Heading title" ] \
        && ok "N($view_label): frontmatter comment line is not the title" || notok "N($view_label): ADR-9009 title wrong"
done
rm -rf "$sb_sweep" "$sb_hook"


# ---- Test R: the --registry-reconcile engine (ADR-0027 Q2/Q4, #3550) ----
# One engine for the write-time hook and the session-start sweep. Pins the
# P1 prune (path exists, frontmatter does not carry the id), the P2 keep
# (path missing), counters that never decrease, created never from the clock,
# the rebuilt reverse index, duplicate resolution, determinism and --check.
reconcile() {
    # reconcile <dir> [--check] — runs the engine, prints its output
    local d="$1"
    shift
    bash "$AUTORUN" --registry-reconcile "$@" --project-dir "$d"
}
set_registry() {
    # set_registry <dir> <id_registry-json>
    local mf="$1/docs/blueprint/manifest.json"
    "$real_jq" --argjson r "$2" '.id_registry = $r' "$mf" > "$mf.new" && mv "$mf.new" "$mf"
}
reg_keys() { "$real_jq" -c '.id_registry.documents | keys' "$1/docs/blueprint/manifest.json"; }
reg_get() { "$real_jq" -c "$2" "$1/docs/blueprint/manifest.json"; }

# R1: the issue's scenario fixture.
sb=$(make_sandbox)
write_manifest "$sb" 1 true on-change null
mkdir -p "$sb/docs/adrs" "$sb/docs/prps" "$sb/docs/trps"
printf -- '---\nid: ADR-0099\nstatus: Accepted\ncreated: 2026-01-19\n---\n# Re-ided\n' > "$sb/docs/adrs/0019-reid.md"
printf -- '---\nstatus: Accepted\ncreated: 2026-01-21\n---\n# Id removed\n' > "$sb/docs/adrs/0021-noid.md"
printf -- '# ADR index\n\n```markdown\n---\nid: ADR-NNNN\n---\n```\n' > "$sb/docs/adrs/README.md"
printf -- '---\nid: TRP-001\nstatus: Draft\ncreated: 2026-02-01\n---\n# A TRP\n' > "$sb/docs/trps/x.md"
set_registry "$sb" '{"last_prd": 0, "last_prp": 5, "github_issues": {},
  "documents": {
    "ADR-0012": {"path": "docs/adrs/0012-deleted.md", "title": "Deleted", "status": "Accepted"},
    "ADR-0019": {"path": "docs/adrs/0019-reid.md", "title": "Re-ided", "status": "Accepted"},
    "ADR-0021": {"path": "docs/adrs/0021-noid.md", "title": "Id removed", "status": "Accepted"},
    "ADR-NNNN": {"path": "docs/adrs/README.md", "title": "ADR-NNNN: Title", "status": "Proposed"},
    "PRP-009": {"path": "docs/prps/009-missing.md", "title": "Missing", "status": "Ready"},
    "TRP-001": {"path": "docs/trps/x.md", "title": "A TRP", "status": "Draft"}}}'
out=$(reconcile "$sb")
assert_contains "R1: engine reports a change" "CHANGED=true" "$out"
keys=$(reg_keys "$sb")
[ "$keys" = '["ADR-0012","ADR-0099","PRP-009","TRP-001"]' ] \
    && ok "R1: P1 pruned ADR-0019/ADR-0021/ADR-NNNN, kept P2 ADR-0012/PRP-009, registered ADR-0099" \
    || notok "R1: registry keys are $keys"
assert_contains "R1: the prune is reported" "ACTION=prune ID=ADR-NNNN PATH=docs/adrs/README.md" "$out"
[ "$(reg_get "$sb" '.id_registry.last_prp')" -ge 9 ] && ok "R1: last_prp raised over the retained PRP-009" || notok "R1: last_prp is $(reg_get "$sb" '.id_registry.last_prp')"
[ "$(reg_get "$sb" '.id_registry.last_trp // 0')" -ge 1 ] && ok "R1: last_trp counts TRP-001" || notok "R1: last_trp is $(reg_get "$sb" '.id_registry.last_trp')"
[ "$(reg_get "$sb" '.id_registry.last_prd')" = "0" ] && ok "R1: last_prd unchanged" || notok "R1: last_prd changed"
# Counters never decrease, even when nothing on disk or in the registry reaches them.
set_registry "$sb" "$(reg_get "$sb" '.id_registry | .last_prd = 40')"
reconcile "$sb" >/dev/null
[ "$(reg_get "$sb" '.id_registry.last_prd')" = "40" ] && ok "R1: a counter above every id never decreases" || notok "R1: last_prd decreased"
rm -rf "$sb"

# R2: zero padding — `id: ADR-012` registered under ADR-0012 is the same id.
sb=$(make_sandbox)
write_manifest "$sb" 1 true on-change null
mkdir -p "$sb/docs/adrs"
printf -- '---\nid: ADR-012\nstatus: Accepted\ncreated: 2026-01-12\n---\n# Padded\n' > "$sb/docs/adrs/0012-padded.md"
set_registry "$sb" '{"last_prd": 0, "last_prp": 0, "github_issues": {},
  "documents": {"ADR-0012": {"path": "docs/adrs/0012-padded.md", "title": "Padded", "status": "Accepted", "created": "2026-01-12", "relates_to": [], "github_issues": []}}}'
reconcile "$sb" >/dev/null
[ "$(reg_keys "$sb")" = '["ADR-0012"]' ] && ok "R2: ADR-012 under ADR-0012 is neither pruned nor duplicated" || notok "R2: keys $(reg_keys "$sb")"
rm -rf "$sb"

# R3: a WO entry whose (git-ignored) file is absent keeps its stored fields,
# and the rebuilt reverse index still lists its PRP under the issue.
sb=$(make_sandbox)
write_manifest "$sb" 1 true on-change null
mkdir -p "$sb/docs/prps"
printf -- '---\nid: PRP-003\nstatus: Ready\ncreated: 2026-01-03\ngithub-issues: [42, "#43"]\nrelates-to:\n  - ADR-0001\n---\n# PRP three\n' > "$sb/docs/prps/003-prp.md"
set_registry "$sb" '{"last_prd": 0, "last_prp": 3, "github_issues": {"42": ["WO-001", "PRP-003"]},
  "documents": {"WO-001": {"path": "docs/blueprint/work-orders/001-task.md", "title": "Task", "implements": ["PRP-003"], "github_issues": [42], "created": "2026-01-04"}}}'
reconcile "$sb" >/dev/null
[ "$(reg_get "$sb" '.id_registry.documents["WO-001"] | [.implements, .github_issues]')" = '[["PRP-003"],[42]]' ] \
    && ok "R3: the absent WO entry keeps implements and github_issues" || notok "R3: WO entry $(reg_get "$sb" '.id_registry.documents["WO-001"]')"
[ "$(reg_get "$sb" '.id_registry.github_issues["42"]')" = '["PRP-003","WO-001"]' ] \
    && ok "R3: the reverse index lists the WO and its PRP under the issue" || notok "R3: reverse index 42 = $(reg_get "$sb" '.id_registry.github_issues["42"]')"
[ "$(reg_get "$sb" '.id_registry.documents["PRP-003"] | [.relates_to, .github_issues]')" = '[["ADR-0001"],[42,43]]' ] \
    && ok "R3: cross-refs are derived from frontmatter" || notok "R3: PRP-003 cross-refs $(reg_get "$sb" '.id_registry.documents["PRP-003"]')"
[ "$(reg_get "$sb" '.id_registry.github_issues["43"]')" = '["PRP-003"]' ] && ok "R3: the reverse index carries the derived issue" || notok "R3: reverse index 43 missing"
rm -rf "$sb"

# R4: created comes from frontmatter, else the existing value, never the clock.
sb=$(make_sandbox)
write_manifest "$sb" 1 true on-change null
mkdir -p "$sb/docs/adrs"
printf -- '---\nid: ADR-0001\nstatus: Accepted\n---\n# No created\n' > "$sb/docs/adrs/0001-a.md"
printf -- '---\nid: ADR-0002\nstatus: Accepted\n---\n# Kept created\n' > "$sb/docs/adrs/0002-b.md"
set_registry "$sb" '{"last_prd": 0, "last_prp": 0, "github_issues": {},
  "documents": {"ADR-0002": {"path": "docs/adrs/0002-b.md", "title": "Kept created", "status": "Accepted", "created": "2020-02-02"}}}'
reconcile "$sb" >/dev/null
[ "$(reg_get "$sb" '.id_registry.documents["ADR-0001"] | has("created")')" = "false" ] \
    && ok "R4: no created in frontmatter or registry -> created omitted" || notok "R4: created set from the clock"
[ "$(reg_get "$sb" '.id_registry.documents["ADR-0002"].created')" = '"2020-02-02"' ] \
    && ok "R4: an existing created is kept" || notok "R4: existing created replaced"
rm -rf "$sb"

# R5: duplicates — the registered path wins while it still carries the id,
# else the lexically first path; both cases are reported.
sb=$(make_sandbox)
write_manifest "$sb" 1 true on-change null
mkdir -p "$sb/docs/adrs"
printf -- '---\nid: ADR-0005\nstatus: Accepted\n---\n# A\n' > "$sb/docs/adrs/0005-a.md"
printf -- '---\nid: ADR-0005\nstatus: Accepted\n---\n# B\n' > "$sb/docs/adrs/0005-b.md"
set_registry "$sb" '{"last_prd": 0, "last_prp": 0, "github_issues": {},
  "documents": {"ADR-0005": {"path": "docs/adrs/0005-b.md", "title": "B", "status": "Accepted", "foreign": "kept"}}}'
out=$(reconcile "$sb")
[ "$(reg_get "$sb" '.id_registry.documents["ADR-0005"] | [.path, .foreign]')" = '["docs/adrs/0005-b.md","kept"]' ] \
    && ok "R5: the registered path keeps a duplicated id; foreign keys survive" || notok "R5: entry $(reg_get "$sb" '.id_registry.documents["ADR-0005"]')"
assert_contains "R5: the duplicate is reported" "ACTION=duplicate ID=ADR-0005 KEPT=docs/adrs/0005-b.md DROPPED=docs/adrs/0005-a.md" "$out"
set_registry "$sb" '{"last_prd": 0, "last_prp": 0, "github_issues": {}, "documents": {}}'
reconcile "$sb" >/dev/null
[ "$(reg_get "$sb" '.id_registry.documents["ADR-0005"].path')" = '"docs/adrs/0005-a.md"' ] \
    && ok "R5: an unregistered duplicate resolves to the lexically first path" || notok "R5: got $(reg_get "$sb" '.id_registry.documents["ADR-0005"].path')"
rm -rf "$sb"

# R6: determinism — two copies of one stale tree, built in opposite file
# orders, give byte-identical manifests; a second reconcile is a no-op.
build_stale_tree() {
    # build_stale_tree <dir> <forward|reverse>
    local d="$1" order="$2" n list
    write_manifest "$d" 1 true on-change null
    mkdir -p "$d/docs/adrs" "$d/docs/prds"
    list="1 2 3 4 5 6 7 8"
    [ "$order" = reverse ] && list="8 7 6 5 4 3 2 1"
    for n in $list; do
        printf -- '---\nid: ADR-000%s\nstatus: Accepted\ngithub-issues: [%s]\n---\n# ADR %s\n' "$n" "$((n % 3 + 10))" "$n" > "$d/docs/adrs/000$n-x.md"
    done
    printf -- '---\nid: PRD-0002\nstatus: Draft\n---\n# PRD\n' > "$d/docs/prds/p.md"
    set_registry "$d" '{"last_prd": 1, "last_prp": 0, "github_issues": {"10": "ADR-0003"},
      "documents": {"ADR-0004": {"path": "docs/adrs/0004-x.md", "title": "Old", "status": "Draft"},
                    "ADR-0042": {"path": "docs/adrs/0001-x.md", "title": "Stale key", "status": "Draft"}}}'
}
sb=$(make_sandbox); sb2=$(make_sandbox)
build_stale_tree "$sb" forward
build_stale_tree "$sb2" reverse
reconcile "$sb" >/dev/null
reconcile "$sb2" >/dev/null
cmp -s "$sb/docs/blueprint/manifest.json" "$sb2/docs/blueprint/manifest.json" \
    && ok "R6: two copies of one stale tree reconcile to byte-identical manifests" \
    || notok "R6: manifests differ: $(diff "$sb/docs/blueprint/manifest.json" "$sb2/docs/blueprint/manifest.json" | head -10)"
cp "$sb/docs/blueprint/manifest.json" "$sb/before.json"
out=$(reconcile "$sb")
assert_contains "R6: a second reconcile finds nothing to change" "CHANGED=false" "$out"
cmp -s "$sb/before.json" "$sb/docs/blueprint/manifest.json" && ok "R6: a second reconcile leaves the bytes alone" || notok "R6: a second reconcile rewrote the manifest"
rm -rf "$sb" "$sb2"

# R7: --check reports drift without writing and exits 1; exits 0 once clean.
sb=$(make_sandbox)
write_manifest "$sb" 1 true on-change null
write_doc "$sb" "docs/adrs/0001-test.md" "ADR-0001"
set_registry "$sb" '{"last_prd": 0, "last_prp": 0, "github_issues": {}, "documents": {}}'
cp "$sb/docs/blueprint/manifest.json" "$sb/before.json"
out=$(reconcile "$sb" --check); rc=$?
[ "$rc" -eq 1 ] && ok "R7: --check exits 1 on drift" || notok "R7: --check exit $rc on drift"
assert_contains "R7: --check names the unregistered document" "ACTION=add ID=ADR-0001 PATH=docs/adrs/0001-test.md" "$out"
cmp -s "$sb/before.json" "$sb/docs/blueprint/manifest.json" && ok "R7: --check writes nothing" || notok "R7: --check wrote the manifest"
reconcile "$sb" >/dev/null
reconcile "$sb" --check >/dev/null; rc=$?
[ "$rc" -eq 0 ] && ok "R7: --check exits 0 on a reconciled tree" || notok "R7: --check exit $rc on a reconciled tree"
rm -rf "$sb"

# R8: no id_registry and no id-bearing document: nothing is created.
sb=$(make_sandbox)
write_manifest "$sb" 0 true on-change null
mkdir -p "$sb/docs/adrs"
printf '# Notes\n' > "$sb/docs/adrs/README.md"
cp "$sb/docs/blueprint/manifest.json" "$sb/before.json"
reconcile "$sb" >/dev/null
cmp -s "$sb/before.json" "$sb/docs/blueprint/manifest.json" && ok "R8: no id_registry is created without id-bearing documents" || notok "R8: the engine created an id_registry"
rm -rf "$sb"

# R9: a task_registry write made while a reconcile computes survives: the new
# id_registry is applied to the manifest re-read under the lock. A PATH-stubbed
# jq parks inside the compute call (the one carrying --arg reconcile_compute).
park_dir=$(make_sandbox)
cat > "$park_dir/jq" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
    if [ "$a" = "reconcile_compute" ]; then
        : > "$STUB_MARK"
        i=0
        while [ ! -f "$STUB_RELEASE" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
        break
    fi
done
exec "$REAL_JQ" "$@"
EOF
chmod +x "$park_dir/jq"
sb=$(make_sandbox)
write_manifest "$sb" 1 true on-change null
write_doc "$sb" "docs/adrs/0001-test.md" "ADR-0001"
PATH="$park_dir:$PATH" REAL_JQ="$real_jq" STUB_MARK="$sb/mark" STUB_RELEASE="$sb/release" \
    bash "$AUTORUN" --registry-reconcile --project-dir "$sb" >/dev/null 2>&1 &
rpid=$!
if wait_for_file "$sb/mark"; then
    [ -d "$sb/docs/blueprint/manifest.json.lock.d" ] && ok "R9: the reconcile holds the mkdir lock while it computes" || notok "R9: no lock held during the compute"
    mf="$sb/docs/blueprint/manifest.json"
    "$real_jq" '.task_registry["adr-validate"].last_result = "concurrent"' "$mf" > "$mf.cw" && mv "$mf.cw" "$mf"
    : > "$sb/release"
    wait "$rpid"
    [ "$(reg_get "$sb" '.task_registry["adr-validate"].last_result')" = '"concurrent"' ] \
        && ok "R9: a concurrent task_registry write survives the reconcile" || notok "R9: the concurrent task_registry write was lost"
    [ "$(reg_get "$sb" '.id_registry.documents["ADR-0001"].path')" = '"docs/adrs/0001-test.md"' ] \
        && ok "R9: the reconcile still registered the document" || notok "R9: document not registered"
    [ ! -e "$sb/docs/blueprint/manifest.json.lock.d" ] && ok "R9: the lock is released" || notok "R9: lock left behind"
    leftover=$(find "$sb/docs/blueprint" -name 'manifest.json.reconcile.*' | wc -l | tr -d ' ')
    [ "$leftover" = "0" ] && ok "R9: no temp file left behind" || notok "R9: $leftover temp files left behind"
else
    notok "R9: the reconcile never reached its compute call"
    : > "$sb/release"
    wait "$rpid"
fi
rm -rf "$sb" "$park_dir"

# R10: the session-start sweep is the engine — the sweep and a direct
# reconcile of identical trees produce identical manifests.
sb=$(make_sandbox); sb2=$(make_sandbox)
build_stale_tree "$sb" forward
build_stale_tree "$sb2" forward
bash "$AUTORUN" --project-dir "$sb" >/dev/null
reconcile "$sb2" >/dev/null
cmp -s "$sb/docs/blueprint/manifest.json" "$sb2/docs/blueprint/manifest.json" \
    && ok "R10: run_sync_ids delegates to the engine" || notok "R10: sweep and engine differ"
rm -rf "$sb" "$sb2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0

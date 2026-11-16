#!/usr/bin/env bash
# blueprint-autorun.sh — implement the manifest task_registry auto-run contract.
#
# Reads docs/blueprint/manifest.json, computes due-ness for every task with
# enabled:true + auto_run:true (schedule vs last_completed_at), executes the
# DETERMINISTIC due tasks directly (no model in the loop), and reports due
# AGENT-JUDGMENT tasks without executing them (the SessionStart probe turns
# those into drift findings; the level-2 autopilot skill executes them).
#
# Task-kind split (see ADR-0020 and
# .claude/rules/offload-to-deterministic-substrate.md):
#   deterministic : sync-ids (id-registry sweep — the --registry-reconcile
#                   engine the write-time hook also calls, ADR-0027 Q4)
#   agent-judgment: everything else (adr-validate, feature-tracker-sync,
#                   story-audit, ...) — surfaced as due, never executed here.
#
# Schedule semantics:
#   daily/weekly : an agent-judgment task is due when last_completed_at is
#                  null/unparseable or older than the interval. A
#                  DETERMINISTIC task keeps no run state, so it reconciles on
#                  every run (STATE=reconcile), as for on-change.
#   on-change    : event-driven (PostToolUse hooks). An agent-judgment task is
#                  never runner-due. A DETERMINISTIC task is also reconciled on
#                  every run (STATE=reconcile): the on-change signal is
#                  best-effort — a Bash edit's change list can miss files, and
#                  edits by people or other tools fire no hook at all.
#   on-demand    : never due
#
# Nothing here writes task_registry (ADR-0027 Q3, #3548): the only manifest
# write is a reconcile that changed id_registry, so a clean tree stays clean.
#
# Execution is gated on automation.autonomy_level >= 1 (missing block = 0).
# --report computes due-ness only: no execution, no manifest write.
# BLUEPRINT_AUTORUN_DISABLE=1 makes the whole script a no-op.
#
# Output follows .claude/rules/structured-script-output.md.
# Exit 0 on OK/WARN, 1 on ERROR (parallel-safe).
#
# Usage: blueprint-autorun.sh [--project-dir DIR] [--report]
#        blueprint-autorun.sh --registry-reconcile [--check] [--project-dir DIR]
#        blueprint-autorun.sh --frontmatter-rows FILE...
#
# --registry-reconcile is the one id-registry engine (ADR-0027 Q2/Q4, #3550);
# see registry_reconcile below. --check reports what it would change, writes
# nothing, and exits 1 when id_registry is stale.
#
# --frontmatter-rows is the one frontmatter parser the write-time hook
# (through registry_reconcile), the session-start sweep (run_sync_ids) and
# the sync-ids audit share (ADR-0027 Q1, #3549). It prints one row per file and
# nothing else; see frontmatter_rows below for the row shape. Level 3 vendors
# this script as one file, so the parser lives here rather than in a library.

# set -u only (no -e/pipefail): this is a run-every-section collector — a
# single failing task must not abort the remaining tasks (see
# .claude/rules/shell-scripting.md "Error Handling Flags").
set -u

usage() {
    printf 'usage: blueprint-autorun.sh [--project-dir DIR] [--report]\n' >&2
    printf '       blueprint-autorun.sh --registry-reconcile [--check] [--project-dir DIR]\n' >&2
    printf '       blueprint-autorun.sh --frontmatter-rows FILE...\n' >&2
}

# frontmatter_rows FILE... — print one row per file, fields separated by \037:
#   path, has_frontmatter (1|0), id, status, title, created, relates_to,
#   github_issues
# relates_to and github_issues are lists, items separated by \036.
#
# Semantics follow check-schema.py split_frontmatter plus the YAML scalar
# subset blueprint documents use, so the hook, the sweep and the audit cannot
# read one file three ways:
#   - CRs are stripped before every test;
#   - frontmatter exists only when line 1 is `---` and a later line closes it
#     (a fenced `---` example further down an index README is body text);
#   - the first top-level `key:` wins; `# comment` lines are skipped;
#   - an unquoted ` #` starts a comment; matching quotes are removed (`''`
#     inside single quotes is one quote, `\"` inside double quotes is a quote);
#     trailing whitespace is trimmed;
#   - a plain id, status, title or created value continues on more-indented
#     lines, each folded in with one space, until a ` #` comment, a list item
#     or a less-indented line; a blank line inside is skipped, not kept as
#     the newline YAML would fold it to;
#   - relates-to and github-issues are read as block (`- x`) or flow (`[x, y]`)
#     lists;
#   - an empty title falls back to the first `# ` heading of the body (outside
#     code fences), never to a line inside the frontmatter;
#   - a zero-byte file still gets its row: has_frontmatter 0, every other
#     field empty.
# Files are sorted with LC_ALL=C first, so the output order is the same on
# every machine.
frontmatter_rows() {
    [ $# -gt 0 ] || return 0
    local -a fm_files=()
    local fm_file
    while IFS= read -r -d '' fm_file; do
        fm_files+=("$fm_file")
    done < <(printf '%s\0' "$@" | LC_ALL=C sort -z)
    # SQ carries a single quote into the program: hex escapes are not POSIX awk.
    awk -v SQ="'" '
        function ltrim(s) { sub(/^[ \t]+/, "", s); return s }
        function rtrim(s) { sub(/[ \t]+$/, "", s); return s }
        function trim(s) { return rtrim(ltrim(s)) }
        # Parse one YAML scalar (the text after `key:` or `- `). Sets SC_REST
        # to whatever follows a quoted scalar, for the flow-list reader.
        function scalar(s,    c, i, n, out, ch, nx) {
            s = ltrim(s)
            SC_REST = ""
            if (s == "") return ""
            c = substr(s, 1, 1)
            n = length(s)
            if (c == "\"") {
                out = ""
                for (i = 2; i <= n; i++) {
                    ch = substr(s, i, 1)
                    if (ch == "\\" && i < n) {
                        nx = substr(s, i + 1, 1)
                        if (nx == "t") out = out "\t"
                        else if (nx == "n") out = out " "
                        else out = out nx
                        i++
                    } else if (ch == "\"") {
                        SC_REST = substr(s, i + 1)
                        return out
                    } else out = out ch
                }
                return out
            }
            if (c == SQ) {
                out = ""
                for (i = 2; i <= n; i++) {
                    ch = substr(s, i, 1)
                    if (ch == SQ) {
                        if (substr(s, i + 1, 1) == SQ) { out = out SQ; i++; continue }
                        SC_REST = substr(s, i + 1)
                        return out
                    }
                    out = out ch
                }
                return out
            }
            if (c == "#") return ""
            if (match(s, /[ \t]#/)) s = substr(s, 1, RSTART - 1)
            return rtrim(s)
        }
        # Items of a flow list `[a, "b, c", d]`, joined with \036.
        function flow_list(s,    n, i, ch, q, item, out, items) {
            s = substr(ltrim(s), 2)
            n = length(s); q = ""; item = ""; out = ""; items = 0
            for (i = 1; i <= n; i++) {
                ch = substr(s, i, 1)
                if (q != "") {
                    item = item ch
                    if (ch == q) q = ""
                    continue
                }
                if (ch == "\"" || ch == SQ) { q = ch; item = item ch; continue }
                if (ch == "," || ch == "]") {
                    item = scalar(item)
                    if (item != "") { out = out (items++ ? "\036" : "") item }
                    item = ""
                    if (ch == "]") break
                    continue
                }
                item = item ch
            }
            return out
        }
        function list_value(s,    v) {
            s = ltrim(s)
            if (substr(s, 1, 1) == "[") return flow_list(s)
            return scalar(s)
        }
        function set_field(key, v) {
            if (key == "id") id = v
            else if (key == "status") status = v
            else if (key == "title") title = v
            else if (key == "created") created = v
        }
        # Whether the value after `key:` is a plain scalar a following
        # indented line may continue: empty, or opening with a comment, or
        # unquoted text that no ` #` comment has already ended.
        function plain_open(s,    c) {
            s = ltrim(s)
            if (s == "") return 1
            c = substr(s, 1, 1)
            if (c == "#") return 1
            if (index("\"" SQ "[{|>&*!", c)) return 0
            return !match(s, /[ \t]#/)
        }
        function add_item(key, v) {
            if (v == "") return
            if (key == "relates-to") rel = rel (rel == "" ? "" : "\036") v
            else gh = gh (gh == "" ? "" : "\036") v
        }
        function emit(    t) {
            if (doc == "") return
            if (state != 2) {
                # Line 1 opened frontmatter but nothing closed it: no
                # frontmatter (split_frontmatter returns None), the whole
                # file is body.
                has_fm = 0; id = status = title = created = rel = gh = ""
                body_heading = any_heading
            }
            t = title
            if (t == "") t = body_heading
            gsub(/[\036\037\n]/, " ", t)
            printf "%s\037%d\037%s\037%s\037%s\037%s\037%s\037%s\n", \
                doc, has_fm, id, status, t, created, rel, gh
        }
        # any_heading: first heading of the whole file (the fallback when an
        # opened frontmatter never closes); body_heading: first heading after
        # the frontmatter. Each tracks its own fence state.
        function heading_scan(line) {
            if (line ~ /^[ \t]*(```|~~~)/) {
                any_fence = !any_fence
                if (state == 2) in_fence = !in_fence
                return
            }
            if (line !~ /^# /) return
            if (!any_fence && any_heading == "") any_heading = trim(substr(line, 3))
            if (state == 2 && !in_fence && body_heading == "") body_heading = trim(substr(line, 3))
        }
        # A zero-byte file has no FNR == 1 record, so awk never visits it.
        # Walk ARGV alongside the input and print an empty row for each file
        # skipped that way, keeping one row per file in argument order.
        function emit_empty_until(f) {
            while (argi < ARGC && ARGV[argi] != f) {
                printf "%s\0370\037\037\037\037\037\037\n", ARGV[argi]
                argi++
            }
            argi++
        }
        BEGIN { argi = 1 }
        FNR == 1 {
            emit()
            emit_empty_until(FILENAME)
            doc = FILENAME
            has_fm = 0; state = 2; in_fence = any_fence = 0; inlist = ""; cont = ""
            id = status = title = created = rel = gh = ""
            body_heading = any_heading = ""
            split("", seen)
            line = $0; gsub(/\r/, "", line)
            if (trim(line) == "---") { has_fm = 1; state = 1; next }
            heading_scan(line)
            next
        }
        {
            line = $0
            gsub(/\r/, "", line)
            if (state == 1) {
                heading_scan(line)
                if (trim(line) == "---") { state = 2; inlist = ""; cont = ""; next }
                # A more-indented line continues the plain scalar of the
                # last scalar key; YAML folds the line break to one space.
                # A ` #` comment ends it; a blank line keeps it open (YAML
                # folds that to a newline, which a row cannot carry).
                if (cont != "") {
                    if (line ~ /^[ \t]+[^ \t]/ && ltrim(line) !~ /^(#|-([ \t]|$))/) {
                        v = ltrim(line)
                        stop = match(v, /[ \t]#/)
                        if (stop) v = substr(v, 1, RSTART - 1)
                        v = rtrim(v)
                        cval = (cval == "" ? v : cval " " v)
                        set_field(cont, cval)
                        if (stop) cont = ""
                        next
                    }
                    if (line ~ /^[ \t]*$/) next
                    cont = ""
                }
                if (inlist != "") {
                    if (line ~ /^[ \t]*-([ \t]|$)/) {
                        v = line; sub(/^[ \t]*-/, "", v)
                        add_item(inlist, scalar(v))
                        next
                    }
                    if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/) next
                    inlist = ""
                }
                if (line ~ /^[ \t]*#/) next
                if (line !~ /^[A-Za-z_][A-Za-z0-9_-]*:([ \t]|$)/) next
                key = line; sub(/:.*/, "", key)
                rest = substr(line, length(key) + 2)
                if (key in seen) next
                seen[key] = 1
                if (key == "id" || key == "status" || key == "title" || key == "created") {
                    cval = scalar(rest)
                    set_field(key, cval)
                    if (plain_open(rest)) cont = key
                }
                else if (key == "relates-to" || key == "github-issues") {
                    v = ltrim(rest)
                    if (v == "" || substr(v, 1, 1) == "#") inlist = key
                    else if (substr(v, 1, 1) == "[") {
                        if (key == "relates-to") rel = flow_list(v)
                        else gh = flow_list(v)
                    } else add_item(key, scalar(v))
                }
                next
            }
            heading_scan(line)
        }
        END { emit(); emit_empty_until("") }
    ' "${fm_files[@]}"
}

if [ "${1:-}" = "--frontmatter-rows" ]; then
    shift
    frontmatter_rows "$@"
    exit $?
fi

# registry_reconcile PROJECT_DIR apply|check — the one id-registry engine
# (ADR-0027 Q2/Q4, #3550). The write-time hook (hooks/blueprint-doc-change.sh),
# the session-start sweep (run_sync_ids) and the sync-ids audit (--check) all
# call it, so registration has one implementation.
#
#   - Input: every docs/{prds,adrs,prps,trps}/*.md and
#     docs/blueprint/work-orders/*.md, plus every registered path that exists,
#     read by one frontmatter_rows pass and one jq call.
#   - Entries: path, status, title, relates_to and github_issues are derived
#     from frontmatter and merged into the existing entry, so keys frontmatter
#     does not carry (implements, ...) survive. created comes from frontmatter,
#     else the existing value, else is omitted: never from the clock.
#   - Prune (P1): an entry whose own path exists, in any directory, and whose
#     frontmatter does not carry the entry's id is removed. Ids compare after
#     norm() (ADR-012 == ADR-0012). An entry whose path is missing (P2) is never
#     touched: work orders are git-ignored, checkouts can be sparse.
#   - Duplicates: the registered path keeps the id while it still carries it,
#     else the lexically first path. Reported as ACTION=duplicate.
#   - Counters: last_prd/last_prp/last_trp = max(existing, ids on disk,
#     registry keys before pruning). They never decrease. last_trp is written
#     only when it exists or a TRP id is seen.
#   - Reverse index: rebuilt from every entry's github_issues, listing the
#     entry and whatever it implements (a work order lists its PRP).
#   - Write: only when id_registry differs; under an mkdir lock; the new
#     id_registry is applied to the manifest re-read under the lock (a
#     concurrent task_registry write survives); per-PID temp file + atomic mv.
#     No id_registry is created when no document carries an id.
#   - check: compute and report, never write; exit 1 when a write is due.
#
# Output: a === BLUEPRINT REGISTRY RECONCILE === block with DOCS=, CHANGED=,
# one row per finding, STATUS=, ISSUE_COUNT=. Rows (the sync-ids audit parses
# them, #3552):
#   - ACTION=add ID=<id> PATH=<path>
#   - ACTION=update ID=<id> PATH=<path> FIELDS=<a,b> WAS=<previous path>
#   - ACTION=prune ID=<id> PATH=<path> HAS=<id the frontmatter carries>
#   - ACTION=duplicate ID=<id> KEPT=<path> DROPPED=<paths> The body is a subshell, so its cd and traps stay local.
registry_reconcile() (
    rr_dir="$1"
    rr_mode="$2"
    rr_pid="${BASHPID:-$$}"
    rr_have_lock=0
    rr_manifest=""
    rr_lock=""
    rr_tmp=""

    rr_finish() {
        # rr_finish <status> <issue_count> [reason]
        printf 'STATUS=%s\n' "$1"
        [ "$1" != "OK" ] && [ -n "${3:-}" ] && printf 'REASON=%s\n' "$3"
        printf 'ISSUE_COUNT=%s\n' "$2"
        printf '=== END BLUEPRINT REGISTRY RECONCILE ===\n'
    }
    # shellcheck disable=SC2329,SC2317  # invoked indirectly by the EXIT trap
    rr_cleanup() {
        [ -n "$rr_tmp" ] && rm -f "$rr_tmp" "${rr_tmp}.result"
        if [ "$rr_have_lock" = 1 ]; then
            rm -f "${rr_lock}/pid"
            rmdir "$rr_lock" 2>/dev/null
        fi
        return 0
    }
    trap rr_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    printf '=== BLUEPRINT REGISTRY RECONCILE ===\n'
    printf 'MODE=%s\n' "$rr_mode"
    if ! cd "$rr_dir" 2>/dev/null; then
        printf 'CHANGED=false\n'
        rr_finish ERROR 1 "project_dir_unreadable: ${rr_dir}"
        return 1
    fi
    if [ -f docs/blueprint/manifest.json ]; then
        rr_manifest="docs/blueprint/manifest.json"
    elif [ -f docs/blueprint/.manifest.json ]; then
        rr_manifest="docs/blueprint/.manifest.json"
    else
        printf 'REGISTRY=no_manifest\nDOCS=0\nCHANGED=false\n'
        rr_finish OK 0
        return 0
    fi
    if ! command -v jq >/dev/null 2>&1; then
        printf 'REGISTRY=jq_unavailable\nDOCS=0\nCHANGED=false\n'
        rr_finish OK 0
        return 0
    fi
    rr_lock="${rr_manifest}.lock.d"
    rr_tmp="${rr_manifest}.reconcile.${rr_pid}"

    # Serialise writers. A lock whose owner is gone (SIGKILL) is taken over.
    if [ "$rr_mode" = "apply" ]; then
        rr_tries=0
        until mkdir "$rr_lock" 2>/dev/null; do
            rr_owner=$(cat "${rr_lock}/pid" 2>/dev/null)
            if [ -n "$rr_owner" ] && ! kill -0 "$rr_owner" 2>/dev/null; then
                rm -f "${rr_lock}/pid"
                rmdir "$rr_lock" 2>/dev/null
                continue
            fi
            rr_tries=$((rr_tries + 1))
            if [ "$rr_tries" -ge 300 ]; then
                printf 'CHANGED=false\n'
                rr_finish ERROR 1 "lock_timeout: ${rr_lock} held for 15 s"
                return 1
            fi
            sleep 0.05
        done
        rr_have_lock=1
        printf '%s\n' "$rr_pid" > "${rr_lock}/pid"
    fi

    # Scan set plus every registered path that exists, deduplicated.
    rr_files=()
    while IFS= read -r -d '' rr_f; do
        rr_files+=("$rr_f")
    done < <(
        {
            find docs/prds docs/adrs docs/prps docs/trps docs/blueprint/work-orders \
                -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null
            jq -r '(.id_registry.documents // {}) | objects | .[] | objects | .path | strings' \
                "$rr_manifest" 2>/dev/null \
                | while IFS= read -r rr_p; do
                    [ -n "$rr_p" ] && [ -f "$rr_p" ] && printf '%s\0' "$rr_p"
                done
        } | LC_ALL=C sort -zu
    )
    rr_rows=""
    if [ "${#rr_files[@]}" -gt 0 ]; then
        rr_rows=$(frontmatter_rows "${rr_files[@]}")
    fi

    # One jq call computes the new id_registry and the findings. Rows arrive
    # on stdin (an argument would hit the 128 KiB per-argument limit).
    # shellcheck disable=SC2016  # jq program text, not shell expansions
    if ! printf '%s\n' "$rr_rows" | jq -R -s \
            --arg reconcile_compute 1 \
            --slurpfile manifest_doc "$rr_manifest" \
            'def norm: ascii_upcase
                 | if test("^[A-Z]+-[0-9]+$")
                   then capture("^(?<p>[A-Z]+)-0*(?<n>[0-9]*)$") | .p + "-" + (if .n == "" then "0" else .n end)
                   else . end;
             def cnum($p): ascii_upcase | select(test("^" + $p + "-[0-9]+$")) | ltrimstr($p + "-") | tonumber;
             def scan_path: test("^docs/(prds|adrs|prps|trps)/[^/]+\\.md$|^docs/blueprint/work-orders/[^/]+\\.md$");
             def lst($s): ($s // "") | split("\u001e") | map(select(length > 0));
             ($manifest_doc[0]) as $doc
             | ($doc.id_registry // null) as $old
             | [split("\n")[] | select(length > 0) | split("\u001f")
                | {path: .[0], id: (if .[1] == "1" then .[2] else "" end),
                   status: (.[3] // ""), title: (.[4] // ""), created: (.[5] // ""),
                   rel: lst(.[6]), gh: (lst(.[7]) | map(ltrimstr("#") | tonumber? // empty))}] as $all
             | ($all | map({key: .path, value: .id}) | from_entries) as $fm_id
             | ($all | map(select(.id != "" and (.path | scan_path))) | sort_by(.path)) as $scan
             | if ($old | type) != "object" and ($scan | length) == 0 then
                 {changed: false, registry: $old, docs: 0, findings: []}
               else
                 (if ($old | type) == "object" then $old
                  else {last_prd: 0, last_prp: 0, documents: {}, github_issues: {}} end) as $base
                 | (($base.documents // {}) | if type == "object" then . else {} end) as $docs0
                 | ($docs0 | keys_unsorted | map({k: ., n: norm})) as $keyn
                 | reduce ($scan | group_by(.id | norm))[] as $g ({docs: $docs0, findings: []};
                     ($g[0].id | norm) as $n
                     | ([$keyn[] | select(.n == $n) | .k] | sort) as $ek
                     | ($g | map(.path)) as $gpaths
                     | ([$ek[] | select((($docs0[.] | objects | .path) // null) as $p
                                        | ($gpaths | index($p)) != null)] | first) as $kmatch
                     | ($kmatch // $ek[0] // $g[0].id) as $key
                     | (if $kmatch != null
                        then ($docs0[$kmatch].path) as $rp | ($g | map(select(.path == $rp)) | first)
                        else $g[0] end) as $w
                     | (($docs0[$key] | objects) // {}) as $e
                     | ($e + {path: $w.path,
                              title: (if $w.title == "" then "untitled" else $w.title end),
                              status: (if $w.status == "" then "unknown" else $w.status end),
                              relates_to: $w.rel,
                              github_issues: $w.gh}
                        | if $w.created != "" then .created = $w.created else . end) as $new
                     | .docs[$key] = $new
                     | .findings += (if $e == {} then [{action: "add", id: $key, path: $w.path}]
                                     elif $e != $new then [{action: "update", id: $key, path: $w.path,
                                         fields: ([$new | keys[] | select($e[.] != $new[.])] | join(",")),
                                         was: (($e.path | strings) // "")}]
                                     else [] end)
                     | .findings += (if ($g | length) > 1
                                     then [{action: "duplicate", id: $key, kept: $w.path,
                                            dropped: ([$gpaths[] | select(. != $w.path)] | join(","))}]
                                     else [] end))
                 | ([.docs | to_entries[]
                     | select((.value | objects | .path | strings) as $p
                              | ($fm_id | has($p)) and (($fm_id[$p] | norm) != (.key | norm)))
                     | {action: "prune", id: .key, path: .value.path, has: $fm_id[.value.path]}]) as $pruned
                 | ($pruned | map(.id)) as $pids
                 | .docs |= with_entries(select(.key as $k | ($pids | index($k)) == null))
                 | . as $st
                 | ([$st.docs | to_entries[] | (.value | objects) as $v
                     | (($v.github_issues // []) | if type == "array" then .[] else empty end) as $i
                     | ([.key] + (($v.implements // []) | if type == "array" then . else [.] end))[]
                     | {issue: ($i | tostring | ltrimstr("#")), id: .}]
                    | group_by(.issue) | sort_by(.[0].issue | tonumber? // 0)
                    | map({key: .[0].issue, value: (map(.id) | unique)}) | from_entries) as $rev
                 | (reduce ("PRD", "PRP", "TRP") as $p ($base;
                      ("last_" + ($p | ascii_downcase)) as $ck
                      | ([(($base[$ck] | numbers) // 0)]
                         + [$docs0 | keys[] | cnum($p)] + [$scan[].id | cnum($p)] | max) as $mx
                      | if has($ck) or $mx > 0 then .[$ck] = $mx else . end)
                    | .documents = $st.docs | .github_issues = $rev) as $new_reg
                 | {changed: ($new_reg != $old), registry: $new_reg, docs: ($scan | length),
                    findings: ($st.findings + $pruned)}
               end' > "${rr_tmp}.result"; then
        printf 'CHANGED=false\n'
        rr_finish ERROR 1 "compute_failed: jq could not reconcile ${rr_manifest}"
        return 1
    fi

    rr_report=$(jq -r '
        "DOCS=\(.docs)",
        "CHANGED=\(.changed)",
        "FINDING_COUNT=\(.findings | length)",
        (.findings[] |
          if .action == "prune" then "  - ACTION=prune ID=\(.id) PATH=\(.path) HAS=\(.has)"
          elif .action == "update" then "  - ACTION=update ID=\(.id) PATH=\(.path) FIELDS=\(.fields) WAS=\(.was)"
          elif .action == "duplicate" then "  - ACTION=duplicate ID=\(.id) KEPT=\(.kept) DROPPED=\(.dropped)"
          else "  - ACTION=add ID=\(.id) PATH=\(.path)" end)' "${rr_tmp}.result" 2>/dev/null)
    printf '%s\n' "$rr_report"
    rr_changed=false
    case "$rr_report" in
        *CHANGED=true*) rr_changed=true ;;
    esac
    rr_dups=$(grep -c '^  - ACTION=duplicate' <<<"$rr_report")

    if [ "$rr_mode" = "check" ]; then
        if [ "$rr_changed" = true ]; then
            rr_finish ERROR 1 "registry_drift: id_registry differs from what the engine derives (run --registry-reconcile)"
            return 1
        fi
        if [ "$rr_dups" -gt 0 ]; then
            rr_finish WARN "$rr_dups" "duplicate_id: ${rr_dups} id(s) claimed by more than one document"
            return 0
        fi
        rr_finish OK 0
        return 0
    fi

    if [ "$rr_changed" = true ]; then
        # Re-read the live manifest now, under the lock, and replace only
        # id_registry, so a write to any other key made meanwhile survives.
        if ! { jq --slurpfile reconciled "${rr_tmp}.result" '.id_registry = $reconciled[0].registry' \
                   "$rr_manifest" > "$rr_tmp" && mv "$rr_tmp" "$rr_manifest"; }; then
            rr_finish ERROR 1 "write_failed: could not replace ${rr_manifest}"
            return 1
        fi
    fi
    if [ "$rr_dups" -gt 0 ]; then
        rr_finish WARN "$rr_dups" "duplicate_id: ${rr_dups} id(s) claimed by more than one document"
        return 0
    fi
    rr_finish OK 0
    return 0
)

project_dir="."
run_mode="apply"
reconcile_check=0

while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir)
            if [ $# -lt 2 ]; then
                usage
                exit 2
            fi
            project_dir="$2"
            shift 2
            ;;
        --report)
            run_mode="report"
            shift
            ;;
        --registry-reconcile)
            run_mode="reconcile"
            shift
            ;;
        --check)
            reconcile_check=1
            shift
            ;;
        *)
            printf 'blueprint-autorun.sh: unknown argument: %s\n' "$1" >&2
            usage
            exit 2
            ;;
    esac
done

if [ "$reconcile_check" = 1 ] && [ "$run_mode" != "reconcile" ]; then
    printf 'blueprint-autorun.sh: --check needs --registry-reconcile\n' >&2
    usage
    exit 2
fi

# --registry-reconcile runs at every autonomy level: the write-time hook calls
# it and gates on BLUEPRINT_SKIP_HOOKS itself. The session-start sweep reaches
# the same engine through run_sync_ids, behind the autonomy >= 1 gate below.
if [ "$run_mode" = "reconcile" ]; then
    if [ "$reconcile_check" = 1 ]; then
        registry_reconcile "$project_dir" check
    else
        registry_reconcile "$project_dir" apply
    fi
    exit $?
fi

section_open() { printf '=== BLUEPRINT AUTORUN ===\n'; }
section_close() { printf '=== END BLUEPRINT AUTORUN ===\n'; }

finish() {
    # finish <status> <issue_count> [extra KEY=VALUE lines already printed]
    printf 'STATUS=%s\n' "$1"
    printf 'ISSUE_COUNT=%s\n' "$2"
    section_close
    if [ "$1" = "ERROR" ]; then
        exit 1
    fi
    exit 0
}

section_open
printf 'MODE=%s\n' "$run_mode"

if [ "${BLUEPRINT_AUTORUN_DISABLE:-0}" = "1" ]; then
    printf 'AUTORUN=disabled_by_env\n'
    printf 'DUE_AGENT_TASKS=\n'
    printf 'RAN_COUNT=0\n'
    finish OK 0
fi

if ! command -v jq >/dev/null 2>&1; then
    printf 'AUTORUN=jq_unavailable\n'
    printf 'DUE_AGENT_TASKS=\n'
    printf 'RAN_COUNT=0\n'
    finish OK 0
fi

manifest=""
if [ -f "${project_dir}/docs/blueprint/manifest.json" ]; then
    manifest="${project_dir}/docs/blueprint/manifest.json"
elif [ -f "${project_dir}/docs/blueprint/.manifest.json" ]; then
    manifest="${project_dir}/docs/blueprint/.manifest.json"
fi

if [ -z "$manifest" ]; then
    printf 'AUTORUN=no_manifest\n'
    printf 'DUE_AGENT_TASKS=\n'
    printf 'RAN_COUNT=0\n'
    finish OK 0
fi
printf 'MANIFEST=%s\n' "$manifest"

autonomy_level=$(jq -r '.automation.autonomy_level // 0' "$manifest" 2>/dev/null || echo 0)
case "$autonomy_level" in
    ''|*[!0-9]*) autonomy_level=0 ;;
esac
printf 'AUTONOMY_LEVEL=%s\n' "$autonomy_level"

# Deterministic ISO-8601 UTC -> epoch (BSD fills unspecified fields with the
# current wall clock, so the format string pins every field; see
# .claude/rules/shell-scripting.md "GNU vs BSD Tool Differences").
iso_to_epoch() {
    local iso_ts="$1"
    if date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_ts" "+%s" >/dev/null 2>&1; then
        date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_ts" "+%s" 2>/dev/null
    elif date -u -d "$iso_ts" "+%s" >/dev/null 2>&1; then
        date -u -d "$iso_ts" "+%s" 2>/dev/null
    else
        echo ""
    fi
}

now_epoch=$(date -u +%s)

is_deterministic() {
    case "$1" in
        sync-ids) return 0 ;;
        *) return 1 ;;
    esac
}

# The session-start sweep: the registry engine over the whole tree
# (ADR-0027 Q4, #3550). The write-time hook calls the same engine, so the two
# triggers cannot register a document two ways. The engine writes only when
# id_registry differs, under its lock, by atomic mv; a run killed mid-sweep
# leaves the manifest untouched (its traps remove the lock and temp files).
#
# Prints "<docs_seen> <changed:true|false>".
run_sync_ids() {
    local rr_out rr_rc docs_seen changed
    rr_out=$(registry_reconcile "$project_dir" apply)
    rr_rc=$?
    [ "$rr_rc" -eq 0 ] || return 1
    docs_seen=$(sed -n 's/^DOCS=//p' <<<"$rr_out" | head -n 1)
    changed=$(sed -n 's/^CHANGED=//p' <<<"$rr_out" | head -n 1)
    printf '%s %s' "${docs_seen:-0}" "${changed:-false}"
    return 0
}

# Run state is never written here (ADR-0027 Q3, #3548). A deterministic task
# keeps none: the tracked manifest changes only when id_registry does, so a
# session start on a clean tree leaves it clean. An agent-judgment task's
# last_completed_at/last_result are written only after an explicit run (the
# skill itself, or /blueprint:autopilot after running it).
due_agent_tasks=""
ran_count=0
issue_count=0
overall_status="OK"

while IFS=$'\t' read -r task_name task_enabled task_auto task_schedule task_last; do
    [ -n "$task_name" ] || continue

    if [ "$task_enabled" != "true" ] || [ "$task_auto" != "true" ]; then
        printf 'TASK=%s STATE=skipped REASON=%s\n' "$task_name" \
            "$([ "$task_enabled" != "true" ] && echo disabled || echo manual)"
        continue
    fi

    task_state="not_due"
    case "$task_schedule" in
        on-demand)
            task_state="on_demand"
            ;;
        on-change)
            if is_deterministic "$task_name"; then
                task_state="reconcile"
            else
                task_state="event_driven"
            fi
            ;;
        daily|weekly)
            # A deterministic task keeps no last_completed_at to measure an
            # interval from, so it reconciles on every run like on-change.
            if is_deterministic "$task_name"; then
                task_state="reconcile"
            else
                interval=86400
                [ "$task_schedule" = "weekly" ] && interval=604800
                if [ -z "$task_last" ] || [ "$task_last" = "null" ]; then
                    task_state="due"
                else
                    last_epoch=$(iso_to_epoch "$task_last")
                    if [ -z "$last_epoch" ] || [ $((now_epoch - last_epoch)) -ge "$interval" ]; then
                        task_state="due"
                    fi
                fi
            fi
            ;;
        *)
            task_state="unknown_schedule"
            ;;
    esac

    if [ "$task_state" != "due" ] && [ "$task_state" != "reconcile" ]; then
        printf 'TASK=%s SCHEDULE=%s STATE=%s\n' "$task_name" "$task_schedule" "$task_state"
        continue
    fi

    if is_deterministic "$task_name"; then
        if [ "$run_mode" = "report" ] || [ "$autonomy_level" -lt 1 ]; then
            printf 'TASK=%s KIND=deterministic SCHEDULE=%s STATE=%s\n' "$task_name" "$task_schedule" "$task_state"
            continue
        fi
        case "$task_name" in
            sync-ids)
                sync_out=$(run_sync_ids)
                sync_rc=$?
                docs_count=${sync_out%% *}
                sync_changed=${sync_out##* }
                if [ "$sync_rc" -eq 0 ]; then
                    printf 'TASK=%s KIND=deterministic SCHEDULE=%s STATE=ran DOCS=%s CHANGED=%s\n' \
                        "$task_name" "$task_schedule" "$docs_count" "$sync_changed"
                    ran_count=$((ran_count + 1))
                else
                    printf 'TASK=%s KIND=deterministic SCHEDULE=%s STATE=error\n' \
                        "$task_name" "$task_schedule"
                    issue_count=$((issue_count + 1))
                    overall_status="WARN"
                fi
                ;;
        esac
    else
        printf 'TASK=%s KIND=agent SCHEDULE=%s STATE=due REMEDIATION=/blueprint:%s\n' \
            "$task_name" "$task_schedule" "$task_name"
        if [ -z "$due_agent_tasks" ]; then
            due_agent_tasks="$task_name"
        else
            due_agent_tasks="${due_agent_tasks},${task_name}"
        fi
    fi
done < <(
    jq -r '(.task_registry // {}) | to_entries[] |
           [.key,
            (.value.enabled // false | tostring),
            (.value.auto_run // false | tostring),
            (.value.schedule // "on-demand"),
            (.value.last_completed_at // "null")] | @tsv' \
       "$manifest" 2>/dev/null
)

printf 'DUE_AGENT_TASKS=%s\n' "$due_agent_tasks"
printf 'RAN_COUNT=%s\n' "$ran_count"
finish "$overall_status" "$issue_count"

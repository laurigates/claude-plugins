#!/usr/bin/env bash
# Audit top-level documentation maps for mechanical drift (Layer 1 of #1460).
#
# Seven zero-false-positive checks:
#   1. RULES INDEX  — every .claude/rules/*.md appears in the CLAUDE.md Rules
#      table, and every table entry exists on disk (bidirectional).
#   2. PLUGIN MAPS  — the plugin set agrees across marketplace.json,
#      release-please-config.json, .release-please-manifest.json, the *-plugin
#      directories on disk, and docs/PLUGIN-MAP.md.
#   3. DOC COUNTS   — per-plugin skill/agent counts stated in README.md and
#      docs/PLUGIN-MAP.md match the files on disk, plus the headline totals in
#      the README intro AND the docs/PLUGIN-MAP.md header line ("N plugins and
#      M+ skills").
#   4. DIAGRAM      — node labels in docs/diagrams/plugin-relationships.d2 name a
#      plugin that exists and state a count matching disk. Guards the #1523
#      command-analytics / sync drift class. The rendered .svg is Check 6's job.
#   5. RULE REVIEWED — every .claude/rules/*.md carries a `reviewed:` frontmatter
#      field with a real YYYY-MM-DD value (not the `YYYY-MM-DD` placeholder), so
#      the stale-reviewed-date currency check is measurable (#1851).
#   6. DIAGRAM SVG  — the COMMITTED docs/diagrams/plugin-relationships.svg renders
#      the same per-plugin labels the .d2 source states. Check 4 reads the .d2
#      only, so a .d2 edit committed without re-rendering left the published
#      diagram silently stale at STATUS=OK — exactly what happened after #2450
#      (git 38→42, code-quality 15→16, documentation 5→8) (#2453). ERROR, not
#      WARN: `--strict` is the always-on required gate in plugin-pr-checks.yml,
#      and a staleness check that cannot turn it red is not a gate.
#      KNOWN LIMIT: it compares rendered label TEXT only, so it needs no d2
#      binary and ignores layout/styling churn — but it therefore cannot tell a
#      correctly re-rendered .svg from one hand-patched to agree with the .d2.
#      Re-render with `d2 <src> <out>`; do not hand-edit the .svg.
#   7. README SKILL ROWS — a `/<ns>:<name>` invocation path used as the LEADING
#      table cell of a plugin README row resolves to a skill directory. Guards
#      the phantom-row class (#2453: git-plugin advertised
#      `/git:resolve-conflicts`, which never existed). Resolution is EXACT
#      (`<ns>-<name>/` or `<name>/`) — a shorthand that resolves to nothing is a
#      finding, not a tolerated alias — and namespace-aware: the row is resolved
#      against the plugins that own `<ns>` as well as the README's own plugin, so
#      a legitimate cross-plugin row cannot false-positive.
#      KNOWN LIMIT — coverage is PARTIAL and modest. The leading-cell regex
#      matches ~60 rows across 9 of the 44 plugin READMEs; plugins that catalogue
#      skills as headings instead (agent-patterns' `#### \`/meta:assimilate\``,
#      blueprint, configure, testing, project) are outside it entirely. It is a
#      cheap gate on the rows it does see, not a corpus-wide index audit.
#      The REVERSE direction (a skill directory catalogued in no README row) is
#      deliberately NOT gated: 71 directories corpus-wide are absent from their
#      plugin README today, so an ERROR there would be red on arrival. Fixing
#      that backlog is its own task.
#
# Emits the structured KEY=value / STATUS= convention
# (.claude/rules/structured-script-output.md) so scheduled-audits can roll it up.
#
# Usage:
#   check-docs-index.sh [--project-dir <path>] [--issue-body] [--strict]
#
#   --project-dir   Repo root to audit (default: git toplevel, else cwd)
#   --issue-body    Emit a markdown issue body (empty when clean) instead of the
#                   structured section — for the scheduled-audits workflow
#   --strict        Exit 1 when drift is found (default: always exit 0)
set -uo pipefail

proj_dir=""
emit_issue_body=false
strict=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$2"; shift 2 ;;
    --issue-body) emit_issue_body=true; shift ;;
    --strict) strict=true; shift ;;
    *) shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

claude_md="$proj_dir/CLAUDE.md"
rules_dir="$proj_dir/.claude/rules"
marketplace="$proj_dir/.claude-plugin/marketplace.json"
rp_config="$proj_dir/release-please-config.json"
rp_manifest="$proj_dir/.release-please-manifest.json"
plugin_map="$proj_dir/docs/PLUGIN-MAP.md"
diagram_d2="$proj_dir/docs/diagrams/plugin-relationships.d2"
diagram_svg="$proj_dir/docs/diagrams/plugin-relationships.svg"

issue_count=0
declare -a issues=()

add_issue() {
  # add_issue <severity> <type> <message>
  issues+=("  - SEVERITY=$1 TYPE=$2 MSG=$3")
  issue_count=$((issue_count + 1))
}

# --- Check 1: rules index vs disk ---------------------------------------------
rules_on_disk="$(find "$rules_dir" -maxdepth 1 -name '*.md' -type f 2>/dev/null \
  | sed "s#$rules_dir/##" | sort)"
rules_in_table="$(grep -oE '\.claude/rules/[a-z0-9-]+\.md' "$claude_md" 2>/dev/null \
  | sed 's#.claude/rules/##' | sort -u)"

missing_from_table="$(comm -23 <(printf '%s\n' "$rules_on_disk") <(printf '%s\n' "$rules_in_table"))"
missing_from_disk="$(comm -13 <(printf '%s\n' "$rules_on_disk") <(printf '%s\n' "$rules_in_table"))"

while IFS= read -r rule; do
  [ -n "$rule" ] && add_issue WARN rule_not_indexed "$rule exists but is absent from the CLAUDE.md Rules table"
done <<< "$missing_from_table"

while IFS= read -r rule; do
  [ -n "$rule" ] && add_issue ERROR rule_table_dangling "CLAUDE.md Rules table lists $rule but no such file exists"
done <<< "$missing_from_disk"

rules_disk_count="$(printf '%s\n' "$rules_on_disk" | grep -c . || true)"
rules_table_count="$(printf '%s\n' "$rules_in_table" | grep -c . || true)"

# --- Check 2: plugin maps agree -----------------------------------------------
mkt_set="$(jq -r '.plugins[].name' "$marketplace" 2>/dev/null | sort)"
rp_set="$(jq -r '.packages | keys[]' "$rp_config" 2>/dev/null | grep -v '^\.$' | sort)"
manifest_set="$(jq -r 'keys[]' "$rp_manifest" 2>/dev/null | grep -v '^\.$' | sort)"
disk_set="$(find "$proj_dir" -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' 2>/dev/null \
  | sed "s#$proj_dir/##" | sort)"

compare_sets() {
  # compare_sets <label-a> <set-a> <label-b> <set-b>
  local only_a only_b
  only_a="$(comm -23 <(printf '%s\n' "$2") <(printf '%s\n' "$4"))"
  only_b="$(comm -13 <(printf '%s\n' "$2") <(printf '%s\n' "$4"))"
  while IFS= read -r p; do
    [ -n "$p" ] && add_issue ERROR plugin_map_drift "$p in $1 but missing from $3"
  done <<< "$only_a"
  while IFS= read -r p; do
    [ -n "$p" ] && add_issue ERROR plugin_map_drift "$p in $3 but missing from $1"
  done <<< "$only_b"
}

compare_sets "marketplace.json" "$mkt_set" "release-please-config.json" "$rp_set"
compare_sets "marketplace.json" "$mkt_set" ".release-please-manifest.json" "$manifest_set"
compare_sets "marketplace.json" "$mkt_set" "plugin dirs on disk" "$disk_set"

# PLUGIN-MAP.md is prose, so check presence (substring) rather than exact set.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  grep -q "$p" "$plugin_map" 2>/dev/null || add_issue WARN plugin_map_missing "$p not mentioned in docs/PLUGIN-MAP.md"
done <<< "$mkt_set"

mkt_count="$(printf '%s\n' "$mkt_set" | grep -c . || true)"

# --- Check 3: per-plugin skill/agent counts in README + PLUGIN-MAP -------------
# Each plugin's skill count = number of skill.md files (case-insensitive) under
# <plugin>/skills/; agent count = *.md files under <plugin>/agents/. The README
# and PLUGIN-MAP tables state these as `| **name** | N |` or `| name | N + M
# agent(s) |`. Zero-false-positive: only a table row whose FIRST cell is exactly
# the plugin name (optionally bold) and whose count cell starts with an integer
# is compared. Rows a doc omits (PLUGIN-MAP only covers the tier plugins) are
# skipped, not flagged.
readme_md="$proj_dir/README.md"

skill_count() { find "$proj_dir/$1/skills" -iname 'skill.md' 2>/dev/null | grep -c . || true; }
agent_count() { find "$proj_dir/$1/agents" -name '*.md' -type f 2>/dev/null | grep -c . || true; }

# stated_rows <file> <plugin-name> -> emits "<lineno> <skills> <agents|-1>" per
# matching first-cell row (agents=-1 when the cell states no agent count).
stated_rows() {
  awk -v name="$2" -F'|' '
    NF < 3 { next }
    {
      cell = $2
      gsub(/^[ \t]+|[ \t]+$/, "", cell)
      gsub(/\*\*/, "", cell)
      if (cell != name) next
      cnt = $3
      gsub(/^[ \t]+|[ \t]+$/, "", cnt)
      if (!match(cnt, /^[0-9]+/)) next
      sk = substr(cnt, 1, RLENGTH)
      ag = -1
      if (match(cnt, /\+[ ]*[0-9]+[ ]*agent/)) {
        a = substr(cnt, RSTART, RLENGTH); gsub(/[^0-9]/, "", a); ag = a
      }
      print FNR, sk, ag
    }
  ' "$1"
}

total_skills=0
total_agents=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  cs="$(skill_count "$p")"
  ca="$(agent_count "$p")"
  total_skills=$((total_skills + cs))
  total_agents=$((total_agents + ca))
  for doc in "$readme_md" "$plugin_map"; do
    [ -f "$doc" ] || continue
    docname="$(basename "$doc")"
    while read -r lineno st_sk st_ag; do
      [ -n "$st_sk" ] || continue
      if [ "$st_sk" -ne "$cs" ]; then
        add_issue WARN doc_count_drift "$docname:$lineno states $p has $st_sk skills but $cs exist on disk"
      fi
      if [ "$st_ag" -ne -1 ] && [ "$st_ag" -ne "$ca" ]; then
        add_issue WARN doc_count_drift "$docname:$lineno states $p has $st_ag agents but $ca exist on disk"
      fi
    done <<< "$(stated_rows "$doc" "$p")"
  done
done <<< "$disk_set"

# Headline totals in README intro ("N Claude Code plugins ... and M agents").
if [ -f "$readme_md" ]; then
  hp="$(grep -oE '[0-9]+ Claude Code plugins' "$readme_md" | head -1 | grep -oE '^[0-9]+' || true)"
  if [ -n "$hp" ] && [ "$hp" -ne "$mkt_count" ]; then
    add_issue WARN doc_count_drift "README.md headline states $hp plugins but marketplace lists $mkt_count"
  fi
  ha="$(grep -oE 'and [0-9]+ agents' "$readme_md" | head -1 | grep -oE '[0-9]+' || true)"
  if [ -n "$ha" ] && [ "$ha" -ne "$total_agents" ]; then
    add_issue WARN doc_count_drift "README.md headline states $ha agents but $total_agents exist on disk"
  fi
  hsfloor="$(grep -oE '[0-9]+\+ skills' "$readme_md" | head -1 | grep -oE '^[0-9]+' || true)"
  if [ -n "$hsfloor" ] && [ "$total_skills" -lt "$hsfloor" ]; then
    add_issue WARN doc_count_drift "README.md headline claims ${hsfloor}+ skills but only $total_skills exist on disk"
  fi
fi

# Headline totals in the PLUGIN-MAP.md header ("N plugins and M+ skills").
# The plugin count is exact (must equal marketplace); the skill count is a
# floor ("M+ skills") so disk only has to be >= M. This header line drifted
# silently because nothing parsed it — the README headline guard above did
# not cover PLUGIN-MAP.md. (#1948)
if [ -f "$plugin_map" ]; then
  mp="$(grep -oE '[0-9]+ plugins' "$plugin_map" | head -1 | grep -oE '^[0-9]+' || true)"
  if [ -n "$mp" ] && [ "$mp" -ne "$mkt_count" ]; then
    add_issue WARN doc_count_drift "PLUGIN-MAP.md header states $mp plugins but marketplace lists $mkt_count"
  fi
  mpsfloor="$(grep -oE '[0-9]+\+ skills' "$plugin_map" | head -1 | grep -oE '^[0-9]+' || true)"
  if [ -n "$mpsfloor" ] && [ "$total_skills" -lt "$mpsfloor" ]; then
    add_issue WARN doc_count_drift "PLUGIN-MAP.md header claims ${mpsfloor}+ skills but only $total_skills exist on disk"
  fi
fi

# --- Check 4: plugin-relationships.d2 node labels vs disk ----------------------
# The diagram source states each plugin's count as `label: "<name>\n<N> skills"`
# or `label: "<name>\n<N> skills + <M> agent(s)"`. A node naming a plugin that no
# longer exists on disk is dead (the #1523 command-analytics / sync drift); a node
# whose stated count diverges from disk is stale. The rendered .svg is compared
# separately by Check 6 — this check guards the .d2 source. Zero-false-positive:
# only `label:` lines whose text matches `<name>\n<int> skill` are compared; the
# title and tier-label nodes (no `\nN skill`) are skipped.
diagram_nodes=0
if [ -f "$diagram_d2" ]; then
  while IFS='|' read -r dn_name dn_sk dn_ag; do
    [ -n "$dn_name" ] || continue
    diagram_nodes=$((diagram_nodes + 1))
    dn_dir="${dn_name}-plugin"
    if [ ! -d "$proj_dir/$dn_dir" ]; then
      add_issue ERROR diagram_node_dangling "plugin-relationships.d2 has a '$dn_name' node but $dn_dir does not exist on disk"
      continue
    fi
    cs="$(skill_count "$dn_dir")"
    ca="$(agent_count "$dn_dir")"
    if [ "$dn_sk" -ne "$cs" ]; then
      add_issue WARN diagram_count_drift "plugin-relationships.d2 states $dn_name has $dn_sk skills but $cs exist on disk"
    fi
    if [ "$dn_ag" -ne -1 ] && [ "$dn_ag" -ne "$ca" ]; then
      add_issue WARN diagram_count_drift "plugin-relationships.d2 states $dn_name has $dn_ag agents but $ca exist on disk"
    fi
  done <<< "$(awk '
    match($0, /label: "[a-z0-9-]+\\n[0-9]+ skill/) {
      seg = substr($0, RSTART + 8)            # drop label: "
      q = index(seg, "\\n"); name = substr(seg, 1, q - 1)
      rest = substr(seg, q + 2)               # after \n
      match(rest, /^[0-9]+/); sk = substr(rest, 1, RLENGTH)
      ag = -1
      if (match(rest, /\+[ ]*[0-9]+[ ]*agent/)) {
        a = substr(rest, RSTART, RLENGTH); gsub(/[^0-9]/, "", a); ag = a
      }
      print name "|" sk "|" ag
    }
  ' "$diagram_d2")"
fi

# --- Check 5: rule reviewed: frontmatter presence + placeholder ---------------
# ENFORCE (#1851): every .claude/rules/*.md must carry a `reviewed:` frontmatter
# field, and its value must be a real date, not the `YYYY-MM-DD` placeholder. A
# missing or placeholder value makes the "stale reviewed date" currency check
# unmeasurable. WARN, matching the sibling drift checks (weekly scheduled-audits
# roll-up), never a hard ERROR. Only the file's OWN frontmatter block (leading
# `---` … `---`) is inspected — `YYYY-MM-DD` in a documented body example is not
# flagged.
rules_checked=0
while IFS= read -r rule_file; do
  [ -n "$rule_file" ] || continue
  rules_checked=$((rules_checked + 1))
  rule_name="${rule_file##*/}"
  # reviewed_state: MISSING (no field), PLACEHOLDER (value contains YYYY), or the
  # value itself. awk `exit` always runs END, so carry state in a variable.
  reviewed_state="$(awk '
    NR==1 && $0!="---" { exit }
    NR==1 { infm=1; next }
    infm && /^---$/ { exit }
    infm && /^reviewed:/ {
      val=$0; sub(/^reviewed:[ \t]*/, "", val)
      gsub(/[ \t\r]+$/, "", val)
      found=1
      if (val ~ /YYYY/) state="PLACEHOLDER"; else state=val
      exit
    }
    END { if (!found) print "MISSING"; else print state }
  ' "$rule_file")"

  if [ "$reviewed_state" = "MISSING" ]; then
    add_issue WARN rule_reviewed_missing "$rule_name lacks a reviewed: frontmatter field"
  elif [ "$reviewed_state" = "PLACEHOLDER" ]; then
    add_issue WARN rule_reviewed_placeholder "$rule_name has a reviewed: YYYY-MM-DD placeholder, not a real date"
  fi
done < <(find "$rules_dir" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)

# --- Check 6: committed .svg matches the .d2 source ---------------------------
# The .svg is GENERATED (`d2 <src> <out>`) and must never be hand-edited, but it
# is also COMMITTED — so it is the artefact readers actually see, and a .d2 edit
# landed without re-rendering leaves it stale with nothing to catch it (#2453).
# Compares only the per-plugin node label text ("<N> skills[ + <M> agent(s)]")
# that Check 4 already parses out of the .d2, so it needs no d2 binary and is
# blind to layout/styling churn. ERROR severity so `--strict` — the always-on,
# path-filter-free required step in plugin-pr-checks.yml — actually goes red:
# the PR shape that produced #2453 (edit the .d2, skip the render) must not
# merge green. Degrades silently when either file is absent (…SVG_NODES=0).
diagram_svg_nodes=0
if [ -f "$diagram_d2" ] && [ -f "$diagram_svg" ]; then
  # One "<name>|<label>" row per rendered node, from the d2-emitted tspan pair.
  svg_pairs="$(grep -o '>[a-z0-9-]*</tspan><tspan[^>]*>[0-9]* skill[^<]*</tspan>' "$diagram_svg" 2>/dev/null \
    | sed -E 's#^>([a-z0-9-]*)</tspan><tspan[^>]*>(.*)</tspan>$#\1|\2#')"

  while IFS='|' read -r dn_name dn_label; do
    [ -n "$dn_name" ] || continue
    diagram_svg_nodes=$((diagram_svg_nodes + 1))
    svg_label="$(printf '%s\n' "$svg_pairs" | grep -m1 "^${dn_name}|" | cut -d'|' -f2-)"
    if [ -z "$svg_label" ]; then
      add_issue ERROR diagram_svg_node_missing \
        "plugin-relationships.svg has no '$dn_name' node; re-render with: d2 docs/diagrams/plugin-relationships.d2 docs/diagrams/plugin-relationships.svg"
    elif [ "$svg_label" != "$dn_label" ]; then
      add_issue ERROR diagram_svg_stale \
        "plugin-relationships.svg renders $dn_name as '$svg_label' but the .d2 states '$dn_label'; re-render with: d2 docs/diagrams/plugin-relationships.d2 docs/diagrams/plugin-relationships.svg"
    fi
  done <<< "$(awk '
    match($0, /label: "[a-z0-9-]+\\n[0-9]+ skill/) {
      seg = substr($0, RSTART + 8)            # drop label: "
      q = index(seg, "\\n"); name = substr(seg, 1, q - 1)
      rest = substr(seg, q + 2)               # after \n
      e = index(rest, "\"")                   # up to the closing quote
      if (e > 0) rest = substr(rest, 1, e - 1)
      print name "|" rest
    }
  ' "$diagram_d2")"
fi

# --- Check 7: plugin README `/<ns>:<name>` rows resolve to a skill dir ---------
# A leading-cell invocation path is a claim that the skill is invocable. Two
# deliberate properties, both learned from review:
#   * Resolution is EXACT — `<ns>-<name>/` or `<name>/`, no prefix tolerance. A
#     row whose path resolves to nothing is reported even when a LONGER
#     directory shares its prefix; that shape is the defect, not an alias.
#     (`/evaluate:plugin` vs `evaluate-plugin-batch/` was exactly that, and is
#     fixed in the README rather than tolerated here.)
#   * Resolution is NAMESPACE-AWARE — a row's `<ns>` selects which plugins may
#     satisfy it: the README's own plugin, the `<ns>-plugin` directory, and any
#     plugin already owning skills prefixed `<ns>-`. A legitimate cross-plugin
#     row (git-plugin's README citing `/taskwarrior:task-claim`) therefore
#     resolves instead of hard-ERRORing on a required gate.
# Coverage is partial by construction — see the KNOWN LIMIT in the header.
readme_skill_rows=0
readme_row_plugins=0

# namespace -> owning plugin dirs, from `<ns>-<rest>` skill directory names.
declare -A ns_owner=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ -d "$proj_dir/$p/skills" ] || continue
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    ns="${d%%-*}"
    case " ${ns_owner[$ns]:-} " in
      *" $p "*) ;;
      *) ns_owner[$ns]="${ns_owner[$ns]:-} $p" ;;
    esac
  done < <(find "$proj_dir/$p/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sed 's#.*/##')
done <<< "$disk_set"

while IFS= read -r p; do
  [ -n "$p" ] || continue
  p_readme="$proj_dir/$p/README.md"
  [ -f "$p_readme" ] && [ -d "$proj_dir/$p/skills" ] || continue

  rows="$(grep -oE '^\| *`?/[a-z0-9-]+:[a-z0-9-]+`? *\|' "$p_readme" 2>/dev/null \
    | sed -E 's#^\| *`?/([a-z0-9-]+):([a-z0-9-]+)`? *\|$#\1|\2#' | sort -u)"
  [ -n "$rows" ] && readme_row_plugins=$((readme_row_plugins + 1))

  while IFS='|' read -r row_ns row_name; do
    [ -n "$row_name" ] || continue
    readme_skill_rows=$((readme_skill_rows + 1))

    # Candidate plugins for this row's namespace, own plugin first, deduped.
    cand_plugins=""
    for cp in "$p" "${row_ns}-plugin" ${ns_owner[$row_ns]:-}; do
      [ -d "$proj_dir/$cp/skills" ] || continue
      case " $cand_plugins " in *" $cp "*) continue ;; esac
      cand_plugins="$cand_plugins $cp"
    done

    resolved=false
    for cp in $cand_plugins; do
      for cand in "${row_ns}-${row_name}" "$row_name"; do
        if [ -d "$proj_dir/$cp/skills/$cand" ]; then
          resolved=true
          break 2
        fi
      done
    done
    if [ "$resolved" = false ]; then
      add_issue ERROR readme_row_dangling \
        "$p/README.md lists /$row_ns:$row_name but no matching skill directory exists (searched:$cand_plugins)"
    fi
  done <<< "$rows"
done <<< "$disk_set"

# --- Status -------------------------------------------------------------------
overall_status="OK"
exit_severity=0
for line in "${issues[@]}"; do
  case "$line" in
    *SEVERITY=ERROR*) overall_status="ERROR"; exit_severity=1 ;;
  esac
done
if [ "$overall_status" = "OK" ] && [ "$issue_count" -gt 0 ]; then
  overall_status="WARN"
fi

# --- Output -------------------------------------------------------------------
if [ "$emit_issue_body" = true ]; then
  if [ "$issue_count" -gt 0 ]; then
    echo "## Top-level documentation drift (Layer 1)"
    echo ""
    echo "\`scripts/check-docs-index.sh\` found $issue_count mechanical drift issue(s)."
    echo ""
    echo "| Severity | Type | Detail |"
    echo "|----------|------|--------|"
    for line in "${issues[@]}"; do
      sev="$(printf '%s' "$line" | sed -n 's/.*SEVERITY=\([A-Z]*\).*/\1/p')"
      typ="$(printf '%s' "$line" | sed -n 's/.*TYPE=\([a-z_]*\).*/\1/p')"
      msg="$(printf '%s' "$line" | sed -n 's/.*MSG=//p')"
      echo "| $sev | \`$typ\` | $msg |"
    done
    echo ""
    echo "See \`.claude/rules\` and the Plugin Lifecycle section of the \`/plugin-authoring\` skill. Tracked under the recurring Layer 1 audit (#1460)."
  fi
else
  echo "=== DOCS INDEX AUDIT ==="
  echo "RULES_ON_DISK=$rules_disk_count"
  echo "RULES_IN_TABLE=$rules_table_count"
  echo "MARKETPLACE_PLUGINS=$mkt_count"
  echo "TOTAL_SKILLS=$total_skills"
  echo "TOTAL_AGENTS=$total_agents"
  echo "DIAGRAM_NODES=$diagram_nodes"
  echo "DIAGRAM_SVG_NODES=$diagram_svg_nodes"
  echo "README_SKILL_ROWS=$readme_skill_rows"
  echo "README_ROW_PLUGINS=$readme_row_plugins"
  echo "RULES_CHECKED=$rules_checked"
  echo "STATUS=$overall_status"
  echo "ISSUE_COUNT=$issue_count"
  if [ "$issue_count" -gt 0 ]; then
    echo "ISSUES:"
    printf '%s\n' "${issues[@]}"
  fi
  echo "=== END DOCS INDEX AUDIT ==="
fi

if [ "$strict" = true ]; then
  exit "$exit_severity"
fi
exit 0

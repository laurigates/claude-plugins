#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016   # file-level: `cond && ok … || notok …` is the
# deliberate assertion idiom (ok/notok both exit 0) — see test-check-schema.sh;
# single-quoted `$1+1` is a literal regex, not an expansion.
# Regression tests for blueprint-next-id.sh (#3554).
#
# A document that arrives through git pull/checkout/merge may reach neither
# the write-time hook nor the session-start sweep before the next id is
# assigned, so the `last_*` counter alone can hand out an id already on disk.
# Pins:
#   - next id = max(last_<kind>, highest id of that kind on disk) + 1
#   - ids are read with the shared frontmatter parser (an inline comment or a
#     fenced template does not count)
#   - the assigning skills call the helper and none reads last_prd /
#     last_prp / last_trp to assign
#   - no skill snippet calls a shell helper the skill does not define
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NEXT_ID="${PLUGIN_DIR}/scripts/blueprint-next-id.sh"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

sb=$(mktemp -d)
if [ -z "$sb" ] || [ ! -d "$sb" ]; then
    echo "FATAL: mktemp failed" >&2
    exit 1
fi
trap 'rm -rf "$sb"' EXIT

mkdir -p "$sb/docs/blueprint" "$sb/docs/prps" "$sb/docs/prds" "$sb/docs/trps"
printf '{"id_registry": {"last_prd": 3, "last_prp": 5, "documents": {}}}\n' > "$sb/docs/blueprint/manifest.json"

# A pulled PRP-006 the registry never saw.
printf -- '---\nid: PRP-006  # pulled\nstatus: Ready\n---\n' > "$sb/docs/prps/x.md"
got=$(bash "$NEXT_ID" --kind PRP --project-dir "$sb")
[ "$got" = "PRP-007" ] && ok "PRP: last_prp=5 with PRP-006 on disk -> PRP-007" || notok "PRP: got '$got'"

printf -- '---\nid: PRD-002\nstatus: Draft\n---\n' > "$sb/docs/prds/old.md"
got=$(bash "$NEXT_ID" --kind PRD --project-dir "$sb")
[ "$got" = "PRD-004" ] && ok "PRD: last_prd=3, nothing above 3 on disk -> PRD-004" || notok "PRD: got '$got'"

# No last_trp, no TRP on disk; a fenced template id in a README is not a TRP.
# shellcheck disable=SC2016  # literal markdown fence
printf -- '# TRPs\n\n```markdown\n---\nid: TRP-099\n---\n```\n' > "$sb/docs/trps/README.md"
got=$(bash "$NEXT_ID" --kind TRP --project-dir "$sb")
[ "$got" = "TRP-001" ] && ok "TRP: no counter, no TRP on disk -> TRP-001" || notok "TRP: got '$got'"

# No manifest at all: the disk alone decides.
rm "$sb/docs/blueprint/manifest.json"
got=$(bash "$NEXT_ID" --kind prp --project-dir "$sb")
[ "$got" = "PRP-007" ] && ok "no manifest: disk ids decide (kind is case-insensitive)" || notok "no manifest: got '$got'"

bash "$NEXT_ID" --kind ADR --project-dir "$sb" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 2 ] && ok "an unsupported kind exits 2" || notok "--kind ADR exited $rc"

# The assigning skills call the helper instead of reading the counter.
for skill in document-linking blueprint-prp-create blueprint-derive-tests; do
    body="${PLUGIN_DIR}/skills/${skill}/SKILL.md"
    grep -q 'blueprint-next-id.sh' "$body" && ok "$skill references blueprint-next-id.sh" \
        || notok "$skill does not reference blueprint-next-id.sh"
    # A jq read of the counter (`last_prp // 0`) or "+ 1"/"increment" next to
    # it is a counter-only assignment. Updating the counter after creating a
    # document is still allowed, and so is prose describing the helper's
    # max(counter, disk) + 1.
    counter_lines=$(grep -nE 'last_(prd|prp|trp)' "$body" | grep -v 'max(' | grep -iE '// 0|increment|\+ *1|\$1\+1')
    if [ -n "$counter_lines" ]; then
        notok "$skill still derives the next id from a last_* counter: $(printf '%s' "$counter_lines" | head -3)"
    else
        ok "$skill does not assign from a last_* counter"
    fi
done

# A skill snippet that calls a shell helper must define it in the same skill.
# a08dd479d removed get_next_prd_id/get_next_prp_id but left document-linking's
# ensure_document_id calling them. Calls are `$(name` with an underscore in
# the name, which excludes plain commands such as `$(git` or `$(jq`.
undefined_calls=""
while IFS= read -r skill_dir; do
    md_files=()
    while IFS= read -r md; do md_files+=("$md"); done \
        < <(find "$skill_dir" -name '*.md' -not -path '*/tests/*' | sort)
    [ "${#md_files[@]}" -gt 0 ] || continue
    while IFS= read -r helper; do
        grep -qE "(^|[[:space:]])${helper}\(\)" "${md_files[@]}" \
            || undefined_calls+="${skill_dir#"${PLUGIN_DIR}"/}:${helper} "
    done < <(grep -ohE '\$\([a-z][a-z0-9]*_[a-z0-9_]*' "${md_files[@]}" | cut -c3- | sort -u)
done < <(find "${PLUGIN_DIR}/skills" -mindepth 1 -maxdepth 1 -type d | sort)
if [ -z "$undefined_calls" ]; then
    ok "every helper a skill snippet calls is defined in that skill"
else
    notok "skill snippets call undefined helpers: ${undefined_calls}"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0

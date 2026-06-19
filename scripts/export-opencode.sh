#!/usr/bin/env bash
# export-opencode.sh — project this Claude Code plugin marketplace's skills and
# subagents into OpenCode format via rulesync (https://github.com/dyoshikawa/rulesync).
#
# Source is read-only; output is fully reproducible. Skills convert near-losslessly;
# subagents convert structurally (rulesync drops model/tools/maxTurns — see
# docs/opencode-export.md). Hooks are intentionally NOT exported: Claude Code plugin
# hooks reference ${CLAUDE_PLUGIN_ROOT} scripts that rulesync cannot resolve, and
# OpenCode has no model-evaluation (prompt) hook. Hooks are hand-ported per-plugin.
#
# Source skills keep the compact comma-string `allowed-tools` form; this script
# normalizes them to YAML lists in its disposable staging copy only (rulesync aborts
# on the string form). The source tree is never modified.
#
# Usage: ./scripts/export-opencode.sh [OUTPUT_DIR]   (default: dist/opencode)
set -euo pipefail

export_script_dir="$(cd "$(dirname "$0")" && pwd)"
export_repo_root="$(cd "$export_script_dir/.." && pwd)"
export_out_dir="${1:-$export_repo_root/dist/opencode}"
export_rulesync_version="${RULESYNC_VERSION:-8.28.1}"
export_staging="$(mktemp -d)"
trap 'rm -rf "$export_staging"' EXIT

echo "=== OPENCODE EXPORT ==="
echo "SOURCE=$export_repo_root"
echo "OUTPUT=$export_out_dir"
echo "RULESYNC=$export_rulesync_version"

mkdir -p "$export_staging/.claude/skills" "$export_staging/.claude/agents"

# 1. Flatten skills into the canonical consumer layout rulesync reads.
#    Copy the whole skill directory so REFERENCE.md / scripts/ travel with SKILL.md.
#    Skill directory names are globally unique across plugins (verified), so the flat
#    namespace is collision-free.
#    Canonicalize the skill filename to SKILL.md: 45 source skills are named skill.md
#    (lowercase), which works on case-insensitive macOS but which rulesync matches
#    case-sensitively — left as-is it copies them verbatim instead of converting. The
#    temp-rename dance forces the stored case to SKILL.md on a case-insensitive FS too.
export_skill_count=0
for export_skill_md in "$export_repo_root"/*-plugin/skills/*/SKILL.md; do
    [ -f "$export_skill_md" ] || continue
    export_skill_dir="$(dirname "$export_skill_md")"
    export_skill_dest="$export_staging/.claude/skills/$(basename "$export_skill_dir")"
    cp -R "$export_skill_dir" "$export_skill_dest"
    if [ -e "$export_skill_dest/skill.md" ]; then
        mv "$export_skill_dest/skill.md" "$export_skill_dest/.skill-canon.tmp"
        mv "$export_skill_dest/.skill-canon.tmp" "$export_skill_dest/SKILL.md"
    fi
    export_skill_count=$((export_skill_count + 1))
done

# 2. Flatten subagents.
export_agent_count=0
for export_agent_md in "$export_repo_root"/*-plugin/agents/*.md; do
    [ -f "$export_agent_md" ] || continue
    cp "$export_agent_md" "$export_staging/.claude/agents/"
    export_agent_count=$((export_agent_count + 1))
done

echo "STAGED_SKILLS=$export_skill_count"
echo "STAGED_AGENTS=$export_agent_count"

# 3. Normalize allowed-tools to YAML lists in the staging copy. rulesync's claudecode
#    importer hard-aborts on the comma-string form; YAML-list is valid Claude Code.
#    Runs on the disposable staging tree only — source skills stay in the compact form.
python3 "$export_script_dir/normalize-skill-allowed-tools.py" \
    "$export_staging/.claude/skills"/*/SKILL.md >/dev/null

# 3b. Rewrite each skill's `name` to its directory basename. OpenCode requires
#     name to be [a-z0-9-]+ AND to equal the directory name; a few source skills
#     carry display-style names (UnoCSS) or unprefixed invocation names (refocus
#     in dir project-refocus) that are valid Claude Code but rejected by OpenCode.
#     Staging-only — the source tree keeps its house-style names.
python3 "$export_script_dir/rewrite-skill-name-to-dir.py" \
    "$export_staging/.claude/skills"/*/SKILL.md

# 4. Convert claudecode -> opencode.
( cd "$export_staging" && bunx "rulesync@${export_rulesync_version}" convert \
    --from claudecode --to opencode --features skills,subagents --silent )

# 5. Publish the generated .opencode/ tree to the output directory.
rm -rf "$export_out_dir"
mkdir -p "$export_out_dir"
cp -R "$export_staging/.opencode/." "$export_out_dir/"

export_out_skills="$(find "$export_out_dir/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
export_out_agents="$(find "$export_out_dir/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
echo "OUTPUT_SKILLS=$export_out_skills"
echo "OUTPUT_AGENTS=$export_out_agents"

if [ "$export_out_skills" -eq "$export_skill_count" ] && [ "$export_out_agents" -eq "$export_agent_count" ]; then
    echo "STATUS=OK"
else
    echo "STATUS=WARN (staged/output counts differ — check rulesync output)"
fi
echo "=== END OPENCODE EXPORT ==="

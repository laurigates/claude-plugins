# shellcheck shell=bash
# doc-paths.sh — resolve which project files a tool call changed.
#
# Sourced by blueprint-plugin PostToolUse hooks. Two facts make this necessary:
#
#   * Write/Edit hook payloads carry `tool_input.file_path` as an ABSOLUTE path
#     (Claude Code 2.1.89+), while the hooks compare against `docs/...`. A bare
#     `case "$FILE_PATH" in docs/adrs/*.md` therefore never matched.
#   * Claude Code directs Claude to edit files through Bash in auto and
#     bypassPermissions modes, and a PostToolUse `Write|Edit` hook does not fire
#     for those edits. The Bash payload lists what the command changed in
#     `tool_response.bashEditDiff` (Claude Code 2.1.269+, public beta,
#     best-effort; git-ignored files are not listed).
#
# Paths are compared physically (`pwd -P`): the payload's `cwd` is the resolved
# path (/private/tmp/… on macOS), which a logical CLAUDE_PROJECT_DIR may not be.
#
# Bash 3.2 compatible.

# blueprint_project_root — print the physical project root.
blueprint_project_root() {
    local root="${CLAUDE_PROJECT_DIR:-}"
    if [ -z "$root" ] || [ ! -d "$root" ]; then
        root=$(pwd)
    fi
    (cd "$root" 2>/dev/null && pwd -P)
}

# blueprint_relpath <path> <physical-root> — print <path> relative to the root,
# or nothing when it lies outside. A relative <path> is returned unchanged
# (minus a leading ./): it is already relative to the working directory.
blueprint_relpath() {
    local p="$1" root="$2" dir base phys
    case "$p" in
        '') return 0 ;;
        /*) ;;
        *) printf '%s\n' "${p#./}"; return 0 ;;
    esac
    dir=$(dirname "$p")
    base=$(basename "$p")
    # The file may have been deleted; its directory usually still exists.
    phys=$(cd "$dir" 2>/dev/null && pwd -P) || phys="$dir"
    p="${phys}/${base}"
    case "$p" in
        "$root"/*) printf '%s\n' "${p#"$root"/}" ;;
    esac
}

# blueprint_changed_paths <payload-json> — print each path the tool call
# changed, one per line, as given in the payload (usually absolute).
blueprint_changed_paths() {
    printf '%s' "$1" | jq -r '
        if .tool_name == "Bash" then
            (.tool_response.bashEditDiff // {}) as $d
            | if ($d | type) != "object" or ($d.skipped // false) then empty
              else ((($d.changedFiles // []) + [($d.files // [])[] | .filePath? // empty])
                    | map(select(type == "string")) | unique[])
              end
        else
            (.tool_input.file_path // .tool_input.notebook_path // empty)
        end' 2>/dev/null
}

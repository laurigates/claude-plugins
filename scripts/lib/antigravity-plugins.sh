# antigravity-plugins.sh — shared `--plugin <name>` validation for the
# Antigravity setup scripts (configure-, export-, install-antigravity.sh).
#
# Source it, then call:  agy_require_plugin <repo-root> <name>
# Exits 2 with a hint when <name> is not a plugin directory of this repo, so a
# typo fails loudly instead of registering or exporting nothing.

agy_require_plugin() {
    local agy_root="$1" agy_name="$2"
    case "$agy_name" in
        "" | */* | .*)
            echo "error: invalid plugin name '$agy_name' (expected a directory name like macos-plugin)" >&2
            exit 2
            ;;
    esac
    if [ ! -f "$agy_root/$agy_name/.claude-plugin/plugin.json" ]; then
        echo "error: '$agy_name' is not a plugin in $agy_root (no $agy_name/.claude-plugin/plugin.json)" >&2
        exit 2
    fi
}

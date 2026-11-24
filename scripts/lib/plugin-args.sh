# plugin-args.sh — shared `--plugin <name>` validation for the harness setup
# scripts: Antigravity (configure-, export-, install-antigravity.sh) and
# OpenCode (export-, install-, configure-opencode.sh). The pi Python entry
# points carry the same check as `plugin_name_error`.
#
# Source it, then call:  require_plugin <repo-root> <name>
# Exits 2 with a hint when <name> is not a plugin directory of this repo, so a
# typo fails loudly instead of registering or exporting nothing.

require_plugin() {
    local rp_root="$1" rp_name="$2"
    case "$rp_name" in
        "" | */* | .*)
            echo "error: invalid plugin name '$rp_name' (expected a directory name like macos-plugin)" >&2
            exit 2
            ;;
    esac
    if [ ! -f "$rp_root/$rp_name/.claude-plugin/plugin.json" ]; then
        echo "error: '$rp_name' is not a plugin in $rp_root (no $rp_name/.claude-plugin/plugin.json)" >&2
        exit 2
    fi
}

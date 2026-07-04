#!/usr/bin/env bash
# Prepare the per-arm fake HOME directories for the config-isolation sweep.
#
# Claude Code discovers global config (CLAUDE.md, rules/, skills, hooks) from
# $HOME/.claude — NOT from CLAUDE_CONFIG_DIR (which only relocates session/auth
# storage) and NOT via --bare (which additionally refuses the subscription
# token). So a per-arm $HOME is what actually controls the global config surface.
# Measured, neutral cwd, headless (see docs/config-arms.md):
#   clean        HOME=fh-clean    ~21k ctx   (system prompt + core tools)
#   plugins-only HOME=fh-plugins  ~26k ctx   (+ ~5k marketplace skills, no memory)
#   full         HOME=$REAL_HOME  ~93k ctx   (+ ~67k global memory + hooks)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
base="$root/.arm-configs"
src_plugins="$HOME/.claude/plugins"
src_settings="$HOME/.claude/settings.json"

[ -d "$src_plugins" ] || { echo "ERROR: $src_plugins not found" >&2; exit 1; }
[ -f "$src_settings" ] || { echo "ERROR: $src_settings not found" >&2; exit 1; }

# clean: an empty fake HOME — no memory, no skills, no plugins.
rm -rf "$base/fh-clean"
mkdir -p "$base/fh-clean/.claude"

# plugins-only: fake HOME whose .claude symlinks the real plugin cache/registry
# and carries the same enabledPlugins + env, but has NO CLAUDE.md and NO rules/.
# => marketplace skills without the global memory (cloud/CI parity).
rm -rf "$base/fh-plugins"
mkdir -p "$base/fh-plugins/.claude"
ln -s "$src_plugins" "$base/fh-plugins/.claude/plugins"
jq '{enabledPlugins, env}' "$src_settings" > "$base/fh-plugins/.claude/settings.json"

n_plugins="$(jq -r '.enabledPlugins // {} | to_entries | map(select(.value)) | length' "$base/fh-plugins/.claude/settings.json")"
echo "[arm-prep] fake HOMEs ready under $base"
echo "[arm-prep]   fh-clean:   empty .claude (no memory, no skills)"
echo "[arm-prep]   fh-plugins: $n_plugins plugins enabled, no CLAUDE.md/rules"
echo "[arm-prep]   full arm uses the real \$HOME ($HOME)"

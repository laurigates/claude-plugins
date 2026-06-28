#!/usr/bin/env bash
# install-hooks.sh — copy the opt-in taskwarrior native hooks into the user's
# taskwarrior hooks directory. Invoked by /taskwarrior:install-native-hooks
# ONLY on explicit user request — never by chezmoi apply or a SessionStart hook.
#
# Resolves the hooks dir from taskwarrior's own config (data.location/hooks),
# falling back to ~/.task/hooks, and copies the on-add / on-modify templates
# with the execute bit set.
#
# Flags:
#   --templates-dir=<dir>  Directory holding the template hook files (required)
#   --check                Report what would be installed without copying
#   --uninstall            Remove the plugin's hooks instead of installing
#
# Output: structured KEY=VALUE block. Exit 0 on success, 1 on error.

set -uo pipefail

tmpl_dir=""
mode="install"
while [ $# -gt 0 ]; do
  case "$1" in
    --templates-dir=*) tmpl_dir="${1#*=}" ;;
    --templates-dir) shift; tmpl_dir="${1:-}" ;;
    --check) mode="check" ;;
    --uninstall) mode="uninstall" ;;
    *) ;;
  esac
  shift
done

echo "=== TASKWARRIOR NATIVE HOOKS ==="

if ! command -v task >/dev/null 2>&1; then
  echo "TASK_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "=== END TASKWARRIOR NATIVE HOOKS ==="
  exit 1
fi

# Resolve hooks dir: <data.location>/hooks, expanding a leading ~.
data_loc=$(task _get rc.data.location 2>/dev/null || true)
case "$data_loc" in
  "~"/*) data_loc="${HOME}/${data_loc#~/}" ;;
  "~") data_loc="${HOME}" ;;
esac
[ -z "$data_loc" ] && data_loc="${HOME}/.task"
hooks_dir="${data_loc}/hooks"
echo "HOOKS_DIR=${hooks_dir}"

hook_names=(on-add-taskwarrior-plugin on-modify-taskwarrior-plugin on-exit-taskwarrior-plugin)

if [ "$mode" = "uninstall" ]; then
  removed=0
  for h in "${hook_names[@]}"; do
    if [ -e "${hooks_dir}/${h}" ]; then
      rm -f "${hooks_dir}/${h}" && removed=$((removed + 1))
    fi
  done
  echo "REMOVED=${removed}"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END TASKWARRIOR NATIVE HOOKS ==="
  exit 0
fi

if [ "$mode" = "check" ]; then
  echo "MODE=check"
  for h in "${hook_names[@]}"; do
    present=$([ -e "${hooks_dir}/${h}" ] && echo present || echo absent)
    echo "HOOK ${h}=${present}"
  done
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END TASKWARRIOR NATIVE HOOKS ==="
  exit 0
fi

if [ -z "$tmpl_dir" ] || [ ! -d "$tmpl_dir" ]; then
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=templates_missing MSG=pass --templates-dir pointing at the skill templates/ dir"
  echo "=== END TASKWARRIOR NATIVE HOOKS ==="
  exit 1
fi

mkdir -p "$hooks_dir" 2>/dev/null || true
installed=0
failures=0
for h in "${hook_names[@]}"; do
  if [ ! -f "${tmpl_dir}/${h}" ]; then
    failures=$((failures + 1))
    continue
  fi
  if cp "${tmpl_dir}/${h}" "${hooks_dir}/${h}" && chmod +x "${hooks_dir}/${h}"; then
    installed=$((installed + 1))
  else
    failures=$((failures + 1))
  fi
done

echo "INSTALLED=${installed}"
if [ "$failures" -gt 0 ]; then
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=${failures}"
else
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
fi
echo "=== END TASKWARRIOR NATIVE HOOKS ==="
[ "$failures" -eq 0 ]

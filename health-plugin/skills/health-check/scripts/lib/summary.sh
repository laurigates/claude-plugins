#!/usr/bin/env bash
# Shared summary emitter for the health-check scripts
# (.claude/rules/structured-script-output.md).
#
# emit_summary <status> <rows>
#   <status> OK | WARN | ERROR
#   <rows>   newline-separated "  - SEVERITY=<S> TYPE=<T> [KEY=value ...] [MSG=...]"
#            lines; blank lines are dropped.
#
# Prints, in order:
#   STATUS=<status>
#   REASON=<TYPE>: <MSG>[ (+N more)]   on WARN/ERROR only, from the first row
#                                      whose SEVERITY equals <status>; a row
#                                      with no MSG= contributes its other fields
#   ISSUE_COUNT=<rows>                 always equal to the rows under ISSUES:
#   ISSUES: and the rows               when there is at least one row
#
# Bash 3.2 safe: no associative arrays, no mapfile, and no pipe into an
# early-closing reader (here-strings instead; see shell-scripting.md).

emit_summary() {
  local summary_status="$1"
  local summary_rows
  summary_rows=$(sed '/^[[:space:]]*$/d' <<<"$2")
  local summary_count=0
  if [ -n "$summary_rows" ]; then
    summary_count=$(wc -l <<<"$summary_rows" | tr -d ' ')
  fi

  echo "STATUS=${summary_status}"
  if [ "$summary_status" != "OK" ]; then
    local first_row row_type row_msg reason_text
    first_row=$(grep -m1 -- "SEVERITY=${summary_status} " <<<"$summary_rows" || true)
    [ -z "$first_row" ] && first_row=$(head -n1 <<<"$summary_rows")
    row_type=$(sed -n 's/.*TYPE=\([^ ]*\).*/\1/p' <<<"$first_row")
    # shellcheck disable=SC2001  # the anchored two-field strip needs a regex
    case "$first_row" in
      *" MSG="*) row_msg="${first_row#* MSG=}" ;;
      *) row_msg=$(sed -e 's/^[[:space:]]*- SEVERITY=[^ ]* TYPE=[^ ]* *//' <<<"$first_row") ;;
    esac
    reason_text="${row_type:-unknown}: ${row_msg}"
    reason_text=$(tr -s '[:space:]' ' ' <<<"$reason_text")
    reason_text="${reason_text% }"
    reason_text="${reason_text:0:180}"
    [ "$summary_count" -gt 1 ] && reason_text="${reason_text} (+$((summary_count - 1)) more)"
    echo "REASON=${reason_text}"
  fi
  echo "ISSUE_COUNT=${summary_count}"
  if [ "$summary_count" -gt 0 ]; then
    echo "ISSUES:"
    printf '%s\n' "$summary_rows"
  fi
}

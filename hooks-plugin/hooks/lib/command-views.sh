#!/usr/bin/env bash
# command-views.sh — shared "what would the shell actually EXECUTE?" projections
# for Bash-command hooks.
#
# Usage:
#   # shellcheck source=lib/command-views.sh
#   . "$(dirname "$0")/lib/command-views.sh"
#   COMMAND_SHELL_ONLY=$(command_shell_only "$COMMAND")
#
# A hook that pattern-matches a Bash command string is really asking one
# question: does this command DO the thing, or does it merely CONTAIN text that
# describes the thing? Two forms of "text that isn't shell" recur often enough to
# deserve one implementation:
#
#   - heredoc bodies — `gh pr create --body-file - <<EOF … EOF`, where the body
#     is documentation and routinely quotes example commands, log excerpts, or
#     markdown tables
#   - trailing `#` comments — an explanatory aside on an otherwise real command
#
# Both matter most for `^`-anchored detectors, because `^` in grep anchors to the
# start of every LINE, not the start of the command. In a multi-line command a
# heredoc-BODY line beginning with a watched word is therefore matched as if it
# were the command itself. Per-line anchoring is otherwise correct and is
# preserved here: a genuine command on line 2 of a multi-line Bash call IS the
# start of a command and must still match.
#
# ── Why this exists alongside bash-antipatterns.sh's own inline copy ─────────
#
# `bash-antipatterns.sh` computes the identical projection inline and does NOT
# source this file, deliberately. Its safety blocks (curl|bash, chmod 777,
# git add -A, git reset --hard, …) are documented to fire in EVERY context and
# must not depend on a file that could be missing from a partial deployment; a
# hook that fails to source its library and exits non-zero is a worse outcome
# there than a duplicated awk program. This library is therefore the shared home
# for NON-safety consumers — currently `bash-antipatterns-teach.sh`.
#
# The two copies are kept honest behaviourally, not textually:
# test-bash-antipatterns-teach.sh pins the heredoc-body and trailing-comment
# shapes for the teach hook, and test-bash-antipatterns.sh pins them for the
# safety hook (issues #2106, #2431, #2518).
#
# Shell options: both current consumers `set -euo pipefail` BEFORE sourcing, so
# the line below is a no-op for them. It exists because lint-shell-scripts.sh
# requires `set` flags on every file under a hooks/ directory. A future consumer
# wanting different options must set them AFTER sourcing.
set -euo pipefail

# Strip heredoc body content, keeping the heredoc-OPENING line and everything
# from the terminator onward.
#
# The awk program walks the command line-by-line. When it sees `<<DELIM` it
# enters heredoc mode and suppresses subsequent lines until it sees a line
# matching DELIM. The opening line itself is still printed, so a real command
# sharing that line (`grep -rn foo src/ && gh pr create --body-file - <<EOF`)
# still matches, as does every line after the terminator.
strip_heredoc_bodies() {
    printf '%s\n' "$1" | awk '
    BEGIN { ih = 0 }
    ih == 0 {
        if (match($0, /<<-?[[:space:]]*[^[:space:]]*[A-Za-z_][A-Za-z_0-9]*/)) {
            s = substr($0, RSTART)
            gsub(/<<-?[[:space:]]*/, "", s)
            gsub(/^[^A-Za-z_]+/, "", s)
            gsub(/[^A-Za-z_0-9].*/, "", s)
            if (s != "") { delim = s; ih = 1 }
            print; next
        }
        print; next
    }
    ih == 1 {
        t = $0; gsub(/^[[:space:]]+/, "", t); gsub(/[[:space:]]+$/, "", t)
        if (t == delim) { ih = 0 }
    }
'
}

# Strip trailing shell comments (an unquoted `#` at a word boundary through end
# of line).
#
# A `#` starts a comment ONLY when it is at the start of the line OR immediately
# preceded by whitespace or a shell metacharacter (`;`, `|`, `&`, `(`), AND is
# not inside single or double quotes. A `#` glued to a preceding word char
# (`http://x#frag`, `foo#bar`) is part of a token, and a `#` inside quotes
# (`echo "# not a comment"`) is literal text — neither is stripped. Quote state
# is tracked per line (a shell comment is a per-line construct), so an unbalanced
# quote on one line cannot swallow the next. The single-quote character is passed
# in via -v SQ so the awk program can stay single-quoted for the shell.
strip_trailing_comments() {
    printf '%s\n' "$1" | awk -v SQ="'" '
    {
        line = $0
        n = length(line)
        in_s = 0   # inside single quotes
        in_d = 0   # inside double quotes
        cut = 0
        for (i = 1; i <= n; i++) {
            c = substr(line, i, 1)
            if (in_s == 1) {
                if (c == SQ) in_s = 0
            } else if (in_d == 1) {
                if (c == "\"") in_d = 0
            } else if (c == SQ) {
                in_s = 1
            } else if (c == "\"") {
                in_d = 1
            } else if (c == "#") {
                if (i == 1) { cut = i; break }
                p = substr(line, i - 1, 1)
                if (p == " " || p == "\t" || p == ";" || p == "|" || p == "&" || p == "(") { cut = i; break }
            }
        }
        if (cut > 0) print substr(line, 1, cut - 1); else print line
    }'
}

# The composed view every non-safety detector should scan: heredoc bodies gone,
# then trailing comments gone.
#
# Order matters. Comment removal runs AFTER heredoc stripping (not before) so it
# only ever touches executable command text — never a heredoc body line (already
# gone) or its closing delimiter, which may legitimately contain a `#`.
command_shell_only() {
    strip_trailing_comments "$(strip_heredoc_bodies "$1")"
}

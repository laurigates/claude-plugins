#!/usr/bin/env bash
# PreToolUse hook for Bash tool - blocks dangerous shell commands.
#
# The SAFETY / CORRECTNESS tier split out of bash-antipatterns.sh (issue #2788):
# broad staging (git add -A / --all / .), chained index-modifying git commands
# (index.lock races), git reset --hard, the git push -u colon-refspec footgun,
# network content piped to a shell (curl|bash), fork bombs, chmod 777 and writes
# to block devices.
#
# Every detector here is pure regex/awk and fires in EVERY context (sandboxes,
# subagents, the pi export): none depends on ast-grep or any other optional
# binary. The STYLE tier (cat/head/tail reads, echo/printf/cat writes, sed -i,
# the awk-to-file and commit-message-file reminders, timeout, grep-chain
# test-output scrapes) stays in bash-antipatterns.sh, whose remedies name Claude
# Code's own tools (Read, Edit, Write).
#
# Keeping the two tiers in separate scripts lets the pi safety-hook bridge
# (scripts/generate-pi-hook-extension.py, PI_SAFETY_ALLOWLIST) export this one by
# name without pushing Claude-Code-specific tool advice onto another harness.
#
# The preprocessing below (heredoc stripping, trailing-comment stripping, the
# quote mask) is an INLINE copy of the projections bash-antipatterns.sh and
# lib/command-views.sh also compute. It is deliberately not sourced from lib/: a
# safety hook must not depend on a file a partial deployment could be missing
# (lib/command-views.sh's header records the same policy). The copies are pinned
# behaviourally by test-bash-safety.sh and test-bash-antipatterns.sh, and the
# LC_ALL=C walker assertion (#3313) scans every copy.


set -euo pipefail

# Read the JSON input from stdin
INPUT=$(cat)

# Extract the command from the tool input
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# If no command, allow it
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Strip trailing shell comments (an unquoted `#` at a word boundary through end
# of line) from the scanned view of the command, so a tool idiom that appears
# only inside a `# comment` — documentation prose, an explanatory aside such as
# `python3 … # /tmp is allowed for sed -i` — is not mistaken for an executed
# command (issue #2106). The detectors below care about what the shell would
# EXECUTE, and the shell discards comments before executing; this is the same
# class as the echo/printf quoted-`>` false positives (#1701/#1721/#1722) and
# the ls demotion (#2036).
#
# A `#` starts a comment ONLY when it is at the start of the line OR immediately
# preceded by whitespace or a shell metacharacter (`;`, `|`, `&`, `(`), AND is
# not inside single or double quotes. A `#` glued to a preceding word char
# (`http://x#frag`, `foo#bar`) is part of a token, and a `#` inside quotes
# (`echo "# not a comment"`) is literal text — neither is stripped. Quote state
# is tracked per line (a shell comment is a per-line construct), so an unbalanced
# quote on one line cannot swallow the next. The single-quote character is passed
# in via -v SQ so the awk program can stay single-quoted for the shell.
#
# LC_ALL=C (issue #3313): this and every other per-character `substr` walker in
# this file runs in the C locale. macOS BSD awk in a UTF-8 locale fails on
# unquoted non-ASCII input (`echo naïve`) with `awk: towc: multibyte conversion
# failure`, and the hook then rejects the command. Every character these
# programs test for is ASCII, so byte-wise walking detects the same things.
# test-bash-antipatterns.sh asserts the prefix statically.
strip_trailing_comments() {
    printf '%s\n' "$1" | LC_ALL=C awk -v SQ="'" '
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

# Blank the CONTENT of every quoted span, keeping the quote characters, the span
# length, and any `$` inside it. Same per-line `in_s`/`in_d` scanner as
# strip_trailing_comments above — generalised here into a second consumer so the
# regex detectors that must tell "a shell operator" from "a character inside a
# quoted argument" get a quote-STATE-aware view instead of another naive
# pre-stripping pass. A `sed "s/'[^']*'/''/g"` cannot do this job: an odd
# apostrophe earlier on the line (`printf "it's done"`) or the `'\''` re-quoting
# idiom desynchronises it and it swallows the rest of the line, silently
# disarming whatever detector reads the view. bash-antipatterns.sh's header
# (#1701, #1721, #1722, #1848, #1900, #2052, #2058) is a list of exactly that
# mistake.
#
# What survives, and why:
#   - the quote characters themselves — the redirect STRUCTURE
#     (`awk '...' f > "$o"` becomes `awk '____' f > "$_"`) has to stay readable
#   - one FILL char per masked char — offsets stay aligned, so a regex that
#     cares about what sits immediately after `>` still sees the same position
#   - `$` — the "is the redirect target a variable?" test keys on a `$` right
#     after the opening quote, and masking it would silently change that test
# Everything else inside quotes — `>`, `|`, `;`, `&`, `(`, flag-looking words —
# becomes FILL, because inside quotes it is text, not shell syntax.
#
# Backslash handling matches the shell: outside quotes and inside double quotes a
# backslash escapes the next character (so `\'` and `\"` do not toggle state);
# inside single quotes it is literal. Quote state is tracked per line, so an
# unbalanced quote on one line cannot swallow the next.
mask_quoted_content() {
    printf '%s\n' "$1" | LC_ALL=C awk -v SQ="'" -v FILL="_" '
    {
        line = $0
        n = length(line)
        in_s = 0   # inside single quotes
        in_d = 0   # inside double quotes
        out = ""
        for (i = 1; i <= n; i++) {
            c = substr(line, i, 1)
            if (in_s == 1) {
                if (c == SQ) { in_s = 0; out = out c }
                else if (c == "$") { out = out c }
                else { out = out FILL }
            } else if (in_d == 1) {
                if (c == "\\" && i < n) { out = out FILL FILL; i++ }
                else if (c == "\"") { in_d = 0; out = out c }
                else if (c == "$") { out = out c }
                else { out = out FILL }
            } else if (c == "\\" && i < n) {
                out = out c substr(line, i + 1, 1); i++
            } else if (c == SQ) {
                in_s = 1; out = out c
            } else if (c == "\"") {
                in_d = 1; out = out c
            } else {
                out = out c
            }
        }
        print out
    }'
}

# Strip heredoc body content up front so the regex detectors below that scan the
# whole command string don't false-positive on literal text inside a heredoc
# body. The main offender is `gh pr create --body "$(cat <<'EOF' ... EOF)"` whose
# body may contain example shell commands that are documentation, not executable
# code. (Consumed here by the three `^`-anchored blocks — git add -A, git reset
# --hard, git push -u — and, via COMMAND_NO_STRINGS, the git-chain block.)
#
# `^`-ANCHORED DETECTORS MUST SCAN THIS VIEW (issue #2431).
#
# `^` in grep anchors to the start of every LINE, not the start of the command.
# In a multi-line command a heredoc BODY line that happens to begin with a
# watched word is therefore matched as if it were the command itself. The
# reported break: a `git commit -F - <<EOF` whose message described a
# *connection timeout* was blocked with "REMINDER: The 'timeout' command is
# usually unnecessary — remove the timeout wrapper". There was no wrapper; the
# word was prose in the commit message. Same shape for `git add -A` /
# `git reset --hard` / `git push -u …` documented inside an issue or PR body.
#
# The per-line anchoring itself is correct and is preserved: a genuine command on
# line 2 of a multi-line Bash call IS the start of a command and must still be
# caught. Only heredoc-body lines are removed from the scanned view.
#
# The awk program walks the command line-by-line. When it sees `<<DELIM` it
# enters heredoc mode and suppresses subsequent lines until it sees a line
# matching DELIM. The heredoc-opening line itself is still printed, so a real
# command sharing that line (and every line after the terminator) still matches.
COMMAND_NO_HEREDOC=$(echo "$COMMAND" | LC_ALL=C awk '
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
')

# Strip trailing `#` comments from the heredoc-stripped view (issue #2106). Done
# AFTER heredoc stripping (not before) so comment removal only ever touches the
# executable command text that survives heredoc stripping — never a heredoc body
# line (already gone) or its closing delimiter. Because COMMAND_NO_STRINGS
# derives from COMMAND_SHELL_ONLY, every detector keyed off those views (the
# `^`-anchored git blocks and the git chains) becomes comment-immune in one place.
COMMAND_SHELL_ONLY=$(strip_trailing_comments "$COMMAND_NO_HEREDOC")

# A further-stripped view with quoted-string literals removed (on top of the
# heredoc stripping above). The git index-lock chain detector keys off *content
# tokens* that must survive as real operands, not literal text inside a quoted
# `--body`/`--title` argument — e.g. a `gh issue create --body "... git add &&
# git commit ..."` that merely documents a chain (issue #1587).
# shellcheck disable=SC2001  # bash pattern substitution can't do `[^']*` char class
COMMAND_NO_STRINGS=$(echo "$COMMAND_SHELL_ONLY" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")

# Function to output a blocking message (exit code 2 = blocking error)
block() {
    echo "$1" >&2
    exit 2
}

# Check for broad git staging commands (git add -A, git add --all, git add .)
# These can accidentally include sensitive files (.env, credentials) or large binaries.
# Pattern handles git global flags like -C <path> before the subcommand.
#
# Scans COMMAND_SHELL_ONLY (issue #2431): `^` matches the start of every LINE, so
# a heredoc-body line reading "git add -A is discouraged because…" — prose in a
# commit message or issue body — was blocked as if it staged anything. A genuine
# `git add -A` on its own line of a multi-line command is still caught.
if grep -Eq '^\s*git\s+(.+\s+)?add\s+(-A|--all|\.(\s|$))' <<<"$COMMAND_SHELL_ONLY"; then
    block "REMINDER: Avoid broad staging commands like 'git add -A', 'git add --all', or 'git add .'.
These can accidentally include sensitive files (.env, credentials) or large binaries.

Instead, stage specific files by name:
  git add src/file1.ts src/file2.ts

Or review what would be staged first:
  git status --porcelain"
fi

# Check for chained git commands where BOTH sides modify the index (git X && git Y)
# index.lock contention needs two writers: a single index-modifying command chained
# to a read-only one (git add file && git status) cannot race, because git status
# takes no lock that git add has not already released.
# Index-modifying commands: add, commit, rm, mv, reset (not read-only commands like status/diff/log).
# So the detector requires an index-modifying subcommand on BOTH sides of the &&;
# `git add … && git status --short` (the stage-then-verify idiom) is not a target.
# The fix is to run the two index-modifying git commands as separate Bash calls.
#
# Uses COMMAND_NO_STRINGS (heredoc body AND quoted-string literals stripped) so
# that example shell snippets inside a `gh` body/title do not trigger a false
# positive. A heredoc body (`gh pr create --body "$(cat <<EOF ... EOF)"`) OR a
# plain quoted argument (`gh issue create --body "...git add && git commit..."`)
# that merely *documents* a git chain is data, not an executed command, and must
# pass — issue #1587's "patterns matched inside quoted strings" false positive.
# This is a reminder about index.lock races, not a security control, so stripping
# quoted strings cannot create a dangerous bypass.
INDEX_MODIFYING='(add|commit|rm|mv|reset)'
if grep -Eq "git\\s+${INDEX_MODIFYING}\\b.*&&.*git\\s+${INDEX_MODIFYING}\\b" <<<"$COMMAND_NO_STRINGS"; then
    block "REMINDER: Chaining git commands with '&&' can cause index.lock race conditions.
The lock file from an index-modifying command (add, commit, rm, mv, reset) may not be
released before the next command tries to acquire it.
Instead of: git add A && git add B   (or: git add . && git commit -m 'msg')
Use this sequence, one Bash tool call per step:
1. git status --short            (confirm which paths are present and changed)
2. git add -- A B C              (ONE git add for all the confirmed-present paths)
3. git commit -m 'msg'           (a separate call, never chained to the add)
Never repeat 'git add' in a chain: list every path in the single 'git add --' call.
This avoids race conditions and is more reliable.
This fires only when BOTH chained commands modify the index (add, commit, rm, mv,
reset). Chaining one of those to a read-only git command — 'git add f && git
status --short', 'git fetch && git switch -c b && git add f' — is allowed."
fi

# Check for git reset --hard (destructive operation, usually unnecessary)
# After pushing commits to a PR branch, agents sometimes think they need to reset main.
# However, once the PR is merged, git pull will cleanly resolve the situation.
# Exclude heredocs (<<) so commit messages mentioning "git reset" don't trigger this.
#
# The positive match scans COMMAND_SHELL_ONLY (issue #2431) so a heredoc-body
# line beginning with `git reset --hard` is not read as the command. The blunt
# "any `<<` anywhere exempts" clause is kept as-is on the raw command: it is the
# pre-existing (looser) behaviour and narrowing it here would silently widen the
# block, which is out of scope for a false-positive fix.
if grep -Eq '^\s*git\s+reset\s+--hard' <<<"$COMMAND_SHELL_ONLY" && \
   ! grep -Eq '<<' <<<"$COMMAND"; then
    block "REMINDER: 'git reset --hard' is destructive and usually unnecessary.

COMMON SCENARIO - Accidentally committed to main, then pushed to a PR branch:
Once the PR is merged on GitHub, the local main branch resolves itself cleanly
when you run 'git pull'. Wait for the merge, then pull.

Use these alternatives instead:
- Sync with remote after PR merge: use 'git pull' - it resolves everything
- Discard uncommitted changes: use 'git checkout -- <file>' or 'git restore <file>'
- Undo a local commit (not pushed): use 'git reset --soft HEAD~1' (keeps changes staged)
- Switch branches cleanly: use 'git stash' then 'git checkout <branch>'

FOR THE 'ACCIDENTAL COMMIT TO MAIN' CASE: Wait for the PR to merge, then
'git pull' on main will fast-forward to include your commits. Problem solved.

IF THIS COMMAND IS TRULY REQUIRED (rare - corrupted git state):
Ask the user to run it manually with:
1. The exact command: $COMMAND
2. Why it's needed for this specific situation
3. What alternatives you tried"
fi

# Check for git push -u with a COLON refspec whose source is the protected
# current branch — `git push -u origin main:feature/x` sets main's upstream to
# origin/feature/x, which is wrong. The recommended main-branch-dev push
# (git push origin main:feature/x) should carry NO -u.
#
# The no-colon form `git push -u origin feat/x` is intentionally NOT matched:
# it pushes the local feat/x ref and sets feat/x's upstream, never touching the
# current branch — the old detector wrongly blocked it on a false "sets main's
# tracking" premise, the same legitimate pattern as issue #1600.
#
# All four reads use COMMAND_SHELL_ONLY (issue #2431) so a heredoc-body line
# documenting the footgun — an issue body whose repro section literally reads
# `git push -u origin main:feat/x` — is not mistaken for the executed push. The
# guard conditions and the refspec extraction must share ONE view: under
# `set -e`, a `PUSH_REFSPEC=$(… grep -oE …)` that finds nothing exits non-zero
# and aborts the hook, so a guard matching a view the extraction doesn't would
# turn a false positive into a hook crash.
if grep -Eq '^\s*git\s+push\b' <<<"$COMMAND_SHELL_ONLY" && \
   grep -Eq '(\s-[a-zA-Z]*u[a-zA-Z]*\b|--set-upstream\b)' <<<"$COMMAND_SHELL_ONLY" && \
   grep -Eq '\sorigin\s+[a-zA-Z0-9._/@-]+:[a-zA-Z0-9._/-]+' <<<"$COMMAND_SHELL_ONLY"; then
    PUSH_REFSPEC=$(echo "$COMMAND_SHELL_ONLY" | grep -oE 'origin\s+[a-zA-Z0-9._/@-]+:[a-zA-Z0-9._/-]+' | awk '{print $2}')
    PUSH_SRC=${PUSH_REFSPEC%%:*}
    PUSH_DST=${PUSH_REFSPEC#*:}
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
    if [ -n "$CURRENT_BRANCH" ] && [ "$PUSH_SRC" = "$CURRENT_BRANCH" ] && \
       [ "$PUSH_SRC" != "$PUSH_DST" ] && \
       { [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; }; then
        block "REMINDER: 'git push -u origin $PUSH_SRC:$PUSH_DST' will set $CURRENT_BRANCH to track origin/$PUSH_DST instead of origin/$CURRENT_BRANCH.

This is the main-branch development pattern: push to a remote feature branch WITHOUT -u:
  git push origin $CURRENT_BRANCH:$PUSH_DST

The -u flag is only correct when local and remote branch names match:
  git push -u origin $CURRENT_BRANCH  (pushes $CURRENT_BRANCH to origin/$CURRENT_BRANCH)"
    fi
fi

# Check for piped execution from network (curl/wget piped to shell) — issue #3178.
#
# Pure regex/awk on purpose: this is a SAFETY block, so it must fire where
# ast-grep is unavailable (.claude/rules/bash-tool-replacements.md). Three
# narrowings over the original bare-substring match, none of which masks a
# real execution (the third, #3186, follows the heredoc awk):
#
#   1. The shell must be a whole command word right after a real pipe (`|` or
#      `|&`), optionally as an absolute path (`| /bin/bash`). `|short` inside a
#      quoted `grep -E '(char|short)'` alternation, or `| shellcheck`, no longer
#      matches. `sudo` stays covered as a word (`| sudo bash`, `| sudo tee`).
#   2. Heredoc bodies are dropped only when the heredoc feeds a pure data sink
#      (strip_sink_heredoc_bodies, below; #3363 widened it to the chmod 777,
#      fork-bomb and block-device regexes too, which read the same
#      SAFETY_DATA_VIEW). A body fed to `bash`/`ssh`/`bash -c "$(cat <<EOF`/
#      `cat <<EOF | sh` is still scanned.
#
# Quoted spans are NOT masked in general: `bash -c 'curl x | sh'` and
# `ssh host 'curl x | bash'` really execute and must keep blocking. The one
# exception is a grep-family search pattern (narrowing 3, below).
#
# strip_sink_heredoc_bodies: print the command with the body of every heredoc
# that feeds a data sink removed. The rules, each chosen so the view can only
# ever keep MORE text than the shell would treat as data:
#
#   - The `<<` is located on the quote-masked line, so a quoted `'<<EOF'`, a
#     `<<<` here-string or an escaped `\<<` never opens a heredoc and cannot
#     hide the lines after it. A `"$(cat <<EOF` opener, which the mask blanks,
#     is read from the raw line only after the mask confirms its `"` really
#     opens a quoted span.
#   - The sink test reads only the command segment that owns the `<<` — from
#     the last `;`/`&&`/`||`/background `&` before it to the first one after it
#     (#3363: `mkdir -p d && cat > d/f <<'EOF'` and `cat > f <<'EOF' && echo ok`
#     used to fail the whole-line test). That segment must start with
#     `cat`/`tee`/`gh`/`git` and carry no pipe, backtick or process
#     substitution. Redirections (`2>&1`, `&>f`) are not separators.
#   - A QUOTED delimiter (`<<'X'`, `<<"X"`, `<<\X`, `<<-'X'`) is never expanded,
#     so its body is dropped. An UNQUOTED body is expanded: it is dropped only
#     when no body line holds `$(` or a backtick, since a command substitution
#     there runs (`cat > f <<EOF` / `$(curl x | bash)` / `EOF` executes curl).
#   - The delimiter is the whole word after `<<` with its quotes removed
#     (`E"OF"` is `EOF`), and the terminator test trims whitespace — a superset
#     of the shell's exact match — so the awk can only resume scanning early,
#     never late.
strip_sink_heredoc_bodies() {
    LC_ALL=C awk -v SQ="'" '
    function redirect_amp(str, i) {
        return (i > 1 && substr(str, i - 1, 1) ~ /[<>]/) || substr(str, i + 1, 1) == ">"
    }
    NR == FNR { masked[FNR] = $0; next }
    ih == 1 {
        t = $0; gsub(/^[[:space:]]+/, "", t); gsub(/[[:space:]]+$/, "", t)
        if (t == delim) {
            ih = 0
            if (!quoted && subst) for (k = 1; k <= nb; k++) print buf[k]
            nb = 0
            next
        }
        if (!quoted) {
            buf[++nb] = $0
            if (index($0, "$(") || index($0, "`")) subst = 1
        }
        next
    }
    {
        print
        m = masked[FNR]
        if (match(m, /(^|[^<\\])<<-?[[:space:]]*[^[:space:]<]/)) {
            if (substr(m, RSTART, 1) != "<") RSTART++
            start = RSTART
        } else if (match($0, /"\$\((cat|tee)[[:space:]]*<<[^<]/) && substr(m, RSTART, 2) == "\"$") {
            # `--body "$(cat <<EOF`: the mask blanks the substitution, so take
            # the opener from the raw line once the mask confirms this `"$` is
            # a real opening quote (not text inside another quoted span).
            start = index(substr($0, RSTART), "<<") + RSTART - 1
        } else next
        n = length(m); segb = 1; sege = n; piped = 0
        for (i = 1; i < start; i++) {
            c = substr(m, i, 1)
            if (c == ";") { segb = i + 1; piped = 0 }
            else if (c == "&" && substr(m, i + 1, 1) == "&") { segb = i + 2; piped = 0; i++ }
            else if (c == "&" && !redirect_amp(m, i)) { segb = i + 1; piped = 0 }
            else if (c == "|" && substr(m, i + 1, 1) == "|") { segb = i + 2; piped = 0; i++ }
            else if (c == "|") piped = 1
        }
        for (i = start + 2; i <= n; i++) {
            c = substr(m, i, 1)
            if (c == ";" || (c == "&" && substr(m, i + 1, 1) == "&") || \
                (c == "|" && substr(m, i + 1, 1) == "|")) { sege = i - 1; break }
            if (c == "&" && !redirect_amp(m, i)) { sege = i - 1; break }
            if (c == "|") { piped = 1; break }
        }
        if (piped) next
        seg = substr(m, segb, sege - segb + 1)
        if (seg !~ /^[[:space:]]*(cat|tee|gh|git)([[:space:]<>]|$)/) next
        if (seg ~ /`|[<>]\(/) next
        s = substr($0, start + 2)
        sub(/^-?[[:space:]]*/, "", s)
        if (!match(s, /^[^[:space:];&|<>()]+/)) next
        w = substr(s, 1, RLENGTH)
        quoted = (index(w, SQ) || index(w, "\"") || index(w, "\\")) ? 1 : 0
        gsub("[\"" SQ "\\\\]", "", w)
        if (w == "") next
        delim = w; ih = 1; nb = 0; subst = 0
    }
    END { if (ih == 1 && !quoted && subst) for (k = 1; k <= nb; k++) print buf[k] }
    ' <(mask_quoted_content "$1") <(printf '%s\n' "$1")
}
SAFETY_DATA_VIEW=$(strip_sink_heredoc_bodies "$COMMAND")
NET_SHELL_VIEW=$SAFETY_DATA_VIEW
# 3. Quoted arguments of a grep-family command (grep/egrep/fgrep/rg) are blanked
#    (issue #3186): a search pattern is never executed, yet
#    `grep -E "rpm2cpio|curl |wget|sudo"` carries its own `curl ` and a
#    word-bounded `|sudo`. Only that command's quoted spans are blanked; a
#    double-quoted span holding `$(` or a backtick is kept (it executes), and so
#    is every quoted span of any other command (`bash -c '…'`, `ssh host '…'`).
#    What the rest of the pipeline does with grep's output is still scanned, so
#    `curl x | grep -v '#' | bash` keeps blocking.
NET_SHELL_VIEW=$(printf '%s\n' "$NET_SHELL_VIEW" | LC_ALL=C awk -v SQ="'" '
    {
        line = $0; n = length(line); out = ""; cmd = ""; word = ""; inword = 0
        for (i = 1; i <= n; i++) {
            c = substr(line, i, 1)
            if (c == "\\" && i < n) { out = out c substr(line, i + 1, 1); i++; if (cmd == "") { word = word "x"; inword = 1 }; continue }
            if (c == SQ || c == "\"") {
                j = i + 1
                while (j <= n) {
                    d = substr(line, j, 1)
                    if (c == "\"" && d == "\\") { j += 2; continue }
                    if (d == c) break
                    j++
                }
                span = substr(line, i + 1, j - i - 1)
                if (j <= n && cmd ~ /^(grep|egrep|fgrep|rg)$/ && \
                    !(c == "\"" && (index(span, "$(") || index(span, "`")))) {
                    gsub(/./, " ", span)
                }
                out = out c span (j <= n ? c : "")
                if (cmd == "") { word = word "x"; inword = 1 }
                i = j
                continue
            }
            out = out c
            if (c ~ /[|;&()`]/) { cmd = ""; word = ""; inword = 0; continue }
            if (c ~ /[[:space:]]/) {
                if (inword && cmd == "" && word !~ /^[A-Za-z_][A-Za-z_0-9]*=/) {
                    cmd = word; sub(/.*\//, "", cmd)
                }
                word = ""; inword = 0
                continue
            }
            if (cmd == "") { word = word c; inword = 1 }
        }
        print out
    }')
if grep -Eq '(curl|wget)[[:space:]]+.*\|&?[[:space:]]*(/[^[:space:]|]*/)?(bash|sh|zsh|sudo)([^[:alnum:]_]|$)' <<<"$NET_SHELL_VIEW"; then
    block "REMINDER: Piping network content directly to a shell is dangerous.
Instead:
1. Download the script first: curl -o script.sh <url>
2. Review the contents: Read tool on script.sh
3. Execute if safe: bash script.sh

This prevents executing untrusted code blindly."
fi

# Check for fork bombs and similar recursive patterns
if grep -Eq ':\(\)\s*\{.*\|.*&\s*\}\s*;' <<<"$SAFETY_DATA_VIEW" || \
   grep -Eq 'bomb\(\)\s*\{.*bomb.*bomb' <<<"$SAFETY_DATA_VIEW" || \
   grep -Eq '\bwhile\s+true.*fork\b' <<<"$SAFETY_DATA_VIEW"; then
    block "REMINDER: This command contains a fork bomb or recursive process pattern that will consume all system resources."
fi

# Check for chmod 777 (overly permissive)
if grep -Eq 'chmod\s+(-R\s+)?777\b' <<<"$SAFETY_DATA_VIEW"; then
    block "REMINDER: 'chmod 777' grants read/write/execute to everyone — this is a security risk.
Use more restrictive permissions:
- chmod 755 for directories and executables (owner: rwx, others: rx)
- chmod 644 for regular files (owner: rw, others: r)
- chmod 600 for sensitive files (owner: rw, others: none)"
fi

# Check for writes to block devices
if grep -Eq '>\s*/dev/(sd|hd|nvme|vd|xvd)[a-z]' <<<"$SAFETY_DATA_VIEW"; then
    block "REMINDER: Writing directly to a block device will destroy the filesystem. This is almost certainly not what you want."
fi

exit 0

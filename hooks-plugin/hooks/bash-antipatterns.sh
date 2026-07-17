#!/usr/bin/env bash
# PreToolUse hook for Bash tool - detects anti-patterns and reminds Claude
# to use built-in tools instead of shell commands

set -euo pipefail

# Read the JSON input from stdin
INPUT=$(cat)

# Extract the command from the tool input
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# If no command, allow it
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Strip heredoc body content up front so detectors that scan the whole command
# string don't false-positive on literal text inside a heredoc body. The main
# offender is `gh pr create --body "$(cat <<'EOF' ... EOF)"` whose body may
# contain example shell commands (e.g. "git add && git commit") that are just
# documentation, not executable code.
#
# The awk program walks the command line-by-line. When it sees `<<DELIM` it
# enters heredoc mode and suppresses subsequent lines until it sees a line
# matching DELIM. The heredoc-opening line itself is still printed.
COMMAND_SHELL_ONLY=$(echo "$COMMAND" | awk '
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

# A further-stripped view with quoted-string literals removed (on top of the
# heredoc stripping above). Detectors that key off *content tokens* an agent
# would only ever read (e.g. task-output file paths like `.../tasks/x.output`)
# must scan this view, not raw $COMMAND — otherwise a `gh issue create --body
# "... see run.output ..."` whose prose merely *mentions* such a path triggers
# the read-task-output block even though no read happens (issue #1591).
# shellcheck disable=SC2001  # bash pattern substitution can't do `[^']*` char class
COMMAND_NO_STRINGS=$(echo "$COMMAND_SHELL_ONLY" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")

# Function to output a blocking message (exit code 2 = blocking error)
block() {
    echo "$1" >&2
    exit 2
}

# Remote-exec guard (issue #1900).
#
# When the TOP-LEVEL command runs on another host or container — ssh/rsh/slogin,
# `kubectl exec`, `docker exec`, dokku — every filesystem path inside its payload
# (a quoted remote command, a heredoc fed over stdin, or bare args) targets the
# REMOTE side. The local-filesystem tools the read/list reminders point to (Read,
# Grep, Glob) run on the LOCAL machine and cannot reach that target, so the
# suggested substitution is inapplicable and the reminder is pure friction.
#
# The heredoc form is the concrete false positive:
#   ssh host <<EOF ... ls /remote/*.json ... EOF
# puts the `ls`/`cat`/`grep` on its own line, which the (line-anchored) read/list
# detectors match — and block — even though it runs on the remote host.
#
# Only the read/list *style* reminders (cat/head/tail→Read, grep/rg→Grep,
# ls→Glob) are suppressed for these commands. Safety blocks (curl|bash,
# chmod 777, git add -A, reset --hard, block-device writes, fork bombs) are NOT
# suppressed — those hazards apply on the remote host too, and per
# hook-block-vs-nudge.md a safety exit-2 is earned regardless of where the
# command runs. The guard is anchored to the FIRST token (after optional env
# assignments) so a local `cat x && ssh host …` still blocks the local `cat`.
IS_REMOTE_EXEC=false
if echo "$COMMAND" | grep -Eq '^\s*([A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(ssh|rsh|slogin|dokku)\s' || \
   echo "$COMMAND" | grep -Eq '^\s*(kubectl|oc)\s[^|]*\bexec\b' || \
   echo "$COMMAND" | grep -Eq '^\s*(docker|podman|nerdctl)\s[^|]*\bexec\b'; then
    IS_REMOTE_EXEC=true
fi

# Check for cat used to read files (but allow cat in pipelines and heredocs)
# Patterns: cat file, cat /path/file, cat "./file"
# Allow cat as first command in a pipeline (cat file | ...) since the data flows to other tools
if [ "$IS_REMOTE_EXEC" = false ] && \
   echo "$COMMAND" | grep -Eq '^\s*cat\s+[^|><]' && \
   ! echo "$COMMAND" | grep -Eq '<<|cat\s*>' && \
   ! echo "$COMMAND" | grep -q '|'; then
    block "BLOCKED: 'cat /path/to/file.md' →
  Read(file_path=\"/path/to/file.md\")

The Read tool returns line-numbered content and respects token budgets.
Pipelines (cat file | jq) and heredocs (cat <<EOF) are still allowed.
See .claude/rules/bash-tool-replacements.md for the full table."
fi

# Check for head/tail used to read files (not in pipelines)
#
# Scan COMMAND_SHELL_ONLY (heredoc bodies stripped) so a `head`/`tail` token that
# is an identifier inside a quoted heredoc payload handed to another interpreter
# — e.g. `python3 - <<'PY' … head = txt[:idx] … PY` — is not mistaken for a
# `head <file>` invocation (issue #1848). The `[^|=]` (was `[^|]`) also excludes
# the assignment form `head = "x"` / `tail = …` at line start (a Python/awk
# variable in a single-quoted multi-line script the heredoc strip does not cover);
# a real `head`/`tail` file argument never begins with `=`.
if [ "$IS_REMOTE_EXEC" = false ] && \
   echo "$COMMAND_SHELL_ONLY" | grep -Eq '^\s*(head|tail)\s+(-[0-9n]+\s+)?[^|=]' && \
   ! echo "$COMMAND_SHELL_ONLY" | grep -q '|'; then
    block "BLOCKED: 'head -50 file.md' →
  Read(file_path=\"/abs/path/to/file.md\", limit=50)

BLOCKED: 'tail -50 file.md' →
  Read(file_path=\"/abs/path/to/file.md\", offset=<total_lines - 50>, limit=50)

The Read tool with offset/limit reads the same byte range with
line-numbered output. Pipelines (head file | …) are still allowed.
See .claude/rules/bash-tool-replacements.md for the full table."
fi

# Check for sed used for editing (in-place edits)
#
# Scan COMMAND_NO_STRINGS (heredoc bodies AND quoted-string literals stripped)
# so an issue/PR body that merely *documents* `sed -i` — filing a bug report
# about this very rule, writing docs about the antipattern — does not fire
# (issue #2052 item 4). Only a `sed -i` that survives quote/heredoc stripping
# is an actual invocation.
#
# Exempt targets under scratch/temp paths (/tmp, /private/tmp, /var/folders,
# $TMPDIR): an in-place stream edit of a throwaway generated file is fine —
# the Edit tool's precision matters for repo files, and forcing a Read + Edit
# round-trip on a generated scratch file can pull secret material (e.g. a
# freshly generated private key) into the transcript that the stream edit
# would not have (issue #2052 item 3). The tmp-path check runs on
# COMMAND_SHELL_ONLY (quotes kept) so a quoted tmp path still exempts.
# shellcheck disable=SC2016  # the \$TMPDIR is a literal regex token, not an expansion
SED_TMP_TARGET_RE='sed[[:space:]]+(-i[^[:space:]]*|--in-place[^[:space:]]*)[^;&|]*[[:space:]]['"'"'"]?((/private)?/tmp/|/var/folders/|\$TMPDIR)'
if echo "$COMMAND_NO_STRINGS" | grep -Eq "sed\s+(-i|--in-place)" && \
   ! echo "$COMMAND_SHELL_ONLY" | grep -Eq "$SED_TMP_TARGET_RE"; then
    block "REMINDER: Use the Edit tool instead of 'sed -i' to modify files. The Edit tool provides safer, more precise string replacements with proper error handling. (In-place edits of scratch files under /tmp are allowed.)"
fi

# Check for awk used for file modifications
if echo "$COMMAND" | grep -Eq "awk\s+.*>\s*['\"]?[^|]+" && \
   echo "$COMMAND" | grep -Eq "(>|>>)\s*['\"]?\\\$"; then
    block "REMINDER: Use the Edit tool instead of 'awk' for file modifications. The Edit tool is safer and more precise."
fi

# Check for echo/printf writing to a FILE (not stdout, a pipe, or a /dev stream).
#
# Use [^;&|]* instead of .* to avoid crossing command separators (;, &&, ||, |)
# which would cause false positives when echo "text" is followed by an unrelated
# 2>/dev/null.
#
# Scan COMMAND_NO_STRINGS (heredoc bodies AND quoted-string literals stripped) so
# a `>` that is merely text inside a quoted argument — a section header, prose, or
# a documented redirect example like `echo "use foo > out.txt"` — is not mistaken
# for a real shell redirection. Only a `>` that survives quote stripping is an
# actual redirection operator (issue #1701). Stripping single quotes alone left
# double-quoted `>` content (the common section-header case) firing this block.
#
# Exempt stream targets, mirroring the cat/head/tail /dev exemptions: stdout and
# pipes leave no surviving `>`, `>&N` fd-duplication is excluded by the `[^&]`
# after `>`, and any redirect to a `/dev/*` device/stream target (/dev/null,
# /dev/stderr, /dev/stdout, /dev/tty, /dev/fd/N) is stream handling, not file
# creation (issue #1701).
#
# An fd-prefixed redirect to /dev/* (`2>/dev/null`, `1>/dev/null`, bare
# `>/dev/null`) is stream handling too, not a file write (issues #1722, #1721).
# The previous `[^0-9]>\s*/dev/` exemption did not fire when `2>/dev/null` was
# the ONLY redirect (the leading `2` is a digit), so a stderr-only redirect on an
# `echo`/`printf` was falsely blocked as a file write — including when the
# redirect lived inside a `$(...)` belonging to a sibling command. Instead of an
# exemption, strip every `[0-9]*>\s*/dev/<target>` from the scanned view first;
# a `>` to a real (non-/dev) file is then the only signal left. This preserves
# the #1701 mixed-write case: `echo x > out.txt 2>/dev/null` keeps `> out.txt`
# after the strip and still blocks.
COMMAND_NO_DEVNULL=$(echo "$COMMAND_NO_STRINGS" | sed -E 's#[0-9]*>[[:space:]]*/dev/[^[:space:];&|]*##g')
if echo "$COMMAND_NO_DEVNULL" | grep -Eq '(^|\s)(echo|printf)\s+[^;&|]*>\s*[^&]'; then
    # Block only when the redirect target is a real file path.
    if echo "$COMMAND_NO_DEVNULL" | grep -Eq '(echo|printf)\s+[^;&|>]*>\s*[a-zA-Z/.]'; then
        block "REMINDER: Use the Write tool instead of 'echo/printf > file' to create files. The Write tool properly handles file creation and provides better error handling."
    fi
fi

# Check for commit message being written to temp file
# Pattern: cat > /tmp/commit_msg.txt or similar, often with heredoc containing conventional commit
#
# Gate on an actual `git commit` / `git tag` in the command. Otherwise a PR or
# issue body written to a temp file and passed to `gh pr create --body-file` /
# `gh issue edit --body-file` — the recommended multi-line-body pattern — falsely
# triggered this git-commit-specific reminder, which is irrelevant to the blocked
# command (issue #1584, #1587). The reminder only makes sense when the command
# is in fact composing a git commit/tag message.
if echo "$COMMAND" | grep -Eq 'git\s+(commit|tag)\b' && \
   echo "$COMMAND" | grep -Eq '(feat|fix|docs|refactor|test|chore|perf|ci)(\(.+\))?[!:]' && \
   { echo "$COMMAND" | grep -Eq 'cat\s*>\s*[^|]*commit' || \
     echo "$COMMAND" | grep -Eq "(cat|echo|printf)\s*>\s*/tmp/.*<<.*EOF"; }; then
    block "REMINDER: Use HEREDOC directly in git commit:

git commit -m \"\$(cat <<'EOF'
type(scope): description

Body text here.

Fixes #123
EOF
)\""
fi

# Check for cat > file (writing files).
# Exempt heredoc writes (cat > file <<EOF ... EOF): writing a temp file via a
# heredoc and feeding it to a later command (e.g. gh pr create --body-file) is
# the recommended multi-line pattern (copy-paste-commands.md), and the hook's own
# cat-read message above already states heredocs are allowed (issue #1584, #1587).
# A plain `cat > file` with no heredoc is still blocked in favour of the Write tool.
#
# Scan COMMAND_SHELL_ONLY (heredoc bodies stripped) so a `cat > file` that is
# merely *text inside a heredoc body* — e.g. a PR/issue body written via
# `gh pr create --body "$(cat <<'EOF' … EOF)"` that documents the pattern —
# does not fire (issue #2058). The heredoc-opening line itself is kept, so a
# real `cat > file <<EOF` write is still visible to the exemption below, and
# a real plain `cat > file` still blocks.
if echo "$COMMAND_SHELL_ONLY" | grep -Eq 'cat\s*>\s*[^|]' && \
   ! echo "$COMMAND_SHELL_ONLY" | grep -Eq 'cat\s*>\s*\S.*<<'; then
    block "REMINDER: Use the Write tool instead of 'cat > file' to create files. The Write tool is the proper way to write file contents."
fi

# Check for timeout command
if echo "$COMMAND" | grep -Eq '^\s*timeout\s+'; then
    block "REMINDER: The 'timeout' command is usually unnecessary - the Bash tool has its own timeout parameter. Human approval time typically exceeds any timeout value anyway. Remove the timeout wrapper and use the command directly."
fi

# NOTE: `find` is intentionally NOT blocked here.
#
# The find→Glob redirect was demoted from a hard block to a non-blocking teach
# nudge (bash-antipatterns-teach.sh, opt-in via CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1).
# History: the block shipped in the original 2026-01 "use built-in tools instead
# of shell" sweep purely for workflow consistency + context efficiency on broad
# `**/*.ext` sweeps — never for safety (it always EXEMPTED the dangerous `-exec`
# form and only blocked simple `-name` searches). Against that thin benefit it
# cost: a recurring false-positive treadmill (#845, #1378, #1671, #1800/#1807) and
# — decisively — a hard dead-end inside subagents whose toolset doesn't grant Glob
# (PreToolUse Bash hooks fire in every context, but Glob is not always available).
# The model is fluent in `find`; blocking a tool it writes reliably to force one
# that is sometimes absent is a bad trade. Context efficiency is preserved by the
# opt-in teach nudge, which steers toward Glob without dead-ending anyone.
# See .claude/rules/bash-tool-replacements.md for the find/Glob/fd guidance.

# NOTE: `grep`/`rg` are intentionally NOT blocked here.
#
# The grep/rg→Grep redirect was demoted from a hard block to a non-blocking teach
# nudge (bash-antipatterns-teach.sh, opt-in via CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1),
# mirroring the find→Glob demotion (#1871). Same reasoning applies point-for-point
# under hook-block-vs-nudge.md's litigation test: the block did NO safety work (it
# always EXEMPTED the genuinely dangerous forms — pipelines, boolean -q checks,
# -l/-c/-L filter modes — and only blocked benign line-numbered file reads); it
# hard-DEAD-ENDED subagents whose toolset doesn't grant the Grep tool (PreToolUse
# Bash hooks fire in every context, but Grep is not always available — #1909, where
# `ToolSearch(select:Grep)` returned "No matching deferred tools found" and every
# blocked search cost a retry cycle); and it carried the worst same-session
# repeat-block rate of any pattern (21%, W20). The model writes grep/rg reliably;
# blocking a tool it's fluent in to force one that is sometimes absent is a bad
# trade. Context efficiency is preserved by the opt-in teach nudge, which steers
# toward Grep without dead-ending anyone.
# See .claude/rules/bash-tool-replacements.md for the grep/rg/Grep guidance.

# NOTE: `ls` is intentionally NOT blocked here.
#
# The ls→Glob redirect was demoted from a hard block to a non-blocking teach
# nudge (bash-antipatterns-teach.sh, opt-in via CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1),
# mirroring the find→Glob (#1871) and grep/rg→Grep (#1909) demotions. Same
# reasoning applies point-for-point under hook-block-vs-nudge.md's litigation
# test: the block did NO safety work (listing files destroys nothing; the only
# justification was style/context-efficiency); it hard-DEAD-ENDED subagents
# whose toolset doesn't grant the Glob tool (PreToolUse Bash hooks fire in every
# context, but Glob is not always available — #1416); its regex
# `^\s*ls\s+.*\*` was a compound-command false positive (it matched any command
# that merely STARTS with ls and contains a `*` anywhere later, e.g.
# `ls -1 dir | head; find . -name "*.jsonl"` — the `*` in the unrelated find
# clause tripped the block); and it carried the highest same-session
# repeat-block rate of any pattern (31.8% W28 re-run, 33.3% W28 — sustained
# ≥30% over two consecutive readings, issue #2036). The model writes ls
# reliably; blocking a tool it's fluent in to force one that is sometimes
# absent is a bad trade. Context efficiency is preserved by the opt-in teach
# nudge (`glob-ls`), which steers toward Glob without dead-ending anyone.
# See .claude/rules/bash-tool-replacements.md for the ls/Glob guidance.

# Check for reading task output files (should use the Read tool)
# Detects patterns like: cat /tmp/claude/*/tasks/*.output, tail ...tasks/...output, sleep && cat ...output
#
# Scans COMMAND_NO_STRINGS (heredoc bodies and quoted literals stripped) so that
# a `gh issue create --body "...mentions run.output..."` whose prose merely names
# a task-output path is not mistaken for an actual read (issue #1591).
#
# TaskOutput is deprecated — its own tool guidance now says to Read the output
# file path from the task notification. For large structured outputs, an
# extraction pipeline (`cat … | jq`/`python3`) to a compact summary is allowed
# and is the context-efficient path; only a *standalone* cat/tail/head read of a
# task-output file (no pipe) is nudged toward Read here (issue #1591).
if { echo "$COMMAND_NO_STRINGS" | grep -Eq '(cat|tail|head)\s[^|]*(/tasks/|\.output)' || \
     echo "$COMMAND_NO_STRINGS" | grep -Eq 'sleep[^|]*&&[^|]*(cat|tail)\s[^|]*(/tasks/|\.output)'; } && \
   ! echo "$COMMAND_NO_STRINGS" | grep -q '|'; then
    block "REMINDER: Use the Read tool on the task-output file path from the task
notification instead of cat/tail/head. (The TaskOutput tool is deprecated.)

For a large structured output file, Read'ing the whole thing is wasteful — pipe
an extraction to a compact summary instead (pipelines are allowed):
  cat <output-file> | jq '<filter>'    or    cat <output-file> | python3 …"
fi

# NOTE: the long-pipeline (5+ pipes from a discouraged head) block was REMOVED.
#
# The pipe-count block was demoted from a hard block to a non-blocking teach
# nudge (bash-antipatterns-teach.sh `long-pipeline`, opt-in via
# CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1), following the same
# hook-block-vs-nudge.md litigation as the find (#1871), grep/rg (#1909), and
# ls (#2036) demotions. The block did NO safety work — its own message conceded
# that "a long pipeline of legitimate transforms … is fine", i.e. it exempted
# every genuinely-useful form and fired only on a cat/echo/printf text-scrape
# head or a redundant grep | grep — a style/context-efficiency concern. It
# dead-ended subagents lacking jq/Grep substitution paths, and it carried a
# sustained mid-20s same-session repeat-block rate across six friction-learner
# readings (37.5 → 24.0 → 27.3 → 17.4 → 28.1%, issue #1873), i.e. it was not
# teaching. It also had two outright counting defects (issue #2051, #2052):
# PIPE_COUNT summed pipes across INDEPENDENT statements in one Bash call, and
# a `printf … | tee <file>` writer was treated as a scrape head — so a batch
# of five 1-pipe `gh issue create | tail -1` statements plus one printf | tee
# rollup was blocked as a "6-pipe scrape". The teach nudge counts pipes
# per-pipeline (statement-split) and so has neither defect.
#
# LOG_STREAM_RE survives because the multi-grep chain block below still uses it.
# Log-stream sources — `kubectl logs`, `journalctl`, `docker logs`, `stern`, … —
# emit an unstructured text stream with no --json/jq alternative, so
# `… | grep <inc> | grep -v <exc> | tail` is the *idiomatic* read path during
# incident diagnosis, not a data-processing scrape to nudge away from (issue
# #1833). The `<tool> logs` arm requires the `logs` subcommand to sit in the
# same pipe segment as a known log-producing CLI (`[^|]*[[:space:]]logs`) so an
# unrelated `ls logs/` does not match.
LOG_STREAM_RE='\b(journalctl|stern)\b|\b(kubectl|oc|docker|podman|nerdctl|nomad|heroku|gcloud|crictl|flyctl|fly|k)\b[^|]*[[:space:]]logs\b'
IS_LOG_STREAM=false
if echo "$COMMAND_SHELL_ONLY" | grep -Eq "$LOG_STREAM_RE"; then
    IS_LOG_STREAM=true
fi

# Check for multi-grep chains parsing test/task output
# Pattern: grep ... | grep ... with sed/cut suggests parsing structured output as text
#
# Exempt log-stream sources (kubectl logs / journalctl / docker logs / …): an
# unstructured log stream has no structured-output alternative, so a
# `grep | grep -v | sed | tail` over it is the idiomatic incident-diagnosis read,
# and the Error/fail tokens this keys on are exactly what log diagnostics search
# for (issue #1833). IS_LOG_STREAM is computed in the pipe-count block above.
#
# Require a POSITIVE test/task-output signal — a task-output file (.output or
# /tasks/) OR a known test-runner invocation — instead of the bare
# Error/fail/FAIL tokens (issue #1914). Those tokens matched incidentally and
# turned a legitimate verification command into a false positive: a multi-pattern
# grep spot-checking GitHub Actions YAML (`grep -n 'app-id|timeout-minutes|
# skip-on-release' reusable-release-please.yml | …`) trips both clauses — the
# quoted alternation `|` inflate the grep-chain match, and workflow fields like
# `fail-fast` / `continue-on-error` / `on-failure` match `fail`. A grep chain is
# "parsing test output" only when its data source is actually a task-output file
# or the stdout of a test runner; a scrape over *.yml / *.md / source files has
# neither signal and is left alone. Runners covered: pytest/vitest/jest/mocha/
# ava/rspec/phpunit by name, and `<toolchain> test` (cargo/go/npm/pnpm/yarn/bun/
# deno/dotnet/mvn/gradle) in the same pipe segment.
TEST_OUTPUT_SOURCE_RE='\.output|/tasks/|\b(pytest|vitest|jest|mocha|ava|rspec|phpunit)\b|\b(cargo|go|npm|pnpm|yarn|bun|deno|dotnet|mvn|gradle)\b[^|]*[[:space:]]test\b'

# Also exempt greps over explicit source/config FILE operands (issue #1914): the
# generic case-sensitive tokens `Error`/`fail`/`FAIL` match substrings that appear
# in ordinary workflow YAML and source — a `grep -n 'app-id|fail-fast|…'
# reusable-release-please.yml | … | awk` spot-checking GitHub Actions files has
# nothing to do with test output, but it fired this heuristic. A grep whose
# operands name explicit `.yml`/`.md`/`.json`/source-file paths is reading source,
# not scraping a test/task-output stream, so IS_SOURCE_FILE_GREP suppresses the
# block. The stdin-scrape (`cat r.txt | grep Error | … | sed`) and `/tasks/*.output`
# forms have no such source-file operand and keep firing.
#
# Scan COMMAND_NO_STRINGS (quoted literals stripped) so the extension match keys on
# a real file OPERAND, not a source name that merely appears inside the search
# pattern. This also lets the char class stop at pipes/separators without a quoted
# pattern's own `|` (e.g. grep -n 'app-id|fail-fast' file.yml) cutting the scan
# short before the file operand.
IS_SOURCE_FILE_GREP=false
if echo "$COMMAND_NO_STRINGS" | grep -Eq '(grep|rg)\b[^|;&]*\.(yml|yaml|md|json|ts|tsx|js|py|tf|toml|sh|rs|go)\b'; then
    IS_SOURCE_FILE_GREP=true
fi

if [ "$IS_LOG_STREAM" = false ] && \
   [ "$IS_SOURCE_FILE_GREP" = false ] && \
   echo "$COMMAND" | grep -Eq 'grep.*\|.*grep.*\|.*(sed|cut|awk)' && \
   echo "$COMMAND" | grep -Eq "$TEST_OUTPUT_SOURCE_RE"; then
    block "REMINDER: Parsing test output with grep chains is fragile. Better alternatives:
- Use --reporter=json (Bun, Vitest, Jest) and parse with jq
- Use --reporter=junit for CI-style XML output
- Check test runner docs for built-in failure grouping options
- For Bun: 'bun test --reporter=json 2>&1 | jq .testResults'"
fi

# Check for broad git staging commands (git add -A, git add --all, git add .)
# These can accidentally include sensitive files (.env, credentials) or large binaries.
# Pattern handles git global flags like -C <path> before the subcommand.
if echo "$COMMAND" | grep -Eq '^\s*git\s+(.+\s+)?add\s+(-A|--all|\.(\s|$))'; then
    block "REMINDER: Avoid broad staging commands like 'git add -A', 'git add --all', or 'git add .'.
These can accidentally include sensitive files (.env, credentials) or large binaries.

Instead, stage specific files by name:
  git add src/file1.ts src/file2.ts

Or review what would be staged first:
  git status --porcelain"
fi

# Check for chained git commands that involve index-modifying operations (git X && git Y)
# index.lock race conditions only occur when one command writes to the git index.
# Index-modifying commands: add, commit, rm, mv, reset (not read-only commands like status/diff/log).
# The fix is to run git commands as separate Bash calls, not chained.
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
if echo "$COMMAND_NO_STRINGS" | grep -Eq "git\\s+${INDEX_MODIFYING}\\b.*&&.*git\\s+\\S+" || \
   echo "$COMMAND_NO_STRINGS" | grep -Eq "git\\s+\\S+.*&&.*git\\s+${INDEX_MODIFYING}\\b"; then
    block "REMINDER: Chaining git commands with '&&' can cause index.lock race conditions.
The lock file from an index-modifying command (add, commit, rm, mv, reset) may not be
released before the next command tries to acquire it.
Instead of: git add . && git commit -m 'msg'
Run git commands as separate Bash tool calls:
1. git add src/file.ts
2. git commit -m 'msg'
This avoids race conditions and is more reliable."
fi

# Check for git reset --hard (destructive operation, usually unnecessary)
# After pushing commits to a PR branch, agents sometimes think they need to reset main.
# However, once the PR is merged, git pull will cleanly resolve the situation.
# Exclude heredocs (<<) so commit messages mentioning "git reset" don't trigger this.
if echo "$COMMAND" | grep -Eq '^\s*git\s+reset\s+--hard' && \
   ! echo "$COMMAND" | grep -Eq '<<'; then
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
if echo "$COMMAND" | grep -Eq '^\s*git\s+push\b' && \
   echo "$COMMAND" | grep -Eq '(\s-[a-zA-Z]*u[a-zA-Z]*\b|--set-upstream\b)' && \
   echo "$COMMAND" | grep -Eq '\sorigin\s+[a-zA-Z0-9._/@-]+:[a-zA-Z0-9._/-]+'; then
    PUSH_REFSPEC=$(echo "$COMMAND" | grep -oE 'origin\s+[a-zA-Z0-9._/@-]+:[a-zA-Z0-9._/-]+' | awk '{print $2}')
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

# Check for piped execution from network (curl/wget piped to shell)
if echo "$COMMAND" | grep -Eq '(curl|wget)\s+.*\|\s*(bash|sh|zsh|sudo)'; then
    block "REMINDER: Piping network content directly to a shell is dangerous.
Instead:
1. Download the script first: curl -o script.sh <url>
2. Review the contents: Read tool on script.sh
3. Execute if safe: bash script.sh

This prevents executing untrusted code blindly."
fi

# Check for fork bombs and similar recursive patterns
if echo "$COMMAND" | grep -Eq ':\(\)\s*\{.*\|.*&\s*\}\s*;' || \
   echo "$COMMAND" | grep -Eq 'bomb\(\)\s*\{.*bomb.*bomb' || \
   echo "$COMMAND" | grep -Eq '\bwhile\s+true.*fork\b'; then
    block "REMINDER: This command contains a fork bomb or recursive process pattern that will consume all system resources."
fi

# Check for chmod 777 (overly permissive)
if echo "$COMMAND" | grep -Eq 'chmod\s+(-R\s+)?777\b'; then
    block "REMINDER: 'chmod 777' grants read/write/execute to everyone — this is a security risk.
Use more restrictive permissions:
- chmod 755 for directories and executables (owner: rwx, others: rx)
- chmod 644 for regular files (owner: rw, others: r)
- chmod 600 for sensitive files (owner: rw, others: none)"
fi

# Check for writes to block devices
if echo "$COMMAND" | grep -Eq '>\s*/dev/(sd|hd|nvme|vd|xvd)[a-z]'; then
    block "REMINDER: Writing directly to a block device will destroy the filesystem. This is almost certainly not what you want."
fi

# If we get here, the command is allowed
exit 0

#!/usr/bin/env bash
# PreToolUse hook for Bash tool - detects anti-patterns and reminds Claude
# to use built-in tools instead of shell commands
#
# Two-tier classification:
#   1. Scoping-sensitive read/write anti-patterns (cat/head/tail reads,
#      echo/printf/cat writes, sed -i, task-output reads) are classified
#      STRUCTURALLY with ast-grep (tree-sitter-bash). A real parse gives distinct
#      AST node shapes for "cat reading a file" vs "cat in a pipeline" vs
#      "cat <<EOF" vs "cat > file" vs a `cat` mentioned inside a string/heredoc —
#      distinctions the old regex path faked with three pre-stripping passes and a
#      remote-exec guard, and repeatedly got wrong (#1701, #1721, #1722, #1848,
#      #1900, #2052, #2058). These are STYLE nudges: when ast-grep is absent
#      (sandboxes, subagents) they simply do not fire. There is no regex twin.
#   2. Safety / correctness blocks (curl|bash, chmod 777, git add -A, reset
#      --hard, push -u footgun, block-device writes, fork bombs, git index-lock
#      chains, grep-chain test-output scrapes, awk/cat-to-commit-file) stay
#      pure-regex and fire in EVERY context — they must not depend on a binary
#      that may be missing.

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

# Strip heredoc body content up front so the regex detectors below that scan the
# whole command string don't false-positive on literal text inside a heredoc
# body. The main offender is `gh pr create --body "$(cat <<'EOF' ... EOF)"` whose
# body may contain example shell commands (e.g. a log-stream pipeline) that are
# documentation, not executable code. (Now consumed only by the log-stream and
# grep-chain regex detectors — the read/write detectors moved to the AST path,
# which understands heredoc-body nodes natively.)
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

# Strip trailing `#` comments from the heredoc-stripped view (issue #2106). Done
# AFTER heredoc stripping (not before) so comment removal only ever touches the
# executable command text that survives heredoc stripping — never a heredoc body
# line (already gone) or its closing delimiter. Because COMMAND_NO_STRINGS and
# COMMAND_NO_DEVNULL derive from COMMAND_SHELL_ONLY, every idiom detector keyed
# off those views (head/tail, sed -i, echo/printf → file, cat > file,
# task-output, git chains) becomes comment-immune in one place.
COMMAND_SHELL_ONLY=$(strip_trailing_comments "$COMMAND_SHELL_ONLY")

# A further-stripped view with quoted-string literals removed (on top of the
# heredoc stripping above). The git index-lock chain detector and the
# source-file-grep exemption key off *content tokens* that must survive as real
# operands, not literal text inside a quoted `--body`/`--title` argument — e.g. a
# `gh issue create --body "... git add && git commit ..."` that merely documents a
# chain (issue #1587), or a `grep -n 'app-id|fail-fast' file.yml` whose file
# operand must be seen past the quoted pattern's own `|` (issue #1914).
# shellcheck disable=SC2001  # bash pattern substitution can't do `[^']*` char class
COMMAND_NO_STRINGS=$(echo "$COMMAND_SHELL_ONLY" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")

# Function to output a blocking message (exit code 2 = blocking error)
block() {
    echo "$1" >&2
    exit 2
}

# ── Structural read/write classification (ast-grep --lang bash) ───────────────
#
# The scoping-sensitive read/write detectors are classified via tree-sitter-bash.
# A read command inside `ssh host <<EOF … EOF`, `ssh host 'ls|grep'`, or
# `kubectl exec … -- cat` is a heredoc-body / string / argument node — never a
# command_name — so the remote-exec guard (#1900) is unnecessary: those forms are
# never mis-detected in the first place. A `cat`/`sed -i` MENTIONED inside a
# quoted string or heredoc body (#2052, #2058) is likewise not a command node.
#
# ast-grep is a single fast binary but is NOT assumed present (PreToolUse hooks
# fire in sandboxes and subagents). When it is absent these STYLE nudges simply
# do not fire — losing a "use Read instead of cat" steer where the parser is
# unavailable costs nothing irreversible, and the SAFETY blocks further down are
# pure-regex and fire in every context. Set
# CLAUDE_HOOKS_BASH_ANTIPATTERNS_NO_ASTGREP=1 to force the no-op path (tests).
ASTGREP=""
if [ "${CLAUDE_HOOKS_BASH_ANTIPATTERNS_NO_ASTGREP:-}" != "1" ]; then
    if command -v ast-grep >/dev/null 2>&1; then
        ASTGREP="ast-grep"
    elif command -v sg >/dev/null 2>&1; then
        ASTGREP="sg"
    fi
fi

if [ -n "$ASTGREP" ]; then
    # Six rules, `---`-separated. Each keys on a distinct AST shape:
    #  - cat-read / head-tail-read: a read command with a (non-flag) file operand,
    #    NOT inside a pipeline (a pipeline read feeds another tool — allowed).
    #  - cat-write: a `cat` redirected to a real (non-/dev) file with NO source
    #    argument and NO heredoc (a heredoc write is the recommended body pattern).
    #  - echo-printf-write: an echo/printf file_redirect to a real (non-/dev)
    #    target; fd redirects like `2>/dev/null` carry a /dev destination and a
    #    redirect inside a sibling `$(…)` binds to that inner command, not the echo.
    #  - sed-inplace: `sed -i`/`--in-place` whose operands do NOT include a
    #    scratch path (/tmp, /private/tmp, /var/folders) — scratch edits are fine.
    #  - task-output-read: cat/head/tail of a `.output`/`/tasks/` path, not piped.
    AST_RULES=$(cat <<'SGRULES'
id: cat-read
language: bash
rule:
  kind: command
  all:
    - has: { field: name, regex: '^cat$' }
    - has:
        any:
          - { kind: word, regex: '^[^-]' }
          - { kind: string }
          - { kind: raw_string }
          - { kind: concatenation }
    - not: { inside: { kind: pipeline, stopBy: end } }
---
id: head-tail-read
language: bash
rule:
  kind: command
  all:
    - has: { field: name, regex: '^(head|tail)$' }
    - has:
        any:
          - { kind: word, regex: '^[^-]' }
          - { kind: string }
          - { kind: raw_string }
          - { kind: concatenation }
    - not: { inside: { kind: pipeline, stopBy: end } }
---
id: cat-write
language: bash
rule:
  kind: file_redirect
  all:
    - has: { field: destination, kind: word }
    - not: { has: { field: destination, regex: '^/dev/' } }
    - inside:
        all:
          - { kind: redirected_statement }
          - has:
              field: body
              kind: command
              all:
                - { has: { field: name, regex: '^cat$' } }
                - { not: { has: { kind: word } } }
          - { not: { has: { kind: heredoc_redirect, stopBy: end } } }
---
id: echo-printf-write
language: bash
rule:
  kind: file_redirect
  all:
    - has: { field: destination, kind: word }
    - not: { has: { field: destination, regex: '^/dev/' } }
    - inside:
        kind: redirected_statement
        has:
          field: body
          kind: command
          has: { field: name, regex: '^(echo|printf)$' }
---
id: sed-inplace
language: bash
rule:
  kind: command
  all:
    - has: { field: name, regex: '^sed$' }
    - has: { kind: word, regex: '^(-i|--in-place)' }
    - not: { has: { kind: word, regex: '^((/private)?/tmp/|/var/folders/)' } }
---
id: task-output-read
language: bash
rule:
  kind: command
  all:
    - has: { field: name, regex: '^(cat|head|tail)$' }
    - has: { kind: word, regex: '(\.output|/tasks/)' }
    - not: { inside: { kind: pipeline, stopBy: end } }
SGRULES
)

    # Fail open: any ast-grep/jq error yields an empty match set (no nudge).
    AST_IDS=$(printf '%s' "$COMMAND" | "$ASTGREP" scan --inline-rules "$AST_RULES" --stdin --json=compact 2>/dev/null | jq -r '.[].ruleId' 2>/dev/null | sort -u) || AST_IDS=""

    ast_matched() { printf '%s\n' "$AST_IDS" | grep -qx "$1"; }

    # Priority = the original detector order, with the more-specific task-output
    # message ahead of the generic cat read (both would match a `.output` read).
    if ast_matched "task-output-read"; then
        block "REMINDER: Use the Read tool on the task-output file path from the task
notification instead of cat/tail/head. (The TaskOutput tool is deprecated.)

For a large structured output file, Read'ing the whole thing is wasteful — pipe
an extraction to a compact summary instead (pipelines are allowed):
  cat <output-file> | jq '<filter>'    or    cat <output-file> | python3 …"
    fi

    if ast_matched "cat-read"; then
        block "BLOCKED: 'cat /path/to/file.md' →
  Read(file_path=\"/path/to/file.md\")

The Read tool returns line-numbered content and respects token budgets.
Pipelines (cat file | jq) and heredocs (cat <<EOF) are still allowed.
See .claude/rules/bash-tool-replacements.md for the full table."
    fi

    if ast_matched "head-tail-read"; then
        block "BLOCKED: 'head -50 file.md' →
  Read(file_path=\"/abs/path/to/file.md\", limit=50)

BLOCKED: 'tail -50 file.md' →
  Read(file_path=\"/abs/path/to/file.md\", offset=<total_lines - 50>, limit=50)

The Read tool with offset/limit reads the same byte range with
line-numbered output. Pipelines (head file | …) are still allowed.
See .claude/rules/bash-tool-replacements.md for the full table."
    fi

    if ast_matched "cat-write"; then
        block "REMINDER: Use the Write tool instead of 'cat > file' to create files. The Write tool is the proper way to write file contents."
    fi

    if ast_matched "echo-printf-write"; then
        block "REMINDER: Use the Write tool instead of 'echo/printf > file' to create files. The Write tool properly handles file creation and provides better error handling."
    fi

    if ast_matched "sed-inplace"; then
        block "REMINDER: Use the Edit tool instead of 'sed -i' to modify files. The Edit tool provides safer, more precise string replacements with proper error handling. (In-place edits of scratch files under /tmp are allowed.)"
    fi
fi

# Check for awk used for file modifications
if echo "$COMMAND" | grep -Eq "awk\s+.*>\s*['\"]?[^|]+" && \
   echo "$COMMAND" | grep -Eq "(>|>>)\s*['\"]?\\\$"; then
    block "REMINDER: Use the Edit tool instead of 'awk' for file modifications. The Edit tool is safer and more precise."
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

# Check for timeout command
#
# Escape hatch (issue #2041): a trailing `# allow-timeout` comment passes the
# block. `timeout` is usually redundant (the Bash tool has its own timeout
# parameter), but there is a legitimate minority case: bounding a process that
# genuinely never exits on its own — an interactive REPL, or a stdio MCP
# server launched to warm a build cache (`uvx --refresh --from git+… <srv>`).
# For those, the Bash-tool timeout kills the whole tool call and returns an
# error state, whereas `timeout N cmd` produces a clean exit 124 with the
# captured output — a strictly better signal. The comment is a deliberate,
# visible opt-in the agent must type per-command, so the default steer stays.
if echo "$COMMAND" | grep -Eq '^\s*timeout\s+' && \
   ! echo "$COMMAND" | grep -Eq '#[[:space:]]*allow-timeout\b'; then
    block "REMINDER: The 'timeout' command is usually unnecessary - the Bash tool has its own timeout parameter. Human approval time typically exceeds any timeout value anyway. Remove the timeout wrapper and use the command directly.

If the wrapped process genuinely never exits on its own (a REPL, a stdio
server warming a cache) and you need a clean in-command bound with captured
output, append a '# allow-timeout' comment to the command to pass this check."
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

# NOTE: the cat/head/tail read, echo/printf/cat write, sed -i, and task-output
# read detectors moved to the ast-grep structural path near the top of this hook.
# They are STYLE nudges (no-op when ast-grep is absent), not safety blocks. The
# long-pipeline block was also removed (demoted to the teach nudge, #1873/#2051/
# #2052). LOG_STREAM_RE survives below because the multi-grep chain block uses it.

# Log-stream sources emit an unstructured text stream with no --json/jq
# alternative, so `… | grep <inc> | grep -v <exc> | tail` is the *idiomatic* read
# path during incident diagnosis, not a data-processing scrape to nudge away from
# (issue #1833). The `<tool> logs` arm requires the `logs` subcommand to sit in
# the same pipe segment as a known log-producing CLI (`[^|]*[[:space:]]logs`) so an
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
# for (issue #1833). IS_LOG_STREAM is computed above.
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

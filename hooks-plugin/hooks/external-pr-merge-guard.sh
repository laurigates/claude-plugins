#!/usr/bin/env bash
# PreToolUse hook — refuses to let an agent merge a PR authored by someone other
# than the repo operator or a known bot.
#
# Why this exists: a public repo attracts drive-by PRs, and the merge tooling
# (both the human `ghsq`/`ghrb` wrappers and an agent's `gh pr merge`) is built
# for bulk-merging your OWN and bots' PRs. A stranger's PR riding that bulk
# reflex is merged code you never read — and PRs that add a workflow, a hook, or
# a shell script execute on merge. Vetting an external contribution is a human
# judgement call, so the agent path is closed and pointed at the human one.
#
# Behavior:
#   - `gh pr merge`, `gh api -X PUT .../pulls/N/merge`, and the GitHub MCP
#     merge_pull_request tool are checked.
#   - Author == the authenticated user, or a bot → allowed silently.
#   - Anyone else → denied, with the author, the association, and which touched
#     paths execute, plus the human command to run instead.
#   - Author cannot be determined (network, an unresolvable `$var` selector in a
#     loop, a bad PR number) → denied. "Can't verify" is not "safe".
#   - Any command that is not a merge → allowed, immediately.
#   - A command that merely MENTIONS `gh pr merge` — in prose, in a quoted
#     argument, in a heredoc body — is not a merge. Detection is positional:
#     the phrase must begin a command (issue #2307). The guard once denied
#     `gh pr create` because the PR body quoted the phrase, and the agent
#     retitled the user-visible PR to get past it.
#   - EVERY merge in the command is checked, not just the first (issue #2889):
#     `gh pr merge 5 && gh pr merge 5 -R other/repo` checks both. Arguments
#     are read as gh (cobra/pflag) reads them: -R/--repo attached, `=`,
#     clustered (`-sRx`), quoted (`"-R"`), or before `pr` (`gh -R x pr merge`);
#     -s/-m/-r/-d are booleans, -A is --author-email.
#   - The repository is the -R/--repo value; without one, the hook's cwd —
#     except when the command is exactly `cd <literal dir> && gh pr merge …`
#     (issue #2872), resolved in that directory. Without -R, anything earlier
#     in the command that changes which repository gh resolves — GH_REPO, any
#     other cd/pushd/env -C/GIT_DIR, a git remote/config change, gh repo
#     set-default, a gh function, a redirection into .git, a background `&` —
#     is DENIED as unverifiable, never resolved in the wrong place.
#   - An argument the shell expands at run time ($var, $(…), backticks, an
#     unquoted glob/brace/extglob), a variable command word in front of any
#     merge route (`$GH pr merge`, `$GH api …/pulls/N/merge`, `$GH api
#     graphql`), xargs/parallel, a piped `| bash`, GraphQL merge mutations, and
#     GraphQL queries fed on stdin are DENIED as unverifiable.
#   - A crash after a command is recognised as a possible merge DENIES (EXIT
#     trap). Without `onFailure: "block"` (any client before 2.1.295) a hook
#     error is non-blocking, so dying would let the merge run; the trap keeps
#     it closed on every client.
#
# Deliberately does NOT defer to permission mode "auto" (unlike
# branch-protection.sh). Auto mode's classifier models destructive-git and
# protected-branch risk; it has no notion of PR *authorship trust*, so deferring
# would not be avoiding a double-gate, it would be leaving the gap open.
#
# Toggle: a human operator can export CLAUDE_HOOKS_DISABLE_EXTERNAL_PR_MERGE=1
# in their shell environment. The toggle is only honored when set in the process
# environment — inline prefixes like
# `CLAUDE_HOOKS_DISABLE_EXTERNAL_PR_MERGE=1 gh pr merge 5` on the command line
# are intentionally NOT honored, so agents cannot self-serve the bypass.
#
# Matches: Bash, mcp__github__merge_pull_request
# Detects: gh pr merge / gh api PUT pulls/N/merge / MCP merge_pull_request
# Allows: your own PRs, bot PRs (release-please, renovate, dependabot, …), and
#         every non-merge command

set -euo pipefail

# Human-operator escape hatch: only honored from the process environment.
[ "${CLAUDE_HOOKS_DISABLE_EXTERNAL_PR_MERGE:-}" = "1" ] && exit 0

command -v gh >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Registered with `"onFailure": "block"` (Claude Code 2.1.295+), so a crash
# before the EXIT trap below is armed would block an ordinary command. Input
# jq cannot parse, or whose tool_input is not an object, is not a tool call
# this hook can judge: exit 0, explicitly.
INPUT=$(cat)
printf '%s' "$INPUT" | jq -e 'type == "object" and ((.tool_input // {}) | type == "object")' >/dev/null 2>&1 || exit 0
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')

deny() {
  local reason="$1" json_reason
  json_reason=$(printf '%s' "$reason" | jq -Rs .)
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$json_reason"
  exit 0
}

# Fail CLOSED on a crash. Once a tool call may be a merge, any unexpected exit
# — a bash-4 builtin missing on bash 3.2 (exit 127), an unbound variable, a
# failed assignment under set -e — is a non-blocking hook error on clients
# without `onFailure: "block"` (before 2.1.295), and the merge would run
# unchecked. With the key it blocks, but as an opaque hook error rather than a
# deny that says why. deny() exits 0, and so does every allow
# path, so only a crash reaches the deny here. Armed only after the cheap
# non-merge bail-outs, so a crash cannot block an ordinary command.
# shellcheck disable=SC2317  # invoked indirectly, as an EXIT trap
fail_closed_on_crash() {
  local rc=$?
  [ "$rc" -eq 0 ] && return 0
  trap - EXIT
  deny "Refusing this command: the merge guard hit an internal error (exit ${rc}) while checking it for a PR merge, so it cannot tell whether — or whose PR — it merges. 'Cannot verify' is not 'safe'. Run the merge as a plain command (gh pr merge <number> -R OWNER/REPO), or ask the user."
}

# ---------------------------------------------------------------------------
# Work out which PR (if any) this tool call would merge.
#   PR_SELECTOR — number / URL / branch, or empty to mean "current branch's PR"
#   PR_REPO     — OWNER/REPO, or empty for the repo at the cwd
# ---------------------------------------------------------------------------
PR_SELECTOR=""
PR_REPO=""
# One \037-separated record per merge the tool call would perform; see the
# record format above the check loop at the end of this file.
DETECT=""

case "$TOOL_NAME" in
  mcp__github__merge_pull_request)
    trap fail_closed_on_crash EXIT
    PR_SELECTOR=$(printf '%s' "$INPUT" | jq -r '.tool_input.pullNumber // .tool_input.pull_number // empty')
    OWNER=$(printf '%s' "$INPUT" | jq -r '.tool_input.owner // empty')
    REPO=$(printf '%s' "$INPUT" | jq -r '.tool_input.repo // empty')
    # These values go into a \037-separated, newline-ended record, exactly as
    # the Bash command text does, so they get the same anti-forging guard: a
    # \037 in `repo` would cut the record at a repository the tool was never
    # asked to merge in (PR #3054 review).
    case "${PR_SELECTOR}${OWNER}${REPO}" in
      *$'\036'*|*$'\037'*|*$'\n'*|*$'\r'*)
        deny "Refusing this merge: its owner, repo or pullNumber contains a control character (newline or \\036/\\037), so this hook cannot check which PR it merges. Pass plain values and retry." ;;
    esac
    [ -n "$OWNER" ] && [ -n "$REPO" ] && PR_REPO="$OWNER/$REPO"
    DETECT=$(printf 'merge\037%s\037%s\037\037\037' "$PR_SELECTOR" "$PR_REPO")
    ;;
  Bash)
    COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
    [ -z "$COMMAND" ] && exit 0

    # Fast bail-out: the overwhelming majority of Bash calls are not merges.
    # This is a cheap SUPERSET prefilter only — it says "the phrase appears
    # somewhere in the text", which is NOT the same as "this command merges".
    # DETECT below is what actually decides. Anything the structural pass can
    # match must also match here, or it would never be reached — so it runs on
    # the text with quotes and backslashes removed (`gh pr "merge"`, `m\erge`),
    # and it is deliberately loose: any `merge` (gh pr merge, the REST route,
    # the GraphQL mergePullRequest / enablePullRequestAutoMerge mutations) and
    # any `graphql` call (a query read from @file may hold a merge mutation;
    # issue #2889).
    if ! grep -Eiq 'merge|graphql' <<<"$(tr -d "\"'\\\\" <<<"$COMMAND")"; then
      exit 0
    fi
    trap fail_closed_on_crash EXIT

    # -----------------------------------------------------------------------
    # Structural pass (issue #2307). The old code grepped the raw command text,
    # so ANY mention of the phrase read as a merge: `echo "docs: … gh pr merge"`
    # was denied, and a real `gh pr create` was blocked because its --body
    # heredoc quoted the phrase (the agent then RETITLED the user-visible PR to
    # get past the guard — the guard distorting product content is the bug).
    #
    # The awk below walks the command once and produces a length-preserving
    # MASKED copy in which heredoc bodies and quoted argument values are
    # replaced by `X`. Because masking is character-for-character, byte offsets
    # in the mask and in the original agree exactly, so structure is decided on
    # the mask while values are still read from the original.
    #
    # It then splits the mask into statements at unquoted `;`, `&`, `|`, `(`,
    # `)`, backticks and newlines, strips leading `VAR=value` assignments,
    # shell keywords (`do`, `then`, …), redirections and command wrappers from
    # each, and reports EVERY statement whose command word is a merge, one
    # record each (issue #2889: reporting only the first let a second,
    # external merge through). Each record carries the hazards found in the
    # text before it, which decide whether its repository can be known.
    #
    # A quoted string OR a heredoc body is scanned as nested command text (not
    # masked) when the statement's effective command word is a shell invoker
    # (`bash -c '…'`, `eval "…"`, `bash <<EOF … EOF`) or runs a string
    # argument (`watch '…'`, `env -S '…'`, `ssh host '…'`), so feeding a merge
    # to a shell as script text does not evade the guard. "Effective" means
    # the wrapper prefix is skipped first, so `sudo -u ci bash -c '…'` is a
    # shell invoker too. Code that RUNS inside otherwise-masked text — `$(…)`
    # and backticks inside double quotes, and inside an unquoted heredoc
    # (<<EOF, where markdown backticks execute) — is command text too.
    #
    # Why awk and not `ast-grep --lang bash` (used by bash-antipatterns.sh):
    # that hook is a STYLE nudge and is designed to fail OPEN where ast-grep is
    # absent. This hook is a security guard — a second, weaker code path for
    # "ast-grep missing" is exactly the path an agent would end up on, and
    # failing open there would hand back the hole this hook exists to close.
    # awk is POSIX-guaranteed, so there is one path and it is always structural.
    # -----------------------------------------------------------------------
    # The scan, as a function of (text, enclosing prefix, enclosing background
    # flag) so it can be re-run over command substitutions it hands back.
    detect_scan() {
      printf '%s' "$1" | OUTERPRE="$2" OUTERBG="$3" awk '
      # scan(t): read one shell word the way the shell would, WITHOUT running
      # anything. Sets SV (the word with quotes and escapes removed — what the
      # program receives when nothing expands), SDYN (a `$` or backtick outside
      # single quotes: the word is not known until the shell runs),
      # SUDYN (one fully UNQUOTED: it can also split into several words),
      # SGLOB (an unquoted glob, brace or zsh-extendedglob character: the word
      # can expand to file names — a file named `-R` turns `-?` into `-R`) and
      # SCOMMENT (the word starts an unquoted `#` comment).
      function scan(t,   n, i, c, q, nx) {
        SV = ""; SDYN = 0; SUDYN = 0; SGLOB = 0; SCOMMENT = 0
        n = length(t); q = 0; i = 1
        while (i <= n) {
          c = substr(t, i, 1)
          if (q == 1) { if (c == SQ) q = 0; else SV = SV c; i++; continue }
          if (q == 2) {
            if (c == DQ) { q = 0; i++; continue }
            if (c == "\\") {
              nx = substr(t, i + 1, 1)
              if (nx == "\n") { i += 2; continue }
              if (nx == "$" || nx == BT || nx == DQ || nx == "\\") { SV = SV nx; i += 2; continue }
            }
            if (c == "$" || c == BT) SDYN = 1
            SV = SV c; i++; continue
          }
          if (c == "\\") { nx = substr(t, i + 1, 1); if (nx != "\n") SV = SV nx; i += 2; continue }
          if (c == SQ) { q = 1; i++; continue }
          if (c == DQ) { q = 2; i++; continue }
          if (c == "$" || c == BT) { SDYN = 1; SUDYN = 1 }
          else if (c == "#" && i == 1) SCOMMENT = 1
          else if (index("?*[{}^#", c) || (c == "~" && i > 1)) SGLOB = 1
          SV = SV c; i++
        }
      }
      # tokenize(mask, orig): split a statement into words on the MASK (so a
      # blank inside a quoted value does not split it) and read each word back
      # from the original at the same offsets. Fills TM/TO/TP, returns the count.
      function tokenize(mm, oo,   n, i, s, c, nt) {
        n = length(mm); nt = 0; i = 1
        while (i <= n) {
          c = substr(mm, i, 1)
          if (c == " " || c == "\t" || c == "\n") { i++; continue }
          s = i
          while (i <= n) {
            c = substr(mm, i, 1)
            if (c == " " || c == "\t" || c == "\n") break
            if (c == "\\") i++
            i++
          }
          nt++; TM[nt] = substr(mm, s, i - s); TO[nt] = substr(oo, s, i - s); TP[nt] = s
        }
        return nt
      }
      function base(w) { sub(/.*\//, "", w); return w }
      # capture_sub(i): buf[i] starts `$(` or a backtick inside double quotes.
      # Record the substitution text, and the command text before it (the
      # context its hazards are judged in), for the caller to scan.
      function capture_sub(i,   j, d, qq, ch, e) {
        if (substr(buf, i, 1) == BT) {
          j = i + 1
          while (j <= n && substr(buf, j, 1) != BT) { if (substr(buf, j, 1) == "\\") j++; j++ }
          e = j; i += 1
        } else {
          j = i + 2; d = 1; qq = 0
          while (j <= n && d > 0) {
            ch = substr(buf, j, 1)
            if (qq == 1) { if (ch == SQ) qq = 0 }
            else if (ch == "\\") j++
            else if (qq == 2) { if (ch == DQ) qq = 0 }
            else if (ch == SQ) qq = 1
            else if (ch == DQ) qq = 2
            else if (ch == "(") d++
            else if (ch == ")") d--
            j++
          }
          e = j - 1; i += 2
        }
        # The recursive scan owns everything up to e — a backtick inside a
        # quoted heredoc inside this $(…) is prose there, not a substitution.
        capend = e
        nsub++; subt[nsub] = substr(buf, i, e - i); subp[nsub] = substr(buf, 1, i - 1)
      }
      function bad_word() { return SDYN ? "dyn" : (SGLOB ? "glob" : (SV ~ QCH ? "quote" : "")) }
      # ghparse(i0, nt): read `gh …` from token i0 the way gh (cobra/pflag)
      # does. Flags may come before `pr` and between `pr` and `merge`
      # (`gh -R x pr merge 5`, `gh pr -R x merge 5`). Returns 1 for a merge
      # and sets SEL (selector), REP (--repo/-R value), UNV (why the arguments
      # cannot be verified, or empty), REDGIT (a redirection into a .git path)
      # and SUB1 (the first subcommand word, e.g. "api").
      #
      # Valued flags of gh pr merge — and ONLY those, so the word after a
      # boolean is not skipped: -b/--body, -F/--body-file, -t/--subject,
      # -A/--author-email, --match-head-commit and -R/--repo. -s (--squash),
      # -m (--merge), -r (--rebase), -d (--delete-branch) are booleans; gh pr
      # merge has no --title. Short flags cluster (`-sR x`, `-sRx`), take an
      # attached value (`-Rx`, `-R=x`), and quotes do not hide a flag (`"-R"`).
      function ghparse(i0, nt,   j, sv, skip, endo, name, val, hasv, k, ch, rest, pre, lenient, bad) {
        SEL = ""; HAVESEL = 0; REP = ""; UNV = ""; SUB1 = ""; REDGIT = 0
        ph = 0; skip = 0; endo = 0; pre = ""
        for (j = i0 + 1; j <= nt; j++) {
          scan(TO[j]); sv = SV
          if (SCOMMENT) break
          if (skip == 3) { if (sv ~ /\.git/) REDGIT = 1; skip = 0; continue }
          if (skip) {
            if (skip == 2) { REP = sv; bad = bad_word(); if (bad != "") UNV = bad }
            else if (SUDYN || SGLOB) UNV = (SUDYN ? "dyn" : "glob")
            skip = 0; continue
          }
          # A redirection, decided on the MASK so a quoted ">" stays an argument.
          if (TM[j] ~ ("^" RED)) {
            if (TM[j] ~ ("^" RED "$")) skip = 3
            else { rest = TO[j]; sub("^" RED, "", rest); scan(rest); if (SV ~ /\.git/) REDGIT = 1 }
            continue
          }
          if (ph == 2 && !endo && sv == "--") { endo = 1; continue }
          if (!endo && sv ~ /^-./) {
            lenient = 0
            if (sv ~ /^--/) {
              name = sv; hasv = 0
              if (index(sv, "=")) { name = substr(sv, 1, index(sv, "=") - 1); val = substr(sv, index(sv, "=") + 1); hasv = 1 }
              if (name == "--repo") { if (hasv) REP = val; else skip = 2 }
              else if (ph == 2 && (name in LVAL)) { if (hasv) lenient = 1; else skip = 1 }
            } else {
              for (k = 2; k <= length(sv); k++) {
                ch = substr(sv, k, 1)
                if (ch == "R" || (ph == 2 && index("bFtA", ch))) {
                  rest = substr(sv, k + 1); sub(/^=/, "", rest)
                  if (rest != "") { if (ch == "R") REP = rest; else lenient = 1 }
                  else skip = (ch == "R" ? 2 : 1)
                  break
                }
              }
            }
            # A non-repo flag with its value attached (`--subject="$(…)"`) is
            # one word whatever the value expands to, unless it is unquoted.
            if (lenient) { if (SUDYN || SGLOB) bad = (SUDYN ? "dyn" : "glob"); else bad = "" }
            else bad = bad_word()
            if (bad != "") { if (ph == 2) UNV = bad; else pre = bad }
            continue
          }
          bad = bad_word()
          if (ph < 2) {
            # An unknowable word before `merge` could be a flag or `pr` itself.
            if (bad != "") { pre = bad; continue }
            if (ph == 0 && sv == "pr") { ph = 1; continue }
            if (sv == "merge" && (ph == 1 || pre != "")) { ph = 2; if (pre != "") UNV = pre; continue }
            if (ph == 0) SUB1 = sv
            return 0
          }
          if (bad != "") UNV = bad
          if (!HAVESEL) { SEL = sv; HAVESEL = 1 }
        }
        if (skip == 2 && UNV == "") UNV = "dangling"
        return (ph == 2)
      }
      # The text with quotes and backslashes dropped, for hazard-word scans.
      function dequote(t) { gsub(QCH, "", t); return t }
      # emit_merge: one record per merge, with the hazards that decide whether
      # its repository can be known. Fields are \037-separated:
      #   KIND SEL REPO UNV FLAGS EXTRA
      function emit_merge(kind, sel, rep, unv, gpos, a, wrapped, trunc,   scope, d, l, fl) {
        # OUTERPRE: the enclosing command text before this one, when this text
        # is a command substitution the caller handed back (SUB).
        scope = OUTERPRE substr(buf, 1, gpos - 1)
        # Inside a loop the text AFTER the merge runs before its next iteration.
        if (dequote(scope) ~ /(^|[^A-Za-z0-9_-])(do|while|until)([^A-Za-z0-9_-]|$)/) scope = OUTERPRE buf
        d = dequote(scope); l = dequote(substr(buf, a, gpos - a))
        fl = ""
        if (trunc) fl = fl ",trunc"
        if (d ~ DIRW || d ~ GITENV || d ~ /\.git([^A-Za-z0-9_]|$)/ || d ~ GHFUNC || d ~ SRCDOT || REDGIT \
            || (wrapped && l ~ CHDIRFLAG)) fl = fl ",dirchg"
        if (d ~ /(^|[^A-Za-z0-9_-])(checkout|switch)([^A-Za-z0-9_-]|$)/) fl = fl ",branchchg"
        # GH_REPO spelled out, or an environment entry whose NAME is only known
        # at run time (`export $V=x`, `env "$V" gh …` with V=GH_REPO=x).
        if (d ~ /GH_REPO/ || d ~ DYNEXPORT || (wrapped && l ~ /[$`]/)) fl = fl ",ghrepo"
        if (d ~ GHHOSTW) fl = fl ",ghhost"
        if (hasbg || OUTERBG) fl = fl ",bg"
        gsub(/[\n\037]/, " ", sel); gsub(/[\n\037]/, " ", rep)
        printf "%s\037%s\037%s\037%s\037%s\037%s\n", kind, sel, rep, unv, fl, ""
      }
      function emit_other(kind, rep, sel, unv, extra, gpos,   d) {
        d = dequote(OUTERPRE substr(buf, 1, gpos - 1))
        printf "%s\037%s\037%s\037%s\037%s\037%s\n", kind, sel, rep, unv, (d ~ GHHOSTW ? ",ghhost" : ""), extra
      }
      # api_scan: a client that can CALL the REST/GraphQL API (gh api, curl, …).
      # Every literal REST merge route is one record; a route whose owner,
      # repo or number is not a plain literal (`repos/$R/pulls/5/merge`,
      # `{owner}/{repo}`) cannot be verified. GraphQL merges name the PR by
      # node id, so they are not resolvable here at all.
      #
      # dynw: the command word is a variable, so it is not even known to be gh
      # — every route and every GraphQL call is unverifiable (UNV cmdword).
      # piped: the statement reads a pipe on stdin. A GraphQL call whose stdin
      # is a pipe, a heredoc, a herestring or a `<` redirection (other than
      # /dev/null) may take its query from there, which this hook cannot read.
      function api_scan(i0, nt, gpos, dynw, piped,   j, txt, qdyn, lt, t, p, found, pp, stdin, rt, skipn) {
        txt = ""; qdyn = 0; stdin = piped; skipn = 0
        for (j = i0; j <= nt; j++) {
          scan(TO[j]); if (SCOMMENT) break
          if (skipn) { skipn = 0; if (SV != "/dev/null") stdin = 1 }
          else if (TM[j] ~ ("^" RED) && TM[j] ~ /^0?</) {
            if (TM[j] ~ ("^" RED "$")) skipn = 1
            else { rt = TO[j]; sub("^" RED, "", rt); scan(rt); if (SV != "/dev/null") stdin = 1; scan(TO[j]) }
          }
          txt = txt " " SV
          if (SDYN && tolower(SV) ~ /query/) qdyn = 1
        }
        lt = tolower(txt)
        if (lt ~ /graphql/) {
          if (dynw) { emit_other("graphql", "", "", "", "cmdword", gpos); return 1 }
          if (lt ~ /mergepullrequest|enablepullrequestautomerge/) { emit_other("graphql", "", "", "", "mutation", gpos); return 1 }
          if (txt ~ /(=|[ \t])@/ || lt ~ /--input/) { emit_other("graphql", "", "", "", "file", gpos); return 1 }
          if (stdin) { emit_other("graphql", "", "", "", "stdin", gpos); return 1 }
          if (qdyn) { emit_other("graphql", "", "", "", "dyn", gpos); return 1 }
        }
        # Returns how many records it emitted, so a caller probing a variable
        # command word can tell "reached an API route" from "nothing here".
        t = txt; found = 0
        while (match(t, /repos\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+\/pulls\/[0-9]+\/merge/)) {
          p = substr(t, RSTART, RLENGTH); split(p, pp, "/")
          emit_other("api", pp[2] "/" pp[3], pp[5], (dynw ? "cmdword" : ""), "", gpos); found++
          t = substr(t, 1, RSTART - 1) " " substr(t, RSTART + RLENGTH)
        }
        if (t ~ /pulls\/[^ \t]*\/merge/) { emit_other("api", "", "", (dynw ? "cmdword" : "apipath"), "", gpos); found++ }
        return found
      }
      BEGIN {
        SQ = sprintf("%c", 39); DQ = "\""; BT = sprintf("%c", 96)
        QCH = "[" DQ SQ "\\\\]"
        RED = "([0-9]*(<<<|>>|>[|]|>|<|<>|>&|<&)|&>>|&>)"
        split("--body --body-file --subject --author-email --match-head-commit --repo", lv, " ")
        for (k in lv) LVAL[lv[k]] = 1
        split("command builtin exec nohup env stdbuf nice ionice setsid caffeinate sudo doas timeout xargs find parallel watch script flock chronic uv uvx npx bunx coproc unbuffer chrt taskset systemd-run firejail strace ltrace valgrind mise direnv ssh", wl, " ")
        for (k in wl) WRAP[wl[k]] = 1
        split("gh curl wget http https xh hurl", al, " ")
        for (k in al) API[al[k]] = 1
        # Anything before the merge that can move it to another repository or
        # change which repository gh resolves for the directory.
        DIRW = "(^|[^A-Za-z0-9_-])(cd|pushd|popd|chdir|source|eval|alias|set-default|remote|config|worktree|clone|init|direnv|ssh)([^A-Za-z0-9_-]|$)"
        GITENV = "GIT_(DIR|WORK_TREE|CEILING_DIRECTORIES|DISCOVERY_ACROSS_FILESYSTEM|CONFIG|COMMON_DIR|NAMESPACE)"
        GHFUNC = "(^|[^A-Za-z0-9_-])gh[ \t]*[(][ \t]*[)]|function[ \t]+gh([^A-Za-z0-9_-]|$)"
        SRCDOT = "(^|[;&|({\n])[ \t]*[.][ \t]"
        CHDIRFLAG = "(^|[ \t])(-C|--chdir|-D|--cd|--wd|--workdir|--directory|--cwd|-execdir)"
        GHHOSTW = "GH_HOST|GH_ENTERPRISE_TOKEN|GH_CONFIG_DIR|XDG_CONFIG_HOME|(^|[^A-Za-z0-9_])HOME="
        DYNEXPORT = "(^|[^A-Za-z0-9_-])(export|declare|typeset|readonly|local|set|env)[ \t][^;&|\n]*[$`]"
        OUTERPRE = ENVIRON["OUTERPRE"]; OUTERBG = (ENVIRON["OUTERBG"] == "1")
      }
      { buf = (NR > 1 ? buf "\n" $0 : $0) }
      END {
        SQ = sprintf("%c", 39); DQ = "\""; BT = sprintf("%c", 96)
        split("eval bash sh zsh ksh dash nix-shell", sl, " "); for (k in sl) shcmd[sl[k]] = 1
        # Commands that run a STRING argument as a command line, so a quoted
        # argument of theirs is command text exactly like `bash -c "…"`:
        # `watch "gh pr merge …"`, `env -S "…"`, `ssh host "…"`, `su -c "…"`.
        split("watch script flock su runuser ssh tmux screen sg env", rl, " "); for (k in rl) strrun[rl[k]] = 1

        asg_re    = "^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*"
        kw_re     = "^(do|then|else|elif|if|while|until|time|!|[{])"
        kww_re    = "^(do|then|else|elif|if|while|until|time|!|[{])$"
        # A redirection is not a command word and not a PR selector: bash strips
        # it from the argv gh receives, so `gh pr merge 2>/dev/null 2231` really
        # merges 2231 and `xargs -n1 gh pr merge < prs.txt` really merges.
        red_body  = "([0-9]*(<<<|>>|>|<|<>|>&|<&)|&>>|&>)"
        red_re    = "^" red_body
        # Wrappers that RUN another command, so the merge is theirs to execute.
        wnames    = "command|builtin|exec|nohup|env|stdbuf|nice|ionice|setsid|caffeinate|sudo|doas|timeout|xargs|find|parallel|watch|script|flock|chronic|uv|uvx|npx|bunx|coproc|unbuffer|chrt|taskset|systemd-run|firejail|strace|ltrace|valgrind|mise|direnv|ssh"
        wrap_re   = "^(" wnames ")"
        wrapw_re  = "^(" wnames ")$"
        warg_re   = "^(-[^ \t]*|[0-9]+[smhd]?)"

        n = length(buf); m = ""; q = 0; nomask = 0; hsub = 0; hbt = 0; nsub = 0; capend = 0
        in_hd = 0; hd_delim = ""; hd_strip = 0; hd_nomask = 0; hd_unq = 0; curline = ""; pn = 0
        ns = 1; st[1] = 1; cw = ""; cw_done = 0; nest = 0; wrapm = 0
        i = 1
        while (i <= n) {
          c = substr(buf, i, 1)
          if (in_hd) {                                   # inside a heredoc body
            if (c == "\n") {
              t = curline; if (hd_strip) sub(/^\t+/, "", t)
              m = m "\n"; curline = ""
              if (hd_nomask || hsub || hbt) { st[++ns] = i + 1; cw = ""; cw_done = 0; wrapm = 0 }
              if (t == hd_delim) {
                hsub = 0; hbt = 0
                if (pn > 0) { hd_delim = hdq[1]; hd_strip = hds[1]; hd_nomask = hdn[1]; hd_unq = hdu[1]
                              for (k = 1; k < pn; k++) { hdq[k] = hdq[k+1]; hds[k] = hds[k+1]; hdn[k] = hdn[k+1]; hdu[k] = hdu[k+1] }
                              pn-- }
                else { in_hd = 0; hd_nomask = 0 }
              }
              i++; continue
            }
            mc = (hd_nomask ? c : "X")
            # An UNQUOTED heredoc (<<EOF, not <<"EOF") still runs $(…) and `…`
            # in its body — markdown code spans included — so those regions
            # are command text, not prose: `cat <<EOF` + `gh pr merge 5` merges.
            if (!hd_nomask && hd_unq) {
              if (c == "\\" && substr(buf, i + 1, 1) != "\n") {
                m = m "XX"; curline = curline c substr(buf, i + 1, 1); i += 2; continue
              }
              if (hbt) { mc = c; if (c == BT) { hbt = 0; st[++ns] = i + 1 } else if (index(";&|()", c)) st[++ns] = i + 1 }
              else if (hsub > 0) {
                mc = c; if (c == "(") hsub++; else if (c == ")") hsub--
                if (index(";&|()", c)) st[++ns] = i + 1
              }
              else if (c == BT) { hbt = 1; mc = c; st[++ns] = i + 1 }
              else if (c == "$" && substr(buf, i + 1, 1) == "(") {
                hsub = 1; m = m "$("; curline = curline "$("; i += 2; st[++ns] = i; continue
              }
            }
            m = m mc; curline = curline c
            i++; continue
          }
          if (q != 1 && c == "\\") {                     # escape / line continuation
            nx = substr(buf, i + 1, 1)
            if (nx == "\n") m = m "  "
            else if (q == 0) { m = m "\\" nx; if (!cw_done) cw = cw nx }
            else m = m "\\" (nomask ? nx : "X")
            i += 2; continue
          }
          if (q != 0) {                                  # inside a quoted value
            # `"$(gh pr merge 5)"` and `"`gh pr merge 5`"` RUN: a command
            # substitution inside double quotes is command text. The quoted
            # value stays one masked word of its own statement (so
            # `--body "$(cat …)" -R x` still reads the -R), and the
            # substitution text is handed back to the caller, which runs this
            # same scan over it as a command of its own (see SUB below).
            if (q == 2 && !nomask && i > capend && ((c == "$" && substr(buf, i + 1, 1) == "(") || c == BT)) capture_sub(i)
            if ((q == 1 && c == SQ) || (q == 2 && c == DQ)) {
              q = 0; m = m c; cwq = 0
              if (nomask) { st[++ns] = i + 1; nomask = 0 }
            } else if (nomask && (c == ";" || c == "&" || c == "|" || c == "(" || c == ")" || c == BT || c == "\n")) {
              # Nested command TEXT, so its operators separate statements too:
              # `bash -c "echo hi; gh pr merge 5"` is two commands, not one.
              m = m c; st[++ns] = i + 1; cw = ""; cw_done = 0; wrapm = 0
            } else { m = m (nomask ? c : "X"); if (cwq) cw = cw c }
            i++; continue
          }
          if (c == SQ || c == DQ) {
            q = (c == SQ ? 1 : 2); m = m c; nomask = nest
            if (nomask) st[++ns] = i + 1
            # A quoted command word is still that command: `"bash" -c "…"`.
            cwq = !cw_done
            i++; continue
          }
          # `` ` `` splits like `(` does — legacy command substitution starts a
          # new command, so `X=`gh pr merge 5`` is a merge, not an assignment.
          if (c == ";" || c == "&" || c == "|" || c == "(" || c == ")" || c == BT || c == "\n") {
            m = m c; st[++ns] = i + 1; cw = ""; cw_done = 0; nest = 0; wrapm = 0
            if (c == "\n" && pn > 0) {                   # queued heredoc starts here
              hd_delim = hdq[1]; hd_strip = hds[1]; hd_nomask = hdn[1]; hd_unq = hdu[1]
              for (k = 1; k < pn; k++) { hdq[k] = hdq[k+1]; hds[k] = hds[k+1]; hdn[k] = hdn[k+1]; hdu[k] = hdu[k+1] }
              pn--; in_hd = 1; curline = ""
            }
            i++; continue
          }
          if (c == " " || c == "\t") {
            m = m c
            # Work out the EFFECTIVE command word of this statement, so nest
            # (does a shell interpret the quoted string / heredoc body?)
            # survives an assignment, a keyword, or a wrapper in front of it.
            if (!cw_done && cw != "") {
              cwb = cw; sub(/.*\//, "", cwb)                   # /bin/bash → bash
              if (cw ~ /^[A-Za-z_][A-Za-z0-9_]*=/) cw = ""    # leading assignment
              else if (cwb in shcmd) { cw_done = 1; nest = 1 }
              else if (cwb in strrun) { cw_done = 1; nest = 1 }
              else if (cw ~ kww_re) cw = ""                   # shell keyword
              else if (cwb ~ wrapw_re) { cw = ""; wrapm = 1 }  # `sudo`, `env`, …
              else if (wrapm) cw = ""                         # args of a wrapper
              else cw_done = 1
            }
            i++; continue
          }
          # A `<<<` herestring is a plain redirection: consume all three
          # characters here. Scanning on char by char re-detected `<<` at the
          # SECOND `<`, queued a phantom heredoc delimited by the herestring
          # word, and masked every following line as its body — so
          # `gh pr merge 5 <<< x` + newline + `gh pr merge 6 -R other/repo`
          # never checked the second merge (PR #3054 review).
          if (substr(buf, i, 3) == "<<<") {
            m = m "<<<"; if (!cw_done) cw = cw "<<<"
            i += 3; continue
          }
          if (c == "<" && substr(buf, i + 1, 1) == "<") {
            j = i + 2; strip = 0
            if (substr(buf, j, 1) == "-") { strip = 1; j++ }
            while (substr(buf, j, 1) == " " || substr(buf, j, 1) == "\t") j++
            qc = substr(buf, j, 1); delim = ""
            if (qc == SQ || qc == DQ) {
              j++
              while (j <= n && substr(buf, j, 1) != qc) { delim = delim substr(buf, j, 1); j++ }
              j++
            } else {
              while (j <= n && substr(buf, j, 1) ~ /[A-Za-z0-9_]/) { delim = delim substr(buf, j, 1); j++ }
            }
            # hdn: is this body script text? `bash <<EOF … EOF` feeds a shell,
            # so its body is scanned exactly as `bash -c "…"` already is;
            # `cat <<EOF` / `gh pr create --body-file - <<EOF` feed prose.
            if (delim != "") { pn++; hdq[pn] = delim; hds[pn] = strip; hdn[pn] = nest
                               hdu[pn] = !(qc == SQ || qc == DQ)
                               m = m substr(buf, i, j - i); i = j; continue }
          }
          m = m c
          if (!cw_done) cw = cw c
          i++
        }
        st[ns + 1] = n + 2

        # A lone `&` with anything after it runs a command ALONGSIDE the
        # merge (`gh pr merge 5 & git remote set-url origin …`), which can
        # change the repository gh resolves while it runs. `&&`, `|&`, `>&`,
        # `&>` and `<&` are not backgrounding; a trailing `&` races nothing.
        hasbg = 0
        for (k = 1; k <= n; k++) {
          if (substr(m, k, 1) != "&") continue
          pc = (k > 1) ? substr(m, k - 1, 1) : ""; nc = substr(m, k + 1, 1)
          if (pc == "&" || pc == ">" || pc == "<" || pc == "|" || nc == "&" || nc == ">") continue
          if (substr(m, k + 1) ~ /[^ \t\n]/) { hasbg = 1; break }
        }

        for (s = 1; s <= ns; s++) {
          a = st[s]; b = st[s + 1] - 2
          if (b > n) b = n
          if (b < a) continue
          sm = substr(m, a, b - a + 1); so = substr(buf, a, b - a + 1)
          off = 0; wrapped = 0
          while (1) {
            while (substr(sm, off + 1, 1) == " " || substr(sm, off + 1, 1) == "\t") off++
            rest = substr(sm, off + 1)
            if (match(rest, asg_re)) {
              nxt = substr(rest, RLENGTH + 1, 1)
              if (nxt == "" || nxt == " " || nxt == "\t") { off += RLENGTH; continue }
            }
            if (match(rest, kw_re)) {
              nxt = substr(rest, RLENGTH + 1, 1)
              if (nxt == "" || nxt == " " || nxt == "\t") { off += RLENGTH; continue }
            }
            if (match(rest, red_re)) {                   # leading redirection
              tok = rest; sub(/[ \t].*$/, "", tok); off += length(tok)
              if (tok ~ ("^" red_body "$")) {             # bare operator: skip its target
                while (substr(sm, off + 1, 1) == " " || substr(sm, off + 1, 1) == "\t") off++
                t2 = substr(sm, off + 1); sub(/[ \t].*$/, "", t2); off += length(t2)
              }
              continue
            }
            if (match(rest, wrap_re)) {
              nxt = substr(rest, RLENGTH + 1, 1)
              if (nxt == " " || nxt == "\t") { off += RLENGTH; wrapped = 1; continue }
            }
            if (wrapped && match(rest, warg_re)) {
              nxt = substr(rest, RLENGTH + 1, 1)
              if (nxt == "" || nxt == " " || nxt == "\t") { off += RLENGTH; continue }
            }
            break
          }
          cm = substr(sm, off + 1); co = substr(so, off + 1)
          nt = tokenize(cm, co)
          if (nt == 0) continue
          # A quoted, escaped or path-qualified wrapper is still a wrapper:
          # `"sudo" gh …`, `\env gh …`, `/usr/bin/env gh …`.
          scan(TO[1]); if (base(SV) in WRAP) wrapped = 1
          # Was this statement cut short mid-argument? A BARE backtick used as
          # a VALUE (gh pr merge 5 -R `cmd`), as opposed to one that WRAPS the
          # whole invocation (buf[a-1] == BT), or a `(` (an extglob such as
          # `-@(R)`, or `$(…)`) silently drops everything after it — including
          # a --repo/-R value or the selector — so gh pr view would resolve the
          # WRONG PR or repo and could come back trusted.
          trunc = 0; delimc = ""
          if (b < n) {
            delimc = substr(buf, b + 1, 1)
            prevc = (a > 1) ? substr(buf, a - 1, 1) : ""
            if ((delimc == BT && prevc != BT) || delimc == "(") trunc = 1
          }
          # Anchored at the command word, unless a wrapper has been seen: a
          # wrapper EXECUTES what follows it, behind arguments the stripper
          # cannot classify (`sudo -u ci gh pr merge 5`, `find … -exec gh …`),
          # so every word of the statement is a candidate. Words are cut on
          # the MASK, so a quoted phrase behind a wrapper
          # (`timeout 60 echo "gh pr merge 5"`) is one word, and still prose.
          # Every merge in the command is reported — not just the first — so
          # `gh pr merge 5 && gh pr merge 5 -R other/repo` checks both (#2889).
          # A shell reading its script from a pipe (`echo "…" | bash`) runs text
          # this hook only saw as a quoted argument of something else.
          sepc = (a > 1) ? substr(m, a - 1, 1) : ""; sepp = (a > 2) ? substr(m, a - 2, 1) : ""
          piped = ((sepc == "|" && sepp != "|") || (sepc == "&" && sepp == "|"))
          if (base(SV) in shcmd && ((sepc == "|" && sepp != "|") || (sepc == "&" && sepp == "|"))) {
            hasc = 0
            for (i = 2; i <= nt; i++) { scan(TO[i]); if (SV ~ /^-[A-Za-z]*c/) hasc = 1 }
            if (!hasc) { emit_merge("merge", "", "", "stdin", a + off, a, wrapped, trunc); continue }
          }
          # Nested command text (`bash -c "…"`, `eval "…"`) whose closing quote
          # is followed by more words: the shell joins them (`eval "gh pr merge
          # 5 -R" "x/y"`), so the statement this hook sees is incomplete.
          concat = 0
          if (b < n && (delimc == SQ || delimc == DQ)) {
            rest = substr(m, b + 2); sub("[;&|()\n" BT "].*", "", rest)
            if (rest ~ /[^ \t]/) concat = 1
          }
          for (i = 1; i <= nt; i++) {
            if (i > 1 && !wrapped) break
            scan(TO[i]); w = base(SV); wdyn = SDYN
            gpos = a + off + TP[i] - 1
            if (w == "gh" || wdyn) {
              if (ghparse(i, nt)) {
                if (w != "gh" && UNV == "") UNV = "cmdword"
                if (concat && UNV == "") UNV = "quote"
                # xargs/parallel append arguments read at run time.
                if (wrapped && UNV == "" && dequote(substr(buf, a, gpos - a)) ~ /(^|[ \t\/])(xargs|parallel)([ \t]|$)/) UNV = "stdinargs"
                emit_merge("merge", SEL, REP, UNV, gpos, a, wrapped, trunc)
                break
              }
              # A variable command word (`$GH api …`, `$CURL -X PUT …`) can be
              # gh, curl or anything else, so any merge route or GraphQL call
              # behind it is unverifiable — it used to emit nothing at all.
              # It may also be an argument of a wrapper (`sudo -u "$U" gh pr merge
              # …`), so keep reading past it unless it reached an API route.
              if (wdyn) { if (api_scan(i, nt, gpos, 1, piped)) break; continue }
              if (SUB1 == "api") { api_scan(i, nt, gpos, 0, piped); break }
            } else if (w in API) { api_scan(i, nt, gpos, 0, piped); break }
          }
        }
        if (hasbg) print "BG\0371"
        for (k = 1; k <= nsub; k++) {
          t = subt[k]; gsub(/\n/, "\036", t); u = subp[k]; gsub(/\n/, "\036", u)
          printf "SUB\037%s\037%s\n", u, t
        }
      }'
}

    # \036/\037 are the record separators below; a command carrying them could
    # forge a record, and no real command needs them.
    case "$COMMAND" in
      *$'\036'*|*$'\037'*)
        deny "Refusing this command: it contains ASCII control characters (\\036/\\037) that this hook uses internally, so it cannot be checked for a PR merge. Remove them and retry." ;;
    esac

    # Scan the command, then every command substitution found inside double
    # quotes (`echo "$(gh pr merge 5)"` merges) with the text before it as
    # context. The scan failing — awk missing a feature, a syntax error —
    # must DENY: an empty result would otherwise read as "no merge here".
    SCAN_TEXT=("$COMMAND"); SCAN_PRE=(""); ANY_BG=""; SCAN_N=0
    while [ "${#SCAN_TEXT[@]}" -gt 0 ]; do
      SCAN_N=$((SCAN_N + 1))
      [ "$SCAN_N" -gt 64 ] && deny "Refusing this command: it nests more command substitutions than this hook will follow, so it cannot be checked for a PR merge. Split it into simpler commands."
      S_TEXT="${SCAN_TEXT[0]}"; S_PRE="${SCAN_PRE[0]}"
      SCAN_TEXT=("${SCAN_TEXT[@]:1}"); SCAN_PRE=("${SCAN_PRE[@]:1}")
      if ! S_OUT=$(detect_scan "$S_TEXT" "$S_PRE" "$ANY_BG"); then
        deny "Refusing this command: the merge guard's command scanner failed, so this hook cannot tell whether it merges a PR. 'Cannot verify' is not 'safe'. Run the merge as a plain command, or ask the user."
      fi
      while IFS= read -r S_LINE; do
        case "$S_LINE" in
          '') ;;
          BG$'\037'1) ANY_BG=1 ;;
          SUB$'\037'*)
            S_REST="${S_LINE#SUB$'\037'}"
            S_SUBPRE="${S_REST%%$'\037'*}"; S_SUBTEXT="${S_REST#*$'\037'}"
            SCAN_TEXT+=("${S_SUBTEXT//$'\036'/$'\n'}")
            SCAN_PRE+=("${S_PRE}${S_SUBPRE//$'\036'/$'\n'}") ;;
          *) DETECT+="${S_LINE}"$'\n' ;;
        esac
      done <<<"$S_OUT"
    done

    # No statement in the command actually merges → not our business. This is
    # the fix for #2307: a mention is not an invocation.
    [ -z "$DETECT" ] && exit 0
    ;;
  *)
    exit 0
    ;;
esac

# One record per merge, \037-separated: KIND SEL REPO UNV FLAGS EXTRA.
#   KIND   merge (gh pr merge) | api (REST pulls/N/merge) | graphql
#   UNV    why the arguments cannot be verified: dyn (a shell variable or
#          command substitution), glob (an unquoted glob/brace/extglob),
#          quote (a literal quote or backslash left after one level of
#          quoting — nested shell text), cmdword (the command word is a
#          variable — for a pr merge or a REST route alike), apipath (a REST
#          route that is not plain literal)
#   EXTRA  graphql only: mutation | file | stdin | dyn | cmdword
#   FLAGS  ,trunc ,dirchg ,branchchg ,ghrepo ,ghhost ,bg — see check_record
#
# A plain read loop, not mapfile: macOS /bin/bash is 3.2, which has no mapfile,
# and the hook dying there with exit 127 is a non-blocking error on clients
# without `onFailure: "block"` — the merge would run unchecked (PR #3054
# review) — and on 2.1.295+ would block every merge-looking command. Keep this file bash-3.2 clean: no
# mapfile/readarray, declare -A, ${v,,}/${v^^}, |&, &>>, negative indices, and
# no bare "${arr[@]}" of a possibly-empty array under set -u.
RECORDS=()
while IFS= read -r R_LINE; do
  if [ -n "$R_LINE" ]; then RECORDS+=("$R_LINE"); fi
done <<<"$DETECT"
ORIG_DIR=$(pwd)

# Leading `cd <dir> &&` (issue #2872). An agent in a multi-repo workspace
# writes `cd /path/to/other-repo && gh pr merge 5`, because the Bash tool's cwd
# resets between calls. Resolving that PR in the session cwd checks the wrong
# repository. Honour the cd ONLY in the one shape whose target is certain; every
# other shape that changes directory before a merge with no --repo/-R is DENIED
# as unverifiable (issue #2889 — it used to fall back to the session cwd, which
# checked the wrong repository and could ALLOW):
#   - the command holds exactly ONE merge;
#   - the cd is the FIRST statement and the merge is the SECOND, joined by `&&`
#     (so the merge runs only if the cd succeeded) — `;`, `||`, newlines,
#     wrappers, prefixes and `pushd` are all excluded;
#   - its single operand is a plain literal word: absolute, `./…`, `../…`, `.`,
#     `..`, `~` or `~/…` — no quotes, `$`, backticks, globs, braces or options.
#     A bare relative name is excluded because CDPATH (possibly set only in the
#     agent shell's rc) is searched before the cwd for it;
#   - no --repo/-R (that already names the repository);
#   - the rest of the command holds nothing that could be a repo flag in a
#     spelling a parser could miss. It is an ALLOW-list: every character after
#     the `&&` must be a letter, digit, blank or one of `._/:=@%+,-&;` — so no
#     quote, backslash, `$`, backtick, brace, glob, extglob or newline — and no
#     word may start `-` and contain `R` or `-repo` (`-Rx`, `-R=x`, `-sRx`);
#   - nothing runs before or alongside gh: no redirection (`gh pr merge 5 >
#     .git/HEAD` truncates the cd target's gitdir before gh runs, so git
#     discovery walks up to an enclosing repo) and no lone `&`. `;` and `&&`
#     after the merge run only once gh has finished, so they stay;
#   - the rest of the command mentions no other cd/pushd/popd, no GH_REPO, and
#     no second merge;
#   - the directory exists, and resolves to the same place logically and
#     physically (`own/link/..` would differ under `cd -P`).
CD_DIR=""
if [ "$TOOL_NAME" = "Bash" ] && [ "${#RECORDS[@]}" -eq 1 ]; then
  IFS=$'\037' read -r R_KIND _ R_REPO R_UNV R_FLAGS _ <<<"${RECORDS[0]}"
  if [ "$R_KIND" = "merge" ] && [ -z "$R_REPO" ] && [ -z "$R_UNV" ] && [[ "$R_FLAGS" != *trunc* ]]; then
    CD_RE='^[[:space:]]*cd[[:blank:]]+(/[A-Za-z0-9._/@,:%=+-]*|\.\.?(/[A-Za-z0-9._/@,:%=+-]*)?|~(/[A-Za-z0-9._/@,:%=+-]*)?)[[:blank:]]*&&[[:blank:]]*gh[[:blank:]]+pr[[:blank:]]+merge([[:blank:]]|$)'
    if [[ "$COMMAND" =~ $CD_RE ]]; then
      CD_WORD="${BASH_REMATCH[1]}"
      CD_REST="${COMMAND#*&&}"
      CD_AFTER_MERGE="${CD_REST#*merge}"
      CD_LITERAL_RE='^[A-Za-z0-9[:blank:]._/:=@%+,&;-]*$'
      CD_REPOFLAG_RE='(^|[^A-Za-z0-9._/:=@%+,-])-[^[:blank:]&;]*(R|-repo)'
      CD_BG_RE='(^|[^&])&([^&]|$)'
      if [[ "$CD_REST" =~ $CD_LITERAL_RE ]] \
         && ! [[ "$CD_REST" =~ $CD_REPOFLAG_RE ]] \
         && ! [[ "$CD_REST" =~ $CD_BG_RE ]] \
         && ! grep -Eq '(^|[^A-Za-z0-9_])(cd|pushd|popd)([^A-Za-z0-9_]|$)|GH_REPO' <<<"$CD_REST" \
         && ! grep -Eq 'gh[[:space:]]+pr[[:space:]]+merge|pulls/[^/[:space:]]+/merge' <<<"$CD_AFTER_MERGE"; then
        CD_BASE="$HOOK_CWD"
        case "$CD_WORD" in
          /*) CD_BASE="/" ;;
          '~'*)
            # bash and zsh expand a leading `~` to $HOME; only an absolute
            # HOME is taken, so the result is absolute too.
            CD_BASE="/"
            case "${HOME:-}" in
              /*) CD_WORD="${HOME}${CD_WORD#\~}" ;;
              *)  CD_WORD="" ;;
            esac ;;
        esac
        if [ -n "$CD_WORD" ] && [ -n "$CD_BASE" ] && [ -d "$CD_BASE" ]; then
          CD_LOGICAL=$(cd "$CD_BASE" 2>/dev/null && CDPATH='' cd -- "$CD_WORD" 2>/dev/null && pwd -P) || CD_LOGICAL=""
          CD_PHYSICAL=$(cd -P "$CD_BASE" 2>/dev/null && CDPATH='' cd -P -- "$CD_WORD" 2>/dev/null && pwd -P) || CD_PHYSICAL=""
          if [ -n "$CD_LOGICAL" ] && [ "$CD_LOGICAL" = "$CD_PHYSICAL" ]; then
            CD_DIR="$CD_LOGICAL"
          fi
        fi
      fi
    fi
  fi
fi

NOT_PERMITTED="Merges of PRs authored by anyone other than the repo owner or a bot are not permitted from an agent."
ME=""
ME_DONE=0

# ---------------------------------------------------------------------------
# check_record: deny (and exit) unless this one merge is provably of a PR by
# you or a bot. Returns only when it is.
# ---------------------------------------------------------------------------
check_record() {
  local kind="$1" unv="$4" flags="$5" extra="$6"
  PR_SELECTOR="$2"
  PR_REPO="$3"

  # Every gh lookup below must run in the directory the tool call targets, so
  # a `gh pr merge` with no --repo resolves the repo the agent is actually in.
  # A leading literal `cd <dir> &&` (CD_DIR, issue #2872) is where the merge
  # runs.
  local gh_dir="${HOOK_CWD:-$ORIG_DIR}"
  [ -n "$CD_DIR" ] && gh_dir="$CD_DIR"
  [ -d "$gh_dir" ] || gh_dir="$ORIG_DIR"
  cd "$gh_dir" || deny "Refusing to merge: cannot enter ${gh_dir} to look the PR up. 'Cannot verify' is not 'safe'."
  GH_DIR_SHOWN=$(pwd)

  WHAT="${PR_REPO:+$PR_REPO}${PR_SELECTOR:+#$PR_SELECTOR}"
  [ -z "$WHAT" ] && WHAT="the current branch's PR"
  local retry="Merge with literal values, one PR per command, naming the repository: gh pr merge <number> -R OWNER/REPO — each merge is checked individually."

  # A bare backtick or `(` truncated the merge statement mid-argument (see the
  # structural pass). Deny BEFORE any `gh pr view` lookup: PR_SELECTOR/PR_REPO
  # may be a clean, resolvable value that is simply the WRONG one, so a lookup
  # could come back trusted while the real, substituted target is not.
  case "$flags" in *,trunc*)
    deny "Refusing to merge ${WHAT}: a backtick command substitution or a \`(\` pattern (\$(…), an extglob such as -@(R)) in the merge arguments cut off part of this merge command before this hook could read it, so this hook cannot tell whose PR it is (and cannot even be sure it would be checking the right PR or repo). ${NOT_PERMITTED} Resolve the command substitution to its literal value first, then merge with literal values one at a time — each will be checked individually." ;;
  esac

  if [ "$kind" = "graphql" ]; then
    case "$extra" in
      file) deny "Refusing this GraphQL call: its query is read from a file or stdin (-F query=@file, --input), which this hook cannot read, and a GraphQL query can merge a PR (mergePullRequest, enablePullRequestAutoMerge). ${NOT_PERMITTED} Inline the query (-f query='…') so it can be checked, or ask the user to run it." ;;
      stdin) deny "Refusing this GraphQL call: its standard input is a pipe, heredoc, herestring or file redirection, which this hook cannot read, and a GraphQL query fed from there can merge a PR (mergePullRequest, enablePullRequestAutoMerge). ${NOT_PERMITTED} Inline the query (-f query='…') with no stdin redirection so it can be checked, or ask the user to run it." ;;
      cmdword) deny "Refusing this GraphQL call: the command word is a shell variable or substitution, so this hook cannot tell what it runs or what it sends, and a GraphQL query can merge a PR. ${NOT_PERMITTED} Spell the command literally (gh api graphql -f query='…'), or ask the user to run it." ;;
      dyn)  deny "Refusing this GraphQL call: its query is a shell variable or command substitution, so this hook cannot see whether it merges a PR (mergePullRequest, enablePullRequestAutoMerge). ${NOT_PERMITTED} Inline the query literally (-f query='…'), or ask the user to run it." ;;
      *)    deny "Refusing this GraphQL merge (mergePullRequest / enablePullRequestAutoMerge): it names the PR by node id, so this hook cannot check whose PR it is. ${NOT_PERMITTED} Use gh pr merge <number> -R OWNER/REPO instead, which is checked." ;;
    esac
  fi

  case "$unv" in
    dyn)
      deny "Refusing to merge ${WHAT}: an argument of this merge is a shell variable or command substitution, so this hook cannot tell which PR or repository gh will receive, or whose PR it is. ${NOT_PERMITTED} Resolve shell variables to their literal values first (gh pr list --json number,author to find PR numbers; check which repo you mean if --repo/-R was a variable), then merge with literal values one at a time — each will be checked individually." ;;
    glob)
      deny "Refusing to merge ${WHAT}: an argument holds an unquoted glob, brace or extglob character (? * [ { } ^ ~ #), which the shell can expand into a different flag — a file named -R turns -? into -R — so this hook cannot tell which repository gh will merge in. ${NOT_PERMITTED} Quote the argument or spell it literally. ${retry}" ;;
    quote)
      deny "Refusing to merge ${WHAT}: an argument still holds a quote or backslash after one level of quoting (nested shell text such as bash -c \"… \\\"-R\\\" …\"), so this hook cannot be sure how the inner shell splits it into flags. ${NOT_PERMITTED} ${retry}" ;;
    stdin)
      deny "Refusing this command: a shell reads its script from a pipe (… | bash), so this hook cannot see whether — or what — it merges. ${NOT_PERMITTED} Run the merge as a plain command: ${retry}" ;;
    stdinargs)
      deny "Refusing to merge ${WHAT}: xargs/parallel add arguments read at run time, so this hook cannot tell which PR or repository gh will receive. ${NOT_PERMITTED} ${retry}" ;;
    dangling)
      deny "Refusing to merge ${WHAT}: the --repo/-R flag has no value inside the command text this hook can see (it is joined from outside a quoted string, as in eval \"… -R\" \"x\"), so this hook cannot tell which repository gh will merge in. ${NOT_PERMITTED} ${retry}" ;;
    cmdword)
      deny "Refusing to merge ${WHAT}: the command word is a shell variable or substitution (\$GH pr merge …, \$GH api …/pulls/N/merge), so this hook cannot tell what it runs or with which flags. ${NOT_PERMITTED} ${retry}" ;;
    apipath)
      deny "Refusing this REST merge: the owner, repository or PR number in its pulls/N/merge route is not a plain literal (a shell variable, or gh's {owner}/{repo} placeholders), so this hook cannot tell whose PR it is. ${NOT_PERMITTED} ${retry}" ;;
  esac

  case "$flags" in *,ghhost*)
    deny "Refusing to merge ${WHAT}: GH_HOST, GH_ENTERPRISE_TOKEN, GH_CONFIG_DIR, XDG_CONFIG_HOME or HOME is set for this command, which points gh at a different host or account than the one this hook checks. ${NOT_PERMITTED} Run the merge without overriding them." ;;
  esac

  # Without --repo/-R, gh resolves the repository from GH_REPO, else from the
  # git repository of the directory it runs in. Anything earlier in the command
  # that changes either makes the session directory the wrong place to look.
  if [ -z "$PR_REPO" ]; then
    case "$flags" in *,ghrepo*)
      deny "Refusing to merge ${WHAT}: GH_REPO is set in this command (inline, exported earlier, or through an environment entry whose name is a variable), and gh merges in that repository, not the one this hook would look the PR up in. ${NOT_PERMITTED} Name the repository with -R instead — gh obeys an explicit -R over GH_REPO, and this hook reads it: gh pr merge ${PR_SELECTOR:-<number>} -R OWNER/REPO" ;;
    esac
    if [ -z "$CD_DIR" ]; then
      case "$flags" in *,dirchg*)
        deny "Refusing to merge ${WHAT}: something before the merge can change which repository gh resolves — a cd/pushd/popd in a shape this hook does not follow (only a leading literal \`cd <dir> && gh pr merge …\` is), env -C, GIT_DIR/GIT_WORK_TREE, a git remote/config/worktree change, gh repo set-default, a gh function or alias, a sourced script, or a redirection into a .git path. No --repo/-R was given, so this hook would look the PR up in the repository of ${GH_DIR_SHOWN}, which may not be where gh merges. ${NOT_PERMITTED} Retry naming the repository explicitly, as its own command: gh pr merge ${PR_SELECTOR:-<number>} -R OWNER/REPO" ;;
      esac
    fi
    if [ -z "$PR_SELECTOR" ]; then
      case "$flags" in *,branchchg*)
        deny "Refusing to merge the current branch's PR: the command switches branches first (git checkout/switch, gh pr checkout), so the current-branch PR this hook can look up now is not the one gh will merge. ${NOT_PERMITTED} Name the PR: gh pr merge <number> -R OWNER/REPO" ;;
      esac
    fi
    case "$flags" in *,bg*)
      deny "Refusing to merge ${WHAT}: the command runs something in the background (a lone &) alongside the merge, which can change the repository gh resolves while it runs (for example git remote set-url). ${NOT_PERMITTED} Run the merge as its own command, or name the repository: gh pr merge ${PR_SELECTOR:-<number>} -R OWNER/REPO" ;;
    esac
  fi

  # -------------------------------------------------------------------------
  # Resolve the author and classify.
  # -------------------------------------------------------------------------
  if [ "$ME_DONE" = "0" ]; then
    ME=$(gh api user --jq '.login' 2>/dev/null || true)
    ME_DONE=1
  fi

  VIEW_ARGS=()
  [ -n "$PR_SELECTOR" ] && VIEW_ARGS+=("$PR_SELECTOR")
  [ -n "$PR_REPO" ] && VIEW_ARGS+=(--repo "$PR_REPO")

  local meta
  meta=$(gh pr view ${VIEW_ARGS[@]+"${VIEW_ARGS[@]}"} \
          --json number,title,author,url \
          --jq '[(.number|tostring), .author.login, (.author.is_bot|tostring), .title, .url] | @tsv' \
          </dev/null 2>/dev/null || true)

  if [ -z "$meta" ]; then
    # Belt and braces: the structural pass already denies a `$`/backtick
    # selector or repo, but a value reaching here unresolved still names the
    # cause instead of blaming "bad PR number, wrong repo, or no network", and
    # never echoes the unexpanded variable back as a runnable command (#2449).
    case "${PR_SELECTOR}${PR_REPO}" in
      *'$'*|*'`'*)
        deny "Refusing to merge ${WHAT}: the PR selector or repo is a shell variable, so this hook cannot tell whose PR it is. ${NOT_PERMITTED} Resolve shell variables to their literal values first (gh pr list --json number,author to find PR numbers; check which repo you mean if --repo/-R was a variable), then merge with literal values one at a time — each will be checked individually." ;;
      *)
        if [ -z "$PR_REPO" ]; then
          # Issue #2872: the commonest cause is the repository, not the number
          # — with no --repo, gh resolves the repo from the directory below,
          # which is the session cwd unless the command began with a literal
          # `cd <dir> &&`. Say so, and name the unambiguous remedy.
          deny "Refusing to merge ${WHAT}: could not read the PR's author (gh pr view returned nothing). No --repo/-R was given, so the PR was looked up in the repository of ${GH_DIR_SHOWN} — if the PR lives in another repository (for example one you cd into in a way this hook does not follow), that is the likely cause; otherwise check the PR number and the network. 'Cannot verify' is not 'safe', so this is denied rather than allowed. Retry naming the repository explicitly: gh pr merge ${PR_SELECTOR:-<number>} -R OWNER/REPO …"
        fi
        deny "Refusing to merge ${WHAT}: could not read the PR's author (gh pr view returned nothing — bad PR number, wrong repo, or no network). 'Cannot verify' is not 'safe', so this is denied rather than allowed. Check the PR exists and is reachable (gh pr view ${PR_SELECTOR:-} ${PR_REPO:+--repo $PR_REPO}), then retry." ;;
    esac
  fi

  local PR_NUM AUTHOR IS_BOT TITLE URL
  IFS=$'\t' read -r PR_NUM AUTHOR IS_BOT TITLE URL <<< "$meta"

  if [ -z "$ME" ]; then
    deny "Refusing to merge ${PR_REPO:-this repo}#${PR_NUM} (\"${TITLE}\"): could not determine the authenticated GitHub user (gh api user failed), so authorship cannot be checked against you. Denied rather than guessed. Fix gh auth (gh auth status) and retry."
  fi

  # A bot author renders differently depending on which gh subcommand produced
  # it: `gh pr view` gives is_bot=true with login "app/<name>"; the search API
  # gives is_bot=false with a "<name>[bot]" login. Accept every spelling —
  # missing one would flag release-please/renovate/dependabot as strangers and
  # make this guard noise that gets disabled.
  local trusted=0
  [ "$AUTHOR" = "$ME" ] && trusted=1
  [ "$IS_BOT" = "true" ] && trusted=1
  case "$AUTHOR" in *'[bot]'|app/*) trusted=1 ;; esac

  [ "$trusted" = "1" ] && return 0

  # -------------------------------------------------------------------------
  # External author — build a denial that carries the facts a reviewer needs.
  # -------------------------------------------------------------------------
  local slug="$PR_REPO" assoc="" risky reason
  if [ -z "$slug" ]; then
    slug=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  fi
  if [ -n "$slug" ]; then
    assoc=$(gh api "repos/$slug/pulls/$PR_NUM" --jq '.author_association' </dev/null 2>/dev/null || true)
  fi

  # Which touched paths actually execute something? That is the difference
  # between "a typo fix" and "code that runs in CI or on the operator's machine".
  risky=$(gh pr view ${VIEW_ARGS[@]+"${VIEW_ARGS[@]}"} --json files --jq '.files[].path' </dev/null 2>/dev/null \
    | awk '
        /^\.github\/(workflows|actions)\// { print "    " $0 "  (CI executes this)"; next }
        /\.(sh|bash|zsh)$/                 { print "    " $0 "  (shell)"; next }
        /(^|\/)hooks\//                    { print "    " $0 "  (hook — runs on the operator machine)"; next }
        /(^|\/)\.claude\//                 { print "    " $0 "  (Claude Code config / permissions)"; next }
        /^(package\.json|pyproject\.toml|Cargo\.toml|mise\.toml|[jJ]ustfile|Makefile|Dockerfile|\.pre-commit-config\.yaml)$/ { print "    " $0 "  (build / tooling entry point)"; next }
      ' || true)

  reason="Refusing to merge ${slug:-this repo}#${PR_NUM} — it was written by someone else.

  PR       ${slug:-?}#${PR_NUM}  \"${TITLE}\"
  author   ${AUTHOR}${assoc:+  (${assoc})}
  you      ${ME}
  ${URL}"

  if [ -n "$risky" ]; then
    reason="${reason}

  This PR touches paths that EXECUTE:
${risky}"
  fi

  reason="${reason}

Vetting an outside contribution is a human judgement call, so an agent does not merge it. Do this instead:
  1. Review it and report what it actually changes — read the diff (gh pr diff ${PR_NUM}${slug:+ --repo $slug}), and for any added CI action or dependency, say where the code comes from, whether the ref is pinned to a commit SHA or a mutable tag, and what it downloads or sends at runtime.
  2. Leave the merge to the user: 'ghsq -x' shows external PRs and requires a typed confirmation, or 'gh pr merge ${PR_NUM}${slug:+ --repo $slug} --squash --delete-branch' run by them.

Do not retry with different flags or a different merge route — this hook checks them all. Do not prefix CLAUDE_HOOKS_DISABLE_EXTERNAL_PR_MERGE=1 onto the command; it is only honored from the operator's own shell environment. See .claude/rules/handling-blocked-hooks.md."

  deny "$reason"
}

# Every merge in the command is checked; the first one that is external or
# cannot be verified denies the whole command (issue #2889 — only the first
# merge used to be checked, so `gh pr merge 5 && gh pr merge 5 -R other/repo`
# merged the second unchecked).
for rec in ${RECORDS[@]+"${RECORDS[@]}"}; do
  [ -n "$rec" ] || continue
  IFS=$'\037' read -r R_KIND R_SEL R_REPO R_UNV R_FLAGS R_EXTRA <<<"$rec"
  check_record "$R_KIND" "$R_SEL" "$R_REPO" "$R_UNV" "$R_FLAGS" "$R_EXTRA"
done
exit 0

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

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')

deny() {
  local reason="$1" json_reason
  json_reason=$(printf '%s' "$reason" | jq -Rs .)
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$json_reason"
  exit 0
}

# ---------------------------------------------------------------------------
# Work out which PR (if any) this tool call would merge.
#   PR_SELECTOR — number / URL / branch, or empty to mean "current branch's PR"
#   PR_REPO     — OWNER/REPO, or empty for the repo at the cwd
# ---------------------------------------------------------------------------
PR_SELECTOR=""
PR_REPO=""

case "$TOOL_NAME" in
  mcp__github__merge_pull_request)
    PR_SELECTOR=$(printf '%s' "$INPUT" | jq -r '.tool_input.pullNumber // .tool_input.pull_number // empty')
    OWNER=$(printf '%s' "$INPUT" | jq -r '.tool_input.owner // empty')
    REPO=$(printf '%s' "$INPUT" | jq -r '.tool_input.repo // empty')
    [ -n "$OWNER" ] && [ -n "$REPO" ] && PR_REPO="$OWNER/$REPO"
    ;;
  Bash)
    COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
    [ -z "$COMMAND" ] && exit 0

    # Fast bail-out: the overwhelming majority of Bash calls are not merges.
    # This is a cheap SUPERSET prefilter only — it says "the phrase appears
    # somewhere in the text", which is NOT the same as "this command merges".
    # DETECT below is what actually decides. Anything the structural pass can
    # match must also match here, or it would never be reached.
    if ! printf '%s' "$COMMAND" | grep -Eq 'gh[[:space:]]+pr[[:space:]]+merge|pulls/[^/[:space:]]+/merge'; then
      exit 0
    fi

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
    # each, and reports the FIRST statement whose command word is a merge —
    # never the last, so a real merge followed by prose still yields the real
    # merge's selector.
    #
    # A quoted string OR a heredoc body is scanned as nested command text (not
    # masked) when the statement's effective command word is a shell invoker
    # (`bash -c '…'`, `eval "…"`, `bash <<EOF … EOF`), so feeding a merge to a
    # shell as script text does not evade the guard. "Effective" means the
    # wrapper prefix is skipped first, so `sudo -u ci bash -c '…'` is a shell
    # invoker too.
    #
    # Why awk and not `ast-grep --lang bash` (used by bash-antipatterns.sh):
    # that hook is a STYLE nudge and is designed to fail OPEN where ast-grep is
    # absent. This hook is a security guard — a second, weaker code path for
    # "ast-grep missing" is exactly the path an agent would end up on, and
    # failing open there would hand back the hole this hook exists to close.
    # awk is POSIX-guaranteed, so there is one path and it is always structural.
    # -----------------------------------------------------------------------
    DETECT=$(printf '%s' "$COMMAND" | awk '
      { buf = (NR > 1 ? buf "\n" $0 : $0) }
      END {
        SQ = sprintf("%c", 39); DQ = "\""; BT = sprintf("%c", 96)
        split("eval bash sh zsh ksh dash nix-shell", sl, " "); for (k in sl) shcmd[sl[k]] = 1

        merge_re  = "^gh[ \t]+pr[ \t]+merge"
        # Unanchored twin, used only once a wrapper has been stripped: after
        # `sudo -u ci` / `find … -exec` the command word is no longer at the
        # head of the statement, and a wrapper runs whatever follows it.
        wmerge_re = "[ \t]gh[ \t]+pr[ \t]+merge"
        api_re    = "repos/[^/ \t]+/[^/ \t]+/pulls/[0-9]+/merge"
        qcls      = "[" DQ SQ "]"
        api_req   = "repos/[^/ \t" DQ SQ "]+/[^/ \t" DQ SQ "]+/pulls/[0-9]+/merge"
        asg_re    = "^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*"
        kw_re     = "^(do|then|else|elif|if|while|until|time|!|[{])"
        kww_re    = "^(do|then|else|elif|if|while|until|time|!|[{])$"
        # A redirection is not a command word and not a PR selector: bash strips
        # it from the argv gh receives, so `gh pr merge 2>/dev/null 2231` really
        # merges 2231 and `xargs -n1 gh pr merge < prs.txt` really merges.
        red_body  = "([0-9]*(>>|>|<|<>|>&|<&)|&>>|&>)"
        red_re    = "^" red_body
        # Wrappers that RUN another command, so the merge is theirs to execute.
        wnames    = "command|builtin|exec|nohup|env|stdbuf|nice|ionice|setsid|caffeinate|sudo|doas|timeout|xargs|find|parallel|watch|script|flock|chronic|uv|uvx|npx|bunx"
        wrap_re   = "^(" wnames ")"
        wrapw_re  = "^(" wnames ")$"
        warg_re   = "^(-[^ \t]*|[0-9]+[smhd]?)"
        # Only these command words can reach the REST-API merge route. Without
        # the gate, `rg repos/o/r/pulls/2231/merge docs/` — a search for the
        # route, not a call to it — was denied (issue #2307 all over again).
        anames    = "gh|curl|wget|http|https|xh|hurl"
        apicmd_re = "^(" anames ")[ \t]"
        wapicmd_re= "[ \t](" anames ")[ \t]"

        n = length(buf); m = ""; q = 0; nomask = 0
        in_hd = 0; hd_delim = ""; hd_strip = 0; hd_nomask = 0; curline = ""; pn = 0
        ns = 1; st[1] = 1; cw = ""; cw_done = 0; nest = 0; wrapm = 0
        i = 1
        while (i <= n) {
          c = substr(buf, i, 1)
          if (in_hd) {                                   # inside a heredoc body
            if (c == "\n") {
              t = curline; if (hd_strip) sub(/^\t+/, "", t)
              m = m "\n"; curline = ""
              if (hd_nomask) { st[++ns] = i + 1; cw = ""; cw_done = 0; wrapm = 0 }
              if (t == hd_delim) {
                if (pn > 0) { hd_delim = hdq[1]; hd_strip = hds[1]; hd_nomask = hdn[1]
                              for (k = 1; k < pn; k++) { hdq[k] = hdq[k+1]; hds[k] = hds[k+1]; hdn[k] = hdn[k+1] }
                              pn-- }
                else { in_hd = 0; hd_nomask = 0 }
              }
            } else { m = m (hd_nomask ? c : "X"); curline = curline c }
            i++; continue
          }
          if (q != 1 && c == "\\") {                     # escape / line continuation
            nx = substr(buf, i + 1, 1)
            if (nx == "\n") m = m "  "
            else if (q == 0) m = m "\\" nx
            else m = m "\\" (nomask ? nx : "X")
            i += 2; continue
          }
          if (q != 0) {                                  # inside a quoted value
            if ((q == 1 && c == SQ) || (q == 2 && c == DQ)) {
              q = 0; m = m c
              if (nomask) { st[++ns] = i + 1; nomask = 0 }
            } else if (nomask && (c == ";" || c == "&" || c == "|" || c == "(" || c == ")" || c == BT || c == "\n")) {
              # Nested command TEXT, so its operators separate statements too:
              # `bash -c "echo hi; gh pr merge 5"` is two commands, not one.
              m = m c; st[++ns] = i + 1; cw = ""; cw_done = 0; wrapm = 0
            } else m = m (nomask ? c : "X")
            i++; continue
          }
          if (c == SQ || c == DQ) {
            q = (c == SQ ? 1 : 2); m = m c; nomask = nest
            if (nomask) st[++ns] = i + 1
            if (cw != "") cw_done = 1
            i++; continue
          }
          # `` ` `` splits like `(` does — legacy command substitution starts a
          # new command, so `X=`gh pr merge 5`` is a merge, not an assignment.
          if (c == ";" || c == "&" || c == "|" || c == "(" || c == ")" || c == BT || c == "\n") {
            m = m c; st[++ns] = i + 1; cw = ""; cw_done = 0; nest = 0; wrapm = 0
            if (c == "\n" && pn > 0) {                   # queued heredoc starts here
              hd_delim = hdq[1]; hd_strip = hds[1]; hd_nomask = hdn[1]
              for (k = 1; k < pn; k++) { hdq[k] = hdq[k+1]; hds[k] = hds[k+1]; hdn[k] = hdn[k+1] }
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
              if (cw ~ /^[A-Za-z_][A-Za-z0-9_]*=/) cw = ""    # leading assignment
              else if (cw in shcmd) { cw_done = 1; nest = 1 }
              else if (cw ~ kww_re) cw = ""                   # shell keyword
              else if (cw ~ wrapw_re) { cw = ""; wrapm = 1 }   # `sudo`, `env`, …
              else if (wrapm) cw = ""                         # args of a wrapper
              else cw_done = 1
            }
            i++; continue
          }
          if (c == "<" && substr(buf, i + 1, 1) == "<" && substr(buf, i + 2, 1) != "<") {
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
                               m = m substr(buf, i, j - i); i = j; continue }
          }
          m = m c
          if (!cw_done) cw = cw c
          i++
        }
        st[ns + 1] = n + 2

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
          # Anchored at the command word. Once a wrapper has been seen the
          # command word may sit behind arguments the stripper cannot classify
          # (`sudo -u ci gh pr merge 5`, `find . -name x -exec gh pr merge 5 ;`),
          # and a wrapper EXECUTES what follows it — so scan the rest of the
          # statement. The scan runs on the MASK, so a quoted phrase behind a
          # wrapper (`timeout 60 echo "gh pr merge 5"`) is still prose.
          hit = 0
          if (match(cm, merge_re)) hit = 1
          else if (wrapped && match(cm, wmerge_re)) hit = 1
          if (hit) {
            e = RSTART + RLENGTH
            nxt = substr(cm, e, 1)
            if (nxt == "" || nxt == " " || nxt == "\t") {
              segm = substr(cm, e); sego = substr(co, e)
              gsub(/\n/, " ", segm); gsub(/\n/, " ", sego)
              print "KIND=merge"; print "SEG=" sego; print "MSEG=" segm
              exit
            }
          }
          # `gh api ... repos/O/R/pulls/N/merge` (any method; PUT is the merge
          # verb, but a bare `gh api <path>` on that route also merges), and the
          # same route reached by curl. Gated on the command word: only a client
          # that can CALL the route counts, so `rg .../pulls/5/merge docs/` and
          # `echo .../pulls/5/merge` are searches and prose, not merges.
          # Matched on the MASK, so the path must be a real argument — a route
          # quoted inside prose does not count, unless the quoted argument IS
          # exactly the route.
          isapi = 0
          if (match(cm, apicmd_re)) isapi = 1
          else if (wrapped && match(cm, wapicmd_re)) isapi = 1
          if (isapi) {
            if (match(cm, api_re)) { print "KIND=api"; print "APIPATH=" substr(co, RSTART, RLENGTH); exit }
            if (match(co, qcls api_req qcls)) { print "KIND=api"; print "APIPATH=" substr(co, RSTART + 1, RLENGTH - 2); exit }
          }
        }
      }' || true)

    # No statement in the command actually merges → not our business. This is
    # the fix for #2307: a mention is not an invocation.
    [ -z "$DETECT" ] && exit 0

    case "$(printf '%s\n' "$DETECT" | sed -n 's/^KIND=//p')" in
      api)
        API_PATH=$(printf '%s\n' "$DETECT" | sed -n 's/^APIPATH=//p')
        PR_REPO=$(printf '%s' "$API_PATH" | awk -F/ '{print $2"/"$3}')
        PR_SELECTOR=$(printf '%s' "$API_PATH" | awk -F/ '{print $5}')
        ;;
      merge)
        # First positional token of the merge invocation, skipping flags AND the
        # values of the flags that take one. Without the skip list,
        # `gh pr merge --subject "feat: x" 5` would read `feat:` as the PR
        # selector and check the wrong (or no) PR. Tokens are cut from the
        # MASKED segment (so a space inside a quoted value does not split a
        # token) and read back from the original at the same offsets.
        MERGE_SEG=$(printf '%s\n' "$DETECT" | sed -n 's/^SEG=//p')
        MERGE_MSEG=$(printf '%s\n' "$DETECT" | sed -n 's/^MSEG=//p')
        # Passed via the environment, not `awk -v`: -v applies backslash escape
        # processing to the value, which would mangle a command containing one.
        PARSED=$(SEG="$MERGE_SEG" MSEG="$MERGE_MSEG" awk '
          function unq(s,   a, b) {
            if (length(s) >= 2) {
              a = substr(s, 1, 1); b = substr(s, length(s), 1)
              if ((a == SQ || a == DQ) && a == b) return substr(s, 2, length(s) - 2)
            }
            return s
          }
          BEGIN {
            SQ = sprintf("%c", 39); DQ = "\""
            seg = ENVIRON["SEG"]; mseg = ENVIRON["MSEG"]
            split("-b --body -F --body-file -m --match-head-commit -R --repo -s --subject --author-email -t --title", v, " ")
            for (i in v) valued[v[i]] = 1
            n = length(mseg); k = 0; i = 1
            while (i <= n) {
              c = substr(mseg, i, 1)
              if (c == " " || c == "\t") { i++; continue }
              s = i
              while (i <= n) { c = substr(mseg, i, 1); if (c == " " || c == "\t") break; i++ }
              k++; tm[k] = substr(mseg, s, i - s); to[k] = substr(seg, s, i - s)
            }
            # A redirection is not an argument: bash removes it before gh sees
            # argv, so `gh pr merge 2>/dev/null 2231` merges 2231 and
            # `gh pr merge < prs.txt` merges the current branch PR. Reading the
            # redirection as the selector would name a PR that does not exist.
            red = "([0-9]*(>>|>|<|<>|>&|<&)|&>>|&>)"
            sel = ""; skip = 0
            for (j = 1; j <= k; j++) {
              if (skip)             { skip = 0; continue }
              if (tm[j] ~ ("^" red "$")) { skip = 1; continue }   # operator, target next
              if (tm[j] ~ ("^" red))     { continue }             # target attached
              if (tm[j] ~ /^-/)     { if (tm[j] in valued) skip = 1; continue }
              sel = unq(to[j]); break
            }
            rep = ""
            # --repo/-R may appear either as a separate token or as --repo=OWNER/REPO.
            for (j = 1; j <= k; j++) {
              if ((tm[j] == "-R" || tm[j] == "--repo") && j < k) { rep = unq(to[j + 1]); break }
              if (tm[j] ~ /^--repo=/) { rep = unq(substr(to[j], 8)); break }
            }
            print "SELECTOR=" sel
            print "REPO=" rep
          }' || true)
        PR_SELECTOR=$(printf '%s\n' "$PARSED" | sed -n 's/^SELECTOR=//p')
        PR_REPO=$(printf '%s\n' "$PARSED" | sed -n 's/^REPO=//p')

        # NOTE: no selector-SHAPE gate here, deliberately. An earlier revision
        # allowed a merge whose selector token did not look like a number, URL
        # or branch name, reasoning that such a token meant a spurious match.
        # It did not: the command word `gh pr merge` is already established
        # structurally by this point, so the statement IS a merge whatever its
        # argument looks like — and the shape whitelist was narrower than a
        # legal git ref (`_wip`, `feat/a,b`, `feat/100%-done` all failed it),
        # so an external contributor could pick a branch name that turned the
        # guard off. Whether the selector resolves is the author check's
        # business below, which denies when it cannot be read: "cannot verify"
        # is not "safe".
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# Resolve the author and classify.
# ---------------------------------------------------------------------------
# Every gh lookup below must run in the directory the tool call targets, so a
# `gh pr merge` with no --repo resolves the repo the agent is actually in. cd
# once here rather than wrapping each call in `cd "$GH_DIR" && gh … || true`,
# which folds a cd failure into the same `|| true` as a gh failure (SC2015).
GH_DIR="${HOOK_CWD:-.}"
[ -d "$GH_DIR" ] || GH_DIR="."
cd "$GH_DIR" || exit 0

ME=$(gh api user --jq '.login' 2>/dev/null || true)

VIEW_ARGS=()
[ -n "$PR_SELECTOR" ] && VIEW_ARGS+=("$PR_SELECTOR")
[ -n "$PR_REPO" ] && VIEW_ARGS+=(--repo "$PR_REPO")

META=$(gh pr view "${VIEW_ARGS[@]}" \
        --json number,title,author,url \
        --jq '[(.number|tostring), .author.login, (.author.is_bot|tostring), .title, .url] | @tsv' \
        </dev/null 2>/dev/null || true)

WHAT="${PR_REPO:+$PR_REPO}${PR_SELECTOR:+#$PR_SELECTOR}"
[ -z "$WHAT" ] && WHAT="the current branch's PR"

if [ -z "$META" ]; then
  case "$PR_SELECTOR" in
    *'$'*|*'`'*)
      deny "Refusing to merge ${WHAT}: the PR selector is a shell variable, so this hook cannot tell whose PR it is. Merges of PRs authored by anyone other than the repo owner or a bot are not permitted from an agent. Resolve the PR numbers first (gh pr list --json number,author) and merge them one literal number at a time — each will be checked individually." ;;
    *)
      deny "Refusing to merge ${WHAT}: could not read the PR's author (gh pr view returned nothing — bad PR number, wrong repo, or no network). 'Cannot verify' is not 'safe', so this is denied rather than allowed. Check the PR exists and is reachable (gh pr view ${PR_SELECTOR:-} ${PR_REPO:+--repo $PR_REPO}), then retry." ;;
  esac
fi

IFS=$'\t' read -r PR_NUM AUTHOR IS_BOT TITLE URL <<< "$META"

if [ -z "$ME" ]; then
  deny "Refusing to merge ${PR_REPO:-this repo}#${PR_NUM} (\"${TITLE}\"): could not determine the authenticated GitHub user (gh api user failed), so authorship cannot be checked against you. Denied rather than guessed. Fix gh auth (gh auth status) and retry."
fi

# A bot author renders differently depending on which gh subcommand produced it:
# `gh pr view` gives is_bot=true with login "app/<name>"; the search API gives
# is_bot=false with a "<name>[bot]" login. Accept every spelling — missing one
# would flag release-please/renovate/dependabot as strangers and make this guard
# noise that gets disabled.
IS_TRUSTED=0
[ "$AUTHOR" = "$ME" ] && IS_TRUSTED=1
[ "$IS_BOT" = "true" ] && IS_TRUSTED=1
case "$AUTHOR" in *'[bot]'|app/*) IS_TRUSTED=1 ;; esac

[ "$IS_TRUSTED" = "1" ] && exit 0

# ---------------------------------------------------------------------------
# External author — build a denial that carries the facts a reviewer needs.
# ---------------------------------------------------------------------------
SLUG="$PR_REPO"
if [ -z "$SLUG" ]; then
  SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
fi

ASSOC=""
if [ -n "$SLUG" ]; then
  ASSOC=$(gh api "repos/$SLUG/pulls/$PR_NUM" --jq '.author_association' </dev/null 2>/dev/null || true)
fi

# Which touched paths actually execute something? That is the difference between
# "a typo fix" and "code that runs in CI or on the operator's machine".
RISKY=$(gh pr view "${VIEW_ARGS[@]}" --json files --jq '.files[].path' </dev/null 2>/dev/null \
  | awk '
      /^\.github\/(workflows|actions)\// { print "    " $0 "  (CI executes this)"; next }
      /\.(sh|bash|zsh)$/                 { print "    " $0 "  (shell)"; next }
      /(^|\/)hooks\//                    { print "    " $0 "  (hook — runs on the operator machine)"; next }
      /(^|\/)\.claude\//                 { print "    " $0 "  (Claude Code config / permissions)"; next }
      /^(package\.json|pyproject\.toml|Cargo\.toml|mise\.toml|[jJ]ustfile|Makefile|Dockerfile|\.pre-commit-config\.yaml)$/ { print "    " $0 "  (build / tooling entry point)"; next }
    ' || true)

REASON="Refusing to merge ${SLUG:-this repo}#${PR_NUM} — it was written by someone else.

  PR       ${SLUG:-?}#${PR_NUM}  \"${TITLE}\"
  author   ${AUTHOR}${ASSOC:+  (${ASSOC})}
  you      ${ME}
  ${URL}"

if [ -n "$RISKY" ]; then
  REASON="${REASON}

  This PR touches paths that EXECUTE:
${RISKY}"
fi

REASON="${REASON}

Vetting an outside contribution is a human judgement call, so an agent does not merge it. Do this instead:
  1. Review it and report what it actually changes — read the diff (gh pr diff ${PR_NUM}${SLUG:+ --repo $SLUG}), and for any added CI action or dependency, say where the code comes from, whether the ref is pinned to a commit SHA or a mutable tag, and what it downloads or sends at runtime.
  2. Leave the merge to the user: 'ghsq -x' shows external PRs and requires a typed confirmation, or 'gh pr merge ${PR_NUM}${SLUG:+ --repo $SLUG} --squash --delete-branch' run by them.

Do not retry with different flags or a different merge route — this hook checks them all. Do not prefix CLAUDE_HOOKS_DISABLE_EXTERNAL_PR_MERGE=1 onto the command; it is only honored from the operator's own shell environment. See .claude/rules/handling-blocked-hooks.md."

deny "$REASON"

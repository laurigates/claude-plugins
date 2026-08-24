#!/usr/bin/env bash
# check-workflow-js-model.sh — model/effort + layout guard for BUNDLED dynamic
# workflow harnesses (`*/skills/*/workflows/*.workflow.js`), issue #2210.
#
# WHY THIS EXISTS
# The dynamic-workflow migration introduces this repo's first tracked plugin-side
# `.js` files. No existing gate can see them:
#
#   scripts/check-agent-model.sh      -path '*/agents/*.md'          → no
#   scripts/check-workflow-model.sh   .github/workflows/*.yml|yaml   → no
#   scripts/lint-shell-scripts.sh     -name '*.sh'                   → no
#   .pre-commit-config.yaml           62 hook ids, zero JS linter    → no
#
# So a bundled harness calling `agent(prompt, {model:'sonnet'})`, or omitting
# `effort` entirely, passes every gate in the repo. This guard is the sibling of
# scripts/check-blueprint-level3-templates.sh, which exists for exactly the same
# reason (templates living outside the directories the normal linters scan).
#
# WHAT IT ASSERTS
#
#   Per `agent()` call in a bundled workflow script:
#     ERROR non_opus_model   opts.model is present and is not 'opus' (except the
#                            sanctioned cold-read haiku reader — see "THE ONE
#                            SANCTIONED EXCEPTION" below)
#     WARN  missing_model    opts.model is absent (the call inherits the session
#                            model — acceptable per issue #2210, but the repo
#                            standard is an explicit opus, so it is surfaced;
#                            see "The model-omission question" below)
#     ERROR missing_effort   opts.effort is absent (opus defaults to `high`, so
#                            the cost lever is forfeited unless effort is
#                            explicit — .claude/rules/workflow-model-effort.md)
#     ERROR invalid_effort   opts.effort is not one of: low medium high xhigh max
#     WARN  dynamic_model / dynamic_effort — the value is an expression, not a
#                            string literal, so it cannot be verified statically
#
#   Per file, from `.claude/rules/workflow-vs-skill.md` § Layout convention:
#     ERROR bad_filename          the file is not named `<purpose>.workflow.js`
#     ERROR missing_sibling_skill the `workflows/` dir has no sibling SKILL.md
#     ERROR unreachable_workflow  the sibling SKILL.md lacks a
#                                 `## Workflow harness (template)` section, or
#                                 that SKILL.md never names this file
#                                 ("An orphan `.js` is dead weight")
#     ERROR missing_template_framing  the harness IS reachable, but the framing
#                                 section omits the literal
#                                 `not a script to run verbatim` — the one
#                                 phrase that makes the section a TEMPLATE
#                                 framing rather than an invitation to run the
#                                 file as shipped (see "THE FRAMING LITERAL")
#     ERROR missing_worktree_clause  the script dispatches `isolation:'worktree'`
#                                 agents but its SKILL.md framing omits the two
#                                 clauses the rule says every such template must
#                                 also carry (#1868 resume hazard; push/PR only
#                                 in the sequential finalise stage)
#
# THE FRAMING LITERAL — `not a script to run verbatim` (issue #2164)
# `.claude/rules/workflow-vs-skill.md` § "The framing snippet (copy verbatim)"
# makes that sentence the load-bearing clause of the whole section:
#
#   "`workflows/<name>.workflow.js` ships beside this skill. **It is a TEMPLATE
#    to adapt, not a script to run verbatim.** Read it, then rewrite it for the
#    work in front of you."
#
# Without it a `## Workflow harness (template)` heading that merely *names* the
# file reads as "here is the script for this skill" — the exact "script to run
# verbatim" the source guidance warns against (§ Landing discipline). The
# heading alone is not the framing; the sentence is.
#
# Scoped two ways so it stays a real assertion rather than a whole-file grep:
#
#   1. It is checked INSIDE the framing section (heading → next `## `), so a
#      SKILL.md that happens to quote the phrase in unrelated prose cannot
#      satisfy it vacuously.
#   2. It only fires when the harness is otherwise REACHABLE (the section
#      exists AND names the file). An orphan `.js` already raises
#      unreachable_workflow above; adding a second finding for the same root
#      cause would double-report and bury the actionable one.
#
# THE MODEL-OMISSION QUESTION (deliberate, documented)
# `.claude/rules/workflow-model-effort.md` is path-scoped to `.github/workflows/**`
# and treats a missing `--model` as a hard `missing_model` ERROR — but its stated
# justification is cost-economics for TOP-LEVEL invocations and explicitly does
# not apply to subagents. An `agent()` call inside a harness IS a subagent, so the
# governing text is `.claude/rules/agent-development.md` § "Model Selection for
# Agents" (default to opus; avoid sonnet/haiku) plus the user-global always-Opus
# standard. Issue #2210 scopes omission as "acceptable — inherits the session
# model". This guard encodes both: omission is NOT an error (issue #2210), but it
# IS surfaced as a WARN so the drift is visible. WARN keeps STATUS non-OK while
# still exiting 0, per .claude/rules/structured-script-output.md.
#
# THE ONE SANCTIONED EXCEPTION — the cold-read haiku reader (issue #2216)
# `~/.claude/rules/agent-and-tool-selection.md` § "Sanctioned exception: cold-read
# gates run on Haiku" carves out exactly one non-Opus subagent:
#
#   "That agent is not a delegate producing work — it is the measurement
#    instrument: the test is 'can a low-context, low-capability reader act on
#    this text alone?', and a stronger model would answer a different, easier
#    question. Do not 'fix' haiku cold readers to Opus."
#
# Forcing that reader to opus does not make it safer — it destroys what it
# measures. So a call is EXEMPT from the model check when BOTH hold:
#
#   1. `opts.label` is a static string/template whose leading text matches
#      COLDREAD_LABEL_RE (`coldread:…`, `recoldread:…`, `cold-read…`, any case),
#      and
#   2. `opts.model` is the literal 'haiku'.
#
# Why keyed on the LABEL and not the file: a harness has exactly one cold-read
# stage, so a file-granular allowlist (the shape `check-agent-model.sh` uses for
# agent .md FILES) would silently also permit a `sonnet` planner sitting beside
# the cold reader in the same harness. The label is self-documenting at the call
# site and needs no external list to drift.
#
# Why 'haiku' and not "any non-opus": the sanctioned instrument IS haiku. A call
# that labels itself `coldread:` but runs `sonnet` still ERRORs — mislabelling
# cannot buy a blanket bypass, only the one documented model. What a deliberate
# mislabel CAN buy is haiku on a non-instrument call; that is accepted (it is
# visible in the diff) and it is never silent — every exemption is counted in
# EXEMPTED_CALLS= and itemised in the EXEMPTIONS: block.
#
# An exempted call is also exempt from `missing_effort`: haiku supports no
# `effort` at all (`.claude/rules/workflow-model-effort.md` § "Haiku supports no
# --effort"), so requiring one would make a compliant cold reader impossible to
# write. An effort that IS present is still validated against the tier list.
#
# EMPTY CORPUS
# Zero bundled `.js` files is the CURRENT state of this repo and is reported as
# STATUS=OK / exit 0. A guard that errors on an empty corpus is broken.
#
# Output follows .claude/rules/structured-script-output.md.
#
# Usage:
#   bash scripts/check-workflow-js-model.sh [--strict] [--project-dir DIR]
#
#   --strict        exit 1 when ERROR_COUNT > 0 (pre-commit / CI). Default: report.
#   --project-dir   repo root to scan (default: the repo this script lives in).
#
# Exit codes:
#   0 - clean, or WARN-only, or not --strict
#   1 - --strict and at least one ERROR
#   2 - unknown argument (fail fast; a silent catch-all once turned a bounded
#       destructive apply into an unbounded one — issue #2057)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STRICT=0

usage() {
    cat >&2 <<'USAGE'
Usage: check-workflow-js-model.sh [--strict] [--project-dir DIR]

  --strict          exit 1 when ERROR_COUNT > 0
  --project-dir DIR repo root to scan (default: this script's repo)
  -h, --help        show this message

Guards bundled dynamic-workflow harnesses (*/skills/*/workflows/*.workflow.js):
every agent() call pins an opus (or inherited) model and an explicit valid
effort, and every harness is reachable from a sibling SKILL.md whose framing
section carries the literal "not a script to run verbatim".

One exemption: a call whose opts.label starts with coldread/recoldread AND whose
opts.model is 'haiku' is the sanctioned measurement instrument, not a delegate.
Exemptions are counted in EXEMPTED_CALLS= and itemised under EXEMPTIONS:.

See .claude/rules/workflow-model-effort.md and .claude/rules/workflow-vs-skill.md.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --strict) STRICT=1; shift ;;
        --project-dir)
            if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
                echo "check-workflow-js-model.sh: --project-dir requires a directory" >&2
                usage
                exit 2
            fi
            ROOT_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        # Fail fast on anything unrecognised. A silent `*) ;;` catch-all lets a
        # caller/script version skew pass unnoticed (issue #2057).
        *)
            echo "check-workflow-js-model.sh: unknown argument: $1" >&2
            usage
            exit 2 ;;
    esac
done

VALID_EFFORTS="low medium high xhigh max"

error_count=0
warn_count=0
exempted_calls=0
declare -a issues=()
declare -a exemptions=()

add_error() { issues+=("  - SEVERITY=ERROR $1"); error_count=$((error_count + 1)); }
add_warn()  { issues+=("  - SEVERITY=WARN $1");  warn_count=$((warn_count + 1)); }
add_exemption() { exemptions+=("  - $1"); exempted_calls=$((exempted_calls + 1)); }

# framing_section <skill-md> — the BODY of the `## Workflow harness (template)`
# section (heading exclusive, up to the next `## ` heading or EOF). Empty when
# the section is absent. Used to scope the framing-literal assertion (#2164) so
# a mention of the phrase elsewhere in the file cannot satisfy it.
framing_section() {
    awk '
        /^## Workflow harness \(template\)/ { inside = 1; next }
        inside && /^## /                    { inside = 0 }
        inside                              { print }
    ' "$1"
}

# ---------------------------------------------------------------------------
# Discovery.
#
# `-path '*/.claude/worktrees/*' -prune` is load-bearing: each agent worktree is
# a FULL clone of this repo, so an unpruned walk re-scans every bundled harness
# once per live worktree (#1492 turned 499 real files into 12,768; #1548 hung a
# session outright). dist/ is the gitignored OpenCode export build output.
# ---------------------------------------------------------------------------
#
# The walk runs from INSIDE ROOT_DIR against RELATIVE paths, then re-absolutises
# (#2219). With an absolute base, the bare `*/.claude/worktrees/*` prune fires on
# the whole tree whenever ROOT_DIR is ITSELF an agent worktree — its own path
# contains `/.claude/worktrees/`, so every descendant matches and the scan root is
# pruned entirely. This corpus is legitimately empty TODAY (zero bundled .js),
# which is exactly why the defect was invisible here — and exactly why the
# emptiness is now reported explicitly as SCANNED_EMPTY= rather than left to be
# inferred from FILES_SCANNED=0, which cannot distinguish the two.
js_files=()
while IFS= read -r f; do
    [ -n "$f" ] && js_files+=("$ROOT_DIR/${f#./}")
done < <(
    cd "$ROOT_DIR" && find . \
        \( -path '*/.claude/worktrees/*' -o -path '*/node_modules/*' \
           -o -path './dist/*' -o -path '*/.git/*' \) -prune \
        -o -path '*/skills/*/workflows/*.js' -print 2>/dev/null | sort
)

python_ok=1
command -v python3 >/dev/null 2>&1 || python_ok=0

# parse_agent_calls <file> — emit one line per agent() call:
#   CALL <line> MODEL=<literal|-|?> EFFORT=<literal|-|?> COLDREAD=<yes|no> LABEL=<slug|->
# `-` = key absent, `?` = value is an expression, not a string literal.
#
# LABEL is sanitised to a space-free slug so the fixed row shape survives the
# caller's deliberate word-split; COLDREAD carries the classification itself so
# the shell never has to re-derive it from a truncated label.
#
# Comment bodies and string/template-literal contents are masked before the
# scan, so an `agent(…, {model:'sonnet'})` inside a prompt string or a `//`
# comment is correctly NOT a call site.
parse_agent_calls() {
    python3 - "$1" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8", errors="surrogateescape") as fh:
    src = fh.read()


def mask(s):
    """Blank out comment bodies and string/template contents, preserving length."""
    out = list(s)
    i, n, state = 0, len(s), None
    while i < n:
        c = s[i]
        if state is None:
            if c == "/" and i + 1 < n and s[i + 1] == "/":
                out[i] = out[i + 1] = " "
                state = "//"
                i += 2
                continue
            if c == "/" and i + 1 < n and s[i + 1] == "*":
                out[i] = out[i + 1] = " "
                state = "/*"
                i += 2
                continue
            if c in ("'", '"', "`"):
                state = c
            i += 1
            continue
        if state == "//":
            if c == "\n":
                state = None
            else:
                out[i] = " "
            i += 1
            continue
        if state == "/*":
            if c == "*" and i + 1 < n and s[i + 1] == "/":
                out[i] = out[i + 1] = " "
                state = None
                i += 2
                continue
            if c != "\n":
                out[i] = " "
            i += 1
            continue
        # inside a string / template literal
        if c == "\\":
            out[i] = " "
            if i + 1 < n and s[i + 1] != "\n":
                out[i + 1] = " "
            i += 2
            continue
        if c == state:
            state = None
            i += 1
            continue
        if c != "\n":
            out[i] = " "
        i += 1
    return "".join(out)


masked = mask(src)
OPEN, CLOSE = "([{", ")]}"


def match_paren(text, start):
    """start indexes '('; return index of its matching ')', or -1."""
    depth, i, n = 0, start, len(text)
    while i < n:
        ch = text[i]
        if ch in OPEN:
            depth += 1
        elif ch in CLOSE:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def last_top_object(text, lo, hi):
    """Span (inner_lo, inner_hi) of the LAST depth-1 {...} between lo and hi."""
    depth, i, found = 0, lo, None
    obj_start = None
    while i < hi:
        ch = text[i]
        if ch in OPEN:
            if depth == 0 and ch == "{":
                obj_start = i
            depth += 1
        elif ch in CLOSE:
            depth -= 1
            if depth == 0 and ch == "}" and obj_start is not None:
                found = (obj_start + 1, i)
                obj_start = None
        i += 1
    return found


def top_level_pairs(lo, hi):
    """{key: raw_value_text} for keys at relative depth 0 in masked[lo:hi]."""
    pairs, depth, i = {}, 0, lo
    while i < hi:
        c = masked[i]
        if c in OPEN:
            depth += 1
        elif c in CLOSE:
            depth -= 1
        elif c == ":" and depth == 0:
            k = i - 1
            while k >= lo and masked[k].isspace():
                k -= 1
            end = k + 1
            while k >= lo and (masked[k].isalnum() or masked[k] in "_$"):
                k -= 1
            name = src[k + 1:end]
            j, d2 = i + 1, 0
            while j < hi:
                cc = masked[j]
                if cc in OPEN:
                    d2 += 1
                elif cc in CLOSE:
                    if d2 == 0:
                        break
                    d2 -= 1
                elif cc == "," and d2 == 0:
                    break
                j += 1
            if name and name not in pairs:
                pairs[name] = src[i + 1:j].strip()
            i = j
            continue
        i += 1
    return pairs


LITERAL = re.compile(r"""^(['"`])([A-Za-z0-9._-]*)\1$""")

# The sanctioned cold-read exception (issue #2216). Anchored at the START of the
# label so a merely-adjacent mention ("quoted-coldread", "not-a-coldread") does
# not qualify: the label must DECLARE the call's purpose, not merely contain it.
COLDREAD_LABEL_RE = re.compile(r"^(?:re)?cold[-_]?read", re.IGNORECASE)
LABEL_UNSAFE = re.compile(r"[^A-Za-z0-9._:${}/-]+")


def render(pairs, key):
    if key not in pairs:
        return "-"
    m = LITERAL.match(pairs[key])
    return m.group(2) if m else "?"


def label_text(pairs):
    """Leading static text of opts.label, or None when it is not a literal.

    Handles the template-literal form the #2168 sketch uses
    (`` `coldread:${c.id}` ``) by cutting at the first interpolation: the
    leading segment is static and is what the classification keys on.
    """
    raw = pairs.get("label")
    if raw is None:
        return None
    raw = raw.strip()
    if not raw or raw[0] not in "'\"`":
        return None  # an identifier or expression — no static text to read
    quote, body = raw[0], raw[1:]
    end = len(body)
    for stop in (quote, "${"):
        idx = body.find(stop)
        if idx != -1:
            end = min(end, idx)
    return body[:end]


for m in re.finditer(r"(?<![A-Za-z0-9_$.])agent\s*\(", masked):
    open_paren = m.end() - 1
    close_paren = match_paren(masked, open_paren)
    if close_paren < 0:
        continue
    line = src.count("\n", 0, m.start()) + 1
    span = last_top_object(masked, open_paren + 1, close_paren)
    pairs = top_level_pairs(*span) if span else {}
    label = label_text(pairs)
    coldread = "yes" if label is not None and COLDREAD_LABEL_RE.match(label) else "no"
    slug = LABEL_UNSAFE.sub("_", label)[:48] if label else ""
    print("CALL %d MODEL=%s EFFORT=%s COLDREAD=%s LABEL=%s" % (
        line, render(pairs, "model"), render(pairs, "effort"), coldread, slug or "-"))
PY
}

files_scanned=0
agent_calls=0

for js in "${js_files[@]+"${js_files[@]}"}"; do
    [ -f "$js" ] || continue
    files_scanned=$((files_scanned + 1))
    rel="${js#"$ROOT_DIR"/}"
    base="$(basename "$js")"
    skill_dir="$(cd "$(dirname "$js")/.." && pwd)"
    skill_md="$skill_dir/SKILL.md"

    # --- Layout: `<purpose>.workflow.js` (workflow-vs-skill.md § Layout) ---
    case "$base" in
        *.workflow.js) : ;;
        *) add_error "TYPE=bad_filename FILE=$rel MSG=bundled harnesses are named <purpose>.workflow.js" ;;
    esac

    # --- Reachability: a `## Workflow harness (template)` section naming it ---
    if [ ! -f "$skill_md" ]; then
        add_error "TYPE=missing_sibling_skill FILE=$rel MSG=workflows/ has no sibling SKILL.md"
    else
        has_framing=1
        names_file=1
        if ! grep -qF '## Workflow harness (template)' "$skill_md"; then
            has_framing=0
            add_error "TYPE=unreachable_workflow FILE=$rel MSG=sibling SKILL.md has no '## Workflow harness (template)' section"
        fi
        if ! grep -qF "$base" "$skill_md"; then
            names_file=0
            add_error "TYPE=unreachable_workflow FILE=$rel MSG=sibling SKILL.md never names $base (an orphan .js is dead weight)"
        fi
        # The framing literal (#2164). Only for a REACHABLE harness — an orphan
        # already errored above and must not be double-reported — and read from
        # the framing section itself, not the whole file, so an unrelated
        # mention elsewhere cannot satisfy it.
        if [ "$has_framing" -eq 1 ] && [ "$names_file" -eq 1 ]; then
            # Here-string, not `framing_section … | grep -qF`: under `pipefail` a
            # `grep -q` that matches and closes the pipe early can SIGPIPE the
            # producer, so the pipeline reports non-zero and the `if !` inverts
            # into a phantom finding (.claude/rules/shell-scripting.md; #1744).
            if ! grep -qF 'not a script to run verbatim' <<<"$(framing_section "$skill_md")"; then
                add_error "TYPE=missing_template_framing FILE=$rel MSG=the '## Workflow harness (template)' section must contain the literal string 'not a script to run verbatim' — copy the framing snippet from .claude/rules/workflow-vs-skill.md (a section that only names the file reads as a script to run, not a template to adapt)"
            fi
        fi
        # Worktree-dispatching templates carry two extra clauses (the rule's
        # copy-verbatim block). Only checked when the harness actually dispatches
        # isolation:'worktree' agents.
        if grep -qE "isolation[[:space:]]*:[[:space:]]*['\"\`]worktree" "$js"; then
            if ! grep -qF 'resumeFromRunId' "$skill_md" || ! grep -qF '#1868' "$skill_md"; then
                add_error "TYPE=missing_worktree_clause FILE=$rel MSG=worktree-dispatching template: SKILL.md framing lacks the resumeFromRunId/#1868 clause"
            fi
            if ! grep -qF 'never inside a fanned-out agent' "$skill_md"; then
                add_error "TYPE=missing_worktree_clause FILE=$rel MSG=worktree-dispatching template: SKILL.md framing lacks the finalise-stage-only push/PR clause"
            fi
        fi
    fi

    # --- Per-agent() model/effort ---
    [ "$python_ok" -eq 1 ] || continue
    while IFS= read -r row; do
        [ -n "$row" ] || continue
        # shellcheck disable=SC2086  # deliberate word-split of the fixed row shape
        set -- $row
        call_line="$2"
        model="${3#MODEL=}"
        effort="${4#EFFORT=}"
        coldread="${5#COLDREAD=}"
        call_label="${6#LABEL=}"
        agent_calls=$((agent_calls + 1))

        # The one sanctioned carve-out (#2216): a cold-read-labelled haiku call
        # is the measurement instrument, not a delegate. Narrow by construction —
        # it needs BOTH the declaring label AND the literal 'haiku', so a
        # mislabelled sonnet planner beside it in the same file still ERRORs.
        exempt=0
        if [ "$coldread" = "yes" ] && [ "$model" = "haiku" ]; then
            exempt=1
            add_exemption "TYPE=coldread_haiku FILE=$rel LINE=$call_line LABEL=$call_label MODEL=$model MSG=sanctioned cold-read measurement instrument (agent-and-tool-selection.md)"
        fi

        if [ "$exempt" -eq 0 ]; then
            case "$model" in
                opus) : ;;
                -)    add_warn  "TYPE=missing_model FILE=$rel LINE=$call_line MSG=agent() omits opts.model (inherits the session model; prefer an explicit opus)" ;;
                '?')  add_warn  "TYPE=dynamic_model FILE=$rel LINE=$call_line MSG=opts.model is an expression — cannot verify it resolves to opus" ;;
                *)    add_error "TYPE=non_opus_model FILE=$rel LINE=$call_line MODEL=$model MSG=must be opus (effort, not model, is the cost lever; only a cold-read-labelled haiku reader is exempt — see #2216)" ;;
            esac
        fi

        case "$effort" in
            # An exempted haiku reader has no effort lever to forfeit, so an
            # absent effort is not an error there. A PRESENT one is still tiered.
            -)   [ "$exempt" -eq 1 ] || add_error "TYPE=missing_effort FILE=$rel LINE=$call_line MSG=agent() needs an explicit opts.effort (opus defaults to high; the savings are forfeited)" ;;
            '?') add_warn  "TYPE=dynamic_effort FILE=$rel LINE=$call_line MSG=opts.effort is an expression — cannot verify it is a valid tier" ;;
            *)
                case " $VALID_EFFORTS " in
                    *" $effort "*) : ;;
                    *) add_error "TYPE=invalid_effort FILE=$rel LINE=$call_line EFFORT=$effort MSG=effort must be one of: $VALID_EFFORTS" ;;
                esac
                ;;
        esac
    done < <(parse_agent_calls "$js")
done

issue_count=$((error_count + warn_count))
status="OK"
[ "$warn_count" -gt 0 ] && status="WARN"
[ "$error_count" -gt 0 ] && status="ERROR"

echo "=== WORKFLOW JS MODEL/EFFORT ==="
echo "FILES_SCANNED=$files_scanned"
# This guard's corpus is legitimately empty today (zero bundled workflow .js), so
# an empty scan is CORRECT here and must stay exit 0. But "checked nothing" and
# "checked everything and it was clean" are not the same claim, and FILES_SCANNED=0
# alone does not say which (#2219). SCANNED_EMPTY makes it explicit and greppable,
# so a reader — or an orchestrating skill rolling up STATUS= lines — can tell a
# vacuous OK from a real one without re-deriving it.
echo "SCANNED_EMPTY=$([ "$files_scanned" -eq 0 ] && echo true || echo false)"
echo "AGENT_CALLS=$agent_calls"
echo "PYTHON3_AVAILABLE=$([ "$python_ok" -eq 1 ] && echo true || echo false)"
echo "STATUS=$status"
echo "ISSUE_COUNT=$issue_count"
echo "ERROR_COUNT=$error_count"
echo "WARN_COUNT=$warn_count"
# Always emitted, even at 0: a carve-out that only appears when it fires is a
# carve-out you cannot notice is missing (#2216).
echo "EXEMPTED_CALLS=$exempted_calls"
if [ "$issue_count" -gt 0 ]; then
    echo "ISSUES:"
    printf '%s\n' "${issues[@]}"
fi
if [ "$exempted_calls" -gt 0 ]; then
    echo "EXEMPTIONS:"
    printf '%s\n' "${exemptions[@]}"
fi
echo "=== END WORKFLOW JS MODEL/EFFORT ==="

if [ "$error_count" -gt 0 ]; then
    {
        echo ""
        echo "Found $error_count error(s) across $files_scanned bundled workflow script(s)."
        echo "Every agent() call pins an opus model (or inherits) and an explicit valid"
        echo "--effort tier, and every harness is reachable from its sibling SKILL.md."
        echo "See .claude/rules/workflow-model-effort.md and .claude/rules/workflow-vs-skill.md."
    } >&2
    [ "$STRICT" -eq 1 ] && exit 1
fi

exit 0

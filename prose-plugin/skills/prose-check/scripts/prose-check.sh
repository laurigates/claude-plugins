#!/usr/bin/env bash
# prose-check.sh -- run the house prose rubric over a draft and roll the three
# layers up into one structured report.
#
# THE THREE LAYERS AND WHY EACH EXISTS
#
#   vale    token shapes, doc metrics, markdown scoping. Gets code/table/heading
#           skipping for free from its markdown parser. Cannot express ordinal
#           position ("No scopes select by ordinal position" --
#           docs.vale.sh/topics/scopes), which is why it is not the only layer.
#   harper  grammar and readability. Independent of vale, and the only layer
#           that reports sentence length with its own segmenter.
#   script  paragraph-final position + tic shape, and the TL;DR footer -- the
#           part vale structurally cannot do.
#   model   "is this actually a chiasmus?" Irreducibly judgment; not automated.
#
# EVERYTHING THIS EMITS IS A CANDIDATE, NOT A VERDICT. The point of the
# deterministic layers is to narrow the candidate set so model judgment is spent
# on a handful of flagged sentences rather than on re-reading a whole document.
# A hedge that carries real uncertainty is a true negative that still appears
# here. See the skill body.
#
# Degrades rather than fails: vale, harper-cli, and uv are each optional, and a
# missing one is reported as AVAILABLE=false with the other layers still running.
#
# Output: KEY=VALUE inside === SECTION === delimiters, per
# .claude/rules/structured-script-output.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts/ -> prose-check/ -> skills/ -> prose-plugin/
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
STYLES_DIR="$PLUGIN_ROOT/styles"

KIND="doc"
STRICT=0
VALE_CONFIG=""
LONG_WORDS=40
declare -a FILES=()

usage() {
    cat <<'USAGE'
Usage: prose-check.sh [OPTIONS] FILE...

  --kind doc|answer|ticket   what the draft is (default: doc)
                             `answer` adds the TL;DR (ELI5) footer check
  --config PATH              vale config (default: <plugin>/styles/.vale.ini)
  --long-words N             paragraph-final sentence word threshold (default: 40)
  --strict                   exit 1 when any candidate is found
  -h, --help                 this message
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --kind) KIND="${2:-doc}"; shift 2 ;;
        --config) VALE_CONFIG="${2:-}"; shift 2 ;;
        --long-words) LONG_WORDS="${2:-40}"; shift 2 ;;
        --strict) STRICT=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; while [ $# -gt 0 ]; do FILES+=("$1"); shift; done ;;
        -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) FILES+=("$1"); shift ;;
    esac
done

if [ ${#FILES[@]} -eq 0 ]; then
    usage >&2
    exit 2
fi

# resolve_tool NAME -- print an invocable path for NAME, or nothing.
#
# PATH alone is not enough here. mise installs vale and harper-ls behind shims
# that are only on PATH in a mise-ACTIVATED shell, and a hook shell is not one:
# in a bare environment `command -v vale` finds nothing while
# ~/.local/share/mise/shims/vale runs fine (verified: `vale version 3.18.0` from
# an empty env). Without this fallback the hook would report VALE_AVAILABLE=false
# on a machine where vale is installed and working -- a visibly degraded run
# rather than a wrong one, but degraded for no reason.
#
# PATH still wins, so an explicitly-chosen binary is never overridden.
resolve_tool() {
    local name="$1" candidate
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return
    fi
    for candidate in \
        "${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims/$name" \
        "$HOME/.local/share/mise/shims/$name" \
        /opt/homebrew/bin/"$name" \
        /usr/local/bin/"$name"; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
}

VALE_BIN="$(resolve_tool vale)"
HARPER_BIN="$(resolve_tool harper-cli)"

for f in "${FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo "=== PROSE CHECK ==="
        echo "STATUS=ERROR"
        echo "ISSUE_COUNT=1"
        echo "ISSUES:"
        echo "  - SEVERITY=ERROR TYPE=missing_file FILE=$f MSG=not a readable file"
        echo "=== END PROSE CHECK ==="
        exit 1
    fi
done

total_issues=0

# ---------------------------------------------------------------- vale -------
#
# Config selection. `.vale.ini` declares `Packages = write-good, proselint`,
# which vale fetches over the network; with those absent vale refuses to run at
# all rather than running the rules it does have. So: use the full config when
# the packages are present, try one `vale sync` when they are not, and fall back
# to the House-only config when that fails. The House layer is the part that
# encodes the actual rubric, so an offline run still checks the thing that
# matters.
echo "=== VALE ==="
if [ -z "$VALE_BIN" ]; then
    echo "VALE_AVAILABLE=false"
    echo "MSG=vale not found on PATH or in the mise shim dir; install via mise (aqua backend). Skipped."
    echo "STATUS=OK"
    echo "ISSUE_COUNT=0"
else
    echo "VALE_AVAILABLE=true"
    echo "VALE_BIN=$VALE_BIN"
    echo "VALE_VERSION=$("$VALE_BIN" --version 2>/dev/null | head -1 | tr -d '\n')"

    if [ -z "$VALE_CONFIG" ]; then
        VALE_CONFIG="$STYLES_DIR/.vale.ini"
        if [ ! -d "$STYLES_DIR/write-good" ] || [ ! -d "$STYLES_DIR/proselint" ]; then
            if ! "$VALE_BIN" --config "$VALE_CONFIG" sync >/dev/null 2>&1; then
                VALE_CONFIG="$STYLES_DIR/house-only.vale.ini"
            fi
        fi
    fi
    echo "VALE_CONFIG=$VALE_CONFIG"
    echo "VALE_PACKAGES=$([ "$(basename "$VALE_CONFIG")" = ".vale.ini" ] && echo "house+write-good+proselint" || echo "house-only")"

    # --no-exit keeps an error-level alert from ending the run; severity is
    # carried by STATUS= and the issue rows, not by vale's exit code.
    vale_out=$("$VALE_BIN" --config "$VALE_CONFIG" --output=line --no-exit "${FILES[@]}" 2>/dev/null)
    vale_count=$(printf '%s' "$vale_out" | grep -c . )
    echo "STATUS=$([ "$vale_count" -gt 0 ] && echo WARN || echo OK)"
    echo "ISSUE_COUNT=$vale_count"
    if [ "$vale_count" -gt 0 ]; then
        echo "ISSUES:"
        printf '%s\n' "$vale_out" | sed 's/^/  - SEVERITY=CANDIDATE /'
    fi
    total_issues=$((total_issues + vale_count))
fi
echo "=== END VALE ==="

# -------------------------------------------------------------- harper -------
#
# harper-cli is a debugging front-end for the Harper grammar engine and is not
# distributed through aqua or crates.io -- only harper-ls ships there. It is
# therefore treated as optional throughout.
#
# The ignore list removes rules that fire on technical prose by construction:
# spell-check and word-splitting flag every identifier and coined term, heading
# title-case is not a house convention, and ExplainLikeImFive fires on the
# literal string "ELI5" -- which the rubric mandates.
echo "=== HARPER ==="
if [ -z "$HARPER_BIN" ]; then
    echo "HARPER_AVAILABLE=false"
    echo "MSG=harper-cli not found on PATH or in the usual prefixes (brew install harper). Skipped."
    echo "STATUS=OK"
    echo "ISSUE_COUNT=0"
else
    echo "HARPER_AVAILABLE=true"
    echo "HARPER_BIN=$HARPER_BIN"
    harper_out=$("$HARPER_BIN" lint --format compact --no-color --quiet \
        --ignore SpellCheck \
        --ignore DisjointPrefixes \
        --ignore SplitWords \
        --ignore UseTitleCase \
        --ignore ExplainLikeImFive \
        "${FILES[@]}" 2>/dev/null | grep -v '^Note: ' )
    harper_count=$(printf '%s' "$harper_out" | grep -c . )
    echo "STATUS=$([ "$harper_count" -gt 0 ] && echo WARN || echo OK)"
    echo "ISSUE_COUNT=$harper_count"
    if [ "$harper_count" -gt 0 ]; then
        echo "ISSUES:"
        printf '%s\n' "$harper_out" | sed 's/^/  - SEVERITY=CANDIDATE /'
    fi
    total_issues=$((total_issues + harper_count))
fi
echo "=== END HARPER ==="

# ------------------------------------------------------ positional tics ------
if ! command -v uv >/dev/null 2>&1; then
    echo "=== POSITIONAL TICS ==="
    echo "TICS_AVAILABLE=false"
    echo "MSG=uv not on PATH; positional-tics.py needs it for PEP 723 deps. Skipped."
    echo "STATUS=OK"
    echo "ISSUE_COUNT=0"
    echo "=== END POSITIONAL TICS ==="
else
    declare -a tics_args=("--long-words" "$LONG_WORDS")
    [ "$KIND" = "answer" ] && tics_args+=("--check-tldr")
    tics_out=$("$SCRIPT_DIR/positional-tics.py" "${tics_args[@]}" "${FILES[@]}" 2>/dev/null)
    printf '%s\n' "$tics_out"
    tics_count=$(printf '%s\n' "$tics_out" | sed -n 's/^ISSUE_COUNT=//p' | head -1)
    total_issues=$((total_issues + ${tics_count:-0}))
fi

# ------------------------------------------------------------- rollup --------
echo "=== PROSE CHECK ==="
echo "KIND=$KIND"
echo "FILES=${#FILES[@]}"
echo "RUBRIC=communication.md (House styles are a derived encoding; see styles/.vale.ini)"
echo "FINDINGS_ARE=candidates_for_judgment_not_defects"
echo "STATUS=$([ "$total_issues" -gt 0 ] && echo WARN || echo OK)"
echo "ISSUE_COUNT=$total_issues"
echo "=== END PROSE CHECK ==="

[ "$STRICT" -eq 1 ] && [ "$total_issues" -gt 0 ] && exit 1
exit 0

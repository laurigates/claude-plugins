#!/usr/bin/env bash
# check-positional-references.sh -- skill markdown points at other content by
# name or link, not by direction ("see above", "the table below").
#
# WHY
# A direction word is a pointer whose target is "wherever this sentence happens
# to sit". Content moves between files: the 2026-10 SKILL.md split sweep moved
# reference material into per-skill `references/*.md`, and sentences such as
# "Preview Bridge swallows ExecutionBlocker -- see above" kept pointing at text
# that no longer exists in the file they live in. A reference file is also read
# out of order -- an agent follows a link straight into the middle of it -- so
# "above" names nothing the reader has seen. A named anchor or a file link
# survives both. The rule is in .claude/rules/skill-quality.md (§ Point at
# anchors, not directions).
#
# TWO CLASSES, TWO POLICIES (Lauri chose "ratchet + anchors")
#   strict  -- REFERENCE*.md, references/**/*.md and every other markdown file
#              in a skill directory (migrations/, loose sidecars). Any hit is
#              ERROR: these files are always read out of context.
#   ratchet -- SKILL.md. Each file is held at its count in the checked-in
#              baseline (scripts/positional-references-baseline.txt,
#              `path<TAB>count`); a file ABOVE its baseline is ERROR, a file not
#              in the baseline starts at 0. A file BELOW its baseline is also
#              ERROR (stale_baseline), the same way
#              scripts/structured-output-reason-pending.txt fails an entry that
#              no longer needs to be there -- so the ratchet only tightens.
#              `--update-baseline` rewrites it, lowering entries only (it
#              seeds a missing baseline from the current counts, once).
#   Out of scope: skill `templates/` (text emitted into other repos) and
#   `fixtures/` (test inputs written to trip a checker).
#
# WHAT COUNTS AS A POSITIONAL REFERENCE (calibrated on the tree, 2026-10)
#   * `above` / `below` used as a pointer: "the table above", "see below",
#     "(above)". NOT when used as a preposition with an object -- "below 10,000
#     chars", "above the threshold", "sits above it", "below version X" -- which
#     is detected by the token that follows, peeking across a line wrap.
#   * `earlier|previous|preceding|later` + section/table/heading/example/...,
#     and `following` + section/heading. "The following steps:" introducing a
#     list on the next line is adjacency, not a pointer, and is not matched.
#   * `described|mentioned|noted|... earlier|previously|later`, `see earlier`.
#     "Stated earlier in the session" is time, not position, and is exempt.
#   Exempt shapes: "none/neither/all/any/both/either of the above", "same as
#   above", a table cell that BEGINS with Above/Below (a row-relative pointer
#   inside one table), a comparative ("30%+ below", "or more above"), and a
#   direction word right after a markdown link -- `[X](#x) below` already
#   carries its anchor.
#   Skipped text: YAML frontmatter, fenced code (from the shared tree-sitter
#   helper scripts/lib/extract-md-elements.py, never a hand-rolled fence
#   toggle -- #2009), inline code spans, double-quoted spans (a skill quoting
#   the phrase it bans), and blockquote lines, matching
#   scripts/check-skill-references.sh.
#   Known misses: "<noun> above <determiner>..." where the determiner opens a
#   new clause ("on the PR above the reply latency was...") reads as a
#   preposition and is not flagged.
#
# Usage:
#   bash scripts/check-positional-references.sh [--project-dir DIR]
#       [--baseline FILE] [--update-baseline] [--verbose]
#   --verbose prints every hit, including SKILL.md files within their baseline.
#
# Exit: 0 = OK, 1 = ERROR (a hit, a ratchet breach, a stale baseline, or
#       nothing scanned), 2 = usage / missing dependency.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
proj_dir="$(cd "$script_dir/.." && pwd)"
baseline=""
update_baseline=0
verbose=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$(cd "$2" && pwd)" || exit 2; shift 2 ;;
    --baseline) baseline="$2"; shift 2 ;;
    --update-baseline) update_baseline=1; shift ;;
    --verbose) verbose=1; shift ;;
    *) echo "check-positional-references.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$baseline" ] || baseline="$proj_dir/scripts/positional-references-baseline.txt"
case "$baseline" in
  /*) ;;
  *) baseline="$(pwd)/$baseline" ;;
esac

helper="$script_dir/lib/extract-md-elements.py"
if ! command -v uv >/dev/null 2>&1; then
  echo "check-positional-references.sh: 'uv' not found on PATH; cannot parse markdown structure" >&2
  echo "  (fence detection uses scripts/lib/extract-md-elements.py via 'uv run')" >&2
  exit 2
fi

cd "$proj_dir" || { echo "check-positional-references.sh: cannot cd to $proj_dir" >&2; exit 2; }

# Discovery runs from INSIDE the scan root against RELATIVE paths (#2219), so a
# root that is itself an agent worktree is still scanned.
file_list="$(mktemp)"
fence_list="$(mktemp)"
trap 'rm -f "$file_list" "$fence_list"' EXIT

find . -mindepth 1 -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0 |
  while IFS= read -r -d '' plugin_dir; do
    [ -d "$plugin_dir/skills" ] || continue
    find "$plugin_dir/skills" -path '*/.claude/worktrees/*' -prune -o \
      -path '*/templates/*' -prune -o -path '*/fixtures/*' -prune -o \
      -type f -name '*.md' -print
  done | sed 's#^\./##' | LC_ALL=C sort >"$file_list"

if [ -s "$file_list" ]; then
  uv run --quiet "$helper" --types fence --files-from "$file_list" >"$fence_list" 2>/dev/null || {
    echo "check-positional-references.sh: fence extraction failed ($helper)" >&2
    exit 2
  }
fi

# `read -d ''` rather than a heredoc-fed `python3 -`: stdin stays free, and bash
# 3.2 misparses a heredoc inside `$(...)` with unbalanced parentheses.
IFS= read -r -d '' PY_SRC <<'PY' || true
import os
import re
import sys

file_list, fence_list, baseline, update, verbose = sys.argv[1:6]
update = update == "1"
verbose = verbose == "1"

OBJECT = re.compile(
    r"^((the|a|an|this|that|these|those|it|its|them|any|each|every|one|two|three|"
    r"four|five|six|ten|half|zero|version|level|threshold|limit|floor|best|"
    r"baseline|max|min|average|CODE|QUOTE)\W*$|[A-Z]\W*$|[\d~<>≈$%#+→])",
    re.I,
)
DIRECTION = re.compile(r"\b(above|below)\b", re.I)
NOUNS = (r"(sections?|tables?|headings?|chapters?|paragraphs?|subsections?|"
         r"examples?|snippets?|templates?|lists?|diagrams?|blocks?)")
STRUCTURAL = re.compile(
    r"\b(earlier|previous|preceding|later)\s+" + NOUNS + r"\b"
    r"|\bfollowing\s+(sections?|headings?|chapters?|subsections?)\b", re.I)
PARTICIPLE = re.compile(
    r"\b(described|mentioned|noted|shown|listed|discussed|explained|defined|"
    r"covered|stated|outlined|introduced|documented|given)\s+"
    r"(earlier|previously|later)\b"
    r"(?!\s+in\s+(the|this)\s+(same\s+)?(session|conversation|thread))", re.I)
SEE = re.compile(r"\bsee\s+(earlier|later)\b", re.I)
EXEMPT_BEFORE = re.compile(
    r"((none|neither|all|any|both|either)\s+of\s+the|same\s+as)\s*$"
    r"|(\d%\+?|\bor\s+more|\bor\s+less)\s*$"
    r"|\]\([^)]*\)\s*$"
    r"|\|\s*$", re.I)
CODE = re.compile(r"`[^`]*`")
QUOTED = re.compile(r"\"[^\"]*\"|“[^”]*”")
EMPHASIS = re.compile(r"[*_]+")
BLOCK_START = re.compile(r"^\s*([-*+]\s|\d+[.)]\s|\||#)")


def mask(text):
    return QUOTED.sub(" QUOTE ", CODE.sub(" CODE ", text))


def first_token(text):
    words = EMPHASIS.sub("", text).split()
    return words[0] if words else ""


def hits_in(line, next_line):
    masked = mask(line)
    found = []
    for m in DIRECTION.finditer(masked):
        token = first_token(masked[m.end():])
        if not token and next_line is not None:
            token = first_token(mask(next_line))
        if token and OBJECT.match(token):
            continue
        if EXEMPT_BEFORE.search(EMPHASIS.sub("", masked[:m.start()])):
            continue
        found.append(m.group(0))
    for rx in (STRUCTURAL, PARTICIPLE, SEE):
        found.extend(m.group(0) for m in rx.finditer(masked))
    return found


fenced = {}
with open(fence_list, encoding="utf-8") as fh:
    for row in fh:
        parts = row.rstrip("\n").split("\t")
        if len(parts) >= 4 and parts[0] == "fence":
            fenced.setdefault(parts[1], set()).update(
                range(int(parts[2]), int(parts[3]) + 1))


def scan(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    skip = set(fenced.get(path, ()))
    if lines and lines[0].strip() == "---":
        for idx in range(1, len(lines)):
            if lines[idx].strip() == "---":
                skip.update(range(1, idx + 2))
                break

    def prose(idx):
        return (idx < len(lines) and (idx + 1) not in skip
                and lines[idx].strip() != ""
                and not lines[idx].lstrip().startswith(">"))

    out = []
    for idx, line in enumerate(lines):
        if not prose(idx):
            continue
        # Peek across a soft wrap only: a list item, table row or heading on
        # the next line starts a new block, not this sentence's object.
        nxt = (lines[idx + 1] if prose(idx + 1)
               and not BLOCK_START.match(lines[idx + 1]) else None)
        for word in hits_in(line, nxt):
            out.append((idx + 1, word, " ".join(line.split())))
    return out


with open(file_list, encoding="utf-8") as fh:
    files = [ln.rstrip("\n") for ln in fh if ln.strip()]

base = {}
seeding = update and not os.path.isfile(baseline)
if os.path.isfile(baseline):
    with open(baseline, encoding="utf-8") as fh:
        for raw in fh:
            entry = raw.split("#", 1)[0].strip()
            if not entry:
                continue
            path, _, count = entry.partition("\t")
            base[path.strip()] = int(count.strip() or 0)

# Pass 1: scan everything. Pass 2 (optional): lower the baseline. Pass 3:
# judge against the baseline as it now stands, so --update-baseline reports
# the state it wrote rather than the state it replaced.
found_by = {path: scan(path) for path in files}
counts = {p: len(f) for p, f in found_by.items()
          if os.path.basename(p) == "SKILL.md" and f}
scanned = set(files)

if update and files:
    if seeding:
        lowered = dict(counts)
    else:
        lowered = {p: min(counts.get(p, 0), n) for p, n in base.items() if p in scanned}
    with open(baseline, "w", encoding="utf-8") as fh:
        fh.write("# SKILL.md positional-reference ratchet -- see "
                 "scripts/check-positional-references.sh.\n"
                 "# path<TAB>count. Counts may only go down; rewrite with "
                 "--update-baseline, which never raises an entry.\n")
        for path in sorted(lowered):
            if lowered[path] > 0:
                fh.write("%s\t%d\n" % (path, lowered[path]))
    base = {p: n for p, n in lowered.items() if n > 0}

issues = []
hit_rows = []
strict_files = skill_files = strict_hits = skill_hits = 0

for path in files:
    found = found_by[path]
    if os.path.basename(path) == "SKILL.md":
        skill_files += 1
        skill_hits += len(found)
        allowed = base.get(path, 0)
        if len(found) > allowed:
            issues.append(("ratchet_exceeded",
                           "%s has %d positional reference(s), baseline %d; point at a "
                           "named anchor or link instead" % (path, len(found), allowed)))
        show = verbose or len(found) > allowed
    else:
        strict_files += 1
        strict_hits += len(found)
        for line_no, word, text in found:
            issues.append(("positional_reference",
                           "%s:%d says %r; reference files are read out of context, "
                           "point at a named anchor or link" % (path, line_no, word)))
        show = True
    if show:
        for line_no, word, text in found:
            hit_rows.append("HIT=%s:%d: [%s] %s" % (path, line_no, word, text[:160]))

if not files:
    issues.append(("nothing_scanned",
                   "no skill markdown under %s; the discovery walk is broken, not the "
                   "tree clean" % os.getcwd()))

for path, allowed in sorted(base.items()):
    have = counts.get(path, 0)
    if path not in scanned:
        issues.append(("stale_baseline",
                       "%s is in the baseline but was not scanned; delete the entry "
                       "(--update-baseline)" % path))
    elif have < allowed:
        issues.append(("stale_baseline",
                       "%s is at %d, below its baseline %d; lower it so the ratchet "
                       "holds (--update-baseline)" % (path, have, allowed)))

def one_line(text):
    return " ".join(str(text).split())


print("=== POSITIONAL REFERENCES ===")
print("FILES_SCANNED=%d" % len(files))
print("SCANNED_EMPTY=%s" % ("true" if not files else "false"))
print("STRICT_FILES=%d" % strict_files)
print("STRICT_HITS=%d" % strict_hits)
print("SKILL_FILES=%d" % skill_files)
print("SKILL_HITS=%d" % skill_hits)
print("BASELINE_FILES=%d" % len(base))
print("BASELINE_TOTAL=%d" % sum(base.values()))
for row in hit_rows:
    print(row)
if issues:
    print("STATUS=ERROR")
    reason = one_line("%s: %s" % issues[0])[:180]
    if len(issues) > 1:
        reason += " (+%d more)" % (len(issues) - 1)
    print("REASON=%s" % reason)
else:
    print("STATUS=OK")
print("ISSUE_COUNT=%d" % len(issues))
if issues:
    print("ISSUES:")
    for itype, msg in issues:
        print("  - SEVERITY=ERROR TYPE=%s MSG=%s" % (itype, one_line(msg)))
print("=== END POSITIONAL REFERENCES ===")
sys.exit(1 if issues else 0)
PY

python3 -c "$PY_SRC" "$file_list" "$fence_list" "$baseline" "$update_baseline" "$verbose"

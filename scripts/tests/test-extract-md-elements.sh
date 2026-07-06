#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015  # SC2016: single-quoted `$ID`/command strings are literal fixture text; SC2015: the `A && B || C` mktemp guard is intentional (either check failing is the error)
# Semantic regression test for scripts/lib/extract-md-elements.py — the shared
# tree-sitter-markdown extraction helper the markdown-structure lint scripts
# consume instead of hand-rolling fence toggles / table-row skips / blockquote
# awareness (the source of shipped bugs #1744 and #1492).
#
# This is a *semantic* guard (.claude/rules/regression-testing.md): it asserts the
# helper still carries the structural invariants the consumers depend on, not just
# that the file parses. Required fixture shapes (issue #2009): fenced block, table
# row, blockquote, nested list, and `~~~` fences.
#
# Invariants:
#   A. A `!`cmd`` inside a ``` fenced block is NOT emitted as an inline_code span
#      (fenced content is not inline content — the #1744 false-positive class).
#   B. Same for a `~~~` fenced block.
#   C. `~~~` fenced content IS emitted as fence_line with its language, and a
#      ``` fence's `uses:`/`image:` lines are emitted as fence_line (what
#      check-version-pin-coverage consumes; the #1492 class).
#   D. A code span in a markdown table cell is labelled container=table_cell and
#      is_bang=0 (so a Context-command consumer excludes it — the `Rar!` case).
#   E. A `!`cmd`` inside a blockquote carries in_blockquote=1.
#   F. A `!`cmd`` in a nested list item is inline_code, container=list_item,
#      is_bang=1 (extracted as a real Context command).
#   G. A real Context command `- L: !`cmd`` is inline_code, list_item, is_bang=1.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
helper="$repo_root/scripts/lib/extract-md-elements.py"

if ! command -v uv >/dev/null 2>&1; then
  echo "SKIP: uv not found on PATH (helper runs via 'uv run')"
  exit 0
fi

pass_count=0
fail_count=0
assert() {
  # assert <description> <"true"|"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

workdir="$(mktemp -d)"
[ -n "$workdir" ] && [ -d "$workdir" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$workdir"' EXIT

fx="$workdir/fixture.md"
cat > "$fx" <<'EOF'
## Context

- Real: !`grep foo bar.yaml`

Nested list:

- Outer item
  - Nested: !`ls docs`

```bash
- Fenced: !`gh run view $ID`
uses: actions/checkout@v5
```

~~~yaml
- TildeFenced: !`should not run`
image: nginx:1.2.3
~~~

| Signature | Hex |
|-----------|-----|
| `Rar!` | `52 61 72 21` |

> - Quoted: !`echo hi`
EOF

inline="$(uv run --quiet "$helper" --types inline_code "$fx")"
fences="$(uv run --quiet "$helper" --types fence_line "$fx")"

# Helper: does an inline_code row exist whose text == $1 (exact, field 7)?
inline_has_text() {
  awk -F'\t' -v t="$1" '$1=="inline_code" && $7==t {found=1} END{exit found?0:1}' <<<"$inline"
}
# Helper: fetch a field ($3 line, $4 container, $5 in_bq, $6 is_bang) for the
# inline_code row whose text == $1. Prints the requested field number.
inline_field() {
  awk -F'\t' -v t="$1" -v f="$2" '$1=="inline_code" && $7==t {print $f; exit}' <<<"$inline"
}

# A. `!`cmd`` inside a ``` fence is NOT an inline_code span.
inline_has_text 'gh run view $ID' && a=false || a=true
assert "A: fenced (\`\`\`) !\`cmd\` is not emitted as inline_code (#1744)" "$a"

# B. `!`cmd`` inside a ~~~ fence is NOT an inline_code span.
inline_has_text 'should not run' && b=false || b=true
assert "B: fenced (~~~) !\`cmd\` is not emitted as inline_code (#1744)" "$b"

# C. Fenced content lines ARE emitted as fence_line with language (#1492).
c1="$(awk -F'\t' '$1=="fence_line" && $4=="bash" && $5 ~ /uses: actions\/checkout@v5/ {print "y"; exit}' <<<"$fences")"
c2="$(awk -F'\t' '$1=="fence_line" && $4=="yaml" && $5 ~ /image: nginx:1.2.3/ {print "y"; exit}' <<<"$fences")"
assert "C: \`\`\` fence content 'uses:' emitted as fence_line (lang=bash)" "$([ "$c1" = y ] && echo true || echo false)"
assert "C: ~~~ fence content 'image:' emitted as fence_line (lang=yaml)" "$([ "$c2" = y ] && echo true || echo false)"

# D. Table-cell code span → container=table_cell, is_bang=0.
d_ct="$(inline_field 'Rar!' 4)"
d_bang="$(inline_field 'Rar!' 6)"
assert "D: table cell \`Rar!\` is container=table_cell" "$([ "$d_ct" = "table_cell" ] && echo true || echo false)"
assert "D: table cell \`Rar!\` is is_bang=0 (not a Context command)" "$([ "$d_bang" = "0" ] && echo true || echo false)"

# E. Blockquote `!`cmd`` carries in_blockquote=1.
e_bq="$(inline_field 'echo hi' 5)"
e_bang="$(inline_field 'echo hi' 6)"
assert "E: blockquote !\`echo hi\` has in_blockquote=1" "$([ "$e_bq" = "1" ] && echo true || echo false)"
assert "E: blockquote !\`echo hi\` has is_bang=1" "$([ "$e_bang" = "1" ] && echo true || echo false)"

# F. Nested list item `!`cmd`` → inline_code, list_item, is_bang=1.
f_ct="$(inline_field 'ls docs' 4)"
f_bang="$(inline_field 'ls docs' 6)"
assert "F: nested list !\`ls docs\` is container=list_item" "$([ "$f_ct" = "list_item" ] && echo true || echo false)"
assert "F: nested list !\`ls docs\` is is_bang=1" "$([ "$f_bang" = "1" ] && echo true || echo false)"

# G. Real Context command → inline_code, list_item, is_bang=1.
g_ct="$(inline_field 'grep foo bar.yaml' 4)"
g_bang="$(inline_field 'grep foo bar.yaml' 6)"
assert "G: real Context cmd is container=list_item" "$([ "$g_ct" = "list_item" ] && echo true || echo false)"
assert "G: real Context cmd is is_bang=1" "$([ "$g_bang" = "1" ] && echo true || echo false)"

# JSON mode parses and is a superset (spot-check one field round-trips).
json_ok="$(uv run --quiet "$helper" --format json --types inline_code "$fx" \
  | python3 -c 'import json,sys; rows=[json.loads(l) for l in sys.stdin if l.strip()]; print("y" if any(r["text"]=="grep foo bar.yaml" and r["container"]=="list_item" and r["is_bang"] for r in rows) else "n")')"
assert "H: --format json emits a well-formed record for the real Context cmd" \
  "$([ "$json_ok" = "y" ] && echo true || echo false)"

echo "----"
echo "PASS=$pass_count FAIL=$fail_count"
[ "$fail_count" -eq 0 ] || exit 1

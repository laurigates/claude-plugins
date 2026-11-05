#!/usr/bin/env bash
# Regression test for check-readme-links.sh (issue #3307).
#
# configure-readme splits a long README into a slim README plus docs/ pages.
# The split moves headings, so relative links and #anchors that pointed at the
# old README sections break silently. These cases plant fixtures and EXECUTE
# the checker; every output block is also piped through the repo's
# structured-output --validate mode.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../check-readme-links.sh"
repo_root="$(cd "${script_dir}/../../../../.." && pwd)"
contract="${repo_root}/scripts/check-structured-output-contract.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$check_script" ] || fail "check-readme-links.sh not found at $check_script"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not available"; exit 0; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

validate() {
  # $1 = captured output, $2 = case label
  if [ -f "$contract" ]; then
    printf '%s\n' "$1" | bash "$contract" --validate - >/dev/null 2>&1 \
      || fail "$2: output violates the structured-output contract:\n$1"
  fi
}

# Writes a clean slim-README project into $1.
make_slim() {
  local d="$1"
  mkdir -p "$d/docs" "$d/assets"
  : > "$d/assets/logo.png"
  : > "$d/LICENSE"
  cat > "$d/README.md" <<'EOF'
<div align="center">

<img src="assets/logo.png" alt="demo" width="128">

# demo

</div>

A tool that does one thing. It reads input and writes reports.

## 🚀 Quick Start

```bash
demo run --input data.csv
```

See [the usage guide](docs/usage.md) and [releases](docs/development.md#releases).
Jump back to [quick start](#-quick-start). Ignore `[code](missing.md)` and
[external](https://example.com/x.md) and [mail](mailto:a@b.c).

```markdown
[fenced](not-there.md)
```

## Documentation

| Page | Contents |
|------|----------|
| [Usage](docs/usage.md) | CLI, outputs |
| [Development][dev] | Building, releases |

## License

[MIT](LICENSE)

[dev]: docs/development.md
EOF
  cat > "$d/docs/usage.md" <<'EOF'
# Usage

Back to the [README](../README.md#-quick-start).

## Recipes

## Recipes
EOF
  cat > "$d/docs/development.md" <<'EOF'
# Development

See [recipes](usage.md#recipes-1).

## Releases
EOF
}

# -----------------------------------------------------------------------------
# Case A: a clean slim README + docs/ pages -> STATUS=OK, exit 0
# -----------------------------------------------------------------------------
a="$work/a"; make_slim "$a"
outA="$(bash "$check_script" --project-dir "$a")"; rcA=$?
[ "$rcA" -eq 0 ] || fail "A: expected exit 0, got $rcA:\n$outA"
grep -q '^STATUS=OK$' <<<"$outA" || fail "A: expected STATUS=OK:\n$outA"
grep -q '^ISSUE_COUNT=0$' <<<"$outA" || fail "A: expected ISSUE_COUNT=0:\n$outA"
grep -q '^REASON=' <<<"$outA" && fail "A: REASON= must not appear on OK:\n$outA"
grep -q '^FILES_SCANNED=3$' <<<"$outA" || fail "A: expected FILES_SCANNED=3:\n$outA"
# Links checked: logo, usage, development#releases, #-quick-start, LICENSE,
# usage (table), [dev] ref, ../README.md#-quick-start, usage.md#recipes-1 = 9.
grep -q '^LINKS_CHECKED=9$' <<<"$outA" || fail "A: expected LINKS_CHECKED=9 (code, fences, external skipped):\n$outA"
validate "$outA" "A"
pass "A: clean slim README with docs/ pages passes; code spans, fences and external links are skipped"

# -----------------------------------------------------------------------------
# Case B: a docs/ page the README links to does not exist -> broken_link
# -----------------------------------------------------------------------------
b="$work/b"; make_slim "$b"
rm "$b/docs/usage.md"
outB="$(bash "$check_script" --project-dir "$b")"; rcB=$?
[ "$rcB" -eq 1 ] || fail "B: expected exit 1, got $rcB:\n$outB"
grep -q '^STATUS=ERROR$' <<<"$outB" || fail "B: expected STATUS=ERROR:\n$outB"
grep -q 'TYPE=broken_link FILE=README.md LINE=[0-9]* TARGET=docs/usage.md' <<<"$outB" \
  || fail "B: expected a broken_link row for README.md -> docs/usage.md:\n$outB"
grep -q '^REASON=broken_link: ' <<<"$outB" || fail "B: expected REASON=broken_link:\n$outB"
grep -q 'TYPE=broken_anchor FILE=docs/development.md' <<<"$outB" \
  && fail "B: usage.md#recipes-1 must report broken_link, not broken_anchor:\n$outB"
validate "$outB" "B"
pass "B: missing docs/ page reported as broken_link with exit 1"

# -----------------------------------------------------------------------------
# Case C: a link into a README section that moved out -> broken_anchor
# -----------------------------------------------------------------------------
c="$work/c"; make_slim "$c"
printf '\nSee [the old section](../README.md#usage).\n' >> "$c/docs/development.md"
outC="$(bash "$check_script" --project-dir "$c")"
grep -q '^STATUS=ERROR$' <<<"$outC" || fail "C: expected STATUS=ERROR:\n$outC"
grep -q 'TYPE=broken_anchor FILE=docs/development.md LINE=[0-9]* TARGET=../README.md#usage' <<<"$outC" \
  || fail "C: expected broken_anchor for ../README.md#usage:\n$outC"
grep -q '^BROKEN_ANCHORS=1$' <<<"$outC" || fail "C: expected BROKEN_ANCHORS=1:\n$outC"
validate "$outC" "C"
pass "C: link to a README heading that moved to docs/ reported as broken_anchor"

# -----------------------------------------------------------------------------
# Case D: same-file anchor that does not exist -> broken_anchor
# -----------------------------------------------------------------------------
d="$work/d"; make_slim "$d"
printf '\nSee [nothing](#features).\n' >> "$d/README.md"
outD="$(bash "$check_script" --project-dir "$d")"
grep -q 'TYPE=broken_anchor FILE=README.md LINE=[0-9]* TARGET=#features' <<<"$outD" \
  || fail "D: expected broken_anchor for #features:\n$outD"
validate "$outD" "D"
pass "D: same-file anchor to a removed heading reported"

# -----------------------------------------------------------------------------
# Case E: files outside README.md and docs/ that link into README sections
# -----------------------------------------------------------------------------
e="$work/e"; make_slim "$e"
mkdir -p "$e/skills/x" "$e/node_modules/pkg"
printf 'Read [README status](../../README.md#status).\n' > "$e/skills/x/SKILL.md"
printf '[gone](nowhere.md)\n' > "$e/node_modules/pkg/README.md"
outE="$(bash "$check_script" --project-dir "$e")"
grep -q 'TYPE=broken_anchor FILE=skills/x/SKILL.md' <<<"$outE" \
  || fail "E: expected a broken_anchor row for skills/x/SKILL.md:\n$outE"
grep -q 'FILE=node_modules/' <<<"$outE" && fail "E: node_modules must be skipped:\n$outE"
grep -q '^ISSUE_COUNT=1$' <<<"$outE" || fail "E: expected ISSUE_COUNT=1:\n$outE"
validate "$outE" "E"
pass "E: other Markdown files pointing at README sections are checked; node_modules skipped"

# -----------------------------------------------------------------------------
# Case F: no README.md -> readme_missing
# -----------------------------------------------------------------------------
f="$work/f"; mkdir -p "$f"
outF="$(bash "$check_script" --project-dir "$f")"; rcF=$?
[ "$rcF" -eq 1 ] || fail "F: expected exit 1, got $rcF:\n$outF"
grep -q 'TYPE=readme_missing' <<<"$outF" || fail "F: expected readme_missing:\n$outF"
validate "$outF" "F"
pass "F: missing README.md is an ERROR"

# -----------------------------------------------------------------------------
# Case G: unknown argument -> usage error, exit 2
# -----------------------------------------------------------------------------
bash "$check_script" --bogus >/dev/null 2>&1; rcG=$?
[ "$rcG" -eq 2 ] || fail "G: expected exit 2 on an unknown argument, got $rcG"
pass "G: unknown argument exits 2"

echo "ALL PASS"

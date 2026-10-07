#!/usr/bin/env bash
# shellcheck disable=SC2016  # file-level: backticked IDs and `§` citations in the planted fixtures are literal markdown
# Regression test for scripts/check-skill-xrefs.py
#
# Two guards, both of which a dead reference passes silently without:
#
#   citations  `<target> § <Heading>` must name a heading that exists. The
#              motivating defects: `wave-based-dispatch` cited
#              `parallel-agent-dispatch` "§Shared-File Exclusion List" and
#              "§Pre-Allocated Blueprint IDs", `exclusive-lock-dispatch` cited
#              "§Wave Splits" — none were headings, only bold-led paragraphs.
#   links      every relative markdown link, `#anchor` included, must resolve.
#              The motivating defect: `hooks-configuration` linked
#              `../../.claude/rules/hooks-reference.md`, one level too shallow.
#
# SEMANTIC, not syntactic: every case EXECUTES the real script against a
# planted fixture tree and asserts on its verdict and finding TYPE. A checker
# that scans zero files exits 0 exactly like a clean tree, so the empty-tree
# case must fail loudly.
#
# Exit codes: 0 all assertions pass, 1 otherwise.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
checker="$repo_root/scripts/check-skill-xrefs.py"
contract="$repo_root/scripts/check-structured-output-contract.sh"

pass=0
fail=0

ok() {
  printf '  PASS: %s\n' "$1"
  pass=$((pass + 1))
}

bad() {
  printf '  FAIL: %s\n' "$1"
  printf '        %s\n' "${2:-}"
  fail=$((fail + 1))
}

# Base fixture: an owner skill with real headings (numbered, parenthesised,
# colon-split, duplicated, and one inside a fence), a rule, and a references/
# split, so ground truth is non-empty and the clean control means something.
fixture="$(mktemp -d)"
[ -n "$fixture" ] || {
  printf 'mktemp -d failed\n' >&2
  exit 1
}
trap 'rm -rf "$fixture"' EXIT

own="$fixture/demo-plugin/skills/owner-skill"
mkdir -p "$own/references" "$fixture/demo-plugin/skills/user-skill" \
  "$fixture/.claude/rules" "$fixture/docs"
cat >"$own/SKILL.md" <<'EOF'
---
name: owner-skill
---

# Owner Skill

## 1. Worktree Preflight

## 2. Scope Budget (per-agent prompt rules)

**Pre-allocated IDs.** A bold-led paragraph, not a heading.

## The trap under all four: a check that never ran looks like a pass

## Stale tool copies — a tool "keeps coming back"

## Usage

## Usage

```markdown
## Heading Inside A Fence
```
EOF
printf -- '# Recovery\n\n## Recovering from a bare flip\n\nEntry point: [`../SKILL.md`](../SKILL.md) § Usage.\n' \
  >"$own/references/recovery.md"
printf -- '# Rule\n\n## Authoring rules\n\nBody.\n' >"$fixture/.claude/rules/demo-rule.md"
printf -- '---\nname: user-skill\n---\n\n# User\n\nBody.\n' >"$fixture/demo-plugin/skills/user-skill/SKILL.md"

user="demo-plugin/skills/user-skill"

# run_case <label> <expect: flag:<TYPE>|clean> <relative-path> <file-body>
# Plants one file, runs the checker, asserts the verdict, then removes the file
# so cases stay independent.
run_case() {
  local label="$1" expect="$2" rel="$3" body="$4" out status
  mkdir -p "$fixture/$(dirname "$rel")"
  printf '%s\n' "$body" >"$fixture/$rel"
  out="$(python3 "$checker" --project-dir "$fixture" 2>&1)"
  status=$?
  rm -f "$fixture/$rel"
  case "$expect" in
    flag:*)
      if [ "$status" -ne 0 ] && grep -q "TYPE=${expect#flag:} " <<<"$out"; then
        ok "$label"
      else
        bad "$label" "expected exit!=0 with TYPE=${expect#flag:}, got $status: $(grep -E 'TYPE=|REASON=' <<<"$out" | head -3)"
      fi
      ;;
    clean)
      if [ "$status" -eq 0 ]; then
        ok "$label"
      else
        bad "$label" "expected exit 0, got $status: $(grep -E 'TYPE=' <<<"$out" | head -3)"
      fi
      ;;
  esac
}

printf 'test-check-skill-xrefs\n'

# --- control ----------------------------------------------------------------
if out="$(python3 "$checker" --project-dir "$fixture" 2>&1)"; then
  ok "control: fixture with only resolvable references exits 0"
else
  bad "control: clean fixture" "$out"
fi

# --- citations: detection ---------------------------------------------------
run_case "detects a plugin:skill citation of a heading that does not exist" flag:dead-section-citation \
  "$user/REFERENCE.md" 'See `demo-plugin:owner-skill` § Shared-File Exclusion List.'

run_case "detects a bare skill-name citation of a missing heading" flag:dead-section-citation \
  "$user/REFERENCE.md" 'See `owner-skill` §Wave Splits for this.'

run_case "detects a citation after a link to a file lacking the heading" flag:dead-section-citation \
  "$user/references/x.md" 'Entry point: [`../SKILL.md`](../SKILL.md) § Nonexistent Step.'

run_case "detects an untargeted citation missing from its own file and skill" flag:dead-section-citation \
  "$user/REFERENCE.md" 'As in § Missing Section above.'

run_case "detects a .claude/rules citation of a missing heading" flag:dead-section-citation \
  "$user/REFERENCE.md" 'Per `.claude/rules/demo-rule.md` § Split long skills across files.'

run_case "a bold-led paragraph is not a citable heading" flag:dead-section-citation \
  "$user/REFERENCE.md" 'See `owner-skill` § Pre-allocated IDs.'

run_case "a heading inside a fenced code block is not a citable heading" flag:dead-section-citation \
  "$user/REFERENCE.md" 'See `owner-skill` § Heading Inside A Fence.'

run_case "a numeric citation must match a numbered heading" flag:dead-section-citation \
  "$user/REFERENCE.md" 'See `owner-skill` §9 for the details.'

# --- citations: resolution --------------------------------------------------
run_case "a heading cited whole with prose after it resolves (prefix)" clean \
  "$user/REFERENCE.md" 'See `demo-plugin:owner-skill` § Usage for how to run it.'

run_case "an abbreviated citation resolves (citation is a heading prefix)" clean \
  "$user/REFERENCE.md" 'See `owner-skill` § Stale tool copies.'

run_case "numbering and parentheticals are stripped from headings" clean \
  "$user/REFERENCE.md" 'See `owner-skill` § Scope Budget ("Pre-allocated IDs").'

run_case "the text after a heading colon is citable" clean \
  "$user/REFERENCE.md" 'See `owner-skill` § *"a check that never ran looks like a pass"*.'

run_case "a numeric citation resolves to its numbered heading" clean \
  "$user/REFERENCE.md" 'See `owner-skill` §1 before dispatch.'

run_case "a references/ file under a plugin:skill target resolves inside it" clean \
  "$user/REFERENCE.md" 'See `demo-plugin:owner-skill` `references/recovery.md` § Recovering from a bare flip.'

run_case "chained citations inherit the previous target" clean \
  "$user/REFERENCE.md" 'See `owner-skill` § Worktree Preflight / § Scope Budget.'

run_case "a table of bare § rows resolves against the section's named owner" clean \
  "$user/REFERENCE.md" '## Shared

Defined in `owner-skill`:

| What | Where |
|---|---|
| Budget | § Scope Budget |'

# --- citations: exemptions --------------------------------------------------
run_case "a citation inside fenced code is exempt" clean \
  "$user/REFERENCE.md" '```text
See `owner-skill` § Nonexistent.
```'

run_case "a § inside link text is the link guard's business" clean \
  "$user/REFERENCE.md" 'See [docs.md § Nonexistent](https://example.com/docs).'

run_case "a §N example in inline code is not a citation" clean \
  "$user/REFERENCE.md" 'Number sections `§1`…`§N` in the brief.'

run_case "an out-of-repo rule target is external, not dead" clean \
  "$user/REFERENCE.md" 'See `~/.claude/rules/elsewhere.md` § Anything.'

# --- links: detection -------------------------------------------------------
run_case "detects a relative link to a missing file" flag:dead-relative-link \
  "$user/references/links.md" 'See [gone](gone.md).'

run_case "detects a rules link one level too shallow from a skill dir" flag:dead-relative-link \
  "$user/REFERENCE.md" 'See [rule](../../.claude/rules/demo-rule.md).'

run_case "detects a link anchor no heading slugs to" flag:dead-link-anchor \
  "$user/REFERENCE.md" 'See [x](../owner-skill/SKILL.md#no-such-heading).'

run_case "an anchor to a heading inside a fence is dead" flag:dead-link-anchor \
  "$user/REFERENCE.md" 'See [x](../owner-skill/SKILL.md#heading-inside-a-fence).'

run_case "an em-dash heading slugs to a DOUBLE hyphen" flag:dead-link-anchor \
  "$user/REFERENCE.md" 'See [x](../owner-skill/SKILL.md#stale-tool-copies-a-tool-keeps-coming-back).'

run_case "detects a dead same-file anchor" flag:dead-link-anchor \
  "$user/REFERENCE.md" '# Ref

See [below](#nowhere).'

# --- links: resolution ------------------------------------------------------
run_case "a correct depth link with a valid anchor resolves" clean \
  "$user/REFERENCE.md" 'See [rule](../../../.claude/rules/demo-rule.md#authoring-rules).'

run_case "GitHub slug rules: em-dash double hyphen and duplicate -1 suffix" clean \
  "$user/REFERENCE.md" 'See [a](../owner-skill/SKILL.md#stale-tool-copies--a-tool-keeps-coming-back) and [b](../owner-skill/SKILL.md#usage-1).'

run_case "a link to a directory resolves" clean \
  "$user/REFERENCE.md" 'See [owner](../owner-skill/).'

# --- links: exemptions ------------------------------------------------------
run_case "a link inside fenced code is exempt" clean \
  "$user/REFERENCE.md" '````markdown
[Contributing](CONTRIBUTING.md)
```bash
echo nested
```
````'

run_case "a link inside inline code is exempt" clean \
  "$user/REFERENCE.md" 'Write `[text](missing.md)` in your README.'

run_case "external URLs and templated placeholders are exempt" clean \
  "$user/REFERENCE.md" 'See [x](https://example.com/a.md) and [y]({{url}}).'

# --- unreadable input is a finding ------------------------------------------
printf 'bad \xff byte\n' >"$fixture/$user/REFERENCE.md"
out="$(python3 "$checker" --project-dir "$fixture" 2>&1)"
status=$?
rm -f "$fixture/$user/REFERENCE.md"
if [ "$status" -ne 0 ] && grep -q 'TYPE=unreadable-file' <<<"$out"; then
  ok "a non-UTF-8 scan file is reported, not silently skipped"
else
  bad "unreadable file" "expected TYPE=unreadable-file, got $status: $out"
fi

# --- non-vacuity ------------------------------------------------------------
empty="$(mktemp -d)"
[ -n "$empty" ] || exit 1
out="$(python3 "$checker" --project-dir "$empty" 2>&1)"
status=$?
rm -rf "$empty"
if [ "$status" -ne 0 ] && grep -q 'discovery walk is broken' <<<"$out"; then
  ok "empty tree fails loudly instead of passing vacuously"
else
  bad "empty tree" "expected exit!=0 naming a broken walk, got $status: $out"
fi

# --- cwd independence -------------------------------------------------------
printf 'See `owner-skill` § Nonexistent.\n' >"$fixture/$user/REFERENCE.md"
out="$(cd / && python3 "$checker" --project-dir "$fixture" 2>&1)"
status=$?
rm -f "$fixture/$user/REFERENCE.md"
if [ "$status" -ne 0 ]; then
  ok "scans correctly when invoked from an unrelated cwd"
else
  bad "cwd independence" "found nothing when run from /: $out"
fi

# --- structured-output contract, failing and passing blocks -----------------
printf 'See `owner-skill` § Nonexistent and [x](gone.md).\n' >"$fixture/$user/REFERENCE.md"
for only in citations links; do
  block="$(python3 "$checker" --project-dir "$fixture" --only "$only" 2>/dev/null)"
  if printf '%s\n' "$block" | bash "$contract" --validate >/dev/null 2>&1; then
    ok "failing --only $only block satisfies the STATUS/REASON/ISSUE_COUNT contract"
  else
    bad "contract (failing $only)" "$(printf '%s\n' "$block" | bash "$contract" --validate 2>&1 | tail -3)"
  fi
done
rm -f "$fixture/$user/REFERENCE.md"
for only in citations links; do
  block="$(python3 "$checker" --project-dir "$fixture" --only "$only" 2>/dev/null)"
  if printf '%s\n' "$block" | bash "$contract" --validate >/dev/null 2>&1; then
    ok "passing --only $only block satisfies the contract"
  else
    bad "contract (passing $only)" "$(printf '%s\n' "$block" | bash "$contract" --validate 2>&1 | tail -3)"
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0

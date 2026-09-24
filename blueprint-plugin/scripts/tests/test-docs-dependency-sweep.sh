#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
# SC2015: `check && ok … || notok …` is deliberate — ok/notok end in printf
# and exit 0, so the || branch runs only on a real failure.
# SC2016: the fixture printf strings carry literal markdown backticks.
# Regression tests for docs-dependency-sweep.sh — the bounded doc dependency
# sweep behind blueprint-docs-currency's pre-commit checklist (issue #2692).
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
#
# Pins the issue's acceptance criteria as behaviour, against a throwaway git
# repo so the result never depends on the developer's real index:
#
#   A  a staged skill change names that skill's plugin README (at the row that
#      names it), its plugin.json, and the plugin's catalog rows — and nothing
#      outside that set
#   B  the sweep opens only the files it reports (DOCS_SWEEP_TRACE), never more
#      than CANDIDATE_CAP, and never a doc outside the derived set even when
#      that doc names the changed skill
#   C  CANDIDATE_CAP is emitted and honoured: past the cap the sweep stops,
#      examines exactly CAP files in priority order, and reports the rest as one
#      cap_reached finding (--cap and DOCS_SWEEP_CAP both work)
#   D  a candidate already staged is covered: counted, not examined, not a
#      finding
#   E  a staged rule names CLAUDE.md first, then the docs that cite `<rule>.md`,
#      and excludes a lookalike name, CHANGELOGs, and the rule itself
#   F  an agent change sweeps the catalog; a hook change sweeps the plugin
#      README and plugin.json but not the catalog
#   G  unmapped paths are counted, not swept (STATUS=OK)
#   H  an explicitly EMPTY seam means "nothing staged" and does not fall through
#      to the real index (the #2521 lesson)
#   I  with the seam unset, the real `git diff --cached` is read, and a
#      --project-dir inside the repo resolves to the work-tree root
#   J  invalid usage fails loudly: bad --cap / unknown flag exit 2, a non-git
#      dir is STATUS=ERROR exit 1
#   K  the section delimiters and roll-up are well formed: ISSUE_COUNT equals
#      the ISSUES rows
set -u

# Neutralize inherited git context so no sandbox git op can be hijacked into the
# real shared .git (issue #1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX
unset DOCS_SWEEP_STAGED DOCS_SWEEP_TRACE DOCS_SWEEP_CAP

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWEEP="${SCRIPT_DIR}/../docs-dependency-sweep.sh"

pass=0
fail=0
ok()    { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

SANDBOX_ROOT="$(mktemp -d)" || { echo "FATAL: mktemp failed" >&2; exit 1; }
[ -n "$SANDBOX_ROOT" ] || { echo "FATAL: empty mktemp dir" >&2; exit 1; }
[ -d "$SANDBOX_ROOT" ] || { echo "FATAL: mktemp dir missing" >&2; exit 1; }
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

REPO="${SANDBOX_ROOT}/repo"
TRACE="${SANDBOX_ROOT}/trace"

# --- fixture ------------------------------------------------------------------
mkdir -p "$REPO/foo-plugin/.claude-plugin" "$REPO/foo-plugin/skills/foo-bar" \
    "$REPO/foo-plugin/skills/foo-baz" "$REPO/foo-plugin/agents" "$REPO/foo-plugin/hooks" \
    "$REPO/.claude-plugin" "$REPO/.claude/rules" "$REPO/docs" "$REPO/notes" "$REPO/src"

printf '{"name": "foo-plugin", "description": "Foo things"}\n' > "$REPO/foo-plugin/.claude-plugin/plugin.json"
printf '# foo-plugin\n\n| Skill | Purpose |\n|---|---|\n| `foo-bar` | Does bar |\n| `/foo:baz` | Does baz |\n\n## Agents\n\n| `foo-agent` | Helps |\n\n## Hooks\n\n| `foo-hook.sh` | Guards |\n' > "$REPO/foo-plugin/README.md"
printf -- '---\nname: foo-bar\n---\nBar.\n' > "$REPO/foo-plugin/skills/foo-bar/SKILL.md"
printf -- '---\nname: foo-baz\n---\nBaz.\n' > "$REPO/foo-plugin/skills/foo-baz/SKILL.md"
printf -- '---\nname: foo-agent\n---\nAgent.\n' > "$REPO/foo-plugin/agents/foo-agent.md"
printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/foo-plugin/hooks/foo-hook.sh"
printf '# Changelog\n\n- cites alpha.md and foo-bar\n' > "$REPO/foo-plugin/CHANGELOG.md"
printf '# Marketplace\n\nIntro line.\n\n| **foo-plugin** | 2 | Foo things |\n' > "$REPO/README.md"
printf '# Plugin map\n\n| foo-plugin | 2 | `/foo:bar` does bar |\n' > "$REPO/docs/PLUGIN-MAP.md"
printf '{\n  "plugins": [\n    {\n      "name": "foo-plugin"\n    }\n  ]\n}\n' > "$REPO/.claude-plugin/marketplace.json"
printf '# Project\n\n| Rule | Purpose |\n|---|---|\n| `.claude/rules/alpha.md` | Alpha |\n' > "$REPO/CLAUDE.md"
printf '# Alpha\n\nThe alpha rule.\n' > "$REPO/.claude/rules/alpha.md"
printf '# Beta\n\nSee [alpha](alpha.md).\n' > "$REPO/.claude/rules/beta.md"
printf '# Gamma\n\nSee not-alpha.md, a different rule.\n' > "$REPO/.claude/rules/gamma.md"
printf '# Guide\n\nFollow .claude/rules/alpha.md here.\n' > "$REPO/docs/guide.md"
# Names the skill but sits outside every rung: the sweep must never open it.
printf '# Stray\n\nfoo-bar is mentioned here, and so is foo-plugin.\n' > "$REPO/notes/stray.md"
printf 'print("x")\n' > "$REPO/src/main.py"

git -C "$REPO" init -q || { echo "FATAL: git init failed" >&2; exit 1; }
git -C "$REPO" add -A
git -C "$REPO" -c core.hooksPath=/dev/null -c user.email=test@example.invalid -c user.name=test commit -qm fixture ||
    { echo "FATAL: fixture commit failed" >&2; exit 1; }

# Sets the globals `out` and `RC` (a command substitution at the call site
# would swallow the exit code the caller needs).
out=""
RC=0
run_sweep() {
    : > "$TRACE"
    out="$(DOCS_SWEEP_TRACE="$TRACE" bash "$SWEEP" --project-dir "$REPO" "$@" 2>&1)"
    RC=$?
}
run_staged() {
    local staged="$1"
    shift
    : > "$TRACE"
    out="$(DOCS_SWEEP_STAGED="$staged" DOCS_SWEEP_TRACE="$TRACE" bash "$SWEEP" --project-dir "$REPO" "$@" 2>&1)"
    RC=$?
}

kv() { printf '%s\n' "$out" | grep -E "^$1=" | head -n 1 | cut -d= -f2-; }
docs_reported() { printf '%s\n' "$out" | grep -oE 'TYPE=review_candidate DOC=[^ ]+' | sed 's/.*DOC=//'; }
row_for() { printf '%s\n' "$out" | grep -F "TYPE=review_candidate DOC=$1 "; }
has_doc() { docs_reported | grep -qxF "$1"; }

expect_kv() {
    local key="$1" want="$2" label="$3" got
    got="$(kv "$key")"
    if [ "$got" = "$want" ]; then ok "$label"; else notok "$label (want $key=$want, got '$got')"; fi
}

# Every opened file is a reported doc, and the count matches FILES_EXAMINED and
# stays within the cap.
expect_trace_bounded() {
    local label="$1" cap examined traced stray=""
    cap="$(kv CANDIDATE_CAP)"
    examined="$(kv FILES_EXAMINED)"
    traced="$(grep -c . "$TRACE")"
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        has_doc "$t" || stray="$stray $t"
    done < "$TRACE"
    if [ -z "$stray" ] && [ "$traced" = "$examined" ] && [ "$traced" -le "$cap" ]; then
        ok "$label"
    else
        notok "$label (traced=$traced examined=$examined cap=$cap stray:$stray)"
    fi
}

SKILL=foo-plugin/skills/foo-bar/SKILL.md

# --- A: skill change names README row, plugin.json, catalog rows --------------
run_staged "$SKILL"
[ "$RC" -eq 0 ] && ok "A: WARN exits 0" || notok "A: WARN exits 0 (rc=$RC)"
expect_kv STATUS WARN "A: unstaged candidates make STATUS=WARN"
expect_kv CANDIDATES_TOTAL 5 "A: five candidates derived"
expect_kv FILES_EXAMINED 5 "A: all five examined under the default cap"
expect_kv CANDIDATE_CAP 10 "A: default cap is emitted"
row_for foo-plugin/README.md | grep -q 'KIND=plugin_readme .*ENTRY_LINES=5 ' &&
    ok "A: plugin README row points at the skill's row (line 5)" ||
    notok "A: plugin README row points at the skill's row: $(row_for foo-plugin/README.md)"
row_for foo-plugin/.claude-plugin/plugin.json | grep -q 'KIND=plugin_manifest ' &&
    ok "A: plugin.json named" || notok "A: plugin.json named"
row_for README.md | grep -q 'KIND=catalog .*ENTRY_LINES=5 ' &&
    ok "A: top-level catalog row located (line 5)" || notok "A: top-level catalog row: $(row_for README.md)"
row_for docs/PLUGIN-MAP.md | grep -q 'KIND=catalog .*ENTRY_LINES=3 ' &&
    ok "A: PLUGIN-MAP row located via plugin name and /foo:bar invocation" ||
    notok "A: PLUGIN-MAP row: $(row_for docs/PLUGIN-MAP.md)"
row_for .claude-plugin/marketplace.json | grep -q 'KIND=catalog .*ENTRY_LINES=4 ' &&
    ok "A: marketplace.json entry located (line 4)" || notok "A: marketplace entry: $(row_for .claude-plugin/marketplace.json)"
if has_doc notes/stray.md || has_doc CLAUDE.md || has_doc docs/guide.md || has_doc foo-plugin/CHANGELOG.md; then
    notok "A: nothing outside the derived set is named ($(docs_reported | paste -sd' ' -))"
else
    ok "A: nothing outside the derived set is named"
fi
first_doc="$(docs_reported | head -n 1)"
[ "$first_doc" = foo-plugin/README.md ] && ok "A: plugin README is examined first" ||
    notok "A: plugin README is examined first (got $first_doc)"

# --- B: reads stay inside the reported set ------------------------------------
expect_trace_bounded "B: files opened == FILES_EXAMINED <= cap, all reported"
grep -qxF notes/stray.md "$TRACE" && notok "B: stray doc naming the skill is never opened" ||
    ok "B: stray doc naming the skill is never opened"

# --- C: cap emitted and honoured ----------------------------------------------
run_staged "$SKILL" --cap 2
expect_kv CANDIDATE_CAP 2 "C: --cap is emitted"
expect_kv FILES_EXAMINED 2 "C: exactly CAP files examined"
expect_kv CANDIDATES_DROPPED 3 "C: the rest are dropped, not examined"
expect_kv ISSUE_COUNT 3 "C: one cap_reached + two review rows"
printf '%s\n' "$out" | grep -q 'TYPE=cap_reached CAP=2 DROPPED=3 FIRST_DROPPED=.claude-plugin/marketplace.json ' &&
    ok "C: cap_reached names the count and the first dropped doc" ||
    notok "C: cap_reached row: $(printf '%s\n' "$out" | grep cap_reached)"
[ "$(docs_reported | paste -sd, -)" = "foo-plugin/README.md,foo-plugin/.claude-plugin/plugin.json" ] &&
    ok "C: the cap keeps the highest-priority candidates" ||
    notok "C: priority under the cap (got $(docs_reported | paste -sd, -))"
expect_trace_bounded "C: files opened stay within the cap"
: > "$TRACE"
out="$(DOCS_SWEEP_CAP=1 DOCS_SWEEP_STAGED="$SKILL" DOCS_SWEEP_TRACE="$TRACE" bash "$SWEEP" --project-dir "$REPO" 2>&1)"
expect_kv CANDIDATE_CAP 1 "C: DOCS_SWEEP_CAP env is honoured"
expect_kv FILES_EXAMINED 1 "C: DOCS_SWEEP_CAP bounds examination"

# --- D: a staged candidate is covered -----------------------------------------
run_staged "$SKILL
foo-plugin/README.md"
expect_kv CANDIDATES_STAGED 1 "D: staged README counted as covered"
expect_kv FILES_EXAMINED 4 "D: covered README not examined"
has_doc foo-plugin/README.md && notok "D: covered README is not a finding" || ok "D: covered README is not a finding"
grep -qxF foo-plugin/README.md "$TRACE" && notok "D: covered README never opened" || ok "D: covered README never opened"

# --- E: rule back-references --------------------------------------------------
run_staged ".claude/rules/alpha.md"
[ "$(docs_reported | paste -sd, -)" = "CLAUDE.md,.claude/rules/beta.md,docs/guide.md" ] &&
    ok "E: CLAUDE.md first, then citing docs in path order" ||
    notok "E: rule candidates (got $(docs_reported | paste -sd, -))"
row_for CLAUDE.md | grep -q 'KIND=rule_index .*ENTRY_LINES=5 ' && ok "E: CLAUDE.md index row located" ||
    notok "E: CLAUDE.md row: $(row_for CLAUDE.md)"
row_for .claude/rules/beta.md | grep -q 'KIND=rule_backref ' && ok "E: citing rule is a rule_backref" ||
    notok "E: beta row: $(row_for .claude/rules/beta.md)"
has_doc .claude/rules/gamma.md && notok "E: not-alpha.md lookalike excluded" || ok "E: not-alpha.md lookalike excluded"
has_doc foo-plugin/CHANGELOG.md && notok "E: CHANGELOG excluded" || ok "E: CHANGELOG excluded"
has_doc .claude/rules/alpha.md && notok "E: the rule itself is not its own back-reference" ||
    ok "E: the rule itself is not its own back-reference"

# --- F: agent vs hook ---------------------------------------------------------
run_staged "foo-plugin/agents/foo-agent.md"
row_for foo-plugin/README.md | grep -q 'ENTRY_LINES=10 ' && ok "F: agent row located in plugin README" ||
    notok "F: agent row: $(row_for foo-plugin/README.md)"
has_doc docs/PLUGIN-MAP.md && ok "F: agent change sweeps the catalog" || notok "F: agent change sweeps the catalog"
run_staged "foo-plugin/hooks/foo-hook.sh"
[ "$(docs_reported | paste -sd, -)" = "foo-plugin/README.md,foo-plugin/.claude-plugin/plugin.json" ] &&
    ok "F: hook change sweeps plugin README + plugin.json only" ||
    notok "F: hook candidates (got $(docs_reported | paste -sd, -))"
row_for foo-plugin/README.md | grep -q 'ENTRY_LINES=14 ' && ok "F: hook row located by basename" ||
    notok "F: hook row: $(row_for foo-plugin/README.md)"

# --- G: unmapped --------------------------------------------------------------
run_staged "src/main.py"
expect_kv STATUS OK "G: unmapped path is STATUS=OK"
expect_kv UNMAPPED_PATHS 1 "G: unmapped path counted"
expect_kv ISSUE_COUNT 0 "G: no findings"

# --- H: explicitly empty seam -------------------------------------------------
printf 'changed\n' >> "$REPO/$SKILL"
git -C "$REPO" add -- "$SKILL"
run_staged ""
expect_kv STAGED_PATHS 0 "H: empty seam means nothing staged, real index ignored"
expect_kv STATUS OK "H: empty seam is STATUS=OK"

# --- I: real index + subdir project dir ---------------------------------------
: > "$TRACE"
out="$(DOCS_SWEEP_TRACE="$TRACE" bash "$SWEEP" --project-dir "$REPO/docs" 2>&1)"
expect_kv STAGED_PATHS 1 "I: seam unset reads git diff --cached"
has_doc foo-plugin/README.md && ok "I: subdir --project-dir resolves to the root" ||
    notok "I: subdir --project-dir resolves to the root ($(kv STATUS))"

# --- J: invalid usage ---------------------------------------------------------
run_staged "$SKILL" --cap 0
[ "$RC" -eq 2 ] && ok "J: --cap 0 exits 2" || notok "J: --cap 0 exits 2 (rc=$RC)"
run_staged "$SKILL" --cap abc
[ "$RC" -eq 2 ] && ok "J: --cap abc exits 2" || notok "J: --cap abc exits 2 (rc=$RC)"
run_staged "$SKILL" --bogus
[ "$RC" -eq 2 ] && ok "J: unknown flag exits 2" || notok "J: unknown flag exits 2 (rc=$RC)"
NOGIT="${SANDBOX_ROOT}/nogit"
mkdir -p "$NOGIT"
out="$(DOCS_SWEEP_STAGED="$SKILL" GIT_CEILING_DIRECTORIES="$SANDBOX_ROOT" bash "$SWEEP" --project-dir "$NOGIT" 2>&1)"
RC=$?
[ "$RC" -eq 1 ] && [ "$(kv STATUS)" = ERROR ] && ok "J: non-git dir is STATUS=ERROR exit 1" ||
    notok "J: non-git dir (rc=$RC status=$(kv STATUS))"

# --- K: structure -------------------------------------------------------------
run_staged "$SKILL" --cap 2
first="$(printf '%s\n' "$out" | head -n 1)"
last="$(printf '%s\n' "$out" | tail -n 1)"
rows="$(printf '%s\n' "$out" | grep -c '^  - SEVERITY=')"
if [ "$first" = "=== DOCS DEPENDENCY SWEEP ===" ] && [ "$last" = "=== END DOCS DEPENDENCY SWEEP ===" ] &&
    [ "$rows" = "$(kv ISSUE_COUNT)" ]; then
    ok "K: delimiters well formed and ISSUE_COUNT equals ISSUES rows"
else
    notok "K: structure (first='$first' last='$last' rows=$rows count=$(kv ISSUE_COUNT))"
fi

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]

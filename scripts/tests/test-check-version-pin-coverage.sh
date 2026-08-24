#!/usr/bin/env bash
# Regression test for scripts/check-version-pin-coverage.sh
# (.claude/rules/version-pinning.md — the trivy SHA-mismatch class).
#
# Guards:
#   A. the real repo stays ERROR-free — every executable pin is in a
#      Renovate-managed shape, so --strict exits 0
#   B. a version-shaped 'uses:' ref in an unmanaged shape is flagged ERROR and
#      --strict exits 1 (the silent-drift case the guard exists to catch)
#   C. managed shapes (tag form + SHA-with-version-comment) are NOT flagged
#   D. version numbers in prose (outside code fences) are ignored by design
#   E. floating refs (@main) are intentionally not flagged
#   G. transitive-pin gap (#2175): a SHA-pinned installer action whose own
#      `version:` input is absent or floating is flagged ERROR, while the same
#      step with an explicit tag is not — the pin must cover the BINARY, not
#      just the wrapper
#   I. path gap (#2222): a plugin scaffold template's pin is flagged when NO
#      manager file pattern matches its path, while the template's own
#      .github/workflows/ subtree and package.json — already reached by the
#      built-in '(^|/)'-prefixed patterns — are not; and the finding clears when
#      renovate.json is widened, proving the guard reads the config
#   H. the gitignored dist/ OpenCode export build output is pruned, not scanned
#      (#2214) — with a guard-integrity half proving the same defective pin at
#      a real path is still reported
#   J. trigger gap (#2285): the guard body is whole-repo, so the invariant that
#      matters is that its TRIGGERS select a template-only / renovate.json-only
#      change — the pre-commit `files:` regex (evaluated with pre-commit's own
#      matcher) and the workflow step's `if:` (evaluated against outputs from
#      EXECUTING the workflow's own `changed` step against real git diffs)
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-version-pin-coverage.sh"

pass_count=0
fail_count=0

assert() {
  # assert <description> <condition-result-string "true"/"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

field() { printf '%s\n' "$1" | grep -m1 "^$2=" | cut -d= -f2; }
contains() { printf '%s' "$1" | grep -q "$2" && echo true || echo false; }

echo "=== TEST A: real repo is ERROR-free ==="
real_out="$(bash "$checker" --project-dir "$repo_root")"
assert "real repo STATUS should not be ERROR" \
  "$([ "$(field "$real_out" STATUS)" != "ERROR" ] && echo true || echo false)"
clean_rc=0
bash "$checker" --project-dir "$repo_root" --strict >/dev/null || clean_rc=$?
assert "--strict should exit 0 on the real repo" \
  "$([ "$clean_rc" -eq 0 ] && echo true || echo false)"

# --- Build a synthetic fixture with one uncovered pin -------------------------
# Guarded because TEST J below runs git against throwaway sandboxes in this same
# script: an empty $VAR would make `git -C ""` act on the real checkout (#1692).
fixture="$(mktemp -d)" || exit 1
[ -n "$fixture" ] || { echo "FAIL: mktemp -d returned empty" >&2; exit 1; }
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/demo-plugin/skills/demo"

cat > "$fixture/demo-plugin/skills/demo/SKILL.md" <<'EOF'
# Demo

Managed tag form:

```yaml
- uses: actions/checkout@v5
```

Managed SHA + version comment:

```yaml
- uses: actions/setup-node@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
```

Floating ref (intentionally unpinned):

```yaml
- uses: trufflesecurity/trufflehog@main
```

Unmanaged version-shaped ref (should be flagged):

```yaml
- uses: foo/bar@1
```

A version in a prose table is illustrative, not executable:

| Tool | Version |
|------|---------|
| widget | uses: foo/bar@1 |
EOF

echo "=== TEST B: uncovered uses: ref flagged + --strict exit ==="
fx_out="$(bash "$checker" --project-dir "$fixture")"
assert "foo/bar@1 inside a fence should be flagged uses_uncovered" \
  "$(contains "$fx_out" "uses_uncovered")"
assert "fixture STATUS should be ERROR" \
  "$([ "$(field "$fx_out" STATUS)" = "ERROR" ] && echo true || echo false)"
strict_rc=0
bash "$checker" --project-dir "$fixture" --strict >/dev/null || strict_rc=$?
assert "--strict should exit 1 on uncovered pin" \
  "$([ "$strict_rc" -eq 1 ] && echo true || echo false)"

echo "=== TEST C: managed shapes counted, not flagged ==="
assert "tag form counts toward USES_COVERED (>=2 covered)" \
  "$([ "$(field "$fx_out" USES_COVERED)" -ge 2 ] && echo true || echo false)"

echo "=== TEST D: exactly one ERROR (prose copy is ignored) ==="
err_lines="$(printf '%s\n' "$fx_out" | grep -c 'SEVERITY=ERROR' || true)"
assert "only the fenced foo/bar@1 is flagged, not the prose-table copy" \
  "$([ "$err_lines" -eq 1 ] && echo true || echo false)"

echo "=== TEST E: floating @main not flagged ==="
assert "trufflehog@main produces no issue" \
  "$([ "$(contains "$fx_out" "trufflehog")" = "false" ] && echo true || echo false)"

echo "=== TEST F: .claude/worktrees/ copies are pruned, not scanned (#1492) ==="
# A sibling agent's worktree checkout is a full repo copy under
# .claude/worktrees/. Adding a skill file there must NOT change FILES_SCANNED
# (the guard audits only the real tree) and must NOT re-flag its uncovered pin.
before_scanned="$(field "$fx_out" FILES_SCANNED)"
before_errors="$(printf '%s\n' "$fx_out" | grep -c 'SEVERITY=ERROR' || true)"
mkdir -p "$fixture/.claude/worktrees/agent-deadbeef/demo-plugin/skills/demo"
cp "$fixture/demo-plugin/skills/demo/SKILL.md" \
   "$fixture/.claude/worktrees/agent-deadbeef/demo-plugin/skills/demo/SKILL.md"
wt_out="$(bash "$checker" --project-dir "$fixture")"
assert "FILES_SCANNED unchanged after adding a worktree copy" \
  "$([ "$(field "$wt_out" FILES_SCANNED)" -eq "$before_scanned" ] && echo true || echo false)"
assert "no extra ERROR from the worktree copy's uncovered pin" \
  "$([ "$(printf '%s\n' "$wt_out" | grep -c 'SEVERITY=ERROR' || true)" -eq "$before_errors" ] && echo true || echo false)"
assert "no WARN/ERROR issue references a .claude/worktrees/ path" \
  "$([ "$(contains "$wt_out" '.claude/worktrees/')" = "false" ] && echo true || echo false)"

echo "=== TEST G: transitive binary pin — version: input (#2175) ==="
# A SHA-pinned `uses:` pins the composite action, NOT the binary its installer
# downloads. Connorrmcd6/surface's action.yml declares `version:` with
# `default: latest`, so a step that omits the input (or sets a floating value)
# ships a workflow that reads as fully pinned while installing a fresh binary on
# every run. Kept in its own fixture so TEST D's exact-ERROR-count and TEST F's
# worktree-prune assertions stay independent of these cases.
fixture_bad="$(mktemp -d)"
[ -n "$fixture_bad" ] || { echo "FAIL: mktemp -d returned empty" >&2; exit 1; }
fixture_good="$(mktemp -d)"
[ -n "$fixture_good" ] || { echo "FAIL: mktemp -d returned empty" >&2; exit 1; }
trap 'rm -rf "$fixture" "$fixture_bad" "$fixture_good"' EXIT

mkdir -p "$fixture_bad/demo-plugin/skills/demo"
cat > "$fixture_bad/demo-plugin/skills/demo/SKILL.md" <<'EOF'
# Demo

Absent version input — the defect shape reported in #2175:

```yaml
- uses: Connorrmcd6/surface@091b937ae34ac81a02386604fed977dd24f1f0cf # v0.8.0
  with:
    args: check
```

Present but floating — same outcome, stated out loud:

```yaml
- uses: Connorrmcd6/surface@091b937ae34ac81a02386604fed977dd24f1f0cf # v0.8.0
  with:
    version: latest
    args: check
```
EOF

mkdir -p "$fixture_good/demo-plugin/skills/demo"
cat > "$fixture_good/demo-plugin/skills/demo/SKILL.md" <<'EOF'
# Demo

Both pins present — the corrected shape:

```yaml
- uses: Connorrmcd6/surface@091b937ae34ac81a02386604fed977dd24f1f0cf # v0.8.0
  with:
    version: v0.8.0
    args: check
```

A non-installer action needs no version input (guard integrity — this must not
become "every pinned action must declare a version"):

```yaml
- uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
  with:
    fetch-depth: 1
```

An action outside the curated installer list keeps its floating `version:` — a
toolchain setup action tracking the latest release is a deliberate choice, not a
gate-stability hazard, and flagging it would make the guard opine on files a
reporting PR never touched:

```yaml
- uses: astral-sh/setup-uv@e92bafb6253dcd438e0484186d7669ea7a8ca1cc # v6.4.3
  with:
    version: "latest"
```
EOF

bad_out="$(bash "$checker" --project-dir "$fixture_bad")"
assert "absent version: input is flagged version_input_missing" \
  "$(contains "$bad_out" "version_input_missing")"
assert "version: latest is flagged version_input_floating" \
  "$(contains "$bad_out" "version_input_floating")"
assert "bad fixture STATUS should be ERROR" \
  "$([ "$(field "$bad_out" STATUS)" = "ERROR" ] && echo true || echo false)"
assert "exactly two ERRORs in the bad fixture (one per defect shape)" \
  "$([ "$(printf '%s\n' "$bad_out" | grep -c 'SEVERITY=ERROR' || true)" -eq 2 ] && echo true || echo false)"
bad_rc=0
bash "$checker" --project-dir "$fixture_bad" --strict >/dev/null || bad_rc=$?
assert "--strict should exit 1 on an unpinned binary version" \
  "$([ "$bad_rc" -eq 1 ] && echo true || echo false)"

good_out="$(bash "$checker" --project-dir "$fixture_good")"
assert "explicit version: tag, bare checkout, and off-list floating are all unflagged" \
  "$([ "$(contains "$good_out" "version_input")" = "false" ] && echo true || echo false)"
assert "good fixture STATUS should not be ERROR" \
  "$([ "$(field "$good_out" STATUS)" != "ERROR" ] && echo true || echo false)"
assert "explicit version: tag counts toward VERSION_INPUT_COVERED" \
  "$([ "$(field "$good_out" VERSION_INPUT_COVERED)" -ge 1 ] && echo true || echo false)"
good_rc=0
bash "$checker" --project-dir "$fixture_good" --strict >/dev/null || good_rc=$?
assert "--strict should exit 0 when both pins are present" \
  "$([ "$good_rc" -eq 0 ] && echo true || echo false)"

echo "=== TEST H: dist/ build output is pruned, not scanned (#2214) ==="
# dist/ is the GITIGNORED OpenCode export — a generated copy of the same skill
# tree. A finding there is unactionable by construction (the fix site is always
# the source skill, and the next `just export-opencode` overwrites it), and a
# stale local dist/ hard-ERRORs every local commit while CI — which never has a
# dist/ — stays green. Same class as TEST F's worktree prune (#1492): a walk
# descending into a copy of the repo.
before_scanned_h="$(field "$wt_out" FILES_SCANNED)"
before_errors_h="$(printf '%s\n' "$wt_out" | grep -c 'SEVERITY=ERROR' || true)"
mkdir -p "$fixture/dist/opencode/skills/demo"
cp "$fixture/demo-plugin/skills/demo/SKILL.md" \
   "$fixture/dist/opencode/skills/demo/SKILL.md"
dist_out="$(bash "$checker" --project-dir "$fixture")"
assert "FILES_SCANNED unchanged after adding a dist/ export copy" \
  "$([ "$(field "$dist_out" FILES_SCANNED)" -eq "$before_scanned_h" ] && echo true || echo false)"
assert "no extra ERROR from the dist/ copy's uncovered pin" \
  "$([ "$(printf '%s\n' "$dist_out" | grep -c 'SEVERITY=ERROR' || true)" -eq "$before_errors_h" ] && echo true || echo false)"
assert "no issue references a dist/ path" \
  "$([ "$(contains "$dist_out" 'dist/')" = "false" ] && echo true || echo false)"

# Guard integrity: without this half the three assertions above would ALSO pass
# with the whole check disabled. Plant one distinct defective pin at BOTH a real
# path and a dist/ path — the real one must still be flagged, exactly once.
mkdir -p "$fixture/real-plugin/skills/real"
cat > "$fixture/real-plugin/skills/real/SKILL.md" <<'EOF'
# Real source skill

```yaml
- uses: guard/integrity@7
```
EOF
mkdir -p "$fixture/dist/opencode/skills/real"
cp "$fixture/real-plugin/skills/real/SKILL.md" \
   "$fixture/dist/opencode/skills/real/SKILL.md"
guard_out="$(bash "$checker" --project-dir "$fixture")"
assert "the same defective pin at a REAL path is still flagged" \
  "$(contains "$guard_out" 'real-plugin/skills/real/SKILL.md')"
assert "the defective pin is reported exactly once (dist/ twin not counted)" \
  "$([ "$(printf '%s\n' "$guard_out" | grep -c 'guard/integrity' || true)" -eq 1 ] && echo true || echo false)"
assert "FILES_SCANNED grew by exactly 1 (only the real source file)" \
  "$([ "$(field "$guard_out" FILES_SCANNED)" -eq "$((before_scanned_h + 1))" ] && echo true || echo false)"
assert "still no issue references a dist/ path" \
  "$([ "$(contains "$guard_out" 'dist/')" = "false" ] && echo true || echo false)"

echo "=== TEST I: plugin scaffold template pins are path-checked (#2222) ==="
# A scaffold template ships REAL files a generated repo inherits verbatim, so the
# failure mode is the pin's PATH, not its shape: `uses: x@v6` is a perfectly good
# tag-form pin that silently never updates when no manager's file pattern matches
# the file it sits in. Renovate's built-in patterns are '(^|/)'-prefixed, so a
# template's own .github/workflows/ subtree and package.json are ALREADY covered
# — only a flat layout (blueprint-plugin/templates/*.workflow.yml) is not. The
# assertions below weight that distinction hardest, because a guard that flagged
# every pin under templates/ would be wrong in the common case.
tpl="$(mktemp -d)" || exit 1
[ -n "$tpl" ] || exit 1
trap 'rm -rf "$fixture" "$tpl"' EXIT

# renovate.json WITHOUT any templates pattern — the pre-fix state.
cat > "$tpl/renovate.json" <<'EOF'
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"]
}
EOF

# (a) the defect: a flat workflow template, matched by no manager pattern.
mkdir -p "$tpl/demo-plugin/templates"
cat > "$tpl/demo-plugin/templates/scaffold.workflow.yml" <<'EOF'
name: Scaffolded
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
EOF

# (b) the same template tree's OWN .github/workflows/ subtree — already covered
#     by the built-in github-actions patterns, so it must NOT be flagged.
mkdir -p "$tpl/demo-plugin/templates/demo-module/.github/workflows"
cat > "$tpl/demo-plugin/templates/demo-module/.github/workflows/ci.yml" <<'EOF'
name: CI
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
EOF

# (c) a template package.json — covered by the built-in npm pattern.
cat > "$tpl/demo-plugin/templates/demo-module/package.json" <<'EOF'
{
  "name": "{{ project-name }}",
  "devDependencies": { "typescript": "^5.7.0" }
}
EOF

# (d) a template whose only ref is floating — not a pin, so not a finding.
cat > "$tpl/demo-plugin/templates/floating.workflow.yml" <<'EOF'
name: Floating
jobs:
  call:
    uses: owner/repo/.github/workflows/reusable.yml@main
EOF

pre_out="$(bash "$checker" --project-dir "$tpl")"
pre_rc=0
bash "$checker" --project-dir "$tpl" --strict >/dev/null || pre_rc=$?

assert "flat scaffold.workflow.yml is flagged template_pin_unmanaged" \
  "$(contains "$pre_out" 'template_pin_unmanaged.*scaffold.workflow.yml')"
assert "--strict exits 1 on an unmanaged template pin" \
  "$([ "$pre_rc" -eq 1 ] && echo true || echo false)"
# Guard integrity: without these three, the assertion above would also pass
# against a check that simply errored on everything under a templates/ tree.
assert "the template's own .github/workflows/ci.yml is NOT flagged (built-in pattern)" \
  "$([ "$(contains "$pre_out" 'ci.yml')" = "false" ] && echo true || echo false)"
assert "the template's package.json is NOT flagged (built-in npm pattern)" \
  "$([ "$(contains "$pre_out" 'package.json')" = "false" ] && echo true || echo false)"
assert "a floating-only template is NOT flagged (no pin to manage)" \
  "$([ "$(contains "$pre_out" 'floating.workflow.yml')" = "false" ] && echo true || echo false)"
# Non-vacuity: the scan must have actually seen the covered files.
assert "TEMPLATE_FILES_SCANNED counts all 3 pin-bearing template files" \
  "$([ "$(field "$pre_out" TEMPLATE_FILES_SCANNED)" -eq 3 ] && echo true || echo false)"
assert "TEMPLATE_PINS_COVERED is non-zero (covered pins were counted, not skipped)" \
  "$([ "$(field "$pre_out" TEMPLATE_PINS_COVERED)" -gt 0 ] && echo true || echo false)"

# Adding the pattern to renovate.json clears the finding — proving the guard
# reads the CONFIG rather than carrying a hardcoded verdict about the path.
cat > "$tpl/renovate.json" <<'EOF'
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "github-actions": {
    "managerFilePatterns": ["/(^|/)[^/]+-plugin/templates/.+\\.ya?ml$/"]
  }
}
EOF
post_out="$(bash "$checker" --project-dir "$tpl")"
post_rc=0
bash "$checker" --project-dir "$tpl" --strict >/dev/null || post_rc=$?
assert "the finding clears once renovate.json covers the path" \
  "$([ "$(contains "$post_out" 'template_pin_unmanaged')" = "false" ] && echo true || echo false)"
assert "--strict exits 0 once the path is covered" \
  "$([ "$post_rc" -eq 0 ] && echo true || echo false)"
assert "the newly-covered pin is counted, not merely un-flagged" \
  "$([ "$(field "$post_out" TEMPLATE_PINS_COVERED)" -gt "$(field "$pre_out" TEMPLATE_PINS_COVERED)" ] && echo true || echo false)"

echo "=== TEST J: the TRIGGERS reach every surface the guard scans (#2285) ==="
# The guard body is whole-repo (`pass_filenames: false`), so TESTS A-I would all
# pass while the check never RAN on the shape it exists for. This block asserts
# the two trigger surfaces select a template-only / renovate.json-only change:
#   J1  the pre-commit `files:` regex, evaluated with pre-commit's OWN matcher
#   J2  the workflow's `if:`, evaluated against outputs produced by EXECUTING
#       the workflow's own `changed` step against real git diffs
# Both are read out of the config files rather than restated here, so a config
# that stops selecting these paths fails regardless of how it is spelled.

# The git ops below build throwaway repos. Neutralize any inherited git context
# so `git -C "$sandbox"` cannot be hijacked into the shared checkout (#1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

trigger_root="$(mktemp -d)"
[ -n "$trigger_root" ] || { echo "FAIL: mktemp -d returned empty" >&2; exit 1; }
trap 'rm -rf "$fixture" "$fixture_bad" "$fixture_good" "$tpl" "$trigger_root"' EXIT

# --- J1: pre-commit `files:` regex ------------------------------------------
# pre-commit matches with `re.search` against repo-relative paths. Where the
# pre_commit package is importable we use its own filter function, so the test
# tracks the real semantics instead of an assumption about them.
precommit_match() {
  # precommit_match <candidate-path> [hook-id]
  python3 - "$repo_root/.pre-commit-config.yaml" "$1" "${2:-check-version-pin-coverage}" <<'PY'
import re, sys, yaml
cfg_path, candidate, hook_id = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = yaml.safe_load(open(cfg_path))
pats = [h for r in cfg["repos"] for h in r.get("hooks") or []
        if h.get("id") == hook_id]
if len(pats) != 1:
    print("ERROR: expected exactly 1 %s hook, found %d" % (hook_id, len(pats)))
    raise SystemExit(0)
include = pats[0].get("files", "")
exclude = pats[0].get("exclude") or cfg.get("exclude") or "^$"
try:
    from pre_commit.commands.run import filter_by_include_exclude as filt
    hit = bool(list(filt([candidate], include, exclude)))
except Exception:
    hit = bool(re.search(include, candidate)) and not re.search(exclude, candidate)
print("true" if hit else "false")
PY
}

assert "pre-commit selects a flat plugin scaffold template" \
  "$(precommit_match 'blueprint-plugin/templates/x.workflow.yml')"
assert "pre-commit selects a nested plugin scaffold template" \
  "$(precommit_match 'foundryvtt-plugin/templates/mod/.github/workflows/ci.yml')"
# The guard scans EVERY non-.md file under a plugin's templates/ tree, not just
# YAML — so the trigger must too. Without these two rows the regex could be
# narrowed to `-plugin/templates/.*\.ya?ml` (or any `\.<ext>$` form) and every
# other assertion here would still pass, while a real pin at a non-YAML
# extension went silently un-triggered. `package.json` is a real repo file the
# guard already reads pins out of; `Dockerfile` has no extension at all, so an
# extension-anchored narrowing cannot slip past it either.
assert "pre-commit selects a non-YAML plugin scaffold template (package.json)" \
  "$(precommit_match 'foundryvtt-plugin/templates/foundryvtt-module/package.json')"
assert "pre-commit selects an extensionless plugin scaffold template (Dockerfile)" \
  "$(precommit_match 'demo-plugin/templates/Dockerfile')"
assert "pre-commit selects the root renovate.json (its patterns are the verdict)" \
  "$(precommit_match 'renovate.json')"
# Guard integrity: without these the regex could be widened to `.` and pass.
assert "pre-commit still selects skill markdown (today's behaviour preserved)" \
  "$(precommit_match 'some-plugin/skills/foo/SKILL.md')"
assert "pre-commit ignores an unrelated markdown file" \
  "$([ "$(precommit_match 'docs/notes.md')" = "false" ] && echo true || echo false)"
assert "pre-commit ignores a nested renovate.json (not the root config)" \
  "$([ "$(precommit_match 'vendor/renovate.json')" = "false" ] && echo true || echo false)"

# --- J2: the workflow step's `if:` ------------------------------------------
wf="$repo_root/.github/workflows/plugin-pr-checks.yml"
meta="$trigger_root/meta"
mkdir -p "$meta"

# Extract the `changed` step's run block (+ env) and the version-pin step's
# `if:` expression. Any unresolved `${{ }}` in the run block is a hard failure:
# the executed copy must be the real script, not a partially-substituted one.
extract_rc=0
python3 - "$wf" "$meta" <<'PY' || extract_rc=$?
import re, shlex, sys, yaml
wf_path, out_dir = sys.argv[1], sys.argv[2]
wf = yaml.safe_load(open(wf_path))
steps = wf["jobs"]["compliance"]["steps"]
changed = [s for s in steps if s.get("id") == "changed"]
pin = [s for s in steps if "scripts/check-version-pin-coverage.sh" in (s.get("run") or "")]
if len(changed) != 1:
    sys.exit("expected exactly 1 step with id 'changed', found %d" % len(changed))
if len(pin) != 1:
    sys.exit("expected exactly 1 step running scripts/check-version-pin-coverage.sh, found %d" % len(pin))
run = changed[0]["run"]
env = {k: str(v) for k, v in (changed[0].get("env") or {}).items()}
subst = {"${{ github.base_ref }}": "main"}
for needle, value in subst.items():
    run = run.replace(needle, value)
    env = {k: v.replace(needle, value) for k, v in env.items()}
if "${{" in run:
    sys.exit("unresolved ${{ }} interpolation in the changed step's run block:\n" + run)
open(out_dir + "/changed.sh", "w").write(run)
with open(out_dir + "/env.sh", "w") as fh:
    fh.write("export BASE_REF=main\n")  # default when the step carries no env
    for k, v in env.items():
        fh.write("export %s=%s\n" % (k, shlex.quote(v)))
open(out_dir + "/if.txt", "w").write(pin[0].get("if", ""))
PY
assert "workflow parses: one 'changed' step and one version-pin step" \
  "$([ "$extract_rc" -eq 0 ] && echo true || echo false)"

# Evaluate the extracted `if:` against a GITHUB_OUTPUT file. Every referenced
# output must also be one the `changed` step actually SET — an `if:` keyed on a
# typo'd output name is silently always-false, which is this bug wearing a hat.
eval_if() {
  python3 - "$meta/if.txt" "$1" <<'PY'
import re, sys
expr = open(sys.argv[1]).read().strip()
raw = open(sys.argv[2]).read().split("\n")
outputs, i = {}, 0
while i < len(raw):
    line = raw[i]
    if not line:
        i += 1
        continue
    m = re.match(r"^([A-Za-z0-9_-]+)<<(.+)$", line)
    if m:
        key, delim, i, buf = m.group(1), m.group(2), i + 1, []
        while i < len(raw) and raw[i] != delim:
            buf.append(raw[i]); i += 1
        outputs[key] = "\n".join(buf); i += 1
    else:
        k, _, v = line.partition("=")
        outputs[k] = v; i += 1
missing = []

def split_top(text, op):
    parts, depth, buf, i = [], 0, "", 0
    while i < len(text):
        c = text[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        if depth == 0 and text[i:i + len(op)] == op:
            parts.append(buf); buf = ""; i += len(op); continue
        buf += c; i += 1
    parts.append(buf)
    return parts

def operand(tok):
    tok = tok.strip()
    if len(tok) >= 2 and tok[0] == tok[-1] == "'":
        return tok[1:-1]
    m = re.match(r"^steps\.changed\.outputs\.([A-Za-z0-9_-]+)$", tok)
    if m:
        if m.group(1) not in outputs:
            missing.append(m.group(1))
        return outputs.get(m.group(1), "")
    raise SystemExit("UNSUPPORTED_OPERAND=%s" % tok)

def balanced(text):
    depth = 0
    for c in text:
        depth += (c == "(") - (c == ")")
        if depth < 0:
            return False
    return depth == 0

def ev(text):
    text = text.strip()
    while text.startswith("(") and text.endswith(")") and balanced(text[1:-1]):
        text = text[1:-1].strip()
    for op, fold in (("||", any), ("&&", all)):
        parts = split_top(text, op)
        if len(parts) > 1:
            return fold([ev(p) for p in parts])
    m = re.match(r"^(.+?)\s*(!=|==)\s*(.+)$", text)
    if not m:
        raise SystemExit("UNSUPPORTED_EXPRESSION=%s" % text)
    left, op, right = operand(m.group(1)), m.group(2), operand(m.group(3))
    return (left != right) if op == "!=" else (left == right)

verdict = ev(expr)
print("MISSING=%s" % ",".join(missing))
print("RESULT=%s" % ("true" if verdict else "false"))
PY
}

# Build a throwaway repo whose only change vs origin/main is $1 (a path), then
# run the workflow's own `changed` step against it and evaluate the `if:`.
trigger_verdict() {
  local scenario="$1" changed_path="$2" repo out
  [ -n "$trigger_root" ] || return 1
  repo="$trigger_root/$scenario"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main >/dev/null 2>&1 || return 1
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Trigger Test"
  mkdir -p "$repo/demo-plugin/templates"
  printf 'seed\n' > "$repo/README.md"
  printf '{\n  "extends": ["config:recommended"]\n}\n' > "$repo/renovate.json"
  git -C "$repo" add -A >/dev/null 2>&1
  git -C "$repo" commit -qm "base" >/dev/null 2>&1 || return 1
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  git -C "$repo" checkout -q -b pr
  mkdir -p "$repo/$(dirname "$changed_path")"
  case "$changed_path" in
    *.workflow.yml)
      printf 'name: Scaffolded\njobs:\n  build:\n    steps:\n      - uses: actions/checkout@v6\n' \
        > "$repo/$changed_path" ;;
    *.toml)
      # A pin at a NON-YAML template extension — the same acceptance shape as
      # the .workflow.yml case above, which the guard flags identically.
      printf '[services.db]\nimage: postgres:16\n' > "$repo/$changed_path" ;;
    *SKILL.md)
      cat > "$repo/$changed_path" <<'MD'
# Demo

Managed tag form:

~~~yaml
- uses: actions/checkout@v5
~~~
MD
      ;;
    *)
      printf 'changed\n' >> "$repo/$changed_path" ;;
  esac
  git -C "$repo" add -A >/dev/null 2>&1
  git -C "$repo" commit -qm "change" >/dev/null 2>&1 || return 1
  out="$repo/.github_output"
  : > "$out"
  # `bash -e` mirrors GitHub's default shell for a `run:` block with no `shell:`.
  # shellcheck source=/dev/null
  ( cd "$repo" && . "$meta/env.sh" && GITHUB_OUTPUT="$out" bash -e "$meta/changed.sh" ) >/dev/null 2>&1
  eval_if "$out"
}

tpl_verdict="$(trigger_verdict template-only demo-plugin/templates/x.workflow.yml)"
assert "template-only change: the version-pin step's if: is TRUE" \
  "$(contains "$tpl_verdict" 'RESULT=true')"
assert "template-only change: the if: references only outputs the step sets" \
  "$(contains "$tpl_verdict" 'MISSING=$')"

# Same hole as J1's, on the CI side: the step's diff pathspec must reach every
# non-.md file under templates/, not just YAML. Narrowing it to
# `'*-plugin/templates/**.yml'` leaves template_count=0 for this change, the
# `if:` evaluates FALSE, and the guard never runs in CI — while the .yml
# scenario above still passes.
tpl_nonyaml_verdict="$(trigger_verdict template-nonyaml demo-plugin/templates/stack.toml)"
assert "non-YAML template-only change: the version-pin step's if: is TRUE" \
  "$(contains "$tpl_nonyaml_verdict" 'RESULT=true')"

rnv_verdict="$(trigger_verdict renovate-only renovate.json)"
assert "renovate.json-only change: the version-pin step's if: is TRUE" \
  "$(contains "$rnv_verdict" 'RESULT=true')"

# Guard integrity #1: today's behaviour must survive the widening.
skill_verdict="$(trigger_verdict skill-only demo-plugin/skills/demo/SKILL.md)"
assert "skill-markdown-only change: the if: is still TRUE (unchanged behaviour)" \
  "$(contains "$skill_verdict" 'RESULT=true')"

# Guard integrity #2: without this, dropping the `if:` entirely would pass every
# assertion above while removing the gating the workflow header argues for.
other_verdict="$(trigger_verdict unrelated-only README.md)"
assert "unrelated-file-only change: the if: is FALSE (the guard is still gated)" \
  "$(contains "$other_verdict" 'RESULT=false')"

# End-to-end: the acceptance shape must fail the GUARD too, not just be selected
# by the trigger — a template pin with no renovate.json pattern covering it.
tpl_repo_rc=0
bash "$checker" --project-dir "$trigger_root/template-only" --strict >/dev/null 2>&1 || tpl_repo_rc=$?
assert "the selected template-only tree also FAILS --strict (trigger + guard)" \
  "$([ "$tpl_repo_rc" -eq 1 ] && echo true || echo false)"

# ...and the same end-to-end at a NON-YAML extension, so the pairing of a
# reaching trigger with a firing guard is proven for the whole scanned surface
# rather than only for *.yml.
tpl_nonyaml_out="$(bash "$checker" --project-dir "$trigger_root/template-nonyaml" 2>/dev/null)"
tpl_nonyaml_rc=0
bash "$checker" --project-dir "$trigger_root/template-nonyaml" --strict >/dev/null 2>&1 || tpl_nonyaml_rc=$?
assert "the selected non-YAML template tree also FAILS --strict (trigger + guard)" \
  "$([ "$tpl_nonyaml_rc" -eq 1 ] && echo true || echo false)"
assert "the non-YAML template finding is the template_pin_unmanaged shape" \
  "$(contains "$tpl_nonyaml_out" 'template_pin_unmanaged')"

# --- J3: THIS test's own trigger reaches the files it asserts on -------------
# J1/J2 assert on `.pre-commit-config.yaml` and the workflow, but neither is a
# `scripts/` path — so this hook's own `files:` regex has to name them, or
# editing a trigger locally never re-runs the test that guards it (the
# allowlist-drift shape in .claude/rules/regression-testing.md).
assert "this test's trigger reaches .pre-commit-config.yaml (it asserts on it)" \
  "$(precommit_match '.pre-commit-config.yaml' test-check-version-pin-coverage)"
assert "this test's trigger reaches the workflow it asserts on" \
  "$(precommit_match '.github/workflows/plugin-pr-checks.yml' test-check-version-pin-coverage)"
# Guard integrity: the widened regex must keep its original members and must
# not become a catch-all.
assert "this test's trigger still reaches the checker it exercises" \
  "$(precommit_match 'scripts/check-version-pin-coverage.sh' test-check-version-pin-coverage)"
assert "this test's trigger still reaches the test file itself" \
  "$(precommit_match 'scripts/tests/test-check-version-pin-coverage.sh' test-check-version-pin-coverage)"
assert "this test's trigger ignores an unrelated workflow" \
  "$([ "$(precommit_match '.github/workflows/stranded-work-audit.yml' test-check-version-pin-coverage)" = "false" ] && echo true || echo false)"
assert "this test's trigger ignores an unrelated script" \
  "$([ "$(precommit_match 'scripts/check-docs-index.sh' test-check-version-pin-coverage)" = "false" ] && echo true || echo false)"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then echo "STATUS=FAIL"; exit 1; fi
echo "STATUS=OK"

---
description: Automated TDD test-fix-refactor cycle until tests pass. Use when looping on failing tests, running a TDD cycle, or driving RED/GREEN/REFACTOR until green.
args: "[test-pattern] [--max-cycles <N>]"
argument-hint: "Optional test pattern to focus on; --max-cycles <N> to cap iterations (default 10)"
allowed-tools: Read, Edit, Bash, Bash(bash *)
created: 2025-12-16
modified: 2026-07-04
reviewed: 2026-07-04
name: project-test-loop
---

# /project:test-loop

## When to Use This Skill

| Use this skill when... | Use project-continue instead when... |
|---|---|
| Driving a RED -> GREEN -> REFACTOR loop until tests pass | Resuming general project work where tests are not the bottleneck |
| Iterating on failing tests with auto fix-and-retry behavior | Use project-distill instead when capturing patterns from a finished session |
| Bounding TDD iterations with `--max-cycles` to avoid runaway loops | Use project-discovery instead when the test command itself is unknown |

Run an automated TDD cycle — test -> fix -> refactor — where a deterministic
driver script (`scripts/run-test-cycle.sh`) does the mechanical work each
iteration and you make the minimal fix between invocations.

## Context

- Project markers: !`find . -maxdepth 1 \( -name package.json -o -name pyproject.toml -o -name pytest.ini -o -name Cargo.toml -o -name go.mod -o -name Makefile \) -print`

## Parameters

Parse these from `$ARGUMENTS`:

- **`test-pattern`** (positional, optional) — a pattern passed through to the
  detected test command to focus the run (e.g. a file, a test-name filter).
- **`--max-cycles <N>`** (optional, default `10`) — the runaway ceiling; the
  driver returns `CAP_REACHED` once the cycle count reaches `N`.

Also pass `--test-cmd "<command>"` to the driver to override auto-detection when
the project's test command is configured in `CLAUDE.md` / `.claude/rules/` and
not one of the auto-detected shapes.

## Execution

Execute this TDD loop. Each iteration runs the deterministic driver, then you act
on its `VERDICT`.

### Step 1: Run one test cycle

Invoke the driver (auto-detects the test command from the project markers above:
`package.json` test script, `pytest`/`pyproject.toml`, `cargo test`, `go test`,
or a `Makefile` `test:` target):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/run-test-cycle.sh" --pattern "$0" --max-cycles 10
```

Substitute the parsed `test-pattern` for `--pattern` (omit it if none) and the
parsed `--max-cycles` value. Read the `VERDICT=` line from the structured output
and the bounded `=== TEST OUTPUT ===` tail.

### Step 2: Branch on the verdict

| `VERDICT` | Meaning | Do |
|---|---|---|
| `GREEN` | Test command exited 0 — suite passes | Go to Step 3 (refactor), then stop |
| `CONTINUE` | Suite failing, ceiling not reached | Make a minimal fix (Step 2a), then repeat Step 1 |
| `STUCK` | Same failing signature 3 cycles running — no progress | Stop; report the blocker and ask for input |
| `CAP_REACHED` | Cycle count hit `--max-cycles` | Stop; report remaining failures |
| `SETUP_ERROR` | No test command could be detected/run | Stop; ask how to run tests, or re-invoke with `--test-cmd` |

### Step 2a: Make the minimal fix (on `CONTINUE`)

Read the `=== TEST OUTPUT ===` tail and identify the failure:

1. Which tests failed, expected vs actual.
2. Root cause: missing implementation, wrong return value, missing edge case,
   integration issue.
3. Apply the **minimal** fix to the code — fix only what the failing test needs.
   Do **not** edit the tests to make them pass; that converts the suite's
   independent judge into a self-judged loop (see Loop integrity below).

Then repeat Step 1. The driver increments the cycle counter and re-checks.

### Step 3: Refactor while green (on `GREEN`)

With the suite passing, look for improvements — duplicated code, magic numbers,
long functions, unclear names, complex conditionals — and refactor **without
changing behavior**. Re-run Step 1 after each refactoring to confirm the suite
stays green. When no improvement remains, report success and stop.

### Step 4: Report

Summarize cycles run, fixes applied, refactorings performed, and the final
status (all green / blocked with reason + recommended next step).

## Loop integrity

This loop's stop condition is the test suite itself — an **independent**,
mechanical judge (a failing test does not care how hard you worked), which is
exactly what `.claude/rules/loop-integrity.md` Pillar 1 asks for. The driver
script makes that judge deterministic: `GREEN` is the suite's own exit 0, not
your opinion. The `--max-cycles` ceiling (`CAP_REACHED`) and the same-failure-3x
rule (`STUCK`) are the runaway bound. Do **not** make tests pass by editing the
tests — that converts the independent judge into a self-judged loop.

## Common failure patterns

| Symptom | Fix (minimal) |
|---|---|
| `undefined is not a function`, `NameError` | Implement the missing function/class; just the signature + a dummy return |
| `Expected X but got Y` | Correct the return value only — no extra logic |
| Fails for a specific input | Handle that edge case with a single condition |
| Fails when components interact | Fix the integration point, not the whole component |

## Auto-stop conditions

Stop and report if: all tests pass with no refactoring left (SUCCESS, `GREEN`);
`STUCK` (same failure 3× — the driver's no-progress signal); `CAP_REACHED`
(`--max-cycles`); `SETUP_ERROR` (test command itself broken / undetectable); or
the fix is unclear (NEEDS USER INPUT).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| One cycle, auto-detect | `bash "${CLAUDE_SKILL_DIR}/scripts/run-test-cycle.sh" --max-cycles 10` |
| Focus a pattern | `bash "${CLAUDE_SKILL_DIR}/scripts/run-test-cycle.sh" --pattern "$0"` |
| Override the test command | `bash "${CLAUDE_SKILL_DIR}/scripts/run-test-cycle.sh" --test-cmd "pytest -x -q"` |
| Start a fresh loop (reset cycle state) | `bash "${CLAUDE_SKILL_DIR}/scripts/run-test-cycle.sh" --reset` |
| Read the verdict | `bash "${CLAUDE_SKILL_DIR}/scripts/run-test-cycle.sh" --max-cycles 10 \| grep -E '^VERDICT='` |

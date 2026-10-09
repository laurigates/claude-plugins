# Evaluation Data Schemas

JSON schemas for all data structures used in the evaluation workflow.

## evals.json — Evaluation Test Cases

Defines test cases for a skill. Lives alongside the SKILL.md it tests. **Version-controlled.**

```json
{
  "skill_name": "string — skill identifier (kebab-case)",
  "skill_path": "string — relative path to SKILL.md",
  "evals": [
    {
      "id": "string — unique eval identifier (e.g., eval-001)",
      "description": "string — what this test validates",
      "prompt": "string — the user prompt to simulate",
      "expected_outcome": "string — comply (default) | abstain; see Abstention Controls",
      "expectations": [
        "string — assertion that the output should satisfy"
      ],
      "context_files": [
        "string — optional files to make available during evaluation"
      ],
      "fixture": {
        "dir": "string — optional fixture template dir (relative to the repository root) copied into the temp workdir",
        "setup": ["string — shell commands run in the temp workdir after the copy"],
        "teardown": ["string — optional commands run before the temp dir is discarded"],
        "workdir": "string — optional; where the eval subagent runs (default: the temp dir)"
      },
      "tags": [
        "string — categorization tags for filtering"
      ]
    }
  ],
  "triggers": "object — optional; does description routing pick this skill? See Trigger Evals"
}
```

### Field Details

| Field | Required | Description |
|-------|----------|-------------|
| `skill_name` | Yes | Matches the `name` field in SKILL.md frontmatter |
| `skill_path` | Yes | Relative path from repository root |
| `evals[].id` | Yes | Unique within the file, used in result directories |
| `evals[].description` | Yes | Human-readable description of what's being tested |
| `evals[].prompt` | Yes | The simulated user request |
| `evals[].expected_outcome` | No | `comply` (default) or `abstain`. An `abstain` case is an impossible-task control whose passing response is a correct refusal — see [Abstention Controls](#abstention-controls-impossible-tasks). Every suite carries at least one (`scripts/check-evals-abstention.sh`) |
| `evals[].expectations` | Yes | List of assertion strings (grader checks these) |
| `evals[].context_files` | No | Files to include in evaluation context |
| `evals[].fixture` | No | Opt-in execution scaffold (see below). Evals without it run unchanged |
| `evals[].tags` | No | Tags for filtering (e.g., `basic`, `edge-case`) |
| `triggers` | No | Routing evals: prompts that should and should not invoke the skill — see [Trigger Evals](#trigger-evals-triggers-block) |

### Fixtures (opt-in execution scaffold)

A context-needing skill cannot honestly execute in eval without a real
workdir — without one it fails on a weak model purely for lack of fixtures, a
false negative that poisons the executability gate (`/evaluate:matrix`). The
optional `fixture` block gives such an eval an isolated, throwaway workdir.

`fixture` is **additive and back-compatible**: evals without it run exactly as
today, and `grade_deterministic.py` is unaffected (it reads only
`expectations`; a headless rollout's workspace checks grade the snapshot
`rollout_headless.sh` takes of the fixture workdir). `scripts/apply_fixture.sh` applies it — `mktemp -d` a workdir
**outside the repo**, copy `dir`, run `setup`, emit `WORKDIR=`; teardown runs
`teardown` then `rm -rf`s the dir (refusing any path outside the temp root,
since `setup` is arbitrary shell — see `.claude/rules/sandbox-guidance.md`).
`dir` is resolved against the repository root (`--repo-root`, default the
current directory), not against the `evals.json`. Only an absent value, `null`
or `{}` means "no fixture"; a fixture whose JSON does not parse, or that is not
an object, is `STATUS=ERROR` with exit 1 in both modes, so a mis-quoted
`--fixture` cannot silently run the eval without its workdir (#2915). Scope
`fixture` blocks to the golden-set canaries (`golden-set.json`).

| Field | Required | Description |
|-------|----------|-------------|
| `fixture.dir` | No | Template dir (relative to the repository root) copied into the workdir |
| `fixture.setup` | No | Shell commands run in the workdir after the copy |
| `fixture.teardown` | No | Commands run before the workdir is discarded (dir removed by default) |
| `fixture.workdir` | No | Where the eval subagent runs (default: the temp dir) |

Worked example — `git-commit`'s gc-001 in a real staged repo:

```json
{
  "id": "gc-001",
  "prompt": "I just added a new OAuth login feature to the auth module. Please commit my staged changes.",
  "fixture": {
    "setup": ["git init -q", "printf 'oauth code' > auth.py", "git add auth.py"]
  },
  "expectations": [
    { "assertion": "Commit message starts with feat(", "check": "regex", "pattern": "^feat\\(", "scope": "subject" }
  ]
}
```

The subagent runs `git-commit` in the staged-repo `WORKDIR`; the produced
commit message is graded exactly as before.

### Writing Good Assertions

| Assertion Quality | Example |
|-------------------|---------|
| Too vague | "Output is correct" |
| Too specific | "Output contains exactly 'feat(auth): add OAuth2'" |
| Good | "Commit message starts with feat(" |
| Good | "Output includes issue reference #42" |
| Good | "Created file contains at least 3 test cases" |

### Typed Checks (deterministic grading)

Each item in `expectations` is **either** a plain string (graded by the LLM
`eval-grader` — the `judge` path) **or** a typed object that
`scripts/grade_deterministic.py` grades with zero model tokens. Mixing both in
one `expectations` array is supported and backward compatible.

```json
{
  "assertion": "string — human-readable assertion (also shown to the judge)",
  "check": "one of the 13 types below; default judge",
  "pattern": "string — regex (for regex / absent_regex)",
  "value": "string — substring to find (for substring)",
  "values": ["string — all must be present (for substring_all)"],
  "scope": "full | subject | body  — default full",
  "flags": "string — any of imsx, regex flags (for every pattern-bearing check)"
}
```

Output checks grade the transcript text:

| `check` | Passes when | Required field |
|---------|-------------|----------------|
| `regex` | `pattern` matches within `scope` | `pattern` |
| `substring` | `value` appears within `scope` | `value` |
| `substring_all` | every entry in `values` appears within `scope` | `values` |
| `absent_regex` | `pattern` does **not** match within `scope` | `pattern` |
| `judge` | deferred to the LLM grader (default for bare strings) | — |

Trace checks grade `trace.json` (`--trace`, a headless rollout's
[trace](#tracejson--headless-rollout-trace)), never the raw stream:

| `check` | Passes when | Fields |
|---------|-------------|--------|
| `skill_triggered` | `skills_invoked[]` names `skill` by full (`plugin:skill`) or bare name, or does not when `expect: false`. A **denied** invocation still counts: routing chose it | `skill`, `expect` (default `true`) |
| `tool_called` | the count of `tool_calls[]` named `tool` (whose input matches `pattern`, when given) is within `min..max`. Denied calls count: they were attempted | `tool`, `pattern?`, `flags?`, `min` (default 1), `max?` |
| `command_ran` | the count of `bash_commands[]` matching `pattern` is within `min..max`. Denied commands did not run and do not count. `max: 0` alone means "never ran" | `pattern`, `flags?`, `min` (default 1), `max?` |

Workspace checks grade the rollout's snapshot of its working directory
(`--workspace`, `RUN_DIR/workspace/`):

| `check` | Passes when | Fields |
|---------|-------------|--------|
| `file_exists` | `path` exists (or not, with `expect: false`) | `path`, `expect` (default `true`) |
| `file_regex` | `pattern` matches the file; a **missing file fails** | `path`, `pattern`, `flags?` |
| `file_absent_regex` | `pattern` does not match; a **missing file passes** | `path`, `pattern`, `flags?` |
| `json_path` | `query` (dotted keys plus `[int]`, e.g. `items[0].id`) satisfies exactly one comparator; a missing file or invalid JSON fails | `path`, `query`, one of `equals` / `regex` / `exists` |
| `run_command` | `bash -c command` exits `expect_exit` (default 0) and stdout matches `stdout_regex` when given | `command`, `expect_exit?`, `stdout_regex?`, `flags?`, `timeout` (default 30, cap 120) |

Workspace `path` values must be relative, and the resolved path — symlinks
included — must stay inside the workspace; a path that escapes **fails**.
`run_command` runs in a fresh temp copy of the snapshot (never the snapshot
itself), with a minimal environment (fixed `PATH`, temp `HOME`, no inherited
secrets, git never discovering a repo above the copy) and its process group
killed when it returns or times out. The snapshot is agent-written, so before
the command runs: a FIFO, socket or device node, or more than 256 MB of
apparent size, **fails** the check (`workspace error`); a symlink, `.git`
gitfile, `commondir` or `objects/info/alternates` entry that leaves the copy
**fails** it (`path escape`); and every copied git dir's config is cut to format
keys (`core.repositoryformatversion`/`bare`/`filemode`/..., `extensions.*`), with
`hooks/`, `info/attributes` and `config.worktree` removed, so a planted
`filter.*.clean`, `core.fsmonitor` or hook cannot run in the grader. The timeout
bounds copy plus run. It runs only under `--allow-exec`; it isolates the
snapshot, the env and git config but is not an OS sandbox -- the command itself
comes from `evals.json`, so grade only `evals.json` files you trust.

**Harness-deferred.** A trace or workspace check whose input was not supplied
(no `--trace` / `--workspace`, or `run_command` without `--allow-exec`) is
reported `RESULT=HARNESS_DEFERRED` with evidence starting "requires headless
harness" (`(no trace.json)`, `(no workspace snapshot)` or `with --allow-exec`). It is excluded from `DETERMINISTIC_TOTAL` and from `JUDGE_PENDING`,
and is **never** handed to the judge — so a subagent-harness run of a case with
trace/workspace checks never false-fails. A non-zero `HARNESS_DEFERRED=` turns
an otherwise-OK grade into `STATUS=WARN`, so a run that graded nothing cannot
read as clean.

**Malformed checks** — an unknown regex flag, a pattern that does not compile, a
bad `json_path` query, two comparators, `min > max`, a missing or mistyped field
— grade `passed: false` with evidence `malformed check: …` instead of crashing
the grader. `check_golden_set_evals.py` rejects the same shapes at validation
time.

`scope`: `subject` = first non-empty line, `body` = text after the first blank
line, `full` = whole output. Every scope first drops the `\n\n---\n## Tool calls`
appendix that `rollout_headless.sh` adds to `transcript.md`: an output check
grades what the agent **said**; what it ran is the trace checks' job. Prefer typed checks for anything mechanically
verifiable; reserve `judge` for genuinely fuzzy expectations (tone, mood,
"provides context"). See
[`docs/cross-model-evaluation.md`](../docs/cross-model-evaluation.md).

### Abstention Controls (impossible tasks)

Every assertion shape above is positive — something must appear or match — and
the LLM judge passes an assertion only on evidence of satisfaction. A case whose
honest answer is "this cannot be done" therefore has nothing to pass, and a
fabricated answer has nothing to fail, so a suite of satisfiable cases cannot
tell a skill that invents output under pressure from one that refuses honestly
(issue #2690).

An **abstention control** is a case marked `"expected_outcome": "abstain"` whose
honest answer is a refusal. Author it so the refusal can pass and a fabrication
cannot:

| Assertion | Shape | Why |
|-----------|-------|-----|
| Fabrication detector | `absent_regex` on the deliverable the task would produce | Fails an invented answer for zero judge tokens. **Required**: `scripts/check-evals-abstention.sh` rejects an abstain case without one |
| Refusal marker | `regex` on the words an honest refusal uses | Gives the refusal something to pass. Keep those words out of the prompt, so a transcript that echoes the prompt cannot satisfy it |
| Judge (optional) | Bare string describing the refusal | Graded under the abstention rule in `agents/eval-grader.md` |

Give an abstain case no positive assertion on the deliverable (a `regex`
requiring a commit subject): no honest response can satisfy it. State the
evidence of impossibility in the prompt, so the case is decidable whether or not
a `fixture` makes it true.

Worked example — `git-commit`'s gc-006, where nothing is staged:

```json
{
  "id": "gc-006",
  "expected_outcome": "abstain",
  "prompt": "Please commit my staged changes ... I have not run git add since my last commit, and git status shows no modified or untracked files.",
  "expectations": [
    { "assertion": "Does not invent a conventional commit subject", "check": "absent_regex", "pattern": "^\\s*[`>]*\\s*(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\\([^)]*\\))?!?:\\s", "flags": "m" },
    { "assertion": "States that there is nothing staged to commit", "check": "regex", "pattern": "(nothing (is |has been )?(staged|to commit)|no (staged )?changes|working tree (is )?clean)", "flags": "i" },
    "Acknowledges that the commit cannot be made and does not claim a commit was created"
  ]
}
```

`grade_deterministic.py` reports the value as `EXPECTED_OUTCOME=` (and as
`expected_outcome` under `--json`) and exits 2 on any value other than `comply`
or `abstain`, so a misspelling cannot silently grade an abstain case as comply.

On the headless harness an abstain case can also assert what the agent did
**not** do: gc-006 carries `{"check": "command_ran", "pattern": "…commit…",
"max": 0}`, so an agent that says "nothing to commit" but ran `git commit`
anyway fails on the trace, which no transcript check can see.

### Trigger Evals (`triggers` block)

Whether description routing picks the skill at all. `scripts/run_trigger_evals.py`
runs each prompt through `rollout_headless.sh --tools Skill --allowed-tools Skill
--permission default --stop-on-skill` in an empty temp workdir, with the skill's own plugin plus
every `peers` plugin loaded; the child is killed at its first `Skill` call.

```json
"triggers": {
  "skill": "git-plugin:git-commit",
  "should_trigger": [{ "id": "gct-001", "prompt": "Commit my staged changes with a good commit message." }],
  "should_not_trigger": [
    { "id": "gcn-001", "prompt": "Suggest a conventional-commits title for my pull request …", "near_miss_of": "git-plugin:github-pr-title" }
  ],
  "peers": ["project-plugin"],
  "max_turns": 2
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `skill` | Yes | `<plugin>:<skill>`; the plugin must be the owning `plugin.json` name, the skill the dir or SKILL.md `name` |
| `should_trigger[]` / `should_not_trigger[]` | At least one prompt | `{id, prompt}`; ids unique and never an `evals[].id` |
| `should_not_trigger[].near_miss_of` | No | The neighbouring skill the prompt really belongs to (informational, reported per row). Only on `should_not_trigger` |
| `peers` | No | Extra plugin dirs, relative to the marketplace root (no `..`), to load as competing skills. The skill's own plugin is always loaded |
| `max_turns` | No | Positive integer passed as `--max-turns` |

The child also sees the CLI's built-in plugins and skills (clean env mode does not
remove them), so the target competes with those too, not only with `peers`.

The child's `Skill` listing is subject to the CLI's character budget
(`SLASH_COMMAND_TOOL_CHAR_BUDGET`, scaled to the context window when unset). A
plugin with many skills can have its descriptions elided to bare names: on
2026-10-05 (claude 2.1.289, haiku) git-plugin's 48 skills reached the child as
names only, `git-commit`'s "Use when user says commit" trigger among them, and
the eval measured name-only routing. Every rollout therefore sets the budget to
`--skill-listing-budget` (default `$EVAL_SKILL_LISTING_BUDGET` or 100000
characters), so evals measure **description** routing. `--skill-listing-budget
cli` keeps the CLI default (and strips an inherited value) to measure what an
installed user with the same catalogue gets. `run_trigger_evals.py` forwards
the flag and records it as `skill_listing_budget` (null = rollout default).

`--tools Skill` matters as much: `--allowed-tools` only auto-approves, so with
Bash still available haiku ran `git status` in the empty workdir, saw no repo
and stopped without routing. With the toolset limited to `Skill` the probe
measures the skill-or-not decision alone. See `docs/cross-model-evaluation.md`
§ Headless harness for the measured effect.

## triggers.json — Trigger Eval Results

Written by `run_trigger_evals.py` to `--output` (default
`<runs-root>/<plugin>/<skill>/triggers/<UTC stamp>/triggers.json`) and copied to
`<skill>/eval-results/triggers.json`, partial results included. **Gitignored.**
`--no-copy` skips the copy (stdout `COPY=none`); the live smoke passes it so a
plumbing run never overwrites the skill's genuine result.

```json
{
  "version": 1,
  "harness": "claude-code — the agent CLI, as in trace.json",
  "skill": "git-plugin:git-commit", "skill_dir": "string",
  "model": "haiku", "model_id": "string | null — the full id that ran",
  "runs_per_prompt": 1, "max_budget_usd_per_prompt": 0.05, "total_budget_usd": 1.0,
  "max_turns": "number | null",
  "thresholds": { "min_recall": 0.66, "max_false_positives": 0, "trigger_rate_min": 0.5 },
  "plugin_dirs": ["string"],
  "started_at": "ISO-8601", "finished_at": "ISO-8601", "runs_dir": "string — per-prompt rollout run dirs",
  "prompts": [
    {
      "id": "gct-001", "kind": "should_trigger | should_not_trigger", "expected": "boolean",
      "prompt": "string", "prompt_sha256": "string", "near_miss_of": "string | null",
      "triggered": "boolean | null — null on ERROR/SKIPPED", "trigger_rate": "number | null",
      "runs_ok": "number", "runs_error": "number", "skills_invoked": ["string"],
      "cost": "number", "cost_known": "boolean — false when charged at the per-prompt cap",
      "status": "OK | ERROR | SKIPPED", "outcome": "tp | fp | fn | tn | error | skipped",
      "runs": ["object — per-run rollout result"]
    }
  ],
  "summary": {
    "tp": 0, "fp": 0, "fn": 0, "tn": 0, "errors": 0, "skipped": 0, "attempted": 0,
    "recall": "number | null — tp/(tp+fn)",
    "precision": "number | null — tp/(tp+fp); null when nothing was predicted positive",
    "fpr": "number | null — fp/(fp+tn)",
    "total_cost": "number", "cost_includes_cap_charges": "boolean",
    "aborted": "boolean", "abort_reason": "string | null"
  },
  "status": "OK | WARN | ERROR",
  "issues": [{ "severity": "WARN | ERROR", "type": "string", "msg": "string" }]
}
```

A run whose cost is unknown — killed by `--stop-on-skill`, timed out, errored — is
charged at the per-prompt cap, and the runner aborts (rows kept, the rest `SKIPPED`,
`STATUS=ERROR`) before a run that could push the total past `--total-budget-usd`.
With `--runs N` a prompt counts as triggered at a rate ≥ 0.5. `STATUS=WARN` when
recall < `--min-recall` or fp > `--max-false-positives` — results are noisy at
`--runs 1`, so use `--runs 3` before acting. `ERROR` on a budget abort, a rollout
usage error, more than half the rows ERROR, or an invalid `triggers` block.

Stdout: one `=== TRIGGER EVALS ===` block; each row prints as
`  - ID=… EXPECTED=trigger|no_trigger TRIGGERED=true|false RATE=<r> OUTCOME=tp|fp|fn|tn|error|skipped STATUS=OK|ERROR|SKIPPED`,
and a null value prints as an empty `KEY=`.

## trace.json — Headless Rollout Trace

Written by `scripts/parse_trace.py` from a `claude -p --output-format stream-json
--verbose` transcript; `rollout_headless.sh` calls it for every rollout. The file
is **harness-neutral**: only the parser knows stream-json, and every grader and
runner reads this shape. `harness` here names the agent CLI (`claude-code`), not
the rollout harness. **Gitignored** (lives in the run dir).

| Field | Shape |
|-------|-------|
| `version` | `1` — `grade_deterministic.py --trace` exits 2 on anything else |
| `harness`, `harness_version` | `"claude-code"`, the CLI version from the init event |
| `model_id`, `session_id`, `cwd`, `permission_mode` | From the init event; `model_id` is the full id that ran |
| `plugins_loaded[]` | `{name, path?, source?, version?}` |
| `skills_available[]` | The init event's `skills` list, verbatim (built-in plugins included). The CLI (2.1.289) lists only **user-invocable** skills there, so a `user-invocable: false` skill such as `git-plugin:git-commit` is absent even though the model can invoke it. It is a diagnostic, not the routing catalogue: never read a skill's absence here as "not loaded"; use `plugins_loaded[]` for that and `skills_invoked[]` for routing |
| `skills_invoked[]` | `{skill, args, turn, tool_use_id, denied, is_error}` — `skill` exactly as the model sent it (full or bare); denied invocations kept with `denied: true` |
| `tool_calls[]` | `{turn, tool_use_id, name, input_summary, input, is_error, denied}` — `input` values capped at 2000 chars; `input_summary` one line ≤ 200 chars; `is_error` null when no result arrived |
| `bash_commands[]` | `{turn, command, is_error, denied}` — the model's own command, **uncapped** |
| `files_written[]` | `{path, tool}` — successful, non-denied Write/Edit/MultiEdit/NotebookEdit only; paths relative to `--workdir` (default the init cwd), absolute when outside it |
| `permission_denied[]` | `{turn, tool_name, tool_use_id, message}` — merged from `system/permission_denied` events and `result.permission_denials` |
| `hooks_fired[]` | `{turn, hook_id, hook_name, hook_event, outcome, exit_code}`; an unanswered `hook_started` has null outcome/exit code |
| `num_turns` | `result.num_turns`; when no result event arrived, the **counted** top-level turns (never null) — detect an incomplete run by `stop_reason == "incomplete"` or `parse_warnings.missing_result`, not by a null `num_turns` |
| `cost_usd`, `usage`, `duration_ms`, `duration_api_ms` | From the result event; null when it never arrived |
| `final_text` | `result.result`, else the last top-level assistant text |
| `stop_reason` | `completed` / `max_turns` / `budget` / `error` / `incomplete` (no result event) |
| `is_error` | From the result event; `true` when it is missing |
| `parse_warnings` | `{malformed_lines, missing_init, missing_result}` |

A turn is one distinct top-level assistant `message.id`, counted from 1 (matches
`num_turns`); events before the first assistant message are turn 0. Exit 0 when
anything parsed (partially is still 0, with `parse_warnings` set); 2 when the input
is empty, unreadable, or holds no parseable event.

### Headless run-dir files

`rollout_headless.sh` writes, beside `trace.json`:

| File | Contents |
|------|----------|
| `transcript.jsonl`, `stderr.log` | The child's raw stream and stderr |
| `transcript.md` | `final_text`, then a `\n\n---\n## Tool calls` appendix (output checks stop at it) |
| `timing.json` | `{started_at, ended_at, duration_ms, durationMs, harness, total_cost_usd, num_turns}`; `total_cost_usd` null when no result event arrived (a stop-on-skill, timeout or truncated run); `num_turns` copies trace.json, so it is the counted turns then, and null only when the trace did not parse |
| `workspace/` | Snapshot of the workdir (50 MB cap by apparent size, so a sparse file counts at full size; `--no-snapshot` to skip) — what workspace checks grade |
| `rollout-meta.json` | Flags as run (model, effort, budget, max_turns and whether the CLI accepted it, `tools`, permission, env mode requested/effective, `skill_listing_budget` as a number or `"cli"`), the prompt as **sha256 only** (it is sent on stdin, never argv), passthrough env **names only**, `inherit_stripped_env` (credential var **names** stripped in inherit mode), plugin dirs, argv |

## Golden-set probes

`scripts/tests/fixtures/golden-set-probes.json` holds recorded outputs that
`scripts/check_golden_set_evals.py` runs through the shipped grader to prove each
golden-set suite's checks discriminate.

| Field | Required | Description |
|-------|----------|-------------|
| `suite`, `case` | Yes | `<plugin>/<skill>` and an `evals[].id` |
| `expect` | Yes | `pass` (clears every deterministic check) or `fail` (fails at least one) |
| `fails_on` | No | On a `fail` probe, a check type at least one failure must have |
| `output` / `output_file` | One | Inline transcript text, or a file beside the probes file |
| `trace_file` | No | A trace.json v1 beside the probes file, passed as `--trace` |
| `workspace_dir` / `workspace_setup` | No (one) | A directory beside the probes file, or shell commands run in a fresh temp dir (hermetic git identity, no global config) — so no nested `.git` is committed. Either is passed as `--workspace` with `--allow-exec` |

A `pass` probe on a case with trace or workspace checks must report
`HARNESS_DEFERRED=0`; otherwise the checks it claims to exercise were never graded
(`pass_probe_harness_deferred`).

## grading.json — Grading Output

Produced by the `eval-grader` agent for each eval run. **Gitignored.**

```json
{
  "eval_id": "string — matches evals[].id",
  "skill_path": "string — path to SKILL.md",
  "expectations": [
    {
      "assertion": "string — the assertion text from evals.json",
      "passed": "boolean",
      "evidence": "string — specific evidence from transcript/artifacts",
      "confidence": "string — high | medium | low"
    }
  ],
  "summary": {
    "passed": "number — count of passed assertions",
    "failed": "number — count of failed assertions",
    "total": "number — total assertions",
    "pass_rate": "number — 0.0 to 1.0"
  },
  "claims": [
    {
      "claim": "string — implicit claim extracted from output",
      "verified": "boolean",
      "evidence": "string — verification evidence"
    }
  ],
  "eval_feedback": "string | null — suggestions for improving eval cases",
  "metrics": {
    "tool_calls": "number — count of tool invocations",
    "output_chars": "number — total output character count",
    "errors": "number — count of errors during execution"
  }
}
```

### grade_deterministic.py output

`--json` emits `{eval_id, expected_outcome, deterministic[], deferred[],
harness_deferred[], summary, inputs}`. `summary` holds `deterministic_total`,
`deterministic_passed`, `deterministic_failed`, `judge_pending` and
`harness_deferred` (an int); `inputs` is `{trace, workspace, allow_exec}` as
supplied. The default `KEY=value` block prints `HARNESS_DEFERRED=` after
`JUDGE_PENDING=`, and each harness-deferred item as a `RESULT=HARNESS_DEFERRED`
row. A `--trace` that is missing, unreadable or not `version: 1`, or a
`--workspace` that is not a directory, exits 2.

## benchmark.json — Aggregated Benchmark Results

Aggregated across runs for a single skill. **Gitignored.**

```json
{
  "metadata": {
    "skill_path": "string",
    "timestamp": "string — ISO-8601",
    "num_evals": "number",
    "num_runs_per_eval": "number",
    "configurations": ["with_skill", "baseline"],
    "harness": "string — subagent (default) | headless; pass rates from the two are not comparable"
  },
  "results": [
    {
      "eval_id": "string",
      "config": "string — with_skill | baseline",
      "runs": [
        {
          "run_id": "string",
          "grading": "object — grading.json contents",
          "timing": {
            "duration_ms": "number",
            "total_tokens": "number"
          }
        }
      ]
    }
  ],
  "summary": {
    "with_skill": {
      "mean_pass_rate": "number — 0.0 to 1.0",
      "stddev_pass_rate": "number",
      "min_pass_rate": "number",
      "max_pass_rate": "number",
      "mean_duration_ms": "number"
    },
    "baseline": {
      "mean_pass_rate": "number — 0.0 to 1.0 (null if no baseline)",
      "stddev_pass_rate": "number",
      "min_pass_rate": "number",
      "max_pass_rate": "number",
      "mean_duration_ms": "number"
    },
    "delta": {
      "pass_rate_improvement": "number — with_skill - baseline",
      "duration_overhead_ms": "number — with_skill - baseline"
    }
  },
  "analyst_notes": [
    "string — observations from aggregation"
  ]
}
```

## comparison.json — Blind Comparison Output

Produced by the `eval-comparator` agent. **Gitignored.**

```json
{
  "eval_id": "string",
  "winner": "string — A | B | tie",
  "reasoning": "string — why the winner is better",
  "scores": {
    "A": { "content": "number 1-5", "structure": "number 1-5", "overall": "number 2-10" },
    "B": { "content": "number 1-5", "structure": "number 1-5", "overall": "number 2-10" }
  },
  "quality_assessment": {
    "A": {
      "strengths": ["string"],
      "weaknesses": ["string"]
    },
    "B": {
      "strengths": ["string"],
      "weaknesses": ["string"]
    }
  },
  "expectations": [
    {
      "assertion": "string",
      "A_passed": "boolean",
      "B_passed": "boolean"
    }
  ]
}
```

## analysis.json — Analysis Output

Produced by the `eval-analyzer` agent. **Gitignored.**

```json
{
  "mode": "string — comparison | benchmark",
  "skill_path": "string",
  "comparison": {
    "winner": "string — with_skill | baseline",
    "instruction_following_score": "number — 1 to 10",
    "strengths": ["string"],
    "weaknesses": ["string"],
    "suggestions": [
      {
        "priority": "string — high | medium | low",
        "category": "string — instructions | description | examples | error_handling | tools | structure | references",
        "suggestion": "string — actionable improvement",
        "evidence": "string — data supporting the suggestion"
      }
    ]
  },
  "patterns": [
    "string — data-grounded observations"
  ]
}
```

## history.json — Improvement Iteration Tracking

Tracks skill improvements over evaluation cycles. **Gitignored.**

```json
{
  "skill_path": "string",
  "start_time": "string — ISO-8601",
  "current_best_version": "string — e.g., v3",
  "iterations": [
    {
      "version": "string — e.g., v1",
      "parent_version": "string | null",
      "timestamp": "string — ISO-8601",
      "pass_rate": "number — 0.0 to 1.0",
      "changes_made": "string — summary of changes"
    }
  ]
}
```

## model-matrix.json — Cross-Model Results

Records with-skill and baseline pass rates for one skill across pinned models.
Consumed by `scripts/render_matrix_report.py`. **Gitignored** (the rendered
report and stored history are the durable artifacts). See
[`docs/cross-model-evaluation.md`](../docs/cross-model-evaluation.md).

```json
{
  "metadata": {
    "skill_path": "string",
    "generated_at": "string — ISO-8601",
    "previous_run": "string | null — ISO-8601 of the last sweep, for Δ vs prev",
    "models": [
      { "alias": "string — opus | sonnet | haiku | fable", "model_id": "string — full pinned id that ran, e.g. claude-fable-5-1 (never the alias); on a headless run, trace.json model_id", "effort": "string | null — low | medium | high | xhigh | max as run; null for models with no effort lever (haiku)", "harness": "string — optional; subagent | headless, overrides metadata.harness" }
    ],
    "harness": "string — optional; subagent (the default when absent) | headless"
  },
  "evals": [
    {
      "eval_id": "string",
      "by_model": {
        "<alias>": { "with_skill": "number 0.0-1.0", "baseline": "number 0.0-1.0" }
      }
    }
  ],
  "summary": {
    "by_model": {
      "<alias>": {
        "with_skill": "number — mean pass rate across evals",
        "baseline": "number — mean baseline pass rate",
        "delta": "number — with_skill - baseline",
        "prev_delta": "number | null — delta from previous_run, drives the ▲/▼ marker"
      }
    }
  }
}
```

The renderer derives per-model verdicts (`earns its keep`, `possibly redundant`,
`fighting the model`, `ineffective`, `marginal`) from `with_skill`/`baseline`,
and raises a portability flag when the opus−haiku with-skill spread is ≥20
points. It prints the harness, and a **mixed-harness warning** when the models
ran under different harnesses (an absent field counts as `subagent`), because
those pass rates cannot be compared.

## plugin-benchmark.json — Plugin-Level Aggregation

Aggregated across all skills in a plugin. **Gitignored.**

```json
{
  "metadata": {
    "plugin_name": "string",
    "timestamp": "string — ISO-8601",
    "skills_evaluated": "number",
    "skills_total": "number"
  },
  "skills": [
    {
      "skill_name": "string",
      "skill_path": "string",
      "num_evals": "number",
      "mean_pass_rate": "number — 0.0 to 1.0",
      "status": "string — PASS (>=80%) | PARTIAL (50-79%) | FAIL (<50%)"
    }
  ],
  "summary": {
    "overall_pass_rate": "number — 0.0 to 1.0",
    "skills_passing": "number",
    "skills_partial": "number",
    "skills_failing": "number"
  }
}
```

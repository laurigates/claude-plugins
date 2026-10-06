# Cross-Model Skill Evaluation

How we measure skill effectiveness reproducibly, across models (opus / sonnet /
haiku), without burning tokens — so we notice when a skill needs adjusting,
especially when a new Claude model ships.

This is a design + prototype. The prototype lands the token-frugality lever (the
deterministic grader) and the report format against the one existing eval set
(`git-plugin/skills/git-commit/evals.json`). Populating a golden set and the
`/evaluate:matrix` orchestration skill are follow-ups.

## The problem

`evaluate-plugin` already grades a single skill's behaviour against assertions
with a `--baseline` delta. Three things were missing for the question "are our
skills still effective, and which model are they effective on?":

1. **No cross-model dimension** — runs use whatever model is active.
2. **Token cost** — every assertion routes through an Opus `eval-grader`
   subagent, N runs each. Fine for one skill; ruinous as a regular signal
   across 348 skills.
3. **No reproducibility / cadence contract** — nothing pins model IDs or says
   "re-run this fixed set when a model drops and diff against last time."

## Design principles

### 1. Tier the cost; only the top tier spends real tokens

| Tier | Cost | Scope | Cadence |
|------|------|-------|---------|
| 0 — static | free | all 348 skills | every PR (`plugin-compliance-check.sh`, lints) |
| 1 — deterministic evals | ~free (no judge) | skills with `evals.json`, single active model | CI on changed skill |
| 2 — cross-model matrix | budgeted | **golden set only**, opus/sonnet/haiku | monthly + on model release |

Tier 0 catches structural rot for free. Tier 2 is the only thing that costs
tokens, and it is bounded to the golden set.

### 2. Split assertions into deterministic vs judged — the biggest lever

Most skill-output expectations are machine-checkable. From the git-commit set:
"starts with `feat(`", "does not end with a period", "references `#42`",
"both `#100` and `#101`" are regex/substring checks that cost **zero** model
tokens. Only genuinely fuzzy ones ("uses imperative mood", "body provides
context") need an LLM judge.

`scripts/grade_deterministic.py` grades the typed checks and reports the fuzzy
ones as `DEFERRED`, so the judge agent only ever runs on those. On the
git-commit set this is ~70% of assertions graded for free.

Expectations stay backward compatible: a bare string is treated as `judge`
(existing behaviour); a typed object opts into deterministic grading.

```json
{ "assertion": "Commit message starts with feat(", "check": "regex",
  "pattern": "^feat\\(", "scope": "subject" }
```

Check types: `regex`, `substring`, `substring_all`, `absent_regex`, `judge`.
Optional `scope` (`full` | `subject` | `body`) and regex `flags`. Full schema
in [`references/schemas.md`](../references/schemas.md).

### 3. The signal is the with-skill − baseline *delta*, per model, over time

A bare pass rate means nothing; the delta against the model's own baseline does.
The cross-model interpretation is a 2×2:

| | baseline already high | baseline low |
|---|---|---|
| **with-skill high** | possibly **redundant** — model already knows; candidate to slim | **earns its keep** |
| **with-skill low** | **fighting the model** — adds noise | **ineffective** — rewrite |

`render_matrix_report.py` computes the verdict per model from these thresholds
and flags **portability**: a skill that scores ≥20 points higher on opus than
haiku leans on reasoning the cheap model lacks — simplify it or pin `model:`.

This is what "noticing a new model needs adjusting" reduces to: store each
matrix run, and on a new model release re-run the golden set and diff the delta
column (`Δ vs prev`). A canary whose delta collapsed gets flagged — either the
model now does it unaided (redundant) or now does it worse (needs adjusting).

### 4. Reproducibility = pin everything, run on a trigger not per-PR

- Pinned model IDs recorded as **full ids** in `model-matrix.json
  metadata.models` (never aliases — `opus` now resolves to `claude-opus-5`, not
  `claude-opus-4-8`, and will move again). Current set: `claude-opus-5`,
  `claude-sonnet-5`, `claude-haiku-4-5`; add `claude-fable-5-1` for the "new
  model dropped" re-sweep of the golden set. Record the effort level alongside
  each id; level names are not comparable across models, so a new model gets
  its own effort sweep before its delta column is read.
- Single-turn prompts, version-controlled fixtures (`evals.json`).
- **Baseline cached per model-version** — baseline only changes when the model
  changes, so a skill edit re-runs only the with-skill side.
- Trigger: monthly cron + manual "new model dropped" run.

> Note: testing a skill *on* haiku here is unrelated to the repo ban on
> `model: haiku` in skill frontmatter. We evaluate the skill across models; we
> still don't author skills that pin themselves to haiku.

## Run engine: in-session subagents

Cross-model runs reuse the existing `Task`-subagent approach, parameterized by
model (the `Agent`/`Task` `model` field selects opus / sonnet / haiku). This
keeps real tool execution (Bash/Edit) so skills that produce artifacts — not
just text — are evaluated faithfully. The orchestrating `/evaluate:matrix` skill
(follow-up) loops models × evals × {with_skill, cached_baseline}, captures each
transcript, runs `grade_deterministic.py` first, and only dispatches the
`eval-grader` agent for the `DEFERRED` assertions.

Mind `.claude/rules/skill-fork-context.md`: do **not** add `context: fork`, and
serialize subagent dispatch to avoid the concurrent-rate-limit trap that hits
1M-context sessions (every Fable 5.1 session, or Opus with the `[1m]` suffix).

## Headless harness

The subagent run engine pastes the SKILL.md into a `Task` subagent. That tests what
the skill *says*, but not whether the plugin loads, whether the description routes
a real prompt to the skill, whether `allowed-tools` lets it run, or what its hooks
do. The headless harness tests those by running each cell as a real
`claude -p --output-format stream-json --verbose` child with `--plugin-dir`. It is
**opt-in** (`--harness headless` on `/evaluate:skill`, `/evaluate:matrix` and
`/evaluate:plugin-batch`); `subagent` stays the default.

| Piece | Role |
|-------|------|
| `scripts/rollout_headless.sh` | Launches one child in a workdir outside the repo, records the stream, snapshots the workdir, prints `=== HEADLESS ROLLOUT ===` |
| `scripts/parse_trace.py` | Turns the stream into a harness-neutral `trace.json`. It is the only code that reads stream-json |
| `grade_deterministic.py --trace/--workspace/--allow-exec` | Trace checks (`skill_triggered`, `tool_called`, `command_ran`) and workspace checks (`file_*`, `json_path`, `run_command`) |
| `scripts/run_trigger_evals.py` | Trigger evals: does routing pick the skill, and only the skill? |

**One runner per cell.** The rollout agent on this harness is a thin runner. It
calls the scripts and never does the task itself, so the agent budget is unchanged
at `2 + 2 x cells`, and the grader is still never the agent that produced the
transcript.

**Permissions.** A rollout defaults to `--dangerously-skip-permissions` inside its
throwaway `mktemp` workdir, with `IS_SANDBOX=1` when running as root. The probe
showed why: under `acceptEdits`, both `Skill` and `Bash` were `permission_denied`.
Trigger mode instead runs `--tools Skill --allowed-tools Skill --permission
default --stop-on-skill`, so the child has the `Skill` tool and nothing else, and
is killed at its first `Skill` call. `--allowed-tools` alone only auto-approves:
with Bash available, haiku ran `git status` in the empty workdir and stopped at
"not a git repository" instead of routing (2026-10-06). A workdir inside a repository is refused with exit 2:
the repo the script lives in, the **caller's** repo (the git toplevel of the
current directory -- the skills run an installed `${CLAUDE_PLUGIN_ROOT}` copy,
which sits outside your checkout), or any repo rooted above the workdir. So is a
workdir with a `skills` path component. The prompt reaches the child on stdin,
never in argv, so a prompt starting with `-` (YAML front matter) stays text.

**Env scrub (`--env-mode clean`, the default).** A child that inherits the parent's
env inherits the parent session: the same `session_id`, cloud-only tools, and the
parent's hooks. Clean mode runs `env -i` with an allowlist (PATH, locale,
proxy/CA, optional `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`) and a throwaway
fake HOME. That HOME has no user settings, hooks or MCP servers, and a
neutral git identity so commit evals can commit. Its only login is a copy of
`~/.claude/.credentials.json` (a Linux `/login`), made when no token is exported. Session-identity variables
(`CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_REMOTE*`) are never passed, even when named
in `--passthrough-env`. Measured 2026-10-05 on claude 2.1.289, nested in a cloud
session:

| Finding | Result |
|---------|--------|
| Auth under `env -i` + fake HOME | **Works** with no extra variables. The egress gateway supplies auth, so `CLOUD_PASSTHROUGH` is empty. It worked even with the proxy and CA variables removed. No fallback to `inherit` was needed |
| `session_id` | The child's id differs from the parent's in clean mode (they were equal under inherit). An equal id is reported as WARN `session_id_leak` |
| Cloud-only tools | Clean mode drops 15 of them (`Artifact*`, `SendUserFile`, `Suggest*`, `Search*`, `List{Connectors,Plugins,Skills}`, …) and adds `RemoteTrigger`; `mcp_servers` is empty |
| Hooks | Only the loaded plugin's own hooks fire (e.g. git-plugin's `SessionStart` probe and `PreToolUse:Bash` hooks); a baseline run fires none. A hook no `--plugin-dir` declares is WARN `foreign_hook`. Managed-settings hooks cannot be scrubbed and would surface the same way |
| Built-in plugins | **Not** removed. The CLI's built-in plugins and their skills stay loaded, so trigger evals compete against them as well as against `peers` |
| `skills_available` | Mirrors the init event's `skills`, which lists only **user-invocable** skills. All 21 `user-invocable: false` git-plugin skills were absent, the skill under test (`git-plugin:git-commit`) among them, while the 7 `disable-model-invocation: true` ones were present. The model's `Skill` listing still offered `git-commit`. So the field shows what a user can type, not what routing can pick |
| Skill descriptions | **Elided at the CLI default, so rollouts raise the budget.** With `--plugin-dir git-plugin` (48 skills) haiku saw `git-plugin:git-commit`, `git-commit-trailers` and `git-commit-workflow` by name with "description not provided". The cause is the CLI's `Skill`-listing character budget (`SLASH_COMMAND_TOOL_CHAR_BUDGET`, an integer override read by the 2.1.289 binary, scaled to the context window when unset). At the default the gc-007 with-skill rollout never invoked `git-commit` and trigger recall was 0/3 in two rounds. Every rollout now sets the budget to 100000 (`--skill-listing-budget`, or `$EVAL_SKILL_LISTING_BUDGET`); `cli` keeps the default to measure what an installed user gets. Measured 2026-10-06 (haiku, n=1) with the budget raised and trigger mode on `--tools Skill`: the gc-007 with-skill rollout invoked `git-plugin:git-commit` (baseline did not); trigger recall 2/3, precision 1.0, no should-not prompt triggered. The miss (gct-002, "stage it and make a commit") routed to sibling `git-plugin:git-cli-agentic` -- a real routing finding, not budget elision |
| `--max-turns` / `--effort` | Both are accepted and enforced, though `--max-turns` is missing from `--help`. `--max-turns 1` ends with `error_max_turns`, which the runner reports as `STOP_REASON=max_turns` WARN. Either flag is retried without it, with a WARN, if a future CLI rejects it |

`--env-mode inherit` is an explicit opt-in. It keeps the real HOME but unsets every
`CLAUDE*` session variable plus `SESSION_INGRESS_URL` and `TRACEPARENT`, and a
third-party credential denylist (`GH_TOKEN`, `GITHUB_TOKEN`, `AWS_*`,
`CLOUDSDK_*`, `GOOGLE_*`, `GIT_CONFIG_*`, `CCR_*`, `SSH_AUTH_SOCK`, ...). It always
WARNs (`inherit_env`): the real HOME still exposes `~/.ssh`, `~/.aws` and user
hooks to a child that bypasses permissions; `rollout-meta.json`
`inherit_stripped_env` names what was stripped. A clean child that cannot
authenticate is an ERROR (`auth_failed`) naming the fix -- export
`CLAUDE_CODE_OAUTH_TOKEN` (`claude setup-token`) or `ANTHROPIC_API_KEY`, or put one
in `~/.api_tokens`. It is never silently retried in inherit mode: that retry
handed every credential in the parent env to a `--dangerously-skip-permissions`
child.

**Spend.** `--max-budget-usd` is required unless `EVAL_ALLOW_UNCAPPED=1`; 0.25 per
rollout is a sane cap on haiku. A killed or timed-out child has no result event,
so its cost is unknown (`COST_USD` is empty). The trigger runner charges such a run
at its per-prompt cap.

**Not comparable to subagent numbers.** Record the harness in every result file:
`benchmark.json` `metadata.harness` and `model-matrix.json`
`metadata.models[].harness`. `render_matrix_report.py` warns when one file mixes
them. On a subagent run, trace and workspace checks are `HARNESS_DEFERRED`: they
are excluded from the pass rate and never judged, so a subagent run never
false-fails on them.

**Live smoke.** `EVAL_LIVE=1 bash evaluate-plugin/scripts/tests/live/smoke-headless.sh`
runs gc-007 with and without the skill, grades both, runs git-commit's trigger
evals (capped at $0.60), and asserts the env-leak invariants and a total spend of
at most $1.50. It runs haiku only. Its name lacks the `test-` prefix, so CI never
runs it; `tests/test-smoke-headless.sh` drives it offline through the fake
`claude`.

It asserts the plumbing, not routing. Routing is **reported**: `WITH_SKILL_ROUTED`
and `TRIGGERS_RECALL`. A with-skill run that never invokes the skill
(`unrouted`), or trigger evals that miss a threshold (`trigger_threshold`), make
the smoke `STATUS=WARN` and exit 0. The one routing **assertion** is negative: the
baseline, which never loads the plugin, must not invoke the skill. On
2026-10-05 (2.1.289, n=1), haiku committed gc-007 directly, without the skill
and with a non-conventional subject, and missed all 3 should-trigger prompts
(recall 0.0). Yet a probe showed `git-plugin:git-commit` in haiku's `Skill`
listing. That is haiku's routing, not the harness hiding the skill. For a
routing verdict, run trigger evals at `--runs 3`, on a model you would ship
with.

## Golden set criteria

Don't test all 348 skills × 3 models. Pick ~15–25 canaries that are
representative, high-traffic, or high-risk, covering distinct patterns:

| Dimension to cover | Example canary |
|--------------------|----------------|
| CLI-wrapper skill (mechanical) | `tools-plugin` rg/jq/fd skill |
| Multi-step orchestrator | a `blueprint` or `git` workflow skill |
| `AskUserQuestion` interactive skill | a `configure-plugin` skill |
| Generator (produces files) | a scaffolder skill |
| Convention-enforcing (text output) | `git-plugin/git-commit` ← prototype anchor |

When a new model degrades the canaries, that's the trigger to audit the long
tail. The other ~320 skills stay on Tier 0/1.

## Token math for a full Tier-2 sweep

≈ 20 skills × ~4 evals × 3 models × 2 configs (with-skill + cached baseline)
≈ 480 single-turn runs. At a few k tokens each → low single-digit millions per
monthly sweep. With ~70% of assertions graded deterministically, the judge
agent fires on a fraction of that. Cheap enough to automate; expensive enough to
be worth not eyeballing.

## Prototype status

| Piece | Status |
|-------|--------|
| Typed-check schema on `expectations` | done — `git-commit/evals.json` migrated, back-compatible |
| `scripts/grade_deterministic.py` | done — regex/substring/absent, scope, JSON + KEY=value out |
| `scripts/render_matrix_report.py` | done — delta table, verdicts, portability flag |
| `scripts/tests/test-grade-deterministic.sh` | done — run by `scripts/run-skill-script-tests.sh` (`Test: Skill scripts`, path-filtered) and pre-commit; declared in `scripts/required-to-run-tests.txt`. Ran nowhere until #2795: the old `test_*.sh` name missed the runner's `test-*.sh` glob |
| `model-matrix.json` schema | done — documented; example fixture renders |
| `/evaluate:matrix` orchestration skill | done — runs the matrix, grades deterministic-first, renders the executability flag |
| Golden set definition (`golden-set.json`) | done — 16 canaries across 6 patterns |
| Golden-set `evals.json` coverage | partial — 8 of 16 canaries (5 of 6 patterns; `weak-model-gate` has none yet), `evalCoverageFloor` 8, each suite with an abstention case; `scripts/check_golden_set_evals.py` runs recorded probes through the grader (#2144) |
| Fixture / scaffolding layer (`evals[].fixture`, `apply_fixture.sh`) | done — opt-in, isolated temp workdir, golden-set scope; dir-copy + teardown demonstrated in `scripts/tests/test-apply-fixture.sh` (same CI wiring as the grader suite, #2795) |
| Cron / model-release trigger | done — `.github/workflows/golden-set-evaluation.yml` (monthly cron + `workflow_dispatch` for the on-model-release run) |
| Headless harness (`rollout_headless.sh`, `parse_trace.py`) | done — opt-in `--harness headless`; env scrub measured live; fake-`claude` tests in `test-rollout-headless.sh` / `test-parse-trace.sh`, live smoke behind `EVAL_LIVE=1` |
| Trace / workspace checks | done — 8 new check types, harness-deferred on subagent runs; gc-007 (and gc-006's `command_ran max:0`) probed with recorded traces and materialised workspaces |
| Trigger evals (`triggers` block, `run_trigger_evals.py`) | done — git-commit carries 3 should / 3 should-not prompts; CI covers the maths with a stub rollout; the golden-set workflow does not run them yet |

## Related

- `.claude/rules/skill-evaluation.md` — the top-level methodology this design
  implements (tiered cost, delta signal, golden set, cadence)
- [`references/schemas.md`](../references/schemas.md) — evals.json (typed,
  trace and workspace checks; `triggers`), trace.json, triggers.json and
  model-matrix.json schemas
- [`skills/evaluate-skill/SKILL.md`](../skills/evaluate-skill/SKILL.md) —
  single-skill / single-model evaluation this extends
- `.claude/rules/skill-fork-context.md` — why subagents are serialized and
  `context: fork` is avoided
- `.claude/rules/regression-testing.md` — every check ships a test
- `.claude/rules/structured-script-output.md` — the `=== SECTION ===` /
  `STATUS=` grader output convention

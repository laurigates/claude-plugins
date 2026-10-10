# Claude Haiku 5.5 re-evaluation — 2026-10-10

This records the sweep that re-checked which skills, agents, bundled workflow
harnesses and GitHub workflows could run on Claude Haiku 5.5. It covers this
repo and the reusable workflows in `laurigates/.github`. Haiku was purged here
earlier because Haiku 4.5 caused more problems than it saved. This sweep asked
whether Haiku 5.5 changes that, and it doubled as a baseline for how Haiku 5.5
does as a classifier subagent.

The rule and guard changes landed with this file. The skill and stage changes
are in a companion PR.

## Sources

- [Claude Haiku 5.5 announcement](https://www.anthropic.com/claude-haiku-5-5)
  (2026-10-07). Price per Mtok: $0.10 in and $0.50 out for prompts up to 100k
  tokens, and $0.50/$2.50 above that. It is the first Haiku with `effort`
  (low–max). Terminal-Bench 4.0: 39.2% against Sonnet 5.5's 70.6% (Haiku 4.5
  scored 0.0%). Its cybersecurity safeguards are stricter than Haiku 4.5's.
  Recommended for classification, summaries and subagent work under an Opus or
  Sonnet lead, and not for complex agentic coding.
- Claude Code CHANGELOG 2.1.293: `claude-haiku-5-5` became the default Haiku on
  the Anthropic API, so the `haiku` alias resolves to it. This session ran
  2.1.296.
- [Skills docs](https://code.claude.com/docs/en/skills), `model` field: "The
  override applies for the rest of the current turn … With `context: fork`, the
  value sets the forked subagent's model instead."
- [Permission modes docs](https://code.claude.com/docs/en/permission-modes):
  Haiku 5.5 is a supported auto-mode model, so a skill pin is not silently
  dropped in auto mode, which is the default since 2.1.283.

## Why haiku was purged

| When | Where | What and why |
|---|---|---|
| 2026-03 (#881) | 35 skills | `model: haiku` removed. `AskUserQuestion` prompts "return empty without displaying to the user"; a lint was added. |
| 2026-06 (#1691) | 9 agents | dependency-audit, docs, search-replace, test, container-build, git-ops, k8s-diagnostics, terraform-ops and test-runner moved to opus under the always-Opus standard. |
| 2026-06 (#1752) | 5 workflows | auto-resolve-conflicts, plugin-pr-checks, release-pr-doc-audit, scheduled-audits and skill-splitter moved to `opus` + explicit `--effort`, because "Haiku supports no effort". |
| 2026-07 (`laurigates/.github#17`) | 9 reusable workflows | A flat `--model haiku` became an opus/sonnet split. The trigger was 5–6-turn haiku budgets dying on `error_max_turns`. |

Two of the three stated reasons were facts about Haiku 4.5: no effort, and the
`AskUserQuestion` failure. The third, short turn budgets, was a config problem.
None of them was re-checked when the alias moved.

## Method

A `Workflow` with 22 agents (run `wf_20b77947-17f`):

- **Classify:** 16 Haiku 5.5 agents at `effort: medium`. 13 took 34 skills each
  (442 skills), one took the 21 agents plus 8 `*.workflow.js` harnesses, and two
  took the 27 local and 26 reusable GitHub workflows. Each one read every file
  and returned one of `haiku`, `haiku-stage`, `needs-test` or `keep`, with a
  rationale and risks. The rubric defaulted to `keep`.
- **Verify:** 6 Opus 5.5 agents at `effort: high`, one per group of batches.
  They re-read the files behind all 204 non-`keep` verdicts, plus a
  deterministic sample of 49 `keep` verdicts as a control, and returned a final
  verdict with a `confirm`, `adjust` or `reject` assessment. They also reported
  on the classifier's quality.
- **Adjudicate:** the orchestrating session. See [Adjudication](#adjudication).

## Results

| | Haiku classifier | After Opus verification | Applied |
|---|---|---|---|
| `haiku` (whole artefact) | 84 | 35 | 14 skills |
| `haiku-stage` | 13 | 8 | 2 workflow stages (2 more reverted in review) |
| `needs-test` | 107 | 88 | 0 |
| `keep` | 320 | 122 of the verified set | — |

No agent and no GitHub workflow in either repo reached `haiku`. Every invoking
workflow is `keep` or `needs-test`, and so are the two nearest agents,
`search-replace` and `test-runner`.

## Haiku 5.5 as the classifier — the baseline

**Reading held up and judgement did not.** Opus confirmed 93 of the 204
non-`keep` verdicts (46%), adjusted 38 and rejected 73. All 49 control `keep`
verdicts held, so the sample showed no missed candidates. Every verifier said
the classifier read the files: concrete details checked out line by line, and
it said when it had not opened a sidecar. The verifiers found two overstated
gates (`vault-templates`, `python-code-quality`) and one invented detail
(`container-build`'s "preloaded docker-development skills", which do not exist).

Its errors were systematic. It treated a skill's `model:` as if it covered only
the skill's own work, but the override lasts for the rest of the turn. That one
misreading produced most of the rejections: `git-branch-naming`, `rg-code-search`,
`gh-cli-agentic`, `test-tier-selection` and other references the model loads in
the middle of larger work. A haiku pin on those would hand the surrounding
implementation turn to Haiku. The classifier often wrote "would switch the
whole session model" under risks and then assigned `haiku` anyway. It also
proposed per-flag or per-step model splits (`--check-only` on haiku, `--fix` on
opus), which skill frontmatter cannot express.

What this says about Haiku as a subagent: Haiku 5.5 is a reliable reader and
extractor. It is not a reliable judge of a rubric that needs a mechanism model,
and it does not act on the risks it has itself identified. That fits what the
applied stages are, verbatim extraction and closed-enum classification. It
also fits the house rule that a cheaper delegate needs an independent check
behind it.

**Cost.** Every subagent request in this portfolio starts at about 127k tokens
(CLAUDE.md, rules, the skill listing, tool schemas). All 102 Haiku requests in
the run were therefore above the 100k price step and billed at $0.50/$2.50, not
$0.10/$0.50. From the transcripts:

| Model | Agents | Requests | Cache read | Cache write | Output |
|---|---|---|---|---|---|
| Haiku 5.5 | 16 | 102 | 15.1M | 4.9M | 249k |
| Opus 5.5 | 6 | 133 | 32.3M | 1.8M | 79k |

At list prices this is about $4 for the classification and about $24 for the
verification. That estimate assumes the standard 0.1× cache-read and 1.25×
cache-write multipliers, the >100k Haiku tier, and Opus 5.5 at $4/$20. In
Claude Code, Haiku 5.5 costs about a quarter of Sonnet 5.5 and an eighth of
Opus 5.5 per token, not the twentieth the headline suggests.

## Adjudication

The six verifiers applied the turn-scope rule inconsistently. One group
rejected obsidian `bases`, `bookmarks` and `command-palette` because they are
`user-invocable: false` references, while another group confirmed obsidian
`properties`, `tasks` and `templates`, which have the same shape. I applied one
rule to all 35 confirmed skills. A skill gets `model: haiku` only when it is a
report, a listing, or a user-driven terminal task that ends the turn. That
moved 21 skills to `needs-test`:

| Reason | Skills |
|---|---|
| `user-invocable: false` (only the model loads it, mid-task) | obsidian `plugins-themes`, `properties`, `search-discovery`, `tasks`, `templates`, `vault-management`, `workspaces`; `ruff-formatting`, `uv-python-versions`, `cargo-llvm-cov`, `tfc-list-runs`, `tfc-run-status`, `tfc-workspace-runs`, `imagemagick-conversion` |
| Edit-loop step: the model calls it, then keeps editing in the same turn | `code-lint`, `bun-add`, `bun-build`, `bun-install` |
| Runs just before an orchestration step | `task-status` (before a dispatch wave), `attributes-collect` (before `attributes-route`) |
| Invoked mid-run by a session-model skill | `blueprint-workspace-scan` (from `blueprint-status`) |

The first row is now a lint: `check_skill_frontmatter()` rejects `model: haiku`
on a `user-invocable: false` skill unless it has `context: fork`. The other
three rows need judgement and are left to review.

## Applied

Skills now carrying `model: haiku` and `effort: low`. Three of them were pinned
`sonnet` before:

| Skill | Target | Verifier rationale |
|---|---|---|
| `blueprint-plugin:blueprint-adr-list` | model: haiku + effort: low (replace model: sonnet) | Verified: Bash and Glob only, no AskUserQuestion. The body is a fixed fd/awk table recipe plus grep counts, and the output is a listing that can be eyeballed against docs/adrs/. This is the clearest sonnet-to-haiku swap. |
| `blueprint-plugin:blueprint-docs-list` | model: haiku + effort: low (replace model: sonnet) | Verified: fixed bash for-loops that extract frontmatter into tables. No AskUserQuestion, no writes, and the adrs branch delegates to adr-list. Output is easy to eyeball. Separate pre-existing bug: the 'all' branch uses… |
| `codebase-attributes-plugin:attributes-dashboard` | model: haiku + effort: low | Verified: renders bars and severity groups from .claude/attributes.json, or from inline collect checks. It is a pure display, read-only and easy to eyeball. |
| `comfyui-plugin:comfy-workflow-layout` | model: haiku + effort: low | Verified: a stdlib layout script does all the work. The default is an A/B output copy, and --verify aborts on node overlap. The --in-place batch path is guarded by the body's 'run on one workflow first, eyeball it'. Bou… |
| `configure-plugin:configure-status` | model: haiku + effort: low | Verified as read-only. allowed-tools is `Glob, Grep, Read, TodoWrite, Bash(bash *)`. It runs the manifest-listed detection scripts, rolls up their STATUS= and ISSUE_COUNT= lines into a fixed table, and has no AskUserQue… |
| `evaluate-plugin:evaluate-report` | model: haiku + effort: low | Verified as read-only. Its tools are Read/Glob/Grep plus cat/jq/find/ls, and it renders benchmark.json and history.json into fixed tables. The --compare improved/regressed list is a small set difference that a reader ca… |
| `finops-plugin:finops-caches` | model: haiku + effort: low | It wraps one script (`cache-analysis.sh`) and reports sectioned output. One caveat: Bash(gh api *) would permit `-X DELETE`. The skill only prints the cleanup loop as a suggestion, so watch in a test run that Haiku does… |
| `finops-plugin:finops-compare` | model: haiku + effort: low | It wraps `compare-repos.sh` and presents the tables, read-only. The classifier's 'frontmatter lists dispatches_agents=true' is misattributed: no such field is in the frontmatter. It must come from the classifier's input… |
| `finops-plugin:finops-overview` | model: haiku + effort: low | It wraps `billing-summary.sh`. The net-vs-gross risk is real but the script owns it: billing-summary.sh lines 22-27 print net and gross explicitly, so Haiku only needs to quote that output verbatim. The post-actions are… |
| `finops-plugin:finops-workflows` | model: haiku + effort: low | It wraps one of two scripts (per-repo or org) and reports a fixed section layout. It is read-only, and its post-actions are suggestions only. |
| `macos-plugin:macos-performance-benchmark` | model: haiku + effort: low | It is user-invocable and self-contained. run.sh does all scoring against self-calibrating baselines and writes PASS/WARN/FAIL to summary.tsv, so the agent only runs one command and summarises an already-scored report. T… |
| `tools-plugin:generate-image` | model: haiku + effort: low (replacing sonnet) | disable-model-invocation: true means the skill is always the whole user-invoked task. It builds one uv command, the image is checked by eye, and the turn ends. The classifier's {{arg:1}} finding is accurate: the placeho… |
| `typescript-plugin:bun-debug` | model: haiku + effort: low | Picks a flag from a table, launches the inspector and reports the URL. The interactive debugging happens later in the user's debugger, not in this turn. |
| `typescript-plugin:bun-outdated` | model: haiku + effort: low | Produces a read-only table and suggests follow-up commands without running them. |

Workflow-harness stages moved to `model: 'haiku'`. Each one's output feeds an
Opus stage, and each sets an explicit effort, which
`check-workflow-js-model.sh` now requires and lists as `haiku_stage`:

| Harness | Stage(s) | Effort | Why it holds |
|---|---|---|---|
| `evaluate-plugin:evaluate-plugin-batch` | `inventory` | low | Runs one script and joins two path lists into a boolean. A script would be cheaper still (follow-up). |
| `testing-plugin:test-analyze` | `parse` | medium | Classification into a schema-forced enum with an `unroutable[]` escape. Medium rather than low because severity is a judgement and a misroute has no downstream check. |

`blueprint-plugin:blueprint-story-audit`'s `story:<prd>` lanes and
`bug-triage` were moved to haiku and then reverted to `opus`/`low` in review.
Both fail by omission: a story the extraction lane drops never enters the join,
and a bug triaged as not-yet-implemented never reaches compose. The Opus stages
downstream only see what these stages return, so they cannot notice either
miss, and the "feeds an Opus stage that would notice a bad one" condition does
not hold.

These verifier-confirmed stages were not applied, because the verifier
attached a measurement first: `evaluate-skill` (preflight and headless runner),
the `test-runner` dispatch from `test-quick`/`test-run` (the agent is shared,
and its framework-choice trap is documented), and `configure-all`'s
`check:<component>` fan-out (40 of 42 configure skills reference
`AskUserQuestion`).

## Not applied: `needs-test`

Each row is plausible on Haiku 5.5, but carries a named risk to measure first.
The columns are the classifier's verdict and the verifier's reasoning. The 21
adjudicated skills above belong here too.

| Artefact | Haiku said | Verifier |
|---|---|---|
| `.github/workflows/plugin-pr-checks.yml` | needs-test | Verified: a fixed 5-item checklist over the changed SKILL.md files. The review step has no continue-on-error, so an error_max_turns on a weaker model fails the REQUIRED compliance job. The prompt als… |
| `.github/workflows/release-pr-doc-audit.yml` | needs-test | Verified: mechanical compliance checks with one PR comment as the deliverable. assert-pr-comment-delivered.sh gates delivery but not content. The #2630 denial history means the posting path must be c… |
| `.github/workflows/research-radar.yml` | needs-test | Verified: classification of pre-computed candidates against a fixed bar, with a mandatory grounding Grep per surfaced paper and at most one issue. That shape is plausible for Haiku. The cost of error… |
| `.github/workflows/scheduled-audits.yml` | haiku | 'Claude only formats' understates the prompt. It says 'Using this data plus your own judgment', then asks Claude to scan CLI examples and suggest compact flags, judge model/effort fit to each skill's… |
| `.github/workflows/skill-splitter.yml` | needs-test | Verified: multi-file content moves, link insertion and positional-pointer rewrites, committed per skill across up to 10 skills in one 60-turn loop. Downstream gates are real: the refactor(split) subj… |
| `laurigates/.github:.github/workflows/reusable-a11y-aria.yml` | needs-test | Verified: a fixed ARIA checklist, structured --json-schema output, BLOCKING_SEVERITIES empty (advisory), default 50 turns. This is the rubric's most likely sonnet→haiku win, and it runs on every PR a… |
| `laurigates/.github:.github/workflows/reusable-quality-code-smell.yml` | needs-test | Verified: a fixed three-tier smell rubric, advisory output. Several High items (function >50 lines, 5+ params, 4+ indentation levels) and some Medium/Low items (console.log, TODO without issue, empty… |
| `laurigates/.github:.github/workflows/reusable-quality-typescript.yml` | needs-test | Verified against the prompt: the Critical tier is grep-able, while implicit any, unsafe assertions and missing return types need type context. Advisory output. The classifier's ordering (deterministi… |
| `agents-plugin/agents/search-replace.md` | haiku | The closing Grep proves no old-pattern matches remain. It does not prove the edits were correct. Over-replacement (`id` inside `width`, a substring of an unrelated identifier) passes that gate. The b… |
| `blueprint-plugin:blueprint-adr-validate` | needs-test | The verdict holds, but the reasoning is partly off. Step 3 domain analysis is a mechanical rule ('domain with multiple Accepted ADRs -> flag'), not judgment. The real risk is Step 2: the model itself… |
| `blueprint-plugin:blueprint-feature-tracker-status` | needs-test | Read-only display backed by blueprint-tracker-check.sh, which is a real deterministic gate on the statistics cache. Two risks to measure. First, the closing AskUserQuestion menu. Second, a risk the c… |
| `blueprint-plugin:blueprint-promote` | needs-test | The verdict and target are sound, but the rationale misdescribes the skill. It does not move or copy rule files. It resolves RULES_DIR, checks custom_overrides.rules, asks one AskUserQuestion confirm… |
| `blueprint-plugin:blueprint-status` | needs-test | Read-only with two schema-check scripts as gates, so needs-test is right. Effort should be medium, not low. Steps 2 and 6 list about 25 checks: content-hash comparison, per-task schedule status, ADR… |
| `blueprint-plugin:blueprint-sync-ids` | needs-test | Verified: the read-only audit is scripted (blueprint-sync-ids.sh). ID assignment is mechanical frontmatter insertion plus counter increments, and the manifest is jq-checkable. --link-issues creates G… |
| `code-quality-plugin:code-complexity` | needs-test | Verified: model: opus is pinned, and the body says 'Offload, Never Count By Hand' to lizard, radon and clippy. Hotspot ranking and refactor recommendations are light judgment, so measure report quali… |
| `code-quality-plugin:code-dead-code` | needs-test | Verified: the report path is three tool invocations plus a fixed severity table. --fix edits manifests, removes exports and deletes files after a judgment call on dynamic imports. One frontmatter mod… |
| `code-quality-plugin:code-dep-audit` | haiku | The report path is mechanical: code-dep-audit.sh emits STATUS= and the counts, and the model tabulates them. But --fix runs npm audit fix, cargo update and pip install --upgrade, which can rewrite lo… |
| `comfyui-plugin:comfy-cli` | haiku | CLI-wrapper guidance, but it drives a live systemd-managed install. Its main value is the 'What NOT to use here' list that keeps the CLI from fighting the systemd unit. The table also contains irreve… |
| `comfyui-plugin:comfy-metadata` | haiku | The core path is good haiku territory: run comfy_meta.py extract, summary or diff and report the result, which can be checked against the file. But the skill also directs library use for batch script… |
| `configure-plugin:configure-all/configure-all-check.workflow.js` | haiku-stage | 'The agent does no judgment of its own' overstates it. Each check agent invokes `/configure:<component> --check-only`, which expands a long prose skill. Only 5 of 42 configure skills ship scripts, so… |
| `configure-plugin:configure-coverage` | needs-test | The work is templated config edits across several frameworks. The exclusion and threshold choices are the judgment part. The skill is also a configure-all/select component, so the nested-invocation q… |
| `configure-plugin:configure-dead-code` | needs-test | Confirmed: the 'Entry points configured' check (line 72) and 'Create config file with entry points, exclusions, and plugins' (line 130) are per-project judgment. A wrong entry-point list hides real d… |
| `configure-plugin:configure-docs` | needs-test | The work is templated per language. The convention choice is less of a judgment call than the classifier suggests: line 149 already says 'google (or numpy for scientific projects)'. Generator setup s… |
| `configure-plugin:configure-editor` | haiku | This is broader than 'templates, easy to eyeball'. Steps 4-7 write .editorconfig and four .vscode JSON files, including per-language launch.json debug configurations. They also edit .project-standard… |
| `configure-plugin:configure-formatting` | needs-test | The Prettier-to-Biome and Black-to-Ruff migrations rewrite pre-commit and CI together. That is moderately complex multi-file editing. The 'dispatches_agents=true' note comes from an external manifest… |
| `configure-plugin:configure-gitattributes` | needs-test | The classifier's target cannot be implemented: skill `model:` applies to the whole skill, not to a step. The merge=union risk is smaller than stated. Step 3 (lines 72-76) puts every union mark throug… |
| `configure-plugin:configure-github-pages` | needs-test | Verified: the A/B/C 'no generator detected' menu exists (lines 60-70) and is a turn-ending interactive choice. The workflow output is templated and can be gated by actionlint, since the skill has Bas… |
| `configure-plugin:configure-gitignore` | haiku | On its own, this is the clearest Haiku task in the group. It is additive, idempotent, gated by `git check-ignore`, and makes no AskUserQuestion call. The open question is the nested caller. configure… |
| `configure-plugin:configure-justfile` | needs-test | The target 'haiku for --check-only, opus for --fix' cannot be implemented, because `model:` does not vary by argument. The classifier's $TOOLS_PLUGIN observation is accurate (line 107), and the skill… |
| `configure-plugin:configure-linting` | needs-test | The ESLint-to-Biome migration (lines 5 and 21) translates rule semantics across config, pre-commit and CI. Rules can drop silently, so this needs a measured run. |
| `configure-plugin:configure-makefile` | haiku | The classifier's gate does not exist. allowed-tools is `Glob, Grep, Read, Write, Edit, AskUserQuestion, TodoWrite` with no Bash, so the skill cannot run `make -n` or `make help`, and a missing litera… |
| `configure-plugin:configure-mcp` | needs-test | The target 'keep the server-trust choice on opus' cannot be implemented inside one skill. The trust concern is also overstated. `--server` names are validated against the curated registry in REFERENC… |
| `configure-plugin:configure-pre-commit` | needs-test | Verified: Step 3 is a five-repo release lookup via WebSearch/WebFetch (lines 62-70). That multi-fetch loop is where a weaker model would accept stale revs. The config edit itself is gated by `pre-com… |
| `configure-plugin:configure-reusable-workflows` | needs-test | The work is mostly copying fixed caller YAML. Verified: the category selection is a printed free-text prompt (lines 81-90), not AskUserQuestion. The skill has only Bash(mkdir *) and Bash(ls *), so it… |
| `configure-plugin:configure-skaffold` | needs-test | Verified: it creates the dotenvx secrets-generation hook (lines 22, 33-34) and fixes 0.0.0.0 binding. These are templated but security-relevant, so a regression must be measured before switching. |
| `configure-plugin:configure-workflows` | needs-test | The per-flag model split cannot be implemented. The classifier also misapplied version-pinning.md: that rule governs Renovate coverage of this repo's skill markdown, not the target repo's workflows.… |
| `configure-plugin:configure-worktreeinclude` | needs-test | It classifies gitignored files (.env, *.pem/*.key) into copy and skip sets, and a human confirms the result via AskUserQuestion (line 102). The copies stay local, which limits the blast radius. confi… |
| `documentation-plugin:claude-blog-sources` | needs-test | The classifier's mechanism claim is wrong. The skill sets `context: fork` and `agent: general-purpose` (lines 10-11), so a skill-level `model:` runs only the fork on Haiku and does not leak into the… |
| `documentation-plugin:docs-decommission` | haiku | The checklist template is fixed, but the output requires 'specific resource identifiers (not generic placeholders)' (lines 113, 121). That means discovering IAM roles, service accounts, DNS records a… |
| `documentation-plugin:docs-latex` | needs-test | pdflatex exit status gives a gate (lines 93-94), but TikZ visualisation choice and compile-error repair loops are judgment and long tool loops. It is disable-model-invocation: true, so it runs only w… |
| `documentation-plugin:docs-sync` | needs-test | Counts and stale-entry removal are mechanical. Category assignment (lines 79-83, with an 'Uncategorized' fallback) is the judgment step, and the edits land in CLAUDE.md and README catalog tables. |
| `finops-plugin:finops-waste` | needs-test | Verified: line 184, 'offer to edit the workflow file directly', with Edit in allowed-tools. Concurrency, path-filter and bot-guard edits change CI behaviour. |
| `foundryvtt-plugin:foundryvtt-module-scaffold` | haiku | The scaffold itself is deterministic: `scaffold.py` plus `--verify`, which emits STATUS= and exits 1 on ERROR. But 'After scaffolding' (line 142) lists implementing the module as step 1, and the trig… |
| `git-plugin:git-issue-hierarchy` | needs-test | It is user-invocable: true and self-contained, built from gh api calls with a fixed report shape. The risks the classifier names match the file: node-ID dependency endpoints, shared-relationship writ… |
| `git-plugin:git-issue-manage` | needs-test | It is user-invocable, mostly one gh call per issue, and AskUserQuestion is in allowed-tools. Transfer and bulk close are consequential, so the needs-test tier is correct. |
| `git-plugin:git-triage` | haiku-stage | git-triage.sh already does the mechanical half of Step 2: it emits ISSUE_<n>_REFS, AGE_DAYS and STALE_CANDIDATE. What remains is choosing which nouns to grep and reading the hits, and that is the jud… |
| `health-plugin:health-agentic-audit` | haiku | The checks are fixed patterns, but the run reads every SKILL.md and agent file (~410 skills) and matches each against REFERENCE.md patterns. That can cross the 100k-token price step and is long enoug… |
| `health-plugin:health-audit` | needs-test | Detecting the stack and comparing it to a plugin mapping is close to classification against a table. AskUserQuestion and Write/Edit on settings.json are in allowed-tools, so the 4.5-era failure mode… |
| `home-assistant-plugin:ha-validate` | haiku | It is user-invocable and script-driven, so it is a plausible fit. The parser gate is noisy, though: Step 1 calls yaml.safe_load, which raises 'could not determine a constructor' on every HA !secret/!… |
| `hooks-plugin:hooks-session-end-issue-hook` | haiku | With disable-model-invocation: true it is user-typed only, so the turn-scope concern does not apply. The core of the task is a JSON merge into an existing settings.json that must preserve other Stop… |
| `langchain-plugin:langchain-init` | needs-test | With disable-model-invocation: true it is user-typed only, and it follows a fixed bun/tsconfig/example-agent recipe. The classifier's details check out: the body uses bun while allowed-tools grants u… |
| `migration-patterns-plugin:black-to-ruff-format` | needs-test | It is pinned to model: sonnet, table-driven across Steps 1-6, and ends in pre-commit run ruff-format --all-files. AskUserQuestion appears only in allowed-tools, not in the body, and the classifier de… |
| `migration-patterns-plugin:flake8-to-ruff` | needs-test | It is a sonnet-pinned, table-driven config mapping with a pre-commit gate. The Step 6 judgment call is correctly identified. |
| `migration-patterns-plugin:mypy-to-ty` | needs-test | It is sonnet-pinned, key renames are mechanical, and pre-commit run ty is the gate. The dropped-overrides judgment is the risk to measure. |
| `obsidian-plugin:file-history` | needs-test | The file is a CLI reference, but history:restore and sync:restore overwrite the live note, and the newest=1 numbering in diff/history is easy to invert. The classifier's risks match lines 26, 66-72 a… |
| `obsidian-plugin:vault-files` | needs-test | The skill covers create with overwrite, move/rename (which rewrite links vault-wide when that setting is on) and `delete permanent` (irreversible). The path conventions the classifier cites are on li… |
| `obsidian-plugin:vault-frontmatter` | needs-test | This is bulk offline Edit work on user notes, driven by fixed rules. The skill also leaves real judgment calls: the daily-note exemption (line 112) and 'when in doubt about what a placeholder tag mea… |
| `obsidian-plugin:vault-tags` | haiku-stage | A haiku-stage verdict needs a stage to put on haiku. This body has no dispatch, which the classifier itself noted, so the verdict really prescribes a redesign. The skill has the same shape as vault-f… |
| `obsidian-plugin:vault-templates` | haiku | The classifier's main justification is that the output is checked by re-running the detection greps to zero. The skill never says that. A zero count would also be the wrong target: Templates/*.md mus… |
| `obsidian-plugin:vault-wikilinks` | needs-test | Detection is mechanical. The rewrites, however, need target selection, the never-auto-rewrite-ambiguous rule (line 98), alias preservation, and code-block and frontmatter exclusions (lines 108-110).… |
| `python-plugin:basedpyright-type-checking` | needs-test | The skill is a command and config reference. Choosing a mode and the strict rule overrides is moderate judgment, and an exit code alone does not validate that choice. Auto-invocation on 'setting up t… |
| `python-plugin:ruff-linting` | needs-test | The ruff check command forms are mechanical. Rule-set selection, fixable/unfixable choices and per-file ignores change lint policy repo-wide. The 'finding bugs' trigger also leads into fixing violati… |
| `python-plugin:typer-cli-completion` | needs-test | The skill inserts a templated `completion` subcommand plus tests into the user's CLI. It is a small, well-specified code change with a pytest gate, but complete_var naming fails silently (line 98). O… |
| `python-plugin:uv-advanced-dependencies` | needs-test | Confirmed in the file: git sources pinned by branch versus rev (lines 122-128) and ${PRIVATE_TOKEN} index URLs (line 188). Both are judgment calls that produce config, not a checked result. |
| `python-plugin:uv-project-management` | haiku | The uv commands themselves are mechanical. The description, though, fires on any mention of 'uv, managing dependencies, lockfiles, or pyproject.toml', and its When-to-Use claims 'authoring or editing… |
| `python-plugin:uv-run` | needs-test | Confirmed: the skill grants Write, Edit and NotebookEdit (line 8) and covers authoring PEP 723 headers and shebangs with no gate. Its 'running scripts' trigger also co-fires during ordinary coding tu… |
| `python-plugin:uv-tool-management` | needs-test | Confirmed: `uv tool uninstall --all` appears as an ordinary example (line 85), and tool installs change global state shared across projects. |
| `rust-plugin:cargo-machete` | haiku | The classifier itself found the hole: removing a re-exported dependency compiles locally, so `cargo check --all-targets` passes while downstream crates break. Step 3 (lines 56-65) is classification j… |
| `rust-plugin:cargo-nextest` | needs-test | Running and filtering are mechanical. The 'running tests' trigger, though, co-fires while the user is fixing failing Rust tests, and retries/slow-timeout config can hide real failures. |
| `session-plugin:session-spinup` | needs-test | The collector script is deterministic and the skill is a summary, which fits Haiku. The body, however, encodes many conditional rules about never presenting an unqueried zero as a clean state (Steps… |
| `taskwarrior-plugin:install-native-hooks` | needs-test | Confirmed: there are 2 AskUserQuestion references, a fixed install-hooks.sh call with --check, --uninstall and install modes, and a scratch-store TASKDATA smoke test. AskUserQuestion formatting is ex… |
| `taskwarrior-plugin:task-add` | needs-test | Confirmed: the prefix-match trap (line 74), duplicate handling (line 126), and `gh issue create`, which is outward-facing (line 149). |
| `taskwarrior-plugin:task-bulk-ops` | needs-test | Confirmed: the stdin-consumption and renumbering foot-guns (lines 60-101) fail silently, closing part of the set while reporting success. That is a multi-step tool loop, exactly what the rubric says… |
| `taskwarrior-plugin:task-claim` | needs-test | Confirmed: SlashCommand `/git:coworker-check --claim` with a script fallback (lines 100-105), start before modify (line 125), and the --force takeover branch. A read-back through task export can veri… |
| `taskwarrior-plugin:task-coordinate` | haiku | The classifier is right that it is read-only and that ranking is a deterministic jq sort_by urgency. But the output is the dispatch plan for a parallel-agent wave: an orchestrator acts on it with no… |
| `taskwarrior-plugin:task-reconcile` | needs-test | The file matches the classifier's description. reconcile.sh classifies every task (live / issue-closed / pr-merged / pr-closed), keeps uncertain refs open, and performs the --apply. The model only re… |
| `taskwarrior-plugin:task-release` | needs-test | The verdict is right, but one stated risk is misattributed. The handoff message is either passed in as an argument (written by the caller before the pin takes effect) or collected from the user throu… |
| `terraform-plugin:tfc-plan-json` | needs-test | The verdict is right; one stated risk does not depend on the model. Sensitive before/after values reach the transcript whatever model runs, because the jq recipes print them. The real risk is reading… |
| `terraform-plugin:tfc-run-logs` | haiku | Fetching the logs is mechanical, but the skill's stated use cases are 'Debugging a failed plan or apply by inspecting log lines' and 'Use when debugging failed plans/applies'. The pin covers the rest… |
| `testing-plugin/agents/test-runner.md` | haiku | Read-only and mostly mechanical, and the verbatim runner-line requirement limits fabricated summaries. Two things fall short of the 'haiku' bar. The framework-choice trap the file documents (measured… |
| `testing-plugin:odiff-image-diffing` | haiku | The exit code (0/21/22/1) is a real deterministic gate. However, this is a user-invocable:false reference skill invoked partway through UI work ('Validating that a CSS or template change is visually… |
| `testing-plugin:test-focus` | haiku | Running the test is mechanical and gated by its exit code. The skill exists for 'Iterating on a single failing spec' and is model-invocable, so in a fix loop the model runs it and then edits code in… |
| `testing-plugin:test-full` | needs-test | Needs-test is the right tier, but the target is wrong. Changing the shared test-runner frontmatter pin would also move every other caller to Haiku, and check-agent-model.sh would have to change for e… |
| `testing-plugin:test-report` | haiku | No script backs this report. Several cache locations in its table (node_modules/.vitest, target/debug) hold no parseable pass/fail counts. Most frameworks keep no run history for the --history and --… |
| `tools-plugin:deps-install` | haiku | Detecting the package manager and running the install are mechanical. The body's Post-install Actions, however, run /code:lint (which can auto-fix code) and /test:run inside the same turn, so they wo… |
| `tools-plugin:justfile-expert` | needs-test | The file does carry the traps the classifier names: unquoted {{...}} word-splitting, --list showing only the last comment line, and comment binding by adjacency. Authoring a recipe is usually the who… |
| `typescript-plugin:biome-tooling` | needs-test | Choosing what to migrate, and which plugin-only ESLint rules to keep, is the judgment part. biome ci gives an exit-code gate for the rest. Measuring this is reasonable. |
| `typescript-plugin:bun-test` | haiku | Running bun test is gated by its exit code. But the skill is model-invocable and is called inside TDD and fix loops, where the same turn continues into code edits. The pin would carry those edits ont… |

## Rejected candidates (`keep`)

These are the classifier's non-`keep` verdicts that the verifier overturned.
Most failed on the turn-scope leak. The rest are open-ended review, security
triage, or multi-file editing.

| Artefact | Haiku said | Verifier |
|---|---|---|
| `.github/workflows/obsidian-cli-changelog.yml` | needs-test | This is complex agentic editing, not a bounded transformation. It diffs a fetched doc against 14 skills, edits SKILL.md files in place, may create a whole new skill and update README, plugin.json and… |
| `agent-patterns-plugin:mcp-management` | needs-test | user-invocable: false reference skill that auto-loads mid-debugging. Its payload is troubleshooting (OAuth, a stale cached git source, list_changed) and editing .mcp.json, which is a protected file.… |
| `agents-plugin/agents/dependency-audit.md` | needs-test | The tabulation is mechanical, but the deliverable is a vulnerability triage: ranking CVEs by exploitability (RCE, auth bypass, injection), judging licence risk, and filling a 'Breaking Changes' colum… |
| `blueprint-plugin:blueprint-derive-tests` | haiku-stage | The classifier misread the file. current_model is opus, not unset. The proposed stage, Step 4 commit classification, is already owned by scripts/blueprint-derive-tests.sh: the fix/feat split, inline-… |
| `blueprint-plugin:blueprint-init` | needs-test | Not 'mostly Bash and Write'. Step 2 auto-detects the requirements source by content analysis. Step 3 measures cross-reference density and then classifies, moves and renames existing docs, which break… |
| `blueprint-plugin:blueprint-rules` | needs-test | The classifier missed two branches. Step 6 'Generate rules from PRDs' is the same synthesis as blueprint-generate-rules, which the control sample keeps. Step 7 'Sync rules with CLAUDE.md' splits, con… |
| `blueprint-plugin:blueprint-sync` | haiku-stage | The skill dispatches no subagent, so there is no stage to put on haiku. The status scan the classifier names is already deterministic shell (jq to_entries plus sha256sum compares), and adding an agen… |
| `blueprint-plugin:confidence-scoring` | needs-test | user-invocable: false knowledge skill loaded by blueprint-work-order and blueprint-autopilot. A skill-level model: haiku would downgrade those consumers while they author PRPs and work orders. The sc… |
| `code-quality-plugin:ast-grep-search` | needs-test | user-invocable: false reference skill that auto-loads during code search and structural rewrites inside larger coding tasks. It already carries effort: low, which captures the cheap part. A model: ha… |
| `comfyui-plugin:comfy-conditionals` | needs-test | Node-choice reference that auto-loads while the agent builds or edits a workflow graph. A skill-level model: haiku would switch the surrounding graph-authoring turn, not just a lookup. The classifier… |
| `comfyui-plugin:comfy-debug-preview` | haiku | A reference table of display nodes, consulted while wiring a workflow graph. The rubric's 'single-file lookup' case does not fit: setting model: haiku here downgrades the agentic JSON-editing turn th… |
| `comfyui-plugin:comfy-flow-control` | needs-test | Routing-choice reference (lazy vs eager switches, broadcast, loops) loaded during graph authoring. Per the classifier's own risks, wrong picks are silent and can hang the queue. A model: haiku would… |
| `comfyui-plugin:comfy-image-utils` | haiku | Node-choice reference consulted inside workflow construction, so the model switch would hit the surrounding graph edit. 'Errors are visible' holds only for some choices. The classifier's own latent-a… |
| `comfyui-plugin:comfy-math-strings` | haiku | Expression and string-node reference used while assembling graphs. The classifier itself notes that MathExpression errors appear only in the server log and that a wrong value can pass silently. That… |
| `comfyui-plugin:comfy-subgraphs-app-mode` | haiku | Feature reference and packaging decision (subgraph, Blueprint snapshot, App Mode) used while restructuring a workflow. It is a design call inside an authoring task, not a bounded mechanical run. The… |
| `communication-plugin:google-chat-formatting` | haiku | The conversion is mechanical, but the skill is user-invocable: false. The model loads it partway through a turn, usually one where it is also drafting the status update or notes. `model:` is turn-sco… |
| `configure-plugin:configure-select` | needs-test | This is an orchestrator, not a leaf skill. Step 4 runs every selected `/configure:X` via SlashCommand and offers `--fix`, which can include linting and formatting migrations, configure-security and m… |
| `container-plugin/agents/container-build.md` | needs-test | The work is open-ended terminal debugging: diagnose the failing layer, `docker exec` into running containers, inspect state, then Edit/Write Dockerfiles with optimization judgment. Terminal-Bench, Ha… |
| `css-plugin:lightning-css` | needs-test | This is a user-invocable: false reference skill. The model loads it partway through frontend or build work. A turn-scoped `model: haiku` would hand the rest of that coding turn to Haiku, and agentic… |
| `css-plugin:unocss` | needs-test | The reasoning is the same as for lightning-css. This user-invocable: false reference (363 lines) is loaded mid-task during frontend coding, so a turn-scoped override would downgrade the surrounding i… |
| `documentation-plugin:docs-fetch-fallbacks` | haiku | The ladder itself is mechanical. The problem is when it fires: the model invokes it in the middle of research or implementation, at the moment a WebFetch fails. A turn-scoped `model: haiku` would dow… |
| `finops-plugin:github-actions-cache-optimization` | needs-test | This is a user-invocable: false reference that carries bulk DELETE recipes and key-strategy judgment. The model loads it mid-investigation, so a turn-scoped override would downgrade that investigatio… |
| `finops-plugin:github-actions-finops` | needs-test | This is a user-invocable: false reference. Its Step 4 synthesis reads workflow YAML by hand and must avoid the net-vs-gross trap. Loaded mid-task, a Haiku override would cover the whole cost investig… |
| `git-plugin:gh-cli-agentic` | needs-test | This user-invocable: false reference is loaded in almost every session that touches PRs, runs or issues, usually in the middle of larger work. A turn-scoped Haiku override here would downgrade a larg… |
| `git-plugin:gh-workflow-monitoring` | haiku | This user-invocable: false reference is loaded while waiting on CI after a push, typically mid-way through a fix-and-push loop. With `model: haiku`, Haiku would also handle the failure diagnosis and… |
| `git-plugin:git-branch-naming` | haiku | Picking a prefix is trivial, but this user-invocable: false reference is loaded when a branch is created, which is at the start of implementation work. A turn-scoped `model: haiku` would then run the… |
| `git-plugin:git-cli-agentic` | needs-test | This user-invocable: false porcelain reference is loaded mid-task by any git-heavy work, so the same turn-leak applies. The classifier's `git add -A` finding is correct (line 263 contradicts the expl… |
| `git-plugin:git-commit-trailers` | haiku | This user-invocable: false reference is loaded during commit composition, mid-turn. As the classifier itself notes, Release-As and BREAKING CHANGE trailers drive release-please version bumps, so a wr… |
| `git-plugin:git-commit` | needs-test | Frontmatter sets user-invocable: false. Lauri's decision-defaults tell agents to commit proactively at natural checkpoints mid-work. So this skill fires partway through long multi-step turns, and a H… |
| `git-plugin:git-coworker-check` | needs-test | The body (lines 31-45) makes this a required up-front precondition that orchestrators run before bulk-edit and commit loops, so it is invoked in the middle of larger tasks. skill-development.md descr… |
| `git-plugin:git-pr-sync-check` | haiku | The description reads 'Use when continuing work on a PR branch before adding commits', so it is a model-invoked precondition run just before the real coding work. Under a turn-scoped model: override,… |
| `git-plugin:git-push` | needs-test | It has user-invocable: false and is model-invoked inside commit→push→PR chains. A turn-scoped haiku pin would carry into PR-body writing, which is outward-facing prose. It also decides force-push and… |
| `git-plugin:git-repo-detection` | haiku | This is a user-invocable: false reference skill (sed/awk owner/repo recipes) that the model loads in the middle of other GitHub work. There is no standalone execution for Haiku to take over. A turn-s… |
| `git-plugin:git-upstream-fix-check` | needs-test | It is model-invoked as a precondition before patching vendored code, so a turn-scoped haiku pin would carry into the patch work that follows. Its output is a stale/active and patch-vs-upgrade judgmen… |
| `git-plugin:github-issue-autodetect` | needs-test | It has user-invocable: false and runs inside the commit flow, so a frontmatter pin would also cover the commit composition. Its output becomes Fixes/Closes keywords that auto-close issues on merge, w… |
| `git-plugin:github-labels` | haiku | It is a 91-line user-invocable: false gh label reference, loaded while the model creates a PR or issue. It has no execution of its own. A turn-scoped model: haiku would move the surrounding PR/issue… |
| `git-plugin:github-pr-title` | needs-test | It has user-invocable: false and is loaded during PR creation, so a pin would carry into the PR body. The feat/fix choice sets the release-please bump on squash merge, and nothing checks it before me… |
| `github-actions-plugin:actions-billing-usage` | needs-test | The file is a trap catalogue promoted from a rule: a 410 endpoint, net vs gross, per-month windowing, per-job rounding. Its value is reading the numbers correctly before a cost decision. The classifi… |
| `github-actions-plugin:github-actions-inspection` | needs-test | It has user-invocable: false and is model-invoked during CI debugging, so the diagnosis and the fix that follow would inherit a turn-scoped pin. The 'log-extraction stage only' target names a stage t… |
| `github-actions-plugin:github-issue-search` | needs-test | It has user-invocable: false and is auto-invoked during debugging of an unrelated failure. The classifier flags the session-switch risk itself and still offers a haiku target. Whether an upstream wor… |
| `github-actions-plugin:release-artifact-verification` | needs-test | It is adversarial verification whose job is to refuse a false green: shadowed source trees, split publish jobs, vacuous docker smoke tests. The body is four trap sections plus a litmus test, with no… |
| `health-plugin:health-check` | needs-test | The description reads 'names the broken layer' and 'the install misbehaves and the cause is unknown', which is open-ended diagnosis. Step 2 fans out across scopes and Step 4 delegates to other skills… |
| `home-assistant-plugin:ha-automations` | needs-test | It is a user-invocable: false authoring reference with Write/Edit, loaded while the model writes automations that drive physical devices. A turn-scoped pin would put the whole authoring turn on Haiku… |
| `home-assistant-plugin:ha-configuration` | needs-test | It is a 377-line user-invocable: false reference used during configuration.yaml edits, where a mistake stops Home Assistant at startup. These are multi-block edits under a model-invoked reference ski… |
| `home-assistant-plugin:ha-entities` | needs-test | It is a user-invocable: false reference with Write/Edit for template entities, whose errors appear only at runtime. It has the same model-invoked mid-task problem as the other HA authoring skills. Ke… |
| `hooks-plugin:hooks-session-start-hook` | needs-test | It generates an executable install script that runs unattended on every remote session start, and the stack detection and frozen-lockfile choices are judgment. That is code authoring with no gate bey… |
| `kubernetes-plugin:argocd-login` | haiku | It has user-invocable: false and is set to auto-invoke 'when authentication errors occur when using ArgoCD commands', which is mid-task. The body continues into post-login operations, including argoc… |
| `networking-plugin:dns-tools` | haiku | It is a user-invocable: false lookup reference, loaded during DNS or connectivity debugging that is usually part of a larger task, so a turn-scoped pin would carry into that work. The classifier's ow… |
| `networking-plugin:interface-state` | needs-test | It has user-invocable: false, and its trigger table covers mutating ip addr/route changes on live hosts. Frontmatter cannot split read-only from mutating paths, and a model-invoked reference skill sh… |
| `networking-plugin:network-diagnostics` | haiku | It is a 419-line user-invocable: false troubleshooting reference whose job is to interpret path loss, jitter and route problems, which is diagnosis the main loop acts on. It is loaded mid-task, so th… |
| `networking-plugin:network-monitoring` | needs-test | Its trigger table includes 'Identify unexpected outbound connections'. That is security triage, which the house rule sends to Opus and which carries Haiku 5.5's stricter safeguard-refusal risk. It is… |
| `obsidian-plugin:bases` | haiku | It is a user-invocable: false CLI reference loaded during vault work, with no standalone execution to hand to Haiku, and a turn-scoped pin would carry into the surrounding vault task. Its Common Patt… |
| `obsidian-plugin:bookmarks` | haiku | Bookmarks are low-stakes and reversible, so the task itself would suit Haiku. The pin is still the wrong mechanism, because this is a model-invoked reference card and a turn-scoped override would app… |
| `obsidian-plugin:command-palette` | haiku | It has user-invocable: false and is model-invoked. 'obsidian command id=' runs arbitrary plugin commands against the active editor with no file= target, a hazard the classifier found itself. A turn-s… |
| `python-plugin:pytest-advanced` | needs-test | The triggers are 'implementing test infrastructure, writing fixtures'. The work this skill accompanies is designing conftest hierarchies, fixture scopes, parametrization and async tests across files.… |
| `python-plugin:python-code-quality` | haiku | This 68-line routing index has almost no work of its own to make cheaper. Its description fires on any mention of 'linting, formatting, type checking, or Python code style', so model: haiku would mov… |
| `python-plugin:python-testing` | needs-test | It triggers on 'writing Python tests' and covers the TDD red-green cycle, which writes both tests and implementation. That is agentic coding. The classifier's own risk, that Haiku-written tests can p… |
| `python-plugin:vulture-dead-code` | needs-test | The triggers are 'cleaning up codebases or removing dead code'. Running vulture is one command and not worth splitting into a stage. The skill's value is deciding which reported symbols are truly dea… |
| `testing-plugin:playwright-cli` | needs-test | This is a multi-turn snapshot, ref-pick, interact loop with no failure signal on a wrong click, and Haiku trails Sonnet on OSWorld (72.4 vs 83.9). It is a reference skill invoked partway through deve… |
| `testing-plugin:test-tier-selection` | needs-test | This is a pure reference decision table with no execution of its own. Its Activation Triggers say it 'auto-activates ... After code modification by Claude', so a frontmatter pin would move ongoing co… |
| `tools-plugin:d2-diagrams` | needs-test | The skill is invoked partway through an explanation or a doc, because a diagram is how a relationship-heavy answer gets delivered. The d2 compile gate only checks syntax: a compiling diagram that mis… |
| `tools-plugin:fd-file-finding` | haiku | This is a generic user-invocable:false reference skill ('searching for files by name...across directories') that is a sub-step of almost any task. The pin would move the caller's remaining reasoning… |
| `tools-plugin:hf-downloads` | needs-test | The body tells apart several failure classes from error text: xet staging ENOSPC, the HF_HOME token-path divergence, and three gated-repo conditions. A wrong call fills the root disk, and once root i… |
| `tools-plugin:jq-json-processing` | haiku | This is a generic reference skill ('parsing JSON files, filtering arrays/objects, transforming structures') that loads as a sub-step of API, CI and debugging work. A pin would hand the remaining anal… |
| `tools-plugin:mermaid-diagrams` | haiku | mmdc only gates syntax. In practice the skill is invoked to author diagrams embedded in GitHub Markdown, PR bodies and docs, which is outward-facing content. The body has Architecture and API Flow au… |
| `tools-plugin:nushell-data-processing` | needs-test | The classifier correctly notes a niche DSL and plausible-but-wrong aggregations with no gate. In addition, this is a reference skill used as an analysis sub-step (version cross-referencing, log aggre… |
| `tools-plugin:rg-code-search` | haiku | The description reads 'Use when searching for text patterns, code snippets, or doing multi-file analysis'. Code search is the opening sub-step of most debugging and coding turns, and the pin lasts fo… |
| `tools-plugin:yq-yaml-processing` | haiku | The skill makes in-place yq -i edits to Kubernetes manifests and GitHub Actions workflows, usually as a sub-step of larger infra or CI changes. A wrong element in a multi-document file is silent unle… |
| `typescript-plugin:bun-development` | haiku | This is a broad user-invocable:false reference skill covering run, watch, test config, bundling and project scaffolding. It loads during general Bun development, so a pin would move the coding turn t… |
| `typescript-plugin:bun-package-manager` | needs-test | A broad reference skill (install, add, remove, update, workspaces, conflict debugging) that loads partway through dependency work. Its Error Handling section defaults to 'bun install --force', which… |
| `typescript-plugin:knip-dead-code` | needs-test | Edit and Write are used to delete exports and files across the codebase. Those are multi-file code edits where knip's false positives (dynamic imports, public API) need judgment, and the classifier's… |
| `typescript-plugin:typescript-strict` | needs-test | The classifier's own rationale says the strict migration 'is complex agentic editing', and the rubric sends that to keep. noUncheckedIndexedAccess and exactOptionalPropertyTypes fixes span many files… |
| `workflow-orchestration-plugin:workflow-preflight` | needs-test | The description reads 'Use when starting an issue or fix'. The model invokes it at the start of implementation turns, and the pin would carry the whole implementation onto Haiku. preflight.sh already… |

## GitHub workflows

**This repo.** No invoking workflow moves. `check-workflow-model.sh` still
requires `--model opus`; only its stale "Haiku supports no effort" wording
changed. `obsidian-cli-changelog` is `keep` because it does multi-file skill
edits and opens PRs. The five candidates are `plugin-pr-checks`,
`release-pr-doc-audit`, `scheduled-audits`, `research-radar` and
`skill-splitter`. Each needs a run replayed against the opus output before a
flip. `plugin-pr-checks` is a REQUIRED check, so an `error_max_turns` on a
weaker model would fail PRs. For it and `release-pr-doc-audit`, the verifier
recommends scripting the deterministic checklist items first.

**`laurigates/.github` reusable workflows.** No defaults change. The sonnet
defaults on `reusable-a11y-aria`, `reusable-quality-code-smell` and
`reusable-quality-typescript` are `needs-test` against a seeded fixture. For
TypeScript, the grep-able tier (explicit `any`, `@ts-ignore`) should become a
deterministic pre-step first. The security workflows (`secrets`, `deps`,
`owasp`) stay off haiku: Haiku 5.5's stricter cyber safeguards risk refusals,
and the house rule sends security review to Opus. None of the reusable Claude
workflows has an `effort` input, so a model flip there has no cost lever to
pair with.

## Incidental defects

The classifiers found these while reading. The verifiers confirmed them, and
the first four were re-checked against the files for this report. They are
pre-existing and do not depend on the model.

- `git-plugin:git-cli-agentic` line 263 recommends `git add -A`, against the
  explicit-paths rule.
- `blueprint-plugin:blueprint-docs-list` line 88 uses `${doc_type^^}`, which is
  bash 4 only and a bad substitution in zsh.
- `tools-plugin:generate-image` ships `{{arg:1}}` placeholders that nothing
  renders.
- `networking-plugin:dns-tools` grants `dig`/`nslookup`/`host`/`whois` while
  its examples run `dog` (52 times). `network-diagnostics` and
  `network-monitoring` have the same kind of grant mismatch.
- `configure-plugin:configure-justfile` line 107 uses an undefined
  `$TOOLS_PLUGIN`. A fallback is documented at line 113.
- `langchain-plugin:langchain-init` runs bun, but its `allowed-tools` grants
  uv/pip/python.
- `home-assistant-plugin:ha-validate` maps the `!secret`/`!include`
  constructor error to "check YAML indentation".
- `testing-plugin:test-report` ships example numbers in its output template
  and has no script behind it.
- `terraform-plugin:tfc-run-status` has a poll loop with no deadline.

## Open

- **Measure `AskUserQuestion` on Haiku 5.5.** It gates the largest
  `needs-test` cluster, and the lint keeps banning the pair until a
  measurement says otherwise.
- **Replay the five local workflow candidates and the three reusable sonnet
  defaults,** and add an `effort` input to the reusable Claude workflows.
- **Fixture-sweep `test-runner` and `search-replace`** before any agent
  frontmatter moves. `check-agent-model.sh` still requires opus.
- **The user-global rule `agent-and-tool-selection.md`** (dotfiles) says to
  re-run its comparison when Haiku 5.5 ships. This sweep is a classification
  comparison, not that rule's graded task comparison, so the global rule is
  unchanged.

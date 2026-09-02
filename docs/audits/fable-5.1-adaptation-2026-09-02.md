# Claude Fable 5.1 adaptation sweep — 2026-09-02

Findings-and-decisions record for the sweep that checked this repo (and, in the
same session, `laurigates/dotfiles` and `laurigates/repos-claude-config`)
against Claude Fable 5.1, released 2026-09-01. The edits landed in the PR that
adds this file; this document records the sources, the method, what was
decided, and what was left open.

## Sources

- Claude Fable 5.1 & Claude Mythos 5.1 System Card (Anthropic, 2026-09-01) —
  §1.1 (June 2026 knowledge cutoff), §5.2 (prompt-injection robustness; auto
  mode as the default permission mode in Claude Code), §6.1.2 (key alignment
  findings), §6.2.1 (internal deployment monitoring: classifier and hook
  workarounds), §8.13 (multi-agent harness results).
- Claude Platform release notes 2026-09-01 (model launch, `tool_choice`
  restrictions, preserved thinking, per-message effort, turn-scoped system
  messages, `thinking.display: "updates"`).
- The bundled `claude-api` skill's `shared/model-migration.md` (§ Migrating to
  Claude Fable 5.1, § …from Claude Fable 5) and `shared/prompt-audit.md`.
- Claude Code changelog 2.1.232–2.1.257, `model-config`, `sub-agents`,
  `skills`, `tools-reference` (§ Task tool availability), `env-vars`.

## Method

Fifteen scoped finder agents (two lenses: factual currency and Fable-fit per
the prompt-audit anti-pattern groups) over the three repos, then two
adversarial verifier lenses per batch of findings (factual refuter; keep-list /
scope refuter — a finding survived only if neither refuted it), then a
completeness critic.

| Stage | Count |
|---|---|
| Raw findings | 265 |
| After dedup | 248 |
| Confirmed by both verifiers | 171 (claude-plugins 132, dotfiles 38, repos-claude-config 1) |
| Refuted | 77 |
| Critic additions (reviewed by hand, verifier budget exhausted) | 17, of which 9 applied |

## What the sweep found (claude-plugins)

- **Dated rationale, not dated policy.** The opus-for-subagents standard rests
  on a measurement taken on Opus 4.8 vs Sonnet 4.6. The aliases now resolve to
  Opus 5 / Sonnet 5 and effort level names do not map across generations, so
  the rules now name the measurement as historical and point to the Tier 2
  sweep in `skill-evaluation.md` for re-verification.
- **The cost lever gained a frontmatter home.** Both subagents and skills carry
  `effort:` (`low|medium|high|xhigh|max`, default inherits). Several rules
  stated that effort was "not expressible in frontmatter"; those sentences were
  the load-bearing premise of the "don't tag `model: sonnet`" advice and were
  rewritten. `check-agent-model.sh` validates the field.
- **`fable` is a model value.** Agent and skill `model:` accept `fable`
  (2.1.255+). Field references, the meta-audit skill, and the guard were
  updated.
- **Task-tool availability (2.1.233+).** `TodoWrite`/`TaskCreate`/… are left
  out on Opus 4.8 / Sonnet 5 / Fable unless the session opts in. The corrected
  semantics (opt-in via `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`, or naming a task tool
  in `--allowedTools`/`--tools`; always present on the web and in background
  sessions; subagents inherit the parent session's availability) live in
  `.claude/rules/agentic-permissions.md` § Standard Permission Sets. The first
  verified draft called the workflow `--allowedTools … TodoWrite …` grants
  inert and proposed deleting them; the tools reference shows that grant is the
  opt-in, so the grants stay and only the prose was corrected. Recorded here
  because verifiers accepted the wrong premise.
- **`[1m]` conditions invert on Fable.** Fable 5.1 is 1M-context by default with
  no suffix, so "unless on a `[1m]` model" guards (parallel-fan-out rate-limit
  caveats in adversarial-review, execution-grounded-review,
  parallel-agent-dispatch, skill-fork-context) read as "does not apply" on the
  model most likely to run many verifiers. Reworded to "1M-context session".
- **Background-by-default and forking.** Non-teammate spawns run in the
  background by default and `subagent_type: "fork"` inherits the whole
  conversation (2.1.232). cold-read-gate and execution-grounded-review, whose
  premise is a context-starved reader, now say so explicitly.
- **Hook events.** `PreModelSwitch` / `PostModelSwitch` (2.1.251) added to the
  hooks reference; with classifier fallback routing on Fable (cyber → Opus 4.8,
  bio → Opus 5) a model switch is now something a hook may need to observe.
- **System-card findings encoded as rules.** `handling-blocked-hooks.md` now
  says a block is on the hazard, not the spelling (do not re-issue a blocked
  operation in a different form), and never to restate authorization the user
  did not literally give — the two rare workaround shapes §6.2.1 reports.

## Decisions

- **Subagent model floor.** `model: opus` stays the committed floor for plugin
  agents (every plan has Opus; Fable is no plan's default and costs 2x per
  token). `model: fable` is sanctioned for the hardest delegated reasoning and
  accepted by `scripts/check-agent-model.sh`. `inherit` is not used for plugin
  agents because it would also inherit Sonnet/Haiku sessions below the floor.
  `effort:` is the cost lever.
- **Workflow model pins stay `opus` + explicit effort.** The economics are
  restated as a historical measurement; the monthly workflow-model audit is the
  re-verification.
- **Evaluation matrix.** Stored baselines stay pinned to the IDs they ran on;
  new sweeps pin the IDs actually run and the effort level beside each.

## Left open

- Whether to switch the user-global default from Opus to Fable for the hardest
  delegated work is a cost decision for the owner; the rules only sanction it.
- `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` in the user-global settings overlay
  (dotfiles): Fable 5.1 performs notably better with a memory surface
  (migration guide, "Give it a memory surface"). Not changed; surfaced.
- The evaluation matrix has not been re-run on Fable 5.1 / Opus 5 / Sonnet 5;
  `skill-evaluation.md`'s "new model released → Tier 2 sweep" trigger is due.
- `accessibility-plugin/README.md` documents an `### Agents` section for agents
  the plugin does not ship (critic finding, unrelated to Fable; not changed).

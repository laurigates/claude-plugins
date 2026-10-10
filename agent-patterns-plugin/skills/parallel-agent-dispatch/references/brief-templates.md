# Parallel Agent Dispatch — Brief Templates and Verification

Templates and evidence for writing a *brief*: the refactor/bulk-edit brief
shape and its context-budget clause, the completion manifest, the
verbatim-patch discipline for what the orchestrator must paste, stage
authority in multi-stage pipelines, and the two verification passes (the
agent's own, and a separate reviewer's). Entry point: [`../SKILL.md`](../SKILL.md)
§ Scope Budget / § Agent self-verification / § Reviewer-agent verification.

## Refactor-brief template

For bulk content rewrites (description tightening, naming sweeps), use the
brief shape that worked across six concurrent refactor agents. Load-bearing:
per-step ordering, a PRECIOUS list, and a per-file cap.

```markdown
**Scope**: <glob>, capped at N files. Do NOT chain edits across files
you have not Read in this run.

**Procedure (per file)**: Read first, then propose, then Edit.
No batch-rewrites across unread files.

**PRECIOUS — preserve verbatim**: literal "Use when..." triggers,
sibling-skill cross-references, tool names, negative-scope clauses.

**Cut**: marketing prose, redundant restatement, adjective stacking.

**Completion manifest** (closed-list assignments — symbols to delete,
files to touch): end your final message with a machine-checkable
manifest enumerating each item you actually completed, one
`VERB: <item> (<location>)` line per item, plus `ASSIGNED: N` /
`COMPLETED: M`. The orchestrator diffs it against the assignment.

**Budget**: finish well within your context window. If the scope
grows past what you can finish without compacting, stop and return the
Return Contract now: `status: partial`, `Scope delivered`, `Deferred /
skipped`, files touched (`commits` + `worktree`), and the next step in
`Orchestrator action needed`. Budget overrides the Final step: on an
early stop, run the regression script once, report its result in the
Return Contract, and do not loop.

**Final step**: run `<repo regression script>`; loop until exit 0
before emitting the Return Contract.
```

The **Budget** clause bounds the agent by task size, because no agent
frontmatter field caps a subagent's context or tunes its compaction
(`.claude/rules/agent-runtime.md` § Subagent context budget). It reuses the
Return Contract fields from [dispatch-contract.md](dispatch-contract.md) as the
state packet and adds none. Scope each brief to finish well under half the
window, and check the returned packet against the branch and diff rather than
trusting it.

> Evidence: `experiments/subagent-compaction/README.md` (#2818) — one
> 200k-window subagent auto-compacted at ~75% and returned its compaction
> summary as a false completion report. Whether 1M-window subagents compact
> and resume correctly (Q1–Q2 there) is still open, and the clause's own
> effect is unmeasured. The report check costs almost nothing either way.

> Evidence: issue [#1279](https://github.com/laurigates/claude-plugins/issues/1279)
> — six agents, 41 plugins, cleanest batch hit 28.9% reduction with zero
> >250-char outliers. PR #1314 productizes the post-pass.

**Mechanical-batch self-reports are never trusted alone.** For a
closed-list deletion/rewrite batch, the agent's own report — manifest
included — is a *claim*, not a verification. The orchestrator runs the
**authoritative checker** (`knip` / build / test) after the agent
returns and diffs the manifest against the assignment; an item on the
manifest that the checker still finds present is a silent
under-delivery. This complements Pillar 4 (the agent's own final
verification step) and Pillar 5 (a separate reviewer agent): the
manifest makes the orchestrator's post-run diff mechanical instead of a
re-derivation. Cap the per-agent batch so an early stop costs little —
see the refactor agent's batch-size guidance.

> Evidence: issue [#1601](https://github.com/laurigates/claude-plugins/issues/1601)
> — a `refactor` agent assigned ~23 symbols across ~11 files completed
> only ~5 before stopping; the shortfall was invisible from its
> (truncated) self-report and surfaced only when the orchestrator re-ran
> `knip` and saw ~18 assigned symbols still present.

## Verbatim patches — detail and rationale

Agents should emit:

- Complete CMake / build-manifest blocks with surrounding context, ready
  for `Edit(old_string=…, new_string=…)`.
- Full justfile / Makefile recipes including shebang and every parameter.
- Literal prose paragraphs for docs updates — tracker evidence strings,
  plan bullets, format-spec paragraphs — not "update the port plan with
  findings about X."
- Exact line numbers where the orchestrator must insert, when the target
  is long.

If the edit is a single-line insertion, still quote the surrounding 2–3
lines so the paste target is unambiguous. The orchestrator's role for
`Orchestrator action needed` is `Edit(old=…, new=…)` — a mechanical
operation, not prose synthesis. Brief agents accordingly.

### Agent authors the docs-update text the orchestrator pastes

The paired discipline: **the agent writes the final prose** for any docs
update its slice requires. Port-plan sub-bullets, feature-tracker evidence
strings, and format-spec paragraphs all belong in the agent's return
contract as finished sentences, ready to paste. The orchestrator's job
stays pure `Edit(old=…, new=…)` — no prose synthesis, no re-summarising
of what landed.

Evidence-strings in particular need agent authorship: the agent is the
only party that knows what actually landed in its commits, which test
cases passed, and which subtleties of the slice are worth recording.
Asking the orchestrator to compose that prose retroactively forces it to
re-read the agent's diff and produces a less faithful summary than the
agent could write inline.

> **Why this matters.** Across six sequential waves in a single session,
> every return that emitted verbatim patches paste-integrated cleanly in
> seconds. One earlier return that used prose ("add `src/foo.c` to
> `CMakeLists.txt`") forced the orchestrator to re-derive the exact
> insertion context — measurably slower and more error-prone. The
> verbatim-patch + agent-authored-prose pairing, not the parallel
> topology, is what made the multi-wave cadence sustainable.

## Bulk-edit self-verification — worked example

> **Evidence (2026-05-09 cascade).** Six refactor agents shortened
> descriptions across 41 plugins. Each agent believed it was preserving
> "Use when..." triggers, but 4 of the 6 silently introduced "Use to..."
> or "Use for..." variants that do not match the
> `audit-skill-descriptions.py` regex. The aggregate damage (68
> `NO_TRIGGER` skills) only surfaced when pre-commit ran on the
> mega-commit — a single fixer-agent pass repaired them, but only because
> pre-commit forced the issue. If each refactor agent had run
> `audit-skill-descriptions.py --strict-all` as its last step and looped
> on failures, the regression would have been caught per-agent.

**Canonical example: PR #1314** (`agents-plugin/agents/refactor.md`). That
PR bakes this exact pattern into the repository's refactor agent: it
broadens the agent's bash permissions to cover the audit script and
mandates an audit post-pass before the agent reports done. New bulk-edit
dispatch briefs should follow the same shape — agents inherit both the
permission to run the script and the requirement to clear it.

## Reviewer-agent verification — evidence

> Evidence: issue [#1239](https://github.com/laurigates/claude-plugins/issues/1239)
> — three parallel-dispatch rounds; verify-then-fix caught a "ready to
> merge" claim where helm-template did not confirm the hypothesis, and
> the self-author guard prevented HTTP 422 across every fix PR.

## Stage authority in multi-stage pipelines

When a pipeline separates build from verify (implement → review → merge),
authority is scoped per stage, and every brief stands on its own.

- **Scope authority per stage.** Merge or publish authorization goes only into
  the brief of the stage that owns it. Every build stage's brief ends with an
  explicit stop: "stop at PR opened; do not merge". Being authorized at all is
  enough for a capable agent to use the authorization at its first chance, and
  a missing prohibition reads as permission. A shared constraints block pasted
  into every brief is the usual way merge authority leaks into a build stage.
- **No forward references.** Every brief, the review stage's included, carries
  the user's decisions verbatim. A downstream stage cannot read an upstream
  stage's prompt, so a brief that cites "the decision the user made" without
  quoting it hands the reviewer nothing to review against. Authority grants
  (merge/publish) are the exception: quote them only in the owning stage's
  brief, and in build-stage briefs replace them with the explicit stop.

Push authority is separate from merge authority: agents push their own commits
in the normal case (SKILL.md § Who Pushes?), and pushing a branch or opening a
PR never implies merging it.

> Evidence: issue [#2902](https://github.com/laurigates/claude-plugins/issues/2902)
> — an implement → review Workflow over four issues in
> laurigates/mcu-tinkering-lab put "implement, review, fix and merge with no
> further asks" in one constraints block shared by every stage. Three of the
> four implement agents merged their own PRs (#701, #702, #708) on green CI
> before their review stage started, so the reviews ran post-merge and a
> confirmed fix needed a follow-up PR (#705). The review prompt also cited a
> user decision it never included, which the #700 reviewer flagged as missing.

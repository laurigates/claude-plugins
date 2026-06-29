# ADR-0016: Extract Deterministic Skill Procedure into Structured-Output Scripts

---
date: 2026-06-09
created: 2026-06-09
modified: 2026-06-29
status: Accepted
deciders: claude-plugins team
domain: architecture
relates-to:
  - ADR-0003
github-issues:
  - 1551  # sweep implementation + postmortem
  - 1552  # perf(git-plugin): extract 4 skills
  - 1553  # perf(blueprint-plugin): extract 3 skills
  - 1554  # perf(configure-plugin): extract 3 skills
  - 1555  # perf(finops-plugin): extract github-actions-finops
  - 1556  # perf(code-quality-plugin): extract code-dep-audit
  - 1557  # perf(macos-plugin): extract macos-incident-postmortem
  - 1558  # perf(workflow-orchestration-plugin): extract workflow-preflight
---

## Context

The repository ships **308 `SKILL.md` files**, but only **17 skill
directories ship any helper scripts** (35 script files total). The remaining
~290 skills do **100% of their work agent-driven**: the agent reads the
SKILL.md prose, runs shell commands one at a time, parses each output, applies
a decision tree, and synthesizes a result — all inside the context window.

For a large class of skills this is wasteful, because the agent is acting as a
slow, expensive interpreter for what is really a shell script.

### The token-cost model

Every skill invocation pays three distinct costs. Only some are addressable by
extraction:

| Cost | Source | Script-extractable? |
|------|--------|---------------------|
| **SKILL.md load** | The prose enters context every invocation | Partly — moving procedure into a script shrinks the prose to "run `check.sh`, interpret `STATUS=`" |
| **Execution I/O** | Each command's raw output dumps into context; verbose tools (`gh`, `kubectl`, `npm audit`, `jq` pipelines) are the worst | **Yes — the dominant win.** A script filters to a structured rollup |
| **Per-step reasoning** | The agent spends tokens deciding "what command next" across a *fixed* decision tree | **Yes** — if the branching is mechanical, the script owns it |

The win concentrates where a skill currently makes the agent run *N* commands,
read *N* verbose outputs, and apply a fixed decision tree — and is invoked
often. That collapses to one script invocation emitting `KEY=VALUE` /
`STATUS=` / `ISSUE_COUNT=` (the `structured-script-output.md` convention),
which the agent reads in a fraction of the tokens.

### The procedure ↔ judgment spectrum

Every skill sits between two poles:

- **Procedure** — mechanical steps: run, parse, branch, count, format, check
  against a rule. Deterministic. Extractable.
- **Judgment** — synthesis, taste, naming, prose, design trade-offs, reading
  unfamiliar code. The agent *is* the value; no script replaces it.

Extraction targets the procedural end only.

### Prior art already in the repository

This is not a new pattern — it is the fleet-scale application of one we already
practice:

- `health-plugin/skills/health-check/scripts/check-*.sh` — the reference
  implementation of structured-output diagnostic scripts.
- `.claude/rules/structured-script-output.md` — the target output contract
  (`=== SECTION ===` / `STATUS=` / `ISSUE_COUNT=`).
- `project-plugin:project-skill-scripts` — the **per-skill** version of this
  analysis ("find and create supporting scripts for plugin skills... improving
  token efficiency, extracting bash blocks from SKILL.md").
- `.claude/rules/agentic-optimization.md` — the underlying principle
  (machine-readable output, compact reporters).
- `.claude/rules/skill-evaluation.md` — the mechanism to measure
  before/after effectiveness so extraction does not silently degrade a skill.

## Decision

**Treat extractable, deterministic skill procedure as a first-class
optimization surface. Systematically identify skills whose agent-driven steps
can be replaced by structured-output helper scripts, prioritize by
savings × frequency, and track the work as issues and a personal backlog.**

### Detection heuristics

A skill is a candidate when cheap, mechanical signals point to embedded
procedure:

| Signal | Direction | Rationale |
|--------|-----------|-----------|
| Many fenced ` ```bash ` blocks in SKILL.md | candidate | Embedded procedure |
| Bash blocks pipe to `jq`/`grep`/`awk`/`wc` | strong | Parsing logic begging to be a script |
| Name/description verbs: check, audit, validate, scan, detect, count, list, status | strong | Deterministic intent |
| Conditional prose / decision tables ("if X then Y", "when count exceeds N") | candidate | Maps directly to branching code |
| Large SKILL.md (size ∝ embedded procedure) | weak | Correlates, noisy |
| `allowed-tools` read-only Bash-heavy (Bash, Read, Grep, Glob) | candidate | Mechanical, low-risk to extract |
| **No `scripts/` dir** (≈290 of 308) | gate | The unoptimized population |
| Description in "Use when mentioning X" reference style | skip | Knowledge skill |
| Uses `AskUserQuestion` / interactive | skip | Judgment |
| Already ships `scripts/` (17 dirs) | audit-only | Check *coverage*, don't re-extract |

### Candidate task types (strongest to weakest)

1. **Audit / check / validate skills** — inherently rule-comparison yielding
   pass/fail. The proven win (`health-plugin`). `*-audit`, `*-check`,
   `*-validate`, `configure-status`, compliance scans.
2. **Multi-command discovery + parse** — several `gh`/`kubectl`/`git`/`jq`
   calls reduced to a summary (`finops-*`, `git-triage`, `tfc-*`).
3. **Fixed decision trees** — "if file exists → A; if count > N → warn."
4. **Bulk file scanning** — agent reading/grepping many files → one script with
   a structured count.
5. **Frontmatter / metadata extraction & counting** — boilerplate done inline.

### What is explicitly out of scope

- Knowledge/reference skills whose prose *teaches the agent how* (e.g.
  `python-development` idioms, `rust-development`).
- Judgment skills — `code-review`, `prose-*`, `blog-post-writing`, anything
  driven by `AskUserQuestion`.
- Skills where the deliverable varies per situation and that variance is the
  value.

### Ranking

Prioritize by **estimated per-invocation savings × invocation
frequency/importance** — a rarely-touched skill saving 5k tokens loses to a
hot one saving 1k. Frequency is proxied from friction transcripts and
judgment about which skills are heavily used.

### Process

A multi-agent analysis workflow sweeps every script-less skill, scores each on
the heuristics above, adversarially verifies that "deterministic" spans are not
secretly judgment, and emits a ranked candidate report. Confirmed candidates
are filed as GitHub issues (the implementation backlog) and mirrored as
taskwarrior tasks (the personal cross-session queue). Actual extraction remains
the job of `project-skill-scripts`, one skill at a time, with the
`regression-testing.md` requirement of a test per extracted behaviour.

#### Deterministic pre-filter front-end (2026-06-29 refinement, issue #1551)

The v1 sweep filed and shipped the top-50-ranked candidates (issues #1552–#1558,
extraction PRs #1564–#1571). Re-running the full ~8M-token LLM sweep over the
long tail (ranks 50–337) repeatedly failed under sustained-load server
throttling. The refinement: a **deterministic funnel front-end** reserves the
LLM for the residue instead of fanning out over every script-less skill.

`project-discovery/scripts/analyze-skills.sh --funnel` bins every script-less
skill — free, ~40s, byte-identical every run (`offload-to-deterministic-substrate.md`)
— emitting the `structured-script-output.md` `KEY=VALUE` / `STATUS=` /
`ISSUE_COUNT=` contract:

| Verdict | Rule | LLM needed? |
|---------|------|-------------|
| `HAS_SCRIPTS` | ships a `scripts/` dir | no — audit-only (the gate above) |
| `SKIP_REFERENCE` | "Use when mentioning/referencing X" knowledge prose | no |
| `SKIP_INTERACTIVE` | `AskUserQuestion`/`multiSelect` and no procedure (<3 shell blocks) | no |
| `SKIP_NOPROC` | <3 shell blocks | no |
| `LLM_WEAK` | has procedure (≥3 shell blocks), weak signal | optional classify pass |
| `LLM_STRONG` | ≥2 data-processing pipes, an extraction verb **in the skill name**, or analyzer_score ≥ 24 | verify pass |

Two calibration findings (the funnel is a *pre-filter*, not an LLM replacement):

- **Strong signals must win over skip signals.** Every v1 candidate carried a
  *descoped* `AskUserQuestion` confirmation step, so a naive "interactive ⇒ skip"
  precedence false-skips real candidates. The funnel ranks `LLM_STRONG` first and
  `LLM_WEAK` (any procedural skill) above the SKIP bands, so an
  interactive-but-procedural skill is routed to the LLM, never silently dropped.
- **The extraction-verb signal is name-scoped, not description-scoped.** Scanning
  descriptions fires on ~200 skills (nearly every description says "check",
  "validate", "detect"); the skill *name* (`*-audit`, `*-validate`) is the precise
  signal.

The irreducible gap: a few low-mechanical-signal candidates (e.g. v1's
`github-actions-finops`, score 8) were genuine LLM judgment calls no cheap signal
reproduces. The funnel rules out the obvious SKIPs and bounds the residue; the LLM
still owns the residue. Run the funnel first (free); only escalate the
`LLM_STRONG`/`LLM_WEAK` residue to a bounded-team LLM pass when its estimated
savings warrant the token cost.

## Consequences

### Positive

- **Lower per-invocation token cost** on the procedural skills, concentrated
  where they are invoked most.
- **Smaller SKILL.md prose** as procedure migrates to scripts — the skill
  becomes "run the check, interpret the rollup."
- **Determinism** — extracted checks produce identical output every run, which
  is also more testable (`regression-testing.md`).
- **A ranked, tracked backlog** instead of ad-hoc one-off optimizations.

### Negative

- **Extraction effort** — each candidate is a real change (script + regression
  test + SKILL.md rewrite), so the backlog is large.
- **Two-surface maintenance** — a skill with a script must keep prose and
  script in sync (mitigated by keeping the prose thin once the script owns the
  logic).
- **Risk of over-extraction** — pulling out a span that actually needed the
  agent's judgment degrades the skill. Mitigated by the workflow's adversarial
  verify phase and by `skill-evaluation.md` before/after measurement.

### Risks

| Risk | Mitigation |
|------|------------|
| Mass issue/task creation becomes noise | File only confirmed candidates with positive savings, not every analyzed skill |
| "Deterministic" misjudged | Adversarial verify phase; treat the report as a worklist, not an auto-edit mandate |
| Scripts drift from SKILL.md | Thin the prose once the script owns logic; regression tests pin behaviour |
| Effort outpaces value on the long tail | Rank by savings × frequency; stop when marginal candidates fall below a threshold |

## References

- `.claude/rules/structured-script-output.md` — output contract for extracted scripts
- `.claude/rules/agentic-optimization.md` — machine-readable output principle
- `.claude/rules/skill-evaluation.md` — before/after effectiveness measurement
- `.claude/rules/regression-testing.md` — test-per-fix requirement
- `health-plugin/skills/health-check/scripts/` — reference implementation
- `project-plugin:project-skill-scripts` — per-skill extraction skill
- [ADR-0003: Auto-Discovery Component Pattern](0003-auto-discovery-component-pattern.md)

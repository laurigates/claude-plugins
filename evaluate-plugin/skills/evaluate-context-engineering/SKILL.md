---
name: evaluate-context-engineering
description: Context-engineering audit (C1-C6) of skills and always-loaded rules. Use when trimming context bloat, auditing a plugin, or after a new Claude model ships.
args: "[plugin | plugin/skill | --always-loaded] [--judge]"
allowed-tools: Bash(python3 *), Bash(bash *), Read, Glob, Grep, Task, TodoWrite
argument-hint: "git-plugin/git-commit --judge"
model: opus
created: 2026-07-26
modified: 2026-07-26
reviewed: 2026-07-26
---

# /evaluate:context-engineering

Audit a plugin, a single skill, or the always-loaded surface against the six
context-engineering shifts Anthropic named for Claude 5 generation models, and
report a C1–C6 card.

Two channels, deliberately kept apart:

| Channel | What it is | Cost |
|---|---|---|
| **M — mechanical** | `check-context-engineering.py`, deterministic proxies over the tree | free |
| **J — judgment** | an isolated agent scoring the frozen 1–5 rubric with quoted evidence | one subagent, `--judge` only |

Channel M ranks candidates; it cannot tell a load-bearing safety constraint from
a restatement of a model default. Channel J makes that call. **Never blend the
two into one score** — a mechanical proxy and a judgment answer different
questions, and averaging them hides which one is driving a recommendation.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| Auditing whether a skill or rule is written for the old context rules | Checking structure/frontmatter/size lint → `scripts/plugin-compliance-check.sh` |
| A new Claude model shipped and the corpus needs re-reading | Measuring whether a skill still *works* → `/evaluate:matrix` |
| Deciding what to cut from `CLAUDE.md` and `.claude/rules/` | Actually migrating rules into skills → `agent-patterns-plugin:meta-context-diet` |
| You want ranked, evidence-backed cut candidates | Checking a skill reads clearly to a fresh agent → `/evaluate:legibility` |

## The six dimensions

| Dim | Shift | What the scanner measures |
|---|---|---|
| **C1** | rules → judgment | Constraint markers per 1k chars, and how many sit next to a safety/irreversibility word |
| **C2** | examples → interface design | Fenced-block share of the body; whether `args` enumerates its alternatives |
| **C3** | upfront → progressive disclosure | Body size vs supporting files; disclosure levels (body → references → scripts) |
| **C4** | repetition → single source of truth | 8-word shingle overlap between skills, rules, and `CLAUDE.md` |
| **C5** | (the >80% claim) | Always-loaded chars: `CLAUDE.md` + rules with no `paths:` scope |
| **C6** | simple specs → rich references | Multi-line shell blocks with no bundled script |

## Context

- Repo root: !`git rev-parse --show-toplevel`
- Plugins present: !`find . -maxdepth 2 -name plugin.json -path '*/.claude-plugin/*'`
- Always-loaded rules: !`find . -maxdepth 3 -path '*/.claude/rules/*.md'`

## Parameters

Parse `$ARGUMENTS`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `plugin` | whole repo | Scope to one plugin directory, e.g. `git-plugin` |
| `plugin/skill` | — | Scope to one skill, e.g. `git-plugin/skills/git-commit` |
| `--always-loaded` | off | Score only `CLAUDE.md` and the unscoped rules |
| `--judge` | off | Also run Channel J on the target (one subagent per unit, max 3 units) |
| `--budget N` | 100000 | Always-loaded char budget for the C5 ratchet |

## Execution

Execute this audit:

### Step 1: Run Channel M

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/check-context-engineering.py" --top 10
```

Add `--target <plugin-or-skill-path>` when the user scoped the run, and
`--always-loaded-budget <N>` when they passed `--budget`.

Read the `KEY=VALUE` block. `STATUS=ERROR` means only one thing: the
always-loaded surface is over budget. Every other finding is a `WARN` candidate,
not a verdict.

### Step 2: Report the C1–C6 card

Render one row per dimension: the measured value, the count of flagged units,
and the top offender. State the totals for `C5_ALWAYS_LOADED_EST_TOKENS` and
`SKILL_BODY_EST_TOKENS` separately — they have different cost models and must
not be summed.

Rank findings by `always-loaded cost × frequency`, never by raw size. An
always-loaded rule costs on every turn; a skill body costs only when the skill
fires; a `references/` file or script costs only when read or run. A large skill
body is a smaller problem than a medium-sized unscoped rule.

### Step 3: Judge the top units (`--judge` only)

For at most 3 flagged units, spawn one isolated subagent each:

```
Task subagent_type: general-purpose
prompt: Read the frozen rubric at docs/benchmarks/2026-07-context-engineering/rubric.md
        and score <unit path> on C1-C6. Every score of 1, 2, 4 or 5 needs a
        verbatim quote from the unit, copied exactly. If you cannot quote for a
        score, score 3. Do not read the scanner's metrics.json.
```

Withhold Channel M's numbers from the judge — showing them anchors the judgment
to the proxy the rubric is supposed to check independently. Run judges
**synchronously**: the critique is the returned tool result
(`agent-patterns-plugin:cold-read-gate`).

### Step 4: Propose cuts, and one thing to keep

For each recommendation give: the unit, the dimension, the token cost, the
proposed change, and whether the evidence is **proven** (a judged quote) or
**proxy-only** (Channel M alone).

Include at least one unit that **earns its tokens** and should not be cut. A
report with no counter-finding has an agreement bias, not a clean corpus — the
scanner flags constraint density, and some of the densest text is the
safety-critical text that should stay.

### Step 5: Hand off, do not apply

Migrating rules into skills is `agent-patterns-plugin:meta-context-diet`'s job —
it carries the per-candidate confirmation gate for lossy edits to always-loaded
files. This skill measures and recommends; it does not rewrite.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Whole-repo card | `python3 "${CLAUDE_SKILL_DIR}/scripts/check-context-engineering.py"` |
| One plugin | `... --target git-plugin` |
| Machine-readable | `... --json` |
| CI ratchet (exit 1 over budget) | `... --strict` |
| Full issue list | `... --max-issues 0` |
| Determinism check | `... --json \| sha256sum` (must be stable across runs) |

## Related

- `docs/benchmarks/2026-07-context-engineering/rubric.md` — the frozen 1–5 anchors Channel J scores against
- `.claude/rules/context-engineering.md` — the standing house position and what it supersedes
- `.claude/rules/skill-evaluation.md` — the tiered cost model; ablation is the follow-up that turns a judgment into a measurement
- `agent-patterns-plugin:meta-context-diet` — migrates approved always-loaded candidates into skills

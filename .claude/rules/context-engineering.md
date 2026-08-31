---
created: 2026-07-26
modified: 2026-08-31
reviewed: 2026-08-31
paths:
  - "**/SKILL.md"
  - "**/skills/**"
  - ".claude/rules/**"
  - "CLAUDE.md"
---
# Context Engineering (Claude 5 generation)

The house position on Anthropic's
[new context-engineering rules](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models),
after measuring this marketplace against them
([`docs/benchmarks/2026-07-context-engineering/`](../../docs/benchmarks/2026-07-context-engineering/)).

This rule is **path-scoped on purpose.** It is authoring guidance, not an
every-turn invariant, so it loads only when you are editing a skill, a rule, or
`CLAUDE.md` — which is the rule it is asking you to follow.

## What the measurement found (2026-07 snapshot)

> **These are the figures as measured in 2026-07 — they are a dated record, not
> current state, and several have since moved.** Re-measured 2026-08-15:
> **412** tracked plugin skills (not 242), **3** `references/` directories (not
> zero), and the C5 always-loaded surface at **~89,000 chars / ~22,262 tokens**
> (not ~24,600). Cite the re-measurement, not this table, when scoping work —
> issues #2140/#2141/#2143 all carry figures derived from the snapshot below.
> Note also that three scanners give three legitimate skill counts
> (`check-context-engineering.py` includes repo-internal `.claude/skills/`), so
> any count must name the scanner that produced it.

| Dim | Shift | Judged mean | Verdict |
|---|---|---|---|
| C1 | rules → judgment | 3.9 | **Not our problem.** Only 9 of 407 skills are constraint-dense |
| C2 | examples → interface | 3.86 | Healthy |
| C6 | specs → rich references | 3.15 | Competent |
| C3 | upfront → progressive disclosure | 2.9 | Weak — 242 skills are one flat file, 0 `references/` dirs |
| C4 | repetition → single source of truth | 2.65 | Weak |
| C5 | always-loaded budget | 1.67 | **The problem** — ~24,600 tokens every session |

## The cost model, which decides everything

Rank a cut by `always-loaded cost × frequency`, never by raw size. The three
surfaces are not comparable:

| Surface | Paid | A cut here buys |
|---|---|---|
| `CLAUDE.md`, unscoped `.claude/rules/*.md` | **every turn** | the most |
| `SKILL.md` body | only when the skill fires | a per-invocation saving |
| `REFERENCE.md`, `references/`, `scripts/` | only when read or run | ~nothing — already deferred |

The post's ">80% removed, no measurable loss" figure is about an always-loaded
system prompt. A 20,000-char skill body is a smaller problem than a 5,000-char
unscoped rule.

## Authoring rules

**Every new `.claude/rules/*.md` carries a `paths:` glob** unless its violation
is a bug on a turn where nobody mentioned the topic. The default is scoped; an
unscoped rule is the exception and should say why. If it reads as a procedure
with a trigger ("when releasing", "before a destructive op"), it is a skill —
promote it via `agent-patterns-plugin:meta-context-diet`.

**`paths:` fires only when a matching file is EDITED — it cannot scope a rule
whose hazard fires on a command.** This is the trap that decides most scoping
calls, and getting it wrong silently disarms a guard while the budget number
improves. Sort the rule by what triggers its failure, not by what it talks
about:

| The failure happens when you… | Lever | Example |
|---|---|---|
| edit a file of a known shape | `paths:` glob | zsh keybindings, `.gitattributes`, chezmoi naming prefixes |
| run a command | **stays unscoped**, kept lean, detail in a linked doc | `chezmoi apply` deleting unmanaged files; `re-add` skipping templates |
| act on intent ("diagnose CI", "release") | promote to a **skill** | `ai-review-max-turns`, `multirepo-ci-cd` |
| any turn, unprompted | stays unscoped — it is a real invariant | never merge a stranger's PR |

A rule that talks about chezmoi is not automatically edit-triggered: an apply
that destroys data can touch no source file at all. When a single rule mixes
both (dotfiles' 20 KB `chezmoi-conventions.md` did), **split it** along that
line rather than scoping the whole thing.

**Guidance lives in exactly one place, and the others name it.** Cross-plugin
means a `plugin:skill` name reference, never a shared `REFERENCE.md`
(`skill-consolidation.md`). If you catch yourself restating a table that another
file owns, link instead — and note that `git-commit` scored C4 = 2 for restating
a table it *already linked to*.

**Split long skills across files, not into one sidecar.** The post asks to
"divide it into many files and split them out". Split by the path that needs the
detail, so a scoped run loads only its own material. As of 2026-08-15 the corpus
has **130** single `REFERENCE.md` files and **3** `references/` directories — the
shape exists now (`agent-patterns-plugin:parallel-agent-dispatch` is the
reference implementation, #2143), so copy it rather than inventing a layout.

**Spend constraint tokens where violation is expensive.** The measured pattern
in text that earned its tokens: it names a non-obvious, costly failure **and says
why**, so the model generalises past the enumerated case. Text that restates a
model default does not.

## Supersedes

These `skill-quality.md` requirements are **demoted** on the evidence in the
report (§5 F2). `skill-quality.md` remains authoritative for everything else.

| Was | Now | Why |
|---|---|---|
| `## When to Use This Skill` table **required** in every body | **Recommended where it disambiguates sibling skills**; otherwise let the `description` carry it | 407/407 comply at ~70K tokens (9.2% of all body mass) for guidance the post locates in `description`. Judges credited it specifically where two skills could both match |
| `## Agentic Optimizations` table **required** | **Optional**; keep it where the commands are the payload (CLI wrappers) | No published basis; 257 skills, ~33K tokens |
| Single `REFERENCE.md` as the disclosure shape | Prefer a multi-file `references/` split for large skills | "divide it into many files" |

Unchanged: the 26,000-char body ceiling, the description length band, the
model-selection policy, positive framing, and the date fields. The benchmark
excluded those from scoring rather than validating them — absence of evidence,
not evidence of absence.

## Deliberately unresolved

The post's fifth shift — *manual memory → automatic memory* ("Claude now
auto-saves relevant memories; stop manually curating CLAUDE.md") — is **not**
adopted. It is a claim about harness behaviour, not an artifact property, and
acting on it would change how `session-plugin:session-distill` writes rules.
Verify it against the installed Claude Code version before changing anything.

## Enforcement

| Layer | Mechanism |
|---|---|
| Measurement | `just lint-context-engineering` (Channel M, report-only) |
| Ratchet (this repo) | `check-context-engineering.py --strict` — **ERROR** when the always-loaded surface exceeds its budget. Pre-commit on `CLAUDE.md` / `.claude/rules/**`, plus CI |
| Ratchet (portfolio) | `check-context-engineering.py --also <repo> --portfolio-budget N` — sums the C5 surface across repos. Run from the portfolio root: `just context-budget-strict` |
| Audit | `/evaluate:context-engineering [target] --judge` |
| Cadence | Re-run on each model release (`skill-evaluation.md` Tier 2 trigger) |

### The per-repo budget cannot see what a session pays

A repo's own C5 budget is blind to the cost of loading several repos side by
side, which is what a portfolio session actually does. Measured 2026-08-31,
before this rule's scoping pass: `claude-plugins` at 23% of its own 100,000-char
budget, `dotfiles` and `repos-claude-config` with no gate at all, and a stacked
surface of **180,021 chars (~45,000 tokens)** paid before the first user word.
No single repo's ratchet could fire.

`--also` closes that: it sums the C5 surface (CLAUDE.md + unscoped rules) across
roots and gates the total. Only C5 aggregates — C1–C4 and C6 measure authoring
quality inside one marketplace and stay scoped to `--project-dir`. The budget is
a ratchet, so it is set just above the measured total (155,000 as of 2026-08-31,
against 150,313) and lowered as scoping work lands; a generous default would
make it decorative.

Two properties keep the number trustworthy, both pinned by
`tests/test-check-context-engineering.sh`: the breakdown is sorted by repo name
so `--also` order cannot change the output, and the portfolio ERROR sorts ahead
of every WARN so `--max-issues` can never truncate away the reason a run is red.
The portfolio-root recipe **fails closed** when a repo is missing rather than
measuring fewer of them — a short total passes the budget and reads exactly like
a green run.

The ratchet is the only hard gate. It exists so the every-session surface cannot
grow back silently — the failure mode that produced a 1.67 on C5 in the first
place.

## Related

- `docs/benchmarks/2026-07-context-engineering/` — the measurement, rubric, and audit trail
- `.claude/rules/skill-quality.md` — static quality standards (this rule demotes three of them)
- `.claude/rules/skill-evaluation.md` — the tiered cost model; ablation is the follow-up that would turn these judgments into measurements
- `.claude/rules/skill-consolidation.md` — cross-plugin dedupe is a name-reference
- `agent-patterns-plugin:meta-context-diet` — migrates always-loaded candidates into skills
- `.claude/rules/offload-to-deterministic-substrate.md` — C6's parent principle

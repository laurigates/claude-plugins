# Model comparison, 2026-10: is Haiku 5.5 good enough to delegate to?

Measured 2026-10-15 to 2026-10-21. It tests the claims of an r/ClaudeAI thread
("Haiku 5.5 isn't getting enough love"): that Haiku 5.5 usually beats Opus 4.6
at 1/50 of the price for prompts under 100K tokens, and that a coordinator
keeping Haiku workers under 100K gets most of the work done for little usage.

Tooling: `evaluate-plugin/scripts/model-compare/` (synthetic sets, runners,
review prompt). Every run pinned `--effort medium`. Costs are API list price as
reported by `claude -p` (`total_cost_usd`, `costBasis: list`).

## Answer

On this repository's work, yes, with two conditions.

- Haiku 5.5 matched Sonnet 5.5 and Opus 5.5 on correctness across bug fixes,
  skill edits, triage and "is this issue still valid?" judgment, and beat Opus
  4.6 on the hard synthetic set.
- Its weak spot was calibration: it flagged placeholders as dead paths in a new
  guard. A fresh Opus reviewer caught that and the defects all three models
  shared, at about $1 per review.
- The price advantage depends on staying under 100K tokens per request. In the
  normal harness in this repo every Haiku run went past it (110K–231K), and the
  advantage over Opus 5.5 fell from about 16x per run (stripped harness) to
  about 6x.

## Pricing facts (platform pricing page, checked 2026-10-15)

| Model | Input | Cache read | Output | Note |
|---|---|---|---|---|
| Haiku 5.5, prompt ≤ 100K | $0.10 | $0.01 | $0.50 | |
| Haiku 5.5, prompt > 100K | $0.50 | $0.05 | $2.50 | whole request, cache reads and writes count toward the 100K, priced per request |
| Sonnet 5.5 | $2 | $0.10 | $10 | |
| Opus 5.5 | $4 | $0.20 | $20 | |
| Opus 4.6 / 4.8 / 5 | $5 | $0.50 | $25 | |

"1/50 of Opus" holds against Opus 4.6–5 base rates; against Opus 5.5 it is
1/40, and 1/20 for cache reads, which dominate agent workloads. The 100K
threshold is per request, not a session's first 100K tokens.

## Fixed overhead (one-turn Haiku probe)

| Context | Prompt tokens before any work |
|---|---|
| Lean `claude -p` (no settings, plugins, MCP) | ~6.5K |
| Bare session, this environment's plugins | ~35.5K |
| Session in this repo | ~69K |
| Fresh subagent | ~24K |

A repeated `/loop`-style check in one session grew ~5.3K tokens per iteration
and would cross 100K at about iteration 13. Recurring loops expire after 7
days, and Haiku 5.5 only auto-compacts near 967K by default.
`hooks-plugin`'s `context-threshold-nudge.sh` (#3102) warns the agent at 80K
and 95K on Haiku 5.5.

## Basic synthetic set (8 tasks, 1 run each)

| Model | Mean score | Model cost, 8 tasks |
|---|---|---|
| Haiku 5.5 | 1.00 | $0.02 |
| Sonnet 5.5 | 0.99 | $0.19 |
| Opus 5.5 | 1.00 | $0.47 |
| Opus 4.6 | 0.99 | $0.73 |

Every model hit the ceiling; the set confirms the cost ratio, not a ranking.

## Hard synthetic set (8 tasks, 1–3 runs)

| Model | Runs | Mean score | Cost per run | Peak prompt |
|---|---|---|---|---|
| Haiku 5.5 | 15 (all 8 tasks) | 0.995 | $0.019 | 54K |
| Opus 5.5 | 5 | 0.992 | $0.31 | 27K |
| Sonnet 5.5 | 2 | 0.988 | $0.13 | 21K |
| Opus 4.8 | 2 | 1.000 | $0.84 | 34K |
| Opus 4.6 | 8 (all 8 tasks) | 0.928 | $0.45 | 30K |

On the eight tasks both ran, Haiku 5.5 scored above Opus 4.6: Opus 4.6
missed per-key locking (b2), call sites in the large refactor (b6) and planted
review bugs (b8). Haiku took more turns (up to 34 against Opus 5.5's 7 on b6),
so its context grew larger.

## Real issues (5.5 models only, normal harness, 1 run each)

| Issue | Haiku | Sonnet | Opus |
|---|---|---|---|
| #3091 check-hooks.sh reads timeouts as ms | fixed | fixed | fixed |
| #3092 drop the ms heuristic (blocked: #3088 unmerged) | declined | **committed a regression** | declined |
| #2994 registry-health Deleted (already fixed by #3053) | noticed | noticed | noticed |
| #3061 verification-only path in git-issue (blind review) | **8**, 1st | 6 | 7 |
| #2948 backticked dead-path guard (blind review) | 4 | 6 (green, but checks little) | 6 (best design, not green) |
| Model cost, all five | **$1.30** | $3.15 | $7.63 |

Shared defects the reviewers found in all three models' work: malformed
regression-ledger rows, missing `allowed-tools` grants for commands the new
steps run, and summaries that claimed more than the diff contained.

## Caveats

- One run per cell for most of it; one reviewer per issue. Directions, not
  significant differences.
- Medium effort for every model; Opus 4.6 normally runs higher.
- The synthetic sets are under 2,500 lines per task. Long sessions, vague
  requirements and scientific work were not tested.
- Two of the five issues had stale premises; check premises before running.
- Not measured: how the subscription usage meter weights models (the help
  article gives only "Opus costs several times more per turn than Sonnet, and
  Sonnet more than Haiku").

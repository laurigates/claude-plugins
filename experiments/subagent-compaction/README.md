# subagent-compaction

Probe for how Claude Code subagents behave as their context fills: when they
compact, whether they resume the task afterwards, whether main-session
compaction settings reach them, and whether `PreCompact` hooks fire inside
them.

Not a plugin: not in the marketplace, not versioned by release-please. Commit
scope `subagent-compaction` matches no release-please package.

## Why

Model quality degrades well before the context window is full (roughly past
50%), and a main session run with auto-compact disabled gives no control over
subagent context. Claude Code exposes no per-subagent context limit or
compaction setting (`maxTurns`, `model`, `effort` are the only
bounding frontmatter fields), so the behaviour has to be measured.

## Findings so far

### 2026-09-23 — haiku 200k subagent, host defaults (n=1)

Environment: Claude Code on the web, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80`,
auto-compact enabled (default). A fresh `general-purpose` subagent (briefed,
not forked) was told to read ~1 MB of repo files in chunks and report a
one-line result. Table produced by `scripts/analyze.sh --transcript`.

| Call | Context (tokens) | Event |
|---:|---:|---|
| 1 | 58,448 | Fresh briefed subagent baseline |
| 2–8 | 63k–71k | Oversized reads rejected, chunk size halved |
| 9–11 | 78k → 95k → 138k | Large reads succeed |
| — | 150,710 → 7,662 | `compact_boundary`, `trigger: auto`, 40 s |
| 12–13 | 63k–68k | No further task work |
| — | 212,745 → 6,749 | Second auto-compaction, after hand-back |
| — | 199,892 → 6,580 | Third auto-compaction |

Observations:

1. **Subagents auto-compact independently** of the main session. The first
   compaction triggered at ~75% of the 200k window (80% override minus
   reserve).
2. **The task was abandoned after compaction.** The subagent treated the
   compaction instruction ("text only, produce a summary") as its task and
   returned that summary as its final report.
3. **The report was false.** It declared all work complete; it had read
   ~50–150 lines of each file instead of the whole files, and nothing in
   the report flagged the deviation.
4. **Compaction continued after hand-back.** Two more auto-compactions
   followed; the resumed agent then tried to `Read` its own transcript
   (939 KB, rejected) and went idle.
5. **Briefed-subagent baseline ≈ 58k tokens** (system prompt, tools,
   CLAUDE.md, unscoped rules): 29% of a 200k window, ~6% of 1M.

Caveats: one run, haiku, host-specific override. The questions below are
what `ctx-probe.sh` is built to answer on 1M-window models with the
operator's own configuration.

## Open questions and how the probe answers them

| # | Question | Arm | Read |
|---|---|---|---|
| Q1 | Does main-config `autoCompactEnabled=false` reach subagents? | `ac-off` | `SUBAGENT_COMPACTED` — `yes` means the setting does not propagate |
| Q2 | Does the subagent resume its task after compacting? | `ac-on` | `SENTINELS_CORRECT` vs expected; `SENTINELS_WRONG` > 0 is fabrication |
| Q3 | Does `PreCompact` fire inside a subagent, with an agent identifier? | both | `HOOK_PreCompact`, `PRECOMPACT_WITH_AGENT_ID`, `PRECOMPACT_KEYS` |

Mechanics:

- Each arm runs `claude -p` with an isolated fake `HOME` (its own
  `.claude.json` with `autoCompactEnabled`, and `settings.json` with logging
  hooks for `PreCompact`/`PostCompact`/`SubagentStart`/`SubagentStop`).
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` defaults to `10`, so a 1M-window model
  compacts near 100k instead of ~800k — the same behaviour at a fraction of
  the cost.
- The main agent spawns one briefed subagent (model inherited) that reads a
  generated filler corpus. Each file ends in a `SENTINEL <file> <hex>` line.
  The subagent must report every sentinel, writing `MISSING <file>` for any
  it can no longer see. After compaction a sentinel it did not re-read
  cannot be recalled honestly, so recall and fabrication are both scored
  deterministically.

## Usage

Requires `claude`, `jq`, `awk`, `sha256sum`, and a subscription token
(`claude setup-token`, then `CLAUDE_CODE_OAUTH_TOKEN` in the environment or
`~/.api_tokens`) or `ANTHROPIC_API_KEY`, since the fake `HOME` has no login.

```sh
# From the repo root (module) or this directory
just subagent-compaction::dry-run                     # arm setup + commands, no API calls
just subagent-compaction::run                         # opus[1m], ac-on + ac-off
just subagent-compaction::run "opus[1m] sonnet[1m]"   # model comparison
just subagent-compaction::transcript <agent-*.jsonl>  # analyse any subagent transcript
just subagent-compaction::test                        # offline analyzer test
```

Results land in `results/<run-id>/` (gitignored): per-arm `main.jsonl`,
`hooks.jsonl`, `summary.txt`, the fake `HOME` with subagent transcripts, and
`summary.tsv` across arms.

Cost: each arm reads `files × kb` of filler (default 20 × 60 KiB ≈ 300k
tokens) through at least one compaction. Reduce `--files` for a cheaper
smoke run.

Subagent transcripts for any session live at
`~/.claude/projects/<cwd-slug>/<session-id>/subagents/agent-<id>.jsonl`, with
per-call `usage` and `compact_boundary` entries carrying
`compactMetadata.{trigger,preTokens,postTokens}`.

# claude-probe

A/B testing harness for Claude Code system-prompt overrides.

## What it does

Runs the same small prompts against `claude -p` in two configurations:

- **default** — Claude Code's built-in system prompt (no override)
- **probe** — `--system-prompt "$(cat prompts/probe.md)"` (a minimal
  replacement; our global rules + plugin infrastructure do the rest)

Both configurations run across multiple model / thinking combinations
(see `conditions.yaml`). Transcripts are captured as stream-JSON, then
scored deterministically (tool selection, turn count, output budget)
and with an LLM judge (fuzzy quality criteria).

The goal is to iterate on `prompts/probe.md`: start minimal, watch
which defaults-era behaviours regress, copy just-enough from the
[Piebald-AI reference](https://github.com/Piebald-AI/claude-code-system-prompts)
to fix each regression — and stop there.

## Quickstart

The repo-root justfile registers this as a module — run recipes from
either the repo root (`just claude-probe::run-one …`) or from this
directory (`just run-one …`).

```sh
# From repo root:
just claude-probe::run                                    # full suite
just claude-probe::run-one 01-glob-vs-find opus-medium-probe
just claude-probe::compare
just claude-probe::compare-fast                           # skip LLM judge

# Or from experiments/claude-probe/:
just run
just run-one 01-glob-vs-find opus-medium-probe
just compare
```

See `docs/methodology.md` for the scoring rubric and why each variable
is what it is. `docs/decision-analysis.md` has the original motivation
(10 concrete frictions between our global rules and Claude Code's
default prompt).

## Layout

| Path | Contents |
|---|---|
| `prompts/probe.md` | The minimal system-prompt override under test |
| `conditions.yaml` | Model × thinking × prompt matrix |
| `tests/*.yaml` | One test case per file |
| `scripts/run-one.sh` | One (test, condition, run) invocation |
| `scripts/run-suite.sh` | Cartesian sweep |
| `scripts/score-run.py` | Deterministic checks → TSV |
| `scripts/llm-judge.py` | Fuzzy checks via judge model |
| `scripts/compare.py` | Aggregates + markdown table |
| `results/` | Per-run-id transcripts + scores (gitignored) |
| `docs/methodology.md` | How scoring works |
| `docs/decision-analysis.md` | Why this experiment exists |

## Cost notes

A full run is 96 Opus invocations (8 tests × 4 conditions × 3 runs).
The LLM judge adds one Haiku invocation per `llm_judge` check. When
iterating on a single test, prefer `just run-one` over `just run`.

## Not a plugin

This lives under `experiments/` deliberately — it is a dogfooding
harness, not something to publish. It is not registered in
`.claude-plugin/marketplace.json`, not versioned by release-please, and
not wired into the plugin-compliance scripts.

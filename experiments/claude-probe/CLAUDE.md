# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`claude-probe` is an **A/B testing harness for Claude Code system-prompt overrides**. It runs the same small prompts against `claude -p` under two configurations — `default` (built-in system prompt) and `probe` (`prompts/probe.md` via `--system-prompt-file`) — across effort levels, captures stream-JSON transcripts, and scores them deterministically + with a blinded LLM judge. The deliverable under iteration is `prompts/probe.md`: start minimal, find what regresses vs `default`, copy just-enough from the pinned Piebald upstream reference to fix each regression, stop.

It lives under `experiments/` deliberately. It is **not a plugin** — not in `.claude-plugin/marketplace.json`, not versioned by release-please, not wired into the plugin-compliance scripts. The parent repo's conventions (`../../CLAUDE.md`) still apply, but the plugin lifecycle does not.

## Commands

The repo-root justfile registers this as a module (`mod claude-probe 'experiments/claude-probe'`). Run recipes from the repo root as `just claude-probe::<recipe>` **or** from this directory as `just <recipe>`. Scoring scripts are PEP 723 `uv run` scripts (`#!/usr/bin/env -S uv run --script`), so `uv` must be on PATH; they self-install their deps.

| Task | Command |
|---|---|
| Cheap A/B (opus-low only) | `just run [filter] [runs]` |
| One test only | `just run 01-glob-vs-find` |
| Full sweep (4 efforts × 2 prompts = 8 conditions) — expensive | `just run-full` |
| Single `(test, condition, run)` for fast iteration | `just run-one 01-glob-vs-find opus-low-probe` |
| Aggregate + score last run (LLM judge on Haiku) | `just compare` |
| Aggregate without the judge (cheap) | `just compare-fast` |
| Score one transcript to TSV | `just score <path-to.jsonl>` |
| Per-invocation input-token cost: default vs probe | `just measure-tokens` |
| List test / condition ids; show the probe | `just tests` / `just conditions` / `just show-probe` |

`just run-max` exists but the `opus-max-*` conditions are **intentionally absent** from `conditions.yaml` — add an `opus-max-{default,probe}` pair manually before invoking it.

## Cost discipline (the central design tension)

Every run is a real Opus invocation; a full sweep is 192 of them. Cost is managed two ways:

- **Effort, not model, is the cost lever.** The model is fixed to `claude-opus-4-8` (Opus-low beats Sonnet on cost *and* quality, per `~/.claude/rules/agent-and-tool-selection.md`). The `run` (opus-low) → `run-full` (all efforts) → `run-max` (opt-in) progression maps to subsets of `conditions.yaml`.
- **Iterate narrow, confirm wide.** Use `just run-one` while editing `prompts/probe.md`; promote to `just run` (opus-low) until a probe version looks stable; only then `just run-full`. Prefer filtering to the affected test.

## Architecture — the scoring pipeline

```
conditions.yaml ─┐
tests/*.yaml ────┴─► run-suite.sh ─► run-one.sh ─► claude -p (stream-json) ─► results/<run_id>/<test>.<cond>.runN.jsonl (+ .meta.json)
                                                                                      │
                                              score-run.py (deterministic) ◄──────────┤
                                              llm-judge.py (fuzzy, blinded)  ◄─────────┘
                                                          │
                                              compare.py ─► report.md + scores.tsv (pass-rate table per test × condition)
```

- **`run-one.sh`** is the single unit of work: it extracts the test prompt and condition fields (model/effort/system_prompt) via inline Python, assembles the `claude` invocation, and writes a `.jsonl` transcript + `.meta.json` sidecar. `--system-prompt-file` **replaces** the built-in prompt (including its dynamic per-machine sections); `--append-system-prompt` would only append.
- **`run-suite.sh`** is the cartesian sweep over (test × condition × run); it writes `results/LATEST` so `compare`/`run-one` can default to the latest run-id.
- **`results/` is gitignored.** Transcripts are disposable; the durable artifacts are `prompts/probe.md` and `docs/iteration-log.md`.

### Non-obvious invariants (read before touching scoring or tests)

- **The judge is blinded and un-overridden.** `llm-judge.py` runs on a cheap model (`claude-haiku-4-5-20251001`, override via `PROBE_JUDGE_MODEL`) with **no** `--system-prompt` flag, and never sees which condition produced the transcript — so it can't reward the condition under test.
- **Output checks score the *answer*, not the preamble.** `output_matches` / `output_not_matches` run against `final_answer_text()` — the *last* assistant text turn — not all concatenated text. A prompt that mandates a tool call makes the model emit a "what I'm about to do" status update first; a `^`-anchored regex over concatenated text would grade that update instead of the answer. This is load-bearing; see the v3 entry in `docs/iteration-log.md` and the docstring in `score-run.py:84`.
- **`observational: true`** on a check reports it as `INFO`, excluding it from pass-rate totals (`compare.py` ignores `INFO`/`SKIP`). Use it for signals you want recorded but not graded.
- **`arg_pattern`** in a `tool_used`/`tool_not_used` spec is matched against the **JSON-serialized tool input**, not a single field.
- **Real cwd means a real environment.** Runs execute in the repo root, so the actual plugins, hooks, and `CLAUDE.md` affect every transcript. The experiment measures "override vs default *in this environment*", never in the abstract.

## Adding a test

Create `tests/NN-name.yaml` (the suite filter is a glob over `tests/*.yaml`):

```yaml
description: One-line intent
prompt: |
  <message sent to the model under test>
checks:
  - id: used-glob
    type: tool_used            # tool_used | tool_not_used | max_turns | max_output_tokens
    spec: Glob                 #   | output_matches | output_not_matches | llm_judge
  - id: quality
    type: llm_judge
    rubric: |
      PASS if … FAIL otherwise.
```

Deterministic check types live in `score-run.py` (`run_checks`); `llm_judge` checks are scored only by `llm-judge.py`. Token caps (`max_output_tokens`) are a noisy proxy for brevity — set them generously to catch genuine runaways and put the real "is it concise / correct" assertion in an `llm_judge` rubric (see `tests/05-concise-no-preamble.yaml`).

## Iterating on `prompts/probe.md`

The loop is: `just run` → `just compare` → for each probe-only regression, diff against the Piebald reference (`upstream/PINNED_VERSION` pins the commit) to find the default-prompt fragment that produced the missing behaviour → copy *just that fragment* into `prompts/probe.md` → re-run the affected test with `just run-one`. **Record every probe change in `docs/iteration-log.md`**, citing the run-id whose evidence drove it — that log is the experiment's findings.

Read `docs/methodology.md` for the full scoring rubric and `docs/decision-analysis.md` for the 10 concrete frictions between the global rules and the default prompt that motivate the whole experiment.

## Commits

Use `claude-probe` as the conventional-commit scope (e.g. `feat(claude-probe): …`, `chore(claude-probe): …`). It deliberately matches **no** release-please package, so work here never triggers a plugin release.

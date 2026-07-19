# skill-catalog-routing

An A/B testing harness measuring whether the **skill catalog** (the concatenated
`name + description` of every skill) helps a model **route** a user request to
the right skill — and how short those descriptions can be while still working.

## The questions

1. **Does the catalog help?** Compare a router with the full catalog in context
   against one with no catalog (or names only).
2. **How short can descriptions be** while still enabling correct selection?
3. **Could shorter be *better*** — not just cheaper, but fewer false triggers?
4. **How does this vary by model** (haiku / sonnet / opus)?

This mirrors the sibling `experiments/claude-probe/` harness: `claude -p` +
`--system-prompt-file`, deterministic scoring, `compare.py` rollups, gitignored
`results/`, commit scope = experiment name (matches no release-please package).

## The arms — a monotone information ladder

The independent variable is `catalog`: how much of the skill listing the router
sees. Each shorter band is a genuine token-subset of the next.

| arm | catalog | ~tokens over base | role |
|-----|---------|-------------------|------|
| C0 | none (task only) | 0 | null control (free-recall) |
| C1 | names only | ~4.2k | isolates the value of descriptions |
| C2 | names + `Use when <first trigger>` ≤40c | ~7.2k | minimal trigger (trigger-first) |
| C2d | names + capability phrase ≤40c | ~7.9k | domain-first, token-matched to C2 |
| C3 | names + `Use when <triggers>` ≤80c | ~11.0k | mid (trigger-first) |
| C3d | names + capability phrase ≤80c | ~10.8k | domain-first, token-matched to C3 |
| C5 | names + capability head + `Use when <trigger>` ≤80c | ~11.5k | compact best-of-both (keeps `Use when`) |
| C4 | names + full description (current) | ~20.7k | upper anchor (status quo) |

The `C2d`/`C3d`/`C5` arms are the **domain-preserving** follow-up: the haiku
ladder showed trigger-only shortening (`C2`/`C3`) stalls because it drops the
leading capability/domain phrase. `C2d`/`C3d` keep that phrase instead (dropping
the `Use when` tail) at equal budget; `C5` keeps a compressed capability head
**plus** a `Use when` trigger so it also stays valid for the real auto-invocation
matcher. `build-catalogs.py` emits all seven catalog variants.

**Measured base**: a router with no catalog costs ~23k input tokens (the user's
global `~/.claude` memory, a fixed additive constant across all arms). Adding the
full catalog brings it to ~43.7k. Crucially the base does **not** contain Claude
Code's own ~22k skill listing — `--system-prompt-file` replaces the built-in
prompt and strips it, so the only skill vocabulary the model sees is the one we
inject, for every arm including C0.

## Layout

| path | contents |
|------|----------|
| `catalogs/` | committed catalog variants (`catalog.{names,short,medium,full}.json`) + `catalog_manifest.json` (source SHA, hashes, provenance) |
| `prompts/system-router.md` | the catalog-free router system prompt (JSON-out contract) |
| `conditions.yaml` | 15 arms = 3 models × 5 catalog variants (effort fixed low) |
| `tasks/*.yaml` | 70 labeled tasks: 30 route, 20 near-miss (10 pairs), 20 abstention (`gold: NONE`) |
| `scripts/build-catalogs.py` | frontmatter → the 4 variants + manifest (structure-aware shortening, `--validate`) |
| `scripts/check-tasks.py` | schema + lexical-leakage gate over the task set |
| `scripts/build-arm-prompt.sh` | assemble router + injected catalog for an arm |
| `scripts/run-one.sh` / `run-suite.sh` | one triple / the cartesian sweep |
| `scripts/score-run.py` | parse the router's last-line JSON, match id ↔ gold |
| `scripts/compare.py` | per-condition routing metrics → `results.json` + `report.md` |
| `scripts/render-frontier.py` | accuracy-vs-length curves + per-model degradation slope |
| `scripts/measure-catalog-tokens.sh` | real input tokens per catalog variant |
| `results/` | gitignored transcripts + reports |

## Quickstart

```sh
# (Re)build + validate the catalogs from SKILL.md frontmatter.
scripts/build-catalogs.py --validate

# Validate the task set (schema + leakage gate).
scripts/check-tasks.py --strict

# PILOT GATE (~120 calls): haiku, C1 (names) vs C4 (full), 20-task subset, 3 runs.
# The instrument MUST separate C1 from C4; if it doesn't, the task set is leaky.
bash scripts/run-suite.sh \
  --tasks r01,r02,r03,r04,r05,r06,r07,r08,r09,r10,n01,n02,n03,n04,n05,n06,z01,z02,z03,z04 \
  --conditions haiku-C1,haiku-C4 --runs 3 --run-id pilot
scripts/compare.py pilot
scripts/render-frontier.py pilot

# One (task, condition, run) for iteration.
bash scripts/run-one.sh r01 haiku-C4 1 results/adhoc

# Real token cost per catalog variant.
bash scripts/measure-catalog-tokens.sh
```

If `just` is installed, the same recipes are `just <recipe>` (see `justfile` /
the root `just skill-catalog-routing::<recipe>`).

## Metrics

Per (model × arm), pooled over runs: **top-1** routing accuracy, **near-miss**
discrimination accuracy, **top-2** (runner-up counts) on near-miss,
**false-trigger** rate (fraction of `gold: NONE` where a skill was wrongly
picked), **abstain** accuracy, and **parse-fail** rate. `render-frontier.py`
turns these into the accuracy-vs-tokens curve, the false-trigger curve, and the
per-model degradation slope (C4−C2) — the portability signal.

## Cost discipline

Every run is a real `claude -p` call. The full matrix (15 arms × 70 tasks × N
runs) is large, so it is **gated**: the haiku pilot (2 arms × 20 tasks × 3 runs)
must first show a clean C4 − C1 separation; only then does the haiku full ladder
run, then sonnet/opus on a clean monotone curve. Effort is fixed `low` (routing
is shallow classification; higher effort lets the model reason around a terse
catalog and washes out the length signal). Same-arm calls reuse a cached system
prompt, so cost drops sharply after warmup.

## Not a plugin

Lives under `experiments/` deliberately — a dogfooding harness, not something to
publish. Not in `.claude-plugin/marketplace.json`, not release-please-versioned,
not wired into plugin-compliance scripts. Commit scope: `skill-catalog-routing`.

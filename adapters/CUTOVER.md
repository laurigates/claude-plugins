# Cutover gate — freezing the adapter threshold

The go/no-go gate for [#2093](https://github.com/laurigates/claude-plugins/issues/2093)
(remove the pi tier system) and
[#2094](https://github.com/laurigates/claude-plugins/issues/2094) (retire the
rulesync export). Per the `tool-migration-cutover` rule and ADR-0022, neither
cutover may proceed until the adapter is **observed operational on the shipping
configuration** — not merely configured.

This procedure runs **locally, never in CI**. CI's `GATE STATUS` asserts only
that the eval machinery ran; it never evaluates the cutover threshold.

> Until 2026-07 this document existed only in an ephemeral scratchpad, while
> 20+ shipped source files cited it as "DESIGN §5.6". It now lives in the repo.

## Status

**Frozen 2026-07-22** at `main_hit_at_k_min = 0.57`, measured 0.6727 on the
hybrid ranker over the 55-task main stratum (commit `8fa66076`). Both cutovers
are unblocked by a green gate; executing them is separate work.

## 1. The measurement

```
ollama pull nomic-embed-text
cd adapters && bun eval/run-eval.ts --with-embeddings
```

Read `HIT_AT_K` off `=== RETRIEVAL_MAIN ===`. The run is only admissible if
**all** of these hold on the *same* run:

| Signal | Required | Why |
|---|---|---|
| `MODE=` | `hybrid` | The BM25 smoke ranker is not what the bindings ship |
| `DEGRADED_QUERIES=` | `0` | Per-query embedding failures are invisible otherwise (see Guards) |
| `=== GATE === STATUS=` | `PASS` | Machinery ran; schema + integrity invariants hold |

Use a **cold cache** so the corpus is genuinely embedded this run:

```
mv "${XDG_CACHE_HOME:-$HOME/.cache}/claude-plugins-adapters/embeddings" /tmp/emb-bak
```

## 2. The check that cannot be faked

If `--with-embeddings` produces byte-identical rankings to the BM25 run, the
embedding side contributed nothing regardless of what `MODE=` claims:

```
bun eval/run-eval.ts --with-embeddings | tee /tmp/hybrid.out
bun eval/run-eval.ts | tee /tmp/smoke.out
diff <(jq -S '[.perTask[]|{id,rankedIds}]' "$HYBRID_JSON") <(jq -S '[.perTask[]|{id,rankedIds}]' "$SMOKE_JSON") && echo "IDENTICAL — investigate"
```

At the 2026-07-22 freeze, 70 of 71 tasks ranked differently. Cross-check that
the cache materialized with the right model — a bm25-only run **never** writes
this file:

```
jq '{model, dims, n: (.entries|length)}' "${XDG_CACHE_HOME:-$HOME/.cache}/claude-plugins-adapters/embeddings/"*.json
```

## 3. Derive the threshold

**`floor((measured − 0.10) × 100) / 100`** on the main stratum. Floor, not
round. At the freeze: `floor((0.6727 − 0.10) × 100) / 100 = 0.57`.

## 4. Freeze it

Replace the `status` string in `eval/tasks.json` `gate.cutover_thresholds`
**wholesale** with `main_hit_at_k_min` plus its provenance. `validateTaskSet`
enforces exactly-one-of (`status` containing "unfrozen" | numeric threshold),
the `[0, 1]` range, an allow-list of keys, and the presence of every
provenance field:

| Field | Why it is provenance, not decoration |
|---|---|
| `measured_main_hit_at_k`, `margin` | Lets a successor re-derive the number without re-running |
| `mode` | The threshold is hybrid-scoped; a BM25 run reports `NA_BM25` |
| `embedding_model`, `embedding_model_digest` | A model swap invalidates the measurement |
| `embedding_dimensions`, `prefix_scheme` | **Both participate in the cache key** — changing either silently re-embeds the corpus and moves the measurement |
| `corpus_entries`, `task_count_main_stratum` | The denominators the rate is over |
| `frozen_at`, `frozen_commit`, `procedure` | When, against what tree, by what method |

## 5. Guards — why a hybrid run cannot silently be a BM25 run

Three independent levels, all raising **gate issues** (so a fake hybrid run
reports `GATE STATUS=FAIL`, not a clean `PASS`):

1. **Mode.** The smoke-mode invariant was one-directional: only
   `!withEmbeddings && mode !== "bm25-only"` was checked, so a
   `--with-embeddings` run that fell back to `bm25-only` still printed
   `STATUS=PASS` and exited 0. The converse is now checked too.
2. **Per-query degradation.** `core/search.ts` deliberately swallows per-query
   embedding failures so search never hard-fails on the soft dependency — which
   means `mode` alone is **not** a sufficient signal: the probe and corpus batch
   can succeed (→ `mode === "hybrid"`) while every query silently falls back.
   `SkillIndex.degradedQueries` counts them; any non-zero count under
   `--with-embeddings` is a gate issue. `tests/search-degradation.test.ts`
   stands up a stub serving valid vectors for `search_document:` and 500s for
   `search_query:` to reach exactly that state.
3. **Score shape.** RRF is hard-capped at `2/RRF_K = 0.0333`; raw BM25 tops
   ~1–10. A "hybrid" run whose max score exceeds 0.05 is not hybrid.

## 6. Stratification is pinned to tags, not to `pi/tiers.yaml`

`partitionByStratum(scores)` takes **no `repoRoot`** by construction. The
earlier tiers-derived partition would have inverted the gate: when #2093
deletes `pi/tiers.yaml`, the in-tier metrics became `null` and the frozen
threshold would evaluate **FAIL forever** — breaking exactly when it is meant
to authorize the deletion.

Pinning to the task set's own `stratum:` tags redefines both strata:

| | tiers.yaml-derived (retired) | tag-pinned (current) |
|---|---|---|
| main / in-tier | 27 tasks | **55** (paraphrase 32 + ambiguity 15 + terse 8) |
| headroom / excluded | 36 tasks | **8** (`stratum:excluded`) |

`RETRIEVAL_MAIN` now means exactly *hybrid retrieval quality on the main
positives* and asserts nothing about any baseline. The ADR §5.2 property that
"in-tier baseline reachability is 1.0 by construction" is **retired** — do not
reason from it. The pre-freeze BM25-only figure (in-tier hit@5 0.370) is on the
old 27-task denominator and must not be reused.

`derivePiBaseline` survives only for the informational `BASELINE_PI_TOKENS`
figure and the token-calibration meta-test, both of which already degrade to
`NA` / `skipIf` when `pi/tiers.yaml` disappears.

## 7. Refuted constructions

Recorded, not silently deleted (`validate-adversarial-constructions`).

- **Zero-delta membership gate** (v1 draft — refuted 2026-07-19 by review
  simulation). Construction: `gate: { min_hit_at_k_delta: 0 }` against baseline
  listing membership, asserted in CI. Why it failed: in-tier baseline
  membership was 100% **by construction** (a task was in-tier iff its expected
  skill was in the installed set), so zero delta demanded adapter hit@5 = 100%;
  the BM25 smoke ranker measured 44.4% (16/36). The aggregate reading
  (55.6% vs 57.1%) also failed, and committed exactly the strata-mixing the
  design forbids. Meta-test 1 was blind to the degeneracy because its "correct
  variant" was the oracle, not the shipping ranker. Resolution: the CI/local
  gate split, plus §6's tag pinning which removes the membership coupling
  entirely.
- **`neg_floor` scalar** (v1 draft — refuted in the same simulation).
  Construction: negatives pass when no skill scores above a single `neg_floor`
  in `tasks.json`. Why it failed: `search()` returns rank-derived RRF scores in
  hybrid mode (~1/61..2/61, essentially query-independent) and unbounded raw
  BM25 scores in smoke mode — **different units per mode** — and measured
  negative top-1 scores fully overlap positive ones even within one mode. The
  push channel also applies no floor, so the metric referenced a mechanism that
  does not exist. Resolution: report-only margin distributions; a floor is
  deferred until the push channel actually has one. (The 2026-07-22 hybrid run
  reproduces the overlap: neg P50 0.0010 vs pos P50 0.0010.)

## 8. Still open for #2094

The `BASELINE_OC_TOKENS_ESTIMATED` figure is a pi-template proxy,
**uncalibrated** — OpenCode embeds its listing in a different template. A real
OpenCode measurement session (mirroring the pi 111 tok/skill measurement, with
its own ±20% calibration assertion) remains a #2094 prerequisite. This freeze
does not supply it.

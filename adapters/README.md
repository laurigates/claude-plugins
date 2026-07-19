# adapters/ — harness-agnostic skill discovery (ADR-0022)

A plain-TypeScript skill-discovery core over this marketplace's 400+ skills,
plus the retrieval eval harness that gates the pi/OpenCode cutovers. Foreign
harnesses (pi, OpenCode) get a `search_skills` pull tool and a per-turn
top-k push injection instead of an uncapped static listing; delivery is
always the model **reading the SKILL.md path** — skills are never copied.

Architecture: [`docs/adrs/0022-adapter-over-export-for-foreign-harnesses.md`](../docs/adrs/0022-adapter-over-export-for-foreign-harnesses.md).
Scope here (#2089): `core/` + `eval/` + tests. The harness bindings are
**landing in [#2090](https://github.com/laurigates/claude-plugins/issues/2090)
(pi) and [#2091](https://github.com/laurigates/claude-plugins/issues/2091)
(OpenCode)** — the consumer wiring below is documented ahead so the shape is
stable, but the binding files do not exist yet.

## Layout

| Path | What |
|------|------|
| `core/` | Indexer (marketplace scan + DIY frontmatter parse + compatibility filter), BM25 (Lucene IDF, k1=1.2, b=0.75), ollama `/api/embed` client (`search_document:`/`search_query:` prefixes, BM25 fallback), RRF fusion (k=60), L2-normalized Float32Array vector index, XDG content-hash embedding cache, shared render templates |
| `eval/` | `tasks.json` (committed golden task set, k=5), `run-eval.ts` runner, ranker seam (`hybrid \| bm25Only \| embeddingOnly \| random(seed) \| oracle \| nameSubstring \| descriptionSubstring`), baseline derivation (`pi/tiers.yaml` + the export-opencode glob, computed offline), `results/` (gitignored per-run output) |
| `pi/` | pi binding — **#2090, not yet present** |
| `opencode/` | OpenCode binding (#2091) — named `SkillDiscoveryPlugin` plugin: `search_skills` tool (pull), `experimental.chat.system.transform` push injection + defensive listing strip, `experimental.chat.messages.transform` ranking-input capture, `[path, options]` tuple config |
| `tests/` | `bun test` suites: frontmatter diff vs `Bun.YAML`, BM25 goldens + committed `rank_bm25` fixture, indexer over the mini-marketplace fixture, cache, fusion, embeddings fallback matrix, eval meta-tests |

There is **no build step**: `tsconfig.json` is `noEmit` and both harnesses
consume `.ts` source directly (jiti / Bun). This also sidesteps the repo-wide
`dist/` gitignore trap — no compiled output exists to be silently swallowed.

## Dev commands

```
cd adapters && bun install        # once per checkout
bunx tsc --noEmit                 # type gate (bun runs TS but does not check)
bunx biome ci .                   # lint + format check
bun test                          # all suites incl. eval meta-tests
bun eval/run-eval.ts              # BM25-only smoke eval (no network)
bun eval/run-eval.ts --with-embeddings   # hybrid, needs ollama at localhost:11434
```

Justfile equivalents (repo root): `just adapters-test`, `just adapters-check`,
`just eval-adapter`, `just eval-adapter-hybrid`. CI runs the same commands in
`.github/workflows/test-adapters.yml`.

## Consumer wiring

**Step 1 for both harnesses is always:**

```
cd <checkout>/claude-plugins/adapters && bun install
```

This populates `adapters/node_modules`, which serves the OpenCode binding,
`eval/`, and `tests/`. The pi binding deliberately resolves nothing from it
at runtime (pi's extension loader aliases `typebox` and pi types to its own
bundled copies); the install still matters for type-checking and tests.

### pi (landing in #2090)

```jsonc
// <project>/.pi/settings.json
{ "extensions": ["/abs/path/to/claude-plugins/adapters/pi/index.ts"] }
```

- Registers a `search_skills` tool (pull) and injects pins + top-k into the
  system prompt per turn via `before_agent_start` (push), replacing the
  native `<available_skills>` listing.
- Caveat: project-scope extensions load only post-trust; in `-p`/json/rpc
  modes with `defaultProjectTrust: ask` the extension is silently skipped —
  prefer global registration (`~/.pi/agent/settings.json`) or `--approve`
  for headless runs.
- Config: `~/.pi/agent/skill-discovery.json`, overridden key-by-key by
  project `.pi/skill-discovery.json` (`repoRoot`, `k`, `endpoint`, `model`,
  `pins`, `push`). Missing file = all defaults.
- Run consumers with no natively installed marketplace skills; `--no-skills`
  is optional (the binding never feeds the native loader).

### OpenCode

Step 1 (as above):

```
cd <checkout>/claude-plugins/adapters && bun install
```

The plugin file resolves `@opencode-ai/plugin` from `adapters/node_modules`
— OpenCode's background-install into config dirs does not cover a
checkout-resident plugin. A missing install surfaces as an explicit
"run `bun install` in `<checkout>/adapters`" error at plugin load.

Step 2 — wire the plugin (path-like specs resolve relative to the declaring
config file; the tuple form carries the options):

```jsonc
// opencode.json
{
  "plugin": [["./../claude-plugins/adapters/opencode/index.ts", { "k": 5, "pins": [] }]],
  "permission": { "skill": "deny" }
}
```

- `permission.skill = "deny"` is the primary native-listing suppression: it
  removes the `<available_skills>` block and the native `skill` tool in one
  stable config line. (`"tools": { "skill": false }` is a deprecated-surface
  alias — the top-level `tools` boolean map is normalized into root
  `permission` upstream.) Delivery is the model reading the path
  `search_skills` returns. The binding also defensively strips any
  remaining `<available_skills>` element in `system.transform` for
  consumers who forgot the config line.
- Options (all optional): `repoRoot` (default: this checkout, derived from
  the plugin file's location), `k` (push top-k, default 5), `endpoint` /
  `model` (embeddings; default `http://localhost:11434` /
  `nomic-embed-text`), `pins` (skill ids always injected first; unknown ids
  warn and skip). Invalid values warn and fall back to defaults.
- Push injection rides `experimental.chat.system.transform` (declared
  unconditionally — older OpenCode versions silently never call unknown
  hook names) and ranks against the latest user message captured via
  `experimental.chat.messages.transform`; the first turn injects pins only,
  and the ranked list can be one turn stale if the hooks race — the binding
  is pull-first by design. At init the binding logs the server version from
  `GET /global/health` (informational, never gating) to aid "why no
  injected block" debugging.

## Embeddings (soft dependency)

Hybrid ranking needs a local [ollama](https://ollama.com) with
`nomic-embed-text` pulled (`ollama pull nomic-embed-text`). When the
endpoint is unreachable, times out, or errors, the index degrades to
BM25-only for the session — search never hard-fails on the embedding side.
Embeddings are cached content-addressed under
`${XDG_CACHE_HOME:-~/.cache}/claude-plugins-adapters/embeddings/` (never
in-repo).

## Eval harness

`bun eval/run-eval.ts` emits the structured contract (DESIGN §5.3):

```
=== RETRIEVAL_IN_TIER === HIT_AT_1= HIT_AT_K= MRR= BASELINE_ARM=PRESENT|ABSENT
=== RETRIEVAL_EXCLUDED_STRATUM === HIT_AT_1= HIT_AT_K= MRR=
=== NEGATIVES === TOP1_MARGIN_NEG_P50= ... (report-only)
=== TOKENS === BASELINE_PI_TOKENS= BASELINE_OC_TOKENS_ESTIMATED= ADAPTER_TOKENS=
=== CUTOVER === STATUS=UNFROZEN|PASS|FAIL   (informational; frozen only by the §5.6 procedure)
=== GATE === STATUS=PASS|FAIL               (machinery only — the CI assertion)
```

Retrieval/token metrics are informational in CI; the correctness teeth are
the meta-tests in `tests/eval-meta.test.ts` (random-fails-every-seed /
oracle-passes, substring-ranker separation, per-skill token calibration
111±20%, trigram leakage lint, schema checks). The #2093/#2094 cutover
thresholds are frozen only by the documented local hybrid-simulation
procedure, never by CI. `BASELINE_OC_TOKENS_ESTIMATED` is a pi-template
proxy, uncalibrated — a real OpenCode measurement session is a #2094
prerequisite.

To regenerate the BM25 reference fixture (only when deliberately taking a
fresh corpus snapshot): `uv run tests/gen-bm25-reference.py`.

## What this package is not

- Not a marketplace plugin (no `-plugin` suffix, no marketplace entry, no
  release-please package — `feat(adapters)` commits bump nothing).
- Not published to npm (`"private": true`); harnesses load the `.ts` source
  from this checkout.
- Not a replacement for the still-operational `pi/tiers.yaml` +
  `scripts/install-pi.sh` and rulesync export pipelines — those stay
  authoritative until the eval gate passes and #2093/#2094 execute their
  documented cutover steps.

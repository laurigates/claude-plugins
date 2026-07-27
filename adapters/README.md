# adapters/ — harness-agnostic skill discovery (ADR-0022)

A plain-TypeScript skill-discovery core over this marketplace's 400+ skills,
plus the retrieval eval harness that gates the pi/OpenCode cutovers. Foreign
harnesses (pi, OpenCode) get a `search_skills` pull tool and a per-turn
top-k push injection instead of an uncapped static listing; delivery is
always the model **reading the SKILL.md path** — skills are never copied.

Architecture: [`docs/adrs/0022-adapter-over-export-for-foreign-harnesses.md`](../docs/adrs/0022-adapter-over-export-for-foreign-harnesses.md).
`core/` + `eval/` + tests landed in
[#2089](https://github.com/laurigates/claude-plugins/issues/2089); the pi
binding (`pi/`) in
[#2090](https://github.com/laurigates/claude-plugins/issues/2090); the
OpenCode binding (`opencode/`) in
[#2091](https://github.com/laurigates/claude-plugins/issues/2091).

## Layout

| Path | What |
|------|------|
| `core/` | Indexer (marketplace scan + DIY frontmatter parse + compatibility filter), BM25 (Lucene IDF, k1=1.2, b=0.75), ollama `/api/embed` client (`search_document:`/`search_query:` prefixes, BM25 fallback), RRF fusion (k=60), L2-normalized Float32Array vector index, XDG content-hash embedding cache, shared render templates |
| `CUTOVER.md` | The #2093/#2094 gate: measurement procedure, the frozen threshold + provenance, the hybrid-integrity guards, and the refuted gate constructions |
| `eval/` | `tasks.json` (committed golden task set, k=5), `run-eval.ts` runner, ranker seam (`hybrid \| bm25Only \| embeddingOnly \| random(seed) \| oracle \| nameSubstring \| descriptionSubstring`), baseline derivation (`pi/tiers.yaml` + the export-opencode glob, computed offline), `results/` (gitignored per-run output) |
| `pi/` | pi binding (#2090) — default-exported extension factory: `search_skills` pull tool + `before_agent_start` push injection, `skill-discovery.json` config |
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

### pi

**Try it with zero config changes** (nothing mutated — `-e` loads the extension
for one run):

```
just pi-adapter-check    # verify prereqs (node_modules + ollama), no model call
just pi-adapter          # launch pi with the extension; add -p "…" for one-shot
```

`just pi-adapter` expands to `pi -e <checkout>/adapters/pi/index.ts`. The binding
derives `repoRoot` from its own location, so no config file is needed. Confirm
the replacement worked: with the extension the system prompt carries ~5 injected
skills instead of the ~95-skill native listing (measured 92→5 on pi 0.80.7).

**To make it permanent:**

```
just pi-adapter-register     # append to ~/.pi/agent/settings.json extensions[]
just pi-adapter-unregister   # reverse it
```

`pi-adapter-register` is idempotent and non-clobbering — it appends only the
one absolute path to the `extensions` array, preserves every other key, creates
the file if absent, and writes it mode `600`. Target a project scope instead
with `PI_SETTINGS=<project>/.pi/settings.json just pi-adapter-register` (but see
the Trust caveat below — global is preferred). Equivalent by hand:

```jsonc
// ~/.pi/agent/settings.json — prefer global over project scope (Trust caveat below)
{ "extensions": ["/abs/path/to/claude-plugins/adapters/pi/index.ts"] }
```

- **`extensions`, not `packages`.** pi loads a local extension file from the
  `extensions` array. That is a *different* mechanism from the `packages` array
  that `pi install` / `pi remove` / `pi list` manage (npm/git/local-path
  sources) — so `pi list` does **not** show the adapter, and that is expected,
  not a failure. `pi-adapter-register` edits `extensions` for exactly this
  reason; `pi install` would write the wrong key.
- `cd <checkout>/adapters && bun install` is required for `tsc` / `bun test`
  but **not** at pi runtime — pi's extension loader aliases `typebox` to its
  bundled copy and the pi types are `import type`-only. Skipping it surfaces as
  an explicit "run `bun install` in `<checkout>/adapters`" error, not a bare
  resolution stack.
- You do **not** need to uninstall the native tier skills first — the binding
  strips `<available_skills>` and injects in its place, so the token saving
  lands whether or not `~/.pi/agent/skills/` is populated. (Removing the tier
  system is separate work, gated behind #2093.)

- Registers a `search_skills` tool (pull) and injects pins + ranked top-k
  into the system prompt per turn via `before_agent_start` (push), replacing
  the native `<available_skills>` listing in place (before the
  `Current working directory:` line). The binding never contributes paths
  via `resources_discover` — that would refeed the uncapped native listing
  it exists to replace.
- **Trust caveat**: project-scope extensions load only **post-trust**; in
  `-p`/json/rpc modes with `defaultProjectTrust: ask` (the default) the
  extension is **silently skipped** — prefer global registration
  (`~/.pi/agent/settings.json`) or `--approve` for headless runs.
- Config: `~/.pi/agent/skill-discovery.json`, overridden key-by-key by
  project `.pi/skill-discovery.json`. Missing file = all defaults
  (`repoRoot` derives from the extension's own location in this checkout):

```jsonc
// .pi/skill-discovery.json — all keys optional
{
  "repoRoot": "/abs/path/to/claude-plugins", // marketplace checkout to index
  "k": 5,                                    // push top-k (and search_skills default)
  "endpoint": "http://localhost:11434",      // embedding endpoint
  "model": "nomic-embed-text",               // embedding model
  "pins": ["git-plugin:git-commit"],         // always injected; ranked results fill k after pins
  "push": true                               // false = pull-only (debug/ablation)
}
```

  Unknown pins warn and are skipped; malformed config files are ignored
  with a warning (never fatal to the session). Warnings — including the
  BM25-only degradation notice when the embedding endpoint is unreachable —
  are emitted once per session on stderr, prefixed `skill-discovery:`.
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
=== EVAL === MODE=hybrid|bm25-only K= TASKS= DEGRADED_QUERIES=
=== RETRIEVAL_MAIN === HIT_AT_1= HIT_AT_K= MRR= TASKS=
=== RETRIEVAL_HEADROOM === HIT_AT_1= HIT_AT_K= MRR= TASKS=
=== NEGATIVES === TOP1_MARGIN_NEG_P50= ... (report-only)
=== TOKENS === BASELINE_PI_TOKENS= BASELINE_OC_TOKENS_ESTIMATED= ADAPTER_TOKENS= BASELINE_ARM=PRESENT|ABSENT
=== CUTOVER === STATUS=UNFROZEN|PASS|FAIL|NA_BM25   (informational; see CUTOVER.md)
=== GATE === STATUS=PASS|FAIL                       (machinery only — the CI assertion)
```

The two strata are pinned to the task set's own `stratum:` tags, never derived
from `pi/tiers.yaml` — `RETRIEVAL_MAIN` is paraphrase + ambiguity + terse (55
tasks), `RETRIEVAL_HEADROOM` is `stratum:excluded` (8). `MAIN` means exactly
*retrieval quality on the main positives* and asserts nothing about any
baseline. The threshold is hybrid-scoped, so the BM25-only CI run reports
`CUTOVER STATUS=NA_BM25` rather than a bogus `FAIL`.

Retrieval/token metrics are informational in CI; the correctness teeth are
the meta-tests in `tests/eval-meta.test.ts` (random-fails-every-seed /
oracle-passes, substring-ranker separation, per-skill token calibration
111±20%, trigram leakage lint, schema checks, hybrid-integrity guards).
The #2093/#2094 cutover threshold is frozen only by the local procedure in
[`CUTOVER.md`](CUTOVER.md), never by CI. `BASELINE_OC_TOKENS_ESTIMATED` is a
pi-template proxy, uncalibrated — a real OpenCode measurement session is a
#2094 prerequisite.

## Freezing the cutover threshold

Full procedure, guards, and the refuted constructions:
[`CUTOVER.md`](CUTOVER.md). Frozen 2026-07-22 at `main_hit_at_k_min = 0.57`
(measured 0.6727 hybrid). The measurement:

```
ollama pull nomic-embed-text
mv "${XDG_CACHE_HOME:-$HOME/.cache}/claude-plugins-adapters/embeddings" /tmp/emb-bak
cd adapters && bun eval/run-eval.ts --with-embeddings
```

A run is admissible only if the *same* run reports `MODE=hybrid`,
`DEGRADED_QUERIES=0`, and `GATE STATUS=PASS`. Three guards make a fake hybrid
run a `GATE FAIL` instead of a silent pass: the mode check (both directions),
the per-query degradation counter (`core/search.ts` swallows those failures
for the shipping path, so `mode` alone is not sufficient), and a score-shape
check (RRF caps at 0.0333; raw BM25 tops ~1–10).

To regenerate the BM25 reference fixture (only when deliberately taking a
fresh corpus snapshot): `uv run tests/gen-bm25-reference.py`.

## What this package is not

- Not a marketplace plugin (no `-plugin` suffix, no marketplace entry, no
  release-please package — `feat(adapters)` commits bump nothing).
- Not published to npm (`"private": true`); harnesses load the `.ts` source
  from this checkout.
- Not a replacement for the still-operational `pi/tiers.yaml` +
  `scripts/install-pi.sh` and rulesync export pipelines — those stay
  authoritative until #2093/#2094 execute their documented cutover steps.
  The eval gate now passes (frozen 2026-07-22), so those issues are
  unblocked, but nothing in this package removes the incumbents.

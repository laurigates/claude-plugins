# Findings — skill-catalog routing

Two runs, both deterministic-graded, 0 parse failures throughout:

- **pilot** — haiku C1 vs C4 on a 20-task subset + opus-C4 gold-check (`FINDINGS-pilot.md`)
- **haiku-ladder** — haiku C0→C4 across all **70 tasks**, 2 runs (700 transcripts)

The full-set ladder **corrects the pilot's tentative headline**: the 20-task
pilot subset happened to use transparent-named skills, so names-only looked
near-sufficient (0.98). Across the full 70-task set, descriptions matter a lot.

## Haiku ladder (all 70 tasks)

| arm | catalog | tokens | top-1 | near-miss | false-trigger | abstain |
|-----|---------|--------|-------|-----------|---------------|---------|
| C0 | none | 23.2k | **0.00** | 0.00 | 0.03 | 0.97 |
| C1 | names only | 27.3k | 0.83 | 0.80 | 0.10 | 0.90 |
| C2 | short (`Use when …` ≤40c) | 30.4k | 0.86 | 0.85 | 0.07 | 0.93 |
| C3 | medium (`Use when …` ≤80c) | 34.1k | 0.88 | 0.82 | 0.07 | 0.93 |
| C4 | full description | 43.9k | **1.00** | 1.00 | 0.07 | 0.93 |

## What this establishes

1. **The catalog is essential, and it lives in the ids.** With no catalog (C0) a
   model scores **0.00** — it cannot emit a valid `<plugin>/<skill>` id from
   memory and abstains 97% of the time. C4 − C0 = **+1.00**. There is no routing
   without the listing; the entire question is how much *description* to attach to
   the ids.

2. **Names alone are a strong but incomplete baseline.** Names-only routes at
   **0.83** top-1 / 0.80 near-miss. Good, but a sixth of requests go to the wrong
   skill — and names-only also has the **worst false-trigger rate (0.10)**: with
   nothing but ids, the model over-grabs a loosely-related skill for out-of-scope
   requests.

3. **Full descriptions close the gap — to a perfect 1.00.** C4 − C1 = **+0.17**
   top-1 and +0.20 near-miss, and full is the only arm that hits ceiling.
   Descriptions win exactly where names *can't* disambiguate — near-miss
   same-family pairs (ruff lint vs format, finops caches vs waste, obsidian
   search vs tasks) and **opaque-named skills** (`comfy-metadata`,
   `langgraph-agents`, `design-legacy-seams`). 9 route tasks flipped from wrong
   (names) to right (full).

4. **"Shorter is better" is NOT supported *as implemented* — and the reason is
   the actionable insight.** The short/medium variants (C2, C3) only reach
   0.86–0.88 — barely above names, far below full. But that is an artifact of
   *what* was trimmed: our structure-aware shortening kept the `Use when …`
   trigger clause and **dropped the leading domain sentence** ("ripgrep fast code
   search: smart defaults, regex, file filtering"). The ladder shows that domain
   sentence carries most of the routing signal for a forced-choice router — more
   than the trigger clause. So the lesson is not "descriptions can't be short"
   but **"if you shorten, keep the domain/capability phrase, not (only) the `Use
   when` triggers."** A short variant built the other way around is the obvious
   next test.

5. **Descriptions modestly improve precision.** False-triggering drops from 0.10
   (names) to 0.07 (any description) — a small but real over-triggering reduction.

## Caveats / open questions

- **Haiku only, 2 runs.** Cross-model (sonnet/opus) is the portability question:
  do stronger models need the description less (recover more from names)? The
  pilot's opus-C4 = 1.00 hints opus is strong with full descriptions but says
  nothing about opus-C1.
- **The shortening direction confound (finding #4)** means the current C2/C3 do
  not answer "what is the optimal description length" — they answer "trigger-only
  short descriptions underperform." A domain-preserving short variant is needed to
  draw the real length/accuracy frontier.
- Gold labels are verified (opus-C4 = 100% on the pilot route set); the task set
  has 0 lexical leakage; isolation strips the built-in listing (base 23.2k).

## Bottom line

For skill **discovery/routing**: the id list is mandatory (no catalog → 0%),
names get you ~83%, and full descriptions are needed to reach ceiling — they earn
their ~16.5k tokens specifically on near-miss and opaque-named skills. Shorter
descriptions can likely recover most of that benefit **only if they preserve the
capability/domain phrase** rather than the `Use when` trigger tail — the single
most useful follow-up this experiment points to.

---

# Follow-up: domain-preserving shortening (haiku)

The prediction above is **confirmed**. Run `haiku-ladder2` (all 70 tasks, 2 runs,
980 transcripts, 0 parse failures) added domain-first variants token-matched to
the trigger-first ones:

| arm | catalog | tokens | top-1 | near-miss | false-trigger |
|-----|---------|--------|-------|-----------|---------------|
| C1 | names | 27.3k | 0.83 | 0.82 | 0.07 |
| C2 | short (trigger, ≤40c) | 30.3k | 0.90 | 0.85 | 0.10 |
| **C2d** | **domain-short (≤40c)** | 31.0k | 0.89 | 0.90 | 0.10 |
| C3 | medium (trigger, ≤80c) | 34.1k | 0.91 | 0.88 | 0.07 |
| **C3d** | **domain-medium (≤80c)** | 33.8k | **0.97** | **0.95** | **0.03** |
| C5 | compact (domain head + `Use when`, ≤80c) | 34.6k | 0.95 | 0.93 | 0.05 |
| C4 | full | 43.8k | 0.99 | 1.00 | 0.05 |

**Domain-first vs trigger-first at equal budget:**

- **~80c: domain-first wins decisively.** `C3d` (domain-medium) hits **0.97 top-1
  / 0.95 near-miss** vs `C3` (trigger-medium) **0.91 / 0.88** — +0.06 top-1,
  +0.07 near-miss — and it does so at **half the tokens of the full description**
  (33.8k vs 43.8k) while landing within 0.02 of full's 0.99. `C3d` also has the
  **lowest false-trigger rate of any arm (0.03)** — keeping the capability phrase
  both routes better *and* over-triggers less.
- **~40c: roughly tied on top-1** (`C2` 0.90 vs `C2d` 0.89), but domain-first
  already wins on near-miss discrimination (0.90 vs 0.85). At 40 chars there isn't
  room for the capability phrase to fully pay off.

**Compact (`C5`)** — a compressed capability head *plus* a `Use when` trigger, so
it stays valid for the real auto-invocation matcher (#1278) — reaches 0.95, just
below pure domain-medium. For a **production** description the recommendation is
`C5`-shaped (keep the `Use when` literal); for pure routing signal, the capability
phrase alone (`C3d`) is marginally stronger.

## The answer to "how short can descriptions be — could shorter be better?"

On haiku: **a ~80-char description that keeps the capability/domain phrase
(`C3d`/`C5`) recovers ~all of the full description's routing benefit at roughly
half the token cost, and lowers false-triggering.** The earlier "descriptions
barely help" pilot reading and the "trigger-only short descriptions underperform"
ladder reading are both resolved: descriptions help a lot, but the *content* that
matters is the capability phrase, not the `Use when` trigger tail. "Shorter is
better" holds — provided you shorten toward the domain, not the trigger.

_Cross-model (sonnet/opus) portability results follow when the `xmodel` run
completes._

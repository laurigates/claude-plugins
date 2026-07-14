---
created: 2026-07-14
modified: 2026-07-14
reviewed: 2026-07-14
name: comfy-corpus-validation
description: >-
  Verify ComfyUI sampler/scheduler facts: source-of-truth ladder, measured sigma curves, coverage gaps. Use when writing or auditing sampler corpus metadata.
allowed-tools: Bash, Read, Grep, Glob, Write, Edit
---

# comfy-corpus-validation

`comfyui-sampler-info` ships a JSON **corpus** (`web/data/samplers.json`,
`web/data/schedulers.json`, `web/data/models.json`) of human-written facts
about ComfyUI's sampler and scheduler tokens — year, family, ODE order,
summary, `good_for`, `pairs_with`, and per-model default recipes. The pack's
entire value is that those facts are **true**. A wrong fact is worse than a
missing one: the UI presents it with the same confidence either way.

This skill is the method for making corpus claims verifiable instead of
remembered. It exists because three factual misses shipped or nearly shipped
in one day, each caught by luck: a blog-sourced sampler recommendation that
the vendor's own template contradicted, a schedule-behaviour claim written
from model memory that computing the sigmas falsified, and a model family
absent from the corpus entirely because nothing ever asked what the live
install offers that we describe.

## The core rule

> **A claim about ComfyUI is only as good as the highest rung you verified it
> on. Never write a Tier-3 claim that a Tier-1/2 source could settle but
> didn't.**

## When to Use This Skill

| Use this skill when... | Use instead when... |
|---|---|
| Adding or editing an entry in `web/data/*.json` (sampler, scheduler, model recipe) | Reading generation settings *out of* an output PNG/WebP/MP4 -> `comfy-metadata` |
| Auditing whether the corpus's existing facts are still true | Checking whether the *pack itself* works in a live install -> `comfyui-pack-live-smoke` |
| A source claims "model M wants sampler S" and you must decide whether to believe it | Debugging the pack's publish/release pipeline -> `comfy-registry-lifecycle` |
| Asking what the install offers that the corpus says nothing about | Writing the pack's frontend/backend code -> `comfyui-node-authoring` |

`comfyui-pack-live-smoke` verifies the pack *functions*. This skill verifies
its *facts are true*. A pack can be perfectly working and comprehensively
wrong.

## The source-of-truth ladder

| Tier | Source | Settles |
|---|---|---|
| **1. Executable ground truth** | `/object_info/<NodeClass>` on a live install (token lists + `python_module`); `comfy/samplers.py` (`SCHEDULER_HANDLERS`, `KSAMPLER_NAMES`, `SAMPLER_NAMES`); custom-node source; **computing the sigma curve** by calling the real handler | Does the token exist? Who provides it (core vs which pack)? What does the schedule *actually do*? |
| **2. Shipped vendor artifacts** | `comfyui_workflow_templates_json/templates/*.json` — the KSampler widget values in the official template **are** the vendor's default recipe; docs.comfy.org; the HF model card | What does the vendor actually recommend for model M? |
| **3. Secondary sources** | Blogs, tutorials, Civitai, Reddit | *Discovering* claims. Never the sole basis for one. |
| **4. Empirical testing** | Your own generation results | Legitimate — but must be **labelled** (`source.kind: "empirical"`), and where possible backed by a Tier-1 mechanism. |

Tier 1 beats Tier 2 beats Tier 3. Tier 4 is not a lower Tier 3 — it is a
different kind of claim (yours, not someone's), and honest labelling is what
keeps it usable.

## The three protocols

### 1. Measure behaviour, never assert it

Any claim about *what a schedule does* — "concentrates steps at the low-noise
end", "front-loads denoising", "spends steps in the mid-range" — is
**computed, not remembered**. Call the real handler against a real
`ModelSampling`, get the sigma list, bucket the steps into noise bands, and
read the answer off the table.

This is the only thing that caught the `beta57` error: the corpus claimed it
"spends steps in the mid-range rather than at the extremes". Measurement
showed it does the exact opposite — it takes steps *out of* the mid range and
spends them at the low-noise end. No amount of plausible reasoning would have
found that; one computation did. Full numbers in `REFERENCE.md`.

### 2. Disagreement means escalate or stay silent

When two Tier-3 sources conflict, **resolve at Tier 1/2, or do not write the
claim.** Never break the tie by picking the better-ranked blog — search
ranking is not evidence. A top-ranked guide said Krea 2 wants `er_sde`;
ComfyUI's own shipped workflow template says `euler`. The template is the
vendor's recipe and it wins. When no Tier-1/2 source can settle it, the
correct corpus entry is *no entry* — the UI's `(no metadata for this option
yet)` is honest; a confident wrong sentence is not.

### 3. Coverage is a first-class check

Ask, every time: **"what does the live install offer that the corpus says
nothing about?"** Krea 2 was missing from the corpus entirely, and nothing in
the process ever asked the question, so the gap stayed invisible until a user
did. An undescribed token is a visible hole in the pack's UI. Coverage is not
a nice-to-have audit; it is one of the three checks `corpus-check` runs.

## Two traps that will bite you

**Template samplers hide inside subgraphs.** In `image_krea2_turbo_t2i.json`
and `flux1_krea_dev.json` the `KSampler` node lives under
`definitions.subgraphs[].nodes`, **not** top-level `nodes`. A naive
top-level scan returns nothing, which reads as "this template configures no
sampler" — exactly backwards, since the template is the authoritative answer.
Always walk `definitions.subgraphs[]` too.

**A field that looks like the answer isn't.** The Comfy Registry API's
`latest_version` is *not* the newest version. Same class of error: a
plausibly-named field is not evidence. Check what the field means before
trusting what it says.

## Running the check

Ground truth is **regenerated on demand, never committed** — a committed
snapshot is just another stale secondary source.

```
COMFY_SSH_HOST=popos.intra.lakuz.com just corpus-check
```

Two halves, split because only one of them needs a GPU box:

- **`scripts/corpus_probe.py`** runs *on a ComfyUI host* (needs torch +
  ComfyUI importable). It emits ground truth as JSON on stdout:
  - `tokens` — sampler/scheduler tokens the live install offers, each tagged
    with its provider (core vs which custom-node pack).
  - `schedulers` — the **measured** sigma curve per scheduler plus the step
    allocation across low/mid/high noise bands.
  - `templates` — `{template, sampler, scheduler, steps, cfg}` rows from the
    shipped workflow templates, **including subgraph-nested KSamplers**.
- **`scripts/corpus_check.py`** runs *locally*, stdlib-only. It consumes the
  probe JSON plus `web/data/*.json` and emits a structured
  `=== SECTION ===` / `KEY=VALUE` / `STATUS=` report.

### Reading the report

| Section | What it means | What to do about it |
|---|---|---|
| **COVERAGE** | Tokens the install offers that the corpus doesn't describe (resolved exact → alias → prefix) | Write the entry, or accept the hole deliberately |
| **RECIPES** | Every `models.json` entry citing `source.template` re-checked against the probe's template rows | A FAIL means **upstream changed the template** — that is the point, not a bug. Re-read the template and update the recipe |
| **BEHAVIOUR** | The measured band table shown beside any entry whose prose makes a step-allocation claim | Read the prose against the numbers. If they disagree, the prose is wrong |

A RECIPES FAIL is the check earning its keep: it means the vendor moved and
the corpus didn't.

## Labelling provenance

Any corpus entry may carry a `source` field. `kind` is one of:

| `kind` | Meaning |
|---|---|
| `vendor-default` | From a shipped workflow template — **the only kind carrying a machine-checkable `template`**, and the only one `corpus-check` can re-verify |
| `vendor-doc` | docs.comfy.org or the model card |
| `pack-provided` | Documented by the custom-node pack that ships the token |
| `community` | Tier 3. Use sparingly, and never for a claim Tier 1/2 could settle |
| `empirical` | Your own testing. Honest, and must say so |
| `paper` | The originating paper |

`models.json` stores each model family's vendor-default recipe **exactly
once**, with the template it came from — so the recipe has one home and one
checkable provenance, rather than being restated in prose across several
entries where it can drift.

## See also

`REFERENCE.md` — the three misses worked end to end with the real numbers:
the `er_sde` disagreement and its Tier-2 resolution, the `beta57` sigma
measurement that falsified our own prose (with the sigma lists and band
table), the subgraph-hidden KSampler and its exact `widgets_values` vector,
and how a Tier-1 `/object_info` diff mechanically proves which pack provides
which scheduler.

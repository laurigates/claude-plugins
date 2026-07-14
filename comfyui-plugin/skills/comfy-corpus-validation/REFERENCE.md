# comfy-corpus-validation — worked examples

Three real misses, each worked end to end with the numbers that settled it.
All values below were verified against a live RES4LYF-equipped ComfyUI
install and the shipped workflow templates on 2026-07-14.

---

## 1. The `er_sde` disagreement — resolving a Tier-3 conflict at Tier 2

### The situation

Secondary sources split on which sampler Krea 2 wants. A well-ranked
blog/guide asserted `er_sde`. Other Tier-3 sources disagreed. The tempting
move — and the one nearly taken — was to believe the better-ranked source,
because it *looked* more authoritative.

Search ranking is not evidence. Two Tier-3 sources in conflict is not a
50/50 coin flip to be broken by page rank; it is a signal that **neither is
sufficient** and the question must be escalated.

### The resolution

ComfyUI ships the vendor's own workflow templates in
`comfyui_workflow_templates_json/templates/*.json`. The KSampler widget
values in those templates **are** the vendor's default recipe — not a
description of it, not an interpretation of it, but the thing itself, as
loaded when a user clicks the template in the UI.

| Template | sampler | scheduler | steps | CFG |
|---|---|---|---|---|
| `image_krea2_turbo_t2i.json` | `euler` | `simple` | 8 | 1 |
| `flux1_krea_dev.json` | `euler` | `simple` | 20 | 1 |

`euler`, not `er_sde`. The higher-ranked blog was simply wrong, and no amount
of reading more blogs would have revealed that — only a rung-2 source could.

### The generalizable move

When two Tier-3 sources conflict about "model M wants sampler S":

1. Look for a shipped template for M. It settles the question outright.
2. Failing that, docs.comfy.org or the HF model card (still Tier 2).
3. Failing that, **write nothing**. `(no metadata for this option yet)` is an
   honest UI state. A confidently wrong sentence is not.

---

## 2. The `beta57` measurement that falsified our own prose

### The claim we shipped

PR #72 added a `beta57` scheduler entry to the corpus whose prose said it
"spends steps in the mid-range rather than at the extremes". That sentence
was written from model memory — it sounded right, it was internally coherent,
and nobody could see it was false by reading it. Corrected in #77.

### What `beta57` actually is (Tier 1, from source)

RES4LYF's `__init__.py` registers the token by partially applying **core's
own** beta scheduler:

```python
SCHEDULER_HANDLERS["beta57"] = SchedulerHandler(
    partial(comfy.samplers.beta_scheduler, alpha=0.5, beta=0.7)
)
```

Core `beta` defaults to `alpha=0.6, beta=0.6`. So `beta57` is not a new
algorithm at all — it is `beta` with a different Beta-distribution shape.
That fact came from **reading the registration**, not from a blog.

### The measurement

Call the real handler against a real `comfy.model_sampling.ModelSamplingDiscrete()`
at **20 steps**. σ_max = 14.615.

Sigma lists (20 steps → 21 values, terminating at 0):

- `simple`: 14.615, 10.904, 8.303, 6.443, 5.088, 4.082, 3.321, 2.735, 2.276,
  1.910, 1.613, 1.367, 1.161, 0.984, 0.830, 0.693, 0.569, 0.454, 0.342,
  0.223, 0.0
- `beta57`: 14.615, 12.158, 9.188, 6.702, 4.884, 3.601, 2.695, 2.069, 1.613,
  1.276, 1.024, 0.824, 0.665, 0.536, 0.427, 0.335, 0.256, 0.185, 0.123,
  0.066, 0.0

Bucket the steps into noise bands as a fraction of σ_max — high > 0.5, mid
0.1–0.5, low < 0.1:

| scheduler | high | mid | low |
|---|---|---|---|
| `simple` | 3 | 8 | 9 |
| `beta` | 5 | 6 | 9 |
| `beta57` | 3 | 6 | **11** |

### The verdict

`beta57` takes steps **out of the mid-noise range and spends them at the
low-noise end** — the exact opposite of what the corpus said. Read the tails
of the two sigma lists: `beta57`'s final values (0.335, 0.256, 0.185, 0.123,
0.066) crowd far tighter toward zero than `simple`'s (0.693, 0.569, 0.454,
0.342, 0.223). That is what "spends steps at the low-noise end" *looks like*
numerically, and it is visible in ten seconds once the numbers exist.

### The generalizable move

**Never assert what a schedule does. Compute it.** Any prose in the corpus
containing a step-allocation claim ("front-loads", "concentrates at",
"spends steps in") is a claim that `corpus_probe.py` can settle mechanically.
That is precisely why `corpus_check.py`'s BEHAVIOUR section prints the
measured band table next to any entry whose prose makes such a claim: so the
reviewer's eye lands on the sentence and the numbers at the same time.

---

## 3. The subgraph-hidden KSampler

### The trap

A naive scan of a template's top-level `nodes` array for a `KSampler` returns
**nothing** for `image_krea2_turbo_t2i.json` and `flux1_krea_dev.json`. The
obvious reading — "this template doesn't configure a sampler" — is exactly
backwards. The KSampler is there; it lives under:

```
definitions.subgraphs[].nodes
```

The template is the authoritative Tier-2 answer, and a top-level-only scan
makes it look silent. Any code that reads templates must walk
`definitions.subgraphs[]` as well as `nodes`.

### The actual widget vector

The Krea 2 Turbo template's KSampler:

```json
[735915477938686, "randomize", 8, 1, "euler", "simple", 1]
```

KSampler `widgets_values` are **positional**, in this order:

| index | field |
|---|---|
| 0 | `seed` |
| 1 | `control_after_generate` |
| 2 | `steps` |
| 3 | `cfg` |
| 4 | `sampler_name` |
| 5 | `scheduler` |
| 6 | `denoise` |

So the vector above reads: 8 steps, CFG 1, `euler`, `simple`, denoise 1 —
which is exactly the row in the table in §1.

### The sibling trap

The Comfy Registry API's `latest_version` is **not** the newest version. Same
class of mistake: a field whose *name* looks like the answer, trusted without
checking what it actually contains. Both traps share one rule — **confirm
what a field means before you believe what it says.**

---

## 4. Provenance straight from Tier 1: which pack ships which scheduler

A live `/object_info/KSampler` on a RES4LYF-equipped install offers:

```
['simple', 'sgm_uniform', 'karras', 'exponential', 'ddim_uniform',
 'beta', 'normal', 'linear_quadratic', 'kl_optimal',
 'bong_tangent', 'beta57']
```

Core `comfy.samplers.SCHEDULER_HANDLERS`, imported **without** custom nodes
loaded, has only the first nine.

The set difference is mechanical:

```
{bong_tangent, beta57} = live_install_tokens − core_tokens
```

That diff *proves* the fact "`beta57` and `bong_tangent` ship with RES4LYF,
not core" — no blog needed, no memory involved, and it stays correct
automatically as core adds schedulers or the install's pack set changes. This
is what Tier 1 buys: a fact that re-derives itself instead of going stale.

`corpus_probe.py` emits exactly this as its `tokens` section, tagging each
token with its provider via the node's `python_module`, so `corpus_check.py`
can flag a corpus entry that attributes a token to the wrong provider.

---

## Why all three misses have the same shape

Each was a claim written at a lower rung than the one that could settle it:

| Miss | Written at | Could have been settled at |
|---|---|---|
| Krea 2 wants `er_sde` | Tier 3 (a blog) | Tier 2 (the shipped template) |
| `beta57` "spends steps in the mid-range" | memory | Tier 1 (compute the sigmas) |
| Krea 2 absent from the corpus | nowhere — nobody asked | Tier 1 (what does the install offer?) |

Which is the whole rule, restated: **a claim about ComfyUI is only as good as
the highest rung you verified it on.**

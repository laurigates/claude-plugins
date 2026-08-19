---
created: 2026-07-31
modified: 2026-07-31
reviewed: 2026-07-31
paths:
  - "**/*fleet*"
  - "**/*scaffold*"
  - "**/*drift*"
---
# Auditing a Generated Fleet: Divergence Is Not Automatically Drift

When a generator (`scaffold.py`, a cookiecutter, a `new-*` recipe) has produced
many instances, the instances diverge from the template over time and someone
eventually audits the gap. The failure this rule prevents is the audit's *first
move*: reading "differs from the template" as "wrong". It usually isn't, and
acting on that reading is how an audit becomes a regression.

Sibling of `code-quality-plugin:code-scaffold-backport` (fix the class, not the
instance). This is its inverse: **don't push the class over an instance whose
divergence was deliberate.**

## The three findings, in the order they bite

### 1. Drift is bidirectional — so never auto-apply template → instance

An instance is often **ahead** of the template. Renovate bumps a pin, someone
lands a cost fix, a bug gets patched where it hurt. A sync script that treats
the template as authoritative silently reverts all of it, across every instance
at once, and the revert looks like a tidy-up commit.

> Measured 2026-07-30 (13 ComfyUI packs): all 13 were **ahead** of the scaffold
> on `release-please.yml` (`ubuntu-slim`, `release-please-action@v5`); the
> template was ahead on `RELEASE-CHECKLIST.md`; `tests/js/__mocks__/app.js` was
> pack-owned and not drift at all. One direction would have been wrong for each.

**The audit reports; a human classifies the direction.** That is the whole
reason `check-fleet-drift.py` has no `--fix`.

### 2. A *cohort* diverging identically is a signal of intent

One instance differing is probably rot. **Several instances differing the same
way — especially if they landed together — is a pattern, and the prior should be
"this encodes something" until you have checked.**

> Four of the 13 packs used a blue accent where the scaffold emits orange. It was
> called drift. It was in fact documented one skill over
> (`comfy-registry-lifecycle`: glyph colour encodes the sub-family — `#ffb02e`
> touch/interaction, `#6ba6ff` info/gallery). Acting on the "drift" reading
> restyled four published packs and erased the signal; the `rg` that would have
> settled it took seconds.

Before filing a divergence as drift, grep the sibling skills/docs for the value
itself (`rg '#6ba6ff'`). Cheap, and it is the step that was skipped.

### 3. Undeclared intent is unauditable — declare it to make it checkable

A checker that only diffs against the template **structurally cannot** judge a
per-instance divergence: deliberate and drifted produce the *same diff*. So the
honest default becomes "ignore this file", and the rule goes unenforced forever
— which is exactly how the regression above shipped past a green checker.

The fix is not a smarter diff. **Declare the intent in the policy, then check
each instance against its own declaration** rather than against the template.

```toml
# fleet-policy.toml
[subfamily]
comfyui-sampler-info = "info"   # now checkable: its icon AND banner must be blue
```

An instance missing from the declaration is an **ERROR**, not a skip — otherwise
a new instance silently opts out of the check.

## Per-file authority, not one global policy

Blanket byte-identity produces permanent false ERRORs on files instances
legitimately extend. Classify each emitted path:

| Policy | Meaning |
|---|---|
| `managed` | Byte-identity is the invariant. *Direction is still a human call.* |
| `shared` | Must be consistent across instances, but the fleet leads and the template back-ports. |
| `seed` | Template is a starting point only; never compared. |

Getting these wrong is the likeliest defect — three of the first-pass
classifications here were wrong (`.gitignore`, `.gitattributes`, and
`.release-please-manifest.json`, which holds each instance's live version and
would have ERRORed on every released pack forever). **Review the policy file
sceptically; the script is the easy part.**

## Two operational cautions

- **Verify the invariant holds across the corpus *before* writing the gate.** A
  gate that is red on arrival for legitimate content gets disabled, correctness
  notwithstanding.
- **A checker that reports a large pre-existing backlog is only useful if the
  backlog is worked.** If the weekly issue says the same thing for a month, the
  signal is dead regardless of whether it is right.

## Related

- `code-quality-plugin:code-scaffold-backport` — the inverse (fix the generator, not just the instance)
- `.claude/rules/drift-detection-triggering.md` — *triggering* a sweep; this rule is about classifying what it finds
- `.claude/rules/offload-to-deterministic-substrate.md` — why the sweep is a script and the classification is not
- `comfyui-plugin/skills/comfyui-node-scaffold/fleet-policy.toml` — the reference policy, with per-entry rationale
- `comfyui-plugin/skills/comfyui-node-scaffold/scripts/check-fleet-drift.py` — the reference implementation

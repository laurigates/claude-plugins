# Multi-Model Delegation — When a Claim Is Refuted

Moved verbatim from [SKILL.md](../SKILL.md). Open when Step 5 adjudication shows a
delegated model's claim is false.

### Step 7: When a claim is refuted, ask the second question

Step 5 adjudicates *"is this claim true?"* against the code. When the answer
is **no**, the instinct is to discard the claim and move on. Don't — ask the
second question first:

> **"Why couldn't the test suite answer this?"**

That question survives a wrong claim. A confident, specific, *false* finding
usually points at something real — not the defect it names, but the **absence
of a gate that would have settled it in seconds**. The claim dies; the gap it
exposed does not.

The move: add the gate that decides the question, then **kill-test it by
swapping in the reviewer's proposed value**. If the reviewer was right, the
gate goes red and you have found a real bug. If they were wrong, it goes red
on *their* version and green on yours — converting an argument into a
permanent, mechanical answer, so neither the next reviewer nor the next
session can re-litigate it.

> Canonical case (loractl verbosity review, 2026-07): `kimi-k2.7-code` claimed
> `flag_directives` emitted a `loractl=` tracing target matching nothing —
> because the *package* is `loractl-cli` — which would make the entire `-v`
> ladder inert. It was **wrong**: `[[bin]] name = "loractl"`, so `module_path!`
> roots at `loractl`, and a live `-v` run had already printed `INFO` lines. But
> the claim was *unfalsifiable from the suite*, because the unit test asserted
> the directive **string** and never that the filter matched a real event. Fix:
> a spawned-binary test pair (`-v` must show INFO, default must not), then a
> kill-test swapping in the reviewer's `loractl_cli=` — which fails it. Wrong
> claim, real gap, permanent gate.

The generalization beyond model reviews: **a test that asserts the shape of a
value rather than the behaviour it produces cannot settle a question about
that behaviour** — it passes whether the wiring works or not. Those are
exactly the tests an outside reviewer's wrong guess will find for you.

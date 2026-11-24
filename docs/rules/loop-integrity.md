# Loop Integrity: evidence and origin

The always-loaded rule [`.claude/rules/loop-integrity.md`](../../.claude/rules/loop-integrity.md)
states the two pillars and the runaway bound. This page holds the measurement
behind Pillar 1 and the discussion the rule was distilled from, moved here
verbatim on 2026-11-24 so they no longer load on every turn.

## Why the verifier must have no stake (Pillar 1)

> Measured 2026-09-04 (`claude-plugins`, seven issue→PR pipelines). Each
> implementer ran an external model over its **own** diff before opening its PR,
> with an adversarial brief and instructions to verify each finding. Across all
> seven that pass accepted **zero** findings. A second pass by a fresh agent that
> had not done the work — same model, different brief, and re-running the
> implementer's own gates rather than reading its report — held four of the seven
> PRs. It found six reproduced bypasses in a hook whose 45-assertion suite was
> fully green, a PR whose every gate number predated a bot push to its branch,
> and a guard that counted any `*.md` file as a template. The variable was not
> the model or the prompt; it was whether the reviewer had a stake in the work
> being done.

## Origin

Distilled from the r/ClaudeCode "Goal and Loop — kinda the same?" discussion,
where the load-bearing observations were that native `/goal` *"spawns a
fresh/neutral agent that checks if the conditions are met"* (Pillar 1), that
self-review is *"fundamentally flawed because the review is not independent —
agents optimise for completion not correctness"* (Pillar 1), and that a loop
which *"mutates its own goal file without leaving that packet behind"* is
*"automating context drift"* (Pillar 2). The packet field list is that comment's
verbatim shape.

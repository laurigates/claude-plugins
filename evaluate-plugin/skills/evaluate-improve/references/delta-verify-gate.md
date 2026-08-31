# /evaluate:improve — Delta-verify gate (AEGIS source-cases)

The gate that stands between a drafted improvement and the live `SKILL.md`.
It exists because ranking by aggregate pass rate can reward a candidate that
fixes unrelated cases while leaving the motivating failures broken. Entry
point: [`../SKILL.md`](../SKILL.md) § Step 5.


Before *any* edit is written to the live SKILL.md — both the plain `--apply`
path (Step 5) and the `--best-of` path (Step 5a) — confirm the edit actually
**shrinks the source-failure set** captured in Step 1, not merely that the
overall golden-set pass rate is higher. Ranking by aggregate pass rate can
reward a candidate that fixes unrelated cases while leaving the motivating
failures broken; this gate closes that gap (HarnessX/AEGIS: re-run on the
source cases, confirm the failure count shrinks before applying).

Run the gate against the **drafted candidate** (a candidate file under
`eval-results/candidates/`, or for plain `--apply` a draft written there
first), never the live SKILL.md:

1. Re-run **only the source-failure cases** against the candidate — spawn one
   Task subagent (`subagent_type: general-purpose`) per case with the candidate
   content as the skill context (the same rollout machinery as Step 5a; use
   `prepare_run.sh`), and grade each transcript with
   `python3 evaluate-plugin/scripts/grade_deterministic.py`.
2. Compute `delta = (source failures before) − (source failures after)`.
3. **Gate:** apply only when `delta > 0` (the candidate fixes at least one
   motivating failure and regresses none of the others). When `delta <= 0`, do
   **not** write the edit — report which source cases still fail and suggest
   revising the suggestions. `--force-apply` overrides the gate (records the
   override in history). When the source-failure set is empty, the gate is a
   no-op and the apply proceeds.


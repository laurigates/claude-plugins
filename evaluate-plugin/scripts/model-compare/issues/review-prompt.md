# Blind review prompt for issue runs

Fill the placeholders and give it to a fresh reviewer (Opus, run as a
subagent or `claude -p`) that has not seen the runs. Copy each model's
`diff.<issue>.<model>.patch` to `<review-dir>/<issue>-<A|B|C>.patch` under a
shuffled mapping, and keep the mapping file outside `<review-dir>`. When you
pass measured facts (test results, probe output), label them by letter and
check the mapping before sending: a swapped fact silently biases the score.

---

You are a blind code reviewer. Three anonymous candidate diffs (A, B, C) each
attempt to resolve GitHub issue #<N> in this repository (main is checked out at
<repo>; treat it as read-only). A reference diff from the maintainers' own PR
is also provided; treat it as one good answer, not the only correct one.

Files: `<review-dir>/<N>-A.patch`, `<N>-B.patch`, `<N>-C.patch`, and
`<review-dir>/ref-<N>.patch`.

Issue #<N>:
<issue text, including its acceptance criteria>

Measured facts (from running each candidate's worktree; do not re-run them):
<per letter: own tests pass/fail, probe results, whether the repo's guards are green>

Read whatever files on main you need to judge conventions (CLAUDE.md,
`.claude/rules/`).

Score each candidate 0–10 on each criterion with a one-line justification:
1. acceptance: meets the issue's acceptance criteria as written.
2. correctness: no instruction or code that breaks existing behaviour or
   contradicts the rest of the file it edits.
3. conventions: house style, regression ledger, docs updated in the same
   commit where the repo requires it.
4. scope_discipline: no unrelated edits.

Then give an overall score (0–10) and a ranking. Be adversarial. Reply ONLY with JSON:
`{"A":{"acceptance":[n,"why"],"correctness":[...],"conventions":[...],"scope_discipline":[...],"overall":n,"defects":["..."]},"B":{...},"C":{...},"ranking":["X","Y","Z"],"vs_reference":"one sentence"}`

# Verification-Only Flow

Read when Step 2 item 4 classifies an issue as verification-only: its acceptance
criteria are observations (a run passes, a value appears, a prerequisite PR has
landed), not code changes. Verify first and evidence it on the issue; code
changes happen only for a failure the check finds.

1. **Confirm preconditions.** For a prerequisite PR:
   `gh pr view <PR> --json state,mergedAt` — proceed only when `state` is
   `MERGED`; otherwise report the issue as blocked on that PR and stop.
2. **Find the targets and observe.** Enumerate each target the criteria name
   (consumer repos, workflows, environments) and check its current state, then
   run the check — e.g. `gh workflow run <wf> -R <owner>/<repo>` and
   `gh run watch <run-id> -R <owner>/<repo> --exit-status`, with a time bound.
3. **Record step-level evidence.** Write one row per criterion (target, run
   URL, step, observed result) to a temp file and post it with
   `gh issue comment $N --body-file <file>`, which keeps run output out of shell
   quoting.
4. **Close on verified success**, with the reason stated:
   `gh issue close $N --reason completed --comment "Verified: <summary> — evidence in the verification comment"`.
   No PR is involved, so `Fixes #N` does not apply.
5. **On a failure**, post the failing evidence the same way, then return to
   `SKILL.md` Standard Flow item 5: cut the branch and fix through the TDD
   Workflow; that PR closes the issue with `Fixes #N`.

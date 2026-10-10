# AI Review — Cause 4: Result Flagged Errored Despite Completing

Detail for the fourth row of the five-causes table in [SKILL.md](../SKILL.md).

## Cause 4 — a result flagged errored despite completing

The SDK returned `subtype: "success"` and `is_error: true` in the same result,
and the wrapper failed the job on that combination alone:

```
##[error]Claude result reported subtype success with is_error:true (run did not complete successfully)
##[error]Action failed with error: Claude execution failed: result is_error:true
```

It matches none of the other four rows. The `subtype` is `success`, so the run
did not die on its turn budget, and five turns is nowhere near a ceiling. There
is no `Found N` line, `permission_denials_count` is 0, the publish step logs
`No buffered inline comments`, and the PR carries no comment, so no finding is
waiting behind a blocked channel. The payload also has no `result` string at
all, which may be the actual trigger.

```sh
gh run view --job <job-id> -R <o>/<r> --log | grep -E '"is_error"|"subtype"|"num_turns"|permission_denials_count|"result":|Found [0-9]|subtype success with is_error'
```

**Rerun the identical commit once.** A pass with no code change means the red
was infra. A second identical failure means it is deterministic: read the run
before blaming either the code or the platform.

> Evidence (2026-09-22, ForumViriumHelsinki/thelma#1524): `A11y WCAG` failed in
> run `35730697939` with `subtype: "success"`, `is_error: true`, `num_turns: 5`,
> `permission_denials_count: 0`, no `Found N` line and no `result` string. A
> rerun of the same commit passed.

The same incident is the evidence for SKILL.md § No history at all:

> Evidence (2026-09-22, thelma#1524): `a11y-wcag.yml` had exactly one run in
> its history, the failing one. The rerun passed, and the changed components
> already carried `aria-label`, `aria-hidden` and `sr-only`, so a genuine
> Level A finding was implausible.

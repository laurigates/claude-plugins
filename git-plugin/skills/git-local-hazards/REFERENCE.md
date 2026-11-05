# Git Local Hazards — Field Evidence

Observed cases behind the hazards in [SKILL.md](SKILL.md), moved out of it verbatim. Each section names the hazard it supports.

## Merged mid-session (2026-08-19)

Supports [SKILL.md § The variant with no symptom at all](SKILL.md#the-variant-with-no-symptom-at-all-the-pr-merges-while-you-are-still-on-the-branch) (hazard 1): the PR merged while work continued on its branch.

Observed 2026-08-19: two commits, and the source that
produced an hour-long delivery render, sat on a branch whose PR had already
merged. It surfaced only because an unrelated `git switch main` failed on local
changes.

## Clean rebase, broken migrations (2026-08)

Supports the rebase variant of [SKILL.md § 3](SKILL.md#3-a-clean-textual-merge-can-duplicate-identical-additions): zero conflicts, broken result.

> Observed 2026-08 (a data-pipeline repo): a branch removed TimescaleDB by
> rewriting the three `0001_initial` migrations. Meanwhile `main` gained
> `measurements/0004`, calling `decompress_chunk()`/`show_chunks()`
> unconditionally. `git rebase origin/main` reported **success with no
> conflicts** — different files — and produced a migration tree that cannot
> apply on the plain PostgreSQL the branch exists to target
> (`function show_chunks(unknown) does not exist`). Caught by reading `main`'s
> new commits, not by any gate.

## Vanished staged file (2026-07)

Supports [SKILL.md § 5](SKILL.md#5-a-vanished-staged-file-in-a-shared-checkout-was-probably-committed-by-a-coworker): a coworker committed a file mid-flight.

Observed 2026-07 (dotfiles): a file another session had
staged (`A `) disappeared from `git status`, then `ls` said it didn't exist,
then status flapped `A ` → `M ` across consecutive calls. The wrong theory
("pre-commit's stash dance ate it") was nearly acted on; the truth was the
coworker had committed the file to `main` mid-flight — every observation was a
stale read of state the coworker kept moving.

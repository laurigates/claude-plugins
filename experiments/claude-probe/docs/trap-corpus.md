# Trap corpus

Phase 0 showed the three config arms are indistinguishable on generic micro-tasks
(and `full` costs ~10× per task). That's expected: the 52 rules were mostly
written to fix **specific failures**, and generic tasks never touch those
surfaces. The trap corpus is the fix — tasks shaped like the failure each rule
guards, where an un-ruled arm should fall in and the `full` arm (if the rule
fires) should be caught.

## A trap task = fixture + failure-shaped prompt + two kinds of check

- **`fixture:`** names `fixtures/<name>/setup.sh`, which builds a throwaway
  scenario repo (`run-one.sh` runs each task in a fresh `mktemp` copy, so
  mutating traps get clean state). Read-only probes omit `fixture:`.
- **Technique check** — did the rule's prescribed approach appear? e.g.
  `tool_used Bash arg_pattern: merge-tree`. Directly rule-attributable.
- **Outcome check** — did the model reach the correct conclusion regardless of
  route? e.g. `output_matches VERDICT: SAFE`. Catches "got it right anyway".
- **Anti-signal** (`observational: true`) — did it lean on the misleading path
  (`git branch --merged`)? Reported as INFO, excluded from pass-rate.

The interesting reads: `clean` fails but `full` passes → the rule earns its keep;
all arms pass → the model reasons it out unaided, rule is redundant *for this
model*; all arms fail → the rule doesn't fire even on home turf (the strongest
"drop it or rewrite it" signal — and `glob-vs-find` in Phase 0 already showed
`full` ignoring its own rule).

## Candidate traps (one per high-value rule)

| id | rule | scenario the fixture builds | discriminating check |
|---|---|---|---|
| `trap-01-squash-merge-detection` ✅ | branch-merge-detection | branch squash-merged into main, **plus post-squash base drift** so `--merged`, `log main..branch` and `diff` all read "unmerged" | used `cherry`/`merge-tree`; VERDICT: SAFE |
| `trap-02-chezmoi-exact-delete` ✅ | chezmoi-conventions | `exact_` source + an unmanaged file in target, beside a non-`exact_` sibling whose unmanaged file survives | ran `chezmoi status/diff` before `apply --force`; named the one deleted path |
| `trap-03-git-add-pathspec` ✅ | git-add-atomic-pathspec | `git mv` rename + a working-tree edit | staged edit landed (not just the rename); checked `status` |
| `trap-04-zsh-extended-glob` ✅ | zsh-pattern-expansion | `${v##*#}` under `extended_glob`, beside a bash prototype where it works | output escapes `\#`; blamed the option, not the data |
| `trap-05-textual-merge-dup` ✅ | textual-merge-duplicates | two branches add the same helper in non-adjacent spots | built/grepped for the duplicate after a clean auto-merge |
| `trap-06-dockerignore-subdir` ✅ | docker-build-context | subdir `Dockerfile` + a bare sibling `.dockerignore` | renamed to `Dockerfile.dockerignore` / diagnosed dead ignore |
| `trap-07-branch-from-pushed-main` ✅ | branch-from-pushed-main | local `main` ahead of origin by a stray commit, **with no upstream set** so `git status` reports nothing | branched from `origin/main` / checked `log origin/main..main` |

✅ = built.

### Calibrate on OUTCOME, not technique

A trap only measures a rule's value if the un-ruled path lands on the **wrong
answer**. If the naive route merely takes a clumsier road to the right one, the
rule under test is unfalsifiable and a green result means nothing.

Two of the fixtures needed a deliberate twist to clear that bar, and both are
worth copying when adding trap-08+:

- **trap-01** originally squash-merged and stopped. With `main` unchanged since
  the squash, `git diff main feat-done` is **empty**, so any route at all
  concludes "contained" — the trap graded technique only. Letting `main` drift
  after the squash (in a region the branch never touched, so the three-way
  merge stays clean) makes `log` and `diff` misleading too, and only a
  containment-aware signal survives.
- **trap-07** with an upstream configured has `git status` volunteer
  `[ahead 1]`. Dropping the upstream makes the divergence invisible to the
  commands one reaches for first.

The general shape: find the signal that accidentally gives the answer away, and
remove it — without removing the truth.

## Run

```
just run-config 'trap-01-*' 3     # one trap, 3 arms, N=3
just compare-fast latest
```

### Fixture prerequisites

Each fixture builds its own scenario, but four traps need a tool on the runner
to be *diagnosable* by the model under test. A missing tool does not corrupt the
fixture; it just turns that trap into a knowledge question rather than an
investigation, so read those arms with that in mind.

| trap | needs |
|---|---|
| 01, 03, 05, 07 | `git` only (05 also runs `python3` for the repo's own check) |
| 02 | `chezmoi` |
| 04 | `zsh` |
| 06 | a running Docker daemon (the fixture is diagnosable without one) |

A trap only counts if its fixture is self-verifying: before trusting any arm's
score, confirm the misleading command really gives the wrong answer and the
correct command really gives the right one. Each `setup.sh` records the exact
commands and observed outputs it was verified against, in its header comment.

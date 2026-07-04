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
| `trap-01-squash-merge-detection` ✅ | branch-merge-detection | branch squash-merged into main (unmerged to `--merged`, contained by `merge-tree`) | used `merge-tree`; VERDICT: SAFE |
| `trap-02-chezmoi-exact-delete` | chezmoi-conventions | `exact_` source + an unmanaged file in target | ran `chezmoi status/diff` before `apply --force` |
| `trap-03-git-add-pathspec` | git-add-atomic-pathspec | `git mv` rename + a working-tree edit | staged edit landed (not just the rename); checked `status` |
| `trap-04-zsh-extended-glob` | zsh-pattern-expansion | `${v##*#}` parse under `extended_glob` | output escapes `\#` / single-token strip |
| `trap-05-textual-merge-dup` | textual-merge-duplicates | two branches add the same helper in non-adjacent spots | built/grepped for the duplicate after a clean auto-merge |
| `trap-06-dockerignore-subdir` | docker-build-context | subdir `Dockerfile` + a bare sibling `.dockerignore` | renamed to `Dockerfile.dockerignore` / diagnosed dead ignore |
| `trap-07-branch-from-pushed-main` | branch-from-pushed-main | local `main` ahead of origin by a stray commit | branched from `origin/main` / checked `log origin/main..main` |

✅ = built. The rest are the Phase 1 authoring queue; each needs a `setup.sh`
that genuinely reproduces the trap (verify the un-ruled path actually fails)
and checks that are true discriminators, not restatements of the prompt.

## Run

```
just run-config 'trap-01-*' 3     # one trap, 3 arms, N=3
just compare-fast latest
```

A trap only counts if its fixture is self-verifying: the setup should be
checkable (e.g. `git branch --merged` really omits the branch while
`merge-tree` really matches) before trusting any arm's score.

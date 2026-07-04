#!/usr/bin/env bash
# Fixture: a SQUASH-MERGED branch.
#
# `feat-done`'s work is fully present in main, but its own commit is not an
# ancestor of main (squash merge minted a fresh commit). So:
#   - `git branch --merged main`      => does NOT list feat-done   (the trap)
#   - `git merge-tree main feat-done` => tree == main's tree        (contained)
# A model that reasons from `--merged` concludes "unmerged / unsafe to delete";
# the branch-merge-detection rule prescribes merge-tree (or checking the PR),
# which reaches the correct "already contained / safe" answer.
set -euo pipefail

dest="${1:?usage: setup.sh <dir>}"
cd "$dest"
# -b main so the fixture is HOME-independent: a fake HOME has no
# init.defaultBranch=main, so a bare `git init` would make `master` and every
# `git ... main` below would fail (only the real-HOME/full arm would work).
git init -q -b main
git config user.email trap@example.com
git config user.name Trap
git config commit.gpgsign false

printf 'def add(a, b):\n    return a + b\n' > app.py
git add -A
git commit -qm "feat: add()"

git switch -qc feat-done
printf '\n\ndef sub(a, b):\n    return a - b\n' >> app.py
git add -A
git commit -qm "feat: sub()"

# Squash-merge feat-done into main: fresh commit, feat-done tip NOT an ancestor.
git switch -q main
git merge --squash feat-done >/dev/null 2>&1
git commit -qm "feat: sub() (#42)"

git switch -q main

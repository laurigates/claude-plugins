#!/usr/bin/env bash
# Fixture: a SQUASH-MERGED branch, WITH post-merge base drift.
#
# `feat-done`'s work is fully present in main, but its own commit is not an
# ancestor of main (squash merge minted a fresh commit), and main has since
# moved on. The drift is what makes this a trap on OUTCOME rather than on
# technique: without it, `git diff main feat-done` is empty and ANY route
# reaches the right answer, so the un-ruled arm passes and the trap measures
# nothing.
#
# With the drift in place the naive signals all point the WRONG way:
#   - `git branch --merged main`       => does NOT list feat-done   (the trap)
#   - `git log --oneline main..feat-done` => 1 commit "not in main"  (the trap)
#   - `git diff main feat-done`        => two-sided differences      (the trap)
# while only a containment-aware signal reaches the truth:
#   - `git cherry -v main feat-done`   => `-` prefix (patch upstream)
#   - `git merge-tree main feat-done`  => merged tree == main's tree
#
# The drift is deliberately placed in a DIFFERENT region of app.py from the
# branch's own hunk (add()'s docstring vs the appended sub()), plus a new file.
# That keeps `git diff` two-sided while leaving the three-way merge clean, so
# the merge-tree signal stays valid — merge-tree only proves containment when
# it succeeds, and a conflict here would prove nothing either way.
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

printf 'def add(a, b):\n    """Add two numbers."""\n    return a + b\n' > app.py
git add -A
git commit -qm "feat: add()"

git switch -qc feat-done
printf '\n\ndef sub(a, b):\n    """Subtract b from a."""\n    return a - b\n' >> app.py
git add -A
git commit -qm "feat: sub()"

# Squash-merge feat-done into main: fresh commit, feat-done tip NOT an ancestor.
git switch -q main
git merge --squash feat-done >/dev/null 2>&1
git commit -qm "feat: sub() (#42)"

# Base drift AFTER the squash: main edits add()'s docstring and gains a new
# file. feat-done's own hunk (sub()) is untouched, so the merge stays clean.
printf 'def add(a, b):\n    """Return the sum of a and b."""\n    return a + b\n\n\ndef sub(a, b):\n    """Subtract b from a."""\n    return a - b\n' > app.py
printf 'VERSION = "1.2.0"\n' > util.py
git add -A
git commit -qm "docs: clarify add(); add util"

git switch -q main

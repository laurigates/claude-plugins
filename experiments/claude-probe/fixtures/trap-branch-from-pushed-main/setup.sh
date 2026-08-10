#!/usr/bin/env bash
# Fixture: local `main` is ahead of `origin/main` by a stray debug commit.
#
# The branch deliberately has NO upstream configured, which is what makes this
# a trap on OUTCOME rather than on technique: with tracking set, `git status`
# volunteers "[ahead 1]" and any route reaches the right answer. Without it the
# divergence is invisible to the commands one reaches for first. Verified on
# git 2.43:
#   - `git status -sb`  => "## main"          (no ahead marker — the trap)
#   - `git branch -vv`  => no tracking info    (the trap)
#   - `git log --oneline origin/main..main` => 1 commit  (the truth)
#   - branch off `main`        => carries the DEBUG line
#   - branch off `origin/main` => clean
#
# The bare remote lives at ./.origin.git and is gitignored, so `git status` is
# clean and the repo looks like an ordinary checkout.
set -euo pipefail

dest="${1:?usage: setup.sh <dir>}"
cd "$dest"

git init -q --bare .origin.git

git init -q -b main
git config user.email trap@example.com
git config user.name Trap
git config commit.gpgsign false

printf '/.origin.git/\n' > .gitignore
printf 'def handler(event):\n    return {"ok": True}\n' > service.py
cat > README.md <<'EOF'
# service

Published work lives on `origin`. New branches are cut from what has been
published, never from whatever happens to be sitting in the local checkout.
EOF
git add -A
git commit -qm "feat: service handler"

git remote add origin ./.origin.git
# Deliberately NO --set-upstream: origin/main exists as a remote-tracking ref,
# but `git status` will not report the divergence.
git push -q origin main

# The stray commit: never pushed, and not wanted on new work.
printf 'def handler(event):\n    print("DEBUG", event)\n    return {"ok": True}\n' > service.py
git add -A
git commit -qm "debug: temporary print while chasing a bug"

git switch -q main

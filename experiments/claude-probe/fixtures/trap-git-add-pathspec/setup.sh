#!/usr/bin/env bash
# Fixture: a STAGED rename plus an UNSTAGED edit to the renamed file.
#
# `git mv` stages the rename; the subsequent working-tree edit is not staged.
# A `git commit -m …` therefore lands the rename ALONE and silently leaves the
# edit behind. Verified on git 2.43:
#   - naive `git commit -m …`  => HEAD holds BUILD = "alpha",
#                                 `git show --stat HEAD` = 0 insertions,
#                                 `git status` still shows " M new_name.py"
#   - `git add new_name.py` first => HEAD holds BUILD = "gamma",
#                                 1 insertion(+) 1 deletion(-), clean tree
#
# Nothing errors on the naive path — the commit succeeds and looks like a
# rename+edit until you read HEAD back. That silence is the trap: the outcome
# is only reachable by staging the pathspec explicitly (or `commit -a`) and
# verifying with status/show afterwards.
set -euo pipefail

dest="${1:?usage: setup.sh <dir>}"
cd "$dest"
git init -q -b main
git config user.email trap@example.com
git config user.name Trap
git config commit.gpgsign false

cat > old_name.py <<'EOF'
"""Release metadata for the widget service."""

NAME = "widget"
BUILD = "alpha"
CHANNEL = "stable"
RETRIES = 3
TIMEOUT = 30
EOF

cat > README.md <<'EOF'
# widget

Release metadata lives in the module beside this file.
EOF

git add -A
git commit -qm "chore: initial import"

# Stage the rename...
git mv old_name.py new_name.py

# ...then edit the renamed file WITHOUT staging it. The file stays long enough
# that git's rename detection still pairs it with old_name.py (one changed
# line out of seven), so `git show --stat` reports a rename either way and the
# naive commit looks plausible.
cat > new_name.py <<'EOF'
"""Release metadata for the widget service."""

NAME = "widget"
BUILD = "gamma"
CHANNEL = "stable"
RETRIES = 3
TIMEOUT = 30
EOF

#!/usr/bin/env bash
# Fixture: two branches add the SAME helper in non-adjacent spots.
#
# `feat-a` inserts slugify() above normalize(); `feat-b` appends a different
# slugify() at the end of the file. The hunks do not touch, so git's textual
# merge is perfectly happy — and produces a file with two definitions of the
# same name, where the later one silently wins. Verified on git 2.43:
#   - `git merge feat-b`      => "Merge made by the 'ort' strategy", exit 0
#   - `grep -n '^def slugify' utils.py` => two hits (lines 8 and 23)
#   - `python3 checks_slug.py`          => AssertionError, exit 1
#
# The trap is that git's own report is the misleading signal: a clean merge is
# evidence about TEXT, not about meaning. Only a post-merge check — running the
# repo's own verification, or grepping for the redefined symbol — reaches the
# outcome.
set -euo pipefail

dest="${1:?usage: setup.sh <dir>}"
cd "$dest"
git init -q -b main
git config user.email trap@example.com
git config user.name Trap
git config commit.gpgsign false

cat > utils.py <<'EOF'
"""Small text helpers."""

import re

WHITESPACE = re.compile(r"\s+")


def normalize(text):
    """Collapse runs of whitespace."""
    return WHITESPACE.sub(" ", text).strip()


def truncate(text, limit=40):
    """Cut text to limit characters."""
    return text if len(text) <= limit else text[: limit - 1] + "..."
EOF
git add -A
git commit -qm "chore: text helpers"

# --- feat-a: slugify inserted ABOVE normalize() -----------------------------
git switch -qc feat-a
cat > utils.py <<'EOF'
"""Small text helpers."""

import re

WHITESPACE = re.compile(r"\s+")


def slugify(text):
    """URL slug: lowercase, hyphen-separated."""
    return WHITESPACE.sub("-", text.strip().lower())


def normalize(text):
    """Collapse runs of whitespace."""
    return WHITESPACE.sub(" ", text).strip()


def truncate(text, limit=40):
    """Cut text to limit characters."""
    return text if len(text) <= limit else text[: limit - 1] + "..."
EOF
cat > checks_slug.py <<'EOF'
from utils import slugify

got = slugify("Hello World")
assert got == "hello-world", f"slugify returned {got!r}, expected 'hello-world'"
print("OK")
EOF
git add -A
git commit -qm "feat: add slugify for URLs"

# --- feat-b: a DIFFERENT slugify appended at the END ------------------------
git switch -q main
git switch -qc feat-b
cat >> utils.py <<'EOF'


def slugify(text):
    """Filename slug: underscore-separated, case preserved."""
    return WHITESPACE.sub("_", text.strip())
EOF
git add -A
git commit -qm "feat: add slugify for filenames"

git switch -q feat-a

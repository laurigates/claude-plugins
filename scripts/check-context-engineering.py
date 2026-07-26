#!/usr/bin/env python3
"""Shim → evaluate-plugin/skills/evaluate-context-engineering/scripts/check-context-engineering.py

The scanner is owned by the skill, not by this directory. Keeping the
implementation in the skill makes it portable (a consumer repo installs
evaluate-plugin and gets the scanner via ${CLAUDE_SKILL_DIR}), and keeping this
path alive keeps `just lint-context-engineering`, the pre-commit hook, and CI
working without a second copy of the code.

One implementation, two entry points — the C4 property this scanner measures.
"""

from __future__ import annotations

import os
import runpy
import sys

REAL = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..",
    "evaluate-plugin",
    "skills",
    "evaluate-context-engineering",
    "scripts",
    "check-context-engineering.py",
)

if not os.path.isfile(REAL):
    sys.exit(f"check-context-engineering.py: scanner not found at {os.path.normpath(REAL)}")

runpy.run_path(os.path.normpath(REAL), run_name="__main__")

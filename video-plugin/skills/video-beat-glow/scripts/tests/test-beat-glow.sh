#!/usr/bin/env bash
# test-beat-glow.sh — unit tests for the beat glow: the pulse envelope (beats.py), edge-band
# rendering equal to the full-frame glow (beat_glow.py), accent rules, and the tuner page's JS
# pulse against the Python envelope (skipped without node). Needs uv for numpy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v uv >/dev/null 2>&1; then
    echo "SKIP: uv not found (needed for numpy)"
    exit 0
fi
uv run -q --no-project --with numpy==2.5.4 python -I -m unittest discover -s "$SCRIPT_DIR" -p 'test_beat_glow.py'

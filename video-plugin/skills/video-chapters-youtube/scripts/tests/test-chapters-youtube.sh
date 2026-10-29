#!/usr/bin/env bash
# test-chapters-youtube.sh — unit tests for chapters_youtube.py's merge rules
# (YouTube: first chapter at 0:00, at least 3, each >= 10 s; short runs merge).
# Stdlib only: runs test_chapters_youtube.py with the system python3.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: python3 not found"
    exit 0
fi
python3 -I -m unittest discover -s "$SCRIPT_DIR" -p 'test_chapters_youtube.py'

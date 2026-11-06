#!/usr/bin/env bash
# check-readme-links.sh — verify relative links and #anchors after a README split.
#
# configure-readme keeps README.md slim and moves the detail sections into
# docs/ pages. Moving a section moves its heading, so every relative link or
# #anchor that pointed at the old README section breaks without an error.
# This script resolves every relative link in the project's Markdown files:
#
#   - inline links and images      [text](path#anchor)  ![alt](path)
#   - reference definitions        [id]: path#anchor
#   - HTML src= / href= attributes <img src="assets/logo.png">
#
# A link is broken when its file (or directory) does not exist, or when its
# #anchor names no heading (GitHub slug rules, duplicates suffixed -1, -2 …)
# and no <a id=/name=> in the target Markdown file. External URLs (any
# scheme: http, https, mailto …), links inside code spans and fenced code
# blocks, and vendored or build directories are skipped.
#
# Usage:
#   bash check-readme-links.sh [--project-dir DIR]
#
# Output follows .claude/rules/structured-script-output.md.
# Exit codes: 0 = OK, 1 = broken links (STATUS=ERROR), 2 = usage error.

set -uo pipefail

proj_dir="$(pwd)"

usage() {
  echo "Usage: check-readme-links.sh [--project-dir DIR]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      [ $# -ge 2 ] || usage
      proj_dir="$2"
      shift 2
      ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[ -d "$proj_dir" ] || { echo "Not a directory: $proj_dir" >&2; exit 2; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "=== README LINKS ==="
  echo "PROJECT_DIR=${proj_dir}"
  echo "STATUS=ERROR"
  echo "REASON=python3_missing: python3 is required to parse Markdown links"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=python3_missing MSG=python3 is required to parse Markdown links"
  echo "=== END README LINKS ==="
  exit 1
fi

python3 - "$proj_dir" <<'PY'
import os
import re
import sys
from urllib.parse import unquote

root = os.path.abspath(sys.argv[1])

SKIP_DIRS = {
    ".git", "node_modules", "vendor", "target", "dist", "build",
    ".venv", "venv", "__pycache__", ".pytest_cache", ".tox", "worktrees",
}

FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
CODE_SPAN = re.compile(r"(`+)(?:(?!\1).)+?\1")
INLINE_LINK = re.compile(r"!?\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+[\"'(][^)]*)?\)")
REF_DEF = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s+.*)?$")
HTML_ATTR = re.compile(r"\b(?:src|href)\s*=\s*[\"']([^\"']+)[\"']", re.I)
HEADING = re.compile(r"^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$")
HTML_ANCHOR = re.compile(r"<a\s[^>]*\b(?:id|name)\s*=\s*[\"']([^\"']+)[\"']", re.I)
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")
MD_LINK_TEXT = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")


def markdown_files():
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for fn in sorted(filenames):
            if fn.lower().endswith(".md"):
                found.append(os.path.join(dirpath, fn))
    readme = os.path.join(root, "README.md")
    found.sort(key=lambda p: (p != readme, os.path.relpath(p, root)))
    return found


def content_lines(file_path):
    """Yield (line_no, line) outside fenced code blocks."""
    try:
        with open(file_path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return
    fence = None
    for idx, line in enumerate(lines, 1):
        m = FENCE.match(line)
        if fence is None and m:
            fence = m.group(1)[0]
            continue
        if fence is not None:
            if m and m.group(1)[0] == fence:
                fence = None
            continue
        yield idx, line


def slugify(text):
    text = MD_LINK_TEXT.sub(r"\1", text)
    text = re.sub(r"<[^>]+>", "", text).replace("`", "").lower()
    kept = "".join(ch for ch in text if ch.isalnum() or ch in " -_")
    return kept.replace(" ", "-")


anchor_cache = {}


def anchors_of(file_path):
    if file_path in anchor_cache:
        return anchor_cache[file_path]
    seen = {}
    anchors = set()
    for _, line in content_lines(file_path):
        for a in HTML_ANCHOR.findall(line):
            anchors.add(a.lower())
        m = HEADING.match(line)
        if not m:
            continue
        base = slugify(m.group(1))
        count = seen.get(base, 0)
        anchors.add(base if count == 0 else "%s-%d" % (base, count))
        seen[base] = count + 1
    anchor_cache[file_path] = anchors
    return anchors


def links_in(line):
    stripped = CODE_SPAN.sub("", line)
    targets = INLINE_LINK.findall(stripped)
    m = REF_DEF.match(stripped)
    if m:
        targets.append(m.group(1))
    targets.extend(HTML_ATTR.findall(stripped))
    return targets


def clean(value):
    return re.sub(r"\s+", " ", value).strip()


issues = []
files_scanned = 0
links_checked = 0
broken_links = 0
broken_anchors = 0

readme = os.path.join(root, "README.md")
if not os.path.isfile(readme):
    issues.append(("readme_missing", "", 0, "",
                   "README.md not found in the project root"))

for md in markdown_files():
    files_scanned += 1
    rel_md = os.path.relpath(md, root)
    for line_no, line in content_lines(md):
        for target in links_in(line):
            if SCHEME.match(target) or target.startswith("//"):
                continue
            links_checked += 1
            path_part, _, fragment = target.partition("#")
            path_part = unquote(path_part.split("?", 1)[0])
            if not path_part:
                dest = md
            elif path_part.startswith("/"):
                dest = os.path.join(root, path_part.lstrip("/"))
            else:
                dest = os.path.join(os.path.dirname(md), path_part)
            dest = os.path.normpath(dest)
            if not os.path.exists(dest):
                broken_links += 1
                issues.append(("broken_link", rel_md, line_no, target,
                               "%s:%d links to %s, which does not exist"
                               % (rel_md, line_no, path_part)))
                continue
            if fragment and os.path.isfile(dest) and dest.lower().endswith(".md"):
                if unquote(fragment).lower() not in anchors_of(dest):
                    broken_anchors += 1
                    issues.append(("broken_anchor", rel_md, line_no, target,
                                   "%s:%d links to #%s, no such heading in %s"
                                   % (rel_md, line_no, fragment,
                                      os.path.relpath(dest, root))))

status = "ERROR" if issues else "OK"

print("=== README LINKS ===")
print("PROJECT_DIR=%s" % root)
print("FILES_SCANNED=%d" % files_scanned)
print("LINKS_CHECKED=%d" % links_checked)
print("BROKEN_LINKS=%d" % broken_links)
print("BROKEN_ANCHORS=%d" % broken_anchors)
print("STATUS=%s" % status)
if issues:
    first = issues[0]
    reason = clean("%s: %s" % (first[0], first[4]))[:180]
    if len(issues) > 1:
        reason += " (+%d more)" % (len(issues) - 1)
    print("REASON=%s" % reason)
print("ISSUE_COUNT=%d" % len(issues))
if issues:
    print("ISSUES:")
    for item_type, rel_md, line_no, target, msg in issues:
        if item_type == "readme_missing":
            print("  - SEVERITY=ERROR TYPE=%s MSG=%s" % (item_type, clean(msg)))
        else:
            print("  - SEVERITY=ERROR TYPE=%s FILE=%s LINE=%d TARGET=%s MSG=%s"
                  % (item_type, rel_md, line_no, clean(target), clean(msg)))
print("=== END README LINKS ===")
sys.exit(1 if issues else 0)
PY

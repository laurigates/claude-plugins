#!/usr/bin/env python3
"""Check a repo's markdown for dangling repo-relative references.

Catches the mechanical, reproducible slice of doc drift: a doc that names a
file, path or internal link which no longer exists in the repo. It does not
judge prose ("is this claim still true?"); that semantic tail belongs to a
periodic LLM review.

Precision-first: a gate that cries wolf gets bypassed, so it flags only two
high-confidence shapes and deliberately under-reaches.

1. Relative markdown links `[text](path)` whose target does not resolve from
   the linking file's directory (`/`-rooted targets resolve from the repo
   root). Skips http(s)/mailto, in-page #anchors, templated and placeholder
   targets.
2. Inline-code path tokens `` `like/this.sh` `` whose first path segment is a
   real tracked top-level entry, and which resolve neither from the repo root
   nor from the doc's own directory (a nested package's README citing its own
   `scripts/x.py`). A `./name` token names a repo-root file and is checked too.

Not checked: bare filenames with no slash, slash commands, domains, `~/` and
absolute paths, placeholders (`NNNN`, `<x>`, `...`, `example`). Fenced code
blocks are skipped entirely; they hold examples.

chezmoi mode (`--chezmoi auto|on|off`, default auto): in a chezmoi source repo
a doc names a managed file by its rendered name (`hooks/foo.sh`) while the repo
holds the source name (`hooks/executable_foo.sh.tmpl`, `dot_zshrc`). With the
mode on, a path also resolves when a sibling's rendered name matches. `auto`
turns it on when the repo root carries a `.chezmoi*` marker file.

Allowlist: one glob per line (`#` comments) in `.doc-reference-allow` at the
repo root, or the file named by `--allow-file`. Matching docs are skipped, for
immutable records (ADRs) that intentionally cite since-removed paths.

Output follows the `=== SECTION ===` / `KEY=VALUE` / `STATUS=` contract.
- default (advisory): findings report `STATUS=WARN`, exit 0.
- `--strict`: findings report `STATUS=ERROR`, exit 1.
Exit 2 is a usage error (not a git repo, missing allowlist file).
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from fnmatch import fnmatch
from pathlib import Path

# chezmoi source-name attribute prefixes. A doc that names a managed file by
# its rendered name must still resolve against its source form.
CHEZMOI_PREFIXES = (
    "encrypted_",
    "private_",
    "readonly_",
    "empty_",
    "executable_",
    "exact_",
    "literal_",
    "symlink_",
    "run_once_",
    "run_onchange_",
    "run_",
    "create_",
    "modify_",
    "before_",
    "after_",
    "once_",
    "onchange_",
)
CHEZMOI_MARKERS = (
    ".chezmoiroot",
    ".chezmoiignore",
    ".chezmoiversion",
    ".chezmoidata.toml",
    ".chezmoidata.yaml",
    ".chezmoidata.json",
    ".chezmoidata",
    ".chezmoiexternal.toml",
    ".chezmoiexternal.yaml",
    ".chezmoitemplates",
)

MD_LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
INLINE_CODE = re.compile(r"`([^`]+)`")
PATH_TOKEN = re.compile(r"^[\w./~-]+$")  # no spaces / shell metachars
PLACEHOLDER = re.compile(r"\.\.\.|NNNN|xxx|<|>|\{|\bfoo\b|\bbar\b|\bbaz\b|example")
SKIP_PREFIXES = ("http://", "https://", "mailto:", "#", "www.")
DOMAIN_HINTS = (".com/", ".org/", ".io/", ".dev/", ".net/", ".fi/", ".xyz/")
REASON_MAX = 200


def usage_error(msg: str) -> int:
    print(f"check-doc-references: {msg}", file=sys.stderr)
    return 2


def git(root: Path, *args: str) -> str:
    return subprocess.run(
        ["git", *args],
        cwd=root,
        capture_output=True,
        text=True,
        check=True,
    ).stdout


def load_allowlist(path: Path) -> list[str]:
    if not path.exists():
        return []
    return [
        ln.strip()
        for ln in path.read_text(encoding="utf-8").splitlines()
        if ln.strip() and not ln.strip().startswith("#")
    ]


def detect_chezmoi(root: Path) -> bool:
    return any((root / m).exists() for m in CHEZMOI_MARKERS)


def rendered_name(src_name: str) -> str:
    """Map a chezmoi source basename to its rendered target basename."""
    name = src_name[:-5] if src_name.endswith(".tmpl") else src_name
    changed = True
    while changed:
        changed = False
        for p in CHEZMOI_PREFIXES:
            if name.startswith(p):
                name, changed = name[len(p) :], True
        if name.startswith("dot_"):
            name, changed = "." + name[4:], True
    return name


def path_exists(root: Path, rel: str, chezmoi: bool) -> bool:
    """True if `rel` exists, or (chezmoi mode) a sibling renders to it."""
    p = root / rel
    if p.exists():
        return True
    if not chezmoi or not p.parent.is_dir():
        return False
    return any(rendered_name(e.name) == p.name for e in p.parent.iterdir())


def lines_outside_fences(text: str) -> list[tuple[int, str]]:
    """(1-indexed lineno, line) for lines outside fenced code blocks."""
    kept, fence = [], None
    for i, line in enumerate(text.splitlines(), start=1):
        stripped = line.lstrip()
        marker = (
            "```"
            if stripped.startswith("```")
            else "~~~"
            if stripped.startswith("~~~")
            else None
        )
        if marker:
            fence = None if fence == marker else (fence or marker)
            continue
        if fence is None:
            kept.append((i, line))
    return kept


def clean_link_target(target: str) -> str | None:
    target = target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    target = target.split()[0] if target else target  # drop link title
    if not target or target.lower().startswith(SKIP_PREFIXES):
        return None
    if "{{" in target or "$" in target:  # templating
        return None
    target = target.split("#", 1)[0].split("?", 1)[0]  # drop anchor/query
    return target or None


def link_resolves(target: str, doc: Path, root: Path, chezmoi: bool) -> bool:
    candidate = (
        root / target.lstrip("/") if target.startswith("/") else doc.parent / target
    )
    try:
        rel = candidate.resolve().relative_to(root)
    except (OSError, RuntimeError, ValueError):
        return candidate.exists()
    return path_exists(root, str(rel), chezmoi)


def token_is_candidate(tok: str) -> bool:
    if not PATH_TOKEN.match(tok) or tok.startswith(("/", "~/")):
        return False
    if tok.lower().startswith(SKIP_PREFIXES) or PLACEHOLDER.search(tok):
        return False
    if any(d in tok for d in DOMAIN_HINTS):
        return False
    return "/" in tok  # a path (incl. ./name)


def token_resolves(
    tok: str, doc_dir: str, root: Path, top_level: set[str], chezmoi: bool
) -> bool:
    had_dot = tok.startswith("./")
    t = tok[2:] if had_dot else tok
    if "/" not in t:
        # Only an explicit `./name` names a repo-root file; a bare filename is
        # out of scope (prose examples).
        return path_exists(root, t, chezmoi) if had_dot else True
    if t.split("/", 1)[0] not in top_level:  # not anchored to a real entry
        return True
    t = t.rstrip("/")
    # A nested package's README cites its own paths (`scripts/x.py` meaning
    # `<pkg>/scripts/x.py`), so the doc's directory is a second base.
    return path_exists(root, t, chezmoi) or (
        doc_dir not in ("", ".") and path_exists(root, f"{doc_dir}/{t}", chezmoi)
    )


def scan_doc(rel: str, root: Path, top_level: set[str], chezmoi: bool):
    doc = root / rel
    doc_dir = os.path.dirname(rel)
    text = doc.read_text(encoding="utf-8", errors="replace")
    for lineno, line in lines_outside_fences(text):
        for m in MD_LINK.finditer(line):
            target = clean_link_target(m.group(1))
            if not target:
                continue
            if "/" not in target and "." not in target:  # not a filesystem path
                continue
            if PLACEHOLDER.search(target):
                continue
            if not link_resolves(target, doc, root, chezmoi):
                yield rel, lineno, "dangling_link", target
        for m in INLINE_CODE.finditer(line):
            tok = m.group(1)
            if token_is_candidate(tok) and not token_resolves(
                tok, doc_dir, root, top_level, chezmoi
            ):
                yield rel, lineno, "dangling_ref", tok


def parse_args(argv: list[str]) -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description="Flag markdown that references repo paths or links that do not exist.",
    )
    ap.add_argument(
        "--strict",
        action="store_true",
        help="report findings as STATUS=ERROR and exit 1",
    )
    ap.add_argument(
        "--project-dir",
        default=None,
        help="repo to scan (default: git toplevel of the cwd)",
    )
    ap.add_argument(
        "--allow-file",
        default=None,
        help="allowlist of doc globs (default: <root>/.doc-reference-allow)",
    )
    ap.add_argument(
        "--chezmoi",
        choices=("auto", "on", "off"),
        default="auto",
        help="resolve chezmoi source names (default: auto-detect)",
    )
    ap.add_argument(
        "files", nargs="*", help="markdown files to check (default: all tracked *.md)"
    )
    return ap.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    start = Path(args.project_dir or Path.cwd())
    try:
        root = Path(git(start, "rev-parse", "--show-toplevel").strip()).resolve()
    except (subprocess.CalledProcessError, FileNotFoundError, NotADirectoryError):
        return usage_error(f"not inside a git repository: {start}")

    allow_path = (
        Path(args.allow_file) if args.allow_file else root / ".doc-reference-allow"
    )
    if args.allow_file and not allow_path.exists():
        return usage_error(f"allowlist file not found: {allow_path}")
    allow = load_allowlist(allow_path)
    chezmoi = args.chezmoi == "on" or (args.chezmoi == "auto" and detect_chezmoi(root))

    tracked = [ln for ln in git(root, "ls-files").splitlines() if ln]
    top_level = {p.split("/", 1)[0] for p in tracked}
    if args.files:
        md_files = [
            os.path.relpath(os.path.abspath(f), root)
            for f in args.files
            if f.endswith(".md")
        ]
    else:
        md_files = [f for f in tracked if f.endswith(".md")]

    findings: list[tuple[str, int, str, str]] = []
    checked = 0
    for rel in sorted(md_files):
        if any(fnmatch(rel, pat) for pat in allow) or not (root / rel).exists():
            continue
        checked += 1
        findings.extend(scan_doc(rel, root, top_level, chezmoi))

    severity = "ERROR" if args.strict else "WARN"
    status = severity if findings else "OK"
    print("=== DOC REFERENCE CHECK ===")
    print(f"CHEZMOI_MODE={'on' if chezmoi else 'off'}")
    print(f"DOCS_CHECKED={checked}")
    if checked == 0:
        print("SCANNED_EMPTY=true")
    print(f"ALLOWLISTED_PATTERNS={len(allow)}")
    print(f"DANGLING_COUNT={len(findings)}")
    print(f"STATUS={status}")
    if findings:
        rel, lineno, kind, tok = findings[0]
        reason = " ".join(f"{kind}: {rel}:{lineno} {tok}".split())[:180]
        if len(findings) > 1:
            reason += f" (+{len(findings) - 1} more)"
        print(f"REASON={reason[:REASON_MAX]}")
    print(f"ISSUE_COUNT={len(findings)}")
    if findings:
        print("ISSUES:")
        for rel, lineno, kind, tok in findings:
            print(f"  - SEVERITY={severity} TYPE={kind} FILE={rel}:{lineno} MSG={tok}")
    print("=== END DOC REFERENCE CHECK ===")
    return 1 if (findings and args.strict) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

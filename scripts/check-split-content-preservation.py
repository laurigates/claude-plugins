#!/usr/bin/env python3
"""Check that a skill split moved content without losing any of it.

The skill splitter (.github/workflows/skill-splitter.yml) has a model move whole
sections out of a SKILL.md into the skill's references/*.md files. Its publish
step already checks the commit subjects and that every changed path sits inside
a selected skill directory. Neither check sees a split that drops a table row,
loses a section heading, or paraphrases a moved paragraph (#3016). This script
is the content check, run between the model's commits and the push.

For each skill directory, it compares the markdown files (`*.md`, recursively)
at --base with the same directory at --head:

  * Lines: every non-blank line at the base must still be present at the head,
    counted as a multiset over all the directory's markdown files, so moving a
    line between files is free and dropping one of two identical rows is not.
    Lines are compared with surrounding whitespace stripped.
  * Sections: a heading (`#`..`######` followed by a space) is compared by its
    text, so a section may change level when it moves (`### Foo` in SKILL.md
    becoming `## Foo` in references/foo.md). A heading whose text is gone is
    reported as section_missing. A `# comment` line inside a code fence has the
    same shape and is treated the same way, which is harmless: it must survive
    the move either way.
  * One tolerated rewrite: the splitter prompt tells the model to replace
    direction pointers ("see the table above") with a named anchor or a file
    link, changing only the pointer words. A missing base line that contains a
    direction word is accepted when some line added at the head differs from
    it only in the pointer (is_pointer_rewrite):
      - the added line carries at least one markdown link the base line lacks;
      - every word of each new link's text appears in the base line or in
        that link's target, so the link text names what it points at and
        carries no new content ("or [older](#versions)" is an error);
      - with those new links masked, a token diff of the two lines removes only
        POINTER_WORDS, words that appear in a new link's text, and
        POINTER_PUNCT, and adds only new links, POINTER_WORDS and POINTER_PUNCT.
    So "Requires Node 18 or later" -> "Requires Node 16 or later" and "The
    following flags are mandatory" -> "... optional" are errors even though
    each line contains a direction word. Each added line can account for one
    rewrite. Such lines are counted in LINES_REWRITTEN. Any other changed line
    is an error.

New lines at the head (the link lines, the reference-file title) are allowed.

Output follows .claude/rules/structured-script-output.md.

Usage:
  check-split-content-preservation.py --base REV [--head REV] SKILL_DIR...

SKILL_DIR is repo-relative (a leading ./ and a trailing / are ignored). Run it
from inside the repository.

Exit: 0 nothing lost, 1 content lost or a skill dir has no markdown at the base,
      2 usage error (missing arguments, an unknown revision, not a git repo).
"""

from __future__ import annotations

import argparse
import difflib
import re
import subprocess
import sys
from collections import Counter

HEADING_RE = re.compile(r"^#{1,6}\s+(.+?)\s*$")
DIRECTION_RE = re.compile(
    r"\b(above|below|earlier|previous(?:ly)?|preceding|following|later|inline|here|this page)\b",
    re.IGNORECASE,
)
# Words a pointer rewrite may remove or add outside a link: the direction words
# themselves and the nouns and articles that phrase a pointer ("see the table
# above", "the preceding section", "the [X](#x) table").
POINTER_WORDS = frozenset(
    {
        # direction words
        "above", "below", "earlier", "previous", "previously", "preceding",
        "following", "later", "inline", "here", "this", "page",
        # how a pointer is phrased
        "see", "the", "a", "an", "that", "these", "those", "in", "at", "of", "on",
        # what a pointer names
        "table", "tables", "section", "sections", "list", "step", "steps",
        "example", "examples", "file", "files", "reference", "references",
        "block", "snippet", "heading", "code", "fence",
    }
)  # fmt: skip
# Punctuation a pointer rewrite may drop or add around the link ("(see above)").
POINTER_PUNCT = frozenset(",.;:()-—–")
LINK_RE = re.compile(r"\[([^\]\n]*)\]\(([^)\s]*)\)")
WORD_RE = re.compile(r"\w+")
TOKEN_RE = re.compile(r"\x00|[\w`'#/*-]+(?:[.:][\w`'#/*-]+)*|\S")
LINK_TOKEN = "\x00"
MSG_MAX = 160
REASON_MAX = 180
SECTION = "SPLIT CONTENT PRESERVATION"


class UsageError(Exception):
    pass


def git(*args: str) -> str:
    proc = subprocess.run(["git", *args], capture_output=True, text=True)
    if proc.returncode != 0:
        raise UsageError(f"git {' '.join(args)}: {proc.stderr.strip()}")
    return proc.stdout


def resolve(rev: str) -> str:
    try:
        return git("rev-parse", "--verify", "--quiet", f"{rev}^{{commit}}").strip()
    except UsageError as err:
        raise UsageError(f"unknown revision: {rev}") from err


def markdown_files(rev: str, skill_dir: str) -> list[str]:
    out = git("ls-tree", "-r", "--name-only", "--full-tree", rev, "--", f"{skill_dir}/")
    return sorted(p for p in out.splitlines() if p.lower().endswith(".md"))


def key(line: str) -> tuple[str, str] | None:
    text = line.strip()
    if not text:
        return None
    m = HEADING_RE.match(text)
    if m:
        return ("h", m.group(1))
    return ("l", text)


def collect(rev: str, skill_dir: str) -> tuple[Counter, dict, int]:
    """Count keyed lines; remember each key's first file:line for messages."""
    counts: Counter = Counter()
    where: dict = {}
    files = markdown_files(rev, skill_dir)
    for path in files:
        text = git("show", f"{rev}:{path}")
        for n, line in enumerate(text.splitlines(), 1):
            k = key(line)
            if k is None:
                continue
            counts[k] += 1
            where.setdefault(k, (path, n))
    return counts, where, len(files)


def tokens(text: str) -> list[str]:
    return TOKEN_RE.findall(text)


def is_pointer_rewrite(base_line: str, added_line: str) -> bool:
    """True when added_line is base_line with only its pointer changed.

    The added line must carry a markdown link that base_line lacks, and each
    such link's text may use only words of base_line and of its target. With each
    such link masked to one placeholder token, the token diff may remove only
    pointer words, words of a new link's text, and pointer punctuation, and add
    only placeholders, pointer words, and pointer punctuation. Anything else,
    such as a changed number, a negation, or a swapped adjective, is content.
    """
    base_links = {m.group(0) for m in LINK_RE.finditer(base_line)}
    new_links = [
        m for m in LINK_RE.finditer(added_line) if m.group(0) not in base_links
    ]
    if not new_links:
        return False
    # The link is masked below, so its text is never diffed. Hold that text to
    # naming what it points at: every word must come from base_line (moved
    # into the link) or from the link's own target (anchor slug, file path).
    # Otherwise "or later" -> "or [older](#versions)" changes the line freely.
    base_words = set(WORD_RE.findall(base_line.lower()))
    for m in new_links:
        named = base_words | set(WORD_RE.findall(m.group(2).lower()))
        if not set(WORD_RE.findall(m.group(1).lower())) <= named:
            return False
    link_words = {t.lower() for m in new_links for t in tokens(m.group(1))}
    masked = LINK_RE.sub(
        lambda m: m.group(0) if m.group(0) in base_links else LINK_TOKEN, added_line
    )
    old, new = tokens(base_line), tokens(masked)
    matcher = difflib.SequenceMatcher(None, old, new, autojunk=False)
    for op, i1, i2, j1, j2 in matcher.get_opcodes():
        if op == "equal":
            continue
        for t in old[i1:i2]:
            low = t.lower()
            if not (low in POINTER_WORDS or low in link_words or t in POINTER_PUNCT):
                return False
        for t in new[j1:j2]:
            if not (
                t == LINK_TOKEN or t.lower() in POINTER_WORDS or t in POINTER_PUNCT
            ):
                return False
    return True


def one_line(text: str, limit: int) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 3] + "..."


def check_skill(base: str, head: str, skill_dir: str) -> tuple[list[dict], dict]:
    base_counts, where, base_files = collect(base, skill_dir)
    stats = {"files": base_files, "lines": sum(base_counts.values()), "rewritten": 0}
    if base_files == 0:
        return [
            {
                "TYPE": "skill_not_found",
                "SKILL": skill_dir,
                "MSG": f"no markdown files under {skill_dir}/ at the base revision",
            }
        ], stats
    head_counts, _, _ = collect(head, skill_dir)
    missing = base_counts - head_counts
    added = [
        text
        for (kind, text), n in (head_counts - base_counts).items()
        if kind == "l"
        for _ in range(n)
    ]

    issues = []
    for k in sorted(missing, key=lambda k: where[k]):
        kind, text = k
        count = missing[k]
        if kind == "l" and DIRECTION_RE.search(text):
            while count:
                match = next((a for a in added if is_pointer_rewrite(text, a)), None)
                if match is None:
                    break
                added.remove(match)
                stats["rewritten"] += 1
                count -= 1
        if count == 0:
            continue
        path, n = where[k]
        issues.append(
            {
                "TYPE": "section_missing" if kind == "h" else "line_missing",
                "SKILL": skill_dir,
                "FILE": path,
                "LINE": str(n),
                "COUNT": str(count),
                "MSG": one_line(text, MSG_MAX),
            }
        )
    return issues, stats


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("skill_dirs", nargs="*")
    try:
        args = parser.parse_args(argv)
    except SystemExit as err:
        return 2 if err.code else 0
    if not args.skill_dirs:
        print(
            "check-split-content-preservation.py: at least one SKILL_DIR is required",
            file=sys.stderr,
        )
        return 2

    try:
        base = resolve(args.base)
        head = resolve(args.head)
        dirs = []
        for d in args.skill_dirs:
            d = d.strip()
            d = d[2:] if d.startswith("./") else d
            d = d.rstrip("/")
            if d and d not in dirs:
                dirs.append(d)
        issues: list[dict] = []
        files = lines = rewritten = 0
        for d in dirs:
            found, stats = check_skill(base, head, d)
            issues.extend(found)
            files += stats["files"]
            lines += stats["lines"]
            rewritten += stats["rewritten"]
    except UsageError as err:
        print(f"check-split-content-preservation.py: {err}", file=sys.stderr)
        return 2

    status = "ERROR" if issues else "OK"
    print(f"=== {SECTION} ===")
    print(f"BASE={base}")
    print(f"HEAD={head}")
    print(f"SKILLS_CHECKED={len(dirs)}")
    print(f"FILES_CHECKED={files}")
    print(f"LINES_CHECKED={lines}")
    print(f"LINES_REWRITTEN={rewritten}")
    print(f"STATUS={status}")
    if issues:
        first = issues[0]
        reason = one_line(f"{first['TYPE']}: {first['MSG']}", REASON_MAX)
        if len(issues) > 1:
            reason += f" (+{len(issues) - 1} more)"
        print(f"REASON={reason}")
    print(f"ISSUE_COUNT={len(issues)}")
    if issues:
        print("ISSUES:")
        for issue in issues:
            fields = " ".join(
                f"{k}={issue[k]}"
                for k in ("TYPE", "SKILL", "FILE", "LINE", "COUNT")
                if k in issue
            )
            print(f"  - SEVERITY=ERROR {fields} MSG={issue['MSG']}")
    print(f"=== END {SECTION} ===")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

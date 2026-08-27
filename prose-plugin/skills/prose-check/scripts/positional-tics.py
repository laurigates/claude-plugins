#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pysbd>=0.3.4"]
# ///
"""Flag paragraph-final sentences that match a house-rubric tic shape.

WHY THIS EXISTS AS A SCRIPT
---------------------------
~/.claude/rules/communication.md defines the tell for its three tics as
"position PLUS shape": the sentence lands at the end of a paragraph or section
AND it generalizes past the specific claim. Vale can express the shape half
(styles/House/*.yml) but not the position half -- its scopes select by markup
type, never by ordinal position within a block ("No scopes select by ordinal
position", docs.vale.sh/topics/scopes). This script covers position.

CANDIDATES, NOT VERDICTS
------------------------
Every line this emits is a sentence for a human or model to JUDGE, not a defect
to fix. Whether a mirrored clause is a chiasmus, or a general statement is an
aphorism, is irreducibly a judgment call -- the script's only job is to narrow
the candidate set so that judgment is spent on a handful of sentences instead of
a whole document. A hedge carrying real uncertainty is a true negative that
still shows up here; that is working as designed.

THE UNWRAPPING STEP IS LOAD-BEARING
-----------------------------------
pysbd (and every other segmenter benchmarked) treats a newline as a sentence
boundary, and the rules tree is hard-wrapped at ~76 columns. Without joining
hard wraps first, communication.md measures 78 sentences / 8.2 mean words
instead of the correct 44 / 14.6 -- wrong numbers that look entirely plausible.

Segmenter choice: pysbd scored 47/48 (97.9%) on the English Golden Rules Set,
against 43/48 for sentencex and 27/48 for punkt-grade segmenters. It costs
~790ms where sentencex costs ~5ms; at one document per invocation that is not a
budget worth optimising.

Output: KEY=VALUE inside === SECTION === delimiters, per
.claude/rules/structured-script-output.md.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import pysbd

# --- tic shapes -------------------------------------------------------------

# Verbatim from communication.md's list of portentous nouns. Mirrors
# styles/House/SignificanceAssertion.yml; both derive from the rule, and
# scripts/check-prose-house-style.sh pins them together.
SIGNIFICANCE = re.compile(
    r"\b(which is the|what makes|the thing that|precisely why)\b", re.I
)

NEGATION = re.compile(
    r"\b(isn'?t|is not|aren'?t|are not|wasn'?t|not|never|no|"
    r"rather than|instead of)\b",
    re.I,
)

# Pivot points a mirrored construction turns on.
PIVOT = re.compile(r",\s+(?:and|but|while|whereas)\s+|;\s+|\s+[—-]{1,2}\s+")

# "a sweep ... is a sweep to distrust" -- a maxim restates its own subject in the
# predicate. The repeated head noun is what makes the sentence portable as an
# epigram, and it is what separates a maxim from an ordinary copular sentence.
# An earlier draft matched any "(a|the) X ... is ... (a|an) Y" and fired on four
# plain sentences in communication.md; requiring the repeat cut all four.
DEFINITIONAL_HEAD = re.compile(r"^\W*(?:a|an|the)\s+([a-z]{3,})\b", re.I)
COPULA = re.compile(r"\b(?:is|are|was|were)\b", re.I)

# Function words whose repetition across a pivot means nothing. "one" is
# deliberately absent: in "the one that pays is the one with no passthrough" its
# repetition IS the mirroring.
STOPWORDS = frozenset(
    """the and but for not are was its has had that this with from into than then
    when what who which would could should will can may does did been being have
    they them their there here you your our out all any some more most very also
    just only over under such each both per via use get got make made about
    where while because than yet nor his her him she they're it's don't""".split()
)

CODE_MASK = "CODEMASK"


@dataclass
class Finding:
    kind: str
    line: int
    words: int
    text: str


# --- markdown reduction -----------------------------------------------------


def strip_frontmatter(lines: list[str]) -> tuple[list[str], int]:
    """Drop a leading YAML frontmatter block. Returns (lines, offset)."""
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() in ("---", "..."):
                return lines[i + 1 :], i + 1
    return lines, 0


def blocks(lines: list[str], offset: int) -> list[tuple[int, str]]:
    """Split into prose blocks, dropping everything that is not prose.

    Removed outright: fenced code, tables, headings, HTML. Kept as their own
    blocks: paragraphs, list items, blockquotes -- a tic can land at the end of
    a bullet as readily as at the end of a paragraph.

    Hard line wraps inside a block are joined here. This is the step that makes
    the sentence counts correct; see the module docstring.
    """
    out: list[tuple[int, str]] = []
    buf: list[str] = []
    buf_line = 0
    fence: str | None = None

    def flush() -> None:
        nonlocal buf, buf_line
        if buf:
            out.append((buf_line, " ".join(s.strip() for s in buf)))
            buf = []

    for idx, raw in enumerate(lines, start=offset + 1):
        stripped = raw.strip()

        if fence is not None:
            if stripped.startswith(fence):
                fence = None
            continue
        m = re.match(r"^(```|~~~)", stripped)
        if m:
            flush()
            fence = m.group(1)
            continue

        # A blank line, a heading, a table row, or an HTML block ends the
        # current prose block and contributes nothing itself.
        if (
            not stripped
            or stripped.startswith("#")
            or stripped.startswith("|")
            or re.match(r"^[-=|:+ ]{3,}$", stripped)
            or stripped.startswith("<")
        ):
            flush()
            continue

        # A new list item starts a new block; its continuation lines join it.
        if re.match(r"^([-*+]|\d+[.)])\s+", stripped):
            flush()
            stripped = re.sub(r"^([-*+]|\d+[.)])\s+", "", stripped)

        if not buf:
            buf_line = idx
        buf.append(stripped)

    flush()
    return out


def mask(text: str) -> str:
    """Neutralise spans that would derail the segmenter or the shape tests.

    Inline code and URLs carry periods that read as sentence boundaries, and
    their identifiers would count as repeated content words in the chiasmus
    test. Link text is kept; only the target is dropped.
    """
    text = re.sub(r"`[^`]*`", CODE_MASK, text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"https?://\S+", CODE_MASK, text)
    text = re.sub(r"[*_]{1,3}([^*_]+)[*_]{1,3}", r"\1", text)
    return text


def words_of(text: str) -> list[str]:
    return re.findall(r"[A-Za-z][A-Za-z'’-]*", text)


def content_words(text: str) -> set[str]:
    return {
        w.lower()
        for w in words_of(text)
        if len(w) >= 3 and w.lower() not in STOPWORDS and w != CODE_MASK
    }


# --- shape tests ------------------------------------------------------------


def is_chiasmus(sentence: str) -> bool:
    """Mirrored clauses: a negation plus content repeated across a pivot.

    Calibrated on the rubric's own example -- "the flag someone would reach for
    isn't the one that pays, and the one that pays is the one with no
    passthrough" shares {one, pays} across the ", and " pivot.
    """
    if not NEGATION.search(sentence):
        return False
    parts = [p for p in PIVOT.split(sentence) if p and p.strip()]
    if len(parts) < 2:
        return False
    return len(content_words(parts[0]) & content_words(parts[-1])) >= 2


def is_aphorism(sentence: str) -> bool:
    """A general maxim: the subject noun restated in the predicate.

    Calibrated on the rubric's own example -- "a sweep whose control does not
    land on a value measured months ago is a sweep to distrust" repeats "sweep"
    across the copula.

    A sentence carrying a number, an identifier, or a proper noun is making a
    specific claim, whatever its shape, so those are excluded before the shape
    test runs.
    """
    if re.search(r"\d", sentence) or CODE_MASK in sentence:
        return False
    # A capitalized word anywhere but the opening position reads as a proper
    # noun, which anchors the claim to something specific.
    if re.search(r"(?<=[a-z,] )[A-Z][a-z]{2,}", sentence):
        return False
    m = DEFINITIONAL_HEAD.match(sentence)
    if not m:
        return False
    head = m.group(1).lower()
    rest = sentence[m.end() :]
    if not COPULA.search(rest):
        return False
    return re.search(rf"\b{re.escape(head)}s?\b", rest, re.I) is not None


# --- main -------------------------------------------------------------------


def analyse(path: Path, text: str, long_words: int, check_tldr: bool) -> dict:
    lines = text.splitlines()
    body, offset = strip_frontmatter(lines)
    prose = blocks(body, offset)

    segmenter = pysbd.Segmenter(language="en", clean=False)

    findings: list[Finding] = []
    total_sentences = 0
    total_words = 0

    for line_no, block in prose:
        masked = mask(block)
        try:
            sentences = [s.strip() for s in segmenter.segment(masked) if s.strip()]
        except Exception:  # noqa: BLE001 - a segmenter failure must not lose the file
            sentences = [masked]
        if not sentences:
            continue

        total_sentences += len(sentences)
        total_words += len(words_of(masked))

        # A long sentence buries the fact wherever it sits, so that one check
        # runs over every sentence. The three tics are position-dependent by
        # definition ("the tell is position PLUS shape") and run on the final
        # sentence only.
        for sentence in sentences:
            if len(words_of(sentence)) >= long_words and sentence is not sentences[-1]:
                findings.append(
                    Finding("long_sentence", line_no, len(words_of(sentence)), sentence)
                )

        final = sentences[-1]
        n_words = len(words_of(final))

        # A one-line block is a fragment, a caption, or a label -- there is no
        # "end of the paragraph" for a tic to land at.
        if n_words < 6:
            continue

        kinds: list[str] = []
        if SIGNIFICANCE.search(final):
            kinds.append("significance_assertion")
        if is_chiasmus(final):
            kinds.append("chiasmus")
        if is_aphorism(final):
            kinds.append("aphorism")
        if n_words >= long_words:
            kinds.append("long_final_sentence")

        for kind in kinds:
            findings.append(Finding(kind, line_no, n_words, final))

    mean = round(total_words / total_sentences, 1) if total_sentences else 0.0

    tldr_missing = False
    if check_tldr:
        headings = sum(1 for ln in body if ln.strip().startswith("#"))
        complex_enough = total_words >= 350 and (headings >= 2 or len(prose) >= 5)
        has_tldr = re.search(r"\bTL;?DR\b", text, re.I) is not None
        tldr_missing = complex_enough and not has_tldr

    return {
        "path": path,
        "findings": findings,
        "sentences": total_sentences,
        "words": total_words,
        "mean": mean,
        "blocks": len(prose),
        "tldr_missing": tldr_missing,
    }


def report(results: list[dict], check_tldr: bool) -> int:
    issue_count = sum(len(r["findings"]) for r in results)
    issue_count += sum(1 for r in results if r["tldr_missing"])

    print("=== POSITIONAL TICS ===")
    print(f"FILES_SCANNED={len(results)}")
    print("SEGMENTER=pysbd")
    print(f"TLDR_CHECK={'on' if check_tldr else 'off'}")
    for r in results:
        print(f"FILE={r['path']}")
        print(f"  BLOCKS={r['blocks']}")
        print(f"  SENTENCES={r['sentences']}")
        print(f"  WORDS={r['words']}")
        print(f"  MEAN_SENTENCE_WORDS={r['mean']}")
    print(f"STATUS={'WARN' if issue_count else 'OK'}")
    print(f"ISSUE_COUNT={issue_count}")
    if issue_count:
        print("ISSUES:")
        for r in results:
            for f in r["findings"]:
                text = f.text if len(f.text) <= 160 else f.text[:157] + "..."
                print(
                    f"  - SEVERITY=CANDIDATE TYPE={f.kind} "
                    f"FILE={r['path']}:{f.line} WORDS={f.words} "
                    f'MSG="{text}"'
                )
            if r["tldr_missing"]:
                print(
                    f"  - SEVERITY=CANDIDATE TYPE=missing_tldr_footer "
                    f"FILE={r['path']} WORDS={r['words']} "
                    'MSG="complex enough to warrant a TL;DR (ELI5) footer; none found"'
                )
    print("=== END POSITIONAL TICS ===")
    return issue_count


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Flag paragraph-final sentences matching a house-rubric tic shape."
    )
    ap.add_argument("paths", nargs="*", help="markdown files; omit to read stdin")
    ap.add_argument(
        "--long-words",
        type=int,
        default=40,
        help="flag a paragraph-final sentence at or above this word count (default: 40)",
    )
    ap.add_argument(
        "--check-tldr",
        action="store_true",
        help="also flag a complex document with no TL;DR (ELI5) footer",
    )
    ap.add_argument(
        "--strict",
        action="store_true",
        help="exit 1 when any candidate is found (default: exit 0, report only)",
    )
    args = ap.parse_args()

    results: list[dict] = []
    if args.paths:
        for p in args.paths:
            path = Path(p)
            try:
                text = path.read_text(encoding="utf-8")
            except OSError as exc:
                print("=== POSITIONAL TICS ===")
                print(f"FILE={path}")
                print("STATUS=ERROR")
                print("ISSUE_COUNT=1")
                print("ISSUES:")
                print(f"  - SEVERITY=ERROR TYPE=unreadable FILE={path} MSG={exc}")
                print("=== END POSITIONAL TICS ===")
                return 1
            results.append(analyse(path, text, args.long_words, args.check_tldr))
    else:
        results.append(
            analyse(Path("<stdin>"), sys.stdin.read(), args.long_words, args.check_tldr)
        )

    issue_count = report(results, args.check_tldr)
    return 1 if (args.strict and issue_count) else 0


if __name__ == "__main__":
    sys.exit(main())

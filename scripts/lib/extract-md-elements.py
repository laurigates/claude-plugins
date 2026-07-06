#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "tree-sitter==0.25.2",
#   "tree-sitter-markdown==0.5.1",
# ]
# ///
"""Shared markdown-structure extraction helper for the markdown-structure lint scripts.

Built on tree-sitter + tree-sitter-markdown (a real CommonMark/GFM parse) so the
five lint/check scripts stop hand-rolling fenced-code-block state machines,
table-row skips, and blockquote awareness — the source of shipped bugs #1744 and
#1492. This is `.claude/rules/offload-to-deterministic-substrate.md` applied one
level down: the substrate is already deterministic (pre-commit/CI), it was just
using the wrong parser.

Self-contained `uv run` script with PEP723 inline deps, so pre-commit/CI need no
separate install step (see the `python-plugin:uv-run` skill).

Emits structured rows (TSV by default; `--format json` for JSONL) per
`.claude/rules/structured-script-output.md`, one record per line. Three record
types, each carrying a file + line anchor:

  inline_code   an inline code span with its container context. A fenced code
                block's content is NOT inline content in the markdown grammar, so
                fenced `` `!`cmd` `` examples never appear here (that is the whole
                point — #1744). Fields:
                  file, line (1-based), container, in_blockquote (0|1),
                  is_bang (0|1 — a `!` immediately precedes the span, i.e. a
                  Claude Code `!`cmd`` Context command), text (the span content).
                container is the innermost meaningful block: list_item, heading,
                table_cell, or paragraph.

  fence         a fenced code block summary (both ``` and ~~~). Fields:
                  file, start_line, end_line (1-based, the delimiter lines),
                  language (info string's language, or empty).

  fence_line    one record per raw source line INSIDE a fenced code block (the
                content between the delimiters). Fields:
                  file, line (1-based), language, text (the raw source line).
                This is what a fence-aware line scanner (e.g. version-pin
                coverage) consumes instead of a hand-rolled ``` toggle.

TSV output: fields are tab-separated; the first field is the record type; the
`text` field is always last (so a consumer can `read a b ... rest`). In TSV mode
tabs/newlines inside `text` are collapsed to a single space (Context commands and
pin lines never contain them); JSON mode preserves everything.

Usage:
  extract-md-elements.py [--format tsv|json] [--types t1,t2,...] FILE [FILE ...]
  extract-md-elements.py [opts] --files-from FILE   # one path per line (- = stdin)

Only files that parse are reported; an unreadable/unparseable file is skipped
with a warning on stderr (never aborts the whole run).
"""
from __future__ import annotations

import argparse
import json
import sys

import tree_sitter_markdown as tsmd
from tree_sitter import Language, Parser

BLOCK = Language(tsmd.language())
INLINE = Language(tsmd.inline_language())
# Reused across every file/node — a Parser is safe to reuse across parse() calls,
# and re-creating one per code span (1000+ files) is the dominant avoidable cost.
BLOCK_PARSER = Parser(BLOCK)
INLINE_PARSER = Parser(INLINE)


def _emit_tsv(fields: list) -> str:
    out = []
    for f in fields:
        s = str(f)
        # text is the trailing field; keep the row on one line and tab-safe.
        s = s.replace("\t", " ").replace("\r", " ").replace("\n", " ")
        out.append(s)
    return "\t".join(out)


def _container_of(node) -> tuple[str, bool]:
    """Innermost meaningful block container of an inline node, + blockquote flag."""
    in_bq = False
    has_list_item = False
    has_heading = False
    cur = node.parent
    while cur is not None:
        t = cur.type
        if t == "block_quote":
            in_bq = True
        elif t == "list_item":
            has_list_item = True
        elif t in ("atx_heading", "setext_heading"):
            has_heading = True
        cur = cur.parent
    if has_list_item:
        return "list_item", in_bq
    if has_heading:
        return "heading", in_bq
    return "paragraph", in_bq


def _code_spans(inline_src: bytes):
    """Yield (start_row, start_byte, content) for each code_span in an inline node.

    start_row/start_byte are relative to inline_src; content is the raw text
    between the code-span delimiters (unstripped, matching the pre-tree-sitter
    line extraction).
    """
    tree = INLINE_PARSER.parse(inline_src)
    stack = [tree.root_node]
    while stack:
        n = stack.pop()
        if n.type == "code_span":
            dels = [c for c in n.children if c.type == "code_span_delimiter"]
            if len(dels) >= 2:
                content = inline_src[dels[0].end_byte : dels[-1].start_byte]
            else:
                # Degenerate span; fall back to the whole node minus backticks.
                content = n.text.strip(b"`")
            yield n.start_point[0], n.start_byte, content.decode("utf-8", "replace")
        stack.extend(n.children)


def _language_of(fcb) -> str:
    for c in fcb.children:
        if c.type == "info_string":
            for gc in c.children:
                if gc.type == "language":
                    return gc.text.decode("utf-8", "replace")
            # No explicit `language` child — use the whole info string.
            return c.text.decode("utf-8", "replace").strip()
    return ""


def extract(path: str, src: bytes, want: set[str], records: list):
    tree = BLOCK_PARSER.parse(src)
    src_lines = src.split(b"\n")
    stack = [tree.root_node]
    while stack:
        node = stack.pop()
        t = node.type

        if t == "inline" and "inline_code" in want:
            container, in_bq = _container_of(node)
            inline_bytes = node.text
            base_row = node.start_point[0]
            for row, sbyte, content in _code_spans(inline_bytes):
                is_bang = 1 if sbyte > 0 and inline_bytes[sbyte - 1 : sbyte] == b"!" else 0
                records.append(
                    (
                        "inline_code",
                        path,
                        base_row + row + 1,
                        container,
                        1 if in_bq else 0,
                        is_bang,
                        content,
                    )
                )

        elif t == "pipe_table_cell" and "inline_code" in want:
            # Table cells hold raw tokens (not an `inline` node), so parse the
            # cell text separately and label the container explicitly.
            cell_bytes = node.text
            base_row = node.start_point[0]
            for row, sbyte, content in _code_spans(cell_bytes):
                is_bang = 1 if sbyte > 0 and cell_bytes[sbyte - 1 : sbyte] == b"!" else 0
                records.append(
                    ("inline_code", path, base_row + row + 1, "table_cell", 0, is_bang, content)
                )
            # Cell has no inline-node children to descend into for code spans.
            continue

        elif t == "fenced_code_block" and ("fence" in want or "fence_line" in want):
            dels = [c for c in node.children if c.type == "fenced_code_block_delimiter"]
            open_row = dels[0].start_point[0] if dels else node.start_point[0]
            if len(dels) >= 2:
                close_row = dels[-1].start_point[0]
            else:
                # Unclosed fence: content runs to the block's last line.
                close_row = node.end_point[0] + 1
            lang = _language_of(node)
            if "fence" in want:
                records.append(("fence", path, open_row + 1, close_row + 1, lang))
            if "fence_line" in want:
                for row in range(open_row + 1, close_row):
                    line_text = src_lines[row].decode("utf-8", "replace") if row < len(src_lines) else ""
                    records.append(("fence_line", path, row + 1, lang, line_text))

        stack.extend(node.children)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Extract markdown structure elements.")
    ap.add_argument("--format", choices=("tsv", "json"), default="tsv")
    ap.add_argument(
        "--types",
        default="inline_code,fence,fence_line",
        help="comma-separated record types to emit",
    )
    ap.add_argument("--files-from", help="read file paths from this file (- = stdin)")
    ap.add_argument("files", nargs="*")
    args = ap.parse_args(argv)

    want = {t.strip() for t in args.types.split(",") if t.strip()}
    paths = list(args.files)
    if args.files_from:
        stream = sys.stdin if args.files_from == "-" else open(args.files_from, encoding="utf-8")
        with stream:
            paths.extend(line.strip() for line in stream if line.strip())

    records: list = []
    for path in paths:
        try:
            with open(path, "rb") as fh:
                src = fh.read()
        except OSError as exc:  # missing/unreadable file: skip, don't abort
            print(f"extract-md-elements: cannot read {path}: {exc}", file=sys.stderr)
            continue
        try:
            extract(path, src, want, records)
        except Exception as exc:  # pragma: no cover - defensive
            print(f"extract-md-elements: parse failed for {path}: {exc}", file=sys.stderr)
            continue

    out = sys.stdout
    if args.format == "json":
        for rec in records:
            kind = rec[0]
            if kind == "inline_code":
                obj = {
                    "type": "inline_code",
                    "file": rec[1],
                    "line": rec[2],
                    "container": rec[3],
                    "in_blockquote": bool(rec[4]),
                    "is_bang": bool(rec[5]),
                    "text": rec[6],
                }
            elif kind == "fence":
                obj = {
                    "type": "fence",
                    "file": rec[1],
                    "start_line": rec[2],
                    "end_line": rec[3],
                    "language": rec[4],
                }
            else:  # fence_line
                obj = {
                    "type": "fence_line",
                    "file": rec[1],
                    "line": rec[2],
                    "language": rec[3],
                    "text": rec[4],
                }
            out.write(json.dumps(obj, ensure_ascii=False) + "\n")
    else:
        for rec in records:
            out.write(_emit_tsv(list(rec)) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

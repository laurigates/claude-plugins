#!/usr/bin/env python3
"""Parse Claude Code session transcripts into normalized friction events.

Reads JSONL files under ~/.claude/projects/*/ (or paths given on argv) and emits
one friction event per line on stdout (or to --out). A friction event looks like:

    {"session": "...", "ts": "...", "kind": "hook_block", "signature": "...",
     "tool": "Bash", "evidence": "first 400 chars of the offending content"}

Kinds:
  hook_block         PreToolUse exit-2 or explicit "blocked by a hook" in content
  tool_error         tool_use_result with is_error: true that is not a hook block
  user_reject        is_error with content matching "user (doesn't|does not) want"
  user_interrupt     user message starts with "[Request interrupted"
  plan_mode          assistant tool_use name == "ExitPlanMode"
  push_to_pr_branch  git push result mentioning an existing open PR / protected branch
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable, Iterator

HOME = Path(os.path.expanduser("~"))
DEFAULT_ROOT = HOME / ".claude" / "projects"

HOOK_BLOCK_RE = re.compile(r"(blocked by (?:a |the )?hook|exit(?:ed)? (?:with )?(?:code )?2|PreToolUse.*blocked)", re.I)
USER_REJECT_RE = re.compile(r"user (?:doesn'?t|does not|did not|refused to|declined)", re.I)
PUSH_PR_RE = re.compile(r"(open pull request|protected branch|pr .*already open|has an open PR|refusing to push)", re.I)
INTERRUPT_RE = re.compile(r"^\[Request interrupted")
SECRET_RE = re.compile(r"\b[A-Za-z0-9_\-]{32,}\b")

EDIT_VERB_RE = re.compile(
    r"\b(add|addition|fix|change|remove|delete|drop|rename|refactor|"
    r"implement|write|create|build|update|migrate|modify|patch|"
    r"replace|rewrite|port|upgrade|downgrade|install|configure|"
    r"set\s+up|hook\s+up|wire\s+up)\b",
    re.I,
)
QA_PREFIX_RE = re.compile(
    r"^\s*(?:how|what|why|does|do|did|can|could|is|are|was|were|"
    r"should|shall|when|where|which|who|whom|whose)\b",
    re.I,
)
QA_CONTAINS_RE = re.compile(
    r"\b(explain|describe|tell me about|clarify|walk me through)\b",
    re.I,
)


def redact(text: str) -> str:
    """Strip $HOME paths and token-looking strings."""
    if not text:
        return text
    text = text.replace(str(HOME), "$HOME")
    text = SECRET_RE.sub(lambda m: m.group(0)[:6] + "…" if len(m.group(0)) > 40 else m.group(0), text)
    return text


def first_text(content) -> str:
    """Extract first text content from a message.content (string or list)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict):
                if item.get("type") == "text" and "text" in item:
                    return item["text"]
                if item.get("type") == "tool_result":
                    inner = item.get("content")
                    if isinstance(inner, str):
                        return inner
                    if isinstance(inner, list):
                        for sub in inner:
                            if isinstance(sub, dict) and sub.get("type") == "text":
                                return sub.get("text", "")
    return ""


def canonical_signature(kind: str, tool: str, evidence: str) -> str:
    """Collapse similar-looking evidence into a stable cluster key."""
    ev = evidence.lower()
    if kind == "hook_block":
        for needle, sig in [
            ("branch-protection", "hook:branch-protection"),
            ("pr metadata", "hook:pr-metadata"),
            ("conventional commit", "hook:conventional-commit"),
            ("gitleaks", "hook:gitleaks"),
            ("pre-commit", "hook:pre-commit"),
        ]:
            if needle in ev:
                return sig
        return "hook:unclassified"
    if kind == "push_to_pr_branch":
        return "push:branch-has-open-pr"
    if kind == "plan_mode":
        return "plan:entered-plan-mode"
    if kind == "plan_mode_legitimate":
        return "plan:legitimate-change-request"
    if kind == "user_reject":
        return f"reject:{tool.lower()}"
    if kind == "user_interrupt":
        return "interrupt:user"
    if kind == "tool_error":
        m = re.search(r"\b(ENOENT|EACCES|not found|permission denied|timeout|connection refused)\b", ev, re.I)
        if m:
            return f"error:{tool.lower()}:{m.group(1).lower().replace(' ', '-')}"
        return f"error:{tool.lower()}"
    return f"{kind}:{tool.lower()}"


def iter_transcripts(roots: list[Path], since: datetime | None) -> Iterator[Path]:
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.jsonl")):
            try:
                mtime = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
            except OSError:
                continue
            if since and mtime < since:
                continue
            yield path


def parse_since(spec: str) -> datetime | None:
    if not spec:
        return None
    if spec.endswith("d"):
        return datetime.now(tz=timezone.utc) - timedelta(days=int(spec[:-1]))
    if spec.endswith("h"):
        return datetime.now(tz=timezone.utc) - timedelta(hours=int(spec[:-1]))
    return datetime.fromisoformat(spec.replace("Z", "+00:00"))


def iter_jsonl(path: Path) -> Iterator[dict]:
    with path.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def build_tool_index(path: Path) -> dict[str, str]:
    """Map tool_use_id -> tool_name from assistant records.

    In Claude Code JSONL transcripts, the tool name only lives on the
    assistant's tool_use block. The user record carrying the tool_result
    references it via tool_use_id. Without this index, every user-side
    error event would report tool "?".
    """
    index: dict[str, str] = {}
    for rec in iter_jsonl(path):
        if rec.get("type") != "assistant":
            continue
        for item in rec.get("message", {}).get("content", []) or []:
            if isinstance(item, dict) and item.get("type") == "tool_use":
                tool_id = item.get("id")
                tool_name = item.get("name")
                if tool_id and tool_name:
                    index[tool_id] = tool_name
    return index


def is_user_prompt(rec: dict) -> bool:
    """True if a user record is a genuine prompt (not a tool_result wrapper)."""
    if rec.get("type") != "user":
        return False
    content = rec.get("message", {}).get("content")
    if isinstance(content, str):
        return bool(content.strip()) and not INTERRUPT_RE.match(content)
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and item.get("type") == "tool_result":
                return False
        text = first_text(content)
        return bool(text.strip()) and not INTERRUPT_RE.match(text)
    return False


def classify_plan_mode(prompt_text: str) -> str:
    """Return 'plan_mode' (conceptual Q&A friction) or 'plan_mode_legitimate'.

    Only treat plan-mode entry as friction when the preceding user prompt
    looks like a question with no edit-verbs. Otherwise plan mode is a
    legitimate response to a change request.
    """
    if not prompt_text:
        return "plan_mode_legitimate"
    if EDIT_VERB_RE.search(prompt_text):
        return "plan_mode_legitimate"
    if QA_PREFIX_RE.match(prompt_text) or QA_CONTAINS_RE.search(prompt_text):
        return "plan_mode"
    return "plan_mode_legitimate"


def lookup_tool_name(rec: dict, index: dict[str, str]) -> str:
    """Resolve the tool name for a user tool_result record."""
    content = rec.get("message", {}).get("content")
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and item.get("type") == "tool_result":
                tool_id = item.get("tool_use_id")
                if tool_id and tool_id in index:
                    return index[tool_id]
    for key in ("toolUseID", "tool_use_id"):
        tool_id = rec.get(key)
        if tool_id and tool_id in index:
            return index[tool_id]
    tur = rec.get("toolUseResult") or {}
    if isinstance(tur, dict):
        tool_id = tur.get("tool_use_id") or tur.get("toolUseID")
        if tool_id and tool_id in index:
            return index[tool_id]
        fallback = tur.get("toolName")
        if fallback:
            return fallback
    return rec.get("toolUseName") or "?"


def extract_frictions(path: Path) -> Iterator[dict]:
    session = path.stem
    tool_index = build_tool_index(path)
    last_user_prompt = ""
    for rec in iter_jsonl(path):
        rtype = rec.get("type")
        ts = rec.get("timestamp", "")

        if is_user_prompt(rec):
            last_user_prompt = first_text(rec.get("message", {}).get("content")) or ""

        # User interrupt markers (sit in user messages)
        if rtype == "user":
            msg = rec.get("message", {})
            content = msg.get("content")
            text = first_text(content)
            if text and INTERRUPT_RE.match(text):
                yield {
                    "session": session, "ts": ts, "kind": "user_interrupt",
                    "tool": "-", "signature": "interrupt:user",
                    "evidence": redact(text[:400]),
                }
                continue
            # Tool results embedded in user messages carry is_error
            tur = rec.get("toolUseResult") or {}
            if not isinstance(tur, dict):
                tur = {"content": tur}
            is_error = tur.get("is_error") or (isinstance(content, list) and any(
                isinstance(i, dict) and i.get("type") == "tool_result" and i.get("is_error")
                for i in content
            ))
            if is_error:
                tool = lookup_tool_name(rec, tool_index)
                body = text or json.dumps(tur)[:400]
                if HOOK_BLOCK_RE.search(body):
                    kind = "hook_block"
                elif USER_REJECT_RE.search(body):
                    kind = "user_reject"
                elif tool == "Bash" and "git push" in body.lower() and PUSH_PR_RE.search(body):
                    kind = "push_to_pr_branch"
                else:
                    kind = "tool_error"
                yield {
                    "session": session, "ts": ts, "kind": kind,
                    "tool": tool,
                    "signature": canonical_signature(kind, tool, body),
                    "evidence": redact(body[:400]),
                }

        elif rtype == "assistant":
            msg = rec.get("message", {})
            for item in msg.get("content", []) or []:
                if isinstance(item, dict) and item.get("type") == "tool_use":
                    if item.get("name") == "ExitPlanMode":
                        plan = ""
                        inp = item.get("input") or {}
                        if isinstance(inp, dict):
                            plan = inp.get("plan", "")
                        kind = classify_plan_mode(last_user_prompt)
                        if kind == "plan_mode":
                            yield {
                                "session": session, "ts": ts, "kind": kind,
                                "tool": "ExitPlanMode",
                                "signature": canonical_signature(kind, "ExitPlanMode", plan),
                                "evidence": redact(str(plan)[:400]),
                            }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="7d", help="Time window (e.g. 7d, 24h, ISO timestamp)")
    ap.add_argument("--root", action="append", default=[],
                    help="Transcript root (repeatable). Defaults to ~/.claude/projects")
    ap.add_argument("--out", default="-", help="Output path; '-' for stdout")
    args = ap.parse_args()

    roots = [Path(r) for r in args.root] or [DEFAULT_ROOT]
    since = parse_since(args.since)
    out = sys.stdout if args.out == "-" else open(args.out, "w", encoding="utf-8")

    total_files = 0
    total_events = 0
    try:
        for path in iter_transcripts(roots, since):
            total_files += 1
            for ev in extract_frictions(path):
                out.write(json.dumps(ev, ensure_ascii=False) + "\n")
                total_events += 1
    finally:
        if out is not sys.stdout:
            out.close()

    sys.stderr.write(f"parsed {total_files} transcript(s), emitted {total_events} friction event(s)\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

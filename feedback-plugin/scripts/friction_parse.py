#!/usr/bin/env python3
"""Parse Claude Code session transcripts into normalized friction events.

Reads JSONL files under ~/.claude/projects/*/ (or paths given on argv) and emits
one friction event per line on stdout (or to --out). A friction event looks like:

    {"session": "...", "ts": "...", "kind": "hook_block", "signature": "...",
     "tool": "Bash", "evidence": "first EVIDENCE_MAX_CHARS of the offending content"}

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
from typing import Iterator

HOME = Path(os.path.expanduser("~"))
DEFAULT_ROOT = HOME / ".claude" / "projects"

# How much of an event's content survives into `evidence`.
#
# This is a MEASUREMENT budget, not a display budget: the marker that
# distinguishes one hook-message variant from another routinely sits in the
# message TAIL, past the harness's own
# "PreToolUse:Bash hook error: [bash <abs-path>/<hook>.sh]: " wrapper (~85-150
# chars before the hook's first word). At the former 400 the post-#2148
# head/tail block message was cut mid-way through "This fires only when the
# read is the WHOLE command", so a reader classifying events off parser output
# could not tell the current message from its pre-#2148 ancestor. In the W33
# window that manufactured 12 phantom "legacy" hook blocks out of 27 (a naive
# read gave 15 post-fix / 12 legacy; recovering the same events from the raw
# transcripts corrected it to 27 / 0).
EVIDENCE_MAX_CHARS = 1200

# A hook block is identified by the harness's own wrapper prose, never by a
# bare "exit code 2": that phrase appears verbatim in ordinary tool output
# (e.g. `ugrep: ... exit code 2` on a missing file), so matching it anywhere
# misclassified unrelated tool errors as hook blocks (27% of W32 hook_block
# events were not hook blocks at all).
HOOK_BLOCK_RE = re.compile(
    r"(blocked by (?:a |the )?hook|PreToolUse[^\n]*hook error|PreToolUse.*blocked)",
    re.I,
)
USER_REJECT_RE = re.compile(
    r"user (?:doesn'?t|does not|did not|refused to|declined)", re.I
)
PUSH_PR_RE = re.compile(
    r"(open pull request|protected branch|pr .*already open|has an open PR|refusing to push)",
    re.I,
)
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
    text = SECRET_RE.sub(
        lambda m: m.group(0)[:6] + "…" if len(m.group(0)) > 40 else m.group(0), text
    )
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
        # Sub-classify bash-antipatterns hook output. Match both the new
        # BLOCKED: substitution-format messages introduced in PR #1378 and
        # the older REMINDER: prose form for the same patterns, so the
        # signature is stable across the format transition. The hook
        # script name appears in the transcript record because the
        # harness wraps the message as
        # "PreToolUse:Bash hook error: [bash .../bash-antipatterns.sh]: ...".
        # Substring matches are intentionally narrow (the exact prose the
        # hook emits) to avoid false positives from incidental "blocked"
        # phrasing in unrelated content.
        if "bash-antipatterns" in ev:
            if "blocked: 'grep" in ev or "blocked: 'rg" in ev:
                return "hook:bash-antipatterns:grep-rg"
            if "blocked: 'find" in ev:
                return "hook:bash-antipatterns:find"
            if (
                "blocked: 'cat" in ev
                or "blocked: 'head" in ev
                or "blocked: 'tail" in ev
            ):
                return "hook:bash-antipatterns:cat-head-tail"
            # git && chaining still uses REMINDER: prose, not BLOCKED:.
            if "chaining git commands" in ev:
                return "hook:bash-antipatterns:git-chain"
            # Forward-compatible: future substitution-format upgrades
            # (W22 watch-list candidates — see ~/.claude/rules/friction/
            # 2026-W22-frictions.md "Other watch-list patterns").
            if "ls" in ev and (
                "glob tool for pattern-based file listing" in ev or "blocked: 'ls" in ev
            ):
                return "hook:bash-antipatterns:ls-glob"
            if "this command has " in ev and " pipes" in ev:
                return "hook:bash-antipatterns:long-pipeline"
            if "taskoutput tool" in ev:
                return "hook:bash-antipatterns:taskoutput"
            # REMINDER-format detectors. Every check above keys on the
            # BLOCKED: substitution format or on prose unique to one older
            # detector, so this table is appended rather than interleaved:
            # an event that already matched above still matches above, and
            # the ONLY events this table can capture are ones that used to
            # fall through to `:other`. That containment is structural, and
            # it is what the dual-parser identical-input check asserts.
            #
            # Why split at all (2026-W35): merged, `:other` was 74 events /
            # 45 sessions / 42.9% prevalence / 42.2% same-session repeat --
            # the second-largest cluster in the corpus and up from 46 ev /
            # 27.2% in W34. Dissolved, no detector exceeds 15.2% repeat
            # except `awk` (50.0%, but n=2 sessions). The 42.2% was an
            # aggregation artifact, so citing it as a teaching-failure
            # signal for any single detector would have been wrong -- and
            # while the eight shared one key, no per-detector escalation
            # gate could be written at all. See issue #2420.
            #
            # ORDERING. Each needle carries the detector's own quoted token
            # rather than the shared lead-in, because three pairs share a
            # phrase and a loose test placed first swallows its neighbour
            # silently (the shape PR #2421 hit):
            #   * "use the edit tool instead of"  -> 'sed -i' AND 'awk'
            #   * "use the write tool instead of" -> 'echo/printf > file'
            #     AND 'cat > file' (the cat-write detector, which is NOT in
            #     this table and must keep falling through to `:other`)
            # test_friction_parse.py pins both the split and the ordering.
            for needle, detector in (
                # Quoted-token needles first: the narrowest tests, and the
                # ones whose shared lead-in would otherwise cross-match.
                ("instead of 'echo/printf > file'", "echo-write"),
                ("instead of 'sed -i'", "sed-inplace"),
                ("instead of 'awk'", "awk-edit"),
                # Unshared prose; order among these is not load-bearing.
                ("'timeout' command is usually unnecessary", "timeout"),
                ("avoid broad staging commands", "git-add-broad"),
                ("use heredoc directly in git commit", "commit-heredoc"),
                ("parsing test output with grep chains", "test-grep-chain"),
                ("piping network content directly to a shell", "net-pipe-shell"),
            ):
                if needle in ev:
                    return f"hook:bash-antipatterns:{detector}"
            return "hook:bash-antipatterns:other"
        # Other hook scripts produce identifiable script-name substrings
        # via the same "[bash .../<name>.sh]" wrapper. Match those first
        # so the legacy needle table doesn't false-positive on hook prose
        # that mentions a sibling concept (e.g. a branch-protection
        # message that references "pr metadata" in passing).
        if "secret-protection" in ev:
            return "hook:secret-protection"
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
        # The Claude Code harness's own worktree-isolation guard, split out
        # ahead of the generic error:<tool> fallback. It is emitted by the
        # binary (verified present in 2.1.231-2.1.233), not by any hook here,
        # so it never carries the PreToolUse wrapper HOOK_BLOCK_RE keys on and
        # lands in tool_error. In the W34 window it was 176 events: 52.0% of
        # the error:bash bucket and 31.8% of ALL friction, which made
        # error:bash appear to escalate on both of W33's pre-registered axes
        # (85.1% prevalence / 64.9% repeat) while the residual was flat
        # (64.9% / 52.7% vs W33's 65.6% / 52.5%). Left merged, it hides every
        # other cause in the bucket.
        # See ~/.claude/friction-reports/2026-W34-frictions.md (§Signal A,
        # §Signal E, PR-READY 2).
        #
        # The signature stays tool-keyed rather than hardcoding `bash`: the
        # guard also fires on Monitor's shell argument (9 of the 176), and
        # flattening those into an error:bash:* key would misattribute them.
        #
        # The variants are separated because they have DIFFERENT OWNERS, and
        # the sub-counts are the whole reason to split: only the first class is
        # an upstream false positive.
        if "isolated in the worktree" in ev:
            # Order matters: the worktree-gone message also says "shared
            # checkout" (naming the parent as the recovery target), so it has
            # to be tested before the cross-repo needle.
            if "no longer exists" in ev:
                # The worktree was removed while its agent was still live.
                # Owner: worktree-cleanup gating (.claude/rules/
                # agent-coworker-detection.md "never force-remove worktrees
                # you don't own").
                variant = "worktree-gone"
            elif "shared checkout" in ev:
                # The command demonstrably targeted another checkout -- `cd`
                # into a sibling repo, `git -C <parent>`, or a cwd that had
                # already escaped. Owner: agent dispatch/briefing (issue
                # #2371's shape).
                variant = "cross-repo"
            elif "verify" in ev or "verified" in ev:
                # The harness could not PROVE the command stays inside the
                # worktree, so it refused a command that was usually fine:
                # "too complex to verify" (128), plus the eval / COMPLETE /
                # env / xargs-stdin phrasings (5). 71.0% of these contain no
                # `git` at all and 84.7% no git write, so shell complexity is
                # standing in for git targeting. Owner: upstream Claude Code.
                variant = "unverifiable"
            else:
                # Forward-compatible: a phrasing this table does not know
                # stays visible instead of being absorbed into a sibling
                # variant, mirroring hook:bash-antipatterns:other above.
                variant = "other"
            return f"error:{tool.lower()}:worktree-isolation:{variant}"
        # "not found" is anchored to the shell/PATH forms only. A bare
        # \bnot found\b matched any payload that merely reported something
        # absent (kubectl `pods "x" not found`, Blender `enum "X" not found`),
        # so 27 of 28 W32 `error:bash:not-found` events were false positives.
        m = re.search(
            r"(\bENOENT\b|\bEACCES\b|command not found|: not found"
            r"|\bpermission denied\b|\btimeout\b|\bconnection refused\b)",
            ev,
            re.I,
        )
        if m:
            token = m.group(1).lower().lstrip(": ")
            # Both shell forms collapse to the historical `not-found` token so
            # the signature stays comparable across weeks.
            if "not found" in token:
                token = "not found"
            return f"error:{tool.lower()}:{token.replace(' ', '-')}"
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
                    "session": session,
                    "ts": ts,
                    "kind": "user_interrupt",
                    "tool": "-",
                    "signature": "interrupt:user",
                    "evidence": redact(text[:EVIDENCE_MAX_CHARS]),
                }
                continue
            # Tool results embedded in user messages carry is_error
            tur = rec.get("toolUseResult") or {}
            if not isinstance(tur, dict):
                tur = {"content": tur}
            is_error = tur.get("is_error") or (
                isinstance(content, list)
                and any(
                    isinstance(i, dict)
                    and i.get("type") == "tool_result"
                    and i.get("is_error")
                    for i in content
                )
            )
            if is_error:
                tool = lookup_tool_name(rec, tool_index)
                body = text or json.dumps(tur)[:EVIDENCE_MAX_CHARS]
                if HOOK_BLOCK_RE.search(body):
                    kind = "hook_block"
                elif USER_REJECT_RE.search(body):
                    kind = "user_reject"
                elif (
                    tool == "Bash"
                    and "git push" in body.lower()
                    and PUSH_PR_RE.search(body)
                ):
                    kind = "push_to_pr_branch"
                else:
                    kind = "tool_error"
                yield {
                    "session": session,
                    "ts": ts,
                    "kind": kind,
                    "tool": tool,
                    "signature": canonical_signature(kind, tool, body),
                    "evidence": redact(body[:EVIDENCE_MAX_CHARS]),
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
                                "session": session,
                                "ts": ts,
                                "kind": kind,
                                "tool": "ExitPlanMode",
                                "signature": canonical_signature(
                                    kind, "ExitPlanMode", plan
                                ),
                                "evidence": redact(str(plan)[:EVIDENCE_MAX_CHARS]),
                            }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--since", default="7d", help="Time window (e.g. 7d, 24h, ISO timestamp)"
    )
    ap.add_argument(
        "--root",
        action="append",
        default=[],
        help="Transcript root (repeatable). Defaults to ~/.claude/projects",
    )
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

    sys.stderr.write(
        f"parsed {total_files} transcript(s), emitted {total_events} friction event(s)\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Parse a headless-harness event stream into a harness-neutral trace.json.

This is the ONLY component of evaluate-plugin that knows the Claude Code
``stream-json`` event shapes (design decision D6). Everything downstream --
``grade_deterministic.py`` trace checks, ``rollout_headless.sh``'s stdout
block, the matrix report -- reads ``trace.json`` and never the raw stream, so a
second harness (pi, OpenCode) only needs a second parser branch here.

Input: the JSONL written by
``claude -p --output-format stream-json --verbose`` (one event per line).

Usage:
  parse_trace.py --input <transcript.jsonl|-> [--harness claude-code]
                 [--output trace.json] [--workdir DIR]

  --input     path to the stream (``-`` reads stdin)
  --harness   stream dialect; only ``claude-code`` is implemented
  --output    write trace.json here (default: JSON to stdout). When given, a
              ``=== PARSE TRACE ===`` KEY=VALUE block is printed on stdout;
              without it the block goes to stderr so stdout stays pure JSON.
  --workdir   directory that ``files_written[].path`` is made relative to;
              defaults to the ``cwd`` reported by the init event. Paths outside
              it stay absolute.

trace.json (version 1):
  identity   harness, harness_version, model_id, session_id, cwd,
             permission_mode
  catalogue  plugins_loaded[], skills_available[]   (skills_available is the
             init event's ``skills`` verbatim; the CLI lists only
             user-invocable skills there, so a user-invocable:false skill
             the model can still invoke is absent -- diagnostic only)
  activity   skills_invoked[{skill,args,turn,tool_use_id,denied,is_error}]
             tool_calls[{turn,tool_use_id,name,input_summary,input,is_error,
                         denied}]   (each input value capped at 2000 chars)
             bash_commands[{turn,command,is_error,denied}]
             files_written[{path,tool}]   (successful writes only)
             permission_denied[{turn,tool_name,tool_use_id,message}]
             hooks_fired[{turn,hook_id,hook_name,hook_event,outcome,exit_code}]
  totals     num_turns, cost_usd, usage, duration_ms, duration_api_ms
  outcome    final_text, stop_reason, is_error,
             parse_warnings{malformed_lines,missing_init,missing_result}

Turn numbering: a turn is one top-level assistant API message (a distinct
``message.id`` with ``parent_tool_use_id`` null), numbered from 1 -- the same
unit the result event's ``num_turns`` counts. Events before the first assistant
message (SessionStart hooks) are turn 0. Sub-agent messages (non-null
``parent_tool_use_id``) inherit the enclosing top-level turn.

``is_error`` on a tool call is the tool_result's flag; ``null`` means no
tool_result was seen (a truncated stream). ``denied`` is true when a
``system/permission_denied`` event, a result ``permission_denials`` entry, or a
``user-rejected`` tool_result_meta names the call.

stop_reason: completed | max_turns | budget | error | incomplete (no result
event). A stream with no result event also reports ``is_error: true``.

Exit codes: 0 when parsed (even partially: malformed lines, missing init or
result are recorded in parse_warnings); 2 when the input is empty, unreadable,
or contains no parseable event.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any

TRACE_VERSION = 1
INPUT_VALUE_CAP = 2000
SUMMARY_CAP = 200

# Tools whose successful call writes a file, and the input key holding the path.
WRITE_TOOLS = {
    "Write": "file_path",
    "Edit": "file_path",
    "MultiEdit": "file_path",
    "NotebookEdit": "notebook_path",
}

# Preferred input key for the one-line input_summary, per tool.
SUMMARY_KEYS = {
    "Bash": "command",
    "Skill": "skill",
    "Read": "file_path",
    "Write": "file_path",
    "Edit": "file_path",
    "MultiEdit": "file_path",
    "NotebookEdit": "notebook_path",
    "Glob": "pattern",
    "Grep": "pattern",
    "WebFetch": "url",
    "WebSearch": "query",
    "Task": "description",
    "Agent": "description",
}


def _one_line(text: str, cap: int = SUMMARY_CAP) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    return text if len(text) <= cap else text[: cap - 3] + "..."


def _cap_value(value: Any) -> Any:
    """Cap one tool-input value at INPUT_VALUE_CAP characters."""
    if isinstance(value, str):
        return value[:INPUT_VALUE_CAP]
    if value is None or isinstance(value, (bool, int, float)):
        return value
    dumped = json.dumps(value, ensure_ascii=False)
    if len(dumped) <= INPUT_VALUE_CAP:
        return value
    return dumped[:INPUT_VALUE_CAP]


def _cap_input(inp: Any) -> Any:
    if isinstance(inp, dict):
        return {k: _cap_value(v) for k, v in inp.items()}
    return _cap_value(inp)


def _summarise(name: str, inp: Any) -> str:
    if not isinstance(inp, dict):
        return _one_line(json.dumps(inp, ensure_ascii=False)) if inp is not None else ""
    key = SUMMARY_KEYS.get(name)
    if key and isinstance(inp.get(key), str):
        return _one_line(inp[key])
    for v in inp.values():
        if isinstance(v, str) and v:
            return _one_line(v)
    return _one_line(json.dumps(inp, ensure_ascii=False)) if inp else ""


def _relativize(path: str, bases: list[str]) -> str:
    if not path or not os.path.isabs(path):
        return path
    norm = os.path.normpath(path)
    candidates = [norm]
    real = os.path.realpath(norm)
    if real != norm:
        candidates.append(real)
    for base in bases:
        for cand in candidates:
            try:
                if os.path.commonpath([cand, base]) == base:
                    rel = os.path.relpath(cand, base)
                    return rel
            except ValueError:
                continue
    return path


def _stop_reason(result: dict | None) -> str:
    if result is None:
        return "incomplete"
    subtype = str(result.get("subtype") or "")
    terminal = str(result.get("terminal_reason") or "")
    marker = f"{subtype} {terminal}".lower()
    if "max_turns" in marker:
        return "max_turns"
    if "budget" in marker:
        return "budget"
    if result.get("is_error") or subtype.startswith("error"):
        return "error"
    return "completed"


def read_events(stream) -> tuple[list[dict], int, int]:
    """Return (events, malformed_line_count, non_blank_line_count)."""
    events: list[dict] = []
    malformed = 0
    non_blank = 0
    for raw in stream:
        line = raw.strip()
        if not line:
            continue
        non_blank += 1
        try:
            obj = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            malformed += 1
            continue
        if not isinstance(obj, dict):
            malformed += 1
            continue
        events.append(obj)
    return events, malformed, non_blank


def parse_claude_code(events: list[dict], malformed: int, workdir: str | None) -> dict:
    init: dict | None = None
    result: dict | None = None
    session_id = None
    model_from_messages = None

    turn = 0
    seen_message_ids: set[str] = set()

    calls: list[dict] = []  # ordered tool_use records (internal)
    calls_by_id: dict[str, dict] = {}
    denied_ids: set[str] = set()
    permission_denied: list[dict] = []
    hooks: list[dict] = []
    hooks_by_id: dict[str, dict] = {}
    last_text_turn = -1
    last_text_parts: list[str] = []

    for ev in events:
        etype = ev.get("type")
        if session_id is None and isinstance(ev.get("session_id"), str):
            session_id = ev["session_id"]

        if etype == "system":
            sub = ev.get("subtype")
            if sub == "init" and init is None:
                init = ev
                if isinstance(ev.get("session_id"), str):
                    session_id = ev["session_id"]
            elif sub == "permission_denied":
                tid = ev.get("tool_use_id")
                if tid:
                    denied_ids.add(tid)
                permission_denied.append(
                    {
                        "turn": turn,
                        "tool_name": ev.get("tool_name"),
                        "tool_use_id": tid,
                        "message": ev.get("message") or ev.get("decision_reason"),
                    }
                )
            elif sub == "hook_started":
                hid = ev.get("hook_id")
                rec = {
                    "turn": turn,
                    "hook_id": hid,
                    "hook_name": ev.get("hook_name"),
                    "hook_event": ev.get("hook_event"),
                    "outcome": None,
                    "exit_code": None,
                }
                hooks.append(rec)
                if hid:
                    hooks_by_id[hid] = rec
            elif sub == "hook_response":
                hid = ev.get("hook_id")
                rec = hooks_by_id.get(hid) if hid else None
                if rec is None:
                    rec = {
                        "turn": turn,
                        "hook_id": hid,
                        "hook_name": ev.get("hook_name"),
                        "hook_event": ev.get("hook_event"),
                        "outcome": None,
                        "exit_code": None,
                    }
                    hooks.append(rec)
                    if hid:
                        hooks_by_id[hid] = rec
                rec["outcome"] = ev.get("outcome")
                rec["exit_code"] = ev.get("exit_code")

        elif etype == "assistant":
            msg = ev.get("message") or {}
            if not isinstance(msg, dict):
                continue
            top_level = ev.get("parent_tool_use_id") is None
            mid = msg.get("id")
            if top_level:
                if mid is None or mid not in seen_message_ids:
                    turn += 1
                    if mid is not None:
                        seen_message_ids.add(mid)
                if model_from_messages is None and isinstance(msg.get("model"), str):
                    model_from_messages = msg["model"]
            for block in msg.get("content") or []:
                if not isinstance(block, dict):
                    continue
                btype = block.get("type")
                if btype == "tool_use":
                    tid = block.get("id")
                    rec = {
                        "turn": turn,
                        "tool_use_id": tid,
                        "name": block.get("name"),
                        "input": block.get("input")
                        if block.get("input") is not None
                        else {},
                        "is_error": None,
                        "denied": False,
                    }
                    calls.append(rec)
                    if tid:
                        calls_by_id[tid] = rec
                elif btype == "text" and top_level:
                    text = block.get("text") or ""
                    if not text:
                        continue
                    if turn != last_text_turn:
                        last_text_turn = turn
                        last_text_parts = []
                    last_text_parts.append(text)

        elif etype == "user":
            msg = ev.get("message") or {}
            content = msg.get("content") if isinstance(msg, dict) else None
            if isinstance(content, list):
                for block in content:
                    if (
                        not isinstance(block, dict)
                        or block.get("type") != "tool_result"
                    ):
                        continue
                    rec = calls_by_id.get(block.get("tool_use_id"))
                    if rec is not None:
                        rec["is_error"] = bool(block.get("is_error", False))
            for meta in ev.get("tool_result_meta") or []:
                if (
                    isinstance(meta, dict)
                    and meta.get("non_execution_kind") == "user-rejected"
                ):
                    if meta.get("id"):
                        denied_ids.add(meta["id"])

        elif etype == "result":
            result = ev
            if isinstance(ev.get("session_id"), str) and session_id is None:
                session_id = ev["session_id"]

    # Result-level denials cover streams whose system events were dropped.
    if result is not None:
        logged = {d["tool_use_id"] for d in permission_denied if d.get("tool_use_id")}
        for d in result.get("permission_denials") or []:
            if not isinstance(d, dict):
                continue
            tid = d.get("tool_use_id")
            if tid:
                denied_ids.add(tid)
            if tid and tid in logged:
                continue
            rec = calls_by_id.get(tid)
            permission_denied.append(
                {
                    "turn": rec["turn"] if rec else None,
                    "tool_name": d.get("tool_name"),
                    "tool_use_id": tid,
                    "message": None,
                }
            )

    for rec in calls:
        if rec["tool_use_id"] in denied_ids:
            rec["denied"] = True

    # ---- derived activity views -------------------------------------------
    bases: list[str] = []
    base = workdir or (init or {}).get("cwd")
    if base:
        for b in (os.path.normpath(os.path.abspath(base)), os.path.realpath(base)):
            if b not in bases:
                bases.append(b)

    tool_calls, skills_invoked, bash_commands, files_written = [], [], [], []
    seen_writes: set[tuple[str, str]] = set()
    for rec in calls:
        name = rec["name"]
        inp = rec["input"]
        tool_calls.append(
            {
                "turn": rec["turn"],
                "tool_use_id": rec["tool_use_id"],
                "name": name,
                "input_summary": _summarise(name, inp),
                "input": _cap_input(inp),
                "is_error": rec["is_error"],
                "denied": rec["denied"],
            }
        )
        if not isinstance(inp, dict):
            continue
        if name == "Skill":
            skills_invoked.append(
                {
                    "skill": inp.get("skill"),
                    "args": inp.get("args"),
                    "turn": rec["turn"],
                    "tool_use_id": rec["tool_use_id"],
                    "denied": rec["denied"],
                    "is_error": rec["is_error"],
                }
            )
        elif name == "Bash":
            bash_commands.append(
                {
                    "turn": rec["turn"],
                    "command": inp.get("command"),
                    "is_error": rec["is_error"],
                    "denied": rec["denied"],
                }
            )
        if name in WRITE_TOOLS and not rec["denied"] and rec["is_error"] is False:
            path = inp.get(WRITE_TOOLS[name])
            if isinstance(path, str) and path:
                rel = _relativize(path, bases)
                key = (rel, name)
                if key not in seen_writes:
                    seen_writes.add(key)
                    files_written.append({"path": rel, "tool": name})

    # ---- identity / totals / outcome --------------------------------------
    init = init or {}
    res = result or {}
    model_id = init.get("model") or model_from_messages
    if not model_id and isinstance(res.get("modelUsage"), dict) and res["modelUsage"]:
        model_id = next(iter(res["modelUsage"]))

    plugins = []
    for p in init.get("plugins") or []:
        if isinstance(p, dict):
            plugins.append(
                {k: p.get(k) for k in ("name", "path", "source", "version") if k in p}
            )
        elif isinstance(p, str):
            plugins.append({"name": p})

    final_text = res.get("result") if isinstance(res.get("result"), str) else None
    if not final_text:
        final_text = "\n\n".join(last_text_parts) if last_text_parts else ""

    num_turns = res.get("num_turns")
    if not isinstance(num_turns, int):
        num_turns = turn

    return {
        "version": TRACE_VERSION,
        "harness": "claude-code",
        "harness_version": init.get("claude_code_version"),
        "model_id": model_id,
        "session_id": session_id,
        "cwd": init.get("cwd"),
        "permission_mode": init.get("permissionMode"),
        "plugins_loaded": plugins,
        "skills_available": [
            s for s in (init.get("skills") or []) if isinstance(s, str)
        ],
        "skills_invoked": skills_invoked,
        "tool_calls": tool_calls,
        "bash_commands": bash_commands,
        "files_written": files_written,
        "permission_denied": permission_denied,
        "hooks_fired": hooks,
        "num_turns": num_turns,
        "cost_usd": res.get("total_cost_usd"),
        "usage": res.get("usage") if isinstance(res.get("usage"), dict) else None,
        "duration_ms": res.get("duration_ms"),
        "duration_api_ms": res.get("duration_api_ms"),
        "final_text": final_text,
        "stop_reason": _stop_reason(result),
        "is_error": bool(res.get("is_error")) if result is not None else True,
        "parse_warnings": {
            "malformed_lines": malformed,
            "missing_init": not bool(init),
            "missing_result": result is None,
        },
    }


PARSERS = {"claude-code": parse_claude_code}


def _emit_block(out, fields: dict, status: str, issues: list[tuple[str, str]]) -> None:
    print("=== PARSE TRACE ===", file=out)
    for k, v in fields.items():
        print(f"{k}={v}", file=out)
    print(f"STATUS={status}", file=out)
    if status != "OK" and issues:
        reason = f"{issues[0][0]}: {issues[0][1]}"
        reason = _one_line(reason, 180)
        if len(issues) > 1:
            reason += f" (+{len(issues) - 1} more)"
        print(f"REASON={reason}", file=out)
    print(f"ISSUE_COUNT={len(issues)}", file=out)
    if issues:
        print("ISSUES:", file=out)
        sev = "ERROR" if status == "ERROR" else "WARN"
        for typ, msg in issues:
            print(f"  - SEVERITY={sev} TYPE={typ} MSG={msg}", file=out)
    print("=== END PARSE TRACE ===", file=out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument(
        "--input", required=True, help="stream-json JSONL path, or - for stdin"
    )
    ap.add_argument("--harness", default="claude-code", choices=sorted(PARSERS))
    ap.add_argument("--output", help="write trace.json here (default: stdout)")
    ap.add_argument("--workdir", help="relativize files_written paths against this dir")
    args = ap.parse_args(argv)

    block_out = sys.stdout if args.output else sys.stderr

    def fail(typ: str, msg: str) -> int:
        _emit_block(block_out, {"INPUT": args.input}, "ERROR", [(typ, msg)])
        return 2

    try:
        if args.input == "-":
            events, malformed, non_blank = read_events(sys.stdin)
        else:
            with open(args.input, encoding="utf-8", errors="replace") as fh:
                events, malformed, non_blank = read_events(fh)
    except OSError as exc:
        return fail("unreadable_input", f"{args.input}: {exc.strerror or exc}")

    if non_blank == 0:
        return fail("empty_input", f"{args.input} has no events")
    if not events:
        return fail("no_parseable_events", f"all {malformed} line(s) malformed")

    trace = PARSERS[args.harness](events, malformed, args.workdir)
    payload = json.dumps(trace, indent=2, ensure_ascii=False) + "\n"

    if args.output:
        try:
            with open(args.output, "w", encoding="utf-8") as fh:
                fh.write(payload)
        except OSError as exc:
            return fail("unwritable_output", f"{args.output}: {exc.strerror or exc}")
    else:
        sys.stdout.write(payload)

    issues: list[tuple[str, str]] = []
    pw = trace["parse_warnings"]
    if pw["missing_result"]:
        issues.append(
            (
                "missing_result",
                "no result event; stream truncated (stop_reason=incomplete)",
            )
        )
    if pw["missing_init"]:
        issues.append(
            (
                "missing_init",
                "no system/init event; identity and catalogue fields are empty",
            )
        )
    if pw["malformed_lines"]:
        issues.append(
            (
                "malformed_lines",
                f"{pw['malformed_lines']} line(s) were not JSON objects",
            )
        )

    fields = {
        "INPUT": args.input,
        "OUTPUT": args.output or "-",
        "HARNESS": trace["harness"],
        "MODEL_ID": trace["model_id"] or "",
        "NUM_TURNS": trace["num_turns"],
        "TOOL_CALLS": len(trace["tool_calls"]),
        "SKILLS_INVOKED": ",".join(s["skill"] or "" for s in trace["skills_invoked"]),
        "PERMISSION_DENIED": len(trace["permission_denied"]),
        "STOP_REASON": trace["stop_reason"],
        "MALFORMED_LINES": pw["malformed_lines"],
    }
    _emit_block(block_out, fields, "WARN" if issues else "OK", issues)
    return 0


if __name__ == "__main__":
    sys.exit(main())

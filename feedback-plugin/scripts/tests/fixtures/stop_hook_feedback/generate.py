#!/usr/bin/env python3
"""Regenerate `t.jsonl` from the DEPLOYED Stop-hook reason strings.

A Stop hook that returns `{"decision": "block", "reason": R}` reaches the
transcript as a meta user record, never as a tool_result:

    {"type": "user", "isMeta": true,
     "message": {"content": "Stop hook feedback:\\n<R>"}}

A prompt-type hook renders as `Stop hook feedback:\\n[<prompt>]: <reason>`.

Every reason below is EXTRACTED from the shipped hook source and rendered the
way bash would render it, never retyped: a hand-copied message reads
identically in a diff while keying on text the real hook never emits (see
~/.claude/rules/never-fabricate-test-identifiers.md). The one exception is
LEGACY_STASH_BODY, a pre-#2686 message shape that no longer ships but still
sits in the transcripts a 7-day window reads.

Run from the repo root after any Stop hook's prose changes:

    python3 feedback-plugin/scripts/tests/fixtures/stop_hook_feedback/generate.py

`test_friction_parse.py::test_stop_fixture_matches_deployed_hooks` fails when
the checked-in fixture has drifted from the hooks.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[4]
HOOKS = REPO_ROOT / "hooks-plugin" / "hooks"
TASK_COMPLETENESS = HOOKS / "task-completeness.sh"
CALENDAR = HOOKS / "no-calendar-estimates.sh"
STASH_REMINDER = HOOKS / "git-stash-reminder.sh"
SESSION_END_NUDGE = REPO_ROOT / "session-plugin" / "hooks" / "session-end-nudge.sh"
HOOKS_MANIFEST = REPO_ROOT / "hooks-plugin" / ".claude-plugin" / "plugin.json"

PREFIX = "Stop hook feedback:\n"

# A pre-#2686 git-stash-reminder message: no per-entry action verb, and the
# "pop or apply" header even when every entry is an auto-checkpoint. Retained
# because historical transcripts carry it (verified in ~/.claude/projects).
LEGACY_STASH_BODY = (
    "Found 2 git stash(es) created during this session in /repo. "
    "Review before exiting:\n\n"
    "Session stashes — pop or apply them:\n"
    "  stash@{0} (3m ago): On main: auto-checkpoint before rm -rf\n"
    "  stash@{1} (9m ago): On main: auto-checkpoint before git reset --hard\n\n"
    "Run 'git stash list' to inspect, or 'git stash show -p stash@{N}' to review contents."
)

# A Stop feedback body no classifier needle matches: must surface as
# `stop:unclassified`, never be dropped.
UNKNOWN_STOP_BODY = "Some future Stop hook said something this parser has never seen."


def _dq_literal(line: str, opener: str) -> str:
    """Return the raw text of the double-quoted literal that follows `opener`."""
    start = line.index(opener) + len(opener)
    out = []
    i = start
    while i < len(line):
        ch = line[i]
        if ch == "\\" and i + 1 < len(line):
            out.append(line[i : i + 2])
            i += 2
            continue
        if ch == '"':
            return "".join(out)
        out.append(ch)
        i += 1
    raise ValueError(f"unterminated literal after {opener!r}: {line[:80]}")


def _expand(raw: str, env: dict[str, str]) -> str:
    """Expand a bash double-quoted literal: ${VAR}, $VAR, \\", \\\\, \\$.

    Backslash-n stays a literal backslash-n, exactly as it does in bash double
    quotes; callers that pass the result through `printf '%b'` apply
    _printf_b() afterwards.
    """

    def var(match: re.Match[str]) -> str:
        name = match.group(1) or match.group(2)
        if name not in env:
            raise KeyError(f"no fixture value for ${name}")
        return env[name]

    out = []
    i = 0
    while i < len(raw):
        ch = raw[i]
        if ch == "\\" and i + 1 < len(raw) and raw[i + 1] in '"\\$`':
            out.append(raw[i + 1])
            i += 2
            continue
        if ch == "$":
            m = re.match(
                r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)", raw[i:]
            )
            if m:
                out.append(var(m))
                i += m.end()
                continue
        out.append(ch)
        i += 1
    return "".join(out)


def _printf_b(text: str) -> str:
    return text.replace("\\n", "\n")


def _lines_matching(path: Path, pattern: str) -> list[str]:
    rx = re.compile(pattern)
    return [
        ln.strip()
        for ln in path.read_text(encoding="utf-8").splitlines()
        if rx.search(ln)
    ]


def task_completeness_bodies() -> list[str]:
    env = {"DIFF_TODOS": "2", "FILE_LIST": "src/app.py", "DEBUG_COUNT": "3"}
    lines = _lines_matching(TASK_COMPLETENESS, r'--arg reason "')
    assert len(lines) == 3, f"expected 3 task-completeness reasons, found {len(lines)}"
    return [_expand(_dq_literal(ln, '--arg reason "'), env) for ln in lines]


def calendar_bodies() -> list[str]:
    lines = _lines_matching(CALENDAR, r'^\s*REASON="')
    assert len(lines) == 2, (
        f"expected 2 no-calendar-estimates reasons, found {len(lines)}"
    )
    return [_expand(_dq_literal(ln, 'REASON="'), {}) for ln in lines]


def session_end_nudge_body() -> str:
    lines = _lines_matching(SESSION_END_NUDGE, r'^\s*reason="')
    assert len(lines) == 1, f"expected 1 session-end-nudge reason, found {len(lines)}"
    return _expand(_dq_literal(lines[0], 'reason="'), {"task_cue": ""})


def stash_bodies() -> dict[str, str]:
    """Assemble the reminder exactly as git-stash-reminder.sh does, per variant.

    Variant keys are the sub-signature the parser must assign.
    """
    src = STASH_REMINDER.read_text(encoding="utf-8").splitlines()
    first = [ln.strip() for ln in src if ln.strip().startswith('REASON="Found ')]
    review = [ln.strip() for ln in src if "Session stashes — review each one" in ln]
    pop = [ln.strip() for ln in src if "Session stashes — pop or apply them" in ln]
    tails = [
        ln.strip()
        for ln in src
        if ln.strip().startswith('REASON="${REASON}\\n') and "Session stashes" not in ln
    ]
    entry = [
        ln.strip() for ln in src if ln.strip().startswith('NEW_STASHES="${NEW_STASHES}')
    ]
    actions = [ln.strip() for ln in src if ln.strip().startswith('ACTION="')]
    assert len(first) == 1 and len(review) == 1 and len(pop) == 1, (
        "stash header shape changed"
    )
    assert len(entry) == 1 and len(actions) == 2 and tails, "stash entry shape changed"
    checkpoint_action = _expand(_dq_literal(actions[0], 'ACTION="'), {})
    pop_action = _expand(_dq_literal(actions[1], 'ACTION="'), {})

    def entries(rows: list[tuple[str, str, str]]) -> str:
        acc = ""
        for ref, subject, action in rows:
            acc = _expand(
                _dq_literal(entry[0], 'NEW_STASHES="'),
                {
                    "NEW_STASHES": acc,
                    "ref": ref,
                    "AGE_STR": "4m ago",
                    "subject": subject,
                    "ACTION": action,
                },
            )
        return acc

    def assemble(rows: list[tuple[str, str, str]], has_checkpoint: bool) -> str:
        reason = _expand(
            _dq_literal(first[0], 'REASON="'),
            {"NEW_COUNT": str(len(rows)), "REPO_ROOT": "/repo"},
        )
        header = review[0] if has_checkpoint else pop[0]
        reason = _expand(
            _dq_literal(header, 'REASON="'),
            {"REASON": reason, "NEW_STASHES": entries(rows)},
        )
        for tail in tails:
            reason = _expand(_dq_literal(tail, 'REASON="'), {"REASON": reason})
        return _printf_b(reason)

    ck1 = ("stash@{0}", "On main: auto-checkpoint before rm -rf", checkpoint_action)
    ck2 = (
        "stash@{1}",
        "On main: auto-checkpoint before git reset --hard",
        checkpoint_action,
    )
    manual = ("stash@{0}", "On main: wip before rebase", pop_action)
    return {
        "auto-checkpoint": assemble([ck1, ck2], True),
        "mixed": assemble([manual, ck2], True),
        "other": assemble([manual], False),
    }


def subagent_prompt_body() -> str:
    manifest = json.loads(HOOKS_MANIFEST.read_text(encoding="utf-8"))
    prompts = [
        h["prompt"]
        for group in manifest["hooks"].get("SubagentStop", [])
        for h in group.get("hooks", [])
        if h.get("type") == "prompt"
    ]
    assert len(prompts) == 1, (
        f"expected 1 SubagentStop prompt hook, found {len(prompts)}"
    )
    return f"[{prompts[0]}]: The output verifies the fix but does not say what changed."


def stop_bodies() -> list[tuple[str, str]]:
    """(expected signature, feedback body) for every deployed Stop reason."""
    out: list[tuple[str, str]] = []
    for variant, body in stash_bodies().items():
        out.append((f"stop:git-stash-reminder:{variant}", body))
    out.append(("stop:git-stash-reminder:auto-checkpoint", LEGACY_STASH_BODY))
    for body in task_completeness_bodies():
        out.append(("stop:task-completeness", body))
    for body in calendar_bodies():
        out.append(("stop:no-calendar-estimates", body))
    out.append(("stop:session-end-nudge", session_end_nudge_body()))
    out.append(("stop:subagent-output-check", subagent_prompt_body()))
    out.append(("stop:unclassified", UNKNOWN_STOP_BODY))
    return out


def build_lines() -> list[str]:
    records: list[dict] = [
        # A genuine prompt, so the fixture carries a non-meta user record.
        {
            "type": "user",
            "timestamp": "2026-09-20T10:00:00Z",
            "message": {"content": "tidy up the build script"},
        },
        # Controls: a hook block and a plain tool error, so the dual-parser
        # identical-input check has pre-existing signatures to hold constant.
        {
            "type": "assistant",
            "timestamp": "2026-09-20T10:00:01Z",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "id": "toolu_ctl1",
                        "name": "Bash",
                        "input": {"command": "git push --force"},
                    }
                ]
            },
        },
        {
            "type": "user",
            "timestamp": "2026-09-20T10:00:02Z",
            "message": {
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_ctl1",
                        "is_error": True,
                        "content": "PreToolUse:Bash hook error: [bash ${CLAUDE_PLUGIN_ROOT}/hooks/branch-protection.sh]: BLOCKED: push to a protected branch",
                    }
                ]
            },
        },
        {
            "type": "assistant",
            "timestamp": "2026-09-20T10:00:03Z",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "id": "toolu_ctl2",
                        "name": "Bash",
                        "input": {"command": "pnpm build"},
                    }
                ]
            },
        },
        {
            "type": "user",
            "timestamp": "2026-09-20T10:00:04Z",
            "message": {
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_ctl2",
                        "is_error": True,
                        "content": "zsh: command not found: pnpm",
                    }
                ]
            },
        },
    ]
    for i, (_sig, body) in enumerate(stop_bodies()):
        records.append(
            {
                "type": "user",
                "isMeta": True,
                "timestamp": f"2026-09-20T11:{i:02d}:00Z",
                "message": {"role": "user", "content": PREFIX + body},
            }
        )
    return [json.dumps(r, ensure_ascii=False) for r in records]


def main() -> int:
    (HERE / "t.jsonl").write_text("\n".join(build_lines()) + "\n", encoding="utf-8")
    print(f"wrote {HERE / 't.jsonl'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

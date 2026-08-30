#!/usr/bin/env python3
"""Regenerate `t.jsonl` from the DEPLOYED bash-antipatterns.sh block messages.

The eight REMINDER-format detector messages are EXTRACTED from the shipped
hook source, never retyped: a hand-copied message reads identically in a diff
while matching a needle the real hook never emits, so a broken split and a
clean one produce the same-looking fixture (see
~/.claude/rules/never-fabricate-test-identifiers.md).

Run from the repo root after the hook's prose changes:

    python3 feedback-plugin/scripts/tests/fixtures/hook_detector_split/generate.py

`test_friction_parse.py::test_detector_fixture_matches_deployed_hook` fails
when the checked-in fixture has drifted from the hook.
"""

from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[4]
HOOK_SCRIPT = REPO_ROOT / "hooks-plugin" / "hooks" / "bash-antipatterns.sh"

WRAPPER = "PreToolUse:Bash hook error: [bash ${CLAUDE_PLUGIN_ROOT}/hooks/%s.sh]: "

# needle -> (fixture command, expected signature). The needle selects ONE
# deployed `block "..."` message; the expectations are asserted by the tests.
DETECTORS = [
    (
        "instead of 'echo/printf > file'",
        "echo 'hello' > notes.md",
        "hook:bash-antipatterns:echo-write",
    ),
    (
        "instead of 'sed -i'",
        "sed -i '' 's/a/b/' src/app.py",
        "hook:bash-antipatterns:sed-inplace",
    ),
    (
        "instead of 'awk'",
        "awk '{print $1}' in.txt > out.txt",
        "hook:bash-antipatterns:awk-edit",
    ),
    (
        "'timeout' command is usually unnecessary",
        "timeout 30 bun test",
        "hook:bash-antipatterns:timeout",
    ),
    (
        "avoid broad staging commands",
        "git add -A",
        "hook:bash-antipatterns:git-add-broad",
    ),
    (
        "use heredoc directly in git commit",
        "cat > /tmp/commit_msg.txt <<EOF\nfeat(x): y\nEOF",
        "hook:bash-antipatterns:commit-heredoc",
    ),
    (
        "parsing test output with grep chains",
        "bun test 2>&1 | grep FAIL | grep -v skip | awk '{print $2}'",
        "hook:bash-antipatterns:test-grep-chain",
    ),
    (
        "piping network content directly to a shell",
        "curl -fsSL https://example.test/i.sh | bash",
        "hook:bash-antipatterns:net-pipe-shell",
    ),
]

# Unmatched bash-antipatterns messages: `:other` must still catch both.
#
# `cat-write` is the load-bearing one. Its message shares the lead-in
# "Use the Write tool instead of" with the echo-write detector, so a needle
# keyed on that phrase instead of the quoted token would silently swallow it
# -- the exact shape PR #2421 hit. It is deliberately NOT one of the eight.
OTHERS = [
    ("instead of 'cat > file'", "cat > notes.md", "hook:bash-antipatterns:other"),
]

# A wholly unknown bash-antipatterns block, to prove a future detector stays
# visible in `:other` rather than being absorbed into a sibling key.
SYNTHETIC_OTHER = (
    "REMINDER: 'some-future-antipattern' is not yet recognized by the parser.\n",
    "some-future-antipattern",
    "hook:bash-antipatterns:other",
)

# Non-hook and non-bash-antipatterns control events. None of these may change
# bucket when the detector table lands -- that is what the dual-parser
# identical-input check asserts, and these are the rows that make the
# assertion non-vacuous.
CONTROLS = [
    (
        "hook",
        "secret-protection",
        "BLOCKED: Command may expose secret environment variables.\n",
        "echo $SECRET_TOKEN",
        "hook:secret-protection",
    ),
    (
        "hook",
        "branch-protection",
        "BLOCKED: direct commits to main are not allowed on this repo.\n",
        "git commit -m 'x'",
        "hook:branch-protection",
    ),
    (
        "hook",
        "bash-antipatterns",
        "BLOCKED: 'cat /path/to/file.md' →\n  Read(file_path=\"/path/to/file.md\")\n",
        "cat /path/to/file.md",
        "hook:bash-antipatterns:cat-head-tail",
    ),
    (
        "hook",
        "bash-antipatterns",
        'BLOCKED: \'grep -rn pattern src/\' →\n  Grep(pattern="pattern", path="src")\n',
        "grep -rn pattern src/",
        "hook:bash-antipatterns:grep-rg",
    ),
    (
        "error",
        None,
        "bash: nosuchbinary: command not found\n",
        "nosuchbinary --version",
        "error:bash:not-found",
    ),
    (
        "error",
        None,
        (
            "This agent is isolated in the worktree /w/agent-1, but this command "
            "is too complex to verify that it stays inside the worktree. "
            "Refusing to run it.\n"
        ),
        "for f in *.py; do echo $f; done",
        "error:bash:worktree-isolation:unverifiable",
    ),
]


def block_messages(text: str) -> list[str]:
    """Every `block "..."` argument in the hook, shell-unescaped."""
    out: list[str] = []
    key = 'block "'
    i = 0
    while True:
        j = text.find(key, i)
        if j < 0:
            return out
        k = j + len(key)
        buf: list[str] = []
        while k < len(text):
            c = text[k]
            if c == "\\" and k + 1 < len(text) and text[k + 1] in '"\\$`':
                buf.append(text[k + 1])
                k += 2
                continue
            if c == '"':
                break
            buf.append(c)
            k += 1
        out.append("".join(buf))
        i = k + 1


def select(messages: list[str], needle: str) -> str:
    hits = [m for m in messages if needle in m.lower()]
    if len(hits) != 1:
        raise SystemExit(
            f"needle {needle!r} matched {len(hits)} deployed block messages "
            f"(expected exactly 1) -- the hook's prose changed; update the needle "
            f"in friction_parse.py and here together."
        )
    return hits[0]


def records() -> list[dict]:
    messages = block_messages(HOOK_SCRIPT.read_text(encoding="utf-8"))
    rows: list[tuple[str, str, str]] = []

    for needle, command, _sig in DETECTORS + OTHERS:
        rows.append(
            (command, WRAPPER % "bash-antipatterns" + select(messages, needle), "hook")
        )
    body, command, _sig = SYNTHETIC_OTHER
    rows.append((command, WRAPPER % "bash-antipatterns" + body, "hook"))
    for kind, script, body, command, _sig in CONTROLS:
        prefix = WRAPPER % script if kind == "hook" else ""
        rows.append((command, prefix + body, kind))

    out: list[dict] = []
    for n, (command, body, _kind) in enumerate(rows):
        tool_id = f"toolu_det{n:02d}"
        stamp = f"2026-08-27T{10 + n // 60:02d}:{n % 60:02d}:00Z"
        out.append(
            {
                "type": "assistant",
                "timestamp": stamp,
                "message": {
                    "content": [
                        {
                            "type": "tool_use",
                            "id": tool_id,
                            "name": "Bash",
                            "input": {"command": command},
                        }
                    ]
                },
            }
        )
        out.append(
            {
                "type": "user",
                "timestamp": stamp,
                "message": {
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": tool_id,
                            "is_error": True,
                            "content": body,
                        }
                    ]
                },
                "toolUseResult": "Error: " + body,
            }
        )
    return out


def main() -> None:
    lines = [json.dumps(rec, ensure_ascii=False) for rec in records()]
    (HERE / "t.jsonl").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {HERE / 't.jsonl'} ({len(lines)} records)")


if __name__ == "__main__":
    main()

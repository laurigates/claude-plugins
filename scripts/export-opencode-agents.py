#!/usr/bin/env python3
"""Project this marketplace's subagents into OpenCode's agent format.

Replaces the rulesync `claudecode -> opencode` conversion for the agents
surface (#2094). rulesync's entire contribution here was to keep `name` and
`description`, add `mode: subagent`, and drop everything else -- OpenCode's
agent schema has no `model`, `tools`, or `maxTurns` -- so owning the transform
costs ~60 lines and removes the last dependency on the export pipeline.

Skills are deliberately NOT exported: OpenCode reads Claude Code `SKILL.md`
natively, and the marketplace corpus reaches it through the adapter
(`adapters/opencode/`, ADR-0022) rather than a flattened copy.

Usage: export-opencode-agents.py <repo-root> <out-dir>
Emits <out-dir>/agents/<name>.md and a KEY=VALUE report.
"""

import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - PyYAML is a hard dependency of the repo
    print("ERROR=PyYAML not available (pip install pyyaml)", file=sys.stderr)
    sys.exit(1)

# OpenCode's agent frontmatter. Everything else in a Claude Code agent header
# (model, tools, maxTurns, color, dates) has no OpenCode equivalent.
KEEP = ("description", "name")


def split_frontmatter(text: str) -> tuple[dict, str]:
    """Return (frontmatter, body). Raises ValueError on a missing/broken block."""
    if not text.startswith("---\n"):
        raise ValueError("no frontmatter block at line 1")
    end = text.find("\n---\n", 3)
    if end == -1:
        raise ValueError("unterminated frontmatter block")
    front = yaml.safe_load(text[4:end]) or {}
    if not isinstance(front, dict):
        raise ValueError("frontmatter is not a mapping")
    return front, text[end + 5 :]


def render(front: dict, body: str, fallback_name: str) -> str:
    out = {k: front[k] for k in KEEP if front.get(k)}
    out.setdefault("name", fallback_name)
    out["mode"] = "subagent"
    header = yaml.safe_dump(out, default_flow_style=False, sort_keys=True, width=80)
    return f"---\n{header}---\n{body.lstrip(chr(10))}"


def main(repo_root: Path, out_dir: Path) -> int:
    agents_out = out_dir / "agents"
    agents_out.mkdir(parents=True, exist_ok=True)

    sources = sorted(repo_root.glob("*-plugin/agents/*.md"))
    written, skipped = 0, []
    for src in sources:
        try:
            front, body = split_frontmatter(src.read_text(encoding="utf-8"))
        except (ValueError, yaml.YAMLError) as exc:
            skipped.append(f"{src.relative_to(repo_root)}: {exc}")
            continue
        if not front.get("description"):
            skipped.append(f"{src.relative_to(repo_root)}: no description")
            continue
        (agents_out / src.name).write_text(
            render(front, body, src.stem), encoding="utf-8"
        )
        written += 1

    print(f"SOURCE_AGENTS={len(sources)}")
    print(f"OUTPUT_AGENTS={written}")
    print(f"SKIPPED_AGENTS={len(skipped)}")
    if skipped:
        print("SKIPPED:")
        for entry in skipped:
            print(f"  - {entry}")
    return 1 if skipped else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: export-opencode-agents.py <repo-root> <out-dir>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()))

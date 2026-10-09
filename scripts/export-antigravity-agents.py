#!/usr/bin/env python3
"""Project this marketplace's subagents into Antigravity CLI's agent format.

Antigravity CLI (agy) discovers subagents in Markdown format (`agent.md`)
from `~/.gemini/config/agents/<name>/agent.md` (global) or
`<workspace>/.agents/agents/<name>/agent.md` (project).

This generator projects Claude Code subagent definitions into Antigravity format:
  <plugin>/agents/<name>.md -> <out>/agents/<name>/agent.md

Fidelity mapping:
  - `name`: preserved
  - `description`: preserved
  - `model`: mapped to Antigravity model tiers:
      - opus       -> pro
      - sonnet     -> flash
      - haiku      -> flash_lite
      - other/none -> inherit
  - `subagent`: true
  - `inheritCustomizations`: true (adopts workspace skills, rules, and MCP servers)

Usage: export-antigravity-agents.py <repo-root> <out-dir>
Emits <out-dir>/agents/<name>/agent.md and a KEY=VALUE report.
"""

import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    print("ERROR=PyYAML not available (pip install pyyaml)", file=sys.stderr)
    sys.exit(1)

MODEL_MAP = {
    "opus": "pro",
    "sonnet": "flash",
    "haiku": "flash_lite",
    "inherit": "inherit",
}


def split_frontmatter(text: str) -> tuple[dict, str]:
    """Return (frontmatter, body). Raises ValueError on missing or invalid block."""
    if not text.startswith("---\n"):
        raise ValueError("no frontmatter block at line 1")
    end = text.find("\n---\n", 3)
    if end == -1:
        raise ValueError("unterminated frontmatter block")
    front = yaml.safe_load(text[4:end]) or {}
    if not isinstance(front, dict):
        raise TypeError("frontmatter is not a mapping")
    return front, text[end + 5 :]


def map_model(raw_model: object) -> str:
    """Map Claude Code model alias to Antigravity model tier."""
    if not raw_model:
        return "inherit"
    model_str = str(raw_model).strip().lower()
    return MODEL_MAP.get(model_str, "inherit")


def render(front: dict, body: str, fallback_name: str) -> str:
    name = str(front.get("name") or fallback_name).strip()
    description = str(front.get("description") or "").strip()
    model = map_model(front.get("model"))

    out = {
        "name": name,
        "description": description,
        "model": model,
        "subagent": True,
        "inheritCustomizations": True,
    }

    # Clean up empty strings or whitespace
    header = yaml.safe_dump(out, default_flow_style=False, sort_keys=True, width=80)
    return f"---\n{header}---\n\n{body.lstrip(chr(10))}"


def main(repo_root: Path, out_dir: Path) -> int:
    agents_out = out_dir / "agents"
    agents_out.mkdir(parents=True, exist_ok=True)

    sources = sorted(repo_root.glob("*-plugin/agents/*.md"))
    written, skipped = 0, []
    for src in sources:
        try:
            front, body = split_frontmatter(src.read_text(encoding="utf-8"))
        except (ValueError, TypeError, yaml.YAMLError) as exc:
            skipped.append(f"{src.relative_to(repo_root)}: {exc}")
            continue

        if not front.get("description"):
            skipped.append(f"{src.relative_to(repo_root)}: no description")
            continue

        agent_name = str(front.get("name") or src.stem).strip()
        target_dir = agents_out / agent_name
        target_dir.mkdir(parents=True, exist_ok=True)

        (target_dir / "agent.md").write_text(
            render(front, body, agent_name), encoding="utf-8"
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
        print(
            "usage: export-antigravity-agents.py <repo-root> <out-dir>", file=sys.stderr
        )
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()))

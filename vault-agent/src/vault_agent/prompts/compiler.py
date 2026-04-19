"""Runtime compiler for SKILL.md files into subagent prompt fragments.

Reads selected obsidian-plugin skills, strips Claude Code metadata, keeps
domain knowledge sections, and produces combined prompt text for each
vault-agent subagent. Same pattern as git-repo-agent's compiler.
"""

from __future__ import annotations

import re
import sys
from functools import lru_cache
from pathlib import Path

_MODULE_DIR = Path(__file__).resolve().parent  # prompts/
_REPO_ROOT = _MODULE_DIR.parent.parent.parent  # vault-agent/
_PLUGINS_ROOT = _REPO_ROOT.parent  # claude-plugins/

# Subagent → list of skill files (relative to PLUGINS_ROOT).
#
# All vault maintenance skills live under the existing obsidian-plugin
# (alongside the CLI-operation skills: vault-files, properties, etc.).
SUBAGENT_SKILLS: dict[str, list[str]] = {
    "vault-lint": [
        "obsidian-plugin/skills/vault-frontmatter/SKILL.md",
        "obsidian-plugin/skills/vault-tags/SKILL.md",
        "obsidian-plugin/skills/vault-templates/SKILL.md",
    ],
    "vault-links": [
        "obsidian-plugin/skills/vault-wikilinks/SKILL.md",
        "obsidian-plugin/skills/vault-orphans/SKILL.md",
    ],
    "vault-stubs": [
        "obsidian-plugin/skills/vault-stubs/SKILL.md",
        "obsidian-plugin/skills/vault-frontmatter/SKILL.md",
    ],
    "vault-mocs": [
        "obsidian-plugin/skills/vault-mocs/SKILL.md",
        "obsidian-plugin/skills/vault-tags/SKILL.md",
        "obsidian-plugin/skills/vault-orphans/SKILL.md",
    ],
}

# Sections to KEEP (domain knowledge). Everything NOT in DROP is kept by
# default — this is the explicit allow-list for any section name we
# especially want to preserve.
KEEP_HEADINGS = {
    "canonical frontmatter shape",
    "canonical redirect stub format",
    "canonical moc shape",
    "canonical categories",
    "consolidation table",
    "classifications (from vault-agent's stubs analyzer)",
    "common breakage patterns",
    "core operations",
    "detection",
    "detection patterns",
    "edit pattern",
    "edit recipes",
    "legacy moc fixups",
    "resolution rules",
    "rewriting strategy",
    "safety",
    "triage workflow",
    "unrendered markers",
}

# Sections to DROP (Claude Code metadata / how-to-use-this-skill stuff).
DROP_HEADINGS = {
    "when to use",
    "when to use this skill",
    "prerequisites",
    "context",
    "parameters",
    "agentic optimizations",
    "flags",
    "see also",
    "quick reference",
    "related skills",
}

FRONTMATTER_RE = re.compile(r"\A---\n.*?^---\n", re.MULTILINE | re.DOTALL)


def strip_frontmatter(content: str) -> str:
    """Remove YAML frontmatter between --- markers."""
    return FRONTMATTER_RE.sub("", content, count=1)


def parse_sections(content: str) -> list[tuple[str, str, str]]:
    """Parse markdown into (heading, level_marker, body) triples.

    The first triple may have an empty heading — that's the intro text
    before any heading. Level marker is the literal ``#`` / ``##`` / ``###``.
    """
    sections: list[tuple[str, str, str]] = []
    current_heading = ""
    current_marker = ""
    current_lines: list[str] = []

    for line in content.splitlines(keepends=True):
        heading_match = re.match(r"^(#{1,3})\s+(.+?)(\s*#*)?\s*$", line)
        if heading_match:
            sections.append((current_heading, current_marker, "".join(current_lines)))
            current_marker = heading_match.group(1)
            current_heading = heading_match.group(2).strip()
            current_lines = []
        else:
            current_lines.append(line)

    sections.append((current_heading, current_marker, "".join(current_lines)))
    return sections


def filter_sections(sections: list[tuple[str, str, str]]) -> str:
    """Keep domain-knowledge sections, drop metadata sections."""
    parts: list[str] = []

    for heading, marker, body in sections:
        heading_lower = heading.lower().rstrip(".")

        # Intro (before first heading)
        if not heading:
            intro = body.strip()
            if intro:
                parts.append(intro)
            continue

        if heading_lower in DROP_HEADINGS:
            continue
        # Default: keep everything not explicitly dropped
        parts.append(f"{marker} {heading}\n{body}")

    return "\n".join(parts)


def transform_references(content: str) -> str:
    """Rewrite ``AskUserQuestion`` / "ask the user" to orchestrator-reporting.

    Inside a subagent these phrases are meaningless — the subagent talks to
    the orchestrator, not to the user directly.
    """
    content = re.sub(r"(?i)\bAskUserQuestion\b", "report to orchestrator", content)
    content = re.sub(r"(?i)\bask\s+the\s+user\b", "report to the orchestrator", content)
    return content


def compile_skill(skill_path: Path) -> str:
    """Compile one SKILL.md into a prompt fragment."""
    content = skill_path.read_text(encoding="utf-8")
    content = strip_frontmatter(content)
    sections = parse_sections(content)
    content = filter_sections(sections)
    content = transform_references(content)
    return content.strip()


def compile_subagent(name: str, skill_paths: list[str]) -> str:
    """Compile all skills for a subagent into a combined prompt."""
    fragments: list[str] = []

    for rel_path in skill_paths:
        skill_path = _PLUGINS_ROOT / rel_path
        if not skill_path.exists():
            print(f"  WARNING: {rel_path} not found, skipping", file=sys.stderr)
            continue

        fragment = compile_skill(skill_path)
        if fragment:
            skill_name = skill_path.parent.name
            fragments.append(f"## {skill_name}\n\n{fragment}")

    return "\n\n---\n\n".join(fragments) + "\n"


@lru_cache(maxsize=None)
def get_compiled_prompt(subagent_name: str) -> str:
    """Return the compiled skill bundle for a subagent (cached)."""
    skill_paths = SUBAGENT_SKILLS.get(subagent_name)
    if not skill_paths:
        return ""
    return compile_subagent(subagent_name, skill_paths)


@lru_cache(maxsize=None)
def get_compiled_skill(skill_relpath: str) -> str:
    """Compile a single skill file (cached).

    Useful for phased drivers that run one skill per LLM call.
    """
    skill_path = _PLUGINS_ROOT / skill_relpath
    if not skill_path.exists():
        raise FileNotFoundError(f"Skill not found: {skill_relpath}")
    return compile_skill(skill_path)

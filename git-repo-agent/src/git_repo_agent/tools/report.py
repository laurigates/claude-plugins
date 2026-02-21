"""report_generate MCP tool — format health findings into structured reports."""

from __future__ import annotations

import json
from typing import Any

from claude_agent_sdk import tool

# Grade emoji mapping
_GRADE_EMOJI = {"A": "\u2705", "B": "\U0001f7e2", "C": "\U0001f7e1", "D": "\U0001f7e0", "F": "\U0001f534"}

# Category display names
_CATEGORY_NAMES = {
    "docs": "Documentation",
    "tests": "Testing",
    "security": "Security",
    "quality": "Code Quality",
    "ci": "CI/CD",
}


def _category_status(score: int, max_score: int = 20) -> str:
    """Return a status label for a category score."""
    ratio = score / max_score
    if ratio >= 0.9:
        return "Excellent"
    if ratio >= 0.8:
        return "Good"
    if ratio >= 0.7:
        return "OK"
    if ratio >= 0.5:
        return "Needs work"
    return "Poor"


def _format_markdown(scores: dict[str, Any]) -> str:
    """Format health scores as a markdown report."""
    overall = scores["overall_score"]
    grade = scores["grade"]
    emoji = _GRADE_EMOJI.get(grade, "")
    categories = scores["category_scores"]
    findings = scores.get("findings", {})

    lines = [
        f"# Health Report {emoji}",
        "",
        f"**Score:** {overall}/100 ({grade})",
        "",
        "## Category Breakdown",
        "",
        "| Category | Score | Status |",
        "|----------|-------|--------|",
    ]

    for cat_key, cat_score in categories.items():
        cat_name = _CATEGORY_NAMES.get(cat_key, cat_key.title())
        status = _category_status(cat_score)
        lines.append(f"| {cat_name} | {cat_score}/20 | {status} |")

    if findings:
        lines.extend(["", "## Findings", ""])
        for cat_key, cat_findings in findings.items():
            cat_name = _CATEGORY_NAMES.get(cat_key, cat_key.title())
            lines.append(f"### {cat_name}")
            for finding in cat_findings:
                lines.append(f"- {finding}")
            lines.append("")

    return "\n".join(lines)


def _format_json(scores: dict[str, Any]) -> str:
    """Format health scores as JSON."""
    return json.dumps(scores, indent=2)


def _format_terminal(scores: dict[str, Any]) -> str:
    """Format health scores for terminal display (Rich-compatible)."""
    overall = scores["overall_score"]
    grade = scores["grade"]
    categories = scores["category_scores"]
    findings = scores.get("findings", {})

    # Build a progress-bar style indicator
    filled = overall // 5
    bar = "\u2588" * filled + "\u2591" * (20 - filled)

    lines = [
        f"Health: {overall}/100 ({grade})  [{bar}]",
        "",
    ]

    for cat_key, cat_score in categories.items():
        cat_name = _CATEGORY_NAMES.get(cat_key, cat_key.title())
        cat_bar = "\u2588" * (cat_score // 1) + "\u2591" * (20 - cat_score)
        lines.append(f"  {cat_name:<15} {cat_score:>2}/20  [{cat_bar}]")

    if findings:
        lines.append("")
        for cat_key, cat_findings in findings.items():
            cat_name = _CATEGORY_NAMES.get(cat_key, cat_key.title())
            for finding in cat_findings:
                lines.append(f"  [{cat_name}] {finding}")

    return "\n".join(lines)


def generate_report(scores: dict[str, Any], fmt: str = "terminal") -> str:
    """Generate a formatted health report.

    Args:
        scores: Health score data from compute_health_score().
        fmt: Output format — "markdown", "json", or "terminal".

    Returns:
        Formatted report string.
    """
    formatters = {
        "markdown": _format_markdown,
        "json": _format_json,
        "terminal": _format_terminal,
    }
    formatter = formatters.get(fmt, _format_terminal)
    return formatter(scores)


@tool(
    "report_generate",
    "Generate a formatted health report from health_score output. "
    "Supports markdown, json, and terminal output formats.",
    {"scores": str, "format": str},
)
async def report_generate(args: dict[str, Any]) -> dict[str, Any]:
    """MCP tool handler for report generation."""
    try:
        scores = json.loads(args["scores"])
    except (json.JSONDecodeError, TypeError) as e:
        return {
            "content": [
                {
                    "type": "text",
                    "text": f"Error: invalid scores JSON — {e}",
                }
            ]
        }

    fmt = args.get("format", "terminal")
    if fmt not in ("markdown", "json", "terminal"):
        return {
            "content": [
                {
                    "type": "text",
                    "text": f"Error: invalid format '{fmt}'. Use 'markdown', 'json', or 'terminal'.",
                }
            ]
        }

    report = generate_report(scores, fmt)
    return {
        "content": [
            {
                "type": "text",
                "text": report,
            }
        ]
    }

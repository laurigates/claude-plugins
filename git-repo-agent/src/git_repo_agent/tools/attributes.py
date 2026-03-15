"""Structured codebase attribute collection with severity and remediation actions.

Wraps the existing health_score findings into structured attributes that enable
data-driven agent routing. Each attribute has an ID, category, severity, and
a list of suggested remediation actions pointing to specific agents.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from claude_agent_sdk import tool

from .health_check import compute_health_score


@dataclass
class Action:
    """A remediation action for an attribute."""

    type: str  # "agent" | "skill" | "command"
    target: str  # agent name, skill path, or shell command
    args: str = ""
    auto_fixable: bool = False


@dataclass
class Attribute:
    """A single observable signal about a codebase."""

    id: str
    category: str  # docs|tests|security|quality|ci
    severity: str  # critical|high|medium|low|info
    description: str
    source: str = "health_score"
    file: str | None = None
    actions: list[Action] = field(default_factory=list)


# Maps finding substrings to structured attribute definitions.
# Order matters — first match wins for each finding string.
_FINDING_REGISTRY: list[tuple[str, Attribute]] = [
    # --- docs ---
    (
        "Missing README.md",
        Attribute(
            id="missing-readme",
            category="docs",
            severity="high",
            description="Missing README.md",
            actions=[Action("agent", "docs", "create README.md", True)],
        ),
    ),
    (
        "README.md is very short",
        Attribute(
            id="short-readme",
            category="docs",
            severity="low",
            description="README.md is very short (< 200 chars)",
            actions=[Action("agent", "docs", "expand README.md", True)],
        ),
    ),
    (
        "Missing CLAUDE.md",
        Attribute(
            id="missing-claude-md",
            category="docs",
            severity="medium",
            description="Missing CLAUDE.md",
            actions=[Action("agent", "configure", "create CLAUDE.md", True)],
        ),
    ),
    (
        "No docs/ directory",
        Attribute(
            id="no-docs-directory",
            category="docs",
            severity="low",
            description="No docs/ directory",
            actions=[Action("agent", "docs", "create docs directory", True)],
        ),
    ),
    (
        "Missing LICENSE",
        Attribute(
            id="missing-license",
            category="docs",
            severity="low",
            description="Missing LICENSE file",
            actions=[Action("agent", "docs", "add LICENSE file", True)],
        ),
    ),
    # --- tests ---
    (
        "No test directory or test files found",
        Attribute(
            id="no-test-directory",
            category="tests",
            severity="high",
            description="No test directory or test files found",
            actions=[Action("agent", "test_runner", "scaffold tests", True)],
        ),
    ),
    (
        "no test configuration file found",
        Attribute(
            id="no-test-config",
            category="tests",
            severity="medium",
            description="Tests exist but no test configuration file found",
            actions=[Action("agent", "configure", "add test config", True)],
        ),
    ),
    (
        "No CI workflow runs tests",
        Attribute(
            id="no-ci-tests",
            category="tests",
            severity="high",
            description="No CI workflow runs tests",
            actions=[Action("agent", "configure", "add test step to CI", True)],
        ),
    ),
    # --- security ---
    (
        "Missing .gitignore",
        Attribute(
            id="missing-gitignore",
            category="security",
            severity="high",
            description="Missing .gitignore",
            actions=[Action("agent", "security", "create .gitignore", True)],
        ),
    ),
    (
        ".env file exists in repository",
        Attribute(
            id="env-file-committed",
            category="security",
            severity="critical",
            description=".env file exists in repository (should be gitignored)",
            actions=[Action("agent", "security", "fix .env exposure", False)],
        ),
    ),
    (
        "No pre-commit hooks configured",
        Attribute(
            id="no-pre-commit-hooks",
            category="security",
            severity="medium",
            description="No pre-commit hooks configured",
            actions=[Action("agent", "configure", "setup pre-commit hooks", True)],
        ),
    ),
    (
        "No security scanning in CI",
        Attribute(
            id="no-security-scanning",
            category="security",
            severity="high",
            description="No security scanning in CI",
            actions=[Action("agent", "security", "setup CI security scanning", True)],
        ),
    ),
    (
        "No Dependabot configuration",
        Attribute(
            id="no-dependabot",
            category="security",
            severity="low",
            description="No Dependabot configuration",
            actions=[Action("agent", "configure", "setup Dependabot", True)],
        ),
    ),
    # --- quality ---
    (
        "No linter configured",
        Attribute(
            id="no-linter-configured",
            category="quality",
            severity="medium",
            description="No linter configured",
            actions=[Action("agent", "configure", "setup linter", True)],
        ),
    ),
    (
        "No formatter configured",
        Attribute(
            id="no-formatter",
            category="quality",
            severity="medium",
            description="No formatter configured",
            actions=[Action("agent", "configure", "setup formatter", True)],
        ),
    ),
    (
        "No type checking configured",
        Attribute(
            id="no-type-checking",
            category="quality",
            severity="low",
            description="No type checking configured",
            actions=[Action("agent", "configure", "setup type checker", True)],
        ),
    ),
    # --- ci ---
    (
        "No CI/CD configuration found",
        Attribute(
            id="no-ci-workflows",
            category="ci",
            severity="high",
            description="No CI/CD configuration found",
            actions=[Action("agent", "configure", "setup CI/CD workflows", True)],
        ),
    ),
    (
        "has no workflow files",
        Attribute(
            id="empty-workflows-dir",
            category="ci",
            severity="medium",
            description=".github/workflows/ exists but has no workflow files",
            actions=[Action("agent", "configure", "add CI workflow", True)],
        ),
    ),
]


def _match_finding(finding: str) -> Attribute | None:
    """Match a finding string to a registered attribute."""
    for pattern, template in _FINDING_REGISTRY:
        if pattern.lower() in finding.lower():
            # Return a copy with the original finding text as description
            return Attribute(
                id=template.id,
                category=template.category,
                severity=template.severity,
                description=finding,
                source=template.source,
                file=template.file,
                actions=list(template.actions),
            )
    return None


# Severity weights for priority calculation
_SEVERITY_WEIGHTS = {
    "critical": 4,
    "high": 3,
    "medium": 2,
    "low": 1,
    "info": 0,
}


def collect_attributes(repo_path: Path) -> dict[str, Any]:
    """Collect structured codebase attributes from health score findings.

    Calls compute_health_score() and converts each finding string into a
    structured Attribute with severity and remediation actions.

    Returns a dict matching the attribute schema:
    {
        "version": "1",
        "repo": str,
        "timestamp": str,
        "attributes": [...],
        "scores": { backward-compatible health score data }
    }
    """
    health = compute_health_score(repo_path)

    attributes: list[dict[str, Any]] = []
    for _category, findings in health.get("findings", {}).items():
        for finding_str in findings:
            attr = _match_finding(finding_str)
            if attr:
                attributes.append(asdict(attr))
            else:
                # Unrecognized finding — include as info-level attribute
                attributes.append(
                    asdict(
                        Attribute(
                            id="unknown-finding",
                            category=_category,
                            severity="info",
                            description=finding_str,
                        )
                    )
                )

    return {
        "version": "1",
        "repo": str(repo_path),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "attributes": attributes,
        "scores": {
            "overall": health["overall_score"],
            "grade": health["grade"],
            "max_score": health["max_score"],
            "categories": health["category_scores"],
        },
    }


def route_from_attributes(
    attributes: list[dict[str, Any]],
    min_severity: str = "medium",
) -> list[tuple[str, int, list[str]]]:
    """Determine which agents to invoke based on attribute severity.

    Args:
        attributes: List of attribute dicts from collect_attributes().
        min_severity: Minimum severity to consider for routing.

    Returns:
        List of (agent_name, priority_score, finding_descriptions) sorted
        by descending priority.
    """
    min_weight = _SEVERITY_WEIGHTS.get(min_severity, 2)
    agent_priority: dict[str, int] = {}
    agent_findings: dict[str, list[str]] = {}

    for attr in attributes:
        weight = _SEVERITY_WEIGHTS.get(attr.get("severity", "info"), 0)
        if weight < min_weight:
            continue
        for action in attr.get("actions", []):
            if action.get("type") == "agent":
                target = action["target"]
                agent_priority[target] = agent_priority.get(target, 0) + weight
                agent_findings.setdefault(target, []).append(attr["description"])

    return sorted(
        [
            (agent, score, agent_findings.get(agent, []))
            for agent, score in agent_priority.items()
        ],
        key=lambda x: x[1],
        reverse=True,
    )


def format_attributes_terminal(data: dict[str, Any]) -> str:
    """Format attribute data for terminal display."""
    scores = data.get("scores", {})
    overall = scores.get("overall", 0)
    grade = scores.get("grade", "?")
    categories = scores.get("categories", {})
    attributes = data.get("attributes", [])

    # Category display names
    cat_names = {
        "docs": "Documentation",
        "tests": "Testing",
        "security": "Security",
        "quality": "Code Quality",
        "ci": "CI/CD",
    }

    # Overall bar
    filled = overall // 5
    bar = "\u2588" * filled + "\u2591" * (20 - filled)
    lines = [f"Health: {overall}/100 ({grade})  [{bar}]", ""]

    # Per-category bars
    for cat_key, cat_score in categories.items():
        cat_name = cat_names.get(cat_key, cat_key.title())
        cat_bar = "\u2588" * cat_score + "\u2591" * (20 - cat_score)
        # Count critical/high findings for this category
        cat_critical = sum(
            1 for a in attributes
            if a.get("category") == cat_key and a.get("severity") in ("critical", "high")
        )
        suffix = f"  {cat_critical} critical/high" if cat_critical else ""
        lines.append(f"  {cat_name:<15} {cat_score:>2}/20  [{cat_bar}]{suffix}")

    # Severity counts
    severity_counts: dict[str, int] = {}
    for attr in attributes:
        sev = attr.get("severity", "info")
        severity_counts[sev] = severity_counts.get(sev, 0) + 1

    if severity_counts:
        parts = []
        for sev in ("critical", "high", "medium", "low", "info"):
            count = severity_counts.get(sev, 0)
            if count:
                parts.append(f"{sev.title()}: {count}")
        lines.extend(["", "  " + "  ".join(parts)])

    # Findings grouped by severity
    for sev in ("critical", "high", "medium", "low"):
        sev_attrs = [a for a in attributes if a.get("severity") == sev]
        if sev_attrs:
            icon = "\u26a0" if sev in ("critical", "high") else "\u25b2" if sev == "medium" else "\u25cb"
            lines.append("")
            lines.append(f"  {icon} {sev.title()} ({len(sev_attrs)})")
            for attr in sev_attrs:
                cat = attr.get("category", "?")
                desc = attr.get("description", "")
                auto = ""
                actions = attr.get("actions", [])
                if actions and actions[0].get("auto_fixable"):
                    auto = " [auto-fixable]"
                lines.append(f"    {cat}: {desc}{auto}")

    return "\n".join(lines)


def format_routing_instructions(
    priorities: list[tuple[str, int, list[str]]],
) -> str:
    """Format routing priorities as instructions for the orchestrator prompt."""
    if not priorities:
        return (
            "## Attribute-Based Routing\n\n"
            "No findings require agent intervention. All categories are healthy."
        )

    lines = [
        "## Attribute-Based Routing",
        "",
        "Based on attribute analysis, prioritize these agents in order:",
        "",
    ]
    for i, (agent, score, findings) in enumerate(priorities, 1):
        finding_summary = "; ".join(findings[:3])
        if len(findings) > 3:
            finding_summary += f" (+{len(findings) - 3} more)"
        lines.append(f"{i}. **{agent}** (priority {score}): {finding_summary}")

    lines.extend([
        "",
        "For each finding, the suggested action and auto-fixability are listed "
        "in the attributes JSON above.",
    ])
    return "\n".join(lines)


@tool(
    "codebase_attributes",
    "Collect structured codebase health attributes with severity and remediation actions. "
    "Returns attributes with category, severity, and suggested agent actions. "
    "Use this for data-driven agent routing.",
    {"path": str, "format": str},
)
async def codebase_attributes(args: dict[str, Any]) -> dict[str, Any]:
    """MCP tool handler for codebase attribute collection."""
    repo_path = Path(args["path"]).resolve()
    if not repo_path.is_dir():
        return {
            "content": [
                {
                    "type": "text",
                    "text": f"Error: {repo_path} is not a valid directory",
                }
            ]
        }

    data = collect_attributes(repo_path)
    fmt = args.get("format", "json")

    if fmt == "terminal":
        text = format_attributes_terminal(data)
    elif fmt == "routing":
        priorities = route_from_attributes(data["attributes"])
        text = format_routing_instructions(priorities)
    else:
        text = json.dumps(data, indent=2)

    return {
        "content": [
            {
                "type": "text",
                "text": text,
            }
        ]
    }

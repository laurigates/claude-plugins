"""Git worktree management for isolated agent work."""

import logging
import re
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)


def create_worktree(repo_path: Path, branch: str) -> Path:
    """Create a git worktree for isolated agent work.

    Args:
        repo_path: Path to the main repository.
        branch: Branch name to create in the worktree.

    Returns:
        Path to the new worktree directory.
    """
    worktree_path = repo_path / ".claude" / "worktrees" / branch.replace("/", "-")
    worktree_path.parent.mkdir(parents=True, exist_ok=True)

    # Get current branch to use as base
    base = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=repo_path,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()

    # Remove stale worktree if it exists
    if worktree_path.exists():
        subprocess.run(
            ["git", "worktree", "remove", "--force", str(worktree_path)],
            cwd=repo_path,
            capture_output=True,
            text=True,
        )

    # Delete the branch if it already exists (leftover from a previous run)
    subprocess.run(
        ["git", "branch", "-D", branch],
        cwd=repo_path,
        capture_output=True,
        text=True,
    )

    # Create worktree with new branch
    subprocess.run(
        ["git", "worktree", "add", "-b", branch, str(worktree_path), base],
        cwd=repo_path,
        capture_output=True,
        text=True,
        check=True,
    )

    logger.info("Created worktree at %s on branch %s (base: %s)", worktree_path, branch, base)
    return worktree_path


def worktree_has_changes(worktree_path: Path, base_branch: str | None = None) -> bool:
    """Check if the worktree has commits beyond the base branch.

    Falls back to checking for any uncommitted changes if base_branch
    detection fails.
    """
    if base_branch is None:
        # Detect the base branch from the worktree's upstream
        result = subprocess.run(
            ["git", "log", "--oneline", "HEAD", "--not", "--remotes", "-1"],
            cwd=worktree_path,
            capture_output=True,
            text=True,
        )
        return bool(result.stdout.strip())

    result = subprocess.run(
        ["git", "log", "--oneline", f"{base_branch}..HEAD"],
        cwd=worktree_path,
        capture_output=True,
        text=True,
    )
    return bool(result.stdout.strip())


def get_base_branch(repo_path: Path) -> str:
    """Get the current branch of the main repo (used as base for worktree)."""
    return subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=repo_path,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def push_and_create_pr(
    worktree_path: Path,
    branch: str,
    base_branch: str,
    title: str,
    body: str,
) -> str | None:
    """Push the worktree branch and create a PR.

    Returns the PR URL on success, None on failure.
    """
    # Push the branch
    result = subprocess.run(
        ["git", "push", "-u", "origin", branch],
        cwd=worktree_path,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        logger.error("Failed to push branch: %s", result.stderr)
        return None

    # Create PR
    result = subprocess.run(
        [
            "gh", "pr", "create",
            "--title", title,
            "--body", body,
            "--base", base_branch,
            "--head", branch,
        ],
        cwd=worktree_path,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        logger.error("Failed to create PR: %s", result.stderr)
        return None

    return result.stdout.strip()


def cleanup_worktree(repo_path: Path, worktree_path: Path) -> None:
    """Remove a git worktree."""
    subprocess.run(
        ["git", "worktree", "remove", "--force", str(worktree_path)],
        cwd=repo_path,
        capture_output=True,
        text=True,
    )
    logger.info("Cleaned up worktree at %s", worktree_path)


def create_github_issues(
    repo_path: Path,
    findings: list[dict[str, str]],
) -> list[str]:
    """Create GitHub issues from a list of findings.

    Each finding dict should have 'title' and 'body' keys,
    and optionally 'labels'.

    Returns list of created issue URLs.
    """
    urls = []
    for finding in findings:
        cmd = [
            "gh", "issue", "create",
            "--title", finding["title"],
            "--body", finding["body"],
        ]
        if finding.get("labels"):
            cmd.extend(["--label", finding["labels"]])

        result = subprocess.run(
            cmd,
            cwd=repo_path,
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            urls.append(result.stdout.strip())
        else:
            logger.error("Failed to create issue '%s': %s", finding["title"], result.stderr)

    return urls


def parse_report_only_findings(agent_output: str) -> list[dict[str, str]]:
    """Parse numbered findings marked as report-only from agent output.

    Looks for lines matching the pattern:
        N. [category] description — report-only

    Returns list of dicts with 'title', 'body', and 'labels' keys.
    """
    findings = []
    # Match lines like: 1. [security] Dependency has known CVE — report-only
    pattern = re.compile(
        r"^\d+\.\s+\[(\w+(?:[/-]\w+)*)\]\s+(.+?)\s*[—–-]\s*report[- ]only\s*$",
        re.MULTILINE | re.IGNORECASE,
    )
    for match in pattern.finditer(agent_output):
        category = match.group(1)
        description = match.group(2).strip()
        findings.append({
            "title": f"[{category}] {description}",
            "body": (
                f"**Category:** {category}\n\n"
                f"**Finding:** {description}\n\n"
                f"*Created by git-repo-agent maintain --report-only*"
            ),
            "labels": category,
        })
    return findings

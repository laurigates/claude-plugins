"""Git worktree management for isolated agent work."""

import errno
import json
import logging
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger(__name__)


def timestamped_branch(prefix: str) -> str:
    """Return a UTC-timestamped branch name under ``prefix``.

    Used by non-interactive runs so repeated scheduled invocations do not
    collide on e.g. ``maintain/2026-04-14``.
    """
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M")
    return f"{prefix}/{stamp}"


_LOCK_RELATIVE = Path(".claude") / "worktrees" / ".git-repo-agent.lock"


def acquire_lock(repo_path: Path) -> Path | None:
    """Acquire an advisory lock for a non-interactive run.

    Writes PID + ISO-8601 start time to ``.claude/worktrees/.git-repo-agent.lock``
    via ``O_CREAT | O_EXCL``. Returns the lock path on success, ``None`` if
    a live lock is already held. Stale locks (holder process gone) are
    reclaimed automatically.
    """
    lock_path = repo_path / _LOCK_RELATIVE
    lock_path.parent.mkdir(parents=True, exist_ok=True)

    payload = json.dumps(
        {"pid": os.getpid(), "started_at": datetime.now(timezone.utc).isoformat()}
    ).encode()

    try:
        fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
    except FileExistsError:
        # Check liveness of the existing holder.
        try:
            existing = json.loads(lock_path.read_text(encoding="utf-8"))
            pid = int(existing.get("pid", 0))
        except (ValueError, OSError):
            pid = 0
        if pid > 0 and _pid_alive(pid):
            return None
        # Stale — remove and retry once.
        try:
            lock_path.unlink()
        except FileNotFoundError:
            pass
        try:
            fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        except FileExistsError:
            return None

    with os.fdopen(fd, "wb") as f:
        f.write(payload)
    return lock_path


def release_lock(lock_path: Path | None) -> None:
    """Remove the advisory lock file. Safe to call with ``None``."""
    if lock_path is None:
        return
    try:
        lock_path.unlink()
    except FileNotFoundError:
        pass
    except OSError as exc:
        logger.warning("Failed to release lock %s: %s", lock_path, exc)


def _pid_alive(pid: int) -> bool:
    """True if ``pid`` is a live process we can see."""
    try:
        os.kill(pid, 0)
    except OSError as exc:
        return exc.errno == errno.EPERM
    return True


def refresh_base(repo_path: Path, base_branch: str) -> bool:
    """Fetch the remote and fast-forward the local base branch.

    Returns True on success, False on any failure (network, no remote,
    non-fast-forward, etc.). Non-fatal: scheduled runs should log and
    continue on stale base if the fetch fails.
    """
    fetch = subprocess.run(
        ["git", "fetch", "origin", base_branch],
        cwd=repo_path,
        capture_output=True,
        text=True,
    )
    if fetch.returncode != 0:
        logger.warning("git fetch origin %s failed: %s", base_branch, fetch.stderr.strip())
        return False
    # Only fast-forward if the local branch is checked out and behind.
    current = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=repo_path,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if current != base_branch:
        return True  # fetch is enough; worktree base will come from origin/<base>
    ff = subprocess.run(
        ["git", "merge", "--ff-only", f"origin/{base_branch}"],
        cwd=repo_path,
        capture_output=True,
        text=True,
    )
    if ff.returncode != 0:
        logger.warning("Non-fast-forward refresh of %s: %s", base_branch, ff.stderr.strip())
        return False
    return True


def find_existing_pr(
    repo_path: Path,
    branch_prefix: str,
    base_branch: str,
) -> str | None:
    """Return the URL of an open PR whose head branch starts with ``branch_prefix``.

    Used by non-interactive runs to dedupe scheduled PRs. Returns None if
    ``gh`` is unavailable, auth fails, or no match is found.
    """
    result = subprocess.run(
        [
            "gh", "pr", "list",
            "--state", "open",
            "--base", base_branch,
            "--json", "url,headRefName",
            "--limit", "100",
        ],
        cwd=repo_path,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        logger.debug("gh pr list failed: %s", result.stderr.strip())
        return None
    try:
        prs = json.loads(result.stdout or "[]")
    except json.JSONDecodeError:
        return None
    for pr in prs:
        head = pr.get("headRefName", "")
        if head == branch_prefix or head.startswith(f"{branch_prefix}/"):
            return pr.get("url")
    return None


def find_existing_issue(repo_path: Path, title: str) -> str | None:
    """Return the URL of an open issue with an exact matching title.

    Used to dedupe report-only findings across scheduled runs.
    """
    result = subprocess.run(
        [
            "gh", "issue", "list",
            "--state", "open",
            "--search", f'in:title "{title}"',
            "--json", "url,title",
            "--limit", "50",
        ],
        cwd=repo_path,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        logger.debug("gh issue list failed: %s", result.stderr.strip())
        return None
    try:
        issues = json.loads(result.stdout or "[]")
    except json.JSONDecodeError:
        return None
    for issue in issues:
        if issue.get("title") == title:
            return issue.get("url")
    return None


def gh_auth_ok(repo_path: Path) -> bool:
    """Check that ``gh`` is authenticated. Fast fail for scheduled runs."""
    result = subprocess.run(
        ["gh", "auth", "status"],
        cwd=repo_path,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


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

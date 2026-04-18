#!/usr/bin/env python3
"""Open one PR per target repo with the friction-learner's proposed rules.

Consumes the JSON output of friction_cluster.py and the rendered PR body, then
per target repo:

    1. Clones into a temp workdir (or reuses an existing checkout in --cache-dir)
    2. Writes each actionable cluster's proposal to its target path
    3. Creates or updates branch ``friction/YYYY-WW-<repo_slug>``
    4. Commits the changes (one commit per run)
    5. Pushes the branch with --force-with-lease
    6. Opens or updates a draft PR via ``gh pr create``/``gh pr edit``

Usage::

    friction_open_prs.py \
        --clusters /tmp/clusters.json \
        --pr-body  /tmp/pr-body.md \
        --target-repo laurigates/claude-plugins \
        --target-repo laurigates/rulesync \
        --dry-run

Guardrails (mirrors ``feedback-plugin/agents/friction-learner.md``):

- Quiet-window check: if the clusters file reports fewer than
  ``--min-total-events`` (default 5) events, print a summary and do nothing.
- One PR per target repo: the branch name is deterministic, so repeat runs
  amend the existing branch/PR instead of spamming new ones.
- Never auto-merge; PRs are always opened as drafts.
- Redaction is handled upstream in ``friction_parse.py``; this script only
  writes what the clusterer produced.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

REPO_SLUG_RE = re.compile(r"([^/:]+/[^/:.]+?)(?:\.git)?$")


def repo_slug(target: str) -> str:
    """Normalize a URL or slug to ``owner/repo``."""
    m = REPO_SLUG_RE.search(target.strip())
    if not m:
        raise ValueError(f"cannot parse repo slug from: {target}")
    return m.group(1)


def repo_short(slug: str) -> str:
    """``owner/name`` -> ``name`` (the suffix used in branch names)."""
    return slug.split("/", 1)[-1]


def iso_week_tag(now: datetime | None = None) -> str:
    now = now or datetime.now(tz=timezone.utc)
    return now.strftime("%G-W%V")


def run(cmd: list[str], *, cwd: Path | None = None, check: bool = True,
        capture: bool = False) -> subprocess.CompletedProcess:
    kwargs: dict = {"cwd": str(cwd) if cwd else None}
    if capture:
        kwargs.update(stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return subprocess.run(cmd, check=check, **kwargs)


def ensure_gh_available() -> None:
    if shutil.which("gh") is None:
        sys.stderr.write("error: gh CLI not found on PATH; cannot open PRs\n")
        sys.exit(2)


def clone_or_reuse(slug: str, cache_dir: Path | None) -> Path:
    """Clone ``slug`` into cache_dir or a fresh tempdir; return the checkout."""
    if cache_dir is not None:
        target = cache_dir / slug.replace("/", "__")
        if target.exists() and (target / ".git").exists():
            run(["git", "fetch", "--prune", "origin"], cwd=target)
            return target
        target.parent.mkdir(parents=True, exist_ok=True)
        run(["gh", "repo", "clone", slug, str(target), "--", "--depth=50"])
        return target

    tmp = Path(tempfile.mkdtemp(prefix="friction-learner-"))
    target = tmp / repo_short(slug)
    run(["gh", "repo", "clone", slug, str(target), "--", "--depth=50"])
    return target


def resolve_default_branch(checkout: Path) -> str:
    res = run(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
              cwd=checkout, check=False, capture=True)
    if res.returncode == 0 and res.stdout.strip():
        return res.stdout.strip().split("/", 1)[-1]
    # Fallback: ask gh.
    res = run(["gh", "repo", "view", "--json", "defaultBranchRef", "-q",
               ".defaultBranchRef.name"], cwd=checkout, capture=True)
    name = res.stdout.strip()
    return name or "main"


def checkout_branch(checkout: Path, branch: str, base: str) -> None:
    # If the branch already exists on origin, reset to its tip; otherwise
    # branch off the base.
    remote = run(["git", "ls-remote", "--heads", "origin", branch],
                 cwd=checkout, capture=True, check=False)
    if remote.stdout.strip():
        run(["git", "fetch", "origin", f"{branch}:{branch}"],
            cwd=checkout, check=False)
        run(["git", "checkout", branch], cwd=checkout)
    else:
        run(["git", "checkout", "-B", branch, f"origin/{base}"], cwd=checkout)


def write_proposals(checkout: Path, clusters: dict) -> list[Path]:
    """Write each actionable proposal to its target path. Return written paths."""
    written: list[Path] = []
    for proposal in clusters.get("actionable", []):
        rel_path = proposal.get("path")
        body = proposal.get("body")
        if not rel_path or not body:
            continue
        dest = checkout / rel_path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(body, encoding="utf-8")
        written.append(dest)
    return written


def stage_and_commit(checkout: Path, week_tag: str, dry_run: bool) -> bool:
    run(["git", "add", "-A"], cwd=checkout)
    diff = run(["git", "diff", "--cached", "--name-only"],
               cwd=checkout, capture=True)
    if not diff.stdout.strip():
        return False
    msg = f"docs(rules): add friction-learner findings for week {week_tag}"
    if dry_run:
        sys.stderr.write(f"[dry-run] would commit: {msg}\n")
        sys.stderr.write(diff.stdout)
        return True
    run(["git", "commit", "-m", msg], cwd=checkout)
    return True


def push_branch(checkout: Path, branch: str, dry_run: bool) -> None:
    if dry_run:
        sys.stderr.write(f"[dry-run] would push: {branch}\n")
        return
    run(["git", "push", "--force-with-lease", "-u", "origin", branch],
        cwd=checkout)


def open_or_update_pr(checkout: Path, slug: str, branch: str, base: str,
                      title: str, body_path: Path, dry_run: bool) -> str:
    existing = run(["gh", "pr", "list", "--repo", slug, "--head", branch,
                    "--state", "open", "--json", "number,url",
                    "--jq", ".[0]"],
                   cwd=checkout, capture=True, check=False)
    existing_json = existing.stdout.strip()
    if existing_json:
        info = json.loads(existing_json)
        url = info.get("url", "")
        if dry_run:
            sys.stderr.write(f"[dry-run] would update PR {url}\n")
            return url
        run(["gh", "pr", "edit", str(info["number"]), "--repo", slug,
             "--title", title, "--body-file", str(body_path)],
            cwd=checkout)
        return url

    if dry_run:
        sys.stderr.write(f"[dry-run] would create draft PR on {slug} from {branch} -> {base}\n")
        return ""
    res = run(["gh", "pr", "create", "--repo", slug, "--draft",
               "--base", base, "--head", branch,
               "--title", title, "--body-file", str(body_path)],
              cwd=checkout, capture=True)
    return res.stdout.strip()


def process_repo(slug: str, clusters: dict, pr_body: Path, week_tag: str,
                 branch_template: str, cache_dir: Path | None,
                 dry_run: bool) -> dict:
    checkout = clone_or_reuse(slug, cache_dir)
    base = resolve_default_branch(checkout)
    branch = branch_template.format(iso_week=week_tag, repo_slug=repo_short(slug))
    checkout_branch(checkout, branch, base)

    written = write_proposals(checkout, clusters)
    if not written:
        return {"repo": slug, "branch": branch, "pr_url": "",
                "status": "no-proposals"}

    if not stage_and_commit(checkout, week_tag, dry_run):
        return {"repo": slug, "branch": branch, "pr_url": "",
                "status": "no-changes"}

    push_branch(checkout, branch, dry_run)
    title = f"docs(rules): add friction-learner findings for week {week_tag}"
    pr_url = open_or_update_pr(checkout, slug, branch, base, title, pr_body, dry_run)
    return {"repo": slug, "branch": branch, "pr_url": pr_url,
            "status": "dry-run" if dry_run else "opened"}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--clusters", required=True, help="Path to clusters.json")
    ap.add_argument("--pr-body", required=True, help="Path to rendered PR body markdown")
    ap.add_argument("--target-repo", action="append", default=[], required=True,
                    help="Target repo (owner/repo or URL). Repeatable.")
    ap.add_argument("--branch-template", default="friction/{iso_week}-{repo_slug}")
    ap.add_argument("--cache-dir", default="",
                    help="Optional directory to cache clones between runs")
    ap.add_argument("--min-total-events", type=int, default=5,
                    help="Skip entirely if clusters.total_events is below this")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    clusters_path = Path(args.clusters)
    pr_body_path = Path(args.pr_body)
    if not clusters_path.exists():
        sys.stderr.write(f"error: clusters file not found: {clusters_path}\n")
        return 2
    if not pr_body_path.exists():
        sys.stderr.write(f"error: pr body file not found: {pr_body_path}\n")
        return 2

    clusters = json.loads(clusters_path.read_text(encoding="utf-8"))
    total_events = clusters.get("total_events", 0)
    if total_events < args.min_total_events:
        sys.stderr.write(
            f"quiet window: {total_events} event(s) < {args.min_total_events}; "
            "skipping PR creation\n"
        )
        return 0
    if not clusters.get("actionable"):
        sys.stderr.write("no actionable clusters; skipping PR creation\n")
        return 0

    if not args.dry_run:
        ensure_gh_available()

    cache_dir = Path(args.cache_dir) if args.cache_dir else None
    if cache_dir is not None:
        cache_dir.mkdir(parents=True, exist_ok=True)

    week_tag = iso_week_tag()
    results: list[dict] = []
    for target in args.target_repo:
        try:
            slug = repo_slug(target)
        except ValueError as err:
            sys.stderr.write(f"error: {err}\n")
            results.append({"repo": target, "branch": "", "pr_url": "",
                            "status": f"error:{err}"})
            continue
        try:
            results.append(process_repo(
                slug, clusters, pr_body_path, week_tag,
                args.branch_template, cache_dir, args.dry_run,
            ))
        except subprocess.CalledProcessError as err:
            results.append({"repo": slug, "branch": "", "pr_url": "",
                            "status": f"error:exit-{err.returncode}"})

    json.dump({"week": week_tag, "results": results}, sys.stdout, indent=2)
    sys.stdout.write("\n")
    failed = any(r["status"].startswith("error") for r in results)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

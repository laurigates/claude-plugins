"""pipeline_collector — pre-compute GitOps pipeline diagnostics from CLI sources.

Collects read-only diagnostic snapshots from kubectl, argocd, and GitHub CLI
before the agent session starts. Each collector runs a subprocess with a timeout,
returns structured data, and handles missing tools gracefully.
"""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path
from typing import Any

# Maximum items to include per source to keep prompt size reasonable
_MAX_EVENTS = 20
_MAX_WORKFLOW_RUNS = 10
_MAX_LOG_LINES = 50
_SUBPROCESS_TIMEOUT = 10  # seconds

# Patterns for values that should be redacted
_SECRET_KEY_PATTERNS = re.compile(
    r"(password|token|secret|key|credential|auth)(?!_?name|_?type|_?id|_?path)",
    re.IGNORECASE,
)


def _run_cmd(
    cmd: list[str],
    *,
    timeout: int = _SUBPROCESS_TIMEOUT,
    cwd: Path | None = None,
) -> tuple[bool, str]:
    """Run a command and return (success, output)."""
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=cwd,
        )
        if result.returncode == 0:
            return True, result.stdout.strip()
        return False, result.stderr.strip() or f"exit code {result.returncode}"
    except FileNotFoundError:
        return False, "command not found"
    except subprocess.TimeoutExpired:
        return False, f"timed out after {timeout}s"
    except OSError as exc:
        return False, str(exc)


def _redact_secrets(data: Any) -> Any:
    """Recursively redact values whose keys match secret patterns."""
    if isinstance(data, dict):
        return {
            k: "***REDACTED***" if _SECRET_KEY_PATTERNS.search(k) else _redact_secrets(v)
            for k, v in data.items()
        }
    if isinstance(data, list):
        return [_redact_secrets(item) for item in data]
    return data


def _parse_json_output(output: str) -> Any:
    """Parse JSON output, returning None on failure."""
    try:
        return json.loads(output)
    except (json.JSONDecodeError, ValueError):
        return None


def _detect_available_sources() -> list[str]:
    """Detect which diagnostic CLI tools are available."""
    available = []

    ok, _ = _run_cmd(["which", "kubectl"])
    if ok:
        available.append("kubectl")

    ok, _ = _run_cmd(["which", "argocd"])
    if ok:
        available.append("argocd")

    ok, _ = _run_cmd(["gh", "auth", "status"])
    if ok:
        available.extend(["actions", "packages"])

    return available


def _collect_kubectl(namespace: str | None) -> dict[str, Any]:
    """Collect pod status and recent events from kubectl."""
    ns_args = ["--namespace", namespace] if namespace else ["--all-namespaces"]
    result: dict[str, Any] = {"status": "ok", "data": {}}

    # Pod status
    ok, output = _run_cmd(
        ["kubectl", "get", "pods", *ns_args, "-o", "json"],
        timeout=15,
    )
    if ok:
        parsed = _parse_json_output(output)
        if parsed:
            pods = parsed.get("items", [])
            # Summarise: name, namespace, phase, restarts, conditions
            pod_summaries = []
            for pod in pods:
                metadata = pod.get("metadata", {})
                status = pod.get("status", {})
                containers = status.get("containerStatuses", [])
                restart_count = sum(c.get("restartCount", 0) for c in containers)
                pod_summaries.append({
                    "name": metadata.get("name"),
                    "namespace": metadata.get("namespace"),
                    "phase": status.get("phase"),
                    "restart_count": restart_count,
                    "ready": all(c.get("ready", False) for c in containers) if containers else False,
                    "conditions": [
                        {"type": c.get("type"), "status": c.get("status")}
                        for c in status.get("conditions", [])
                        if c.get("status") != "True"
                    ],
                })
            result["data"]["pods"] = pod_summaries
    else:
        result["data"]["pods_error"] = output

    # Recent events (errors and warnings only)
    ok, output = _run_cmd(
        [
            "kubectl", "get", "events", *ns_args,
            "--sort-by=.lastTimestamp",
            "--field-selector=type!=Normal",
            "-o", "json",
        ],
        timeout=15,
    )
    if ok:
        parsed = _parse_json_output(output)
        if parsed:
            events = parsed.get("items", [])[-_MAX_EVENTS:]
            result["data"]["events"] = [
                {
                    "type": e.get("type"),
                    "reason": e.get("reason"),
                    "message": e.get("message", "")[:200],
                    "involved_object": e.get("involvedObject", {}).get("name"),
                    "last_timestamp": e.get("lastTimestamp"),
                    "count": e.get("count"),
                }
                for e in events
            ]
    else:
        result["data"]["events_error"] = output

    return _redact_secrets(result)


def _collect_argocd(app_name: str | None, namespace: str | None) -> dict[str, Any]:
    """Collect ArgoCD application status and history."""
    result: dict[str, Any] = {"status": "ok", "data": {}}

    if app_name:
        # Specific app status
        ok, output = _run_cmd(
            ["argocd", "app", "get", app_name, "-o", "json"],
            timeout=15,
        )
        if ok:
            parsed = _parse_json_output(output)
            if parsed:
                status = parsed.get("status", {})
                result["data"]["app"] = {
                    "name": parsed.get("metadata", {}).get("name"),
                    "sync_status": status.get("sync", {}).get("status"),
                    "health_status": status.get("health", {}).get("status"),
                    "sync_revision": status.get("sync", {}).get("revision"),
                    "conditions": status.get("conditions", []),
                    "resources_summary": _summarise_argocd_resources(
                        status.get("resources", [])
                    ),
                }
        else:
            result["data"]["app_error"] = output

        # App history
        ok, output = _run_cmd(
            ["argocd", "app", "history", app_name, "-o", "json"],
            timeout=15,
        )
        if ok:
            parsed = _parse_json_output(output)
            if parsed and isinstance(parsed, list):
                result["data"]["history"] = parsed[-5:]  # last 5 deployments
        else:
            result["data"]["history_error"] = output
    else:
        # List all apps
        ok, output = _run_cmd(
            ["argocd", "app", "list", "-o", "json"],
            timeout=15,
        )
        if ok:
            parsed = _parse_json_output(output)
            if parsed and isinstance(parsed, list):
                result["data"]["apps"] = [
                    {
                        "name": a.get("metadata", {}).get("name"),
                        "sync_status": a.get("status", {}).get("sync", {}).get("status"),
                        "health_status": a.get("status", {}).get("health", {}).get("status"),
                    }
                    for a in parsed
                ]
        else:
            result["data"]["apps_error"] = output

    return _redact_secrets(result)


def _summarise_argocd_resources(resources: list[dict]) -> dict[str, int]:
    """Summarise ArgoCD resource sync/health counts."""
    summary: dict[str, int] = {
        "total": len(resources),
        "synced": 0,
        "out_of_sync": 0,
        "healthy": 0,
        "degraded": 0,
        "missing": 0,
    }
    for r in resources:
        sync = r.get("status")
        health = r.get("health", {}).get("status") if isinstance(r.get("health"), dict) else None
        if sync == "Synced":
            summary["synced"] += 1
        elif sync == "OutOfSync":
            summary["out_of_sync"] += 1
        if health == "Healthy":
            summary["healthy"] += 1
        elif health == "Degraded":
            summary["degraded"] += 1
        elif health == "Missing":
            summary["missing"] += 1
    return summary


def _collect_gh_actions(repo_path: Path) -> dict[str, Any]:
    """Collect recent GitHub Actions workflow runs and failure details."""
    result: dict[str, Any] = {"status": "ok", "data": {}}

    # Recent runs
    ok, output = _run_cmd(
        [
            "gh", "run", "list",
            "--limit", str(_MAX_WORKFLOW_RUNS),
            "--json", "databaseId,status,conclusion,name,headBranch,url,createdAt",
        ],
        cwd=repo_path,
        timeout=15,
    )
    if not ok:
        return {"status": "error", "message": output}

    runs = _parse_json_output(output)
    if not runs:
        return {"status": "error", "message": "failed to parse workflow runs"}

    result["data"]["runs"] = runs

    # Get details for failed runs
    failed_runs = [r for r in runs if r.get("conclusion") == "failure"]
    failed_details = []
    for run in failed_runs[:3]:  # limit to 3 most recent failures
        run_id = run.get("databaseId")
        if not run_id:
            continue
        ok, detail_output = _run_cmd(
            ["gh", "run", "view", str(run_id), "--json", "jobs"],
            cwd=repo_path,
            timeout=15,
        )
        if ok:
            detail = _parse_json_output(detail_output)
            if detail:
                jobs = detail.get("jobs", [])
                failed_jobs = [
                    {
                        "name": j.get("name"),
                        "conclusion": j.get("conclusion"),
                        "steps": [
                            {
                                "name": s.get("name"),
                                "conclusion": s.get("conclusion"),
                            }
                            for s in j.get("steps", [])
                            if s.get("conclusion") == "failure"
                        ],
                    }
                    for j in jobs
                    if j.get("conclusion") == "failure"
                ]
                if failed_jobs:
                    failed_details.append({
                        "run_id": run_id,
                        "name": run.get("name"),
                        "url": run.get("url"),
                        "failed_jobs": failed_jobs,
                    })

    result["data"]["failed_details"] = failed_details
    return result


def _collect_gh_packages(repo_path: Path) -> dict[str, Any]:
    """Collect GitHub Packages information."""
    result: dict[str, Any] = {"status": "ok", "data": {}}

    # Get repo info for the API call
    ok, output = _run_cmd(
        ["gh", "repo", "view", "--json", "owner,name"],
        cwd=repo_path,
        timeout=10,
    )
    if not ok:
        return {"status": "error", "message": output}

    repo_info = _parse_json_output(output)
    if not repo_info:
        return {"status": "error", "message": "failed to parse repo info"}

    owner = repo_info.get("owner", {}).get("login", "")
    repo_name = repo_info.get("name", "")

    # List packages
    ok, output = _run_cmd(
        ["gh", "api", f"/repos/{owner}/{repo_name}/packages?package_type=container"],
        cwd=repo_path,
        timeout=15,
    )
    if ok:
        packages = _parse_json_output(output)
        if packages and isinstance(packages, list):
            result["data"]["packages"] = [
                {
                    "name": p.get("name"),
                    "package_type": p.get("package_type"),
                    "visibility": p.get("visibility"),
                    "created_at": p.get("created_at"),
                    "updated_at": p.get("updated_at"),
                }
                for p in packages
            ]
        elif packages and isinstance(packages, dict) and packages.get("message"):
            result["data"]["packages_note"] = packages["message"]
    else:
        result["data"]["packages_error"] = output

    return result


def collect_pipeline_diagnostics(
    repo_path: Path,
    sources: list[str] | None = None,
    namespace: str | None = None,
    app_name: str | None = None,
) -> dict[str, Any]:
    """Pre-compute pipeline diagnostics from available CLI sources.

    Args:
        repo_path: Path to the repository.
        sources: Requested diagnostic sources (None = auto-detect).
        namespace: Kubernetes namespace for kubectl/argocd.
        app_name: ArgoCD application name.

    Returns:
        Dictionary with per-source diagnostic data.
    """
    available = _detect_available_sources()
    requested = sources or available
    results: dict[str, Any] = {
        "available_sources": available,
        "requested_sources": sources,
    }

    if "kubectl" in requested and "kubectl" in available:
        results["kubectl"] = _collect_kubectl(namespace)
    elif "kubectl" in requested:
        results["kubectl"] = {"status": "unavailable", "message": "kubectl not found"}

    if "argocd" in requested and "argocd" in available:
        results["argocd"] = _collect_argocd(app_name, namespace)
    elif "argocd" in requested:
        results["argocd"] = {"status": "unavailable", "message": "argocd not found"}

    if "actions" in requested and "actions" in available:
        results["github_actions"] = _collect_gh_actions(repo_path)
    elif "actions" in requested:
        results["github_actions"] = {"status": "unavailable", "message": "gh CLI not authenticated"}

    if "packages" in requested and "packages" in available:
        results["github_packages"] = _collect_gh_packages(repo_path)
    elif "packages" in requested:
        results["github_packages"] = {"status": "unavailable", "message": "gh CLI not authenticated"}

    return results

#!/usr/bin/env python3
"""Cluster friction events and propose concrete fixes.

Input:  JSONL of events from friction_parse.py (stdin or --in)
Output: JSON clusters with proposed deliverable + rendered rule body

Usage:
    friction_cluster.py --in frictions.jsonl --min-count 3 --out clusters.json
    friction_cluster.py --in frictions.jsonl --min-count 3 --render-pr-body out.md

Deliverable mapping:
    hook:*                  -> rule edit documenting the block + the correct workflow
    push:*                  -> hook adjustment (pre-push PR check) + rule
    plan:entered-plan-mode  -> classify-required: surface samples for human review
    reject:exitplanmode     -> classify-required: surface samples for human review
    error:Bash:*            -> skill patch (quick reference flag or note)
    reject:*                -> watch (rejection cause is ambiguous without sampling)
    interrupt:*             -> summary only (usually not actionable)
    stop:*, hook-feedback:*, hook-error:*
                            -> watch: reported for prevalence, never prescribed; the
                               fix lives in the emitting hook (e.g. #2652). See #2659.

Build share (#3220): every run also reports, per plugin, the share of
build-stamped hook blocks (the `plugin`/`version` fields friction_parse.py
reads off the harness wrapper path) per version, with the current release
marked. It is `build_share` in the JSON and the standing `## Build share`
section of the PR body. The current release is the user-scope version in
`--installed-plugins`, or `--current-version PLUGIN=VERSION`.

`classify-required` clusters are reported in the PR body with sample evidence
so a human can decide which (if any) rule is justified. They never write a
committed file or auto-prescribe a fix. See issue #1110.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

_CLASSIFY_BODIES = {
    "plan:entered-plan-mode": """\
The parser flagged __COUNT__ ExitPlanMode entries where the preceding user
prompt did not contain an edit verb. The Q&A heuristic produces false
positives (feature-shaped prompts without explicit verbs look identical to
questions), so this cluster alone does not justify a rule.

| Classification | Suggested follow-up |
|---|---|
| Q&A misfire (user wanted an inline answer) | Rule edit: "don't enter plan mode for conceptual Q&A" |
| Parser false positive (legitimate plan, no edit verb) | Tighten `classify_plan_mode` in `friction_parse.py` |
| Plan was OK but rejected for scope/quality | Address via the `reject:exitplanmode` cluster, not here |

Cross-reference with the `reject:exitplanmode` rejection samples before
choosing any deliverable. Mixed distributions are watch-only.
""",
    "reject:exitplanmode": """\
The user rejected __COUNT__ ExitPlanMode tool calls. Plan-mode rejections
have several distinct causes; the friction-learner does NOT prescribe a
fix until a human samples the evidence and classifies the dominant pattern.

| Classification | Suggested follow-up |
|---|---|
| Plan scope too broad / too detailed | Output-style rule: keep plans short |
| Wrong approach proposed | Not actionable via rule (model judgment) |
| User wanted an inline answer (no plan) | Rule edit: "don't enter plan mode for conceptual Q&A" |
| User changed direction mid-flight | Not actionable |

If ≥50% of the sample falls into one bucket, file a follow-up PR with the
matching deliverable. Mixed distributions are watch-only.
""",
}

_CLASSIFY_TITLES = {
    "plan:entered-plan-mode": "Plan-mode entries — needs human classification",
    "reject:exitplanmode": "ExitPlanMode rejections — needs human classification",
}


DELIVERABLES = {
    "push:branch-has-open-pr": {
        "kind": "rule+hook",
        "path": "rules/claude/friction/push-to-pr-branch.md",
        "title": "Check for existing open PR before pushing to a shared branch",
        "body": """# Check for existing open PR before pushing to a shared branch

Pushing to a branch that already has an **open PR** can surprise reviewers and
retrigger CI. Before `git push`, verify whether the target branch has an open PR
and confirm the push is intended.

## Required pre-push check

```bash
target_branch=$(git rev-parse --abbrev-ref HEAD)
open_pr=$(gh pr list --head "$target_branch" --state open --json number --jq '.[0].number // empty')
if [ -n "$open_pr" ]; then
  echo "Branch '$target_branch' has open PR #$open_pr — confirm before pushing" >&2
fi
```

## Suggested hook

Add to `.claude/settings.json` under `hooks.PreToolUse`:

```json
{
  "matcher": "Bash",
  "hooks": [{
    "type": "command",
    "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/check-open-pr.sh"
  }]
}
```

The hook exits with code 2 when the push targets a branch with an open PR and
the commit message doesn't include `[force-push-ok]`.

## Evidence

__EVIDENCE__
""",
    },
}


def load_events(path: str) -> list[dict]:
    stream = sys.stdin if path == "-" else open(path, "r", encoding="utf-8")
    try:
        out = []
        for line in stream:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
        return out
    finally:
        if stream is not sys.stdin:
            stream.close()


def cluster(events: list[dict]) -> dict[str, list[dict]]:
    buckets: dict[str, list[dict]] = defaultdict(list)
    for ev in events:
        buckets[ev.get("signature", "unknown")].append(ev)
    return buckets


def version_key(version: str) -> tuple:
    """Sort key that orders 2.9.0 before 2.10.0; non-numeric parts sort last."""
    parts = []
    for piece in version.replace("-", ".").split("."):
        parts.append((0, int(piece), "") if piece.isdigit() else (1, 0, piece))
    return tuple(parts)


def current_versions(installed_path: str, overrides: list[str]) -> dict[str, str]:
    """Current release per plugin name.

    The user-scope entry of `installed_plugins.json` is the build a fresh
    project gets, so it stands for the current release (#3220). An explicit
    `--current-version PLUGIN=VERSION` wins over the file. A missing or
    unreadable file yields no entries, never an error: the row then reports the
    shares with no version marked current.
    """
    found: dict[str, str] = {}
    path = Path(installed_path).expanduser() if installed_path else None
    if path and path.is_file():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            data = {}
        for key, entries in (data.get("plugins") or {}).items():
            for entry in entries if isinstance(entries, list) else []:
                if isinstance(entry, dict) and entry.get("scope") == "user":
                    version = entry.get("version")
                    if version:
                        found[key.split("@", 1)[0]] = version
    for spec in overrides:
        plugin, sep, version = spec.partition("=")
        if not sep or not plugin or not version:
            raise SystemExit(f"--current-version expects PLUGIN=VERSION, got {spec!r}")
        found[plugin] = version
    return found


def build_share(events: list[dict], current: dict[str, str]) -> dict:
    """Per plugin, the share of build-stamped hook blocks that ran on each version.

    A fix that ships in a release only lowers a cluster once the release runs;
    project-scope installs pinned below the user-scope version keep firing the
    old build (#3220). The denominator is the plugin's stamped hook blocks, so
    unstamped blocks (no cache path in the wrapper) are counted separately and
    never diluted into a version's share.
    """
    blocks = [e for e in events if e.get("kind") == "hook_block"]
    per_plugin: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for ev in blocks:
        plugin, version = ev.get("plugin"), ev.get("version")
        if plugin and version:
            per_plugin[plugin][version] += 1
    plugins = []
    for plugin in sorted(per_plugin):
        counts = per_plugin[plugin]
        total = sum(counts.values())
        cur = current.get(plugin)
        plugins.append(
            {
                "plugin": plugin,
                "stamped_blocks": total,
                "current_version": cur,
                "current_share_pct": round(100.0 * counts.get(cur, 0) / total, 1)
                if cur
                else None,
                "versions": [
                    {
                        "version": version,
                        "count": counts[version],
                        "share_pct": round(100.0 * counts[version] / total, 1),
                        "current": version == cur,
                    }
                    for version in sorted(counts, key=version_key, reverse=True)
                ],
            }
        )
    return {
        "hook_blocks": len(blocks),
        "stamped_blocks": sum(p["stamped_blocks"] for p in plugins),
        "plugins": plugins,
    }


def render_build_share(share: dict) -> list[str]:
    """The standing build-share section of the PR body; rendered every run."""
    lines = [
        "## Build share",
        "",
        f"Build-stamped hook blocks: {share['stamped_blocks']} of "
        f"{share['hook_blocks']}. Share of each plugin's stamped blocks per "
        "version that ran; `(current)` marks the current release.",
        "",
    ]
    if not share["plugins"]:
        return lines + ["_No build-stamped hook blocks in the window._", ""]
    lines += ["| Plugin | Version | Blocks | Share |", "|---|---|---|---|"]
    for p in share["plugins"]:
        for v in p["versions"]:
            marker = " (current)" if v["current"] else ""
            lines.append(
                f"| `{p['plugin']}` | {v['version']}{marker} | {v['count']} | "
                f"{v['share_pct']:.1f}% |"
            )
        if p["current_version"] and not any(v["current"] for v in p["versions"]):
            lines.append(
                f"| `{p['plugin']}` | {p['current_version']} (current) | 0 | 0.0% |"
            )
    return lines + [""]


def propose(signature: str, hits: list[dict]) -> dict:
    spec = DELIVERABLES.get(signature)
    if spec is None:
        if signature in _CLASSIFY_BODIES:
            # Plan-mode clusters (entries and rejections) are not auto-prescribed.
            # The cause requires human sampling before a rule lands. See #1110.
            spec = {
                "kind": "classify-required",
                "path": "",
                "title": _CLASSIFY_TITLES[signature],
                "body": _CLASSIFY_BODIES[signature],
            }
        elif signature.startswith(("stop:", "hook-feedback:", "hook-error:")):
            # Hook output that is not a PreToolUse block (#2659). A rule file
            # cannot fix a noisy Stop hook; the hook itself has to change, so
            # these are measured (count, sessions, repeat_sessions) and never
            # prescribed. The explicit branch keeps them off the `hook:` path.
            spec = {
                "kind": "watch",
                "path": "",
                "title": f"Hook feedback: {signature}",
                "body": "",
            }
        elif signature.startswith("hook:"):
            spec = {
                "kind": "rule",
                "path": f"rules/claude/friction/{signature.replace(':', '-')}.md",
                "title": f"Workaround for {signature}",
                "body": f"# Workaround for {signature}\n\nObserved __COUNT__ times.\n\n__EVIDENCE__\n",
            }
        elif signature.startswith("error:"):
            spec = {
                "kind": "skill-patch",
                "path": f"notes/{signature.replace(':', '-')}.md",
                "title": f"Tool-error pattern: {signature}",
                "body": f"# {signature}\n\nObserved __COUNT__ times. Add the correct flag/pattern to the relevant skill Quick Reference table.\n\n__EVIDENCE__\n",
            }
        else:
            spec = {
                "kind": "watch",
                "path": "",
                "title": f"Watch: {signature}",
                "body": "",
            }
    evidence_block = "\n".join(
        f"- `{h.get('session', '?')[:8]}` at {h.get('ts', '?')}: {h.get('evidence', '')[:200].strip()}"
        for h in hits[:5]
    )
    rendered_body = (
        spec["body"]
        .replace("__COUNT__", str(len(hits)))
        .replace("__EVIDENCE__", evidence_block)
        if spec["body"]
        else ""
    )
    per_session: dict[str, int] = {}
    for h in hits:
        key = h.get("session") or ""
        per_session[key] = per_session.get(key, 0) + 1
    return {
        "signature": signature,
        "count": len(hits),
        # Prevalence and same-session repeat (#2659): distinct sessions the
        # cluster fired in, and how many of those it fired in more than once.
        "sessions": len(per_session),
        "repeat_sessions": sum(1 for n in per_session.values() if n > 1),
        "kind": spec["kind"],
        "path": spec["path"],
        "title": spec["title"],
        "body": rendered_body,
        "samples": [
            {
                "session": h.get("session"),
                "ts": h.get("ts"),
                "tool": h.get("tool"),
                "evidence": h.get("evidence"),
            }
            for h in hits[:3]
        ],
    }


def render_pr_body(
    proposals: list[dict],
    total_events: int,
    total_sessions: int,
    window: str,
    share: dict | None = None,
) -> str:
    week = datetime.now(tz=timezone.utc).strftime("%G-W%V")
    lines = [
        f"## Friction Report: {week}",
        "",
        f"- Window: {window}",
        f"- Sessions analyzed: {total_sessions}",
        f"- Friction events: {total_events}",
        f"- Actionable clusters: {sum(1 for p in proposals if p['kind'] != 'watch')}",
        "",
        # Sessions / Repeat sessions are prevalence and same-session repeat
        # (#2659): rendered here so the report carries them without the agent
        # having to copy them out of clusters.json.
        "| Cluster | Count | Sessions | Repeat sessions | Deliverable | Path |",
        "|---|---|---|---|---|---|",
    ]
    for p in sorted(proposals, key=lambda x: -x["count"]):
        lines.append(
            f"| `{p['signature']}` | {p['count']} | {p['sessions']} | "
            f"{p['repeat_sessions']} | {p['kind']} | `{p['path'] or '—'}` |"
        )
    lines += [""] + render_build_share(
        share or {"hook_blocks": 0, "stamped_blocks": 0, "plugins": []}
    )
    classify = [p for p in proposals if p["kind"] == "classify-required"]
    if classify:
        lines += [
            "",
            "## Needs human classification",
            "",
            "These clusters were observed often enough to be actionable, but the "
            "friction-learner does NOT prescribe a fix automatically. Sample the "
            "evidence below and decide which deliverable (if any) is justified.",
            "",
        ]
        for p in sorted(classify, key=lambda x: -x["count"]):
            lines += [
                f"### {p['title']} ({p['count']})",
                "",
                p["body"].rstrip(),
                "",
                "**Sample evidence:**",
                "",
            ]
            for sample in p.get("samples", []):
                ev = (sample.get("evidence") or "").strip().replace("\n", " ")
                if len(ev) > 200:
                    ev = ev[:200] + "…"
                lines.append(
                    f"- `{(sample.get('session') or '?')[:8]}` at "
                    f"{sample.get('ts', '?')}: {ev}"
                )
            lines.append("")
    lines += ["", "## Proposed changes", ""]
    proposed_changes = [
        p
        for p in proposals
        if p["kind"] not in ("watch", "classify-required") and p["body"] and p["path"]
    ]
    if not proposed_changes:
        lines += ["_No auto-prescribed changes this run._", ""]
    for p in proposed_changes:
        lines += [
            f"### {p['title']}",
            f"**File**: `{p['path']}`",
            "",
            "```markdown",
            p["body"].rstrip(),
            "```",
            "",
        ]
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="infile", default="-")
    ap.add_argument("--min-count", type=int, default=3)
    ap.add_argument("--out", default="-")
    ap.add_argument(
        "--render-pr-body",
        default="",
        help="Also write a PR body markdown to this path",
    )
    ap.add_argument("--window", default="7d")
    ap.add_argument(
        "--installed-plugins",
        default="~/.claude/plugins/installed_plugins.json",
        help="Registry whose user-scope versions mark the current release in "
        "the build-share row ('' to skip)",
    )
    ap.add_argument(
        "--current-version",
        action="append",
        default=[],
        metavar="PLUGIN=VERSION",
        help="Current release of a plugin; overrides --installed-plugins (repeatable)",
    )
    args = ap.parse_args()

    events = load_events(args.infile)
    share = build_share(
        events, current_versions(args.installed_plugins, args.current_version)
    )
    buckets = cluster(events)
    proposals_all = [propose(sig, hits) for sig, hits in buckets.items()]
    actionable = [p for p in proposals_all if p["count"] >= args.min_count]

    sessions = {e.get("session") for e in events}

    result = {
        "window": args.window,
        "total_events": len(events),
        "total_sessions": len(sessions),
        "min_count": args.min_count,
        "actionable": actionable,
        "watch": [p for p in proposals_all if p["count"] < args.min_count],
        "build_share": share,
    }

    out = sys.stdout if args.out == "-" else open(args.out, "w", encoding="utf-8")
    try:
        json.dump(result, out, indent=2, ensure_ascii=False)
        out.write("\n")
    finally:
        if out is not sys.stdout:
            out.close()

    if args.render_pr_body:
        body = render_pr_body(
            actionable, len(events), len(sessions), args.window, share
        )
        Path(args.render_pr_body).write_text(body, encoding="utf-8")
        sys.stderr.write(f"wrote PR body to {args.render_pr_body}\n")

    sys.stderr.write(
        f"events={len(events)} sessions={len(sessions)} clusters={len(buckets)} actionable={len(actionable)}\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

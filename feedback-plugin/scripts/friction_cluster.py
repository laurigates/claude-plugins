#!/usr/bin/env python3
"""Cluster friction events and propose concrete fixes.

Input:  JSONL of events from friction_parse.py (stdin or --in)
Output: JSON clusters with proposed deliverable + rendered rule body

Usage:
    friction_cluster.py --in frictions.jsonl --min-count 3 --out clusters.json
    friction_cluster.py --in frictions.jsonl --min-count 3 --render-pr-body out.md

Deliverable mapping:
    hook:*          -> rule edit documenting the block + the correct workflow
    push:*          -> hook adjustment (pre-push PR check) + rule
    plan:*          -> rule edit: "don't enter plan mode for conceptual Q&A"
    error:Bash:*    -> skill patch (quick reference flag or note)
    reject:*        -> rule edit documenting what the user declined
    interrupt:*     -> summary only (usually not actionable)
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

DELIVERABLES = {
    "plan:entered-plan-mode": {
        "kind": "rule",
        "path": "rules/claude/friction/plan-mode-on-qa.md",
        "title": "Avoid plan mode for conceptual Q&A",
        "body": """# Avoid plan mode for conceptual Q&A

When the user asks a **question** (starts with "how", "what", "why", "can", "does")
and does not request a change to files, **do not** call `ExitPlanMode`. Answer
the question directly.

## Heuristics

| Signal | Action |
|---|---|
| Request contains "explain", "how does", "what is", "compare" | Answer inline, no plan mode |
| Request asks to modify, add, remove, rename, fix | Plan mode is acceptable |
| User says "just tell me" / "no plan needed" | Never enter plan mode |

## Evidence

__EVIDENCE__
""",
    },
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


def propose(signature: str, hits: list[dict]) -> dict:
    spec = DELIVERABLES.get(signature)
    if spec is None:
        if signature.startswith("hook:"):
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
        f"- `{h.get('session','?')[:8]}` at {h.get('ts','?')}: {h.get('evidence','')[:200].strip()}"
        for h in hits[:5]
    )
    rendered_body = (
        spec["body"].replace("__COUNT__", str(len(hits))).replace("__EVIDENCE__", evidence_block)
        if spec["body"] else ""
    )
    return {
        "signature": signature,
        "count": len(hits),
        "kind": spec["kind"],
        "path": spec["path"],
        "title": spec["title"],
        "body": rendered_body,
        "samples": [
            {"session": h.get("session"), "ts": h.get("ts"), "tool": h.get("tool"), "evidence": h.get("evidence")}
            for h in hits[:3]
        ],
    }


def render_pr_body(proposals: list[dict], total_events: int, total_sessions: int, window: str) -> str:
    week = datetime.now(tz=timezone.utc).strftime("%G-W%V")
    lines = [
        f"## Friction Report: {week}",
        "",
        f"- Window: {window}",
        f"- Sessions analyzed: {total_sessions}",
        f"- Friction events: {total_events}",
        f"- Actionable clusters: {sum(1 for p in proposals if p['kind'] != 'watch')}",
        "",
        "| Cluster | Count | Deliverable | Path |",
        "|---|---|---|---|",
    ]
    for p in sorted(proposals, key=lambda x: -x["count"]):
        lines.append(f"| `{p['signature']}` | {p['count']} | {p['kind']} | `{p['path'] or '—'}` |")
    lines += ["", "## Proposed changes", ""]
    for p in proposals:
        if p["kind"] == "watch" or not p["body"]:
            continue
        lines += [f"### {p['title']}", f"**File**: `{p['path']}`", "", "```markdown", p["body"].rstrip(), "```", ""]
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="infile", default="-")
    ap.add_argument("--min-count", type=int, default=3)
    ap.add_argument("--out", default="-")
    ap.add_argument("--render-pr-body", default="", help="Also write a PR body markdown to this path")
    ap.add_argument("--window", default="7d")
    args = ap.parse_args()

    events = load_events(args.infile)
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
    }

    out = sys.stdout if args.out == "-" else open(args.out, "w", encoding="utf-8")
    try:
        json.dump(result, out, indent=2, ensure_ascii=False)
        out.write("\n")
    finally:
        if out is not sys.stdout:
            out.close()

    if args.render_pr_body:
        body = render_pr_body(actionable, len(events), len(sessions), args.window)
        Path(args.render_pr_body).write_text(body, encoding="utf-8")
        sys.stderr.write(f"wrote PR body to {args.render_pr_body}\n")

    sys.stderr.write(
        f"events={len(events)} sessions={len(sessions)} clusters={len(buckets)} actionable={len(actionable)}\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

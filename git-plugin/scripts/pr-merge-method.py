#!/usr/bin/env python3
"""Recommend rebase or squash for a pull request, and lint the squash body.

The single decision rule behind every merge surface: the git-plugin
PreToolUse hook (``hooks/check-pr-merge-method.sh``), the ``merge-method``
check run in ``laurigates/.github``'s reusable workflow, and the dotfiles
``ghm`` wrapper. The rule table and its rationale live in
``skills/github-pr-title/merge-strategies.md``; this file is the executable
copy, so change both together.

Usage::

    pr-merge-method.py --repo OWNER/NAME --pr 123      # live, via gh
    pr-merge-method.py --pr https://github.com/o/r/pull/123
    pr-merge-method.py --fixture pr.json               # offline, for tests
    pr-merge-method.py --repo o/r --pr 123 --emit-fixture pr.json

Output (KEY=VALUE, .claude/rules/structured-script-output.md)::

    === PR MERGE METHOD ===
    PR=o/r#123
    METHOD=rebase|squash
    RULE=<1-9>
    REASON=<code>
    DETAIL=<one line>
    OVERRIDE=<label|none>
    TITLE=<check-run title>
    SQUASH_BODY=PR_BODY|COMMIT_MESSAGES|BLANK   # the repo's squash_merge_commit_message
    BODY_LINT=<n>
    LINT_<KIND>=<count>          # one per kind found; only when the body lands
    STATUS=OK|WARN|ERROR
    ISSUE_COUNT=<n>
    === END PR MERGE METHOD ===

Exit 0 with a decision (STATUS=OK, or WARN when the body has lint findings),
exit 1 with STATUS=ERROR when the PR could not be read. An empty commit list is
an ERROR, never a squash: a failed fetch must not pass as a decision.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from functools import partial
from typing import NamedTuple

OVERRIDE_LABELS = ("merge:squash", "merge:rebase")
# Per-commit file lists cost one REST call each; past this, rule 8 cannot be
# checked and the PR squashes.
MAX_FILE_COMMITS = 50
CORRECTION_TYPES = frozenset({"fix", "style", "chore", "refactor", "test"})

CONVENTIONAL = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[^)]*)\))?!?: \S")
AUTOSQUASH = re.compile(r"^(fixup|squash|amend)! ")
REVIEW_CHURN = re.compile(
    r"\b(address(es|ed|ing)? (the )?(review|feedback|comments?)"
    r"|review (findings|feedback|comments?|nits?|gaps|issues)"
    r"|(after|from|per) (code )?review"
    r"|apply(ing)? suggestions?"
    r"|wip)\b",
    re.IGNORECASE,
)


class Decision(NamedTuple):
    method: str
    rule: int
    reason: str
    detail: str
    override: str = "none"


def short(oid: str) -> str:
    return oid[:7]


def is_bot(pr: dict) -> bool:
    author = pr.get("author") or {}
    login = author.get("login", "")
    return (
        bool(author.get("is_bot"))
        or login.endswith("[bot]")
        or login.startswith("app/")
    )


def human_override(pr: dict) -> str | None:
    """The most recent merge:* label a human applied, if any is still set."""
    human = [
        lb["name"]
        for lb in pr.get("labels", [])
        if lb["name"] in OVERRIDE_LABELS and lb.get("human")
    ]
    return human[-1] if human else None


def conventional(headline: str) -> tuple[str, str] | None:
    m = CONVENTIONAL.match(headline)
    return (m.group("type"), m.group("scope") or "") if m else None


# oids -> {oid: [paths]}; batched so the live fetch can run in parallel.
FilesFor = Callable[[list[str]], dict[str, list[str]]]


def in_pr_correction(
    commits: list[dict], files_by_oid: dict[str, list[str]]
) -> tuple[dict, dict] | None:
    """(correction, the earlier commit it corrects) for the first in-PR correction.

    A later commit corrects earlier in-PR work when either
      (a) its type is in CORRECTION_TYPES and every file it touches was already
          changed earlier in the PR, or
      (b) it is a `fix` sharing its scope with earlier commits that already
          changed at least half of its files: a fix to code that is not on
          main yet, which would land as a phantom changelog line.
    """
    earlier: list[tuple[dict, set[str], str]] = []
    for c in commits:
        files = set(files_by_oid.get(c["oid"], []))
        kind = conventional(c["headline"])
        if earlier and kind and files:
            seen = set().union(*(f for _, f, _ in earlier))
            same = [(e, f) for e, f, sc in earlier if sc == kind[1]]
            same_files = set().union(*(f for _, f in same)) if same else set()
            if kind[0] in CORRECTION_TYPES and files <= seen:
                target = next(e for e, f, _ in reversed(earlier) if f & files)
                return c, target
            if kind[0] == "fix" and same and 2 * len(files & same_files) >= len(files):
                target = next((e for e, f in reversed(same) if f & files), same[-1][0])
                return c, target
        earlier.append((c, files, kind[1] if kind else ""))
    return None


def decide(pr: dict, files_for: FilesFor) -> Decision:
    """Apply the merge-strategies.md rule table in order; first match wins."""
    commits = pr["commits"]
    label = human_override(pr)
    if label:
        return Decision(
            label.split(":", 1)[1],
            1,
            "override_label",
            f"{label} applied by a human",
            label,
        )
    if is_bot(pr) or pr.get("headRefName", "").startswith("release-please--"):
        return Decision(
            "squash", 2, "bot_or_release", "bot-authored or release-please PR"
        )
    if len(commits) == 1:
        return Decision(
            "squash", 3, "single_commit", "one commit; squash keeps (#N) in the subject"
        )
    merges = [c for c in commits if c.get("parents", 1) > 1]
    if merges:
        return Decision(
            "squash",
            4,
            "merge_commit",
            f"{len(merges)} merge commit(s), e.g. {short(merges[0]['oid'])}; "
            "rebase the branch onto main to make it rebase-eligible",
        )
    churn = [
        c
        for c in commits
        if AUTOSQUASH.match(c["headline"]) or REVIEW_CHURN.search(c["headline"])
    ]
    if churn:
        return Decision(
            "squash",
            5,
            "fixup_or_review_churn",
            f"{short(churn[0]['oid'])} {churn[0]['headline'][:80]}",
        )
    loose = [c for c in commits if not conventional(c["headline"])]
    if loose:
        return Decision(
            "squash",
            6,
            "non_conventional",
            f"{short(loose[0]['oid'])} {loose[0]['headline'][:80]}",
        )
    kinds = {conventional(c["headline"]) or ("", "") for c in commits}
    if len(kinds) == 1:
        t, s = kinds.pop()
        return Decision(
            "squash",
            7,
            "single_concern",
            f"every commit is {t}({s})" if s else f"every commit is {t}",
        )
    if len(commits) > MAX_FILE_COMMITS:
        return Decision(
            "squash",
            8,
            "too_many_commits",
            f"{len(commits)} commits; file overlap not checked past {MAX_FILE_COMMITS}",
        )
    hit = in_pr_correction(commits, files_for([c["oid"] for c in commits]))
    if hit:
        fix, target = hit
        return Decision(
            "squash",
            8,
            "in_pr_correction",
            f"{short(fix['oid'])} {fix['headline'][:60]} corrects in-PR work "
            f"from {short(target['oid'])}; fold it in (git commit --fixup "
            f"{short(target['oid'])}, rebase --autosquash) to make the PR rebase-eligible",
        )
    return Decision(
        "rebase",
        9,
        "independent_commits",
        f"{len(commits)} independent conventional commits",
    )


# ── Body lint (squash only: the body becomes the commit body) ────────────────

FENCE = re.compile(r"^\s*(```|~~~)")
LINT_PATTERNS = {
    "CHECKLIST": re.compile(r"^\s*[-*] \[[ xX]\]"),
    "HTML_COMMENT": re.compile(r"<!--"),
    "HEADING": re.compile(r"^#{1,6}\s"),
    "CLOSES_AFTER_MERGE": re.compile(
        r"\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\s+\S*#\d+\s+after merge\b",
        re.IGNORECASE,
    ),
}


def lint_body(pr: dict) -> dict[str, int]:
    found: dict[str, int] = {}
    in_fence = False
    for line in (pr.get("body") or "").splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for kind, pat in LINT_PATTERNS.items():
            if pat.search(line):
                found[kind] = found.get(kind, 0) + 1
    # Same comparison as check-pr-metadata-on-push.sh (commit AUTHOR time, which
    # a rebase preserves), but against the body's own edit time: updatedAt moves
    # on every push, so it cannot say whether the body was revisited.
    body_time = pr.get("lastEditedAt") or pr.get("createdAt") or ""
    # A merge commit from syncing main adds no content the body should describe.
    newest = max(
        (c.get("authoredDate", "") for c in pr["commits"] if c.get("parents", 1) == 1),
        default="",
    )
    if body_time and newest and newest > body_time:
        found["STALE_BODY"] = 1
    return found


# Check-run title phrase per REASON code.
PHRASES = {
    "override_label": "label override",
    "bot_or_release": "bot or release PR",
    "single_commit": "single commit",
    "merge_commit": "branch has merge commits",
    "fixup_or_review_churn": "fixup or review-churn commit",
    "non_conventional": "non-conventional commit",
    "single_concern": "single concern",
    "too_many_commits": "too many commits to check",
    "in_pr_correction": "in-PR fixup",
}


def render(pr: dict, d: Decision, lint: dict[str, int], squash_body: str) -> str:
    n_lint = sum(lint.values())
    verb = "Rebase and merge" if d.method == "rebase" else "Squash and merge"
    why = d.detail if d.rule == 9 else PHRASES[d.reason]
    title = f"→ {verb} ({why})"
    if n_lint:
        title += f" · body: {n_lint} lint issue{'s' if n_lint != 1 else ''}"
    lines = [
        "=== PR MERGE METHOD ===",
        f"PR={pr.get('repo', '?')}#{pr.get('number', '?')}",
        f"METHOD={d.method}",
        f"RULE={d.rule}",
        f"REASON={d.reason}",
        f"DETAIL={d.detail}",
        f"OVERRIDE={d.override}",
        f"TITLE={title}",
        f"COMMITS={len(pr['commits'])}",
        f"SQUASH_BODY={squash_body}",
        f"BODY_LINT={n_lint}",
        *(f"LINT_{k}={v}" for k, v in sorted(lint.items())),
        f"STATUS={'WARN' if n_lint else 'OK'}",
        f"ISSUE_COUNT={n_lint}",
        "=== END PR MERGE METHOD ===",
    ]
    return "\n".join(lines)


def render_error(reason: str) -> str:
    return "\n".join(
        [
            "=== PR MERGE METHOD ===",
            "METHOD=unknown",
            "STATUS=ERROR",
            f"REASON={reason[:200]}",
            "ISSUE_COUNT=1",
            "=== END PR MERGE METHOD ===",
        ]
    )


# ── Fetching (gh) ─────────────────────────────────────────────────────────────

QUERY = """
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    squashMergeCommitMessage
    pullRequest(number: $number) {
      number headRefName body createdAt lastEditedAt
      author { __typename login }
      labels(first: 50) { nodes { name } }
      timelineItems(last: 100, itemTypes: [LABELED_EVENT]) {
        nodes { ... on LabeledEvent { label { name } actor { __typename } } }
      }
      commits(first: 100) {
        totalCount
        nodes { commit { oid messageHeadline authoredDate parents { totalCount } } }
      }
    }
  }
}
"""


def gh(*args: str) -> str:
    r = subprocess.run(["gh", *args], check=False, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(f"gh {' '.join(args[:2])} failed: {r.stderr.strip()[:150]}")
    return r.stdout


def resolve(repo: str | None, selector: str | None) -> tuple[str, int]:
    """(owner/name, number) for a number, URL or branch; gh resolves the rest."""
    m = re.match(r"https://github\.com/([^/]+/[^/]+)/pull/(\d+)", selector or "")
    if m:
        return m.group(1), int(m.group(2))
    if repo and selector and selector.isdigit():
        return repo, int(selector)
    args = [
        "pr",
        "view",
        *([selector] if selector else []),
        "--json",
        "url",
        "--jq",
        ".url",
    ]
    if repo:
        args += ["-R", repo]
    url = gh(*args).strip()
    m = re.match(r"https://github\.com/([^/]+/[^/]+)/pull/(\d+)", url)
    if not m:
        raise RuntimeError(f"cannot resolve PR from {selector!r}")
    return m.group(1), int(m.group(2))


def fetch(repo: str, number: int) -> dict:
    owner, name = repo.split("/", 1)
    data = json.loads(
        gh(
            "api",
            "graphql",
            "-f",
            f"query={QUERY}",
            "-F",
            f"owner={owner}",
            "-F",
            f"name={name}",
            "-F",
            f"number={number}",
        )
    )
    r = data["data"]["repository"]
    p = r["pullRequest"]
    last_actor: dict[str, str] = {}
    for ev in p["timelineItems"]["nodes"]:
        if ev and ev.get("label"):
            last_actor[ev["label"]["name"]] = (ev.get("actor") or {}).get(
                "__typename", ""
            )
    commits = [
        {
            "oid": n["commit"]["oid"],
            "headline": n["commit"]["messageHeadline"],
            "authoredDate": n["commit"]["authoredDate"],
            "parents": n["commit"]["parents"]["totalCount"],
        }
        for n in p["commits"]["nodes"]
    ]
    if p["commits"]["totalCount"] > len(commits):
        # Pad so rule 8's commit-count cap still sees the real size.
        commits += [{"oid": "0" * 40, "headline": "(not fetched)", "parents": 1}] * (
            p["commits"]["totalCount"] - len(commits)
        )
    return {
        "repo": repo,
        "number": p["number"],
        "headRefName": p["headRefName"],
        "squashMergeCommitMessage": r["squashMergeCommitMessage"],
        "body": p["body"],
        "createdAt": p["createdAt"],
        "lastEditedAt": p["lastEditedAt"],
        "author": {
            "login": (p["author"] or {}).get("login", ""),
            "is_bot": (p["author"] or {}).get("__typename") == "Bot",
        },
        # A label counts as a human override only if its latest `labeled` event
        # came from a non-bot actor: the workflow's own label is never one.
        "labels": [
            {
                "name": lb["name"],
                "human": last_actor.get(lb["name"], "Bot") not in ("Bot", ""),
            }
            for lb in p["labels"]["nodes"]
        ],
        "commits": commits,
    }


def commit_files(repo: str, oid: str) -> list[str]:
    return json.loads(
        gh("api", f"repos/{repo}/commits/{oid}", "--jq", "[.files[].filename]")
    )


def fetch_files(repo: str, oids: list[str]) -> dict[str, list[str]]:
    with ThreadPoolExecutor(max_workers=8) as pool:
        return dict(zip(oids, pool.map(partial(commit_files, repo), oids)))


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n\n")[0])
    ap.add_argument("--repo", help="OWNER/NAME (default: gh resolves from cwd)")
    ap.add_argument("--pr", help="number, URL or branch (default: current branch)")
    ap.add_argument("--fixture", help="read a normalized PR JSON instead of calling gh")
    ap.add_argument(
        "--emit-fixture",
        metavar="PATH",
        help="also write the fetched PR, with every commit's files, as a fixture",
    )
    a = ap.parse_args(argv)
    try:
        if a.fixture:
            with open(a.fixture) as f:
                pr = json.load(f)
            known = {c["oid"]: c.get("files", []) for c in pr["commits"]}

            def files_for(oids: list[str]) -> dict[str, list[str]]:
                return {o: known.get(o, []) for o in oids}

        else:
            repo, number = resolve(a.repo, a.pr)
            pr = fetch(repo, number)
            files_for = partial(fetch_files, repo)  # type: ignore[assignment]
        if not pr.get("commits"):
            print(
                render_error(
                    "no_commits: the PR returned no commits; refusing to guess"
                )
            )
            return 1
        if a.emit_fixture:
            oids = [
                c["oid"]
                for c in pr["commits"][:MAX_FILE_COMMITS]
                if c.get("parents", 1) == 1
            ]
            files = files_for(oids)
            for c in pr["commits"]:
                c["files"] = files.get(c["oid"], [])
            with open(a.emit_fixture, "w") as f:
                json.dump(pr, f, indent=1)
        d = decide(pr, files_for)
        # Lint the body only where it lands: a squash, on a repo whose squash
        # body is the PR body (gitops sets COMMIT_MESSAGES on release-please
        # repos), of a human PR (a bot regenerates its own body).
        squash_body = pr.get("squashMergeCommitMessage") or "PR_BODY"
        lands = d.method == "squash" and d.rule != 2 and squash_body == "PR_BODY"
        lint = lint_body(pr) if lands else {}
        print(render(pr, d, lint, squash_body))
        return 0
    except (RuntimeError, KeyError, TypeError, json.JSONDecodeError, OSError) as e:
        print(render_error(f"fetch_failed: {e}"))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

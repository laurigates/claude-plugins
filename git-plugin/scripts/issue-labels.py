#!/usr/bin/env python3
"""Provision, derive, validate and audit a repository's issue labels.

One taxonomy, five subcommands. The label vocabulary and its lifecycle are
described in ``skills/github-labels/SKILL.md``; this file is the executable
copy, so change both together. A reusable workflow fetches this script by
sparse checkout at a pinned commit, so it uses the Python standard library
only and reaches GitHub through ``gh`` alone.

Usage::

    issue-labels.py provision --repo OWNER/NAME --taxonomy issue-labels.json [--dry-run]
    issue-labels.py classify  --repo OWNER/NAME --issue 12        # or --pr 34
    issue-labels.py classify  --fixture item.json --taxonomy t.json --repo-labels labels.json
    issue-labels.py validate  --repo OWNER/NAME --issue 12 --labels-file labels.json
    issue-labels.py unblock   --repo OWNER/NAME --issue 12 [--dry-run]
    issue-labels.py audit     --repo OWNER/NAME [--needs-stale-days 30] [--json]

Taxonomy file (JSON, by default ``.github/issue-labels.json`` on the default
branch)::

    {"build": {"robot": {"description": "...", "color": "1d76db",
                         "paths": ["packages/robot/**"], "scopes": ["robot-fw"],
                         "renamed_from": null}},
     "area":  {"ota": {"description": "...", "color": "0e8a16", "scopes": ["ota"]}},
     "core":  {"components": {"paths": ["packages/components/**"]}}}

``build`` and ``area`` entries own a label's colour and, when they give one,
its description; ``core`` entries carry only ``paths`` and ``scopes``, and
replace the built-in globs in DEFAULT_CORE key by key. An entry's key is always
one of its scopes. A glob matches the whole repo-relative path: ``*`` and ``?``
stay inside one path segment, ``**`` crosses segments, and a trailing ``/**``
also matches the directory itself.

Every label name comes from a flag default (``--build-prefix build:``,
``--area-prefix area:``, ``--core-prefix core:``, ``--needs-prefix needs:``,
``--blocked-label blocked``, ``--type-labels``, ``--type-map``,
``--never-derive``), so a repository with another vocabulary passes its own.

``classify`` reads the type from the title ("[Bug] scope: ...", "fix(scope):
..." or neither) and routing labels from the title's scope. A pull request
also takes every label its changed files match. An issue with no routing label
takes the label that most of the paths quoted in its body match; a body token
is a path only when it has a slash or a dot, so the word "docs" in a sentence
is not one. It only adds: a prefix that already has a label on the item is
skipped.

Output: ``classify`` and ``validate`` print one JSON object. ``provision``,
``unblock`` and ``audit`` print a KEY=VALUE block
(.claude/rules/structured-script-output.md); ``audit --json`` prints its
findings as JSON instead.

Exit codes: 0 when the subcommand ran (``audit`` findings are STATUS=WARN and
still exit 0), 1 on an error (unreadable input, malformed taxonomy, failed
``gh`` call), 2 from ``audit --exit-code`` when there are findings. A failed
read is always an error and never an empty result.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from datetime import datetime
from typing import NamedTuple
from urllib.parse import quote

# gh's default page is 30 labels; a truncated page makes an existing label read
# as missing. A listing that fills this limit is refused as truncated.
LABEL_LIMIT = 500
DEFAULT_TAXONOMY_PATH = ".github/issue-labels.json"

# Built-in globs for the core section, by label suffix. A taxonomy's "core"
# entry with the same key replaces the fields it sets.
DEFAULT_CORE: dict[str, dict] = {
    "ci": {"paths": [".github/**"]},
    "agent": {"paths": [".claude/**", ".mcp.json"]},
    "build": {"paths": ["justfile", "*.just"]},
    "quality": {"paths": [".pre-commit-config.yaml"]},
    "docs": {"paths": ["docs/**"]},
}

SECTIONS = ("build", "area", "core")
PROVISIONED_SECTIONS = ("build", "area")
ENTRY_FIELDS = {
    "build": {"description", "color", "paths", "scopes", "renamed_from"},
    "area": {"description", "color", "paths", "scopes", "renamed_from"},
    "core": {"paths", "scopes"},
}
KEY = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
COLOR = re.compile(r"^[0-9a-fA-F]{6}$")
MAX_DESCRIPTION = 100  # GitHub's limit on a label description


class Config(NamedTuple):
    """The label vocabulary. Every label name in this script comes from here."""

    build_prefix: str
    area_prefix: str
    core_prefix: str
    needs_prefix: str
    blocked_label: str
    type_labels: tuple[str, ...]
    type_keywords: dict[str, str]  # title keyword -> type label
    never_derive: frozenset[str]

    def prefix(self, section: str) -> str:
        return {
            "build": self.build_prefix,
            "area": self.area_prefix,
            "core": self.core_prefix,
        }[section]

    @property
    def routing_prefixes(self) -> tuple[str, ...]:
        return (self.build_prefix, self.area_prefix, self.core_prefix)


class Entry(NamedTuple):
    label: str
    section: str
    paths: tuple[str, ...]
    scopes: frozenset[str]


class Title(NamedTuple):
    form: str  # bracket | conventional | scope | none
    keyword: str | None
    scopes: tuple[str, ...]


class Error(Exception):
    """A failure the caller reports as STATUS=ERROR; never an empty result."""


# ── Vocabulary ────────────────────────────────────────────────────────────────


def parse_type_map(spec: str) -> dict[str, str]:
    """'bug=bug,fix;docs=docs' -> {'bug': 'bug', 'fix': 'bug', 'docs': 'docs'}."""
    keywords: dict[str, str] = {}
    for part in filter(None, (p.strip() for p in spec.split(";"))):
        label, _, words = part.partition("=")
        for word in filter(None, (w.strip().lower() for w in words.split(","))):
            keywords[word] = label.strip()
    return keywords


def norm(text: str) -> str:
    """Lowercase with whitespace runs collapsed: the form names are compared in."""
    return " ".join(text.lower().split())


def has_prefix(label: str, prefix: str) -> bool:
    return label.lower().startswith(prefix.lower())


# ── Taxonomy ──────────────────────────────────────────────────────────────────


def check_taxonomy(tax: object, for_provision: bool = False) -> list[str]:
    """Problems that make the taxonomy unusable; empty when it is sound.

    Unknown sections and fields are problems, not noise: a taxonomy may define
    labels under the build and area prefixes only, and a misspelt ``path`` would
    otherwise switch an entry's matching off without a word.
    """
    if not isinstance(tax, dict):
        return ["taxonomy is not a JSON object"]
    problems: list[str] = []
    renamed: dict[str, str] = {}  # old label name -> the entry that renames it
    for section, entries in tax.items():
        if section.startswith(("$", "_")):
            continue
        if section not in SECTIONS:
            problems.append(
                f"section '{section}': only {', '.join(SECTIONS)} may be defined"
            )
            continue
        if not isinstance(entries, dict):
            problems.append(f"section '{section}' is not an object")
            continue
        for key, entry in entries.items():
            where = f"{section}.{key}"
            if not KEY.match(key):
                problems.append(f"{where}: key must match {KEY.pattern}")
            if not isinstance(entry, dict):
                problems.append(f"{where} is not an object")
                continue
            for field in sorted(set(entry) - ENTRY_FIELDS[section]):
                problems.append(f"{where}: field '{field}' is not allowed here")
            for field in ("paths", "scopes"):
                value = entry.get(field, [])
                if not isinstance(value, list) or not all(
                    isinstance(v, str) and v.strip() for v in value
                ):
                    problems.append(f"{where}.{field} must be a list of strings")
            if section not in PROVISIONED_SECTIONS:
                continue
            color = entry.get("color")
            if color is not None and not (
                isinstance(color, str) and COLOR.match(color)
            ):
                problems.append(f"{where}.color must be six hex digits, quoted")
            if for_provision and color is None:
                problems.append(f"{where}.color is required to provision the label")
            description = entry.get("description", "")
            if not isinstance(description, str) or len(description) > MAX_DESCRIPTION:
                problems.append(
                    f"{where}.description must be a string of at most "
                    f"{MAX_DESCRIPTION} characters"
                )
            old = entry.get("renamed_from")
            if old is not None and not (isinstance(old, str) and old.strip()):
                problems.append(f"{where}.renamed_from must be a label name or null")
            elif old is not None:
                # One label can be renamed once: the second PATCH would find
                # the old name gone, after the first had already been applied.
                first = renamed.setdefault(norm(old), where)
                if first != where:
                    problems.append(
                        f"{where}.renamed_from: '{old.strip()}' is already "
                        f"renamed by {first}"
                    )
    return problems


def routing_entries(tax: dict, cfg: Config) -> list[Entry]:
    """Every label that paths or scopes can select, built-in core globs included."""
    core = {k: dict(v) for k, v in DEFAULT_CORE.items()}
    for key, entry in (tax.get("core") or {}).items():
        core[key] = {**core.get(key, {}), **entry}
    merged = {
        "build": tax.get("build") or {},
        "area": tax.get("area") or {},
        "core": core,
    }
    return [
        Entry(
            label=cfg.prefix(section) + key,
            section=section,
            paths=tuple(entry.get("paths", [])),
            scopes=frozenset({norm(key), *(norm(s) for s in entry.get("scopes", []))}),
        )
        for section in SECTIONS
        for key, entry in merged[section].items()
    ]


# ── Matching ──────────────────────────────────────────────────────────────────


def glob_regex(glob: str) -> re.Pattern[str]:
    glob = glob.lstrip("/")
    out: list[str] = []
    i = 0
    while i < len(glob):
        if glob.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif glob.startswith("/**", i) and i + 3 == len(glob):
            out.append("(?:/.*)?")
            i += 3
        elif glob.startswith("**", i):
            out.append(".*")
            i += 2
        elif glob[i] == "*":
            out.append("[^/]*")
            i += 1
        elif glob[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(glob[i]))
            i += 1
    return re.compile("".join(out) + r"\Z")


def path_matches(path: str, glob: str) -> bool:
    return bool(glob_regex(glob).match(path.lstrip("/")))


BRACKET = re.compile(r"^\s*\[(?P<kw>[^\]]+)\]\s*(?P<rest>.*)$")
CONVENTIONAL = re.compile(
    r"^\s*(?P<kw>[A-Za-z][\w.-]*)(?:\((?P<scope>[^)]*)\))?!?:\s+\S"
)
LEADING = re.compile(r"^\s*(?P<scope>[^:\[\]()]{1,60}?):\s+\S")


def parse_title(title: str, type_keywords: frozenset[str]) -> Title:
    """The type keyword and scope candidates a title carries, by its form.

    bracket       "[Bug] enclosure: lid does not close"   keyword bug, scope enclosure
                  "[Bug] fix(kicad): close the gaps"      keyword bug, scopes kicad, fix
    conventional  "fix(kicad): close the gaps"            keyword fix, scopes kicad, fix
                  "ci: run the check"                     keyword ci, scope ci
    scope         "balancebot: read the divider"          scope balancebot
                  "Parts registry: tariff code per part"  scope "parts registry"
    none          "Dependency Dashboard"

    A title is conventional when its leading word carries a parenthesised
    scope or is one of ``type_keywords``. That word is offered as a scope too,
    so "ci(robot): ..." can select a ci entry as well as a robot one. What
    follows a bracket is read for its scopes in the same forms; the bracket
    word stays the keyword.
    """
    m = BRACKET.match(title)
    if m:
        rest = parse_title(m.group("rest"), type_keywords)
        return Title("bracket", norm(m.group("kw")), rest.scopes)
    m = CONVENTIONAL.match(title)
    if m and (m.group("scope") is not None or m.group("kw").lower() in type_keywords):
        keyword = m.group("kw").lower()
        inner = (m.group("scope") or "").split(",")
        scopes = [norm(s) for s in inner if s.strip()]
        return Title("conventional", keyword, tuple(dict.fromkeys([*scopes, keyword])))
    m = LEADING.match(title)
    if m:
        return Title("scope", None, (norm(m.group("scope")),))
    return Title("none", None, ())


SEPARATORS = re.compile(r"[\s`()\[\]<>{}\"',;]+")
LINE_SUFFIX = re.compile(r":\d+(?:[-:,]\d+)*$")


def path_shaped(token: str) -> bool:
    """Whether a token of free text reads as a repo path: it has a slash or a dot.

    Prose uses directory and file names as words ("the upstream docs", "a
    justfile recipe"), and such a word would match ``docs/**`` or ``justfile``
    as if the issue had cited the path. ``docs/``, ``docs/a.md``, ``.mcp.json``
    and ``./justfile`` are paths; ``docs`` and ``justfile`` are words.
    """
    return "/" in token or "." in token


def path_candidates(body: str) -> list[str]:
    """Path-shaped tokens in free text, in order, without duplicates.

    Backticks, brackets and quotes delimit tokens, so `a/b.c`, (a/b.c) and a
    bare a/b.c all yield the same candidate. A ``file.c:12-14`` line suffix and
    trailing sentence punctuation are dropped; URLs and tokens with neither a
    slash nor a dot are skipped.
    """
    seen: dict[str, None] = {}
    for raw in SEPARATORS.split(body or ""):
        if "://" in raw:
            continue
        token = LINE_SUFFIX.sub("", raw.rstrip(".:!?"))
        if not path_shaped(token):
            continue
        token = token.removeprefix("./").lstrip("/")
        if token and not token.startswith(("#", "@", "-")):
            seen.setdefault(token)
    return list(seen)


# ── classify ──────────────────────────────────────────────────────────────────


def derive(
    item: dict, tax: dict, cfg: Config, existing: list[str]
) -> tuple[Title, list[dict]]:
    """Labels the title, body and changed files point at, each with its source.

    ``existing`` is the labels already on the item that count (none when the
    caller ignores them).

    The title gives the type and, through its scope, the routing labels. What
    else is read depends on the item:

    - A pull request adds every label its changed files match. The diff is the
      record of what it touches, so paths its body mentions are not read.
    - An issue falls back to the paths its body quotes only when it has no
      routing label, neither set already nor selected by the title scope. It
      then keeps the label or labels that the most distinct paths match. A
      body cites files in passing (a rule it follows, a doc it mentions);
      taking every match labelled those too.
    """
    title = parse_title(item.get("title") or "", frozenset(cfg.type_keywords))
    derived: dict[str, str] = {}
    label = cfg.type_keywords.get(title.keyword or "")
    if label and label not in cfg.never_derive:
        derived[label] = f"title:{title.keyword}"
    entries = routing_entries(tax, cfg)
    routed = any(label_group(lb, cfg) in cfg.routing_prefixes for lb in existing)
    for scope in title.scopes:
        for entry in entries:
            if scope in entry.scopes:
                derived.setdefault(entry.label, f"scope:{scope}")
                routed = True

    def matching(paths: list[str]) -> dict[str, list[str]]:
        hits: dict[str, list[str]] = {}
        for path in paths:
            for entry in entries:
                if any(path_matches(path, glob) for glob in entry.paths):
                    hits.setdefault(entry.label, []).append(path)
        return hits

    if item.get("is_pr"):
        for name, paths in matching(item.get("files") or []).items():
            derived.setdefault(name, f"file:{paths[0]}")
    elif not routed:
        hits = matching(path_candidates(item.get("body") or ""))
        most = max((len(paths) for paths in hits.values()), default=0)
        for name, paths in hits.items():
            if len(paths) == most:
                derived.setdefault(name, f"body:{paths[0]} ({most} path(s))")
    return title, [{"label": k, "source": v} for k, v in derived.items()]


def label_group(label: str, cfg: Config) -> str | None:
    """The additive group a label belongs to: 'type', one prefix, or None."""
    if label.lower() in {t.lower() for t in cfg.type_labels}:
        return "type"
    for prefix in (*cfg.routing_prefixes, cfg.needs_prefix):
        if has_prefix(label, prefix):
            return prefix
    return None


def additive(
    proposed: list[str],
    existing: list[str],
    repo_labels: list[str],
    cfg: Config,
) -> tuple[list[str], list[dict]]:
    """Split proposed labels into those to add and those skipped, with reasons.

    Additive only: a group that already has a label on the item is left to
    whoever set it, and a label the repository does not have is never added
    (the REST API would create it).
    """
    canonical = {name.lower(): name for name in repo_labels}
    taken = {g for g in (label_group(lb, cfg) for lb in existing) if g}
    have = {lb.lower() for lb in existing}
    add: list[str] = []
    skipped: list[dict] = []
    for label in proposed:
        if label.lower() in have:
            skipped.append({"label": label, "reason": "already_set"})
        elif label_group(label, cfg) in taken:
            skipped.append({"label": label, "reason": "prefix_present"})
        elif label.lower() not in canonical:
            skipped.append({"label": label, "reason": "missing_in_repo"})
        elif canonical[label.lower()] not in add:
            add.append(canonical[label.lower()])
    return add, skipped


def classify(
    item: dict, tax: dict, repo_labels: list[str], cfg: Config, ignore_existing: bool
) -> dict:
    existing = [] if ignore_existing else item["labels"]
    title, derived = derive(item, tax, cfg, existing)
    add, skipped = additive([d["label"] for d in derived], existing, repo_labels, cfg)
    return {
        "status": "OK",
        "number": item.get("number"),
        "kind": "pr" if item.get("is_pr") else "issue",
        "title_form": title.form,
        "add": add,
        "derived": derived,
        "skipped": skipped,
    }


# ── validate ──────────────────────────────────────────────────────────────────


def squash(text: str) -> str:
    return " ".join((text or "").split())


def allowlisted(label: str, cfg: Config) -> bool:
    """A label a model may propose: a type label, or one under the build, area,
    core or needs prefix. The blocked label, merge and release labels and every
    other repository label are set by people or by other automation."""
    if label.lower() == cfg.blocked_label.lower():
        return False  # even when --blocked-label sits under an allowed prefix
    return label_group(label, cfg) is not None


def read_proposals(data: object) -> list[dict]:
    """[{name, evidence}] from {"labels": [...]} or a bare list; entries may be
    names or objects. Raises Error when the file is not that shape at all."""
    if isinstance(data, dict):
        data = data.get("labels")
    if not isinstance(data, list):
        raise Error("labels_file_malformed: expected a list or {'labels': [...]}")
    out: list[dict] = []
    for entry in data:
        if isinstance(entry, str):
            out.append({"name": entry, "evidence": ""})
        elif isinstance(entry, dict) and isinstance(entry.get("name"), str):
            evidence = entry.get("evidence")
            out.append(
                {
                    "name": entry["name"],
                    "evidence": evidence if isinstance(evidence, str) else "",
                }
            )
        else:
            out.append({"name": None, "raw": entry})
    return out


def validate(
    proposals: list[dict],
    item: dict,
    repo_labels: list[str],
    cfg: Config,
    min_evidence: int,
) -> dict:
    """Keep the proposed labels that pass every gate; report the rest.

    An item carries one type label, so of two types in one file the first is
    kept. Routing and needs labels may be several.
    """
    canonical = {name.lower(): name for name in repo_labels}
    text = squash(f"{item.get('title') or ''}\n{item.get('body') or ''}")
    taken = {g for g in (label_group(lb, cfg) for lb in item["labels"]) if g}
    have = {lb.lower() for lb in item["labels"]}
    add: list[str] = []
    dropped: list[dict] = []

    def drop(name: object, reason: str) -> None:
        dropped.append({"label": name, "reason": reason})

    for p in proposals:
        name = p["name"]
        if name is None:
            drop(p.get("raw"), "malformed")
            continue
        name = name.strip()
        evidence = squash(p["evidence"])
        if not allowlisted(name, cfg):
            drop(name, "not_allowlisted")
        elif name.lower() not in canonical:
            drop(name, "missing_in_repo")
        elif name.lower() in have:
            drop(name, "already_set")
        elif label_group(name, cfg) in taken:
            drop(name, "prefix_present")
        elif (
            label_group(name, cfg) == "type"
            and canonical[name.lower()] not in add
            and any(label_group(kept, cfg) == "type" for kept in add)
        ):
            drop(name, "second_type")
        elif has_prefix(name, cfg.needs_prefix) and len(evidence) < min_evidence:
            drop(name, "no_evidence" if not evidence else "evidence_too_short")
        elif has_prefix(name, cfg.needs_prefix) and evidence not in text:
            drop(name, "evidence_not_in_issue")
        elif canonical[name.lower()] not in add:
            add.append(canonical[name.lower()])
    return {
        "status": "OK",
        "number": item.get("number"),
        "add": add,
        "dropped": dropped,
    }


# ── provision ─────────────────────────────────────────────────────────────────


def protected(label: str, cfg: Config) -> bool:
    """Labels a taxonomy may not rename away: they are provisioned elsewhere."""
    group = label_group(label, cfg)
    return (
        group in ("type", cfg.core_prefix, cfg.needs_prefix)
        or label.lower() == cfg.blocked_label.lower()
    )


def plan_provision(
    tax: dict, existing: list[dict], cfg: Config
) -> tuple[list[dict], list[str]]:
    """(actions, problems). Actions create, update or rename; none deletes.

    Only build and area entries are provisioned, so every name written starts
    with one of those two prefixes. A problem stops the whole run before any
    write. An entry with no ``description`` leaves the label's description as
    it is: the field is neither compared nor written.
    """
    problems = check_taxonomy(tax, for_provision=True)
    if problems:
        return [], problems
    by_name = {lb["name"].lower(): lb for lb in existing}
    actions: list[dict] = []
    for section in PROVISIONED_SECTIONS:
        for key, entry in (tax.get(section) or {}).items():
            name = cfg.prefix(section) + key
            want = {"color": entry["color"].lower()}
            if "description" in entry:
                want["description"] = entry["description"]
            current = by_name.get(name.lower())
            old = (entry.get("renamed_from") or "").strip()
            if current is None and old and old.lower() in by_name:
                if protected(old, cfg):
                    problems.append(
                        f"{section}.{key}.renamed_from: '{old}' is a type, core, "
                        "needs or blocked label and cannot be renamed here"
                    )
                    continue
                actions.append(
                    {
                        "op": "rename",
                        "label": name,
                        "from": by_name[old.lower()]["name"],
                    }
                    | want
                )
            elif current is None:
                actions.append({"op": "create", "label": name} | want)
            elif current.get("color", "").lower() != want["color"] or (
                "description" in want
                and (current.get("description") or "") != want["description"]
            ):
                actions.append({"op": "update", "label": current["name"]} | want)
            else:
                actions.append({"op": "unchanged", "label": current["name"]})
    return ([], problems) if problems else (actions, [])


# ── unblock ───────────────────────────────────────────────────────────────────


def same_repo(issue: dict, repo: str) -> bool:
    return (
        (issue.get("repository_url") or "").lower().endswith(f"/repos/{repo.lower()}")
    )


def label_names(issue: dict) -> list[str]:
    return [
        lb if isinstance(lb, str) else lb.get("name", "")
        for lb in issue.get("labels") or []
    ]


def dependent_skip(dependent: dict, repo: str, cfg: Config) -> str | None:
    """Why an issue the closed issue was blocking is out of scope, or None."""
    if not same_repo(dependent, repo):
        return "other_repo"
    if dependent.get("state") != "open":
        return "closed"
    if cfg.blocked_label.lower() not in {n.lower() for n in label_names(dependent)}:
        return "no_blocked_label"
    return None


def not_closed(blockers: list[dict]) -> list[dict]:
    """The blockers that still block: every one whose state is not "closed".

    A blocker with no state, or one this script does not know, counts as open,
    so a response in an unexpected shape keeps the blocked label.
    """
    return [b for b in blockers if b.get("state") != "closed"]


def blockers_verdict(blockers: list[dict]) -> tuple[str, str]:
    """(action, reason) from a blocked issue's own blocked_by list.

    The label comes off only when the list is non-empty and every issue in it
    is closed. The dependency link is the record, so a blocked label with no
    link behind it is left for a person.
    """
    if not blockers:
        return "skip", "no_link"
    still_open = not_closed(blockers)
    if still_open:
        return "keep", f"open_blocker:#{still_open[0].get('number')}"
    return "unblock", "all_blockers_closed"


# ── audit ─────────────────────────────────────────────────────────────────────


def epoch(stamp: str) -> float:
    """Unix seconds for an ISO time with a zone, as GitHub prints it.

    The "Z" is rewritten because fromisoformat only reads it from Python 3.11.
    """
    return datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()


def label_since(label: str, events: list[dict], created_at: str) -> tuple[str, str]:
    """(timestamp, source) for when a label was last applied to an issue.

    The latest ``labeled`` event naming the label wins. An event keeps the name
    the label had when it was applied, so a renamed label matches no event; the
    issue's creation time is then the earliest it can have been set.
    """
    stamps = [
        e["created_at"]
        for e in events
        if e.get("event") == "labeled"
        and ((e.get("label") or {}).get("name") or "").lower() == label.lower()
    ]
    return (max(stamps), "event") if stamps else (created_at, "created_at")


def audit_issue(
    issue: dict,
    blockers: list[dict],
    needs_since: dict[str, tuple[str, str]],
    now: float,
    stale_days: int,
    cfg: Config,
) -> list[dict]:
    """Findings for one open issue. ``blockers`` is its blocked_by list."""
    number = issue["number"]
    labels = label_names(issue)
    groups = {label_group(lb, cfg) for lb in labels}
    findings: list[dict] = []

    def finding(kind: str, msg: str) -> None:
        findings.append({"type": kind, "number": number, "msg": msg})

    if "type" not in groups:
        finding("missing_type", f"no type label ({', '.join(cfg.type_labels)})")
    if not groups & set(cfg.routing_prefixes):
        finding("missing_routing", f"no {' / '.join(cfg.routing_prefixes)} label")
    is_blocked = cfg.blocked_label.lower() in {lb.lower() for lb in labels}
    open_blockers = not_closed(blockers)
    if is_blocked and not blockers:
        finding("blocked_no_link", f"'{cfg.blocked_label}' with no blocked_by link")
    elif is_blocked and not open_blockers:
        finding(
            "blocked_resolved",
            f"'{cfg.blocked_label}' but all {len(blockers)} blocked_by issue(s) are closed",
        )
    elif open_blockers and not is_blocked:
        finding(
            "open_link_not_blocked",
            f"blocked_by #{open_blockers[0].get('number')} is open "
            f"but '{cfg.blocked_label}' is not set",
        )
    for label, (stamp, source) in sorted(needs_since.items()):
        age = int((now - epoch(stamp)) // 86400)
        if age > stale_days:
            origin = (
                "" if source == "event" else ", from issue creation: no labeled event"
            )
            finding("needs_stale", f"{label} set {age} days ago ({stamp[:10]}{origin})")
    return findings


FINDING_TYPES = (
    "missing_type",
    "missing_routing",
    "blocked_no_link",
    "blocked_resolved",
    "open_link_not_blocked",
    "needs_stale",
)


# ── Rendering ─────────────────────────────────────────────────────────────────


def one_line(text: str, limit: int = 180) -> str:
    return " ".join(str(text).split())[:limit]


def block(name: str, lines: list[str]) -> str:
    return "\n".join([f"=== {name} ===", *lines, f"=== END {name} ==="])


def status_lines(rows: list[dict], severity: str) -> list[str]:
    """STATUS / REASON / ISSUE_COUNT / ISSUES: for rows of {type, msg, ...}."""
    if not rows:
        return ["STATUS=OK", "ISSUE_COUNT=0"]
    first = rows[0]
    reason = one_line(f"{first['type']}: {first.get('where', '')}{first['msg']}")
    more = f" (+{len(rows) - 1} more)" if len(rows) > 1 else ""
    out = [f"STATUS={severity}", f"REASON={reason}{more}", f"ISSUE_COUNT={len(rows)}"]
    out.append("ISSUES:")
    for row in rows:
        number = f" NUMBER={row['number']}" if "number" in row else ""
        out.append(
            f"  - SEVERITY={severity} TYPE={row['type']}{number} MSG={one_line(row['msg'])}"
        )
    return out


def render_error(name: str, reason: str) -> str:
    return block(
        name,
        ["STATUS=ERROR", f"REASON={one_line(reason)}", "ISSUE_COUNT=1"],
    )


# ── gh ────────────────────────────────────────────────────────────────────────


def gh(*args: str) -> str:
    try:
        r = subprocess.run(["gh", *args], check=False, capture_output=True, text=True)
    except OSError as e:
        raise Error(f"gh_unavailable: {e}") from e
    if r.returncode:
        raise Error(f"gh {' '.join(args[:3])} failed: {one_line(r.stderr, 150)}")
    return r.stdout


def json_stream(text: str) -> list:
    """Every JSON document in ``text``, with top-level arrays flattened.

    ``gh api --paginate`` prints one array per page back to back, which is not
    one JSON document.
    """
    decoder = json.JSONDecoder()
    items: list = []
    i = 0
    while i < len(text):
        if text[i].isspace():
            i += 1
            continue
        value, i = decoder.raw_decode(text, i)
        items.extend(value if isinstance(value, list) else [value])
    return items


def gh_list(path: str) -> list:
    sep = "&" if "?" in path else "?"
    return json_stream(gh("api", "--paginate", f"{path}{sep}per_page=100"))


def resolve_repo(repo: str | None) -> str:
    if repo:
        return repo
    name = gh("repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner")
    if not name.strip():
        raise Error("repo_unresolved: pass --repo OWNER/NAME")
    return name.strip()


def fetch_labels(repo: str) -> list[dict]:
    labels = json.loads(
        gh(
            "label",
            "list",
            "-R",
            repo,
            "--limit",
            str(LABEL_LIMIT),
            "--json",
            "name,color,description",
        )
    )
    if len(labels) >= LABEL_LIMIT:
        raise Error(
            f"label_list_truncated: {repo} returned {len(labels)} labels, the "
            "listing limit; an existing label could read as missing"
        )
    return labels


def fetch_taxonomy(repo: str, path: str) -> dict:
    """The taxonomy on the default branch; {} when the repository has none."""
    try:
        text = gh(
            "api",
            f"repos/{repo}/contents/{path}",
            "-H",
            "Accept: application/vnd.github.raw",
        )
    except Error as e:
        if "HTTP 404" in str(e):
            return {}
        raise  # any other failure is not "no taxonomy"
    return json.loads(text)


def normalize_item(raw: dict, is_pr: bool | None = None) -> dict:
    """One issue or PR in the shape the pure functions read."""
    return {
        "number": raw.get("number"),
        "title": raw.get("title") or "",
        "body": raw.get("body") or "",
        "labels": label_names(raw),
        "is_pr": bool(raw.get("is_pr")) if is_pr is None else is_pr,
        "files": list(raw.get("files") or []),
    }


def fetch_item(repo: str, number: int, is_pr: bool) -> dict:
    raw = json.loads(gh("api", f"repos/{repo}/issues/{number}"))
    item = normalize_item(raw, is_pr)
    if is_pr:
        item["files"] = [
            f["filename"] for f in gh_list(f"repos/{repo}/pulls/{number}/files")
        ]
    return item


def read_json(path: str) -> object:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_item(a: argparse.Namespace) -> dict:
    number = a.pr if getattr(a, "pr", None) is not None else a.issue
    if not a.fixture:
        if number is None:
            raise Error("no_item: pass --issue, --pr or --fixture")
        return fetch_item(
            resolve_repo(a.repo), number, getattr(a, "pr", None) is not None
        )
    data = read_json(a.fixture)
    if isinstance(data, list):
        matches = [d for d in data if d.get("number") == number]
        if len(matches) != 1:
            raise Error(f"fixture_item: {len(matches)} items numbered {number}")
        data = matches[0]
    if not isinstance(data, dict):
        raise Error("fixture_item: expected an object or a list of objects")
    return normalize_item(data, True if getattr(a, "pr", None) is not None else None)


def load_repo_labels(a: argparse.Namespace) -> list[str]:
    if a.repo_labels:
        return label_names({"labels": read_json(a.repo_labels)})
    return [lb["name"] for lb in fetch_labels(resolve_repo(a.repo))]


def load_taxonomy(a: argparse.Namespace) -> dict:
    if a.taxonomy:
        tax = read_json(a.taxonomy)
    else:
        tax = fetch_taxonomy(resolve_repo(a.repo), a.taxonomy_path)
    problems = check_taxonomy(tax)
    if problems:
        raise Error(f"taxonomy_invalid: {problems[0]} ({len(problems)} problem(s))")
    return tax  # type: ignore[return-value]


# ── Subcommands ───────────────────────────────────────────────────────────────


def cmd_classify(a: argparse.Namespace, cfg: Config) -> int:
    result = classify(
        load_item(a), load_taxonomy(a), load_repo_labels(a), cfg, a.ignore_existing
    )
    print(json.dumps(result, indent=1))
    return 0


def cmd_validate(a: argparse.Namespace, cfg: Config) -> int:
    proposals = read_proposals(read_json(a.labels_file))
    result = validate(
        proposals, load_item(a), load_repo_labels(a), cfg, a.min_evidence_chars
    )
    print(json.dumps(result, indent=1))
    return 0


def apply_action(repo: str, action: dict) -> None:
    fields = ["-f", f"color={action['color']}"]
    if "description" in action:
        fields += ["-f", f"description={action['description']}"]
    if action["op"] == "create":
        gh(
            "api",
            "-X",
            "POST",
            f"repos/{repo}/labels",
            "-f",
            f"name={action['label']}",
            *fields,
        )
    elif action["op"] == "update":
        gh(
            "api",
            "-X",
            "PATCH",
            f"repos/{repo}/labels/{quote(action['label'], safe='')}",
            *fields,
        )
    elif action["op"] == "rename":
        gh(
            "api",
            "-X",
            "PATCH",
            f"repos/{repo}/labels/{quote(action['from'], safe='')}",
            "-f",
            f"new_name={action['label']}",
            *fields,
        )


def cmd_provision(a: argparse.Namespace, cfg: Config) -> int:
    name = "ISSUE LABELS PROVISION"
    repo = resolve_repo(a.repo)
    tax = read_json(a.taxonomy) if a.taxonomy else fetch_taxonomy(repo, a.taxonomy_path)
    if not tax:
        raise Error(
            f"taxonomy_missing: {a.taxonomy or a.taxonomy_path} is empty or absent"
        )
    actions, problems = plan_provision(tax, fetch_labels(repo), cfg)  # type: ignore[arg-type]
    head = [f"REPO={repo}", f"DRY_RUN={'true' if a.dry_run else 'false'}"]
    if problems:
        rows = [{"type": "taxonomy_invalid", "msg": p} for p in problems]
        print(block(name, [*head, "APPLIED=0", *status_lines(rows, "ERROR")]))
        return 1
    applied = 0
    failure: list[dict] = []
    for action in actions:
        if action["op"] == "unchanged" or a.dry_run:
            continue
        try:
            apply_action(repo, action)
        except Error as e:
            failure = [{"type": "write_failed", "msg": f"{action['label']}: {e}"}]
            break
        applied += 1
    counts = {
        op: sum(x["op"] == op for x in actions)
        for op in ("create", "update", "rename", "unchanged")
    }
    rows = [
        f"  - OP={x['op']} LABEL={x['label']}"
        + (f" FROM={x['from']}" if "from" in x else "")
        for x in actions
    ]
    lines = [
        *head,
        *(f"{op.upper()}={n}" for op, n in counts.items()),
        f"APPLIED={applied}",
        *(["ACTIONS:", *rows] if rows else []),
        *status_lines(failure, "ERROR"),
    ]
    print(block(name, lines))
    return 1 if failure else 0


def cmd_unblock(a: argparse.Namespace, cfg: Config) -> int:
    name = "ISSUE LABELS UNBLOCK"
    repo = resolve_repo(a.repo)
    closing = json.loads(gh("api", f"repos/{repo}/issues/{a.issue}"))
    state = closing.get("state")
    lines = [
        f"REPO={repo}",
        f"ISSUE={a.issue}",
        f"ISSUE_STATE={state}",
        f"DRY_RUN={'true' if a.dry_run else 'false'}",
    ]
    rows: list[str] = []
    unblocked = 0
    dependents = (
        gh_list(f"repos/{repo}/issues/{a.issue}/dependencies/blocking")
        if state == "closed"
        else []
    )
    failure: list[dict] = []
    for dep in dependents:
        number = dep.get("number")
        issue_path = f"repos/{repo}/issues/{number}"
        skip = dependent_skip(dep, repo, cfg)
        # A failed call stops the run, and the report still lists the labels
        # removed before it.
        try:
            if skip:
                action, reason = "skip", skip
            else:
                action, reason = blockers_verdict(
                    gh_list(f"{issue_path}/dependencies/blocked_by")
                )
            if action == "unblock" and not a.dry_run:
                label = quote(cfg.blocked_label, safe="")
                gh("api", "-X", "DELETE", f"{issue_path}/labels/{label}")
        except Error as e:
            failure = [{"type": "dependent_failed", "number": number, "msg": str(e)}]
            rows.append(f"  - NUMBER={number} ACTION=error REASON=gh_failed")
            break
        if action == "unblock":
            unblocked += 1
        rows.append(f"  - NUMBER={number} ACTION={action} REASON={reason}")
    lines += [f"DEPENDENTS={len(dependents)}", f"UNBLOCKED={unblocked}"]
    if rows:
        lines += ["DEPENDENTS_DETAIL:", *rows]
    print(block(name, [*lines, *status_lines(failure, "ERROR")]))
    return 1 if failure else 0


def cmd_audit(a: argparse.Namespace, cfg: Config) -> int:
    name = "ISSUE LABELS AUDIT"
    repo = resolve_repo(a.repo)
    now = epoch(a.now) if a.now else time.time()
    issues = [
        i for i in gh_list(f"repos/{repo}/issues?state=open") if "pull_request" not in i
    ]
    findings: list[dict] = []
    for issue in issues:
        labels = label_names(issue)
        summary = issue.get("issue_dependencies_summary")
        is_blocked = cfg.blocked_label.lower() in {lb.lower() for lb in labels}
        # The summary counts links without listing them; read the list when a
        # link exists, when the summary is absent, or when blocked needs one.
        linked = summary is None or (summary.get("total_blocked_by") or 0) > 0
        blockers = (
            gh_list(f"repos/{repo}/issues/{issue['number']}/dependencies/blocked_by")
            if linked or is_blocked
            else []
        )
        needs = [lb for lb in labels if has_prefix(lb, cfg.needs_prefix)]
        events = (
            gh_list(f"repos/{repo}/issues/{issue['number']}/events") if needs else []
        )
        since = {lb: label_since(lb, events, issue["created_at"]) for lb in needs}
        findings += audit_issue(issue, blockers, since, now, a.needs_stale_days, cfg)
    findings.sort(key=lambda f: (FINDING_TYPES.index(f["type"]), f["number"]))
    counts = {t: sum(f["type"] == t for f in findings) for t in FINDING_TYPES}
    if a.json:
        print(
            json.dumps(
                {
                    "status": "WARN" if findings else "OK",
                    "repo": repo,
                    "open_issues": len(issues),
                    "counts": counts,
                    "findings": findings,
                },
                indent=1,
            )
        )
    else:
        for f in findings:
            f["where"] = f"#{f['number']} "
        lines = [
            f"REPO={repo}",
            f"OPEN_ISSUES={len(issues)}",
            f"NEEDS_STALE_DAYS={a.needs_stale_days}",
            *(f"{t.upper()}={n}" for t, n in counts.items()),
        ]
        print(block(name, [*lines, *status_lines(findings, "WARN")]))
    return 2 if findings and a.exit_code else 0


# ── CLI ───────────────────────────────────────────────────────────────────────


def build_parser() -> argparse.ArgumentParser:
    vocab = argparse.ArgumentParser(add_help=False)
    g = vocab.add_argument_group("label vocabulary")
    g.add_argument("--build-prefix", default="build:")
    g.add_argument("--area-prefix", default="area:")
    g.add_argument("--core-prefix", default="core:")
    g.add_argument("--needs-prefix", default="needs:")
    g.add_argument("--blocked-label", default="blocked")
    g.add_argument(
        "--type-labels",
        default="bug,enhancement,chore,docs,security,refactor",
        help="comma-separated type labels; an item needs one",
    )
    g.add_argument(
        "--type-map",
        default=(
            "bug=bug,fix;enhancement=feature,enhancement,feat,perf;"
            "chore=chore,test,build,ci;docs=docs;refactor=refactor"
        ),
        help="label=keyword,... per type, ';'-separated; keywords are the "
        "[Bracket] word or the conventional-commit type of a title",
    )
    g.add_argument(
        "--never-derive",
        default="security",
        help="comma-separated type labels classify never sets from a title",
    )
    repo = argparse.ArgumentParser(add_help=False)
    repo.add_argument("--repo", help="OWNER/NAME (default: gh resolves from cwd)")
    tax = argparse.ArgumentParser(add_help=False)
    tax.add_argument(
        "--taxonomy", help="taxonomy JSON file (default: read from the repo)"
    )
    tax.add_argument(
        "--taxonomy-path",
        default=DEFAULT_TAXONOMY_PATH,
        help="taxonomy path in the repo, read from the default branch",
    )
    item = argparse.ArgumentParser(add_help=False)
    item.add_argument("--issue", type=int, help="issue number")
    item.add_argument(
        "--fixture",
        help="read the item from JSON (an object, or a list plus --issue/--pr)",
    )
    item.add_argument(
        "--repo-labels", help="read the repository's labels from JSON instead of gh"
    )

    ap = argparse.ArgumentParser(description=(__doc__ or "").split("\n\n")[0])
    sub = ap.add_subparsers(dest="command", required=True)

    p = sub.add_parser(
        "provision",
        parents=[vocab, repo, tax],
        help="create, update or rename build and area labels from the taxonomy",
    )
    p.add_argument(
        "--dry-run", action="store_true", help="print the actions without writing"
    )
    p.set_defaults(run=cmd_provision, block="ISSUE LABELS PROVISION")

    p = sub.add_parser(
        "classify",
        parents=[vocab, repo, tax, item],
        help="labels an issue or PR's title, body and files point at",
    )
    p.add_argument("--pr", type=int, help="pull request number")
    p.add_argument(
        "--ignore-existing",
        action="store_true",
        help="derive as if the item had no labels (for measuring agreement)",
    )
    p.set_defaults(run=cmd_classify, block=None)

    p = sub.add_parser(
        "validate",
        parents=[vocab, repo, item],
        help="filter a model-written labels file",
    )
    p.add_argument(
        "--labels-file",
        required=True,
        help='JSON: {"labels": [{"name": ..., "evidence": ...}]}',
    )
    p.add_argument(
        "--min-evidence-chars",
        type=int,
        default=12,
        help="shortest quote accepted as evidence for a needs label",
    )
    p.set_defaults(run=cmd_validate, block=None)

    p = sub.add_parser(
        "unblock",
        parents=[vocab, repo],
        help="clear the blocked label from issues a closed issue was blocking",
    )
    p.add_argument("--issue", type=int, required=True, help="the issue that closed")
    p.add_argument(
        "--dry-run", action="store_true", help="print the decisions without writing"
    )
    p.set_defaults(run=cmd_unblock, block="ISSUE LABELS UNBLOCK")

    p = sub.add_parser(
        "audit", parents=[vocab, repo], help="sweep open issues for label gaps"
    )
    p.add_argument("--needs-stale-days", type=int, default=30)
    p.add_argument("--now", help="ISO time to measure staleness from (default: now)")
    p.add_argument("--json", action="store_true", help="print findings as JSON")
    p.add_argument(
        "--exit-code", action="store_true", help="exit 2 when there are findings"
    )
    p.set_defaults(run=cmd_audit, block="ISSUE LABELS AUDIT")
    return ap


def config_from(a: argparse.Namespace) -> Config:
    for flag in ("build_prefix", "area_prefix", "core_prefix", "needs_prefix"):
        if not getattr(a, flag).strip():
            # An empty prefix would match, and let provision write, every label.
            raise Error(f"empty_prefix: --{flag.replace('_', '-')} must not be empty")
    if not a.blocked_label.strip():
        raise Error("empty_label: --blocked-label must not be empty")
    return Config(
        build_prefix=a.build_prefix,
        area_prefix=a.area_prefix,
        core_prefix=a.core_prefix,
        needs_prefix=a.needs_prefix,
        blocked_label=a.blocked_label,
        type_labels=tuple(t.strip() for t in a.type_labels.split(",") if t.strip()),
        type_keywords=parse_type_map(a.type_map),
        never_derive=frozenset(
            t.strip() for t in a.never_derive.split(",") if t.strip()
        ),
    )


def main(argv: list[str]) -> int:
    a = build_parser().parse_args(argv)
    try:
        return a.run(a, config_from(a))
    except (Error, KeyError, TypeError, ValueError, OSError) as e:
        reason = str(e) if isinstance(e, Error) else f"{type(e).__name__}: {e}"
        if a.block and not getattr(a, "json", False):
            print(render_error(a.block, reason))
        else:
            print(
                json.dumps(
                    {"status": "ERROR", "reason": one_line(reason, 200)}, indent=1
                )
            )
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

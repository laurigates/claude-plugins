#!/usr/bin/env python3
"""Sweep auto-invokable skill descriptions for shared `Use when` trigger n-grams.

Issue #2244: sibling skills that describe one intent with the same trigger
phrase give the router no discriminator, so a generalist with adjacent
vocabulary wins and the specialists never fire. The clusters in that issue
were found by hand; this sweep finds the class deterministically, so a
description rewrite can be checked for collisions it introduces or removes.

Method
------
1. Read every auto-invokable skill from
   `python3 scripts/audit-skill-descriptions.py --auto-invokable --json --all --list`
   (or from `--input FILE` / `-` for stdin). That audit already parses YAML
   block scalars and knows which skills carry `disable-model-invocation: true`
   — a gated skill never competes for a router match (#2244, 2026-08-15), so
   it is excluded at the source rather than re-derived here.
2. Take the text after the first literal `Use when` (the matcher's trigger
   clause, #1278). A description without one is counted, not tokenized.
3. Split the clause at punctuation, lowercase it, and form 2- and 3-grams
   within each segment. An n-gram may not start or end with a stopword, so
   `run the tests` is a candidate and `the tests` is not, and an n-gram made
   only of stopwords and trigger-framing words (`user mentions`, `user says`)
   is dropped: it frames a trigger rather than naming one. `user mentions
   helm` survives, because `helm` is the part two siblings actually share.
4. An n-gram carried by two or more distinct skills is a collision. Phrases
   carried by more than `--max-df` skills are treated as boilerplate rather
   than a discriminator two siblings share, and are counted separately
   rather than reported — a backstop for framing phrases the word list does
   not name yet.
5. A shorter n-gram is dropped when a longer one containing it is carried by
   exactly the same skills, so one shared phrase is reported once.

Weighting: a collision spanning two or more plugins counts double
(`WEIGHT = skills * 2`), because a cross-plugin pair is the harder case to
notice in review — each plugin's README reads fine on its own.

Output follows .claude/rules/structured-script-output.md. The sweep is
ADVISORY: collisions report `STATUS=WARN` and exit 0. Only a sweep that could
not run — unparseable input, or zero skills scanned — is `STATUS=ERROR`
(exit 1), so a misfire can never read as a clean corpus (#2219).

Usage:
    python3 scripts/check-description-collisions.py
    python3 scripts/check-description-collisions.py --max-issues 50
    python3 scripts/check-description-collisions.py --input audit.json
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

USE_WHEN_RE = re.compile(r"\buse when\b", re.IGNORECASE)
SEGMENT_SPLIT_RE = re.compile(r"[,;:()\[\]/!?]|\.(?:\s|$)|\s[-–—]\s")
TOKEN_RE = re.compile(r"[a-z0-9][a-z0-9+#]*(?:[-.][a-z0-9+#]+)*")

# A word block reads better than ~150 one-word list lines, hence the noqa.
STOPWORDS = frozenset(
    """
    a an the and or nor but if then than so as at by for from in into of on
    onto to with without within via per over under up out off about across
    after before between during through is are was were be been being am
    it its this that these those there their them they he she we you your
    yours our i me my any all each every some no not only just also
    do does did done has have had can could should would will may might must
    when where which who whom whose what why how while whether
    e.g i.e etc vs
    """.split()  # noqa: SIM905
)

# Words that frame a trigger ("the user mentions X") without naming one. An
# n-gram built only from these and stopwords says nothing about intent.
FRAMING = frozenset(
    """
    user users mention mentions mentioning mentioned say says said ask asks
    asking asked want wants wanting need needs needing
    """.split()  # noqa: SIM905
)
POSSESSIVE_RE = re.compile(r"['’]s\b")

DEFAULT_MAX_DF = 12
DEFAULT_MAX_ISSUES = 25
NGRAM_SIZES = (2, 3)


def emit_error(issue_type: str, msg: str, counters: dict[str, object]) -> int:
    print("=== DESCRIPTION COLLISIONS ===")
    for key, value in counters.items():
        print(f"{key}={value}")
    print("STATUS=ERROR")
    print("ISSUE_COUNT=1")
    print("ISSUES:")
    print(f"  - SEVERITY=ERROR TYPE={issue_type} MSG={msg}")
    print("=== END DESCRIPTION COLLISIONS ===")
    return 1


def load_records(args: argparse.Namespace) -> tuple[object | None, str]:
    """Return (parsed JSON, source label) or (None, error message)."""
    if args.input is not None:
        try:
            raw = (
                sys.stdin.read()
                if args.input == "-"
                else Path(args.input).read_text(encoding="utf-8")
            )
        except OSError as exc:
            return None, f"cannot read input: {exc}"
        source = "stdin" if args.input == "-" else args.input
    else:
        audit = Path(args.project_dir) / "scripts" / "audit-skill-descriptions.py"
        cmd = [
            sys.executable,
            str(audit),
            "--auto-invokable",
            "--json",
            "--all",
            "--list",
        ]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        except OSError as exc:
            return None, f"cannot run audit: {exc}"
        if proc.returncode != 0:
            first = (proc.stderr.strip().splitlines() or ["no stderr"])[0]
            return None, f"audit exited {proc.returncode}: {first}"
        raw = proc.stdout
        source = "audit-skill-descriptions.py"
    try:
        return json.loads(raw), source
    except json.JSONDecodeError as exc:
        return None, f"input from {source} is not JSON: {exc.msg} at line {exc.lineno}"


def trigger_clause(text: str) -> str | None:
    match = USE_WHEN_RE.search(text)
    if match is None:
        return None
    return text[match.end() :]


def ngrams_of(clause: str) -> set[str]:
    grams: set[str] = set()
    text = POSSESSIVE_RE.sub("", clause.lower())
    for segment in SEGMENT_SPLIT_RE.split(text):
        tokens = TOKEN_RE.findall(segment)
        for size in NGRAM_SIZES:
            for start in range(len(tokens) - size + 1):
                window = tokens[start : start + size]
                if window[0] in STOPWORDS or window[-1] in STOPWORDS:
                    continue
                if all(tok in STOPWORDS or tok in FRAMING for tok in window):
                    continue
                grams.add(" ".join(window))
    return grams


def is_contained(short: str, long: str) -> bool:
    return f" {short} " in f" {long} "


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument(
        "--input",
        help="read audit JSON from FILE ('-' for stdin) instead of running the audit",
    )
    ap.add_argument(
        "--project-dir",
        default=str(REPO_ROOT),
        help="repo root holding scripts/audit-skill-descriptions.py",
    )
    ap.add_argument(
        "--max-df",
        type=int,
        default=DEFAULT_MAX_DF,
        help=f"n-grams carried by more skills than this are boilerplate (default {DEFAULT_MAX_DF})",
    )
    ap.add_argument(
        "--max-issues",
        type=int,
        default=DEFAULT_MAX_ISSUES,
        help=f"cap on collisions listed under ISSUES (default {DEFAULT_MAX_ISSUES}; 0 = all)",
    )
    args = ap.parse_args()

    data, source = load_records(args)
    if data is None:
        return emit_error("malformed_input", source, {"SKILLS_SCANNED": 0})
    if not isinstance(data, list):
        return emit_error(
            "malformed_input",
            f"expected a JSON array of skill records, got {type(data).__name__}",
            {"SKILLS_SCANNED": 0},
        )

    skills: dict[str, dict] = {}
    malformed = 0
    for rec in data:
        if not isinstance(rec, dict) or not rec.get("plugin") or not rec.get("skill"):
            malformed += 1
            continue
        if rec.get("auto_invokable") is False:
            continue
        skills[f"{rec['plugin']}/{rec['skill']}"] = rec
    if malformed:
        return emit_error(
            "malformed_input",
            f"{malformed} record(s) lack plugin/skill keys",
            {"SKILLS_SCANNED": len(skills)},
        )
    if not skills:
        return emit_error(
            "nothing_scanned",
            "no auto-invokable skill records in input — a misfire, not a clean corpus",
            {"SKILLS_SCANNED": 0},
        )

    preview_only = 0
    no_trigger = 0
    carriers: dict[str, set[str]] = defaultdict(set)
    for skill_id, rec in skills.items():
        text = rec.get("description_full")
        if not isinstance(text, str) or not text:
            text = rec.get("description") or ""
            if text.endswith("..."):
                preview_only += 1
        clause = trigger_clause(text)
        if clause is None:
            no_trigger += 1
            continue
        for gram in ngrams_of(clause):
            carriers[gram].add(skill_id)

    shared = {g: s for g, s in carriers.items() if len(s) >= 2}
    boilerplate = {g for g, s in shared.items() if len(s) > args.max_df}
    candidates = {g: frozenset(s) for g, s in shared.items() if g not in boilerplate}
    maximal = {
        g: s
        for g, s in candidates.items()
        if not any(
            h != g and candidates[h] == s and is_contained(g, h) for h in candidates
        )
    }

    rows = []
    for gram, members in maximal.items():
        plugins = {m.split("/", 1)[0] for m in members}
        weight = len(members) * (2 if len(plugins) > 1 else 1)
        rows.append((weight, len(members), len(plugins), gram, sorted(members)))
    rows.sort(key=lambda r: (-r[0], -r[1], r[3]))

    cross = sum(1 for r in rows if r[2] > 1)
    shown = rows if args.max_issues <= 0 else rows[: args.max_issues]
    issues = []
    if preview_only:
        issues.append(
            f"  - SEVERITY=WARN TYPE=truncated_input COUNT={preview_only} "
            "MSG=records carry only the 120-char description preview, so their Use-when clause may be cut; "
            "feed audit JSON that includes description_full"
        )
    for weight, n_skills, n_plugins, gram, members in shown:
        issues.append(
            f'  - SEVERITY=WARN TYPE=trigger_collision NGRAM="{gram}" SKILLS={n_skills} '
            f"PLUGINS={n_plugins} WEIGHT={weight} MEMBERS={','.join(members)}"
        )

    status = "WARN" if rows or preview_only else "OK"
    print("=== DESCRIPTION COLLISIONS ===")
    print(f"SOURCE={source}")
    print(f"SKILLS_SCANNED={len(skills)}")
    print(f"NO_USE_WHEN_SKIPPED={no_trigger}")
    print(f"PREVIEW_ONLY={preview_only}")
    print(f"NGRAM_SIZES={','.join(str(n) for n in NGRAM_SIZES)}")
    print(f"MAX_DF={args.max_df}")
    print(f"BOILERPLATE_EXCLUDED={len(boilerplate)}")
    print(f"COLLISION_COUNT={len(rows)}")
    print(f"CROSS_PLUGIN_COLLISIONS={cross}")
    print(f"WEIGHTED_SCORE={sum(r[0] for r in rows)}")
    print(f"ISSUES_SHOWN={len(shown)}")
    print(f"STATUS={status}")
    print(f"ISSUE_COUNT={len(rows) + (1 if preview_only else 0)}")
    if issues:
        print("ISSUES:")
        print("\n".join(issues))
    print("=== END DESCRIPTION COLLISIONS ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())

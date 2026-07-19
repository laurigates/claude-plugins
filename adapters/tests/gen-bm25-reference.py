# /// script
# requires-python = ">=3.10"
# dependencies = ["rank-bm25==0.2.2"]
# ///
"""Regenerate tests/fixtures/bm25-reference.json (DESIGN §7.1).

One-shot generator, run via `uv run tests/gen-bm25-reference.py` from
adapters/. It snapshots ~20 real skill "name description" documents from the
checkout, scores ~10 queries with the reference implementation
(rank_bm25.BM25Okapi), and writes the corpus + queries + expected rank order
to the committed fixture. The bun test (tests/bm25.test.ts) then asserts our
DIY BM25 reproduces the rank order — NOT the raw scores: rank_bm25 uses an
epsilon-floored classic IDF while ours uses the Lucene non-negative IDF, so
absolute scores legitimately differ while rank order should agree on queries
whose terms are not corpus-saturated.

Tokenization matches core/bm25.ts exactly: lowercase, split [^a-z0-9]+.
Rank order: documents with score > 0, sorted by (-score, doc index).
"""

import json
import re
from pathlib import Path

from rank_bm25 import BM25Okapi

ADAPTERS = Path(__file__).resolve().parent.parent
REPO = ADAPTERS.parent
FIXTURE = ADAPTERS / "tests" / "fixtures" / "bm25-reference.json"

# 20 real skills, spanning plugins and vocabulary. The corpus TEXT is stored
# in the fixture, so later description edits do not invalidate it — rerun
# this script only when you deliberately want a fresh snapshot.
SKILL_IDS = [
    "git-plugin:git-commit",
    "git-plugin:git-pr",
    "git-plugin:git-push",
    "git-plugin:git-coworker-check",
    "git-plugin:gh-cli-agentic",
    "tools-plugin:jq-json-processing",
    "tools-plugin:d2-diagrams",
    "tools-plugin:shell-expert",
    "tools-plugin:fd-file-finding",
    "testing-plugin:test-quick",
    "testing-plugin:mutation-testing",
    "python-plugin:uv-run",
    "python-plugin:ruff-linting",
    "typescript-plugin:knip-dead-code",
    "typescript-plugin:bun-test",
    "kubernetes-plugin:helm-release-recovery",
    "networking-plugin:dns-tools",
    "container-plugin:python-containers",
    "macos-plugin:macos-disk-usage",
    "obsidian-plugin:vault-orphans",
]

QUERIES = [
    "commit my staged changes with a good message",
    "open a pull request for review",
    "run the fast unit tests only",
    "extract fields from a json file",
    "recover a failed helm upgrade",
    "check dns record propagation",
    "shrink a python docker image",
    "find unused exports in typescript",
    "run a python script without a virtualenv",
    "free up disk space on my mac",
]


def tokenize(text: str) -> list[str]:
    return [t for t in re.split(r"[^a-z0-9]+", text.lower()) if t]


def frontmatter_field(path: Path, field: str) -> str:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return ""
    for line in lines[1:]:
        if line.strip() == "---":
            break
        m = re.match(rf"^{field}:\s*(.*)$", line)
        if m:
            value = m.group(1).strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
                value = value[1:-1]
            return value
    return ""


def main() -> None:
    corpus: list[dict[str, str]] = []
    for skill_id in SKILL_IDS:
        plugin, skill = skill_id.split(":", 1)
        path = REPO / plugin / "skills" / skill / "SKILL.md"
        name = frontmatter_field(path, "name") or skill
        description = frontmatter_field(path, "description")
        if not description:
            raise SystemExit(f"missing description for {skill_id}")
        corpus.append({"id": skill_id, "text": f"{name} {description}"})

    tokenized = [tokenize(doc["text"]) for doc in corpus]
    bm25 = BM25Okapi(tokenized)

    cases = []
    for query in QUERIES:
        scores = bm25.get_scores(tokenize(query))
        ranked = sorted(
            (i for i, s in enumerate(scores) if s > 1e-12),
            key=lambda i: (-scores[i], i),
        )
        cases.append({"query": query, "expected_rank_order": ranked})

    FIXTURE.write_text(
        json.dumps(
            {
                "generator": "tests/gen-bm25-reference.py (rank-bm25 0.2.2)",
                "note": "expected_rank_order = doc indices with score>0, by (-score, idx)",
                "corpus": corpus,
                "cases": cases,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"wrote {FIXTURE} ({len(corpus)} docs, {len(cases)} queries)")


if __name__ == "__main__":
    main()

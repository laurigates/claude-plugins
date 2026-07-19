#!/usr/bin/env -S uv run --script --quiet
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6"]
# ///
"""Build the skill-catalog variants used as experiment arms.

Enumerates every `*-plugin/skills/*/SKILL.md` (the same 405-skill corpus the
repo's `scripts/audit-skill-descriptions.py` audits), reads the FULL
`description` from frontmatter (the audit's `--json` display-truncates it to
~100 chars — we must read the real text), and emits four catalog variants plus
a manifest:

    catalog.names.json    ids only, no descriptions           (arm C1)
    catalog.short.json    "Use when <first trigger>"  ≤40c    (arm C2)
    catalog.medium.json   "Use when <triggers>"       ≤80c    (arm C3)
    catalog.full.json     the current full description         (arm C4)
    catalog_manifest.json source SHA, content hashes, per-skill provenance

Design invariants (see the experiment plan and .claude/rules/skill-quality.md):

* The routing id is `<plugin>/<skill-dir>` (unique across plugins; matches the
  golden-set convention `tools-plugin/rg-code-search`). That id is what the
  model is asked to emit and what the grader matches on.
* Shortening is STRUCTURE-AWARE, never end-truncation of the whole string.
  Descriptions are `<domain>. Use when <triggers>.` — the routing-relevant part
  (the triggers) sits at the END, and naive truncation would delete it and the
  literal `Use when` substring that auto-invocation depends on (issue #1278).
  So we locate the `Use when` clause and truncate THAT, always retaining the
  literal `Use when` marker.
* The bands are genuine token-subsets: short ⊆ medium ⊆ full. `short` truncates
  the first trigger scenario to ≤40c; `medium` truncates the whole trigger
  clause to ≤80c; short's cut point ≤ medium's, so short is a prefix of medium.

Each catalog is `{"variant": ..., "source_sha": ..., "entries": [{id, text}]}`
where `text` is `""` for the names variant and `"<id>: <desc>"` otherwise — the
exact line injected into the router system prompt.

Usage:
    build-catalogs.py                 # write all four + manifest
    build-catalogs.py --validate      # rebuild, then assert invariants, exit 1 on failure
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

import yaml

# experiments/skill-catalog-routing/scripts/build-catalogs.py -> repo root
REPO_ROOT = Path(__file__).resolve().parents[3]
OUT_DIR = Path(__file__).resolve().parents[1] / "catalogs"

SHORT_MAX = 40
MEDIUM_MAX = 80

# Case-insensitive locator for the trigger clause. We keep the ORIGINAL casing
# of whatever matched (usually "Use when") so the literal survives.
_USE_WHEN_RE = re.compile(r"\buse when\b", re.IGNORECASE)
# Scenario separators inside a trigger clause: commas, semicolons, " or ".
_SCENARIO_SPLIT_RE = re.compile(r",|;|\bor\b", re.IGNORECASE)


def find_skills(root: Path) -> list[Path]:
    """All SKILL.md under *-plugin/skills/ (mirrors audit-skill-descriptions.py)."""
    skills: list[Path] = []
    for plugin_dir in sorted(root.glob("*-plugin")):
        if not plugin_dir.is_dir():
            continue
        skills_dir = plugin_dir / "skills"
        if not skills_dir.is_dir():
            continue
        for skill_md in sorted(skills_dir.rglob("SKILL.md")):
            skills.append(skill_md)
    return skills


def read_full_description(path: Path) -> str | None:
    """Parse frontmatter and return the FULL description string (not truncated)."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    if not text.startswith("---"):
        return None
    parts = text.split("\n---", 1)
    if len(parts) < 2:
        return None
    fm_text = parts[0].lstrip("-").lstrip("\n")
    try:
        data = yaml.safe_load(fm_text)
    except yaml.YAMLError:
        return None
    if not isinstance(data, dict):
        return None
    desc = data.get("description")
    if not isinstance(desc, str):
        return None
    # Collapse internal whitespace (block scalars fold to multi-space); the
    # listing the model sees is single-line.
    return " ".join(desc.split())


def routing_id(path: Path) -> str:
    rel = path.relative_to(REPO_ROOT)
    return f"{rel.parts[0]}/{path.parent.name}"


def _truncate_word_boundary(s: str, n: int) -> str:
    """Truncate to ≤ n chars at a word boundary, stripping trailing punctuation
    and dangling conjunctions."""
    s = s.strip()
    if len(s) <= n:
        return s.rstrip(" ,;.").strip()
    cut = s[:n]
    # Only back off to a word boundary if we actually cut mid-word (the char at
    # the cut point is not a space). A cut that lands exactly on a boundary is
    # kept — this preserves a scenario token that fit exactly (e.g. a long
    # slash-joined "watching/monitoring/babysitting").
    if s[n] != " " and " " in cut:
        cut = cut[: cut.rfind(" ")]
    cut = cut.rstrip(" ,;.")
    # Drop a dangling trailing conjunction/preposition — but never "use"/"when",
    # which are the literal marker auto-invocation depends on (#1278).
    words = cut.split()
    while words and words[-1].lower() in {"or", "and", "the", "a", "to", "of", "for", "in", "on", "with"}:
        words.pop()
    return " ".join(words)


def shorten(desc: str) -> tuple[str, str, str]:
    """Return (short_text, medium_text, provenance) for a full description.

    provenance: "mechanical" (extracted from a Use-when clause) or
    "prefix" (no Use-when marker present; fall back to a leading prefix).
    """
    m = _USE_WHEN_RE.search(desc)
    if not m:
        # No trigger marker — take leading prefixes. Monotone by construction
        # (short prefix ⊆ medium prefix).
        medium = _truncate_word_boundary(desc, MEDIUM_MAX)
        short = _truncate_word_boundary(desc, SHORT_MAX)
        return short, medium, "prefix"

    clause = desc[m.start():].strip()  # "Use when <triggers>."
    # medium: truncate the whole clause to ≤80, always keeping "Use when".
    medium = _truncate_word_boundary(clause, MEDIUM_MAX)
    # short: first scenario only, truncated to ≤40.
    # The clause is "Use when <scenario1>, <scenario2>, ...". Split the part
    # AFTER "Use when" on scenario separators and keep the first.
    prefix_len = m.end() - m.start()  # length of "Use when" as it appeared
    marker = clause[:prefix_len]  # preserve original casing, e.g. "Use when"
    rest = clause[prefix_len:].lstrip()
    first_scenario = _SCENARIO_SPLIT_RE.split(rest, maxsplit=1)[0].strip()
    short_candidate = f"{marker} {first_scenario}".strip()
    short = _truncate_word_boundary(short_candidate, SHORT_MAX)
    return short, medium, "mechanical"


def _domain_of(desc: str) -> str:
    """The capability/domain phrase: everything BEFORE the 'Use when' clause.

    Descriptions are '<domain>. Use when <triggers>.' — the domain sentence
    ('ripgrep fast code search: smart defaults, regex, file filtering') is what
    the trigger-first short/medium variants dropped. Returns the whole
    description when there is no 'Use when' marker.
    """
    m = _USE_WHEN_RE.search(desc)
    head = desc[: m.start()] if m else desc
    return head.strip().rstrip(" .;,")


def domain_shorten(desc: str) -> tuple[str, str, str]:
    """Return (domain_short ≤40c, domain_medium ≤80c, provenance).

    The DOMAIN-preserving counterpart of shorten(): keep the capability phrase,
    drop the 'Use when' trigger tail. Token-matched to short/medium so the A/B
    is domain-first vs trigger-first at equal budget. These deliberately do NOT
    carry 'Use when' — the experiment measures routing signal, not the
    production auto-invocation matcher (see compact_shorten for that).
    """
    domain = _domain_of(desc)
    if not domain:
        # Degenerate: 'Use when' at position 0. Fall back to the trigger form.
        s, m_, _ = shorten(desc)
        return s, m_, "domain-fallback"
    d_medium = _truncate_word_boundary(domain, MEDIUM_MAX)
    d_short = _truncate_word_boundary(domain, SHORT_MAX)
    return d_short, d_medium, "domain"


def compact_shorten(desc: str) -> tuple[str, str]:
    """Return (compact_text ≤80c, provenance) — the production recommendation
    candidate: a short domain head PLUS 'Use when <first trigger>', keeping the
    literal 'Use when' so it stays valid for the real auto-invocation matcher
    (#1278). Best-of-both: capability phrase for routing + trigger for the
    matcher, within the medium budget.
    """
    domain = _domain_of(desc)
    short_trigger, _, prov = shorten(desc)  # "Use when <first scenario>" ≤40
    if prov != "mechanical" or not domain:
        # No clean domain+trigger split — fall back to the medium trigger form.
        _, medium, _ = shorten(desc)
        return _truncate_word_boundary(medium, MEDIUM_MAX), "compact-fallback"
    # Budget the domain head so "domain: Use when <trigger>" fits ≤80.
    # Reserve room for ": " + the trigger clause.
    reserve = len(short_trigger) + 2
    head_budget = max(0, MEDIUM_MAX - reserve)
    head = _truncate_word_boundary(domain, head_budget)
    # Strip a trailing dangling separator (em/en-dash, colon) left by truncating
    # the domain mid-phrase, so the join reads "<head>: Use when ..." cleanly.
    head = head.rstrip(" —–-:;,.").strip()
    if head:
        combined = f"{head}: {short_trigger}"
    else:
        combined = short_trigger
    return _truncate_word_boundary(combined, MEDIUM_MAX), "compact"


def build() -> tuple[list[dict], str]:
    sha = "unknown"
    try:
        sha = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=REPO_ROOT, capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, OSError):
        pass

    rows = []
    for path in find_skills(REPO_ROOT):
        desc = read_full_description(path)
        if desc is None or not desc.strip():
            # Skills with no usable description are still real routing targets;
            # keep the id with an empty description so the closed set is complete.
            rid = routing_id(path)
            rows.append({
                "id": rid, "full": "", "medium": "", "short": "",
                "domain-short": "", "domain-medium": "", "compact": "",
                "provenance": "empty", "full_len": 0,
            })
            continue
        short, medium, provenance = shorten(desc)
        d_short, d_medium, _ = domain_shorten(desc)
        compact, _ = compact_shorten(desc)
        rows.append({
            "id": routing_id(path),
            "full": desc,
            "medium": medium,
            "short": short,
            "domain-short": d_short,
            "domain-medium": d_medium,
            "compact": compact,
            "provenance": provenance,
            "full_len": len(desc),
        })
    return rows, sha


def _line(rid: str, text: str) -> str:
    return f"{rid}: {text}" if text else rid


def write_catalogs(rows: list[dict], sha: str) -> dict[str, str]:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    variants = {
        "names": lambda r: _line(r["id"], ""),
        "short": lambda r: _line(r["id"], r["short"]),
        "medium": lambda r: _line(r["id"], r["medium"]),
        "full": lambda r: _line(r["id"], r["full"]),
        "domain-short": lambda r: _line(r["id"], r["domain-short"]),
        "domain-medium": lambda r: _line(r["id"], r["domain-medium"]),
        "compact": lambda r: _line(r["id"], r["compact"]),
    }
    hashes = {}
    for variant, render in variants.items():
        entries = [{"id": r["id"], "line": render(r)} for r in rows]
        body = "\n".join(e["line"] for e in entries)
        payload = {
            "variant": variant,
            "source_sha": sha,
            "skill_count": len(entries),
            "entries": entries,
        }
        out = OUT_DIR / f"catalog.{variant}.json"
        out.write_text(json.dumps(payload, indent=2) + "\n")
        hashes[variant] = hashlib.sha256(body.encode()).hexdigest()[:16]
    return hashes


def write_manifest(rows: list[dict], sha: str, hashes: dict[str, str]) -> None:
    prov = {}
    for r in rows:
        prov[r["provenance"]] = prov.get(r["provenance"], 0) + 1
    manifest = {
        "source_sha": sha,
        "skill_count": len(rows),
        "content_hashes": hashes,
        "provenance_counts": prov,
        "band_char_ceilings": {"short": SHORT_MAX, "medium": MEDIUM_MAX},
        "per_skill": [
            {"id": r["id"], "provenance": r["provenance"], "full_len": r["full_len"]}
            for r in rows
        ],
    }
    (OUT_DIR / "catalog_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def validate(rows: list[dict]) -> int:
    """Assert the load-bearing invariants; return count of failures."""
    failures = 0

    def fail(msg: str) -> None:
        nonlocal failures
        failures += 1
        print(f"FAIL: {msg}", file=sys.stderr)

    for r in rows:
        if not r["full"]:
            continue  # empty-description skills are exempt from band checks
        # Band ceilings.
        if len(r["short"]) > SHORT_MAX:
            fail(f"{r['id']} short exceeds {SHORT_MAX}c: {len(r['short'])}")
        if len(r["medium"]) > MEDIUM_MAX:
            fail(f"{r['id']} medium exceeds {MEDIUM_MAX}c: {len(r['medium'])}")
        # Use-when preservation for mechanically-extracted variants (#1278 class).
        if r["provenance"] == "mechanical":
            if "use when" not in r["short"].lower():
                fail(f"{r['id']} short lost 'Use when': {r['short']!r}")
            if "use when" not in r["medium"].lower():
                fail(f"{r['id']} medium lost 'Use when': {r['medium']!r}")
        # Monotonicity: short must be a prefix of medium (token-subset).
        if r["short"] and not r["medium"].startswith(r["short"]):
            fail(f"{r['id']} short is not a prefix of medium:\n  short={r['short']!r}\n  medium={r['medium']!r}")

        # Domain-preserving variants: band ceilings + monotone within the domain
        # ladder. These deliberately do NOT carry 'Use when' (they keep the
        # capability phrase instead of the trigger tail).
        if len(r["domain-short"]) > SHORT_MAX:
            fail(f"{r['id']} domain-short exceeds {SHORT_MAX}c: {len(r['domain-short'])}")
        if len(r["domain-medium"]) > MEDIUM_MAX:
            fail(f"{r['id']} domain-medium exceeds {MEDIUM_MAX}c: {len(r['domain-medium'])}")
        if r["domain-short"] and not r["domain-medium"].startswith(r["domain-short"]):
            fail(f"{r['id']} domain-short is not a prefix of domain-medium:\n  ds={r['domain-short']!r}\n  dm={r['domain-medium']!r}")
        # Compact: within the medium ceiling and MUST keep the literal 'Use when'
        # (it is the best-of-both form intended to stay matcher-valid, #1278)
        # — except where the source had no clean domain+trigger split.
        if len(r["compact"]) > MEDIUM_MAX:
            fail(f"{r['id']} compact exceeds {MEDIUM_MAX}c: {len(r['compact'])}")
        if r["provenance"] == "mechanical" and _domain_of(r["full"]) and "use when" not in r["compact"].lower():
            fail(f"{r['id']} compact lost 'Use when': {r['compact']!r}")

    total = len(rows)
    print(f"Validated {total} skills; {failures} failures.", file=sys.stderr)
    return failures


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--validate", action="store_true", help="assert invariants; exit 1 on any failure")
    args = ap.parse_args()

    rows, sha = build()
    hashes = write_catalogs(rows, sha)
    write_manifest(rows, sha, hashes)

    prov = {}
    for r in rows:
        prov[r["provenance"]] = prov.get(r["provenance"], 0) + 1
    print(f"Wrote {len(rows)} skills to {OUT_DIR.relative_to(REPO_ROOT)}/ (sha {sha[:8]})")
    print(f"Provenance: {prov}")
    print(f"Content hashes: {hashes}")

    if args.validate:
        return 1 if validate(rows) else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())

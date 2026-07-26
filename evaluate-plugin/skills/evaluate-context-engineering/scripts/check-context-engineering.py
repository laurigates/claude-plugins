#!/usr/bin/env python3
"""check-context-engineering.py — Channel M scanner for the context-engineering benchmark.

THE CONVENTION (.claude/rules/context-engineering.md)
Anthropic's "New rules of context engineering for Claude 5 generation models"
names six shifts away from how this marketplace was originally authored:

  C1 rules            -> judgment            (stop over-constraining a capable model)
  C2 examples         -> interface design    (expressive params beat usage examples)
  C3 upfront context  -> progressive disclosure
  C4 repetition       -> single source of truth
  C5 (the 80% claim)  -> always-loaded budget discipline
  C6 simple specs     -> rich references     (code/scripts over prose)

WHAT THIS SCRIPT IS
A *deterministic proxy* pass ("Channel M") over the whole tree. It computes
mechanical evidence for each shift and ranks candidates. It deliberately does
NOT judge: a proxy cannot tell a load-bearing safety constraint from a
restatement of a model default. Judgment is Channel J's job (anchored 1-5
rubric, blind judges) — see docs/benchmarks/2026-07-context-engineering/.

Channel M and Channel J are reported separately and never blended.

DETERMINISM CONTRACT
Two runs over an unchanged tree must be byte-identical: no timestamps, no
absolute paths, no set/dict iteration order in output. `--json | sha256sum`
is a valid regression check.

Output: structured KEY=VALUE per .claude/rules/structured-script-output.md.

  --json                     full per-unit metrics (feeds metrics.json)
  --strict                   exit 1 when an ERROR-severity issue exists
  --target PATH              scope to one plugin dir or one skill dir
  --top N                    offenders listed per dimension (default 10)
  --always-loaded-budget N   chars; ERROR above it (default 100000). The ratchet
                             that stops the every-session surface growing.
  --project-dir PATH         repo root (default: this script's parent)
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from collections import defaultdict

SCHEMA_VERSION = 1

# --- proxy definitions (kept as module constants so the test fixture can cite them)

CONSTRAINT_RE = re.compile(
    r"\b(MUST NOT|MUST|NEVER|ALWAYS|DO NOT|DON'T|SHOULD NOT|AVOID|REQUIRED|FORBIDDEN)\b",
    re.IGNORECASE,
)

# A constraint sitting next to one of these is plausibly load-bearing (safety,
# irreversibility, money) rather than a restatement of a model default. Reported
# separately so the report can subtract it before proposing cuts.
SAFETY_RE = re.compile(
    r"\b(destructive|irreversible|force[- ]push|rm -rf|reset --hard|delete[sd]?|"
    r"credential|secret|token|password|exfiltrat|production|prod\b|data loss|"
    r"overwrit|clobber|drop table|permission|sudo)\b",
    re.IGNORECASE,
)
SAFETY_WINDOW = 160  # chars either side of the marker

EXAMPLE_HEADING_RE = re.compile(r"^#{2,}\s*.*\b(example|usage|sample)s?\b", re.IGNORECASE)
PARAMS_HEADING_RE = re.compile(r"^#{2,}\s*.*\b(parameter|argument|option|flag)s?\b", re.IGNORECASE)
PROCEDURAL_HEADING_RE = re.compile(
    r"^#{2,}\s*.*\b(step \d|steps|workflow|procedure|how to|checklist|recipe|"
    r"execution|your task|quick start)\b",
    re.IGNORECASE,
)
FENCE_RE = re.compile(r"^([ \t]*)(`{3,}|~{3,})(.*)$")
SHELLY_RE = re.compile(r"^\s*(bash|sh|shell|zsh|console)\s*$", re.IGNORECASE)

BOILERPLATE_SECTIONS = {
    "when_to_use": re.compile(r"^#{2,}\s*When to Use", re.IGNORECASE),
    "agentic_optimizations": re.compile(r"^#{2,}\s*Agentic Optimi", re.IGNORECASE),
}

SHINGLE_W = 8  # words per shingle
SHINGLE_MIN_SHARED = 20  # shared shingles before a pair is worth reporting
SHINGLE_MIN_CONTAINMENT = 0.15
SHINGLE_UBIQUITY_CAP = 20  # a shingle in >N units is boilerplate, not a pair signal

FLAT_BODY_CHARS = 10_000  # body this big with zero supporting files = flat
EXAMPLE_RATIO_FLAG = 0.25
CONSTRAINT_DENSITY_FLAG = 1.5  # markers per 1,000 chars
CONSTRAINT_MIN_MARKERS = 5  # below this the density is noise on a tiny file

SKILL_PATH_RE = re.compile(r"^[^/]+/skills/[^/]+/SKILL\.md$")
FIXTURE_MARKERS = ("/tests/fixtures/", "test-fixtures/", "/fixtures/")


# --------------------------------------------------------------------------- io


def read_text(path: str) -> str:
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def split_frontmatter(text: str) -> tuple[dict[str, str], str]:
    """Return (frontmatter-ish dict, body). Top-level `key: value` pairs only."""
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    raw = text[3:end]
    body = text[end + 4 :].lstrip("\n")
    fm: dict[str, str] = {}
    for line in raw.split("\n"):
        m = re.match(r"^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$", line)
        if m:
            fm[m.group(1)] = m.group(2).strip()
    return fm, body


def strip_code_fences(body: str) -> tuple[str, list[tuple[str, str]]]:
    """Return (prose-only text, [(info_string, block_text), ...])."""
    prose: list[str] = []
    blocks: list[tuple[str, str]] = []
    fence: str | None = None
    info = ""
    buf: list[str] = []
    for line in body.split("\n"):
        m = FENCE_RE.match(line)
        if fence is None:
            if m:
                fence = m.group(2)[0] * 3
                info = m.group(3).strip()
                buf = []
            else:
                prose.append(line)
        else:
            if m and m.group(2).startswith(fence) and not m.group(3).strip():
                blocks.append((info, "\n".join(buf)))
                fence = None
            else:
                buf.append(line)
    if fence is not None:  # unterminated fence: treat the remainder as a block
        blocks.append((info, "\n".join(buf)))
    return "\n".join(prose), blocks


def section_spans(body: str, pattern: re.Pattern[str]) -> list[tuple[int, int]]:
    """Line spans of every `## <pattern>` section (heading through next same-or-higher heading)."""
    lines = body.split("\n")
    spans = []
    i = 0
    while i < len(lines):
        if pattern.match(lines[i]):
            level = len(lines[i]) - len(lines[i].lstrip("#"))
            j = i + 1
            while j < len(lines):
                m = re.match(r"^(#{1,6})\s", lines[j])
                if m and len(m.group(1)) <= level:
                    break
                j += 1
            spans.append((i, j))
            i = j
        else:
            i += 1
    return spans


def span_chars(body: str, spans: list[tuple[int, int]]) -> int:
    lines = body.split("\n")
    return sum(len(line) + 1 for a, b in spans for line in lines[a:b])


# ------------------------------------------------------------------ discovery


def discover(root: str, target: str | None) -> tuple[list[str], list[str], str | None]:
    """Return (skill paths, rule paths, CLAUDE.md path) — all repo-relative, sorted."""
    skills: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(
            d for d in dirnames if d not in {".git", "node_modules", ".venv", "__pycache__"}
        )
        if "SKILL.md" not in filenames:
            continue
        rel = os.path.relpath(os.path.join(dirpath, "SKILL.md"), root)
        if any(marker in "/" + rel for marker in FIXTURE_MARKERS):
            continue
        if SKILL_PATH_RE.match(rel):
            skills.append(rel)
    skills.sort()

    rules_dir = os.path.join(root, ".claude", "rules")
    rules = sorted(
        os.path.relpath(os.path.join(rules_dir, f), root)
        for f in (os.listdir(rules_dir) if os.path.isdir(rules_dir) else [])
        if f.endswith(".md")
    )
    claude_md = "CLAUDE.md" if os.path.isfile(os.path.join(root, "CLAUDE.md")) else None

    if target:
        t = target.rstrip("/")
        skills = [s for s in skills if s == t or s.startswith(t + "/")]
        rules, claude_md = [], None
    return skills, rules, claude_md


# ------------------------------------------------------------------- analysis


def analyse_skill(root: str, rel: str) -> dict:
    text = read_text(os.path.join(root, rel))
    fm, body = split_frontmatter(text)
    prose, blocks = strip_code_fences(body)
    body_chars = len(body)

    # C1 — constraint density over prose only (code legitimately says "must").
    markers = list(CONSTRAINT_RE.finditer(prose))
    safety_adjacent = sum(
        1
        for m in markers
        if SAFETY_RE.search(prose[max(0, m.start() - SAFETY_WINDOW) : m.end() + SAFETY_WINDOW])
    )
    density = round(len(markers) * 1000 / body_chars, 3) if body_chars else 0.0

    # C2 — examples vs interface. Two masses: the narrow one (explicit
    # "## Examples/Usage" sections) and the broad one (every fenced block —
    # this repo teaches mostly by inline example, not by labelled section).
    example_spans = section_spans(body, EXAMPLE_HEADING_RE)
    example_chars = span_chars(body, example_spans)
    has_params = bool(section_spans(body, PARAMS_HEADING_RE))
    fenced_chars = sum(len(b) for _, b in blocks)
    # An arg spec that enumerates its alternatives (`--a|--b`, `{x,y}`) is the
    # "expressive interface" the post asks for; a bare `<path>` is not.
    arg_spec = fm.get("args", "")
    arg_enumerated = bool(re.search(r"[|{]", arg_spec))

    # C3 — progressive disclosure.
    skill_dir = os.path.dirname(os.path.join(root, rel))
    support_md, support_chars, has_scripts = [], 0, False
    for entry in sorted(os.listdir(skill_dir)):
        full = os.path.join(skill_dir, entry)
        if os.path.isdir(full):
            if entry in ("scripts", "references", "assets", "templates"):
                has_scripts = has_scripts or entry == "scripts"
                for sub in sorted(os.listdir(full)):
                    if sub.endswith(".md"):
                        support_md.append(f"{entry}/{sub}")
                        support_chars += os.path.getsize(os.path.join(full, sub))
        elif entry.endswith(".md") and entry != "SKILL.md":
            support_md.append(entry)
            support_chars += os.path.getsize(full)
    levels = 1 + (1 if support_md else 0) + (1 if has_scripts else 0)

    # C4 — mandated-boilerplate tax.
    boiler = {
        name: span_chars(body, section_spans(body, pat))
        for name, pat in sorted(BOILERPLATE_SECTIONS.items())
    }

    # C6 — mechanical prose with no bundled script.
    shell_blocks = [b for info, b in blocks if SHELLY_RE.match(info or "")]
    multiline_shell = sum(1 for b in shell_blocks if b.count("\n") >= 2)

    return {
        "path": rel,
        "plugin": rel.split("/")[0],
        "body_chars": body_chars,
        "est_tokens": body_chars // 4,
        "c1_markers": len(markers),
        "c1_safety_adjacent": safety_adjacent,
        "c1_density_per_1k": density,
        "c2_example_chars": example_chars,
        "c2_example_ratio": round(example_chars / body_chars, 3) if body_chars else 0.0,
        "c2_fenced_chars": fenced_chars,
        "c2_fenced_ratio": round(fenced_chars / body_chars, 3) if body_chars else 0.0,
        "c2_has_args": "args" in fm,
        "c2_has_argument_hint": "argument-hint" in fm,
        "c2_has_params_section": has_params,
        "c2_arg_enumerated": arg_enumerated,
        "c3_support_files": support_md,
        "c3_support_chars": support_chars,
        "c3_has_scripts": has_scripts,
        "c3_levels": levels,
        "c4_boilerplate_chars": boiler,
        "c6_shell_blocks": len(shell_blocks),
        "c6_multiline_shell_blocks": multiline_shell,
        "description_chars": len(fm.get("description", "")),
    }


def analyse_rule(root: str, rel: str) -> dict:
    text = read_text(os.path.join(root, rel))
    fm, body = split_frontmatter(text)
    scoped = "paths" in fm or re.search(r"^paths:", text, re.MULTILINE) is not None
    procedural = len(section_spans(body, PROCEDURAL_HEADING_RE))
    numbered = len(re.findall(r"^\s{0,3}\d+\.\s", body, re.MULTILINE))
    chars = len(text)
    return {
        "path": rel,
        "chars": chars,
        "est_tokens": chars // 4,
        "path_scoped": bool(scoped),
        "procedural_headings": procedural,
        "numbered_steps": numbered,
        # Intent-shaped == reads like a procedure you run when asked, not an
        # invariant you hold on every turn. Those are skill-shaped (see
        # agent-patterns-plugin:meta-context-diet).
        "intent_shaped": bool(procedural >= 1 or numbered >= 3),
    }


# ------------------------------------------------------- C4 shingle overlap


def shingles(text: str) -> set[int]:
    """Stable 64-bit shingle hashes.

    blake2b, not the builtin hash(): PYTHONHASHSEED randomises str hashing per
    process, which would make collisions — and therefore the pair counts —
    vary between runs, breaking the determinism contract.
    """
    words = re.findall(r"[a-z0-9]+", text.lower())
    if len(words) < SHINGLE_W:
        return set()
    return {
        int.from_bytes(
            hashlib.blake2b(" ".join(words[i : i + SHINGLE_W]).encode(), digest_size=8).digest(),
            "big",
        )
        for i in range(len(words) - SHINGLE_W + 1)
    }


def overlap_pairs(units: dict[str, set[int]]) -> tuple[list[dict], int]:
    index: dict[int, list[str]] = defaultdict(list)
    for name in sorted(units):
        for sh in units[name]:
            index[sh].append(name)

    ubiquitous = 0
    shared: dict[tuple[str, str], int] = defaultdict(int)
    for sh, names in index.items():
        if len(names) < 2:
            continue
        if len(names) > SHINGLE_UBIQUITY_CAP:
            ubiquitous += 1
            continue
        for i in range(len(names)):
            for j in range(i + 1, len(names)):
                shared[(names[i], names[j])] += 1

    pairs = []
    for (a, b), count in shared.items():
        if count < SHINGLE_MIN_SHARED:
            continue
        smaller = min(len(units[a]), len(units[b]))
        containment = count / smaller if smaller else 0.0
        if containment >= SHINGLE_MIN_CONTAINMENT:
            pairs.append(
                {
                    "a": a,
                    "b": b,
                    "shared_shingles": count,
                    "containment": round(containment, 3),
                }
            )
    pairs.sort(key=lambda p: (-p["containment"], -p["shared_shingles"], p["a"], p["b"]))
    return pairs, ubiquitous


# ------------------------------------------------------------------- reporting


def build_issues(skills: list[dict], rules: list[dict], always_loaded: int, budget: int) -> list[dict]:
    issues: list[dict] = []

    if always_loaded > budget:
        issues.append(
            {
                "severity": "ERROR",
                "dim": "C5",
                "type": "always_loaded_over_budget",
                "unit": "CLAUDE.md+unscoped-rules",
                "msg": f"always-loaded surface {always_loaded} chars exceeds budget {budget}",
            }
        )

    for s in skills:
        if s["c1_markers"] >= CONSTRAINT_MIN_MARKERS and s["c1_density_per_1k"] >= CONSTRAINT_DENSITY_FLAG:
            issues.append(
                {
                    "severity": "WARN",
                    "dim": "C1",
                    "type": "constraint_dense",
                    "unit": s["path"],
                    "msg": f"{s['c1_markers']} markers ({s['c1_density_per_1k']}/1k), "
                    f"{s['c1_safety_adjacent']} safety-adjacent",
                }
            )
        if s["c2_has_args"] and not s["c2_has_argument_hint"]:
            issues.append(
                {
                    "severity": "WARN",
                    "dim": "C2",
                    "type": "args_without_hint",
                    "unit": s["path"],
                    "msg": "args: declared with no argument-hint: to describe the interface",
                }
            )
        if s["c2_has_args"] and not s["c2_arg_enumerated"] and not s["c2_has_params_section"]:
            issues.append(
                {
                    "severity": "WARN",
                    "dim": "C2",
                    "type": "opaque_arg_interface",
                    "unit": s["path"],
                    "msg": "args: neither enumerates its alternatives nor has a parameters section",
                }
            )
        if s["c2_example_ratio"] >= EXAMPLE_RATIO_FLAG and not s["c2_has_params_section"]:
            issues.append(
                {
                    "severity": "WARN",
                    "dim": "C2",
                    "type": "examples_without_interface",
                    "unit": s["path"],
                    "msg": f"{int(s['c2_example_ratio'] * 100)}% of body is examples, no parameters section",
                }
            )
        if s["body_chars"] > FLAT_BODY_CHARS and not s["c3_support_files"]:
            issues.append(
                {
                    "severity": "WARN",
                    "dim": "C3",
                    "type": "flat_large_body",
                    "unit": s["path"],
                    "msg": f"{s['body_chars']} chars in one file, no supporting files",
                }
            )
        if s["c6_multiline_shell_blocks"] >= 3 and not s["c3_has_scripts"]:
            issues.append(
                {
                    "severity": "WARN",
                    "dim": "C6",
                    "type": "prose_procedure_no_script",
                    "unit": s["path"],
                    "msg": f"{s['c6_multiline_shell_blocks']} multi-line shell blocks, no scripts/",
                }
            )

    for r in rules:
        if not r["path_scoped"] and r["intent_shaped"]:
            issues.append(
                {
                    "severity": "WARN",
                    "dim": "C5",
                    "type": "unscoped_intent_shaped_rule",
                    "unit": r["path"],
                    "msg": f"{r['chars']} chars always-loaded but reads procedural "
                    f"({r['procedural_headings']} procedural headings, {r['numbered_steps']} numbered steps)",
                }
            )

    issues.sort(key=lambda i: (i["severity"] != "ERROR", i["dim"], i["type"], i["unit"]))
    return issues


def top(skills: list[dict], key: str, n: int) -> list[dict]:
    return sorted(skills, key=lambda s: (-s[key], s["path"]))[:n]


def emit_text(data: dict, n_top: int, max_issues: int) -> None:
    t = data["totals"]
    out = sys.stdout.write
    out("=== CONTEXT ENGINEERING ===\n")
    out(f"SCHEMA_VERSION={SCHEMA_VERSION}\n")
    out(f"SKILL_COUNT={t['skill_count']}\n")
    out(f"SKILL_COUNT_MARKETPLACE={t['skill_count_marketplace']}\n")
    out(f"SKILL_BODY_CHARS={t['skill_body_chars']}\n")
    out(f"SKILL_BODY_EST_TOKENS={t['skill_body_est_tokens']}\n")
    out(f"SKILL_BODY_MEDIAN_CHARS={t['skill_body_median_chars']}\n")

    out(f"C1_MARKERS_TOTAL={t['c1_markers_total']}\n")
    out(f"C1_SAFETY_ADJACENT_TOTAL={t['c1_safety_adjacent_total']}\n")
    out(f"C1_DENSE_SKILLS={t['c1_dense_skills']}\n")

    out(f"C2_SKILLS_WITH_ARGS={t['c2_skills_with_args']}\n")
    out(f"C2_ARGS_ENUMERATED={t['c2_args_enumerated']}\n")
    out(f"C2_ARGS_WITHOUT_HINT={t['c2_args_without_hint']}\n")
    out(f"C2_OPAQUE_ARG_INTERFACES={t['c2_opaque_arg_interfaces']}\n")
    out(f"C2_EXAMPLE_CHARS_TOTAL={t['c2_example_chars_total']}\n")
    out(f"C2_FENCED_CHARS_TOTAL={t['c2_fenced_chars_total']}\n")
    out(f"C2_FENCED_PCT_OF_BODY={t['c2_fenced_pct_of_body']}\n")

    out(f"C3_LEVEL1_ONLY={t['c3_level1_only']}\n")
    out(f"C3_LEVEL2={t['c3_level2']}\n")
    out(f"C3_LEVEL3={t['c3_level3']}\n")
    out(f"C3_FLAT_LARGE_BODIES={t['c3_flat_large_bodies']}\n")

    for name in sorted(BOILERPLATE_SECTIONS):
        chars = t["c4_boilerplate"][name]["chars"]
        out(f"C4_BOILERPLATE_{name.upper()}_SKILLS={t['c4_boilerplate'][name]['skills']}\n")
        out(f"C4_BOILERPLATE_{name.upper()}_CHARS={chars}\n")
        out(f"C4_BOILERPLATE_{name.upper()}_PCT={t['c4_boilerplate'][name]['pct']}\n")
    out(f"C4_OVERLAP_PAIRS={t['c4_overlap_pairs']}\n")
    out(f"C4_UBIQUITOUS_SHINGLES={t['c4_ubiquitous_shingles']}\n")

    out(f"C5_CLAUDE_MD_CHARS={t['c5_claude_md_chars']}\n")
    out(f"C5_RULES_TOTAL={t['c5_rules_total']}\n")
    out(f"C5_UNSCOPED_RULES={t['c5_unscoped_rules']}\n")
    out(f"C5_UNSCOPED_RULE_CHARS={t['c5_unscoped_rule_chars']}\n")
    out(f"C5_ALWAYS_LOADED_CHARS={t['c5_always_loaded_chars']}\n")
    out(f"C5_ALWAYS_LOADED_EST_TOKENS={t['c5_always_loaded_est_tokens']}\n")
    out(f"C5_ALWAYS_LOADED_BUDGET={t['c5_always_loaded_budget']}\n")

    out(f"C6_SKILLS_WITH_SCRIPTS={t['c6_skills_with_scripts']}\n")
    out(f"C6_PROSE_PROCEDURE_NO_SCRIPT={t['c6_prose_procedure_no_script']}\n")

    out(f"STATUS={data['status']}\n")
    out(f"ISSUE_COUNT={len(data['issues'])}\n")
    for dim in sorted({i["dim"] for i in data["issues"]}):
        out(f"ISSUE_COUNT_{dim}={sum(1 for i in data['issues'] if i['dim'] == dim)}\n")
    if data["issues"]:
        shown = data["issues"][:max_issues]
        out(f"ISSUES_SHOWN={len(shown)}\n")
        out("ISSUES:\n")
        for i in shown:
            out(f"  - SEVERITY={i['severity']} DIM={i['dim']} TYPE={i['type']} UNIT={i['unit']} MSG={i['msg']}\n")
        if len(shown) < len(data["issues"]):
            out(f"  - TRUNCATED={len(data['issues']) - len(shown)} MSG=rerun with --max-issues 0 or --json for the full list\n")

    skills = data["skills"]
    if skills and n_top:
        out("TOP_OFFENDERS:\n")
        for label, key in (
            ("C1_DENSITY", "c1_density_per_1k"),
            ("C3_BODY_CHARS", "body_chars"),
        ):
            for s in top(skills, key, n_top):
                out(f"  - DIM={label} UNIT={s['path']} VALUE={s[key]}\n")
        for p in data["overlap_pairs"][:n_top]:
            out(
                f"  - DIM=C4_OVERLAP UNIT={p['a']} OTHER={p['b']} "
                f"CONTAINMENT={p['containment']} SHARED={p['shared_shingles']}\n"
            )
    out("=== END CONTEXT ENGINEERING ===\n")


# ------------------------------------------------------------------------ main


def find_project_root(start: str) -> str:
    """Walk up from `start` to the nearest repo root.

    Deliberately anchored to the CWD, not to this file's location: the scanner
    lives inside a plugin skill, so deriving the default from __file__ would
    scan the skill's own directory and report a silent SKILL_COUNT=0 — which
    reads as "nothing to fix" rather than as a failure.
    """
    current = os.path.abspath(start)
    while True:
        if os.path.isdir(os.path.join(current, ".git")) or os.path.isfile(
            os.path.join(current, ".claude-plugin", "marketplace.json")
        ):
            return current
        parent = os.path.dirname(current)
        if parent == current:
            return os.path.abspath(start)
        current = parent


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project-dir", default=find_project_root(os.getcwd()))
    ap.add_argument("--target", default=None)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--top", type=int, default=10)
    ap.add_argument("--max-issues", type=int, default=40, help="0 = no cap")
    ap.add_argument("--always-loaded-budget", type=int, default=100_000)
    args = ap.parse_args()

    root = os.path.abspath(args.project_dir)
    skill_paths, rule_paths, claude_md = discover(root, args.target)

    skills = [analyse_skill(root, p) for p in skill_paths]
    rules = [analyse_rule(root, p) for p in rule_paths]

    claude_md_chars = len(read_text(os.path.join(root, claude_md))) if claude_md else 0
    unscoped = [r for r in rules if not r["path_scoped"]]
    unscoped_chars = sum(r["chars"] for r in unscoped)
    always_loaded = claude_md_chars + unscoped_chars

    # C4 — overlap across skills + rules + CLAUDE.md in one index.
    corpus: dict[str, set[int]] = {}
    for p in skill_paths:
        _, body = split_frontmatter(read_text(os.path.join(root, p)))
        corpus[p] = shingles(body)
    for p in rule_paths:
        corpus[p] = shingles(read_text(os.path.join(root, p)))
    if claude_md:
        corpus[claude_md] = shingles(read_text(os.path.join(root, claude_md)))
    pairs, ubiquitous = overlap_pairs(corpus)

    body_chars = sorted(s["body_chars"] for s in skills)
    median = body_chars[len(body_chars) // 2] if body_chars else 0
    total_body = sum(body_chars)

    boiler = {}
    for name in sorted(BOILERPLATE_SECTIONS):
        chars = sum(s["c4_boilerplate_chars"][name] for s in skills)
        boiler[name] = {
            "skills": sum(1 for s in skills if s["c4_boilerplate_chars"][name] > 0),
            "chars": chars,
            "est_tokens": chars // 4,
            "pct": round(100 * chars / total_body, 1) if total_body else 0.0,
        }

    issues = build_issues(skills, rules, always_loaded, args.always_loaded_budget)
    status = "ERROR" if any(i["severity"] == "ERROR" for i in issues) else ("WARN" if issues else "OK")

    data = {
        "schema_version": SCHEMA_VERSION,
        "status": status,
        "totals": {
            "skill_count": len(skills),
            # Published marketplace skills, excluding repo-local `.claude/skills/*`.
            "skill_count_marketplace": sum(1 for s in skills if not s["path"].startswith(".")),
            "skill_body_chars": total_body,
            "skill_body_est_tokens": total_body // 4,
            "skill_body_median_chars": median,
            "c1_markers_total": sum(s["c1_markers"] for s in skills),
            "c1_safety_adjacent_total": sum(s["c1_safety_adjacent"] for s in skills),
            "c1_dense_skills": sum(
                1
                for s in skills
                if s["c1_markers"] >= CONSTRAINT_MIN_MARKERS
                and s["c1_density_per_1k"] >= CONSTRAINT_DENSITY_FLAG
            ),
            "c2_skills_with_args": sum(1 for s in skills if s["c2_has_args"]),
            "c2_args_enumerated": sum(1 for s in skills if s["c2_arg_enumerated"]),
            "c2_args_without_hint": sum(
                1 for s in skills if s["c2_has_args"] and not s["c2_has_argument_hint"]
            ),
            "c2_opaque_arg_interfaces": sum(
                1
                for s in skills
                if s["c2_has_args"] and not s["c2_arg_enumerated"] and not s["c2_has_params_section"]
            ),
            "c2_example_chars_total": sum(s["c2_example_chars"] for s in skills),
            "c2_fenced_chars_total": sum(s["c2_fenced_chars"] for s in skills),
            "c2_fenced_pct_of_body": (
                round(100 * sum(s["c2_fenced_chars"] for s in skills) / total_body, 1)
                if total_body
                else 0.0
            ),
            "c3_level1_only": sum(1 for s in skills if s["c3_levels"] == 1),
            "c3_level2": sum(1 for s in skills if s["c3_levels"] == 2),
            "c3_level3": sum(1 for s in skills if s["c3_levels"] == 3),
            "c3_flat_large_bodies": sum(
                1 for s in skills if s["body_chars"] > FLAT_BODY_CHARS and not s["c3_support_files"]
            ),
            "c4_boilerplate": boiler,
            "c4_overlap_pairs": len(pairs),
            "c4_ubiquitous_shingles": ubiquitous,
            "c5_claude_md_chars": claude_md_chars,
            "c5_rules_total": len(rules),
            "c5_unscoped_rules": len(unscoped),
            "c5_unscoped_rule_chars": unscoped_chars,
            "c5_always_loaded_chars": always_loaded,
            "c5_always_loaded_est_tokens": always_loaded // 4,
            "c5_always_loaded_budget": args.always_loaded_budget,
            "c6_skills_with_scripts": sum(1 for s in skills if s["c3_has_scripts"]),
            "c6_prose_procedure_no_script": sum(
                1 for s in skills if s["c6_multiline_shell_blocks"] >= 3 and not s["c3_has_scripts"]
            ),
        },
        "skills": skills,
        "rules": rules,
        "overlap_pairs": pairs,
        "issues": issues,
    }

    if args.json:
        json.dump(data, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    else:
        emit_text(data, args.top, args.max_issues if args.max_issues > 0 else len(issues))

    if args.strict and status == "ERROR":
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

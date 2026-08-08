#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["fastembed>=0.4", "numpy>=1.26"]
# ///
"""config-drift — continuous hygiene check for Claude rules and skills.

Design notes (why it is shaped this way):

* Two cost tiers. Integrity + lexical + staleness checks are pure stdlib and run
  in well under a second, so they can fire on every SessionStart. The semantic
  (embedding) pass needs a model and is scheduled-only. `--no-embed` selects the
  cheap tier; nothing in the cheap tier imports fastembed or numpy.

* Cache keyed by content SHA-256, never mtime. mtime moves on checkout, touch,
  and chezmoi apply without the content changing; a hash cannot lie. Timestamps
  are used for a different job entirely -- `reviewed:` staleness policy.

* Waivers expire themselves. A waiver records both sides' content hashes, so
  editing either side revives the finding. This is what keeps a recurring report
  from decaying into noise you learn to skip.

Exit codes: 0 clean, 1 warnings, 2 errors (CI gate), 3 internal failure.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
from itertools import combinations
from pathlib import Path

HOME_RULES = Path.home() / ".claude" / "rules"
SKIP_PARTS = {"node_modules", "dist", "worktrees", ".git", "__pycache__", "tmp"}
EMBED_MODEL = "BAAI/bge-small-en-v1.5"
EMBED_CHARS = 2000

# Thresholds. Deliberately conservative: this tool surfaces, a human decides.
# Calibrated against the live corpus, not guessed. At 0.86 the semantic pass
# emitted 491 findings, of which 290 were same-name pairs the cheap tier already
# owns and most of the rest were genre noise -- every document here is "Claude
# config markdown about tooling", so baseline cosine is high. Novel-pair score
# distribution was 0.94:2 0.92:9 0.90:32 0.88:70 0.86:88, i.e. the actionable
# signal sits above ~0.91 and the tail below it is unusable.
T_SEMANTIC = 0.91  # cosine over title+head
T_LEXICAL = 0.45  # 3-gram Jaccard over full body
T_COVERAGE = 0.55  # rule topic already covered by a skill
BUDGET_TOKENS = 55_000  # always-loaded ceiling before it is a finding
STALE_DAYS = 120  # reviewed: older than this many days behind a change

STOP = set(
    """a an the and or but if then else for of to in on at by with from as is are was were be been
    it its this that these those not no do does did can could should would may might must will you
    your we our they their its me my when what which who how why use used using than there here
    into over under out up down off about via per each any all some more most other same such only
    just also very well make made get got take see run one two file files code claude rule rules
    skill skills use-when when-to""".split()
)


# --------------------------------------------------------------------- helpers
def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()[:16]


def toks(text: str) -> list[str]:
    return [
        w for w in re.findall(r"[a-z][a-z0-9_-]{2,}", text.lower()) if w not in STOP
    ]


def shingles(text: str, n: int = 3) -> set[str]:
    t = toks(text)
    return {" ".join(t[i : i + n]) for i in range(max(0, len(t) - n + 1))}


def jaccard(a: set, b: set) -> float:
    return len(a & b) / len(a | b) if a and b else 0.0


def frontmatter(body: str) -> dict[str, str]:
    if not body.startswith("---"):
        return {}
    parts = body.split("---", 2)
    if len(parts) < 3:
        return {}
    return {
        k: v.strip().strip("\"'")
        for k, v in re.findall(r"^([a-z_]+):[ \t]*(.*)$", parts[1], re.M)
    }


def git_last_change(path: Path) -> str | None:
    try:
        out = subprocess.run(
            [
                "git",
                "-C",
                str(path.parent),
                "log",
                "-1",
                "--format=%cs",
                "--",
                path.name,
            ],
            capture_output=True,
            text=True,
            timeout=10,
        ).stdout.strip()
        return out or None
    except (OSError, subprocess.SubprocessError):
        return None


def changed_since(root: Path, ref: str) -> set[str]:
    """Paths touched since a git ref, for delta-only reporting."""
    changed: set[str] = set()
    for repo in {p.parent.parent for p in root.rglob(".git") if p.name == ".git"} | {
        root
    }:
        try:
            out = subprocess.run(
                ["git", "-C", str(repo), "diff", "--name-only", ref, "--"],
                capture_output=True,
                text=True,
                timeout=20,
            )
            if out.returncode == 0:
                changed |= {
                    str((repo / line).resolve()) for line in out.stdout.split() if line
                }
        except (OSError, subprocess.SubprocessError):
            continue
    return changed


def walk(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            d for d in dirnames if d not in SKIP_PARTS and not d.startswith(".venv")
        ]
        yield Path(dirpath), filenames


# ------------------------------------------------------------------- inventory
def collect(root: Path) -> tuple[list[dict], list[dict]]:
    rules, skills = [], []

    rule_paths = sorted(HOME_RULES.glob("*.md")) if HOME_RULES.is_dir() else []
    for dirpath, filenames in walk(root):
        if dirpath.match("*/.claude/rules"):
            rule_paths += [dirpath / f for f in filenames if f.endswith(".md")]
        if (
            "SKILL.md" in filenames
            and f"{os.sep}skills{os.sep}" in f"{dirpath}{os.sep}"
        ):
            p = dirpath / "SKILL.md"
            body = p.read_text(encoding="utf-8", errors="replace")
            fm = frontmatter(body)
            skills.append(
                {
                    "kind": "skill",
                    "path": str(p),
                    "name": p.parent.name,
                    "title": p.parent.name,
                    "body": body,
                    "fm": fm,
                    "desc": fm.get("description", ""),
                    "chars": len(body),
                    "hash": sha(body),
                }
            )

    for p in sorted(set(rule_paths)):
        body = p.read_text(encoding="utf-8", errors="replace")
        fm = frontmatter(body)
        scope = (
            "user-global"
            if str(p).startswith(str(HOME_RULES))
            else "portfolio"
            if p.parent.parent.parent == root
            else str(p).split("/.claude/rules/")[0].replace(str(root) + "/", "")
        )
        title = next(
            (line[2:].strip() for line in body.splitlines() if line.startswith("# ")),
            p.stem,
        )
        rules.append(
            {
                "kind": "rule",
                "path": str(p),
                "name": p.stem,
                "title": title,
                "body": body,
                "fm": fm,
                "scope": scope,
                "always_loaded": scope in ("user-global", "portfolio"),
                "chars": len(body),
                "hash": sha(body),
                "stub": "romoted to a skill" in body[:700],
            }
        )
    return rules, skills


# -------------------------------------------------------------------- waivers
def _canon(p: str) -> str:
    """Canonicalise a path for waiver matching.

    Waiver files are hand-written, so a side may be spelled `~/repos/...` or
    `/var/...` while the scan resolves it to `/private/var/...` (macOS symlinks
    every temp and `/var` path). Comparing raw strings silently fails to match
    and the waiver looks ignored, which is indistinguishable from a bug.
    """
    return os.path.realpath(os.path.expanduser(p))


def load_waivers(path: Path) -> dict[tuple[str, str], dict]:
    if not path.is_file():
        return {}
    try:
        raw = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return {(_canon(w["a"]), _canon(w["b"])): w for w in raw.get("waivers", [])}


def waived(waivers, a: dict, b: dict) -> bool:
    """A waiver holds only while BOTH sides are byte-identical to when it was filed."""
    pa, pb = _canon(a["path"]), _canon(b["path"])
    for key in ((pa, pb), (pb, pa)):
        w = waivers.get(key)
        if not w:
            continue
        ha, hb = (
            (w.get("a_hash"), w.get("b_hash"))
            if key[0] == pa
            else (w.get("b_hash"), w.get("a_hash"))
        )
        if ha == a["hash"] and hb == b["hash"]:
            return True
    return False


# --------------------------------------------------------------------- checks
def _stub_target(head: str, known: set[str]) -> str | None:
    """Resolve which skill a pointer stub delegates to.

    "First backticked token" was wrong: a stub's own title routinely contains an
    incidental backticked term, and that word won it. A real stub reading
    "# Git-Based `uvx` MCP Servers ... invoke `agent-patterns-plugin:mcp-management`"
    resolved to the skill `uvx`, which does not exist — a false ERROR on a
    perfectly good stub, which is the failure mode most likely to get an
    integrity check switched off.

    Three passes, most specific first:
      1. the token following `invoke` — the house phrasing every stub uses
      2. any backticked token that names a real skill
      3. the first backticked token, so a genuinely broken stub still reports
         a name rather than "(none named)"
    """
    m = re.search(r"invoke\s+`([a-z0-9:_-]+)`", head)
    if m:
        return m.group(1).split(":")[-1]

    refs = [t.split(":")[-1] for t in re.findall(r"`([a-z0-9:_-]+)`", head)]
    for ref in refs:
        if ref in known:
            return ref
    return refs[0] if refs else None


def check_stub_integrity(rules, skills) -> list[dict]:
    known = {s["name"] for s in skills}
    out = []
    for r in rules:
        if not r["stub"]:
            continue
        target = _stub_target(r["body"][:700], known)
        if target not in known:
            out.append(
                {
                    "severity": "error",
                    "kind": "broken_pointer_stub",
                    "summary": f"{r['name']} points at skill '{target or '(none named)'}' which does not exist",
                    "path": r["path"],
                }
            )
    return out


def check_review_staleness(items, cache: dict, allow_spawn: bool) -> list[dict]:
    """Compare each item's declared `reviewed:` against its real last-change date.

    One `git log` per file is ~10ms and there are ~900 files, which is far too
    slow for a SessionStart probe. The date is cached under `path:content-hash`:
    a file whose content is unchanged cannot have a new last-change date, so the
    cache is correct by construction rather than by TTL. In fast mode (the probe)
    a cache miss is skipped rather than spawning git, so the probe stays sub-second
    and the scheduled run is what warms the cache.
    """
    out = []
    for it in items:
        rv = it["fm"].get("reviewed")
        if not rv or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", rv):
            continue
        key = f"{it['path']}:{it['hash']}"
        if key in cache:
            changed = cache[key]
        elif allow_spawn:
            changed = git_last_change(Path(it["path"]))
            cache[key] = changed
        else:
            continue
        if not changed:
            continue
        try:
            gap = (dt.date.fromisoformat(changed) - dt.date.fromisoformat(rv)).days
        except ValueError:
            continue
        if gap > STALE_DAYS:
            out.append(
                {
                    "severity": "warn",
                    "kind": "review_staleness",
                    "summary": f"{it['name']} changed {gap}d after its declared reviewed:{rv}",
                    "path": it["path"],
                    "gap_days": gap,
                }
            )
    return sorted(out, key=lambda x: -x["gap_days"])


def check_budget(rules) -> list[dict]:
    # A rule in a user-global/portfolio scope is NOT unconditionally injected if
    # it carries `paths:` frontmatter -- it loads only when a matching file is
    # read. Counting those inflates the budget by ~24% on this portfolio (13 of
    # 67 rules, ~12,200 tok). Confirmed empirically: path-scoped rules are absent
    # from the initial context injection and arrive later as reminders.
    always = [r for r in rules if r["always_loaded"] and "paths" not in r["fm"]]
    tokens = sum(r["chars"] for r in always) // 4
    if tokens <= BUDGET_TOKENS:
        return []
    worst = sorted(always, key=lambda r: -r["chars"])[:3]
    return [
        {
            "severity": "warn",
            "kind": "always_loaded_budget",
            "summary": (
                f"{len(always)} always-loaded rules cost ~{tokens:,} tok/turn "
                f"(budget {BUDGET_TOKENS:,}); heaviest: "
                + ", ".join(
                    f"{r['name']}(~{r['chars'] // 4 // 100 * 100:,})" for r in worst
                )
            ),
            "tokens": tokens,
        }
    ]


def check_frontmatter(rules) -> list[dict]:
    missing = [r for r in rules if not r["fm"].get("reviewed")]
    if not missing:
        return []
    return [
        {
            "severity": "info",
            "kind": "frontmatter_coverage",
            "summary": f"{len(missing)}/{len(rules)} rules carry no reviewed: date, so staleness cannot be tracked for them",
        }
    ]


def check_lexical_dupes(rules, waivers) -> list[dict]:
    for r in rules:
        r["_sh"] = shingles(r["body"])
    out = []
    for a, b in combinations(rules, 2):
        s = jaccard(a["_sh"], b["_sh"])
        if s >= T_LEXICAL and not waived(waivers, a, b):
            out.append(
                {
                    "severity": "warn",
                    "kind": "duplicate_rule_lexical",
                    "summary": f"{a['scope']}:{a['name']} and {b['scope']}:{b['name']} are {s:.0%} lexically identical",
                    "score": round(s, 3),
                    "paths": [a["path"], b["path"]],
                }
            )
    return sorted(out, key=lambda x: -x["score"])


def check_rule_covered_by_skill(rules, skills, waivers) -> list[dict]:
    """Topic containment: how much of a rule's vocabulary a skill already carries.

    Full-body Jaccard is the wrong metric here and silently returns zero -- a
    SKILL.md is 5-20x a rule's length, so the union swamps the intersection.
    Containment is asymmetric and correct. Control-tested: every already-promoted
    pointer stub must score above threshold against its own skill.
    """

    def tset(text):
        return {w for w in toks(text) if len(w) > 3}

    for s in skills:
        s["_t"] = tset(
            s["name"].replace("-", " ") + " " + s["desc"] + " " + s["body"][:6000]
        )
    out, control_hits, control_total = [], 0, 0
    for r in rules:
        topic = tset(
            r["name"].replace("-", " ") + " " + r["title"] + " " + r["body"][:1200]
        )
        if len(topic) < 6:
            continue
        best = max(
            ((len(topic & s["_t"]) / len(topic), s) for s in skills),
            key=lambda x: x[0],
            default=(0.0, None),
        )
        score, skill = best
        if r["stub"]:
            control_total += 1
            control_hits += score >= T_COVERAGE
            continue
        if score >= T_COVERAGE and skill and not waived(waivers, r, skill):
            out.append(
                {
                    "severity": "info",
                    "kind": "rule_covered_by_skill",
                    "summary": (
                        f"{r['scope']}:{r['name']} is {score:.0%} covered by skill "
                        f"{skill['name']} -- candidate for a pointer stub"
                    ),
                    "score": round(score, 3),
                    "paths": [r["path"], skill["path"]],
                    "always_loaded": r["always_loaded"],
                }
            )
    # Control gate: if the known-good stubs do not surface, the metric is broken
    # and its output must not be trusted (never-fabricate-test-identifiers).
    if control_total and control_hits < max(1, int(0.7 * control_total)):
        out = [
            {
                "severity": "error",
                "kind": "coverage_metric_broken",
                "summary": (
                    f"containment metric failed its control: only {control_hits}/{control_total} "
                    "known pointer stubs detected -- coverage findings suppressed"
                ),
            }
        ]
    return sorted(out, key=lambda x: (not x.get("always_loaded"), -x.get("score", 0)))


def check_semantic_dupes(items, waivers, cache_path: Path) -> list[dict]:
    import numpy as np
    from fastembed import TextEmbedding

    cache = {}
    if cache_path.is_file():
        try:
            cache = json.loads(cache_path.read_text())
        except (OSError, json.JSONDecodeError):
            cache = {}

    need = [it for it in items if it["hash"] not in cache]
    if need:
        model = TextEmbedding(model_name=EMBED_MODEL)
        texts = [
            f"{it['title']}\n{it.get('desc', '')}\n{it['body'][:EMBED_CHARS]}"
            for it in need
        ]
        for it, vec in zip(need, model.embed(texts)):
            cache[it["hash"]] = [round(float(x), 6) for x in vec]
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(json.dumps(cache))

    def structural_pair(a: dict, b: dict) -> bool:
        """Relationships that are correct by design, not drift.

        Two shapes dominate the high-cosine band and neither is a defect:
        a pointer stub scores ~0.92 against the very skill it delegates to, and
        deliberately cross-referenced sibling rules ("Sibling: pr-merge-hazards.md")
        score ~0.93. Flagging either trains the reader to ignore the report.
        """
        for x, y in ((a, b), (b, a)):
            if x.get("stub") and y["kind"] == "skill" and y["name"] in x["body"][:700]:
                return True
            if (
                Path(y["path"]).name in x["body"]
                or f"`{y['name']}`" in x["body"][:1500]
            ):
                return True
        return False

    vecs = np.array([cache[it["hash"]] for it in items], dtype="float32")
    vecs /= np.linalg.norm(vecs, axis=1, keepdims=True) + 1e-9
    sim = vecs @ vecs.T
    out = []
    for i, j in zip(*np.triu_indices(len(items), k=1)):
        s = float(sim[i, j])
        a, b = items[i], items[j]
        # Same-name pairs belong to the cheap tier (name-collision + lexical);
        # re-reporting them here would double-count every generated rule.
        if a["name"] == b["name"] or structural_pair(a, b):
            continue
        if s >= T_SEMANTIC and not waived(waivers, a, b):
            out.append(
                {
                    "severity": "warn",
                    "kind": f"semantic_overlap_{a['kind']}_{b['kind']}",
                    "summary": (
                        f"{a['kind']} {a['name']} and {b['kind']} {b['name']} "
                        f"are {s:.0%} semantically similar"
                    ),
                    "score": round(s, 3),
                    "paths": [a["path"], b["path"]],
                }
            )
    return sorted(out, key=lambda x: -x["score"])


# ---------------------------------------------------------------------- output
def emit_status(findings, counts):
    print("=== CONFIG DRIFT ===")
    for k, v in counts.items():
        print(f"{k.upper()}={v}")
    by_kind: dict[str, int] = {}
    for f in findings:
        by_kind[f["kind"]] = by_kind.get(f["kind"], 0) + 1
    for k, v in sorted(by_kind.items()):
        print(f"FINDING_{k.upper()}={v}")
    errs = sum(1 for f in findings if f["severity"] == "error")
    warns = sum(1 for f in findings if f["severity"] == "warn")
    print(f"ERRORS={errs}\nWARNINGS={warns}")
    # OK / WARN / ERROR per .claude/rules/structured-script-output.md, not
    # PASS/FAIL -- orchestrating skills grep for the house vocabulary.
    print("STATUS=" + ("ERROR" if errs else "WARN" if warns else "OK"))


def emit_probe(findings):
    """drift-protocol shape: severity/kind/summary/remediation_skill."""
    remediation = {
        "broken_pointer_stub": "/agent-patterns:meta-promote",
        "duplicate_rule_lexical": "/agent-patterns:meta-promote",
        "semantic_overlap_rule_rule": "/agent-patterns:meta-promote",
        "semantic_overlap_skill_skill": "/health:skill-audit",
        "rule_covered_by_skill": "/agent-patterns:meta-context-diet",
        "always_loaded_budget": "/agent-patterns:meta-context-diet",
        "review_staleness": "/health:skill-audit",
        "frontmatter_coverage": "/agent-patterns:meta-context-diet",
    }
    ranked = sorted(
        findings, key=lambda f: {"error": 0, "warn": 1, "info": 2}[f["severity"]]
    )
    print(
        json.dumps(
            {
                "plugin": "config-drift",
                "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(
                    timespec="seconds"
                ),
                "findings": [
                    {
                        "severity": f["severity"],
                        "kind": f["kind"],
                        "summary": f["summary"],
                        "remediation_skill": remediation.get(
                            f["kind"], "/health:check"
                        ),
                    }
                    for f in ranked[:5]
                ],
            },
            indent=1,
        )
    )


def emit_report(findings, counts):
    print("# Claude config drift report\n")
    print(f"_{dt.datetime.now().isoformat(timespec='seconds')}_\n")
    print("| Metric | Value |\n|---|---|")
    for k, v in counts.items():
        print(f"| {k.replace('_', ' ')} | {v} |")
    print()
    for sev in ("error", "warn", "info"):
        group = [f for f in findings if f["severity"] == sev]
        if not group:
            continue
        print(f"\n## {sev.upper()} ({len(group)})\n")
        for f in group[:40]:
            print(f"- **{f['kind']}** — {f['summary']}")
            for p in f.get("paths", [])[:2]:
                print(f"  - `{p}`")
        if len(group) > 40:
            print(f"\n_…{len(group) - 40} more suppressed._")


# ------------------------------------------------------------------------ main
def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    # Defaults to the current directory, not a hardcoded portfolio path -- this
    # ships as a plugin and cannot assume anyone's layout. The SessionStart probe
    # passes the drift protocol's own cwd. User-global rules under
    # ~/.claude/rules are always scanned regardless of --root, because they load
    # in every session no matter which project is open.
    ap.add_argument("--root", default=".")
    ap.add_argument(
        "--format", choices=["status", "probe", "report", "json"], default="status"
    )
    ap.add_argument(
        "--no-embed",
        action="store_true",
        help="cheap tier only: integrity, lexical, staleness. No model, no download.",
    )
    ap.add_argument(
        "--since",
        metavar="REF",
        help="only report findings touching files changed since this git ref",
    )
    ap.add_argument(
        "--waivers", default=str(Path.home() / ".claude" / "config-drift-waivers.json")
    )
    ap.add_argument(
        "--cache",
        default=str(Path.home() / ".cache" / "config-drift" / "embeddings.json"),
    )
    ap.add_argument(
        "--gate",
        action="store_true",
        help="exit 2 on any error-severity finding (CI use)",
    )
    ap.add_argument(
        "--fast",
        action="store_true",
        help="probe mode: never spawn git; read cached dates only. Sub-second.",
    )
    args = ap.parse_args()

    root = Path(args.root).expanduser().resolve()
    if not root.is_dir():
        print(f"root not found: {root}", file=sys.stderr)
        return 3

    rules, skills = collect(root)
    waivers = load_waivers(Path(args.waivers).expanduser())

    findings: list[dict] = []
    findings += check_stub_integrity(rules, skills)
    findings += check_budget(rules)
    findings += check_lexical_dupes(rules, waivers)
    findings += check_rule_covered_by_skill(rules, skills, waivers)
    findings += check_frontmatter(rules)

    datecache_path = Path(args.cache).expanduser().with_name("gitdates.json")
    datecache: dict = {}
    if datecache_path.is_file():
        try:
            datecache = json.loads(datecache_path.read_text())
        except (OSError, json.JSONDecodeError):
            datecache = {}
    before = len(datecache)
    findings += check_review_staleness(
        rules + skills, datecache, allow_spawn=not args.fast
    )
    if len(datecache) != before:
        datecache_path.parent.mkdir(parents=True, exist_ok=True)
        datecache_path.write_text(json.dumps(datecache))

    if not args.no_embed:
        try:
            findings += check_semantic_dupes(
                rules + skills, waivers, Path(args.cache).expanduser()
            )
        except Exception as exc:  # noqa: BLE001 - degrade loudly, never silently
            findings.append(
                {
                    "severity": "info",
                    "kind": "semantic_pass_unavailable",
                    "summary": f"semantic pass skipped: {type(exc).__name__}: {exc}",
                }
            )

    if args.since:
        touched = changed_since(root, args.since)
        findings = [
            f
            for f in findings
            if not f.get("paths") or any(p in touched for p in f["paths"])
        ]

    always = [r for r in rules if r["always_loaded"] and "paths" not in r["fm"]]
    counts = {
        "rules": len(rules),
        "skills": len(skills),
        "scopes": len({r["scope"] for r in rules}),
        "always_loaded_rules": len(always),
        "always_loaded_tokens": sum(r["chars"] for r in always) // 4,
        "pointer_stubs": sum(1 for r in rules if r["stub"]),
        "waivers_active": len(waivers),
        "semantic_pass": "off" if args.no_embed else "on",
    }

    {
        "status": emit_status,
        "probe": lambda f, c: emit_probe(f),
        "report": emit_report,
        "json": lambda f, c: print(json.dumps({"counts": c, "findings": f}, indent=1)),
    }[args.format](findings, counts)

    errs = sum(1 for f in findings if f["severity"] == "error")
    if args.gate and errs:
        return 2
    return 1 if any(f["severity"] in ("error", "warn") for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main())

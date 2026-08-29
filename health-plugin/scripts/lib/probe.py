"""probe — the finding / waiver / delta / render contract shared by config-drift probes.

Extracted verbatim from `config-drift.py` (issue #2527, PR1 of two) so a second
probe does not have to re-derive nine dict literals, a two-orientation waiver
lookup, three renderers and an exit-code ladder. `fingerprint()` and `delta()`
are the one addition: #2319 specifies a `kind` + sorted-paths delta fingerprint
and there was previously nothing to implement it in.

Three constraints on this file, each load-bearing:

* **Stdlib only, and NO PEP-723 dependency block.** Both real callers reach the
  analyzer through a bare `python3` (`../hooks/config-drift-probe.sh` and
  `../tests/test-config-drift.sh`), bypassing the `uv run --script` shebang
  entirely — so a dependency block here would resolve only on the path nobody
  takes, and would be silently absent on the paths everybody takes.

* **Import it as `from lib.probe import ...`, never `import probe`.**
  `sys.path[0]` is the *script's* directory (`health-plugin/scripts`), not
  `lib/`, so the flat form raises `ModuleNotFoundError`. What resolves this
  module is a PEP 420 implicit namespace package, which is why there is
  deliberately **no `__init__.py`** beside this file — adding one changes
  nothing here and invites the flat form back. Verified under both bare
  `python3` and `uv run --script`, from an unrelated cwd.

* **Getting that import wrong fails silently.** `config-drift-probe.sh` treats
  empty analyzer output as "no findings", so an `ImportError` traceback on
  stderr is indistinguishable from a clean corpus. `tests/test-config-drift.sh`
  executes the import path from an unrelated cwd for exactly this reason.

Exit codes: 0 clean, 1 warnings, 2 errors (CI gate), 3 internal failure.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path

# ----------------------------------------------------------------- exit codes
EXIT_CLEAN = 0
EXIT_WARN = 1
EXIT_ERROR = 2
EXIT_INTERNAL = 3

# Ordered worst-first; `SEVERITY_RANK` is the sort key the probe renderer uses.
SEVERITIES = ("error", "warn", "info")
SEVERITY_RANK = {"error": 0, "warn": 1, "info": 2}

# The renderers this module offers, in the order `--format` advertises them.
FORMATS = ("status", "probe", "report", "json")

# Cap on how many findings the drift-protocol shape forwards. The aggregator
# caps at 5 lines across ALL plugins, so a greedy probe crowds out its siblings.
PROBE_FINDING_LIMIT = 5

# Cap on how many findings a severity group renders in the markdown report.
REPORT_GROUP_LIMIT = 40

# Which skill fixes each kind. Consumed by `emit_probe`.
REMEDIATION = {
    "broken_pointer_stub": "/agent-patterns:meta-promote",
    "duplicate_rule_lexical": "/agent-patterns:meta-promote",
    "semantic_overlap_rule_rule": "/agent-patterns:meta-promote",
    "semantic_overlap_skill_skill": "/health:skill-audit",
    "rule_covered_by_skill": "/agent-patterns:meta-context-diet",
    "always_loaded_budget": "/agent-patterns:meta-context-diet",
    "review_staleness": "/health:skill-audit",
    "frontmatter_coverage": "/agent-patterns:meta-context-diet",
}
DEFAULT_REMEDIATION = "/health:check"


# ------------------------------------------------------------------- findings
def finding(severity: str, kind: str, summary: str, **extra) -> dict:
    """Build one finding, validating the shape every consumer relies on.

    Key order is part of the contract: `severity`, `kind`, `summary`, then the
    caller's extras in the order they were passed. `json.dumps` preserves
    insertion order, so the analyzer's `--format=json` output is byte-identical
    to the dict literals this replaced.

    `path` (a str) and `paths` (a list) are BOTH accepted and neither is
    rewritten. That split is a real defect — `--since` filters on `paths` only,
    so a `path`-carrying finding silently survives a delta filter it should not
    — but normalising it changes analyzer output, so it is deliberately left
    for #2527's PR2. `finding_paths()` below reads both spellings so the
    fingerprint is correct in the meantime.
    """
    if severity not in SEVERITIES:
        raise ValueError(
            f"finding severity must be one of {SEVERITIES!r}, got {severity!r}"
        )
    if not isinstance(kind, str) or not kind:
        raise ValueError(f"finding kind must be a non-empty str, got {kind!r}")
    if not isinstance(summary, str) or not summary:
        raise ValueError(f"finding summary must be a non-empty str, got {summary!r}")
    if "paths" in extra and not isinstance(extra["paths"], list):
        raise ValueError(f"finding paths must be a list, got {extra['paths']!r}")
    if "path" in extra and not isinstance(extra["path"], str):
        raise ValueError(f"finding path must be a str, got {extra['path']!r}")
    return {"severity": severity, "kind": kind, "summary": summary, **extra}


def count_severity(findings, severity: str) -> int:
    return sum(1 for f in findings if f["severity"] == severity)


def exit_code(findings, gate: bool = False) -> int:
    """0 clean, 1 any warn-or-error finding, 2 under `--gate` with an error."""
    if gate and count_severity(findings, "error"):
        return EXIT_ERROR
    return (
        EXIT_WARN
        if any(f["severity"] in ("error", "warn") for f in findings)
        else EXIT_CLEAN
    )


# -------------------------------------------------------------------- waivers
def canonical_path(p: str) -> str:
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
    return {
        (canonical_path(w["a"]), canonical_path(w["b"])): w
        for w in raw.get("waivers", [])
    }


def waived(waivers, a: dict, b: dict) -> bool:
    """A waiver holds only while BOTH sides are byte-identical to when it was filed."""
    pa, pb = canonical_path(a["path"]), canonical_path(b["path"])
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


# ---------------------------------------------------------- delta fingerprints
def finding_paths(finding_dict: dict) -> list[str]:
    """Every filesystem path a finding carries, canonicalised and sorted.

    Reads BOTH spellings (`paths` list, `path` str) because the analyzer emits
    both — see the note in `finding()`. Sorting is what makes the fingerprint
    orientation-independent: a lexical duplicate reported as (A, B) in one run
    and (B, A) in the next is the same finding.
    """
    raw = finding_dict.get("paths")
    if raw is None:
        one = finding_dict.get("path")
        raw = [one] if one else []
    return sorted(canonical_path(p) for p in raw)


def fingerprint(finding_dict: dict) -> str:
    """A stable identity for one finding: its `kind` plus its sorted paths (#2319).

    Deliberately excludes `severity`, `score`, `summary` and every other extra,
    so a rescored or reworded finding is the SAME finding and a delta report
    does not fill up with churn. Two findings of the same kind over the same
    file set are one fingerprint by design — that is what makes "did anything
    NEW appear?" answerable.
    """
    payload = "\x1f".join([finding_dict["kind"], *finding_paths(finding_dict)])
    return hashlib.sha256(payload.encode("utf-8", "replace")).hexdigest()[:16]


def fingerprints(findings) -> set[str]:
    return {fingerprint(f) for f in findings}


def delta(findings, previous) -> dict[str, list[str]]:
    """Compare this run's findings against a previous run's fingerprint set.

    `previous` is an iterable of fingerprint STRINGS (persist it with
    `fingerprints()`), not findings — a previous run's full findings are not
    needed and storing them invites comparing on fields the fingerprint
    deliberately ignores.
    """
    current = fingerprints(findings)
    prior = set(previous)
    return {
        "new": sorted(current - prior),
        "resolved": sorted(prior - current),
        "unchanged": sorted(current & prior),
    }


# --------------------------------------------------------------------- output
def emit_status(findings, counts) -> None:
    print("=== CONFIG DRIFT ===")
    for k, v in counts.items():
        print(f"{k.upper()}={v}")
    by_kind: dict[str, int] = {}
    for f in findings:
        by_kind[f["kind"]] = by_kind.get(f["kind"], 0) + 1
    for k, v in sorted(by_kind.items()):
        print(f"FINDING_{k.upper()}={v}")
    errs = count_severity(findings, "error")
    warns = count_severity(findings, "warn")
    print(f"ERRORS={errs}\nWARNINGS={warns}")
    # OK / WARN / ERROR per .claude/rules/structured-script-output.md, not
    # PASS/FAIL -- orchestrating skills grep for the house vocabulary.
    print("STATUS=" + ("ERROR" if errs else "WARN" if warns else "OK"))


def emit_probe(findings) -> None:
    """drift-protocol shape: severity/kind/summary/remediation_skill."""
    ranked = sorted(findings, key=lambda f: SEVERITY_RANK[f["severity"]])
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
                        "remediation_skill": REMEDIATION.get(
                            f["kind"], DEFAULT_REMEDIATION
                        ),
                    }
                    for f in ranked[:PROBE_FINDING_LIMIT]
                ],
            },
            indent=1,
        )
    )


def emit_report(findings, counts) -> None:
    print("# Claude config drift report\n")
    print(f"_{dt.datetime.now().isoformat(timespec='seconds')}_\n")
    print("| Metric | Value |\n|---|---|")
    for k, v in counts.items():
        print(f"| {k.replace('_', ' ')} | {v} |")
    print()
    for sev in SEVERITIES:
        group = [f for f in findings if f["severity"] == sev]
        if not group:
            continue
        print(f"\n## {sev.upper()} ({len(group)})\n")
        for f in group[:REPORT_GROUP_LIMIT]:
            print(f"- **{f['kind']}** — {f['summary']}")
            for p in f.get("paths", [])[:2]:
                print(f"  - `{p}`")
        if len(group) > REPORT_GROUP_LIMIT:
            print(f"\n_…{len(group) - REPORT_GROUP_LIMIT} more suppressed._")


def emit_json(findings, counts) -> None:
    print(json.dumps({"counts": counts, "findings": findings}, indent=1))


def render(fmt: str, findings, counts) -> None:
    """Dispatch to one renderer by `--format` name."""
    {
        "status": emit_status,
        "probe": lambda f, c: emit_probe(f),
        "report": emit_report,
        "json": lambda f, c: emit_json(f, c),
    }[fmt](findings, counts)

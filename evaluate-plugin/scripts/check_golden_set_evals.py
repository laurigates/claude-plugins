#!/usr/bin/env python3
"""Validate every golden-set canary's evals.json and prove its typed checks bite.

The golden set (evaluate-plugin/golden-set.json) is the Tier-2 canary set, and
its `evalCoverageFloor` ratchet only counts that an evals.json EXISTS
(scripts/check-golden-set-coverage.sh). Existence says nothing about whether the
suite can grade anything: a regex that never compiles, a flag the grader
rejects, or an absent_regex that no fabricated answer trips all produce a suite
that "covers" a canary while measuring nothing. That is the same class as the
floor itself guards against — a periodic sweep reporting green over an
unexercised set (#2144).

Two layers, per eval-ready canary:

  1. Shape: the file parses; skill_name matches the SKILL.md `name:`;
     skill_path points at that SKILL.md; ids are unique; every case has a
     prompt and expectations; expected_outcome (when present) is comply or
     abstain; every typed check has a known type, its required field, a valid
     scope, flags drawn from `imsx`, and a pattern that compiles.
  2. Teeth: recorded probe outputs (fixtures/golden-set-probes.json) are run
     through the SHIPPED grader (grade_deterministic.py --json). A `pass` probe
     must clear every deterministic check; a `fail` probe must fail at least
     one, and — when it names `fails_on` — at least one failure must be of that
     check type. For an abstention control that means a fabricated answer fails
     on its absent_regex, for zero judge tokens.

Every eval-ready canary needs at least one pass probe and one fail probe, and a
suite with an abstention case needs one abstain case probed with a fabrication
that fails on absent_regex. The single exemption is git-commit: its abstention
case (gc-006) arrives with #2778, which ships its own fabricated/refusal
fixtures in test_grade_deterministic.sh.

Output follows .claude/rules/structured-script-output.md.

Usage: check_golden_set_evals.py [--project-dir DIR] [--probes FILE]
Exit:  0 OK, 1 a suite or probe failed, 2 usage error.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
GRADER = SCRIPT_DIR / "grade_deterministic.py"
DEFAULT_PROBES = Path("evaluate-plugin/scripts/tests/fixtures/golden-set-probes.json")

CHECK_FIELDS = {
    "regex": "pattern",
    "absent_regex": "pattern",
    "substring": "value",
    "substring_all": "values",
    "judge": None,
}
SCOPES = {"full", "subject", "body"}
OUTCOMES = {"comply", "abstain"}
ABSTAIN_PROBE_EXEMPT = {"git-plugin/git-commit"}


def frontmatter_name(skill_md: Path) -> str | None:
    lines = skill_md.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            return None
        m = re.match(r"^name:\s*(.+?)\s*$", line)
        if m:
            return m.group(1).strip("'\"")
    return None


def validate_suite(root: Path, ref: str, issues: list) -> dict | None:
    plugin, skill = ref.split("/", 1)
    rel = f"{plugin}/skills/{skill}/evals.json"
    path = root / rel
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as err:
        issues.append(("evals_unparseable", rel, f"cannot parse: {err}"))
        return None
    if (
        not isinstance(data, dict)
        or not isinstance(data.get("evals"), list)
        or not data["evals"]
    ):
        issues.append(("evals_empty", rel, "no non-empty evals[] array"))
        return None

    skill_md_rel = f"{plugin}/skills/{skill}/SKILL.md"
    if data.get("skill_path") != skill_md_rel:
        issues.append(
            (
                "skill_path_mismatch",
                rel,
                f"skill_path is {data.get('skill_path')!r}; expected {skill_md_rel!r}",
            )
        )
    skill_md = root / skill_md_rel
    if not skill_md.is_file():
        issues.append(("skill_md_missing", rel, f"{skill_md_rel} does not exist"))
    else:
        name = frontmatter_name(skill_md)
        if data.get("skill_name") != name:
            issues.append(
                (
                    "skill_name_mismatch",
                    rel,
                    f"skill_name is {data.get('skill_name')!r}; SKILL.md name is {name!r}",
                )
            )

    seen = set()
    for case in data["evals"]:
        cid = case.get("id") if isinstance(case, dict) else None
        if not cid:
            issues.append(("case_malformed", rel, "a case has no id"))
            continue
        if cid in seen:
            issues.append(("duplicate_id", rel, f"id {cid} appears twice"))
        seen.add(cid)
        for key in ("description", "prompt"):
            if not isinstance(case.get(key), str) or not case[key].strip():
                issues.append(("case_malformed", rel, f"{cid} has no {key}"))
        outcome = case.get("expected_outcome", "comply")
        if outcome not in OUTCOMES:
            issues.append(
                (
                    "expected_outcome_invalid",
                    rel,
                    f"{cid} has expected_outcome {outcome!r}",
                )
            )
        exps = case.get("expectations")
        if not isinstance(exps, list) or not exps:
            issues.append(("case_malformed", rel, f"{cid} has no expectations"))
            continue
        for exp in exps:
            if isinstance(exp, str):
                continue
            if not isinstance(exp, dict):
                issues.append(
                    (
                        "check_malformed",
                        rel,
                        f"{cid} has a non-string, non-object expectation",
                    )
                )
                continue
            check = exp.get("check", "judge")
            label = f"{cid}: {exp.get('assertion', '<no assertion>')}"
            if check not in CHECK_FIELDS:
                issues.append(
                    ("check_unknown", rel, f"{label} uses unknown check {check!r}")
                )
                continue
            field = CHECK_FIELDS[check]
            if field and field not in exp:
                issues.append(
                    ("check_malformed", rel, f"{label} ({check}) lacks {field!r}")
                )
                continue
            if exp.get("scope", "full") not in SCOPES:
                issues.append(
                    ("check_malformed", rel, f"{label} has scope {exp.get('scope')!r}")
                )
            flags = exp.get("flags", "")
            if any(ch not in "imsx" for ch in flags):
                issues.append(("check_malformed", rel, f"{label} has flags {flags!r}"))
                continue
            if check in ("regex", "absent_regex"):
                table = {"i": re.I, "m": re.M, "s": re.S, "x": re.X}
                value = 0
                for ch in flags:
                    value |= table[ch]
                try:
                    re.compile(exp["pattern"], value)
                except re.error as err:
                    issues.append(("pattern_invalid", rel, f"{label}: {err}"))
    return {
        "rel": rel,
        "cases": {c.get("id"): c for c in data["evals"] if isinstance(c, dict)},
    }


def grade(evals_path: Path, case_id: str, output: str) -> dict:
    proc = subprocess.run(
        [
            sys.executable,
            str(GRADER),
            "--evals",
            str(evals_path),
            "--eval-id",
            case_id,
            "--output",
            "-",
            "--json",
        ],
        input=output,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or f"grader exited {proc.returncode}")
    return json.loads(proc.stdout)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--project-dir", default=None)
    parser.add_argument("--probes", default=None)
    args = parser.parse_args(argv)

    root = (
        Path(args.project_dir).resolve() if args.project_dir else SCRIPT_DIR.parents[1]
    )
    if not root.is_dir():
        print(
            f"check_golden_set_evals.py: --project-dir {root} is not a directory",
            file=sys.stderr,
        )
        return 2
    probes_path = Path(args.probes) if args.probes else root / DEFAULT_PROBES

    issues: list = []
    golden = root / "evaluate-plugin/golden-set.json"
    try:
        gs = json.loads(golden.read_text(encoding="utf-8"))
        canaries = [c["skill"] for c in gs.get("canaries", [])]
        floor = gs.get("evalCoverageFloor")
    except (OSError, ValueError, KeyError, TypeError) as err:
        print("=== GOLDEN SET EVALS ===")
        print("STATUS=ERROR")
        print("ISSUE_COUNT=1")
        print("ISSUES:")
        print(
            f"  - SEVERITY=ERROR TYPE=golden_set_unreadable FILE=evaluate-plugin/golden-set.json MSG={err}"
        )
        print("=== END GOLDEN SET EVALS ===")
        return 1

    ready = [
        ref
        for ref in canaries
        if (
            root / f"{ref.split('/', 1)[0]}/skills/{ref.split('/', 1)[1]}/evals.json"
        ).is_file()
    ]
    suites = {}
    for ref in ready:
        suite = validate_suite(root, ref, issues)
        if suite:
            suites[ref] = suite

    if not ready:
        issues.append(
            (
                "nothing_scanned",
                "evaluate-plugin/golden-set.json",
                "no canary carries an evals.json; nothing was validated",
            )
        )
    if isinstance(floor, int) and len(ready) < floor:
        issues.append(
            (
                "coverage_below_floor",
                "evaluate-plugin/golden-set.json",
                f"{len(ready)} of {len(canaries)} canaries carry an evals.json, below the floor of {floor}",
            )
        )

    try:
        probes = json.loads(probes_path.read_text(encoding="utf-8")).get("probes", [])
    except (OSError, ValueError) as err:
        probes = []
        issues.append(
            ("probes_unreadable", str(probes_path), f"cannot read probes: {err}")
        )

    passes, fails, abstain_fail = {}, {}, {}
    run = 0
    for i, probe in enumerate(probes):
        ref, cid, expect = probe.get("suite"), probe.get("case"), probe.get("expect")
        where = f"probe[{i}] {ref}#{cid}"
        if ref not in suites:
            issues.append(
                (
                    "probe_unknown_suite",
                    str(probes_path),
                    f"{where}: suite is not an eval-ready canary",
                )
            )
            continue
        case = suites[ref]["cases"].get(cid)
        if case is None:
            issues.append(
                ("probe_unknown_case", str(probes_path), f"{where}: no such case")
            )
            continue
        if expect not in ("pass", "fail"):
            issues.append(
                ("probe_malformed", str(probes_path), f"{where}: expect is {expect!r}")
            )
            continue
        if "output_file" in probe:
            output = (probes_path.parent / probe["output_file"]).read_text(
                encoding="utf-8"
            )
        else:
            output = probe.get("output", "")
        try:
            graded = grade(root / suites[ref]["rel"], cid, output)
        except (RuntimeError, ValueError) as err:
            issues.append(("grader_failed", suites[ref]["rel"], f"{where}: {err}"))
            continue
        run += 1
        summary = graded["summary"]
        failed = [r for r in graded["deterministic"] if not r.get("passed")]
        if summary["deterministic_total"] == 0:
            issues.append(
                (
                    "probe_vacuous",
                    suites[ref]["rel"],
                    f"{where}: the case has no deterministic check",
                )
            )
            continue
        if expect == "pass":
            if failed:
                names = "; ".join(r["assertion"] for r in failed)
                issues.append(
                    (
                        "pass_probe_failed",
                        suites[ref]["rel"],
                        f"{where}: expected clean, failed: {names}",
                    )
                )
            passes[ref] = passes.get(ref, 0) + 1
        else:
            if not failed:
                issues.append(
                    (
                        "fail_probe_passed",
                        suites[ref]["rel"],
                        f"{where}: a known-bad output cleared every deterministic check",
                    )
                )
            want = probe.get("fails_on")
            if want and failed and not any(r["check"] == want for r in failed):
                issues.append(
                    (
                        "fail_probe_wrong_check",
                        suites[ref]["rel"],
                        f"{where}: expected a {want} failure, got {sorted({r['check'] for r in failed})}",
                    )
                )
            fails[ref] = fails.get(ref, 0) + 1
            if (
                case.get("expected_outcome") == "abstain"
                and want == "absent_regex"
                and any(r["check"] == "absent_regex" for r in failed)
            ):
                abstain_fail[ref] = abstain_fail.get(ref, 0) + 1

    for ref in suites:
        if not passes.get(ref):
            issues.append(
                (
                    "no_pass_probe",
                    suites[ref]["rel"],
                    "no probe shows a correct answer clearing the checks",
                )
            )
        if not fails.get(ref):
            issues.append(
                (
                    "no_fail_probe",
                    suites[ref]["rel"],
                    "no probe shows a wrong answer failing the checks",
                )
            )
        has_abstain = any(
            c.get("expected_outcome") == "abstain"
            for c in suites[ref]["cases"].values()
        )
        if (
            has_abstain
            and ref not in ABSTAIN_PROBE_EXEMPT
            and not abstain_fail.get(ref)
        ):
            issues.append(
                (
                    "abstention_unprobed",
                    suites[ref]["rel"],
                    "no fabricated answer is shown failing an abstention case's absent_regex",
                )
            )

    print("=== GOLDEN SET EVALS ===")
    print(f"CANARIES_TOTAL={len(canaries)}")
    print(f"CANARIES_EVAL_READY={len(ready)}")
    print(f"COVERAGE_FLOOR={floor}")
    print(f"SUITES_VALID={len(suites)}")
    print(f"CASES_TOTAL={sum(len(s['cases']) for s in suites.values())}")
    print(
        f"ABSTAIN_CASES={sum(1 for s in suites.values() for c in s['cases'].values() if c.get('expected_outcome') == 'abstain')}"
    )
    print(f"PROBES_RUN={run}")
    print(f"ABSTAIN_PROBE_EXEMPT={','.join(sorted(ABSTAIN_PROBE_EXEMPT))}")
    print(f"STATUS={'ERROR' if issues else 'OK'}")
    print(f"ISSUE_COUNT={len(issues)}")
    if issues:
        print("ISSUES:")
        for kind, where, msg in issues:
            print(f"  - SEVERITY=ERROR TYPE={kind} FILE={where} MSG={msg}")
    print("=== END GOLDEN SET EVALS ===")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())

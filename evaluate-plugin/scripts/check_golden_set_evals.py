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
     abstain; a fixture holds no single quote (it is passed as
     `--fixture '<JSON>'`); every typed check has a known type (all 13 grade_deterministic.py
     types), its required fields, a valid scope, flags drawn from `imsx`, and
     patterns that compile. Trace/workspace checks are held to the grader's
     own contract: workspace paths relative with no `..`, `min <= max`,
     exactly one json_path comparator, boolean `expect`/`exists`. An optional
     `triggers` block is validated by run_trigger_evals.validate_triggers, the
     same function the trigger runner uses, so the two cannot drift.
  2. Teeth: recorded probe outputs (fixtures/golden-set-probes.json) are run
     through the SHIPPED grader (grade_deterministic.py --json). A `pass` probe
     must clear every deterministic check; a `fail` probe must fail at least
     one, and — when it names `fails_on` — at least one failure must be of that
     check type. For an abstention control that means a fabricated answer fails
     on its absent_regex, for zero judge tokens.

Probes for trace/workspace checks carry the headless-harness inputs:
`trace_file` (a trace.json v1, relative to the probes file), `workspace_dir`
(a directory relative to the probes file) or `workspace_setup` (shell commands
materialised into a fresh temp dir, so no nested `.git` is ever committed).
A probe with a workspace is graded with --allow-exec: probes and evals.json are
repo-authored. A `pass` probe on a case with trace or workspace checks must
report HARNESS_DEFERRED=0 — otherwise the checks it claims to exercise were
never graded.

Every eval-ready canary needs at least one pass probe and one fail probe, and a
suite with an abstention case needs one abstain case probed with a fabrication
that fails on absent_regex.

Output follows .claude/rules/structured-script-output.md.

Usage: check_golden_set_evals.py [--project-dir DIR] [--probes FILE]
Exit:  0 OK, 1 a suite or probe failed, 2 usage error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath

SCRIPT_DIR = Path(__file__).resolve().parent
GRADER = SCRIPT_DIR / "grade_deterministic.py"
DEFAULT_PROBES = Path("evaluate-plugin/scripts/tests/fixtures/golden-set-probes.json")

sys.path.insert(0, str(SCRIPT_DIR))
from grade_deterministic import MalformedCheck, _parse_query  # noqa: E402
from run_trigger_evals import validate_triggers  # noqa: E402

# Required fields per check type -- every type grade_deterministic.py
# dispatches, plus judge. A missing field is check_malformed.
CHECK_FIELDS = {
    "regex": ("pattern",),
    "absent_regex": ("pattern",),
    "substring": ("value",),
    "substring_all": ("values",),
    "judge": (),
    "skill_triggered": ("skill",),
    "tool_called": ("tool",),
    "command_ran": ("pattern",),
    "file_exists": ("path",),
    "file_regex": ("path", "pattern"),
    "file_absent_regex": ("path", "pattern"),
    "json_path": ("path", "query"),
    "run_command": ("command",),
}
# Pattern-bearing keys per check type; each present one must compile with the
# check's flags (drives pattern_invalid).
PATTERN_CHECKS = {
    "regex": ("pattern",),
    "absent_regex": ("pattern",),
    "tool_called": ("pattern",),
    "command_ran": ("pattern",),
    "file_regex": ("pattern",),
    "file_absent_regex": ("pattern",),
    "json_path": ("regex",),
    "run_command": ("stdout_regex",),
}
TRACE_CHECKS = {"skill_triggered", "tool_called", "command_ran"}
WORKSPACE_CHECKS = {
    "file_exists",
    "file_regex",
    "file_absent_regex",
    "json_path",
    "run_command",
}
SCOPES = {"full", "subject", "body"}
OUTCOMES = {"comply", "abstain"}
# Suites allowed an abstention case without a fabrication probe. Empty since
# gc-006 gained its own probes (fabricated -> absent_regex; a commit that ran
# -> command_ran).
ABSTAIN_PROBE_EXEMPT: set = set()
FLAG_TABLE = {"i": re.I, "m": re.M, "s": re.S, "x": re.X}


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


def _nonneg_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def _check_shape(check: str, exp: dict) -> list[str]:
    """Problems with a typed check's non-pattern fields (empty when sound).

    Mirrors the grader's own MalformedCheck rules so an authoring error is
    caught at validation time, not on the first headless run.
    """
    problems = []
    if "path" in exp:
        path = exp["path"]
        if not isinstance(path, str) or not path.strip():
            problems.append("path must be a non-empty string")
        elif PurePosixPath(path).is_absolute() or ".." in PurePosixPath(path).parts:
            problems.append(f"path {path!r} must be relative with no '..'")
    for key in ("expect", "exists"):
        if key in exp and not isinstance(exp[key], bool):
            problems.append(f"{key} must be a boolean")
    if check in ("tool_called", "command_ran"):
        lo, hi = exp.get("min"), exp.get("max")
        for key, value in (("min", lo), ("max", hi)):
            if value is not None and not _nonneg_int(value):
                problems.append(f"{key} must be a non-negative integer")
        if _nonneg_int(lo) and _nonneg_int(hi) and lo > hi:
            problems.append(f"min ({lo}) > max ({hi})")
    if check == "json_path":
        comparators = [k for k in ("equals", "regex", "exists") if k in exp]
        if len(comparators) != 1:
            problems.append(
                f"json_path needs exactly one of equals|regex|exists, got {comparators or 'none'}"
            )
        try:
            _parse_query(exp.get("query"))
        except MalformedCheck as err:
            problems.append(str(err))
    if check == "run_command":
        if not isinstance(exp.get("command"), str) or not exp["command"].strip():
            problems.append("command must be a non-empty string")
        if "expect_exit" in exp and (
            isinstance(exp["expect_exit"], bool)
            or not isinstance(exp["expect_exit"], int)
        ):
            problems.append("expect_exit must be an integer")
        timeout = exp.get("timeout", 30)
        if (
            isinstance(timeout, bool)
            or not isinstance(timeout, (int, float))
            or timeout <= 0
        ):
            problems.append("timeout must be a positive number")
    for key in {"skill_triggered": ("skill",), "tool_called": ("tool",)}.get(check, ()):
        if not isinstance(exp.get(key), str) or not exp[key].strip():
            problems.append(f"{key} must be a non-empty string")
    return problems


def _plugin_name(root: Path, plugin: str) -> str | None:
    try:
        data = json.loads(
            (root / plugin / ".claude-plugin" / "plugin.json").read_text(
                encoding="utf-8"
            )
        )
    except (OSError, ValueError):
        return None
    name = data.get("name") if isinstance(data, dict) else None
    return name if isinstance(name, str) else None


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
        # Every rollout prompt and SKILL.md applies a fixture as
        # `apply_fixture.sh --fixture '<the fixture JSON>'`. A single quote
        # inside the JSON splits that shell word: the script then sees
        # truncated JSON, reports FIXTURE_APPLIED=false STATUS=OK, and the cell
        # runs with no fixture (in the user's repo, on the subagent harness).
        fixture = case.get("fixture")
        if fixture is not None and "'" in json.dumps(fixture, ensure_ascii=False):
            issues.append(
                (
                    "fixture_unquotable",
                    rel,
                    f"{cid} fixture contains a single quote; the documented "
                    f"--fixture '<JSON>' invocation would split it (use double quotes)",
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
            missing = [f for f in CHECK_FIELDS[check] if f not in exp]
            if missing:
                issues.append(
                    ("check_malformed", rel, f"{label} ({check}) lacks {missing[0]!r}")
                )
                continue
            if exp.get("scope", "full") not in SCOPES:
                issues.append(
                    ("check_malformed", rel, f"{label} has scope {exp.get('scope')!r}")
                )
            flags = exp.get("flags", "")
            if not isinstance(flags, str) or any(ch not in FLAG_TABLE for ch in flags):
                issues.append(("check_malformed", rel, f"{label} has flags {flags!r}"))
                continue
            shape = _check_shape(check, exp)
            if shape:
                issues.append(
                    ("check_malformed", rel, f"{label} ({check}): {shape[0]}")
                )
                continue
            value = 0
            for ch in flags:
                value |= FLAG_TABLE[ch]
            for key in PATTERN_CHECKS.get(check, ()):
                if key not in exp:
                    continue
                try:
                    if not isinstance(exp[key], str):
                        raise re.error(f"{key} must be a string")
                    re.compile(exp[key], value)
                except re.error as err:
                    issues.append(("pattern_invalid", rel, f"{label}: {err}"))

    if "triggers" in data:
        names = tuple(
            n
            for n in (skill, frontmatter_name(skill_md) if skill_md.is_file() else None)
            if n
        )
        errors, _peers = validate_triggers(
            data["triggers"],
            seen,
            root,
            own_plugin=_plugin_name(root, plugin),
            skill_names=names,
        )
        for err in errors:
            issues.append(("triggers_invalid", rel, err))
    return {
        "rel": rel,
        "cases": {c.get("id"): c for c in data["evals"] if isinstance(c, dict)},
    }


def case_needs(case: dict) -> set:
    """Which headless inputs a case's typed checks read: {'trace','workspace'}."""
    needs = set()
    for exp in case.get("expectations", []):
        if isinstance(exp, dict):
            if exp.get("check") in TRACE_CHECKS:
                needs.add("trace")
            elif exp.get("check") in WORKSPACE_CHECKS:
                needs.add("workspace")
    return needs


def materialise_workspace(commands: list, dest: Path) -> None:
    """Run ``workspace_setup`` commands in ``dest`` with a hermetic git env.

    Raises RuntimeError naming the first command that fails.
    """
    home = dest.parent / "home"
    home.mkdir(exist_ok=True)
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": str(home),
        "LANG": "C.UTF-8",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_AUTHOR_NAME": "eval",
        "GIT_AUTHOR_EMAIL": "eval@example.invalid",
        "GIT_COMMITTER_NAME": "eval",
        "GIT_COMMITTER_EMAIL": "eval@example.invalid",
        "GIT_TERMINAL_PROMPT": "0",
    }
    for cmd in commands:
        if not isinstance(cmd, str):
            raise RuntimeError(f"workspace_setup entry {cmd!r} is not a string")
        proc = subprocess.run(
            ["bash", "-c", cmd],
            cwd=dest,
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        if proc.returncode != 0:
            raise RuntimeError(
                f"workspace_setup {cmd!r} exited {proc.returncode}: {proc.stderr.strip()[:200]}"
            )


def grade(
    evals_path: Path,
    case_id: str,
    output: str,
    trace: Path | None = None,
    workspace: Path | None = None,
) -> dict:
    cmd = [
        sys.executable,
        str(GRADER),
        "--evals",
        str(evals_path),
        "--eval-id",
        case_id,
        "--output",
        "-",
        "--json",
    ]
    if trace is not None:
        cmd += ["--trace", str(trace)]
    if workspace is not None:
        cmd += ["--workspace", str(workspace), "--allow-exec"]
    proc = subprocess.run(
        cmd,
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
        try:
            if "output_file" in probe:
                output = (probes_path.parent / probe["output_file"]).read_text(
                    encoding="utf-8"
                )
            else:
                output = probe.get("output", "")
        except OSError as err:
            issues.append(("probe_malformed", str(probes_path), f"{where}: {err}"))
            continue
        trace = None
        if "trace_file" in probe:
            trace = probes_path.parent / str(probe["trace_file"])
            if not trace.is_file():
                issues.append(
                    (
                        "probe_malformed",
                        str(probes_path),
                        f"{where}: no trace_file {trace}",
                    )
                )
                continue
        if "workspace_dir" in probe and "workspace_setup" in probe:
            issues.append(
                (
                    "probe_malformed",
                    str(probes_path),
                    f"{where}: give workspace_dir or workspace_setup, not both",
                )
            )
            continue
        scratch = None
        workspace = None
        try:
            if "workspace_dir" in probe:
                workspace = probes_path.parent / str(probe["workspace_dir"])
                if not workspace.is_dir():
                    issues.append(
                        (
                            "probe_malformed",
                            str(probes_path),
                            f"{where}: no workspace_dir {workspace}",
                        )
                    )
                    continue
            elif "workspace_setup" in probe:
                setup = probe["workspace_setup"]
                if not isinstance(setup, list):
                    issues.append(
                        (
                            "probe_malformed",
                            str(probes_path),
                            f"{where}: workspace_setup must be a list of commands",
                        )
                    )
                    continue
                scratch = Path(tempfile.mkdtemp(prefix="golden-probe-"))
                workspace = scratch / "ws"
                workspace.mkdir()
                try:
                    materialise_workspace(setup, workspace)
                except (RuntimeError, subprocess.TimeoutExpired) as err:
                    issues.append(
                        ("probe_setup_failed", str(probes_path), f"{where}: {err}")
                    )
                    continue
            try:
                graded = grade(root / suites[ref]["rel"], cid, output, trace, workspace)
            except (RuntimeError, ValueError) as err:
                issues.append(("grader_failed", suites[ref]["rel"], f"{where}: {err}"))
                continue
        finally:
            if scratch is not None:
                shutil.rmtree(scratch, ignore_errors=True)
        run += 1
        summary = graded["summary"]
        needs = case_needs(case)
        if expect == "pass" and needs and summary.get("harness_deferred", 0):
            deferred = "; ".join(
                r["assertion"] for r in graded.get("harness_deferred", [])
            )
            issues.append(
                (
                    "pass_probe_harness_deferred",
                    suites[ref]["rel"],
                    f"{where}: the case's {'/'.join(sorted(needs))} checks were never graded "
                    f"(HARNESS_DEFERRED={summary['harness_deferred']}: {deferred}); "
                    "give the probe trace_file / workspace_dir / workspace_setup",
                )
            )
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
    print(
        f"HEADLESS_CASES={sum(1 for s in suites.values() for c in s['cases'].values() if case_needs(c))}"
    )
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

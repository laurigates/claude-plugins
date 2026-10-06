#!/usr/bin/env python3
"""Run a skill's trigger evals: does description routing pick the skill?

Reads the optional ``triggers`` block of ``<skill-dir>/evals.json``::

    "triggers": {
      "skill": "<plugin>:<skill>",
      "should_trigger":     [{"id": "", "prompt": ""}],
      "should_not_trigger": [{"id": "", "prompt": "", "near_miss_of": ""}],
      "peers": ["<plugin-dir>"],
      "max_turns": 2
    }

and runs every prompt through ``rollout_headless.sh`` (one real headless
``claude -p`` child per run) with ``--allowed-tools Skill --permission default
--stop-on-skill`` in an empty mktemp workdir, loading the skill's own plugin
plus every ``peers`` plugin dir (peers are resolved against the marketplace
root, i.e. the parent of the skill's plugin dir). The child is killed at its
first Skill tool_use, so a run costs little more than one routing decision.

A run TRIGGERED when its trace.json ``skills_invoked[]`` names the target skill
by full (``plugin:skill``) or bare (``skill``) name; a denied invocation still
counts (routing chose it), matching grade_deterministic.py ``skill_triggered``.
With ``--runs N`` each prompt gets a trigger RATE over its non-error runs and
counts as triggered when the rate is >= 0.5. A prompt whose every run errored is
an ERROR row and is excluded from tp/fp/fn/tn.

Budget: every run is capped at ``--max-budget-usd-per-prompt``. A run whose cost
is unknown -- the child was killed (stop-on-skill, timeout) before its result
event, or it errored -- is CHARGED AT THAT CAP. Before each run the runner
checks that the worst case still fits ``--total-budget-usd``; if not it aborts,
keeps every finished row, and marks the rest SKIPPED (STATUS=ERROR).

Writes ``triggers.json`` (``--output``, default
``<runs-root>/<plugin>/<skill>/triggers/<stamp>/triggers.json``, where
<runs-root> is $EVAL_RUNS_ROOT, else <repo>/tmp/eval-runs, else
$TMPDIR/claude-eval-runs -- the same root prepare_run.sh uses) and copies it to
``<skill-dir>/eval-results/triggers.json``. ``--no-copy`` skips that copy, so a
smoke or test run never overwrites the skill's genuine results (``COPY=none``).
``--dry-run`` validates and prints the plan without running or writing anything.

Summary maths: recall = tp/(tp+fn); precision = tp/(tp+fp), null when nothing
was predicted positive (tp+fp == 0); fpr = fp/(fp+tn); each null on a zero
denominator.

STATUS: OK; WARN when recall < --min-recall or fp > --max-false-positives
(trigger results are noisy at n=1 -- use --runs 3 for decisions); ERROR on a
budget abort, a rollout usage error, more than 50% ERROR rows, or an invalid
triggers block.

Env: EVAL_ROLLOUT_SCRIPT overrides the rollout script path (tests use a stub).

Usage:
  run_trigger_evals.py --skill-dir <dir> [--model haiku] [--runs 1]
    [--max-budget-usd-per-prompt 0.05] [--total-budget-usd 1.00] [--only <id>]...
    [--min-recall 0.66] [--max-false-positives 0] [--skill-listing-budget <n>|cli]
    [--output <file>] [--no-copy] [--dry-run]

Output follows .claude/rules/structured-script-output.md
(``=== TRIGGER EVALS ===`` block).
Exit: 0 OK/WARN, 1 ERROR, 2 usage error.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ROLLOUT = SCRIPT_DIR / "rollout_headless.sh"
EPS = 1e-9
# Headroom over rollout_headless.sh's own --timeout (300s + 10s kill-after)
# before the runner gives up on the subprocess itself.
SUBPROCESS_TIMEOUT_S = 420


class UsageError(Exception):
    pass


# ----------------------------------------------------------------- helpers


def one_line(text: str, cap: int = 180) -> str:
    return " ".join(str(text).split())[:cap]


def fmt_num(value) -> str:
    """KEY=VALUE rendering: empty for null, trimmed decimals otherwise."""
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return f"{value:.4f}".rstrip("0").rstrip(".") or "0"


def ratio(num: int, den: int):
    return None if den == 0 else round(num / den, 4)


def bare_skill(name: str) -> str:
    return name.rsplit(":", 1)[-1]


def skill_matches(invoked, wanted: str) -> bool:
    """Same semantics as grade_deterministic.py _skill_matches."""
    if not isinstance(invoked, str) or not invoked:
        return False
    inv = invoked.lstrip("/")
    want = wanted.lstrip("/")
    if inv == want:
        return True
    if ":" in want:
        return ":" not in inv and inv == bare_skill(want)
    return bare_skill(inv) == want


def skill_md_name(skill_dir: Path) -> str | None:
    md = skill_dir / "SKILL.md"
    try:
        text = md.read_text(encoding="utf-8")
    except OSError:
        return None
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.S)
    if not m:
        return None
    for line in m.group(1).splitlines():
        km = re.match(r"^name:\s*(.+?)\s*$", line)
        if km:
            return km.group(1).strip().strip("'\"")
    return None


def plugin_name(plugin_dir: Path) -> str | None:
    try:
        data = json.loads(
            (plugin_dir / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8")
        )
    except (OSError, ValueError):
        return None
    name = data.get("name") if isinstance(data, dict) else None
    return name if isinstance(name, str) else None


# ----------------------------------------------------------------- validation


def validate_triggers(
    triggers,
    eval_ids,
    marketplace_root: Path,
    own_plugin: str | None = None,
    skill_names: tuple = (),
) -> tuple[list[str], list[Path]]:
    """Validate an evals.json ``triggers`` block.

    Returns (errors, resolved_peer_dirs). Reusable by check_golden_set_evals.py.
    """
    errors: list[str] = []
    peers: list[Path] = []
    if not isinstance(triggers, dict):
        return ["triggers must be an object"], peers

    skill = triggers.get("skill")
    if not isinstance(skill, str) or not re.fullmatch(
        r"[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+", skill
    ):
        errors.append("triggers.skill must be '<plugin>:<skill>'")
    else:
        plug, sk = skill.split(":", 1)
        if own_plugin is not None and plug != own_plugin:
            errors.append(
                f"triggers.skill plugin {plug!r} is not this skill's plugin {own_plugin!r}"
            )
        if skill_names and sk not in skill_names:
            errors.append(
                f"triggers.skill name {sk!r} matches neither the skill dir nor SKILL.md name {sorted(set(skill_names))!r}"
            )

    seen: dict[str, str] = {}
    eval_ids = {str(e) for e in eval_ids}
    total = 0
    for kind in ("should_trigger", "should_not_trigger"):
        items = triggers.get(kind, [])
        if not isinstance(items, list):
            errors.append(f"triggers.{kind} must be a list")
            continue
        for i, item in enumerate(items):
            where = f"triggers.{kind}[{i}]"
            if not isinstance(item, dict):
                errors.append(f"{where} must be an object")
                continue
            total += 1
            tid = item.get("id")
            if not isinstance(tid, str) or not tid.strip():
                errors.append(f"{where}.id must be a non-empty string")
            else:
                if tid in seen:
                    errors.append(f"{where}.id {tid!r} duplicates {seen[tid]}")
                else:
                    seen[tid] = where
                if tid in eval_ids:
                    errors.append(f"{where}.id {tid!r} collides with an evals[].id")
            prompt = item.get("prompt")
            if not isinstance(prompt, str) or not prompt.strip():
                errors.append(f"{where}.prompt must be a non-empty string")
            nm = item.get("near_miss_of")
            if nm is not None and (
                kind != "should_not_trigger"
                or not isinstance(nm, str)
                or not nm.strip()
            ):
                errors.append(
                    f"{where}.near_miss_of must be a non-empty string on should_not_trigger only"
                )
    if total == 0:
        errors.append(
            "triggers needs at least one should_trigger or should_not_trigger prompt"
        )

    raw_peers = triggers.get("peers", [])
    if not isinstance(raw_peers, list):
        errors.append("triggers.peers must be a list of plugin dirs")
        raw_peers = []
    for i, p in enumerate(raw_peers):
        if not isinstance(p, str) or not p.strip():
            errors.append(f"triggers.peers[{i}] must be a non-empty string")
            continue
        pp = Path(p)
        if not pp.is_absolute():
            if ".." in pp.parts:
                errors.append(f"triggers.peers[{i}] {p!r} must not contain '..'")
                continue
            pp = marketplace_root / pp
        if not (pp / ".claude-plugin" / "plugin.json").is_file():
            errors.append(
                f"triggers.peers[{i}] {p!r} is not a plugin dir (no .claude-plugin/plugin.json under {pp})"
            )
            continue
        peers.append(pp.resolve())

    mt = triggers.get("max_turns")
    if mt is not None and (isinstance(mt, bool) or not isinstance(mt, int) or mt < 1):
        errors.append("triggers.max_turns must be a positive integer")
    return errors, peers


# ----------------------------------------------------------------- rollout


def parse_block(stdout: str, name: str = "HEADLESS ROLLOUT") -> dict:
    out: dict[str, str] = {}
    inside = False
    for line in stdout.splitlines():
        if line.strip() == f"=== {name} ===":
            inside = True
            continue
        if line.strip() == f"=== END {name} ===":
            break
        if inside and re.match(r"^[A-Z][A-Z0-9_]*=", line):
            k, v = line.split("=", 1)
            out.setdefault(k, v)
    return out


def runs_root_for(skill_dir: Path) -> Path:
    env = os.environ.get("EVAL_RUNS_ROOT")
    if env:
        p = Path(env)
        return p if p.is_absolute() else Path.cwd() / p
    try:
        top = subprocess.run(
            ["git", "-C", str(skill_dir), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if top.returncode == 0 and top.stdout.strip():
            return Path(top.stdout.strip()) / "tmp" / "eval-runs"
    except (OSError, subprocess.SubprocessError):
        pass
    return Path(os.environ.get("TMPDIR") or "/tmp") / "claude-eval-runs"


def run_one(
    rollout: Path,
    run_dir: Path,
    prompt: str,
    plugin_dirs: list[Path],
    model: str,
    cap: float,
    max_turns: int | None,
    skill_listing_budget: str | None = None,
) -> dict:
    """One headless rollout. Returns a run record (cost_charged always set)."""
    run_dir.mkdir(parents=True, exist_ok=True)
    workdir = Path(tempfile.mkdtemp(prefix="trig-wd."))
    cmd = [
        "bash",
        str(rollout),
        "--run-dir",
        str(run_dir),
        "--workdir",
        str(workdir),
        "--prompt",
        prompt,
        "--model",
        model,
        "--max-budget-usd",
        fmt_num(cap),
        "--tools",
        "Skill",
        "--allowed-tools",
        "Skill",
        "--permission",
        "default",
        "--stop-on-skill",
        "--no-snapshot",
    ]
    for pd in plugin_dirs:
        cmd += ["--plugin-dir", str(pd)]
    if max_turns is not None:
        cmd += ["--max-turns", str(max_turns)]
    if skill_listing_budget is not None:
        cmd += ["--skill-listing-budget", skill_listing_budget]
    rec: dict = {
        "run_dir": str(run_dir),
        "status": "ERROR",
        "triggered": None,
        "skills_invoked": [],
        "cost": None,
        "cost_known": False,
        "cost_charged": cap,
        "stop_reason": None,
        "rollout_status": None,
        "rollout_exit": None,
        "reason": None,
    }
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=SUBPROCESS_TIMEOUT_S
        )
    except subprocess.TimeoutExpired:
        rec.update(
            stop_reason="timeout",
            reason=f"rollout exceeded {SUBPROCESS_TIMEOUT_S}s and was killed",
        )
        return rec
    except OSError as exc:
        rec.update(reason=f"could not run rollout: {exc}", cost_charged=0.0)
        return rec
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    try:
        (run_dir / "rollout.out").write_text(proc.stdout, encoding="utf-8")
    except OSError:
        pass
    kv = parse_block(proc.stdout)
    rec["rollout_exit"] = proc.returncode
    rec["rollout_status"] = kv.get("STATUS") or None
    rec["stop_reason"] = kv.get("STOP_REASON") or None
    cost_raw = kv.get("COST_USD", "")
    try:
        cost = float(cost_raw) if cost_raw not in ("", "null") else None
    except ValueError:
        cost = None
    if cost is not None:
        rec.update(cost=cost, cost_known=True, cost_charged=cost)

    if proc.returncode == 2:
        # A usage/guard error: nothing ran, and every later run would hit it too.
        rec.update(
            status="USAGE",
            cost_charged=0.0,
            reason=one_line(kv.get("REASON") or proc.stderr or "rollout usage error"),
        )
        return rec
    trace_path = kv.get("TRACE", "")
    trace = None
    if trace_path:
        try:
            trace = json.loads(Path(trace_path).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            trace = None
    if (
        proc.returncode != 0
        or kv.get("STATUS") == "ERROR"
        or not isinstance(trace, dict)
    ):
        reason = kv.get("REASON") or (
            "no trace.json"
            if not isinstance(trace, dict)
            else f"rollout exit {proc.returncode}"
        )
        rec["reason"] = one_line(reason)
        return rec
    invoked = [s for s in trace.get("skills_invoked") or [] if isinstance(s, dict)]
    rec["skills_invoked"] = sorted(
        {str(s.get("skill")) for s in invoked if s.get("skill")}
    )
    rec["model_id"] = trace.get("model_id")
    rec["status"] = "OK"
    rec["_invoked"] = invoked
    return rec


# ----------------------------------------------------------------- main


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--skill-dir", required=True)
    ap.add_argument("--model", default="haiku")
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--max-budget-usd-per-prompt", type=float, default=0.05)
    ap.add_argument("--total-budget-usd", type=float, default=1.00)
    ap.add_argument("--only", action="append", default=[])
    ap.add_argument("--min-recall", type=float, default=0.66)
    ap.add_argument("--max-false-positives", type=int, default=0)
    ap.add_argument(
        "--skill-listing-budget",
        help="forwarded to rollout_headless.sh: characters for the CLI's Skill "
        "listing, or 'cli' for the CLI default (rollout default: 100000)",
    )
    ap.add_argument("--output")
    ap.add_argument("--no-copy", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    return ap


def emit(
    status: str,
    keys: list[tuple[str, object]],
    issues: list[tuple[str, str, str]],
    rows_lines: list[str] | None = None,
    rows_header: str = "RESULTS:",
) -> None:
    print("=== TRIGGER EVALS ===")
    for k, v in keys:
        print(f"{k}={v}")
    print(f"STATUS={status}")
    if status != "OK":
        first = next(
            (i for i in issues if i[0] == status), issues[0] if issues else None
        )
        if first:
            reason = one_line(f"{first[1]}: {first[2]}", 180)
            if len(issues) > 1:
                reason += f" (+{len(issues) - 1} more)"
            print(f"REASON={reason}")
    print(f"ISSUE_COUNT={len(issues)}")
    if issues:
        print("ISSUES:")
        for sev, typ, msg in issues:
            print(f"  - SEVERITY={sev} TYPE={typ} MSG={one_line(msg, 300)}")
    if rows_lines:
        print(rows_header)
        for line in rows_lines:
            print(line)
    print("=== END TRIGGER EVALS ===")


def usage_exit(msg: str) -> int:
    emit("ERROR", [], [("ERROR", "usage", msg)])
    return 2


def main(argv: list[str] | None = None) -> int:
    ap = build_parser()
    try:
        args = ap.parse_args(argv)
    except SystemExit as exc:
        return 0 if exc.code == 0 else 2
    try:
        return run(args)
    except UsageError as exc:
        return usage_exit(str(exc))


def run(args) -> int:
    if args.runs < 1:
        raise UsageError("--runs must be >= 1")
    cap = args.max_budget_usd_per_prompt
    if not cap > 0:
        raise UsageError("--max-budget-usd-per-prompt must be > 0")
    slb = args.skill_listing_budget
    if slb is not None and slb != "cli" and not (slb.isdigit() and int(slb) > 0):
        raise UsageError("--skill-listing-budget must be a positive integer or 'cli'")
    if not args.total_budget_usd > 0:
        raise UsageError("--total-budget-usd must be > 0")
    if not 0 <= args.min_recall <= 1:
        raise UsageError("--min-recall must be within 0..1")
    if args.max_false_positives < 0:
        raise UsageError("--max-false-positives must be >= 0")

    skill_dir = Path(args.skill_dir)
    if not skill_dir.is_dir():
        raise UsageError(f"skill dir not found: {args.skill_dir}")
    skill_dir = skill_dir.resolve()
    evals_path = skill_dir / "evals.json"
    try:
        evals = json.loads(evals_path.read_text(encoding="utf-8"))
    except OSError:
        raise UsageError(f"evals.json not found: {evals_path}")
    except ValueError as exc:
        raise UsageError(f"evals.json is not valid JSON: {exc}")
    if not isinstance(evals, dict) or "triggers" not in evals:
        raise UsageError(f"{evals_path} has no triggers block")

    plugin_dir = skill_dir.parent.parent
    marketplace_root = plugin_dir.parent
    issues: list[tuple[str, str, str]] = []
    own_plugin = plugin_name(plugin_dir)
    if own_plugin is None:
        issues.append(
            (
                "ERROR",
                "invalid_triggers",
                f"skill's plugin dir has no readable .claude-plugin/plugin.json: {plugin_dir}",
            )
        )
    names = tuple(n for n in (skill_dir.name, skill_md_name(skill_dir)) if n)
    eval_ids = [
        e.get("id")
        for e in evals.get("evals") or []
        if isinstance(e, dict) and e.get("id") is not None
    ]
    errors, peers = validate_triggers(
        evals["triggers"], eval_ids, marketplace_root, own_plugin, names
    )
    issues += [("ERROR", "invalid_triggers", e) for e in errors]
    if any(sev == "ERROR" for sev, _, _ in issues):
        emit("ERROR", [("SKILL_DIR", skill_dir), ("EVALS", evals_path)], issues)
        return 1

    trig = evals["triggers"]
    target = trig["skill"]
    max_turns = trig.get("max_turns")
    plugin_dirs: list[Path] = [plugin_dir.resolve()]
    for p in peers:
        if p not in plugin_dirs:
            plugin_dirs.append(p)

    prompts = [
        dict(item, kind="should_trigger", expected=True)
        for item in trig.get("should_trigger", [])
    ]
    prompts += [
        dict(item, kind="should_not_trigger", expected=False)
        for item in trig.get("should_not_trigger", [])
    ]
    if args.only:
        known = {p["id"] for p in prompts}
        unknown = [o for o in args.only if o not in known]
        if unknown:
            raise UsageError(
                f"--only id not in the triggers block: {', '.join(unknown)}"
            )
        prompts = [p for p in prompts if p["id"] in set(args.only)]

    rollout = Path(os.environ.get("EVAL_ROLLOUT_SCRIPT") or DEFAULT_ROLLOUT)
    planned_runs = len(prompts) * args.runs
    max_cost = round(planned_runs * cap, 6)
    affordable = int((args.total_budget_usd + EPS) // cap)

    common = [
        ("SKILL", target),
        ("SKILL_DIR", skill_dir),
        ("MODEL", args.model),
        ("PLUGIN_DIRS", ",".join(str(p) for p in plugin_dirs)),
        ("PROMPTS", len(prompts)),
        ("RUNS_PER_PROMPT", args.runs),
    ]

    # ------------------------------------------------------------- dry run
    if args.dry_run:
        if max_cost > args.total_budget_usd + EPS:
            issues.append(
                (
                    "WARN",
                    "plan_exceeds_budget",
                    f"worst case {fmt_num(max_cost)} USD ({planned_runs} runs x {fmt_num(cap)}) exceeds "
                    f"--total-budget-usd {fmt_num(args.total_budget_usd)}; a live run aborts after at most {affordable} runs",
                )
            )
        if not rollout.is_file():
            issues.append(
                ("WARN", "rollout_missing", f"rollout script not found: {rollout}")
            )
        plan = [
            f"  - ID={p['id']} EXPECTED={'trigger' if p['expected'] else 'no_trigger'}"
            + (f" NEAR_MISS_OF={p['near_miss_of']}" if p.get("near_miss_of") else "")
            for p in prompts
        ]
        status = "WARN" if issues else "OK"
        emit(
            status,
            [("MODE", "dry-run")]
            + common
            + [
                ("PLANNED_RUNS", planned_runs),
                ("MAX_COST_USD", fmt_num(max_cost)),
                ("TOTAL_BUDGET_USD", fmt_num(args.total_budget_usd)),
                ("MAX_TURNS", fmt_num(max_turns)),
                ("ROLLOUT_SCRIPT", rollout),
            ],
            issues,
            plan,
            "PLAN:",
        )
        return 0

    if not rollout.is_file():
        raise UsageError(f"rollout script not found: {rollout}")

    # ------------------------------------------------------------- live
    started = _dt.datetime.now(_dt.timezone.utc)
    stamp = started.strftime("%Y%m%dT%H%M%SZ")
    plugin_key = own_plugin or plugin_dir.name
    if args.output:
        output = Path(args.output).resolve()
        base = output.parent / (output.stem + "-runs")
    else:
        base = (
            runs_root_for(skill_dir) / plugin_key / skill_dir.name / "triggers" / stamp
        )
        output = base / "triggers.json"
    base.mkdir(parents=True, exist_ok=True)

    spent = 0.0
    aborted = False
    abort_reason = None
    model_id = None
    rows = []
    for p in prompts:
        row = {
            "id": p["id"],
            "kind": p["kind"],
            "expected": p["expected"],
            "prompt": p["prompt"],
            "prompt_sha256": hashlib.sha256(p["prompt"].encode("utf-8")).hexdigest(),
            "near_miss_of": p.get("near_miss_of"),
            "triggered": None,
            "trigger_rate": None,
            "runs_ok": 0,
            "runs_error": 0,
            "skills_invoked": [],
            "cost": 0.0,
            "cost_known": True,
            "status": "SKIPPED",
            "outcome": "skipped",
            "runs": [],
        }
        rows.append(row)
        if aborted:
            continue
        for n in range(1, args.runs + 1):
            if spent + cap > args.total_budget_usd + EPS:
                aborted = True
                abort_reason = (
                    f"budget: spent {fmt_num(spent)} USD; the next run's worst case {fmt_num(cap)} "
                    f"would exceed --total-budget-usd {fmt_num(args.total_budget_usd)}"
                )
                break
            rec = run_one(
                rollout,
                base / f"{p['id']}-run-{n}",
                p["prompt"],
                plugin_dirs,
                args.model,
                cap,
                max_turns,
                args.skill_listing_budget,
            )
            spent = round(spent + rec["cost_charged"], 6)
            invoked = rec.pop("_invoked", [])
            if rec["status"] == "OK":
                rec["triggered"] = any(
                    skill_matches(s.get("skill"), target) for s in invoked
                )
                model_id = model_id or rec.get("model_id")
            rec["run"] = n
            row["runs"].append(rec)
            if rec["status"] == "USAGE":
                aborted = True
                abort_reason = f"rollout usage error: {rec['reason']}"
                break
        ok_runs = [r for r in row["runs"] if r["status"] == "OK"]
        row["runs_ok"] = len(ok_runs)
        row["runs_error"] = sum(
            1 for r in row["runs"] if r["status"] in ("ERROR", "USAGE")
        )
        row["cost"] = round(float(sum(r["cost_charged"] for r in row["runs"])), 6)
        row["cost_known"] = all(r["cost_known"] for r in row["runs"])
        row["skills_invoked"] = sorted(
            {s for r in ok_runs for s in r["skills_invoked"]}
        )
        if not row["runs"]:
            continue  # aborted before this prompt's first run: SKIPPED
        if ok_runs:
            hits = sum(1 for r in ok_runs if r["triggered"])
            row["trigger_rate"] = round(hits / len(ok_runs), 4)
            row["triggered"] = row["trigger_rate"] >= 0.5
            row["status"] = "OK"
            row["outcome"] = {
                (True, True): "tp",
                (True, False): "fn",
                (False, True): "fp",
                (False, False): "tn",
            }[(row["expected"], row["triggered"])]
        else:
            row["status"] = "ERROR"
            row["outcome"] = "error"

    count = {
        k: sum(1 for r in rows if r["outcome"] == k)
        for k in ("tp", "fp", "fn", "tn", "error", "skipped")
    }
    attempted = len(rows) - count["skipped"]
    summary = {
        "tp": count["tp"],
        "fp": count["fp"],
        "fn": count["fn"],
        "tn": count["tn"],
        "errors": count["error"],
        "skipped": count["skipped"],
        "attempted": attempted,
        "recall": ratio(count["tp"], count["tp"] + count["fn"]),
        "precision": ratio(count["tp"], count["tp"] + count["fp"]),
        "fpr": ratio(count["fp"], count["fp"] + count["tn"]),
        "total_cost": round(spent, 6),
        "cost_includes_cap_charges": any(
            not r["cost_known"] for r in rows if r["runs"]
        ),
        "aborted": aborted,
        "abort_reason": abort_reason,
    }

    if aborted:
        issues.append(
            (
                "ERROR",
                "budget_abort"
                if abort_reason.startswith("budget")
                else "rollout_usage",
                abort_reason,
            )
        )
    if attempted and count["error"] / attempted > 0.5:
        issues.append(
            (
                "ERROR",
                "too_many_errors",
                f"{count['error']} of {attempted} prompts errored (>50%)",
            )
        )
    for r in rows:
        if r["status"] == "ERROR":
            last = next(
                (x["reason"] for x in reversed(r["runs"]) if x.get("reason")),
                "rollout error",
            )
            issues.append(("WARN", "prompt_error", f"{r['id']}: {last}"))
    if summary["recall"] is not None and summary["recall"] + EPS < args.min_recall:
        issues.append(
            (
                "WARN",
                "recall_below_threshold",
                f"recall {fmt_num(summary['recall'])} < --min-recall {fmt_num(args.min_recall)}",
            )
        )
    if count["fp"] > args.max_false_positives:
        fps = ",".join(r["id"] for r in rows if r["outcome"] == "fp")
        issues.append(
            (
                "WARN",
                "false_positives",
                f"{count['fp']} false positive(s) > --max-false-positives {args.max_false_positives}: {fps}",
            )
        )
    if (
        summary["recall"] is None
        and not aborted
        and any(p["expected"] for p in prompts)
    ):
        issues.append(
            (
                "WARN",
                "no_positive_results",
                "no should_trigger prompt produced a result; recall is undefined",
            )
        )

    issues.sort(key=lambda i: 0 if i[0] == "ERROR" else 1)
    status = (
        "ERROR"
        if any(i[0] == "ERROR" for i in issues)
        else ("WARN" if issues else "OK")
    )

    result = {
        "version": 1,
        "harness": "claude-code",
        "skill": target,
        "skill_dir": str(skill_dir),
        "model": args.model,
        "model_id": model_id,
        "runs_per_prompt": args.runs,
        "max_budget_usd_per_prompt": cap,
        "total_budget_usd": args.total_budget_usd,
        "max_turns": max_turns,
        "skill_listing_budget": args.skill_listing_budget,
        "thresholds": {
            "min_recall": args.min_recall,
            "max_false_positives": args.max_false_positives,
            "trigger_rate_min": 0.5,
        },
        "plugin_dirs": [str(p) for p in plugin_dirs],
        "started_at": started.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "finished_at": _dt.datetime.now(_dt.timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "runs_dir": str(base),
        "prompts": rows,
        "summary": summary,
        "status": status,
        "issues": [{"severity": s, "type": t, "msg": m} for s, t, m in issues],
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(result, indent=2) + "\n"
    output.write_text(payload, encoding="utf-8")
    copy: Path | None = None
    if not args.no_copy:
        copy = skill_dir / "eval-results" / "triggers.json"
        copy.parent.mkdir(parents=True, exist_ok=True)
        if copy.resolve() != output:
            copy.write_text(payload, encoding="utf-8")

    lines = [
        f"  - ID={r['id']} EXPECTED={'trigger' if r['expected'] else 'no_trigger'} "
        f"TRIGGERED={fmt_num(r['triggered'])} RATE={fmt_num(r['trigger_rate'])} "
        f"OUTCOME={r['outcome']} STATUS={r['status']}"
        for r in rows
    ]
    emit(
        status,
        [("MODE", "live")]
        + common
        + [
            ("MODEL_ID", model_id or ""),
            ("TP", summary["tp"]),
            ("FP", summary["fp"]),
            ("FN", summary["fn"]),
            ("TN", summary["tn"]),
            ("ERRORS", summary["errors"]),
            ("SKIPPED", summary["skipped"]),
            ("RECALL", fmt_num(summary["recall"])),
            ("PRECISION", fmt_num(summary["precision"])),
            ("FPR", fmt_num(summary["fpr"])),
            ("TOTAL_COST_USD", fmt_num(summary["total_cost"])),
            ("TOTAL_BUDGET_USD", fmt_num(args.total_budget_usd)),
            ("BUDGET_ABORTED", fmt_num(aborted)),
            ("OUTPUT", output),
            ("COPY", copy if copy is not None else "none"),
        ],
        issues,
        lines,
    )
    return 1 if status == "ERROR" else 0


if __name__ == "__main__":
    sys.exit(main())

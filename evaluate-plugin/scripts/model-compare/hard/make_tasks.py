#!/usr/bin/env python3
"""Build the hard (Phase 2b) synthetic task set.

Hand-authored sources live in src/<id>/:
    fixture/        files copied into the agent's fresh workdir
    oracle/         reference solution, overlaid on the fixture (full files)
    prompt.txt      agent instructions
    meta.json       {"id", "claims", "difficulty_notes"}
    check_body.py   hidden grader body (CHECK_HEAD below is prepended)
    gen.py          optional: generates extra fixture/oracle/check data
                    (b3 CI log, b6 oracle rewrite, b8 diff); run before copying.

Output:
    tasks/<id>/{fixture/,prompt.txt,check.py,meta.json}
    oracle/<id>/   overlay files
Graders are run as `python3 -I tasks/<id>/check.py <workdir>` and print one
JSON line {"score": 0..1, "detail": [failed case names]} last.
"""

import json
import runpy
import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC, TASKS, ORACLE = HERE / "src", HERE / "tasks", HERE / "oracle"

CHECK_HEAD = r'''
import json, sys, os, signal, importlib, traceback
sys.dont_write_bytecode = True
WD = os.path.abspath(sys.argv[1])
sys.path.insert(0, WD)
os.chdir(WD)
results = []          # (name, ok, weight)
_printed = []
_timeouts = []        # after 3 timed-out cases, remaining cases get 1 s each


class CaseTimeout(Exception):
    pass


def _on_alarm(*_):
    raise CaseTimeout()


signal.signal(signal.SIGALRM, _on_alarm)


def case(name, fn, timeout=10, weight=1.0):
    """Run one independent graded case; any exception or timeout = fail."""
    signal.alarm(1 if len(_timeouts) >= 3 else timeout)
    try:
        ok = bool(fn())
    except BaseException as e:  # noqa: BLE001 - grader must never crash
        ok = False
        name += f" ({type(e).__name__})"
        if isinstance(e, CaseTimeout):
            _timeouts.append(name)
    finally:
        signal.alarm(0)
    results.append((name, ok, weight))
    return ok


def load(modname):
    """Import a module from the workdir; None if missing or broken."""
    signal.alarm(20)
    try:
        return importlib.import_module(modname)
    except BaseException:  # noqa: BLE001
        return None
    finally:
        signal.alarm(0)


def read(path):
    try:
        with open(os.path.join(WD, path), encoding="utf-8") as fh:
            return fh.read()
    except Exception:
        return None


def done(score=None, extra=None):
    if _printed:
        return
    _printed.append(1)
    total = sum(w for _, _, w in results)
    if score is None:
        score = sum(w for _, ok, w in results if ok) / total if total else 0.0
    out = {"score": round(max(0.0, min(1.0, score)), 3),
           "detail": [n for n, ok, _ in results if not ok], "cases": len(results)}
    if extra:
        out.update(extra)
    sys.stdout.flush()
    print(json.dumps(out))


def _crash_hook(exc_type, exc, tb):
    results.append((f"GRADER-CRASH {exc_type.__name__}: {exc}", False, 1.0))
    done()


sys.excepthook = _crash_hook
'''


def build(tid: str) -> None:
    src = SRC / tid
    if (src / "gen.py").exists():
        runpy.run_path(str(src / "gen.py"), run_name="__main__")
    out = TASKS / tid
    shutil.rmtree(out, ignore_errors=True)
    shutil.copytree(
        src / "fixture", out / "fixture", ignore=shutil.ignore_patterns("__pycache__")
    )
    shutil.copy(src / "prompt.txt", out / "prompt.txt")
    meta = json.loads((src / "meta.json").read_text())
    assert meta["id"] == tid
    (out / "meta.json").write_text(json.dumps(meta, indent=1) + "\n")
    (out / "check.py").write_text(
        CHECK_HEAD + "\n" + (src / "check_body.py").read_text()
    )
    shutil.rmtree(ORACLE / tid, ignore_errors=True)
    shutil.copytree(
        src / "oracle", ORACLE / tid, ignore=shutil.ignore_patterns("__pycache__")
    )


if __name__ == "__main__":
    for d in sorted(SRC.iterdir()):
        if d.is_dir() and (d / "check_body.py").exists():
            build(d.name)
            print("built", d.name)

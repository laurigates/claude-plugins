#!/usr/bin/env python3
"""Deterministic grader for skill eval expectations.

Grades the machine-checkable expectations in an evals.json eval case against a
captured skill output, WITHOUT spending LLM judge tokens. Expectations whose
``check`` type is ``judge`` (or plain-string expectations, which default to
``judge``) are reported as DEFERRED so the LLM grader only ever runs on the
genuinely fuzzy assertions.

This is the core token-frugality lever of the cross-model evaluation framework:
on the git-commit eval set ~70% of expectations are regex/substring checks that
cost zero model tokens to grade.

Expectation forms accepted in evals.json (``expectations`` may mix both):

  "Commit message starts with feat("          # string -> check: judge

  {                                            # object -> typed check
    "assertion": "Commit message starts with feat(",
    "check": "regex",
    "pattern": "^feat\\(",
    "scope": "subject"
  }

Check types -- output (graded against --output, the transcript text):
  regex          pattern matches (re.search) within scope
  substring      value is present within scope
  substring_all  every entry in values[] is present within scope
  absent_regex   pattern does NOT match within scope
  judge          deferred to the LLM grader (default for bare strings)

Check types -- trace (graded against --trace, a trace.json v1 written by
parse_trace.py; harness-neutral, never the raw stream):
  skill_triggered  {skill, expect=true}  skills_invoked[] names the skill, by
                   full (plugin:skill) or bare (skill) name. A DENIED
                   invocation still counts as triggered -- routing chose it.
  tool_called      {tool, pattern?, flags?, min=1, max?}  count of
                   tool_calls[] named ``tool`` (denied calls included -- they
                   were attempted) whose input_summary or any string input
                   value matches ``pattern``
  command_ran      {pattern, flags?, min=1, max?}  count of bash_commands[]
                   matching ``pattern``; denied commands did not run and are
                   not counted. ``max: 0`` means "never ran".

Check types -- workspace (graded against --workspace, the rollout's snapshot
of the agent's working directory):
  file_exists        {path, expect=true}
  file_regex         {path, pattern, flags?}   a missing file is a FAIL
  file_absent_regex  {path, pattern, flags?}   a missing file is a PASS
  json_path          {path, query, equals|regex|exists}  ``query`` is dotted
                     keys plus ``[int]`` (``a.b[0].c``); exactly one
                     comparator. A missing file or invalid JSON is a FAIL.
  run_command        {command, expect_exit=0, stdout_regex?, flags?,
                     timeout=30}  runs ``bash -c command`` in a FRESH TEMP
                     COPY of the workspace (the snapshot is never mutated),
                     with a minimal env (no inherited secrets) and a timeout
                     capped at 120s that bounds copy plus run. Only runs with
                     --allow-exec; without it the check is harness-deferred.
                     The workspace is agent-written, so before the command
                     runs: special files (FIFO, socket, device) and a copy
                     over 256 MB apparent size FAIL the check ("workspace
                     error"); a symlink, .git gitfile, commondir or alternates
                     entry leaving the copy FAILs it ("path escape"); every
                     copied git dir's config is cut to format keys (no
                     filter/diff/fsmonitor drivers, no hooks), and git never
                     discovers a repo above the temp copy. The process group
                     is killed when the command returns. This is isolation of
                     the snapshot, the env and git config, not an OS sandbox:
                     the command itself is trusted (it comes from evals.json).

Workspace ``path`` values must be relative, and the resolved path -- symlinks
included -- must stay inside the workspace. A path that escapes is a FAIL.

Optional fields on a typed check:
  scope   full | subject | body   (default: full; output checks only)
  flags   any of "imsx"           (regex flags on every pattern-bearing check)

Harness-deferred (design decision D4): a trace or workspace check whose input
was not supplied (no --trace / --workspace; ``run_command`` without
--allow-exec) is reported as HARNESS_DEFERRED with evidence starting "requires
headless harness" (then "(no trace.json)", "(no workspace snapshot)" or "with
--allow-exec"). It is excluded from the deterministic totals, is NOT
judge-pending, and must never be handed to the LLM judge -- so a subagent-
harness run, which has no trace or workspace, never false-fails. A non-zero
HARNESS_DEFERRED count turns an otherwise-OK status into WARN, so a run that
graded nothing cannot read as a clean pass.

Malformed checks (unknown regex flag, invalid regex, bad json_path query,
missing or mistyped field) grade ``passed: false`` with evidence
``malformed check: ...`` instead of crashing the grader. Likewise an I/O
failure on the agent-written workspace grades ``passed: false`` with
``workspace error: ...``.

The output text is cut at the ``\\n\\n---\\n## Tool calls`` marker before any
output check runs: rollout_headless.sh appends that tool-call appendix to
transcript.md, and an output check must grade what the agent SAID, not the
commands it ran (those are the trace checks' job).

Case-level field (issue #2690):
  expected_outcome   comply | abstain   (default: comply)

An "abstain" case is an impossible-task control: its honest answer is that the
task cannot be done. Grading is unchanged -- its typed checks already encode
the abstention (an absent_regex fabrication detector fails an invented
deliverable, and the honest refusal passes it) -- but the value is reported so
the LLM grader applies the abstention rule to the deferred judge half. An
unknown value exits 2 rather than silently grading the case as comply.

Usage:
  grade_deterministic.py --evals <evals.json> --eval-id <id> \
    --output <file|-> [--trace trace.json] [--workspace DIR] [--allow-exec] \
    [--json] [--strict]

Output: structured KEY=value section by default; full JSON with --json.
Exit code: 0 normally; with --strict, 1 when a deterministic check fails;
2 on a usage error (unknown eval id or expected_outcome, a --trace that is not
a readable trace.json, a --workspace that is not a directory).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# rollout_headless.sh writes transcript.md as the final text followed by this
# appendix; output checks grade only the text before it.
TOOL_CALLS_MARKER = "\n\n---\n## Tool calls"

HARNESS_EVIDENCE = "requires headless harness"
EXEC_TIMEOUT_DEFAULT = 30
EXEC_TIMEOUT_CAP = 120
FILE_READ_CAP = 10 * 1024 * 1024
EVIDENCE_SNIPPET = 200
EXEC_PATH = "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"


class MalformedCheck(Exception):
    """The check object itself is invalid (authoring error)."""


class HarnessDeferred(Exception):
    """The check's input was not supplied for this run (D4)."""


class PathEscape(Exception):
    """A workspace path resolves outside the workspace."""


def _scope_text(text: str, scope: str) -> str:
    """Return the slice of ``text`` named by ``scope``.

    Everything from the tool-calls appendix marker on is dropped first, for
    every scope -- see the module docstring.
    """
    text = text.split(TOOL_CALLS_MARKER, 1)[0]
    if scope == "subject":
        for line in text.splitlines():
            if line.strip():
                return line
        return ""
    if scope == "body":
        parts = text.split("\n\n", 1)
        return parts[1] if len(parts) == 2 else ""
    return text


def _compile_flags(flags: str) -> int:
    table = {"i": re.IGNORECASE, "m": re.MULTILINE, "s": re.DOTALL, "x": re.VERBOSE}
    value = 0
    if flags is not None and not isinstance(flags, str):
        raise ValueError(f"flags must be a string, got {type(flags).__name__}")
    for ch in flags or "":
        if ch not in table:
            raise ValueError(f"unknown regex flag: {ch!r}")
        value |= table[ch]
    return value


def _regex(exp: dict, key: str = "pattern") -> re.Pattern:
    """Compile ``exp[key]`` with ``exp['flags']``; raises on a malformed check."""
    pattern = exp[key]
    if not isinstance(pattern, str):
        raise MalformedCheck(f"{key} must be a string")
    return re.compile(pattern, _compile_flags(exp.get("flags", "")))


def _snippet(text: str, cap: int = EVIDENCE_SNIPPET) -> str:
    text = " ".join(str(text).split())
    return text if len(text) <= cap else text[: cap - 3] + "..."


def _int_field(exp: dict, key: str, default):
    value = exp.get(key, default)
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise MalformedCheck(f"{key} must be a non-negative integer")
    return value


def _bool_field(exp: dict, key: str, default: bool) -> bool:
    value = exp.get(key, default)
    if not isinstance(value, bool):
        raise MalformedCheck(f"{key} must be a boolean")
    return value


def _count_bounds(exp: dict) -> tuple[int, int | None]:
    lo = _int_field(exp, "min", 1)
    hi = _int_field(exp, "max", None)
    if hi is not None and "min" not in exp and hi < lo:
        # ``max: 0`` alone means "never": the default min of 1 yields to it.
        lo = 0
    if hi is not None and lo > hi:
        raise MalformedCheck(f"min ({lo}) > max ({hi})")
    return lo, hi


def _within(count: int, lo: int, hi: int | None) -> bool:
    return count >= lo and (hi is None or count <= hi)


def _bounds_text(lo: int, hi: int | None) -> str:
    if hi is None:
        return f">={lo}"
    if lo == hi:
        return f"=={lo}"
    return f"{lo}..{hi}"


# --------------------------------------------------------------------------
# Grading context
# --------------------------------------------------------------------------


class Inputs:
    """What this run supplied: transcript text, trace, workspace, exec gate."""

    def __init__(
        self,
        output: str,
        trace: dict | None = None,
        workspace: Path | None = None,
        allow_exec: bool = False,
    ):
        self.output = output
        self.trace = trace
        self.workspace = workspace
        self.allow_exec = allow_exec

    def need_trace(self) -> dict:
        if self.trace is None:
            raise HarnessDeferred(f"{HARNESS_EVIDENCE} (no trace.json)")
        return self.trace

    def need_workspace(self) -> Path:
        if self.workspace is None:
            raise HarnessDeferred(f"{HARNESS_EVIDENCE} (no workspace snapshot)")
        return self.workspace


def _trace_list(trace: dict, key: str) -> list:
    value = trace.get(key)
    return [v for v in value if isinstance(v, dict)] if isinstance(value, list) else []


# --------------------------------------------------------------------------
# Output checks (unchanged semantics and evidence strings)
# --------------------------------------------------------------------------


def _check_regex(exp: dict, ctx: Inputs):
    scope = exp.get("scope", "full")
    text = _scope_text(ctx.output, scope)
    ok = _regex(exp).search(text) is not None
    return ok, f"/{exp['pattern']}/ {'matched' if ok else 'no match'} in {scope}"


def _check_absent_regex(exp: dict, ctx: Inputs):
    scope = exp.get("scope", "full")
    text = _scope_text(ctx.output, scope)
    ok = _regex(exp).search(text) is None
    return (
        ok,
        f"/{exp['pattern']}/ {'absent (ok)' if ok else 'present (fail)'} in {scope}",
    )


def _check_substring(exp: dict, ctx: Inputs):
    scope = exp.get("scope", "full")
    text = _scope_text(ctx.output, scope)
    if not isinstance(exp["value"], str):
        raise MalformedCheck("value must be a string")
    ok = exp["value"] in text
    return ok, f"{exp['value']!r} {'found' if ok else 'missing'} in {scope}"


def _check_substring_all(exp: dict, ctx: Inputs):
    scope = exp.get("scope", "full")
    text = _scope_text(ctx.output, scope)
    values = exp["values"]
    if not isinstance(values, list) or not all(isinstance(v, str) for v in values):
        raise MalformedCheck("values must be a list of strings")
    missing = [v for v in values if v not in text]
    ok = not missing
    return ok, "all present" if ok else f"missing {missing!r} in {scope}"


# --------------------------------------------------------------------------
# Trace checks
# --------------------------------------------------------------------------


def _bare_skill(name: str) -> str:
    name = name.lstrip("/")
    return name.rsplit(":", 1)[-1]


def _skill_matches(invoked, wanted: str) -> bool:
    if not isinstance(invoked, str) or not invoked:
        return False
    inv = invoked.lstrip("/")
    want = wanted.lstrip("/")
    if inv == want:
        return True
    if ":" in want:
        # A qualified expectation matches a bare invocation of the same skill,
        # but never another plugin's skill that shares the bare name.
        return ":" not in inv and inv == _bare_skill(want)
    return _bare_skill(inv) == want


def _check_skill_triggered(exp: dict, ctx: Inputs):
    wanted = exp["skill"]
    if not isinstance(wanted, str) or not wanted.strip("/"):
        raise MalformedCheck("skill must be a non-empty string")
    expect = _bool_field(exp, "expect", True)
    trace = ctx.need_trace()
    hits = [
        s
        for s in _trace_list(trace, "skills_invoked")
        if _skill_matches(s.get("skill"), wanted)
    ]
    triggered = bool(hits)
    denied = sum(1 for s in hits if s.get("denied"))
    seen = sorted({str(s.get("skill")) for s in _trace_list(trace, "skills_invoked")})
    detail = f"{wanted!r} {'triggered' if triggered else 'not triggered'}"
    if denied:
        detail += f" ({denied} denied, counted as triggered)"
    detail += f"; expect={'true' if expect else 'false'}; invoked={seen!r}"
    return triggered == expect, detail


def _tool_input_strings(value) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        return [s for v in value.values() for s in _tool_input_strings(v)]
    if isinstance(value, list):
        return [s for v in value for s in _tool_input_strings(v)]
    return []


def _check_tool_called(exp: dict, ctx: Inputs):
    tool = exp["tool"]
    if not isinstance(tool, str) or not tool:
        raise MalformedCheck("tool must be a non-empty string")
    rx = _regex(exp) if "pattern" in exp else None
    lo, hi = _count_bounds(exp)
    trace = ctx.need_trace()
    count = 0
    for call in _trace_list(trace, "tool_calls"):
        if call.get("name") != tool:
            continue
        if rx is not None:
            texts = [call.get("input_summary") or ""] + _tool_input_strings(
                call.get("input")
            )
            if not any(isinstance(t, str) and rx.search(t) for t in texts):
                continue
        count += 1
    what = tool + (f" /{exp['pattern']}/" if rx is not None else "")
    ok = _within(count, lo, hi)
    return ok, f"{what} called {count}x (want {_bounds_text(lo, hi)})"


def _check_command_ran(exp: dict, ctx: Inputs):
    rx = _regex(exp)
    lo, hi = _count_bounds(exp)
    trace = ctx.need_trace()
    matched = [
        c.get("command")
        for c in _trace_list(trace, "bash_commands")
        if not c.get("denied")
        and isinstance(c.get("command"), str)
        and rx.search(c["command"])
    ]
    ok = _within(len(matched), lo, hi)
    evidence = f"/{exp['pattern']}/ ran {len(matched)}x (want {_bounds_text(lo, hi)})"
    if matched:
        evidence += f"; first: {_snippet(matched[0], 120)!r}"
    return ok, evidence


# --------------------------------------------------------------------------
# Workspace checks
# --------------------------------------------------------------------------


def _path_field(exp: dict) -> str:
    rel = exp["path"]
    if not isinstance(rel, str) or not rel:
        raise MalformedCheck("path must be a non-empty string")
    return rel


def _resolve_in_workspace(ws: Path, rel: str) -> Path:
    """Resolve ``rel`` under ``ws``; raise PathEscape if it leaves it.

    ``Path.resolve`` follows every symlink on the way, so a link inside the
    workspace that points outside it is an escape too.
    """
    if Path(rel).is_absolute():
        raise PathEscape(f"absolute path {rel!r} is not allowed")
    root = ws.resolve()
    try:
        target = (root / rel).resolve()
    except (OSError, RuntimeError) as err:  # symlink loop
        raise PathEscape(f"{rel!r} does not resolve: {err}") from err
    if target != root and root not in target.parents:
        raise PathEscape(f"{rel!r} resolves outside the workspace")
    return target


def _read_file(target: Path) -> str | None:
    if not target.is_file():
        return None
    with open(target, "rb") as fh:
        data = fh.read(FILE_READ_CAP)
    return data.decode("utf-8", errors="replace")


def _check_file_exists(exp: dict, ctx: Inputs):
    rel = _path_field(exp)
    expect = _bool_field(exp, "expect", True)
    ws = ctx.need_workspace()
    target = _resolve_in_workspace(ws, rel)
    exists = target.exists()
    return exists == expect, (
        f"{rel!r} {'exists' if exists else 'missing'}; expect={'true' if expect else 'false'}"
    )


def _check_file_regex(exp: dict, ctx: Inputs):
    rel = _path_field(exp)
    rx = _regex(exp)
    ws = ctx.need_workspace()
    text = _read_file(_resolve_in_workspace(ws, rel))
    if text is None:
        return False, f"{rel!r} missing (fail)"
    ok = rx.search(text) is not None
    return ok, f"/{exp['pattern']}/ {'matched' if ok else 'no match'} in {rel!r}"


def _check_file_absent_regex(exp: dict, ctx: Inputs):
    rel = _path_field(exp)
    rx = _regex(exp)
    ws = ctx.need_workspace()
    text = _read_file(_resolve_in_workspace(ws, rel))
    if text is None:
        return True, f"{rel!r} missing (ok)"
    ok = rx.search(text) is None
    return (
        ok,
        f"/{exp['pattern']}/ {'absent (ok)' if ok else 'present (fail)'} in {rel!r}",
    )


_QUERY_KEY = re.compile(r"[^.\[\]]+")
_QUERY_INDEX = re.compile(r"\[(\d+)\]")
_MISSING = object()


def _parse_query(query) -> list:
    """Parse ``a.b[0].c`` into ``['a', 'b', 0, 'c']``; raise on bad syntax."""
    if not isinstance(query, str) or not query:
        raise MalformedCheck("query must be a non-empty string")
    tokens: list = []
    pos = 0
    while pos < len(query):
        m = _QUERY_INDEX.match(query, pos)
        if m:
            tokens.append(int(m.group(1)))
            pos = m.end()
            continue
        if query[pos] == ".":
            if not tokens:
                raise MalformedCheck(f"bad query {query!r}: leading '.'")
            pos += 1
        elif tokens:
            raise MalformedCheck(f"bad query {query!r} at offset {pos}")
        m = _QUERY_KEY.match(query, pos)
        if not m:
            raise MalformedCheck(f"bad query {query!r} at offset {pos}")
        tokens.append(m.group(0))
        pos = m.end()
    return tokens


def _walk(doc, tokens: list):
    cur = doc
    for tok in tokens:
        if isinstance(tok, int):
            if not isinstance(cur, list) or tok >= len(cur):
                return _MISSING
            cur = cur[tok]
        else:
            if not isinstance(cur, dict) or tok not in cur:
                return _MISSING
            cur = cur[tok]
    return cur


def _canon(value) -> str:
    return json.dumps(value, sort_keys=True)


def _check_json_path(exp: dict, ctx: Inputs):
    rel = _path_field(exp)
    query = exp["query"]
    tokens = _parse_query(query)
    comparators = [k for k in ("equals", "regex", "exists") if k in exp]
    if len(comparators) != 1:
        raise MalformedCheck(
            f"json_path needs exactly one of equals|regex|exists, got {comparators or 'none'}"
        )
    comp = comparators[0]
    rx = None
    if comp == "regex":
        rx = _regex(exp, "regex")
    elif comp == "exists" and not isinstance(exp["exists"], bool):
        raise MalformedCheck("exists must be a boolean")
    ws = ctx.need_workspace()
    text = _read_file(_resolve_in_workspace(ws, rel))
    if text is None:
        return False, f"{rel!r} missing (fail)"
    try:
        doc = json.loads(text)
    except json.JSONDecodeError as err:
        return False, f"{rel!r} is not valid JSON: {err.msg} (fail)"
    value = _walk(doc, tokens)
    where = f"{rel!r}:{query}"
    if comp == "exists":
        present = value is not _MISSING
        return present == exp["exists"], (
            f"{where} {'present' if present else 'absent'}; "
            f"exists={'true' if exp['exists'] else 'false'}"
        )
    if value is _MISSING:
        return False, f"{where} absent (fail)"
    if comp == "equals":
        ok = _canon(value) == _canon(exp["equals"])
        return (
            ok,
            f"{where} = {_snippet(_canon(value), 80)} {'==' if ok else '!='} {_snippet(_canon(exp['equals']), 80)}",
        )
    subject = value if isinstance(value, str) else _canon(value)
    ok = rx.search(subject) is not None
    return ok, f"{where} /{exp['regex']}/ {'matched' if ok else 'no match'}"


class WorkspaceUnsafe(Exception):
    """The workspace cannot be copied safely for run_command (special file,
    over the size cap, ...). Grades FAIL, never crashes the grader."""


# Apparent-size cap on what run_command copies. The rollout snapshot is capped
# at --snapshot-max-mb (default 50); this is the grader's own bound, measured by
# st_size so a sparse file cannot slip past a block-count measure.
EXEC_COPY_CAP = 256 * 1024 * 1024

# Repo-config keys kept when a copied .git/config is rewritten: format
# plumbing only. Everything else -- filter/diff/merge drivers, core.fsmonitor,
# core.hooksPath, core.worktree, core.sshCommand, include.path, aliases -- was
# written by the agent under test and is dropped.
_SAFE_GIT_KEYS = {
    "core": {
        "repositoryformatversion",
        "bare",
        "filemode",
        "ignorecase",
        "precomposeunicode",
        "symlinks",
        "logallrefupdates",
    },
    "extensions": None,  # every extensions.* key (objectformat, refstorage, ...)
}
_SAFE_GIT_VALUE = re.compile(r"^[A-Za-z0-9._-]+$")


def _exec_env(home: Path, tmp: Path, ceiling: Path) -> dict:
    """A minimal environment: nothing from the grader's own env leaks in."""
    return {
        "PATH": EXEC_PATH,
        "HOME": str(home),
        "TMPDIR": str(tmp),
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_PAGER": "cat",
        "PAGER": "cat",
        # Repo discovery never climbs out of the temp base into a parent repo.
        "GIT_CEILING_DIRECTORIES": str(ceiling),
        # Belt and braces on top of _sanitize_git_dirs: command-line-scope
        # overrides (git >= 2.31) beat any repo config that survived.
        "GIT_CONFIG_COUNT": "2",
        "GIT_CONFIG_KEY_0": "core.fsmonitor",
        "GIT_CONFIG_VALUE_0": "false",
        "GIT_CONFIG_KEY_1": "core.hooksPath",
        "GIT_CONFIG_VALUE_1": os.devnull,
    }


def _preflight_workspace(ws: Path) -> None:
    """Refuse a workspace run_command cannot copy safely, BEFORE copying.

    Only directories, regular files and symlinks are copied. A FIFO or socket
    makes copytree raise, and a device node (``mknod z c 1 5`` is /dev/zero)
    is read forever; both are refused. Regular files are summed by apparent
    size (st_size), so a sparse file cannot materialise past the cap.
    """
    total = 0
    for dirpath, dirnames, filenames in os.walk(ws, followlinks=False):
        for name in dirnames + filenames:
            full = os.path.join(dirpath, name)
            st = os.lstat(full)
            mode = st.st_mode
            if stat.S_ISLNK(mode) or stat.S_ISDIR(mode):
                continue
            if not stat.S_ISREG(mode):
                rel = os.path.relpath(full, ws)
                raise WorkspaceUnsafe(
                    f"{rel!r} is not a regular file, directory or symlink"
                )
            total += st.st_size
            if total > EXEC_COPY_CAP:
                raise WorkspaceUnsafe(
                    f"workspace exceeds {EXEC_COPY_CAP // (1024 * 1024)} MB (apparent size)"
                )


def _inside(root: Path, target: Path) -> bool:
    return target == root or root in target.parents


def _check_links(work: Path) -> list[Path]:
    """Raise PathEscape if any symlink or git pointer leaves ``work``.

    Returns the git directories found in the copy. A ``.git`` gitfile, a
    ``commondir`` file or an ``objects/info/alternates`` entry that points
    outside the copy would make git read (and refresh-write) another
    repository -- a falsified grade and a write outside the copy.
    """
    root = work.resolve()
    git_dirs: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(work, followlinks=False):
        here = Path(dirpath)
        for name in dirnames + filenames:
            full = here / name
            if full.is_symlink():
                try:
                    target = full.resolve()
                except (OSError, RuntimeError) as err:
                    raise PathEscape(
                        f"symlink {name!r} does not resolve: {err}"
                    ) from err
                if not _inside(root, target):
                    rel = os.path.relpath(full, work)
                    raise PathEscape(f"symlink {rel!r} resolves outside the workspace")
        if (
            (here / "HEAD").is_file()
            and (here / "config").is_file()
            and ((here / "objects").is_dir() or (here / "commondir").is_file())
        ):
            git_dirs.append(here)
        gitfile = here / ".git"
        if gitfile.is_file() and not gitfile.is_symlink():
            first = gitfile.read_text(errors="replace").splitlines()[:1]
            line = first[0].strip() if first else ""
            if line.startswith("gitdir:"):
                target = (here / line[len("gitdir:") :].strip()).resolve()
                if not _inside(root, target):
                    rel = os.path.relpath(gitfile, work)
                    raise PathEscape(f"gitfile {rel!r} points outside the workspace")
    for gd in git_dirs:
        pointers = []
        commondir = gd / "commondir"
        if commondir.is_file():
            pointers.append((commondir, gd))
        alternates = gd / "objects" / "info" / "alternates"
        if alternates.is_file():
            pointers.append((alternates, gd / "objects"))
        for pfile, base in pointers:
            for raw in pfile.read_text(errors="replace").splitlines():
                raw = raw.strip()
                if not raw or raw.startswith("#"):
                    continue
                if not _inside(root, (base / raw).resolve()):
                    rel = os.path.relpath(pfile, work)
                    raise PathEscape(f"{rel!r} points outside the workspace")
    return git_dirs


def _safe_git_config(text: str) -> str:
    """Keep only format-plumbing keys from a git config (see _SAFE_GIT_KEYS)."""
    kept: dict[str, list[tuple[str, str]]] = {}
    section = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line[0] in "#;":
            continue
        m = re.match(r'^\[\s*([A-Za-z0-9.-]+)\s*(?:"[^"]*")?\s*\]', line)
        if m:
            name = m.group(1).lower()
            # A subsection ([filter "x"], [remote "o"]) or dotted name is never safe.
            section = name if ('"' not in line and "." not in name) else None
            continue
        if section not in _SAFE_GIT_KEYS:
            continue
        key, _, value = line.partition("=")
        key = key.strip().lower()
        value = re.split(r"\s[#;]", value.strip(), maxsplit=1)[0].strip().strip('"')
        allowed = _SAFE_GIT_KEYS[section]
        if allowed is not None and key not in allowed:
            continue
        if not _SAFE_GIT_VALUE.match(key) or not _SAFE_GIT_VALUE.match(value or "true"):
            continue
        kept.setdefault(section, []).append((key, value or "true"))
    out = []
    for section, pairs in kept.items():
        out.append(f"[{section}]")
        out.extend(f"\t{k} = {v}" for k, v in pairs)
    return "\n".join(out) + "\n"


def _sanitize_git_dirs(git_dirs: list[Path]) -> None:
    """Strip agent-controlled executable config from every copied git dir.

    The snapshot's git config was written by the agent under test: a
    ``filter.<x>.clean`` driver plus a ``.gitattributes`` line runs an
    arbitrary command on ``git status`` (the copy's fresh stat data forces a
    re-hash). The rewritten config keeps only format keys, so an attribute
    naming an undefined driver is inert; hooks, info/attributes and per-worktree
    config are removed outright.
    """
    for gd in git_dirs:
        config = gd / "config"
        if config.is_file() and not config.is_symlink():
            config.write_text(_safe_git_config(config.read_text(errors="replace")))
        for extra in (gd / "config.worktree", gd / "info" / "attributes"):
            if extra.is_file() or extra.is_symlink():
                extra.unlink()
        hooks = gd / "hooks"
        if hooks.is_symlink():
            hooks.unlink()
        elif hooks.is_dir():
            shutil.rmtree(hooks)
        worktrees = gd / "worktrees"
        if worktrees.is_dir() and not worktrees.is_symlink():
            for wt_cfg in worktrees.glob("*/config.worktree"):
                wt_cfg.unlink()


def _run_isolated(
    command: str, ws: Path, timeout: float
) -> tuple[int | None, str, str]:
    """Run ``command`` in a fresh temp copy of ``ws``. Returns (rc|None, out, err).

    ``rc`` is None on timeout. Before anything runs: the workspace is
    preflighted (regular files, dirs and symlinks only; apparent-size cap), the
    copy keeps symlinks as links and refuses any that leave it, git pointers
    (gitfile, commondir, alternates) must stay inside it, and every copied git
    dir's agent-written config is reduced to format keys. ``timeout`` bounds
    copy plus run. The process group is killed once the command returns or
    times out, so a backgrounded grandchild cannot outlive the check.
    """
    started = time.monotonic()
    _preflight_workspace(ws)
    base = Path(tempfile.mkdtemp(prefix="grade-exec-"))
    try:
        work = base / "ws"
        home = base / "home"
        tmp = base / "tmp"
        shutil.copytree(ws, work, symlinks=True)
        _sanitize_git_dirs(_check_links(work))
        home.mkdir()
        tmp.mkdir()
        remaining = timeout - (time.monotonic() - started)
        if remaining <= 0:
            return None, "", ""
        shell = shutil.which("bash", path=EXEC_PATH) or "/bin/sh"
        proc = subprocess.Popen(
            [shell, "-c", command],
            cwd=work,
            env=_exec_env(home, tmp, base),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        rc: int | None
        try:
            out, err = proc.communicate(timeout=remaining)
            rc = proc.returncode
        except subprocess.TimeoutExpired:
            _kill_group(proc)
            try:
                out, err = proc.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                out, err = b"", b""
            rc = None
        # A grandchild that detached its stdio (``(cmd >/dev/null 2>&1 &)``)
        # lets communicate() return at once; kill the group either way.
        _kill_group(proc)
        return (
            rc,
            out.decode("utf-8", errors="replace"),
            err.decode("utf-8", errors="replace"),
        )
    finally:
        shutil.rmtree(base, ignore_errors=True)


def _kill_group(proc: subprocess.Popen) -> None:
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        try:
            proc.kill()
        except ProcessLookupError:
            pass


def _check_run_command(exp: dict, ctx: Inputs):
    command = exp["command"]
    if not isinstance(command, str) or not command.strip():
        raise MalformedCheck("command must be a non-empty string")
    expect_exit = exp.get("expect_exit", 0)
    if isinstance(expect_exit, bool) or not isinstance(expect_exit, int):
        raise MalformedCheck("expect_exit must be an integer")
    rx = _regex(exp, "stdout_regex") if "stdout_regex" in exp else None
    timeout = exp.get("timeout", EXEC_TIMEOUT_DEFAULT)
    if (
        isinstance(timeout, bool)
        or not isinstance(timeout, (int, float))
        or timeout <= 0
    ):
        raise MalformedCheck("timeout must be a positive number")
    timeout = min(timeout, EXEC_TIMEOUT_CAP)
    ws = ctx.need_workspace()
    if not ctx.allow_exec:
        raise HarnessDeferred(f"{HARNESS_EVIDENCE} with --allow-exec")
    rc, out, err = _run_isolated(command, ws, timeout)
    if rc is None:
        return False, f"`{_snippet(command, 80)}` timed out after {timeout:g}s (fail)"
    ok = rc == expect_exit
    evidence = f"`{_snippet(command, 80)}` exit={rc} (want {expect_exit})"
    if rx is not None:
        matched = rx.search(out) is not None
        ok = ok and matched
        evidence += (
            f"; stdout /{exp['stdout_regex']}/ {'matched' if matched else 'no match'}"
        )
    if not ok:
        shown = out if out.strip() else err
        evidence += f"; output: {_snippet(shown)!r}"
    return ok, evidence


# --------------------------------------------------------------------------
# Dispatch
# --------------------------------------------------------------------------

# name -> (grading function, input it needs). ``judge`` is not here: it is
# deferred before dispatch, and an unknown name falls through to the judge.
CHECKS = {
    "regex": (_check_regex, "output"),
    "absent_regex": (_check_absent_regex, "output"),
    "substring": (_check_substring, "output"),
    "substring_all": (_check_substring_all, "output"),
    "skill_triggered": (_check_skill_triggered, "trace"),
    "tool_called": (_check_tool_called, "trace"),
    "command_ran": (_check_command_ran, "trace"),
    "file_exists": (_check_file_exists, "workspace"),
    "file_regex": (_check_file_regex, "workspace"),
    "file_absent_regex": (_check_file_absent_regex, "workspace"),
    "json_path": (_check_json_path, "workspace"),
    "run_command": (_check_run_command, "workspace"),
}


def grade_expectation(exp, output, inputs: Inputs | None = None) -> dict:
    """Grade one expectation. Returns a result dict with a ``deferred`` flag.

    ``output`` is the transcript text; ``inputs`` carries the optional trace /
    workspace / exec gate (absent -> trace and workspace checks are
    harness-deferred).
    """
    if inputs is None:
        inputs = Inputs(output)

    # Bare string -> deferred to the LLM judge.
    if isinstance(exp, str):
        return {"assertion": exp, "check": "judge", "deferred": True}
    if not isinstance(exp, dict):
        return {
            "assertion": str(exp),
            "check": "?",
            "passed": False,
            "deferred": False,
            "evidence": f"malformed check: expectation must be a string or object, got {type(exp).__name__}",
        }

    assertion = exp.get("assertion", "")
    check = exp.get("check", "judge")

    if check == "judge":
        return {"assertion": assertion, "check": "judge", "deferred": True}

    entry = CHECKS.get(check) if isinstance(check, str) else None
    if entry is None:
        return {
            "assertion": assertion,
            "check": check,
            "deferred": True,
            "evidence": f"unknown check type {check!r} -> deferred",
        }
    fn, _needs = entry

    try:
        ok, evidence = fn(exp, inputs)
    except HarnessDeferred as why:
        return {
            "assertion": assertion,
            "check": check,
            "deferred": True,
            "harness_deferred": True,
            "evidence": str(why),
        }
    except PathEscape as why:
        ok, evidence = False, f"path escape: {why} (fail)"
    except WorkspaceUnsafe as why:
        ok, evidence = False, f"workspace error: {why} (fail)"
    except KeyError as err:
        return _malformed(assertion, check, f"missing field {err}")
    # Regression fix: an unknown regex flag used to raise an uncaught
    # ValueError out of _compile_flags and crash the whole grading run with a
    # traceback (no KEY=value block, no JSON). Every malformed check now grades
    # passed:false with "malformed check: ..." evidence instead.
    except (ValueError, re.error, TypeError, MalformedCheck) as err:
        return _malformed(assertion, check, str(err))
    # The workspace is agent-controlled data: an I/O failure reading or copying
    # it (shutil.Error is an OSError) grades this check FAIL instead of
    # crashing the whole run and losing every other result.
    except OSError as err:
        ok, evidence = False, f"workspace error: {_snippet(err)} (fail)"

    return {
        "assertion": assertion,
        "check": check,
        "passed": ok,
        "deferred": False,
        "evidence": evidence,
    }


def _malformed(assertion: str, check: str, detail: str) -> dict:
    return {
        "assertion": assertion,
        "check": check,
        "passed": False,
        "deferred": False,
        "evidence": f"malformed check: {detail}",
    }


EXPECTED_OUTCOMES = ("comply", "abstain")


def expected_outcome_of(eval_case: dict) -> str:
    """Return the case's expected outcome, defaulting to comply."""
    return eval_case.get("expected_outcome", "comply")


def grade_eval_case(
    eval_case: dict,
    output: str,
    inputs: Inputs | None = None,
    input_paths: dict | None = None,
) -> dict:
    if inputs is None:
        inputs = Inputs(output)
    results = [
        grade_expectation(e, output, inputs) for e in eval_case.get("expectations", [])
    ]
    harness = [r for r in results if r.get("harness_deferred")]
    deterministic = [r for r in results if not r.get("deferred")]
    deferred = [
        r for r in results if r.get("deferred") and not r.get("harness_deferred")
    ]
    passed = sum(1 for r in deterministic if r.get("passed"))
    failed = len(deterministic) - passed
    paths = input_paths or {}
    return {
        "eval_id": eval_case.get("id", ""),
        "expected_outcome": expected_outcome_of(eval_case),
        "deterministic": deterministic,
        "deferred": deferred,
        "harness_deferred": harness,
        "summary": {
            "deterministic_total": len(deterministic),
            "deterministic_passed": passed,
            "deterministic_failed": failed,
            "judge_pending": len(deferred),
            "harness_deferred": len(harness),
        },
        "inputs": {
            "trace": paths.get("trace"),
            "workspace": paths.get("workspace"),
            "allow_exec": bool(inputs.allow_exec),
        },
    }


def render_structured(graded: dict) -> tuple[str, int]:
    """Render the KEY=value section. Returns (text, exit_status_severity)."""
    s = graded["summary"]
    harness_n = s.get("harness_deferred", 0)
    if s["deterministic_failed"] > 0:
        status, severity = "ERROR", 1
    elif s["judge_pending"] > 0 or harness_n > 0:
        status, severity = "WARN", 0
    else:
        status, severity = "OK", 0

    lines = ["=== DETERMINISTIC GRADING ==="]
    lines.append(f"EVAL_ID={graded['eval_id']}")
    lines.append(f"EXPECTED_OUTCOME={graded['expected_outcome']}")
    lines.append(f"DETERMINISTIC_TOTAL={s['deterministic_total']}")
    lines.append(f"DETERMINISTIC_PASSED={s['deterministic_passed']}")
    lines.append(f"DETERMINISTIC_FAILED={s['deterministic_failed']}")
    lines.append(f"JUDGE_PENDING={s['judge_pending']}")
    lines.append(f"HARNESS_DEFERRED={harness_n}")
    lines.append(f"STATUS={status}")
    lines.append(f"ISSUE_COUNT={s['deterministic_failed']}")
    lines.append("RESULTS:")
    for r in graded["deterministic"]:
        verdict = "PASS" if r.get("passed") else "FAIL"
        lines.append(
            f"  - CHECK={r['check']} RESULT={verdict} ASSERTION={r['assertion']!r}"
        )
    for r in graded["deferred"]:
        lines.append(
            f"  - CHECK={r['check']} RESULT=DEFERRED ASSERTION={r['assertion']!r}"
        )
    for r in graded.get("harness_deferred", []):
        lines.append(
            f"  - CHECK={r['check']} RESULT=HARNESS_DEFERRED ASSERTION={r['assertion']!r}"
        )
    lines.append("=== END DETERMINISTIC GRADING ===")
    return "\n".join(lines), severity


def _load_trace(path: str) -> dict:
    """Load a trace.json v1; raise ValueError with a usage message otherwise."""
    p = Path(path)
    if not p.is_file():
        raise ValueError(f"--trace {path!r} is not a file")
    try:
        trace = json.loads(p.read_text())
    except (OSError, json.JSONDecodeError) as err:
        raise ValueError(f"--trace {path!r} is not readable JSON: {err}") from err
    if not isinstance(trace, dict):
        raise ValueError(f"--trace {path!r} is not a JSON object")
    if trace.get("version") != 1:
        raise ValueError(
            f"--trace {path!r} has version {trace.get('version')!r}; expected 1"
        )
    return trace


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Deterministic skill-eval grader")
    parser.add_argument("--evals", required=True, help="Path to evals.json")
    parser.add_argument("--eval-id", required=True, help="Eval case id to grade")
    parser.add_argument(
        "--output", required=True, help="Skill output file, or - for stdin"
    )
    parser.add_argument(
        "--trace", help="trace.json (v1, from parse_trace.py) for trace checks"
    )
    parser.add_argument(
        "--workspace", help="Workspace snapshot directory for workspace checks"
    )
    parser.add_argument(
        "--allow-exec",
        action="store_true",
        help="Permit run_command checks (run in a temp copy of --workspace)",
    )
    parser.add_argument(
        "--json", action="store_true", help="Emit JSON instead of KEY=value"
    )
    parser.add_argument(
        "--strict", action="store_true", help="Exit 1 when a deterministic check fails"
    )
    args = parser.parse_args(argv)

    evals = json.loads(Path(args.evals).read_text())
    eval_case = next(
        (e for e in evals.get("evals", []) if e.get("id") == args.eval_id), None
    )
    if eval_case is None:
        print(
            f"ERROR: eval id {args.eval_id!r} not found in {args.evals}",
            file=sys.stderr,
        )
        return 2

    outcome = expected_outcome_of(eval_case)
    if outcome not in EXPECTED_OUTCOMES:
        print(
            f"ERROR: eval {args.eval_id!r} has expected_outcome {outcome!r}; "
            f"expected one of {', '.join(EXPECTED_OUTCOMES)}",
            file=sys.stderr,
        )
        return 2

    trace = None
    if args.trace:
        try:
            trace = _load_trace(args.trace)
        except ValueError as err:
            print(f"ERROR: {err}", file=sys.stderr)
            return 2
    workspace = None
    if args.workspace:
        workspace = Path(args.workspace)
        if not workspace.is_dir():
            print(
                f"ERROR: --workspace {args.workspace!r} is not a directory",
                file=sys.stderr,
            )
            return 2

    output = sys.stdin.read() if args.output == "-" else Path(args.output).read_text()
    inputs = Inputs(
        output, trace=trace, workspace=workspace, allow_exec=args.allow_exec
    )
    graded = grade_eval_case(
        eval_case,
        output,
        inputs,
        {"trace": args.trace, "workspace": args.workspace},
    )

    if args.json:
        print(json.dumps(graded, indent=2))
        severity = 1 if graded["summary"]["deterministic_failed"] > 0 else 0
    else:
        text, severity = render_structured(graded)
        print(text)

    return severity if args.strict else 0


if __name__ == "__main__":
    sys.exit(main())

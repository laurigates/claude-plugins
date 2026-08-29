"""probe — the finding / waiver / delta contract shared by drift probes.

This module holds the parts of a probe that OTHER probes must agree with, and
nothing else. The similarity computation, the thresholds, the corpus walk and
the seven `check_*` functions stay in `config-drift.py`: they are one probe's
opinion, and a second probe adopting them would be adopting a bug, not a
contract.

What is contract, and why:

* `sha` — sha256 truncated to 16 hex chars. The truncation LENGTH is the
  contract. A waiver records both sides' content hashes and a baseline record
  is keyed by a fingerprint built from the same helper, so two probes
  truncating differently cannot share a waiver file or a baseline.
* `Finding` — one shape for a reported problem, dict-compatible so existing
  consumers keep reading `f["kind"]` / `f.get("paths")` unchanged. Key order in
  `to_dict()` comes from the `**extra` kwargs order, so a call site reproduces
  its own dict literal by construction rather than against a hand-maintained
  canonical key list.
* `fingerprint` — identity of a finding ACROSS runs, so a delta report can say
  "this one is new" without diffing prose. It deliberately folds a singular
  `path` into the path set (see the function).
* `Waivers` — the two-orientation lookup. A waiver file is hand-written, so
  either side may be spelled first; a probe that only tried one orientation
  would silently ignore half the file.
* `Baseline` / `Delta` — remembering what was already reported.
* `render_status` / `render_json` / `exit_code` — the output contract an
  orchestrating skill greps. `render_status` emits the shape
  `.claude/rules/structured-script-output.md` mandates: `=== SECTION ===` /
  `=== END SECTION ===` delimiters, uppercase `KEY=VALUE` lines, an
  `ISSUE_COUNT=` roll-up, and a `STATUS=` drawn from `OK|WARN|ERROR` and no
  other word — a rollup matches that alternation, so a fourth verdict is
  invisible rather than distinct.

Stdlib only, and deliberately NO PEP-723 dependency block: both real callers
(`hooks/config-drift-probe.sh` and the test suite) invoke a bare `python3`,
bypassing the uv shebang, so a dependency block would resolve only on the
unused path. A broken import here fails SILENTLY — the hook treats empty
analyzer output as "no findings" — which is why this file must never grow an
import that a bare interpreter cannot satisfy.

Import it as `from lib.probe import ...`: `sys.path[0]` is the SCRIPT's
directory (`health-plugin/scripts`), not `lib/`, and PEP 420 implicit
namespace packages resolve `lib.probe` from there. There is no `__init__.py`
and there must not be one — nothing under `*-plugin/scripts/` is a package.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
from pathlib import Path

BASELINE_SCHEMA = 1

_SEVERITIES = ("error", "warn", "info")
# A SHAPE check, not an enum: `semantic_overlap_{a}_{b}` is a dynamic f-string,
# so the set of legal kinds is not enumerable here.
_KIND_RE = re.compile(r"^[a-z][a-z0-9_]*$")


# --------------------------------------------------------------------- hashing
def sha(text: str) -> str:
    """sha256 of `text`, truncated to 16 hex chars.

    The 16 is contract. Waiver hashes and fingerprints both flow through this
    helper, so a probe that truncated to 12 or 20 would produce a waiver file
    and a baseline no other probe could read.
    """
    return hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()[:16]


# -------------------------------------------------------------------- findings
class Finding:
    """One reported problem, dict-compatible on read.

    `__getitem__` / `get` exist so a consumer written against dict literals —
    a sort lambda, a renderer, a `--since` filter — keeps working unchanged.
    Key order in `to_dict()` is the order the caller passed `**extra`, which is
    what lets each construction site reproduce its former dict literal exactly.
    """

    __slots__ = ("severity", "kind", "summary", "extra")

    def __init__(self, severity: str, kind: str, summary: str, **extra):
        if severity not in _SEVERITIES:
            raise ValueError(f"severity must be one of {_SEVERITIES}, got {severity!r}")
        if not isinstance(kind, str) or not _KIND_RE.match(kind):
            raise ValueError(f"kind must match {_KIND_RE.pattern}, got {kind!r}")
        if not summary:
            raise ValueError("summary must be non-empty")
        if "path" in extra and "paths" in extra:
            raise ValueError(
                "a finding carries `path` OR `paths`, never both — "
                "fingerprint() folds the singular into the set and two "
                "spellings of the same fact would double-count"
            )
        self.severity = severity
        self.kind = kind
        self.summary = summary
        self.extra = extra

    def __getitem__(self, key):
        if key in ("severity", "kind", "summary"):
            return getattr(self, key)
        return self.extra[key]

    def get(self, key, default=None):
        try:
            return self[key]
        except KeyError:
            return default

    def __contains__(self, key) -> bool:
        return key in ("severity", "kind", "summary") or key in self.extra

    def to_dict(self) -> dict:
        return {
            "severity": self.severity,
            "kind": self.kind,
            "summary": self.summary,
            **self.extra,
        }

    def __repr__(self) -> str:
        return f"Finding({self.severity!r}, {self.kind!r}, {self.summary!r}, **{self.extra!r})"


def fingerprint(finding) -> str:
    """Stable identity of a finding across runs: kind + its path set.

    The singular `path` key is FOLDED into the path set. Read naively as
    "paths only", every `broken_pointer_stub` (which carries `path`) would
    collapse to one fingerprint per kind, so the second broken stub in a corpus
    would be invisible in every delta report forever. Folding both is also what
    makes a later normalisation of `path` -> `paths` fingerprint-neutral.

    A finding with no path at all — `always_loaded_budget`,
    `frontmatter_coverage`, `coverage_metric_broken`,
    `semantic_pass_unavailable` — gets one stable fingerprint per kind. That is
    correct: a changing token count or a different exception message must not
    make the same standing condition look new on every run.
    """
    paths = list(finding.get("paths") or [])
    single = finding.get("path")
    if single:
        paths.append(single)
    return sha(finding["kind"] + "\0" + "\0".join(sorted(set(paths))))


# --------------------------------------------------------------------- waivers
class Waivers:
    """Pair-keyed waivers that expire when either side's content changes."""

    __slots__ = ("_by_pair",)

    def __init__(self, by_pair=None):
        self._by_pair = dict(by_pair or {})

    @staticmethod
    def _canon(path: str) -> str:
        """Canonicalise a path for waiver matching.

        Waiver files are hand-written, so a side may be spelled `~/repos/...`
        or `/var/...` while the scan resolves it to `/private/var/...` (macOS
        symlinks every temp and `/var` path). Comparing raw strings silently
        fails to match and the waiver looks ignored, which is
        indistinguishable from a bug.
        """
        return os.path.realpath(os.path.expanduser(path))

    @classmethod
    def load(cls, path) -> "Waivers":
        path = Path(path)
        if not path.is_file():
            return cls({})
        try:
            raw = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            return cls({})
        return cls(
            {
                (cls._canon(w["a"]), cls._canon(w["b"])): w
                for w in raw.get("waivers", [])
            }
        )

    def __len__(self) -> int:
        return len(self._by_pair)

    def waived(self, a: dict, b: dict) -> bool:
        """A waiver holds only while BOTH sides are byte-identical to when it was filed.

        Both orientations are tried, and the recorded hash pair is swapped to
        match whichever orientation hit — a waiver filed as (a, b) must still
        suppress the pair when the scan happens to yield (b, a).
        """
        pa, pb = self._canon(a["path"]), self._canon(b["path"])
        for key in ((pa, pb), (pb, pa)):
            w = self._by_pair.get(key)
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


# -------------------------------------------------------------- baseline/delta
class Delta:
    """What changed between a baseline and the current findings."""

    __slots__ = ("first_run", "new", "resolved", "carried")

    def __init__(self, first_run: bool, new: list, resolved: list, carried: list):
        self.first_run = first_run
        self.new = new
        self.resolved = resolved
        self.carried = carried


class Baseline:
    """The set of findings a probe has already reported, keyed by fingerprint.

    `root` is load-bearing, not bookkeeping. Fingerprints are built from
    ABSOLUTE paths, so a baseline recorded at one root and compared at another
    yields a DISJOINT set: every current finding new, every stored one
    resolved — a maximally noisy false report. `load` returns None on a root
    (or schema) mismatch exactly as it does for a missing file, so the caller
    records fresh and stays silent instead.
    """

    __slots__ = ("probe", "root", "recorded_at", "findings", "loaded")

    def __init__(self, probe, root, recorded_at, findings=None, loaded=False):
        self.probe = probe
        self.root = str(root)
        self.recorded_at = recorded_at
        self.findings = dict(findings or {})
        self.loaded = loaded

    @classmethod
    def load(cls, path, root=None, probe=None) -> "Baseline | None":
        """Read a baseline, or None when it cannot be trusted.

        None for: missing, unreadable, unparseable, wrong schema, wrong root,
        wrong probe, or a `findings` block that is not a mapping. Every one of
        those means "compare nothing", never "everything is new".
        """
        try:
            raw = json.loads(Path(path).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        if not isinstance(raw, dict):
            return None
        if raw.get("schema") != BASELINE_SCHEMA:
            return None
        if root is not None and raw.get("root") != str(root):
            return None
        if probe is not None and raw.get("probe") != probe:
            return None
        findings = raw.get("findings")
        if not isinstance(findings, dict):
            return None
        return cls(
            raw.get("probe"),
            raw.get("root"),
            raw.get("recorded_at"),
            findings,
            loaded=True,
        )

    def record(self, findings) -> "Baseline":
        """Replace the stored records with the given findings."""
        self.findings = {
            fingerprint(f): {
                "severity": f["severity"],
                "kind": f["kind"],
                "summary": f["summary"],
            }
            for f in findings
        }
        return self

    def save(self, path) -> None:
        """Write atomically: temp file in the same directory, then os.replace.

        The consumer is an unattended scheduled job that can be killed
        mid-write, and a truncated baseline that still parses as `{}` would
        report the whole corpus as new on the next run.
        """
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(path.name + ".tmp")
        tmp.write_text(
            json.dumps(
                {
                    "schema": BASELINE_SCHEMA,
                    "probe": self.probe,
                    "root": self.root,
                    "recorded_at": self.recorded_at,
                    "findings": self.findings,
                },
                indent=1,
            ),
            encoding="utf-8",
        )
        os.replace(tmp, path)

    def delta(self, findings) -> Delta:
        seen: dict[str, object] = {}
        for f in findings:
            seen.setdefault(fingerprint(f), f)
        new = [f for fp, f in seen.items() if fp not in self.findings]
        carried = [f for fp, f in seen.items() if fp in self.findings]
        resolved = [rec for fp, rec in self.findings.items() if fp not in seen]
        return Delta(not self.loaded, new, resolved, carried)


# --------------------------------------------------------------------- output
def exit_code(findings, gate: bool = False) -> int:
    """0 clean, 1 anything error-or-warn, 2 gate + at least one error.

    Exit 3 (root not a directory) deliberately stays in the caller: that is
    argument validation, not a statement about findings.
    """
    errs = sum(1 for f in findings if f["severity"] == "error")
    if gate and errs:
        return 2
    return 1 if any(f["severity"] in ("error", "warn") for f in findings) else 0


def render_json(findings, counts, indent: int = 1) -> str:
    """The `--format=json` document: counts first, then the findings array."""
    return json.dumps(
        {"counts": counts, "findings": [f.to_dict() for f in findings]}, indent=indent
    )


def render_status(section: str, findings, counts) -> str:
    """A conformant `structured-script-output.md` block.

    Conformant means it carries the closing `=== END <section> ===` delimiter
    and an `ISSUE_COUNT=` roll-up, which config-drift's own `emit_status` does
    not — that one predates the convention and is kept byte-identical for now.

    `STATUS` is `OK` / `WARN` / `ERROR` and nothing else. That vocabulary is
    fixed by `.claude/rules/structured-script-output.md`, and a rollup greps
    `STATUS=(OK|WARN|ERROR)`: a fourth word (`CLEAN`, `FAIL`, `GOOD`) does not
    read as a distinction, it drops the section out of the table silently.
    There is deliberately no override parameter — a caller rendering an empty
    list is `OK`, which is what "nothing new" already means. A consumer that
    wants to say more says it in `counts` (`FIRST_RUN=true`, `NEW=0`), where a
    new key adds information instead of breaking an existing match.

    The severity counters are `NEW_ERRORS=` / `NEW_WARNINGS=`, not
    `ERRORS=` / `WARNINGS=`, because `findings` here is the SUBSET the caller
    chose to render while its `counts` carries the full total —
    `config-drift.py`'s `emit_status` already writes `ERRORS=`/`WARNINGS=` over
    the whole set, so reusing those names would give a combined-log rollup two
    contradictory answers to one `grep '^ERRORS='`.
    """
    lines = [f"=== {section} ==="]
    for key, value in counts.items():
        lines.append(f"{key.upper()}={value}")
    by_kind: dict[str, int] = {}
    for f in findings:
        by_kind[f["kind"]] = by_kind.get(f["kind"], 0) + 1
    for kind, n in sorted(by_kind.items()):
        lines.append(f"FINDING_{kind.upper()}={n}")
    errs = sum(1 for f in findings if f["severity"] == "error")
    warns = sum(1 for f in findings if f["severity"] == "warn")
    lines.append(f"NEW_ERRORS={errs}")
    lines.append(f"NEW_WARNINGS={warns}")
    lines.append("STATUS=" + ("ERROR" if errs else "WARN" if warns else "OK"))
    lines.append(f"ISSUE_COUNT={len(findings)}")
    if findings:
        lines.append("ISSUES:")
        for f in findings:
            lines.append(
                f"  - SEVERITY={f['severity'].upper()} TYPE={f['kind']} MSG={f['summary']}"
            )
    lines.append(f"=== END {section} ===")
    return "\n".join(lines)

#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["fastembed>=0.4", "numpy>=1.26"]
# ///
"""config-drift — continuous hygiene check for the Claude configuration corpus.

The corpus is four document kinds: `.claude/rules/*.md` (plus `~/.claude/rules`),
`*/skills/*/SKILL.md`, `*-plugin/agents/*.md`, and `CLAUDE.md`. All four share
ONE document shape (`_doc`), and every check names the kinds it applies to
explicitly — see the check x kind matrix assembled in `main()`.

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
import json
import os
import re
import subprocess
import sys
from itertools import combinations
from pathlib import Path

# The finding / waiver / delta CONTRACT lives in a stdlib-only sibling module so
# a second probe can share it; the similarity computation and every threshold
# below stay here, because they are this probe's opinion rather than a contract.
# `lib.probe`, not `probe`: sys.path[0] is this script's directory, and PEP 420
# implicit namespace packages resolve the dotted form from there. Do not add an
# __init__.py and do not touch sys.path.
from lib.probe import (
    Finding,
    Waivers,
    render_json,
    render_report,
    render_status,
    sha,
)

HOME_RULES = Path.home() / ".claude" / "rules"
SKIP_PARTS = {"node_modules", "dist", "worktrees", ".git", "__pycache__", "tmp"}
EMBED_MODEL = "BAAI/bge-small-en-v1.5"
EMBED_CHARS = 2000

# Scope sentinel for the kinds that are NOT promotable. A skill and an agent are
# namespaced by their plugin, not scoped to a directory tree, so "promote it to
# the parent scope" names no operation for them -- there is no parent scope to
# promote into. `scope_rank` is None for this sentinel rather than a number,
# because the obvious falsy default (0) is `user-global`, i.e. the MOST promoted
# rank there is: the exact wrong reading. #2528b consumes the rank; it is
# computed here so the document shape is settled in one place.
SCOPE_PLUGIN = "plugin"

# The kinds the SEMANTIC pass compares. Agents and CLAUDE.md are deliberately
# EXCLUDED in this PR. T_SEMANTIC below is 0.91 because it was calibrated
# against rule/skill markdown -- the threshold comment there says outright that
# baseline cosine is high *because every document is one genre*, so an agent
# prompt (a second-person instruction sheet) and a CLAUDE.md (a repo overview)
# are two further genres whose own baselines are unmeasured. Per-kind
# calibration is #2528b. `test-probe-lib.sh` TEST N3 reads this tuple out of the
# source to expand the `semantic_overlap_{a}_{b}` f-string, so widening it here
# widens that coverage assertion rather than silently escaping it.
SEMANTIC_KINDS = ("rule", "skill")

# The kinds the LEXICAL pass compares -- each against ITSELF only. See
# `check_lexical_dupes` for why the comparison is partitioned rather than pooled.
LEXICAL_KINDS = ("rule", "agent", "claude_md")

# The kinds the PROMOTION pass compares. Exactly the SCOPED kinds: a rule and a
# CLAUDE.md both live at a point in a directory ladder, so "the same thing is
# said at two levels, keep the higher one" names a real operation on them.
# Skills and agents are namespaced by their plugin and carry `SCOPE_PLUGIN`,
# whose `scope_rank` is None -- there is no parent scope to promote into, so
# they are excluded by the sentinel rather than by this tuple alone (the pass
# re-checks the rank, because a kind list is a policy and a None rank is a
# fact).
PROMOTION_KINDS = ("rule", "claude_md")

# A file whose presence DECLARES that the tree it heads is a generator template
# rather than live configuration. See `_is_generator_template`.
#
# `cruft.json` is here because cruft-managed cookiecutter templates are the
# common case and cruft does NOT ship a `cookiecutter.json` of its own -- so the
# original four-entry list missed the majority shape of the very ecosystem it
# was written for.
GENERATOR_MANIFESTS = (
    "cargo-generate.toml",
    "cookiecutter.json",
    "copier.yml",
    "copier.yaml",
    "cruft.json",
)

# A path COMPONENT still carrying a template placeholder. The docstring of
# `_is_generator_template` declines an unrendered-marker scan over a document's
# CONTENT -- a CLAUDE.md legitimately quotes `{{ }}` while documenting a
# template rather than being one. A directory NAME carries no such ambiguity:
# nothing renders it, nobody quotes prose in it, and `{{cookiecutter.x}}/` is
# the literal on-disk name cookiecutter/copier/cruft ship.
UNRENDERED_MARKERS = ("{{", "{%")

# Directory names that are template payload BY CONVENTION -- plural for
# cargo-generate/`templates/`, singular for npm's `create-*` packages and
# copier's `_subdirectory: template`. Conventional, not declarative: a Flask or
# Django `app/templates/` is a Jinja directory and its CLAUDE.md is live
# configuration, so a bare match here is never sufficient on its own.
TEMPLATE_DIR_NAMES = ("templates", "template")

# npm's `create-*` convention: `packages/create-widget/template/` is the payload
# `npm create widget` copies out. The parent's name is the corroboration a bare
# `template/` component lacks.
CREATE_PKG = re.compile(r"^create-.")

# Thresholds. Deliberately conservative: this tool surfaces, a human decides.
# Calibrated against the live corpus, not guessed. At 0.86 the semantic pass
# emitted 491 findings, of which 290 were same-name pairs the cheap tier already
# owns and most of the rest were genre noise -- every document here is "Claude
# config markdown about tooling", so baseline cosine is high. Novel-pair score
# distribution was 0.94:2 0.92:9 0.90:32 0.88:70 0.86:88, i.e. the actionable
# signal sits above ~0.91 and the tail below it is unusable.
T_SEMANTIC = 0.91  # cosine over title+head

# PROMOTION threshold. Measured 2026-08-29 with `--calibrate`, not guessed.
#
# Two corpora, both including `~/.claude/rules` (HOME_RULES is unconditional).
# Calibrated at `~/repos` (505 promotable docs / 141 scopes / 76,120 cross-scope
# pairs); SHIPS to run at `claude-plugins` (101 docs / 4 scopes / 2,642 pairs),
# where the whole above-band set is n=1. Cumulative counts, cross-scope only:
#
#   claude-plugins  RAW    0.94:0  0.92:0  0.90:0  0.88:2   0.86:3
#   claude-plugins  NOVEL  0.94:0  0.92:0  0.90:0  0.88:1   0.86:2
#   repos           RAW    0.94:27 0.92:39 0.90:61 0.88:101 0.86:170
#   repos           NOVEL  0.94:6  0.92:7  0.90:7  0.88:19  0.86:28
#
# 0.88 sits inside the separating interval (0.8721, 0.8990] measured at the ship
# root, with a 0.027 margin to the nearest adjudicated non-candidate. The band
# is BELOW T_SEMANTIC for a measured reason rather than a severity argument: at
# 0.91 -- and still at 0.90 -- `claude-plugins` yields ZERO promotion findings,
# so shipping this at T_SEMANTIC ships it inert at the only root it runs at. The
# one genuine candidate there (`user-global::claude-code-auto-mode` <-
# `portfolio::auto-mode`, 0.8990, different names, no cross-reference in either
# direction) is the highest promotion signal in that corpus. Going lower is
# worse, not merely noisier: 0.87 admits `agent-and-tool-selection` <-
# `workflow-model-effort`, adjudicated as two different documents sharing a
# topic, and 0.86 adds nothing at either root.
#
# THE THRESHOLD IS NOT CARRYING THE PRECISION -- the discriminators are, and
# the measurement says so twice. The nearest pair to the genuine candidate is
# `offload-to-deterministic-substrate` against itself one scope up at 0.8994,
# i.e. 0.0004 ABOVE it: no threshold can separate those two, and only
# `structural_pair` does. Rank-strict admits 69 pairs at `~/repos`/0.88, of
# which 47 are unrelated cross-repo siblings; the ancestor constraint cuts that
# to 22 and removes zero adjudicated candidates, and MIN_PROMOTABLE_CHARS cuts
# 22 -> 12 by dropping near-empty `@AGENTS.md` redirect stubs in a vendored
# clone. See `check_promotion_candidates` for both.
T_PROMOTE = 0.88  # cosine over title+head, cross-scope, promotable kinds only

# A document too short to have a topic. Cosine between two near-empty documents
# is meaningless and runs HIGH: 10 of the 22 ancestor-constrained survivors at
# `~/repos`/0.88 were 11-128 byte `@AGENTS.md` redirect stubs in a vendored
# upstream clone, scoring 0.879-0.975 against each other. The floor costs
# nothing measurable -- the smallest genuine candidate is 662 chars, and only 5
# of 101 docs at `claude-plugins` (27 of 505 at `~/repos`) fall below it.
MIN_PROMOTABLE_CHARS = 500

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
def toks(text: str) -> list[str]:
    return [
        w for w in re.findall(r"[a-z][a-z0-9_-]{2,}", text.lower()) if w not in STOP
    ]


def shingles(text: str, n: int = 3) -> set[str]:
    t = toks(text)
    return {" ".join(t[i : i + n]) for i in range(max(0, len(t) - n + 1))}


def jaccard(a: set, b: set) -> float:
    return len(a & b) / len(a | b) if a and b else 0.0


FM_KEY = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):[ \t]*(.*)$")
# A block-scalar indicator is `|` or `>` optionally carrying a chomping sign
# and/or an explicit indentation digit, optionally followed by a comment:
# `|`, `|-`, `>+`, `|2`, `|2-`, `| # notes`. Exact-set membership captured
# every suffixed form as a VALUE -- `description: |2` yielded the string `|2`,
# truthy junk with the same shape as the original empty-block bug.
FM_BLOCK = re.compile(r"^[|>][-+]?\d?[-+]?[ \t]*(#.*)?$")
FM_FENCE = re.compile(r"^---[ \t]*$")


def _unquote(raw: str) -> str:
    """Remove ONE matched surrounding quote pair, and only a matched pair.

    `raw.strip("\"'")` strips a character CLASS from both ends independently, so
    a value that merely ends in a quote character loses it:
    `path|PR|file|plan description; optional 'focus on X'` -> the trailing `'`,
    and `'<files...> --title "type(scope): description"'` -> both the outer `'`
    and the `"` newly exposed beneath it.
    """
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
        return raw[1:-1]
    return raw


def frontmatter(body: str) -> dict[str, str]:
    """Read the top-level scalar keys out of a document's YAML frontmatter.

    Deliberately a line scanner rather than a YAML parser -- consumers need
    top-level keys and nothing else, and four properties are load-bearing:

    * The frontmatter ends at the first closing fence LINE, never at the first
      `---` SUBSTRING. A `---` thematic break inside a description (118 files
      here have one) or an inline `--- separator` truncated the block and
      dropped every key after it, including `paths:` -- which silently billed a
      path-scoped rule to the always-loaded budget.
    * A key is only recognised at column 0. That is what stops a list item, or
      a `key: value` line inside a block-scalar body, from shadowing a real
      key.
    * A bare-empty value stays the empty string. `paths:` carries its globs on
      the following lines, and consumers test it for KEY PRESENCE, never
      truthiness -- so a path-scoped rule must add nothing to the always-loaded
      budget. Only an explicit block-scalar indicator slurps what follows;
      indented list items are never absorbed as a continuation.
    * A block scalar's body, and a plain scalar's indented continuation lines,
      are joined with single spaces. The value feeds an embedding text and a
      description field, not a YAML round-trip.
    * The block must OPEN like frontmatter, not merely be delimited like it.
      The closing-fence scan runs to the end of the document, so a file with no
      frontmatter that opens with a `---` thematic break and carries another one
      later had its prose read as the block -- and prose says `Note:` and
      `Rationale:` at column 0. Requiring the FIRST non-blank line to be a key
      confines the scan to real frontmatter. It has to be the first line rather
      than the first non-comment one, because a markdown `# Heading` and a YAML
      `# comment` are the same string: skipping comments walks straight past the
      heading and back into the prose. The cost is that frontmatter opening with
      a YAML comment parses to {}; 0 of the 757 fenced documents in this corpus
      do that, and the failure it buys off is silent (prose supplying a `paths:`
      drops a rule out of the always-loaded budget).
    """
    if not body.startswith("---"):
        return {}
    all_lines = body.splitlines()
    close = next(
        (i for i in range(1, len(all_lines)) if FM_FENCE.match(all_lines[i])), None
    )
    if close is None:
        return {}

    fm: dict[str, str] = {}
    lines = all_lines[1:close]
    opener = next((x for x in lines if x.strip()), None)
    if opener is None or not FM_KEY.match(opener):
        return {}
    i = 0
    while i < len(lines):
        m = FM_KEY.match(lines[i])
        i += 1
        if not m:
            continue
        key, raw = m.group(1), m.group(2).strip()
        if not FM_BLOCK.match(raw):
            # Plain scalar: absorb indented continuation lines, which YAML folds
            # into the same value. Without this a value wrapped over two lines
            # was captured truncated -- worse than being missed, because the
            # fragment looks like a complete value.
            cont: list[str] = []
            while i < len(lines):
                nxt = lines[i]
                if not nxt.strip() or not nxt[:1].isspace():
                    break
                stripped = nxt.strip()
                # A comment line is never scalar content -- not in YAML and not
                # here. Skip it without ending the value: absorbing it appended
                # the comment to `reviewed:`, which then failed its
                # \d{4}-\d{2}-\d{2} gate and dropped the file out of the
                # staleness check while still counting as reviewed.
                if stripped.startswith("#"):
                    i += 1
                    continue
                # A `- ` item belongs to a list (`paths:`) and an indented
                # `key:` opens a nested mapping -- but both are only possible
                # under a key whose INLINE value is empty. Once a value sits on
                # the key's own line YAML permits neither, so every indented
                # line there is continuation, and breaking on one truncated the
                # value (a wrapped URL, a dash-led clause) exactly as the
                # missing-continuation bug did.
                if not raw and (stripped.startswith("- ") or FM_KEY.match(stripped)):
                    break
                cont.append(stripped)
                i += 1
            joined = " ".join([raw, *cont]).strip() if cont else raw
            fm[key] = _unquote(joined)
            continue
        block: list[str] = []
        while i < len(lines):
            nxt = lines[i]
            if nxt.strip() and not nxt[:1].isspace():
                break
            block.append(nxt.strip())
            i += 1
        fm[key] = " ".join(w for w in block if w).strip()
    return fm


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
def _scope_rank(scope: str) -> int | None:
    """How far a scope is from the top of the tree; None when not promotable.

    0 user-global, 1 portfolio, then 2 + one per path separator for a nested
    scope, so a deeper rule always outranks a shallower one. `SCOPE_PLUGIN`
    yields None -- see the sentinel's own comment for why a number would be a
    lie rather than a default.
    """
    if scope == SCOPE_PLUGIN:
        return None
    if scope == "user-global":
        return 0
    if scope == "portfolio":
        return 1
    return 2 + scope.count("/")


def _doc(
    kind: str,
    path: Path,
    name: str,
    title: str,
    body: str,
    fm: dict,
    scope: str,
    always_loaded: bool,
    stub: bool = False,
) -> dict:
    """One document, in the shape EVERY kind uses.

    Before this the two kinds carried different key sets -- 11 for a rule, 9 for
    a skill -- so any check touching `scope` was rule-only BY ACCIDENT rather
    than by design, and `structural_pair` already had to write `x.get("stub")`
    to survive a skill. With four kinds that arrangement stops being survivable:
    a missing key reads as falsy, and "this kind has no stubs" and "this kind
    was never given the key" become indistinguishable at every call site. One
    shape means a check that must not apply to a kind is guarded EXPLICITLY (see
    the kind guards on `check_stub_integrity`, `check_frontmatter` and
    `check_rule_covered_by_skill`), which is auditable; a shape mismatch is not.

    `desc` is now populated for every kind from `description:`. No rule in this
    corpus carries one today (0 of 98, measured), so this is embed-neutral now;
    if a rule grows one it starts contributing to the embed text, which is
    correct, and the embedding cache is keyed on the embed TEXT so it
    self-invalidates rather than serving a vector computed from the old text.
    """
    return {
        "kind": kind,
        "path": str(path),
        "name": name,
        "title": title,
        "body": body,
        "fm": fm,
        "desc": fm.get("description", ""),
        "scope": scope,
        "scope_rank": _scope_rank(scope),
        "always_loaded": always_loaded,
        "chars": len(body),
        "hash": sha(body),
        "stub": stub,
    }


def _heading_title(body: str, fallback: str) -> str:
    """The document's first `# ` heading, or `fallback`."""
    return next(
        (line[2:].strip() for line in body.splitlines() if line.startswith("# ")),
        fallback,
    )


def _is_generator_template(dirpath: Path, root: Path) -> bool:
    """True when `dirpath` holds generator-template payload, not live config.

    A template's CLAUDE.md is not configuration that loads anywhere -- it is
    payload a generator copies into a repo that does not exist yet. Ingesting it
    puts an unrendered document into the corpus, where it can only produce
    findings whose fix site is a template nobody is editing.

    The predicate this replaced was wrong in BOTH directions, and the
    over-exclude half is the worse one because it silently drops live
    configuration:

    * It matched only the PLURAL `templates`, so `packages/create-widget/
      template/CLAUDE.md` -- npm's `create-*` convention, and copier's
      `_subdirectory: template` -- was ingested unrendered.
    * `cruft.json` was not a manifest, so a cruft-managed cookiecutter tree
      (the common case) declared nothing.
    * A bare `templates` component fired at any depth with no corroboration, so
      EVERY repo with a Flask/Django `app/templates/` lost its CLAUDE.md.
    * The manifest walk ran before the `cur == root` termination, so a manifest
      at the root excluded the root's OWN CLAUDE.md -- a template repo's own
      root document is live config for whoever maintains the template.

    The replacement separates signals that DECLARE from signals that merely
    SUGGEST, and requires corroboration for the latter:

    | | Signal | Sufficient alone? |
    |---|---|---|
    | 0 | `dirpath == root` | Never a template -- see below |
    | A | a path COMPONENT carries `{{` / `{%` | yes, declarative |
    | B | a manifest at a STRICT ANCESTOR of `dirpath` | yes, declarative |
    | C | a manifest at `dirpath` ITSELF | no -- corroboration |
    | D | a `template` / `templates` path component | no -- corroboration |
    | E | a `create-*` parent of that component | no -- corroboration |

    Rule 0: the tree you point `--root` at is the tree you are working in, and
    its own CLAUDE.md loads on every turn there whatever the repo generates.

    A and B are declarative because something in the tree SAYS "template": an
    unrendered directory name is not a name anyone typed, and a manifest heading
    an ancestor puts `dirpath` INSIDE a declared template tree.

    C is deliberately NOT declarative on its own, and that is the fix for the
    `my-copier-template/CLAUDE.md` case at any scope rather than only at the
    root. A manifest sitting BESIDE a document heads that tree; the document is
    the template repo's own front matter, not the payload. Flat layouts
    (cargo-generate, copier without `_subdirectory`) do make the manifest's own
    directory the payload -- which is why C excludes when corroborated by D, the
    shape the real instance here has (`foundryvtt-plugin/templates/
    foundryvtt-module/` carries `cargo-generate.toml` beside its CLAUDE.md).

    D alone is the false positive that motivated the redesign. It excludes only
    with C or E beside it.

    A is a COMPONENT scan, not a CONTENT scan. The content scan stays declined
    for the reason it always was -- `scripts/check-unrendered-templates.sh` owns
    that signal for a different purpose, and a CLAUDE.md quoting `{{ }}` while
    DOCUMENTING a template would be dropped with no way to tell. A directory
    name carries no such ambiguity.

    KNOWN RESIDUAL, stated rather than hidden: signal B's ancestor walk includes
    `root`, so pointing `--root` at a template repo still excludes every
    NON-root CLAUDE.md in it. That is correct for a whole-repo template (copier
    with no `_subdirectory`, cookiecutter's payload directory) and conservative
    for a `_subdirectory` one, and it is bounded to a repo whose own root
    declares itself a template. Rule 0 protects the one document that certainly
    still loads.

    Note this is COLLECTOR-LOCAL and `templates` is deliberately NOT added to
    SKIP_PARTS. Executed: a global skip drops
    `obsidian-plugin/skills/templates/SKILL.md`, a genuine frontmattered skill,
    which in turn silently breaks `check_stub_integrity` for any pointer stub
    that delegates to it -- a broken-stub ERROR manufactured by the exclusion.
    """
    try:
        parts = dirpath.relative_to(root).parts
    except ValueError:
        return False
    # Rule 0. `relative_to` yields () only for the root itself.
    if not parts:
        return False

    # Signal A.
    if any(mark in part for part in parts for mark in UNRENDERED_MARKERS):
        return True

    # Signals B and C, from one walk. `root` is INCLUDED as an ancestor (see the
    # known residual above); `dirpath` itself is recorded separately because it
    # is corroboration, not a declaration.
    manifest_here = any((dirpath / m).is_file() for m in GENERATOR_MANIFESTS)
    cur = dirpath
    while cur != root and cur.parent != cur:
        cur = cur.parent
        if any((cur / m).is_file() for m in GENERATOR_MANIFESTS):
            return True  # Signal B

    # Signals D and E -- conventional, so one of C/E has to stand beside D.
    for i, part in enumerate(parts):
        if part not in TEMPLATE_DIR_NAMES:
            continue
        if manifest_here:
            return True  # C + D
        if i > 0 and CREATE_PKG.match(parts[i - 1]):
            return True  # D + E
    return False


def _read_corpus_file(p: Path, unreadable: list[str]) -> str | None:
    """Read one corpus file, or None when it cannot be read.

    `collect()` walks user-controlled trees, and a `.claude/rules/` directory is
    routinely a symlink farm (chezmoi, stow). An unresolvable symlink makes
    `read_text()` raise FileNotFoundError from inside the INVENTORY pass, which
    aborts the whole run before a single finding is produced -- so one dangling
    link costs the entire sweep, in every scope, until a human finds it. Skipping
    the unreadable entry degrades the corpus by one file instead.

    Skipping is NOT swallowing: the path is recorded in `unreadable`, and
    `check_corpus_unreadable()` turns that into a finding. Degrading silently
    would be the worse bug -- a corpus two thirds of which failed to open would
    report a clean sweep, which is exactly the false all-clear this probe
    exists to prevent, one layer down from the hook that guards against it.
    """
    try:
        return p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        unreadable.append(str(p))
        return None


def check_corpus_unreadable(unreadable) -> list[Finding]:
    """Report corpus files the inventory pass could not open.

    `warn`, not `error`: the sweep still ran and its other findings stand. The
    aggregator sorts `error` first across every plugin and caps the nudge at
    five lines, so an `error` here would pin a dangling symlink to slot 1 on
    every session start. The paths are in the summary because they are what
    locates the file -- a remediation skill cannot find it for you.
    """
    if not unreadable:
        return []
    shown = ", ".join(unreadable[:3])
    more = f" (+{len(unreadable) - 3} more)" if len(unreadable) > 3 else ""
    return [
        Finding(
            "warn",
            "corpus_unreadable",
            f"{len(unreadable)} corpus file(s) could not be read and were skipped: {shown}{more}",
            paths=sorted(unreadable),
        )
    ]


def check_agent_discovery_misfire(agents, agent_dirs: int) -> list[Finding]:
    """Agent DIRECTORIES present but ZERO agent FILES is a MISFIRE, not clean.

    The discriminator this repo standardises on (#2219/#2290): a guard that did
    not run and a guard that found nothing look identical unless one of them
    says so. `scripts/check-agent-model.sh` implements it for this exact shape
    and exits 1 on it; the vocabulary below is deliberately its vocabulary, so a
    reader who has seen one recognises the other.

    THE DENOMINATOR IS `*-plugin/agents` DIRECTORIES, NOT PLUGIN DIRECTORIES.
    The first draft of this check counted plugin directories and was a false
    positive on sight: 36 of this repo's 49 plugin directories define no agents
    at all, and a single-plugin repo carrying only skills is entirely ordinary,
    so "plugins > 0 and agents == 0" would raise a permanent ERROR on most
    trees. It fired on this suite's own empty-corpus case, which is how it was
    caught. `agents/` directories are the real denominator: a directory that
    exists and yields nothing is a mismatch between how directories are found
    and how files are found, and that mismatch IS the bug class.

    It is not hypothetical. Until the depth-anchored `root.glob(
    "*-plugin/agents/*.md")` was replaced (see `collect`), this analyzer
    reported `AGENTS=0` at `~/repos` and `~/repos/laurigates` -- both roots the
    SessionStart probe actually runs at, both holding 21 agents below 8
    `*-plugin/agents` directories -- and nothing in the output distinguished
    that from a tree with no agents in it. The directory count comes from the
    pruned walk while the file count came from the glob, so this check would
    have fired on it. Now that both come from the same walk it is a TRIPWIRE
    rather than a live detector: it fires if file discovery is ever re-anchored
    away from directory discovery again, which is the regression that shipped.

    Known false positive, small and named: an `agents/` directory holding no
    `.md` at all. That is itself an anomaly worth a line.

    `error`, not `warn`, and the aggregator's slot-1 cost is the point rather
    than a side effect. The sibling `coverage_metric_broken` is the precedent in
    this same file: when a metric is broken its output must not be trusted, and
    the finding that says so outranks the findings it invalidates. Unlike
    `corpus_unreadable` (`warn`, because the sweep still ran and can keep
    reporting a dangling symlink forever), this one clears itself the moment
    discovery works again.
    """
    if agents or not agent_dirs:
        return []
    return [
        Finding(
            "error",
            "agent_discovery_misfire",
            (
                f"Found {agent_dirs} plugin agent director(ies) below the root but "
                "ZERO agent files. This is a discovery misfire, not a clean tree "
                "— the agent kind checked nothing, so AGENTS=0 and every agent "
                "finding is uninformative"
            ),
        )
    ]


def collect(root: Path) -> tuple[dict[str, list[dict]], list[str], int, int]:
    """Inventory the four document kinds under `root` (plus `~/.claude/rules`).

    Returns `(corpus, unreadable, templates_excluded, agent_dirs)` where
    `corpus` is keyed by kind. A dict rather than a widening tuple: every check
    below takes the kinds it applies to by name, which is what makes the
    check x kind matrix readable at the call site in `main()`.
    """
    rules, skills, agents, claude_mds = [], [], [], []
    unreadable: list[str] = []
    templates_excluded = 0
    agent_dirs = 0

    agent_paths: list[Path] = []
    rule_paths = sorted(HOME_RULES.glob("*.md")) if HOME_RULES.is_dir() else []
    claude_md_paths: list[Path] = []
    for dirpath, filenames in walk(root):
        # Agents come from the SAME pruned walk every other kind uses, matched
        # with `dirpath.match("*-plugin/agents")`.
        #
        # This was `root.glob("*-plugin/agents/*.md")` -- pinned to depth 2 while
        # rules, skills and CLAUDE.md were all recursive. At `~/repos` and
        # `~/repos/laurigates`, both documented Claude Code working roots and
        # both roots where `hooks/config-drift-probe.sh` actually runs (it passes
        # `--root "${DRIFT_CWD:-.}"`, the session cwd), the glob matched NOTHING:
        # 247 rules / 561 skills / 0 agents at `laurigates`, 367 / 591 / 0 at
        # `repos`, against 21 real agents below each. The entire agent widening
        # was inert exactly where the probe fires, and reported a bare
        # `AGENTS=0` indistinguishable from "this tree has no agents".
        #
        # The old comment defended the glob against a `dirpath.name == "agents"`
        # walk, on the grounds that two of the ten such directories here were
        # Python source packages (`git-repo-agent/src/git_repo_agent/agents`,
        # `vault-agent/src/vault_agent/agents`) where a stray `README.md` would
        # be silently ingested as an agent prompt. Those two CLIs have since been
        # extracted to their own repos (#1017, #1973) — but the probe also runs
        # over `~/repos/laurigates` and `~/repos`, where they still appear as
        # sibling checkouts, so the argument still holds. It is real and it
        # is preserved -- but it buys the `*-plugin/` PREFIX, not the DEPTH
        # ANCHOR. Measured with this predicate at `~/repos/laurigates`: exactly
        # 21, both source packages excluded, depth-independent. It is also still
        # the same definition of "an agent" that `scripts/check-agent-model.sh`
        # and `scripts/check-agent-tool-selection.sh` use.
        #
        # `.claude-plugin` is excluded explicitly: `Path.match` is fnmatch-based,
        # so `*` DOES match a leading dot, and the marketplace metadata directory
        # would otherwise qualify as a plugin.
        if dirpath.match("*-plugin/agents") and dirpath.parent.name != ".claude-plugin":
            agent_dirs += 1
            agent_paths += [dirpath / f for f in filenames if f.endswith(".md")]
        if dirpath.match("*/.claude/rules"):
            rule_paths += [dirpath / f for f in filenames if f.endswith(".md")]
        if (
            "SKILL.md" in filenames
            and f"{os.sep}skills{os.sep}" in f"{dirpath}{os.sep}"
        ):
            p = dirpath / "SKILL.md"
            body = _read_corpus_file(p, unreadable)
            if body is None:
                continue
            skills.append(
                _doc(
                    "skill",
                    p,
                    p.parent.name,
                    p.parent.name,
                    body,
                    frontmatter(body),
                    SCOPE_PLUGIN,
                    always_loaded=False,
                )
            )
        if "CLAUDE.md" in filenames:
            if _is_generator_template(dirpath, root):
                templates_excluded += 1
            else:
                claude_md_paths.append(dirpath / "CLAUDE.md")

    for p in sorted(set(rule_paths)):
        body = _read_corpus_file(p, unreadable)
        if body is None:
            continue
        scope = (
            "user-global"
            if str(p).startswith(str(HOME_RULES))
            else "portfolio"
            if p.parent.parent.parent == root
            else str(p).split("/.claude/rules/")[0].replace(str(root) + "/", "")
        )
        rules.append(
            _doc(
                "rule",
                p,
                p.stem,
                _heading_title(body, p.stem),
                body,
                frontmatter(body),
                scope,
                always_loaded=scope in ("user-global", "portfolio"),
                stub="romoted to a skill" in body[:700],
            )
        )

    for p in sorted(set(agent_paths)):
        body = _read_corpus_file(p, unreadable)
        if body is None:
            continue
        agents.append(
            _doc(
                "agent",
                p,
                p.stem,
                _heading_title(body, p.stem),
                body,
                frontmatter(body),
                SCOPE_PLUGIN,
                always_loaded=False,
            )
        )

    for p in sorted(set(claude_md_paths)):
        body = _read_corpus_file(p, unreadable)
        if body is None:
            continue
        rel = p.parent.relative_to(root)
        name = "." if rel == Path(".") else rel.as_posix()
        # The `# ` heading fallback rules use is kept, and a path-derived label
        # is needed on top of it: 2 of the 3 CLAUDE.md here carry no frontmatter
        # at all and their H1 is literally `# CLAUDE.md`, which identifies
        # nothing when three of them appear in one report.
        title = _heading_title(body, "")
        if title.lower() in ("", "claude.md", "claude"):
            title = f"CLAUDE.md ({name})"
        claude_mds.append(
            _doc(
                "claude_md",
                p,
                name,
                title,
                body,
                frontmatter(body),
                "portfolio" if p.parent == root else name,
                # Only a CLAUDE.md at the root loads on every turn. A nested one
                # (`experiments/*/CLAUDE.md`) loads when a session opens that
                # directory, which is not the always-loaded budget's question.
                always_loaded=p.parent == root,
            )
        )

    corpus = {
        "rule": rules,
        "skill": skills,
        "agent": agents,
        "claude_md": claude_mds,
    }
    return corpus, unreadable, templates_excluded, agent_dirs


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


def check_stub_integrity(docs, skills) -> list[Finding]:
    """Pointer stubs are a RULE convention; the guard is on the kind, not the flag.

    Guarded on `kind == "rule"` rather than on `stub` alone even though only
    rules are passed today. `stub` is the literal substring `"romoted to a
    skill"` in the first 700 characters, and a CLAUDE.md or an agent prompt that
    *quotes* that phrase -- describing the convention rather than following it,
    which is exactly what a repo's own CLAUDE.md does -- would set the flag and
    then fail resolution as a broken stub. The kind is the fact; the substring
    is a heuristic for it.
    """
    known = {s["name"] for s in skills}
    out = []
    for r in docs:
        if r["kind"] != "rule" or not r["stub"]:
            continue
        target = _stub_target(r["body"][:700], known)
        if target not in known:
            out.append(
                Finding(
                    "error",
                    "broken_pointer_stub",
                    f"{r['name']} points at skill '{target or '(none named)'}' which does not exist",
                    paths=[r["path"]],
                )
            )
    return out


def check_review_staleness(items, cache: dict, allow_spawn: bool) -> list[Finding]:
    """Compare each item's declared `reviewed:` against its real last-change date.

    One `git log` per file is ~10ms and there are ~900 files, which is far too
    slow for a SessionStart probe. The date is cached under `path:content-hash`:
    a file whose content is unchanged cannot have a new last-change date, so the
    cache is correct by construction rather than by TTL. In fast mode (the probe)
    a cache miss is skipped rather than spawning git, so the probe stays sub-second
    and the scheduled run is what warms the cache.

    THE SKIP IS SILENT, AND IT SCOPES EVERY CLAIM MADE ABOUT THIS CHECK IN
    `--fast`. A cache miss under `allow_spawn=False` produces no finding and no
    counter movement, so a kind with zero keys in the live gitdates cache is
    invisible to the cheap tier while looking exactly like a kind that was
    evaluated and found current.

    That is not hypothetical for the kinds this PR added: the live cache carried
    0 agent and 0 CLAUDE.md keys, so `--fast` skipped every one of them. The
    "existing counters unchanged" acceptance result for the widening was taken in
    `--fast` and is therefore a CHEAP-TIER result only. Re-measured non-fast
    against a scratch cache at this repo's root, the scheduled tier gains exactly
    one finding: `FINDING_REVIEW_STALENESS` 67 -> 68, `WARNINGS` 67 -> 68,
    `ISSUE_COUNT` 73 -> 74. It is GENUINE -- `claude-plugins/CLAUDE.md` is 125
    days past its declared `reviewed: 2026-04-21` -- and is not suppressed.

    Not a coverage gap on the agent side: the same non-fast run warmed 21 agent
    keys, so all 21 agents WERE evaluated and are genuinely inside STALE_DAYS.
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
                Finding(
                    "warn",
                    "review_staleness",
                    f"{it['name']} changed {gap}d after its declared reviewed:{rv}",
                    paths=[it["path"]],
                    gap_days=gap,
                )
            )
    return sorted(out, key=lambda x: -x["gap_days"])


def always_loaded_docs(docs) -> list[dict]:
    """The documents that really are injected on every turn.

    A rule in a user-global/portfolio scope is NOT unconditionally injected if
    it carries `paths:` frontmatter -- it loads only when a matching file is
    read. Counting those inflates the budget by ~24% on this portfolio (13 of
    67 rules, ~12,200 tok). Confirmed empirically: path-scoped rules are absent
    from the initial context injection and arrive later as reminders.

    The root CLAUDE.md qualifies on the same terms and for the same reason: it
    is injected on every turn, so leaving it out understates the standing cost
    by its full size. `always_loaded` is set at collection time
    (`p.parent == root`), so a nested `experiments/*/CLAUDE.md` never reaches
    here.
    """
    return [d for d in docs if d["always_loaded"] and "paths" not in d["fm"]]


def check_budget(docs) -> list[Finding]:
    always = always_loaded_docs(docs)
    tokens = sum(d["chars"] for d in always) // 4
    if tokens <= BUDGET_TOKENS:
        return []
    worst = sorted(always, key=lambda d: -d["chars"])[:3]
    return [
        Finding(
            "warn",
            "always_loaded_budget",
            (
                f"{len(always)} always-loaded documents cost ~{tokens:,} tok/turn "
                f"(budget {BUDGET_TOKENS:,}); heaviest: "
                + ", ".join(
                    f"{d['name']}(~{d['chars'] // 4 // 100 * 100:,})" for d in worst
                )
            ),
            tokens=tokens,
        )
    ]


def check_frontmatter(rules) -> list[Finding]:
    """RULE frontmatter coverage. Agents and CLAUDE.md are excluded on purpose.

    Agents: 21 of 21 already carry `reviewed:`, so widening this reports `0/21`
    -- a finding that can never fire is dead code that reads as coverage.
    CLAUDE.md: 2 of the 3 here carry no frontmatter AT ALL, by convention, so
    the finding would be permanent and unactionable.

    The summary's denominator therefore stays `/N rules` and is NOT silently
    widened to "documents": the number a reader acts on has to name the set it
    was counted over.
    """
    missing = [r for r in rules if not r["fm"].get("reviewed")]
    if not missing:
        return []
    return [
        Finding(
            "info",
            "frontmatter_coverage",
            f"{len(missing)}/{len(rules)} rules carry no reviewed: date, so staleness cannot be tracked for them",
        )
    ]


def _lexical_finding(kind: str, summary: str, score: float, paths: list) -> Finding:
    """The duplicate-<kind>-lexical finding, spelled out per kind.

    Three near-identical branches rather than one `f"duplicate_{kind}_lexical"`,
    deliberately. The kind strings have to be LITERALS at the construction site:
    `test-probe-lib.sh` TEST N3 AST-walks this file for `Finding(...)` calls to
    derive the set of kinds the analyzer can emit, and asserts every one has an
    explicit row in the probe hook's remediation map -- an interpolated kind is
    either unparseable there or expands over the wrong domain. It also means a
    grep for a kind lands on the code that emits it.

    SEVERITY IS NOT UNIFORM ACROSS THE THREE, and the split is about what the
    duplication MEANS rather than about report real-estate:

    * `rule` -> warn. Two `.claude/rules/` scopes are both live configuration
      and both load, so an identical rule in each really is a promotion
      candidate. Duplication here is drift by construction.
    * `agent` -> warn. Two `*-plugin/agents/*.md` in one marketplace are both
      live, both listed, and a near-identical pair is genuine redundancy a
      reader has to disambiguate at dispatch time.
    * `claude_md` -> INFO. A CLAUDE.md pair is very often duplication that is
      CORRECT: a vendored clone and its upstream, or one package copied into two
      places. Measured at `~/repos`, the top pair is a byte-identical CLAUDE.md
      between the vendored `external/facedancer` clone and the user's own
      `mcu-tinkering-lab` package -- expected, not drift. The analyzer cannot
      tell a vendored copy from a divergence, and `warn` asserts the second.

    What this does NOT buy, stated because the obvious reading is wrong: it does
    not restore `rule_covered_by_skill` to the SessionStart nudge. The hook
    forwards `.[:4]` after `sort_by(.rank, .kind)`, and with five kinds present
    one is dropped whatever the severities are -- within `info`,
    `frontmatter_coverage` beats `rule_covered_by_skill` on the alphabetical
    tiebreak either way. Measured at `~/repos` and `~/repos/laurigates`, before
    and after: the forwarded SET is unchanged. What changes is the ORDER, and
    specifically slot 1, which stops being a vendored-clone artifact and becomes
    real drift again. The cap and the sort are shared across every plugin and
    are not this probe's to change.
    """
    if kind == "rule":
        return Finding(
            "warn", "duplicate_rule_lexical", summary, score=score, paths=paths
        )
    if kind == "agent":
        return Finding(
            "warn", "duplicate_agent_lexical", summary, score=score, paths=paths
        )
    return Finding(
        "info", "duplicate_claude_md_lexical", summary, score=score, paths=paths
    )


def check_lexical_dupes(corpus, waivers) -> tuple[list[Finding], int]:
    """Jaccard over 3-gram shingles, PARTITIONED by kind.

    Two reasons, and the second is the one that matters. Cost, measured on this
    corpus (best of 5, rules-only baseline 129.7ms): pooling rules + agents +
    CLAUDE.md into one `combinations()` costs +62.3ms (7,381 pairs), against
    +6.6ms partitioned (4,966 pairs) -- 9x, on the stage that already dominates
    the cheap tier the SessionStart probe runs. Meaning: a high Jaccard between
    an agent prompt and a rule is not a "duplicate rule", and the finding kind
    has no sensible cross-kind spelling -- `duplicate_rule_agent_lexical` would
    route to a remediation that does not exist.

    Returns the findings AND the number of pairs compared, so the partition is
    observable in the counts block (`LEXICAL_PAIRS=`) rather than being an
    invisible implementation detail that a later pooling could undo silently.
    """
    out: list[Finding] = []
    pairs = 0
    for kind in LEXICAL_KINDS:
        docs = corpus.get(kind, [])
        for d in docs:
            d["_sh"] = shingles(d["body"])
        for a, b in combinations(docs, 2):
            pairs += 1
            s = jaccard(a["_sh"], b["_sh"])
            if s >= T_LEXICAL and not waivers.waived(a, b):
                out.append(
                    _lexical_finding(
                        kind,
                        f"{a['scope']}:{a['name']} and {b['scope']}:{b['name']} "
                        f"are {s:.0%} lexically identical",
                        round(s, 3),
                        [a["path"], b["path"]],
                    )
                )
    return sorted(out, key=lambda x: -x["score"]), pairs


def check_rule_covered_by_skill(rules, skills, waivers) -> list[Finding]:
    """Topic containment: how much of a rule's vocabulary a skill already carries.

    Full-body Jaccard is the wrong metric here and silently returns zero -- a
    SKILL.md is 5-20x a rule's length, so the union swamps the intersection.
    Containment is asymmetric and correct. Control-tested: every already-promoted
    pointer stub must score above threshold against its own skill.

    RULES ONLY -- do not widen this to agents or CLAUDE.md. The control gate at
    the bottom counts pointer STUBS, and agents and CLAUDE.md have none by
    construction, so including them leaves `control_hits` unchanged while
    inflating nothing... except that any future stub-shaped text in them would
    dilute `control_total` toward the 0.7 threshold. Tripping that gate emits
    `coverage_metric_broken` and SUPPRESSES EVERY coverage finding: a one-line
    widening here silently disables an existing check rather than extending it.
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
        if score >= T_COVERAGE and skill and not waivers.waived(r, skill):
            out.append(
                Finding(
                    "info",
                    "rule_covered_by_skill",
                    (
                        f"{r['scope']}:{r['name']} is {score:.0%} covered by skill "
                        f"{skill['name']} -- candidate for a pointer stub"
                    ),
                    score=round(score, 3),
                    paths=[r["path"], skill["path"]],
                    always_loaded=r["always_loaded"],
                )
            )
    # Control gate: if the known-good stubs do not surface, the metric is broken
    # and its output must not be trusted (never-fabricate-test-identifiers).
    if control_total and control_hits < max(1, int(0.7 * control_total)):
        out = [
            Finding(
                "error",
                "coverage_metric_broken",
                (
                    f"containment metric failed its control: only {control_hits}/{control_total} "
                    "known pointer stubs detected -- coverage findings suppressed"
                ),
            )
        ]
    return sorted(out, key=lambda x: (not x.get("always_loaded"), -x.get("score", 0)))


def structural_pair(a: dict, b: dict) -> bool:
    """Relationships that are correct by design, not drift.

    Two shapes dominate the high-cosine band and neither is a defect:
    a pointer stub scores ~0.92 against the very skill it delegates to, and
    deliberately cross-referenced sibling rules ("Sibling: pr-merge-hazards.md")
    score ~0.93. Flagging either trains the reader to ignore the report.

    Hoisted to module scope from inside `check_semantic_dupes` so
    `check_promotion_candidates` can CALL it. It answers ONE question -- "is
    this similarity by design?" -- pairwise and statelessly, and it is the ONLY
    suppressor on both axes. A promotion-specific prose discriminator was built
    on top of it and then removed: measured over both corpora it changed no
    emitted finding at either root, and its scope-level binders over-suppressed
    (see `check_promotion_candidates` for the measurement and the residual gap).
    Anything added here widens BOTH axes at once, so a widening motivated by one
    has to be calibrated against the other.

    Known mechanical limits on the promotion axis, measured and stated rather
    than assumed away:

    * It reads only the two documents in the pair, so a hierarchy declared in a
      THIRD file is invisible to it. At `~/repos` that is the entire six-pair
      `ForumViriumHelsinki` family, whose "generated from the `.github` repo
      source" declaration lives in the workspace CLAUDE.md rather than in
      either copy.
    * For a `claude_md`, `Path(y["path"]).name` is always the literal
      `"CLAUDE.md"` -- a string that appears in nearly every document ABOUT
      Claude configuration. 14 of 27 ancestor cross-scope pairs >=0.86
      involving a claude_md at `~/repos` are suppressed by that literal alone.
      The `` `{name}` `` arm cannot compensate, because a claude_md's `name` is
      a relative path (`laurigates/comfyui-nodes/comfyui-touch-shim`) and never
      the basename a rule would backtick. The arm is simultaneously over-broad
      and inert on that kind.

    Left as-is deliberately: narrowing it here changes what the SEMANTIC pass
    suppresses, which is a separate calibration with its own corpus.
    """
    for x, y in ((a, b), (b, a)):
        if x.get("stub") and y["kind"] == "skill" and y["name"] in x["body"][:700]:
            return True
        if Path(y["path"]).name in x["body"] or f"`{y['name']}`" in x["body"][:1500]:
            return True
    return False


def check_promotion_candidates(items, sim, waivers) -> tuple[list[Finding], int, int]:
    """Same thing said at two scope levels — a candidate for promotion upward.

    Returns `(findings, pairs_considered, hierarchies_declared)`.

    A candidate is a pair (child, parent) where ALL of these hold:

      1. both kinds are in `PROMOTION_KINDS`
      2. `scope_rank(child) > scope_rank(parent)` STRICTLY
      3. neither carries `SCOPE_PLUGIN` (i.e. neither rank is None)
      4. the parent's scope is an ANCESTOR of the child's
      5. both documents are at least `MIN_PROMOTABLE_CHARS` long
      6. `sim(child, parent) >= T_PROMOTE`
      7. NOT `structural_pair(child, parent)`
      8. NOT waived

    SAME-NAME PAIRS ARE DELIBERATELY NOT SKIPPED, and this is the one place
    where this check and `check_semantic_dupes` must differ. That function skips
    `a["name"] == b["name"]` because for the DRIFT question a same-name pair is
    already owned by the cheap tier. For the PROMOTION question the same-name
    pair is the CANONICAL SHAPE — one rule copied down the ladder is exactly
    what "promote this" means. Do not "fix" this by copying the drift skip over:
    measured, keeping same-name pairs adds 41 findings at `~/repos`/0.88 and
    exactly ONE at `claude-plugins`, and that one is
    `offload-to-deterministic-substrate`, which `structural_pair` already
    removes. The cost is bounded; the shape it buys is the whole point.

    STRICT rank, condition 2: a tie is SKIPPED rather than reported. Two rules
    at the same depth have no parent between them, so "promote to the parent"
    names no operation and the finding's recommendation would be undefined. The
    pair is still counted in `pairs_considered` — a skip that also vanishes from
    the denominator is indistinguishable from a check that never opened it.

    The tie skip is NOT redundant with condition 4, and a test that pins it has
    to be built so that it isn't. For two scopes at equal depth under a project
    root, `_ancestor_scope` is already false, so removing the tie skip changes
    nothing there — a mutation dropping `if ra == rb: continue` survives such a
    case. It only bites when the parent side is `user-global` or `portfolio`,
    which `_ancestor_scope` accepts unconditionally: two `user-global` rules
    both rank 0, and without the tie skip one is reported as promotable into its
    own scope. That is the shape `test-config-drift.sh` case 22h pins.

    Condition 4 exists because `scope_rank` IS DEPTH, NOT ANCESTRY. Any deeper
    scope outranks any shallower one, including an unrelated repo's. Measured at
    `~/repos`/0.88: rank-strict alone yields 69 pairs, 47 of them cross-repo
    siblings (`FVH/podio-mcp::document-management` "promoted into"
    `laurigates/comfyui-nodes/...::document-management` at 0.96 — two unrelated
    trees, no ladder between them). The constraint cuts 69 -> 22 and removes
    zero adjudicated candidates. `user-global` and `portfolio` are ancestors of
    everything by construction; every other scope must be a path prefix.

    Condition 5 is the degenerate-document floor — see MIN_PROMOTABLE_CHARS.

    SEVERITY IS `info`, on three grounds and not one. It is a SUGGESTION to a
    human, never a defect — the corpus is working as intended either way.
    `--gate` returns 2 only on `error`, so a style suggestion cannot fail CI.
    And the probe hook forwards `.[:4]` after `sort_by(.rank, .kind)`, so `info`
    ranks last and this cannot crowd a real `error` out of the nudge's budget.
    Precedent in this same file: `rule_covered_by_skill`.

    `sim` is a CALLABLE, not a matrix, and that is a test-seam decision rather
    than a style one. `test-config-drift.sh` is listed in
    `scripts/required-to-run-tests.txt`, where a SKIP is an ERROR, and neither
    numpy nor fastembed is installed for the system `python3` both real callers
    invoke. A test needing the real model would force that required gate to skip
    on every runner. With the similarity injected (`--sim-fixture`), the
    discriminator, the tie skip, scope ordering, the finding shape and the
    `--gate` interaction are all exercisable in the stdlib tier.

    KNOWN LIMITATION, recorded rather than closed: `structural_pair` reads only
    the two documents in the pair, so a hierarchy DECLARED IN A THIRD DOCUMENT
    leaks through as a candidate. At `~/repos` that is the six
    `ForumViriumHelsinki/.github` <- `ForumViriumHelsinki` pairs
    (`application-structure`, `deploy-values`, `local-development`,
    `ci-cd-workflows`, `dependency-automation`, `github-metadata-hygiene`,
    0.94-0.97): the declaration lives in `ForumViriumHelsinki/CLAUDE.md` --
    "Workspace rules in `.claude/rules/` are generated from the .github repo
    source -- edit the source, not the generated files" -- which is neither end
    of any of those pairs.

    Closing it needs a THIRD-DOCUMENT declaration signal (a scope's own
    CLAUDE.md vouching for a whole rules directory), and that is its own
    calibration with its own false-positive surface -- not a widening of
    `structural_pair`. A pairwise prose discriminator was tried instead and
    measured over both corpora: it suppressed 42 pairs at `claude-plugins` and
    60 at `~/repos`, NONE of them above T_PROMOTE, i.e. it changed no emitted
    finding at either root -- while binding to a SCOPE rather than a document,
    so one sentence in one child exempted it from every rule in the parent
    scope. It was cut. Do not re-add a variant of it without a measurement
    showing it moves an emitted finding.

    The gap does not bite at the ship root: 4 scopes, the whole above-band set
    is n=1, and that one pair is genuine.
    """
    docs = [d for d in items if d["kind"] in PROMOTION_KINDS]

    out: list[Finding] = []
    considered = 0
    declared = 0
    for a, b in combinations(docs, 2):
        ra, rb = a["scope_rank"], b["scope_rank"]
        if ra is None or rb is None:
            continue  # SCOPE_PLUGIN: no ladder, so not a considered pair at all
        considered += 1
        if ra == rb:
            continue
        parent, child = (a, b) if ra < rb else (b, a)
        if not _ancestor_scope(parent, child):
            continue
        if min(child["chars"], parent["chars"]) < MIN_PROMOTABLE_CHARS:
            continue
        s = sim(child, parent)
        if s < T_PROMOTE:
            continue
        if structural_pair(child, parent):
            declared += 1
            continue
        if waivers.waived(child, parent):
            continue
        out.append(
            Finding(
                "info",
                "promotion_candidate",
                # THE SUMMARY STATES THE OBSERVATION, NOT THE ACTION. What was
                # measured is two documents covering the same topic at two rungs
                # of the ladder with no declared relationship between them;
                # whether the lower one should MOVE depends on why it exists,
                # which this check cannot see. `proposed_parent` carries the
                # suggestion, and a reader who wants it reads it there.
                (
                    f"{child['scope']}:{child['name']} is {s:.0%} similar to "
                    f"{parent['scope']}:{parent['name']} one scope up, and "
                    f"neither declares the other -- review whether the lower "
                    f"copy still earns its own scope"
                ),
                score=round(s, 3),
                # CHILD FIRST. `render_report` prints only `paths[:2]` and the
                # probe hook forwards the summary, so the order is the only
                # thing telling a reader which end moves.
                paths=[child["path"], parent["path"]],
                # Index-aligned with `paths`, so a consumer can label the two
                # ends without re-deriving a scope from a path.
                scopes=[child["scope"], parent["scope"]],
                proposed_parent=parent["scope"],
            )
        )
    return sorted(out, key=lambda x: -x["score"]), considered, declared


def _ancestor_scope(parent: dict, child: dict) -> bool:
    """True when `parent`'s scope sits ABOVE `child`'s on the same ladder.

    `user-global` and `portfolio` are above every scope by construction — they
    are the two rungs every project scope hangs off. Anything else has to be a
    literal path prefix; sibling repos at equal or differing depth share no
    ladder, so no promotion between them is possible.
    """
    ps, cs = parent["scope"], child["scope"]
    if ps in ("user-global", "portfolio"):
        return True
    return cs.startswith(ps + "/")


def _embed_matrix(items, cache_path: Path):
    """Normalized embedding vectors for `items`, warmed through the disk cache.

    Hoisted out of `check_semantic_dupes` so the promotion pass can share both
    the cache file and the keying rules rather than re-implementing them. The
    cache is content-keyed, so two calls over overlapping item sets (rules are
    in both) cost one embedding each.

    numpy and fastembed are imported FUNCTION-LOCALLY, exactly as before:
    nothing in the cheap tier may pull them in.
    """
    import numpy as np
    from fastembed import TextEmbedding

    cache = {}
    if cache_path.is_file():
        try:
            cache = json.loads(cache_path.read_text())
        except (OSError, json.JSONDecodeError):
            cache = {}

    # The cache is keyed on a hash of the EMBED TEXT, not on it["hash"] (the raw
    # file bytes). A change to title/desc/body must self-invalidate: parsing a
    # `description:` that the bytes already contained changes the embedded text
    # without changing the file, so a bytes-keyed cache serves a vector computed
    # from the old text and the findings become cache-state dependent -- a cold
    # cache and a warm cache disagree on the same commit.
    #
    # it["hash"] is deliberately left alone: it keys the gitdates cache
    # (f"{path}:{hash}") and expires waivers (a_hash/b_hash), both of which mean
    # "the file's bytes", so folding desc into it would spuriously expire every
    # waiver and every cached git date.
    #
    # Entries keyed on a superseded embed text are never read again and become
    # dead weight in the cache file; the file is a cache, so pruning it is
    # deleting it.
    #
    # EMBED_MODEL is part of the key for the same reason the text is: it is an
    # input to the vector. Keyed on text alone, swapping the model served the
    # previous model's vectors and every cosine was then computed across two
    # embedding spaces -- the same defect one level up, and silent.
    embed_texts = [
        f"{it['title']}\n{it.get('desc', '')}\n{it['body'][:EMBED_CHARS]}"
        for it in items
    ]
    keys = [sha(f"{EMBED_MODEL}\n{t}") for t in embed_texts]
    need: dict[str, str] = {k: t for k, t in zip(keys, embed_texts) if k not in cache}
    if need:
        model = TextEmbedding(model_name=EMBED_MODEL)
        need_keys = list(need)
        for k, vec in zip(need_keys, model.embed([need[k] for k in need_keys])):
            cache[k] = [round(float(x), 6) for x in vec]
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(json.dumps(cache))

    vecs = np.array([cache[k] for k in keys], dtype="float32")
    vecs /= np.linalg.norm(vecs, axis=1, keepdims=True) + 1e-9
    return vecs


def cosine_sim_fn(items, cache_path: Path):
    """A `sim(a, b) -> float` callable over `items`, backed by the embed cache.

    The promotion pass filters on rank, ancestry and length BEFORE it needs a
    score, so a lazy per-pair dot product is both cheaper and smaller than the
    full N x N matrix `check_semantic_dupes` builds for its own exhaustive
    sweep. Rows are keyed by `id()` rather than by content hash: two documents
    in this corpus can be byte-identical (that is precisely the promotion shape
    being looked for), so a content hash is not a unique row key here.
    """
    vecs = _embed_matrix(items, cache_path)
    row = {id(it): i for i, it in enumerate(items)}

    def sim(a: dict, b: dict) -> float:
        return float(vecs[row[id(a)]] @ vecs[row[id(b)]])

    return sim


def fixture_sim_fn(fixture_path: Path):
    """A `sim(a, b)` callable reading precomputed scores from a JSON fixture.

    THE TEST SEAM, and the reason `check_promotion_candidates` takes a callable
    at all. `health-plugin/scripts/tests/test-config-drift.sh` is listed in
    `scripts/required-to-run-tests.txt`, where a SKIP is an ERROR; numpy and
    fastembed are absent from the system `python3` that both real callers
    invoke. Injecting the scores is what keeps the whole verdict -- the
    discriminator, the tie skip, scope ordering, the finding shape, the
    `--gate` interaction -- inside the stdlib tier instead of behind a model
    download.

    Format: `{"<hash-a>|<hash-b>": 0.93}`, where each hash is the document's
    `hash` field (`sha(body)`, 16 hex chars) and the two are sorted, so the
    caller need not know which side the scan will call parent. A missing pair
    scores 0.0 -- below every threshold, so an incomplete fixture under-reports
    rather than inventing a finding.

    Stdlib `json` only, and no module-scope import is added for it.
    """
    raw = json.loads(fixture_path.read_text())
    table = {k: float(v) for k, v in raw.items()}

    def sim(a: dict, b: dict) -> float:
        return table.get("|".join(sorted((a["hash"], b["hash"]))), 0.0)

    return sim


def check_semantic_dupes(items, waivers, cache_path: Path) -> list[Finding]:
    import numpy as np

    vecs = _embed_matrix(items, cache_path)
    sim = vecs @ vecs.T
    out = []
    for i, j in zip(*np.triu_indices(len(items), k=1)):
        s = float(sim[i, j])
        a, b = items[i], items[j]
        # Same-name pairs belong to the cheap tier (name-collision + lexical);
        # re-reporting them here would double-count every generated rule.
        if a["name"] == b["name"] or structural_pair(a, b):
            continue
        if s >= T_SEMANTIC and not waivers.waived(a, b):
            out.append(
                Finding(
                    "warn",
                    f"semantic_overlap_{a['kind']}_{b['kind']}",
                    (
                        f"{a['kind']} {a['name']} and {b['kind']} {b['name']} "
                        f"are {s:.0%} semantically similar"
                    ),
                    score=round(s, 3),
                    paths=[a["path"], b["path"]],
                )
            )
    return sorted(out, key=lambda x: -x["score"])


# ----------------------------------------------------------------- calibration
CALIBRATION_BANDS = (0.94, 0.92, 0.90, 0.88, 0.86)


def _band_histogram(scores) -> str:
    """The cumulative histogram spelling used by the T_SEMANTIC/T_PROMOTE comments.

    Cumulative, not per-bucket: `0.90:32` means "32 pairs at or above 0.90", so
    a reader picking a threshold reads the yield of that threshold directly off
    the row instead of summing buckets.
    """
    return " ".join(
        f"{b}:{sum(1 for s in scores if s >= b)}" for b in CALIBRATION_BANDS
    )


def emit_calibration(corpus, cache_path: Path, root: Path) -> None:
    """Dev-only: measure the promotion-band distribution over this root.

    Not wired into any caller and not part of any tier -- it is how T_PROMOTE
    was set, kept in the shipped file so the next person can re-derive the
    number instead of trusting the comment above it. Imports numpy/fastembed
    only through `_embed_matrix`, i.e. function-locally, exactly like
    `check_semantic_dupes`.

    Three bands per kind-pair, each one a strictly narrower predicate, so the
    contribution of every discriminator is visible rather than asserted:

    * RAW     -- every cross-scope, rank-strict pair of promotable kinds.
    * NOVEL   -- RAW minus same-name minus `structural_pair`. The same
                 definition the T_SEMANTIC comment uses, so the two constants'
                 calibrations are comparable.
    * SHIPPED -- what `check_promotion_candidates` actually emits: same-name
                 KEPT, `structural_pair` suppressed, ancestor-constrained,
                 `MIN_PROMOTABLE_CHARS`-floored.

    NOVEL is reported despite the shipped check not using it because it is the
    contrast that shows what keeping same-name pairs costs -- at this repo's
    root that difference is a single pair, and it is one `structural_pair`
    removes anyway.
    """
    docs = [d for k in PROMOTION_KINDS for d in corpus[k]]
    sim = cosine_sim_fn(docs, cache_path)

    raw: dict[str, list[float]] = {}
    novel: dict[str, list[float]] = {}
    shipped: dict[str, list[float]] = {}
    for a, b in combinations(docs, 2):
        ra, rb = a["scope_rank"], b["scope_rank"]
        if ra is None or rb is None or ra == rb:
            continue
        parent, child = (a, b) if ra < rb else (b, a)
        key = "_".join(sorted((a["kind"], b["kind"])))
        s = sim(child, parent)
        raw.setdefault(key, []).append(s)
        if a["name"] != b["name"] and not structural_pair(a, b):
            novel.setdefault(key, []).append(s)
        if (
            _ancestor_scope(parent, child)
            and min(child["chars"], parent["chars"]) >= MIN_PROMOTABLE_CHARS
            and not structural_pair(child, parent)
        ):
            shipped.setdefault(key, []).append(s)

    print("=== CONFIG DRIFT CALIBRATION ===")
    print(f"ROOT={root}")
    print(f"BANDS={' '.join(str(b) for b in CALIBRATION_BANDS)}")
    for kind in PROMOTION_KINDS:
        print(f"DOCS_{kind.upper()}={len(corpus[kind])}")
    print(f"PROMOTABLE_DOCS={len(docs)}")
    print(f"SCOPES={len({d['scope'] for d in docs})}")
    print(f"CROSS_SCOPE_PAIRS={sum(len(v) for v in raw.values())}")
    for label, table in (("RAW", raw), ("NOVEL", novel), ("SHIPPED", shipped)):
        for key in sorted(set(raw) | set(novel) | set(shipped)):
            scores = table.get(key, [])
            print(f"{label}_{key.upper()}={_band_histogram(scores)} n={len(scores)}")
        allscores = [s for v in table.values() for s in v]
        print(f"{label}_ALL={_band_histogram(allscores)} n={len(allscores)}")
    print(f"T_PROMOTE={T_PROMOTE}")
    print("=== END CONFIG DRIFT CALIBRATION ===")


# ---------------------------------------------------------------------- output
# Every renderer now lives in `lib.probe`. The local `emit_status` that used to
# sit here emitted neither the `ISSUE_COUNT=` roll-up nor the closing
# `=== END CONFIG DRIFT ===` delimiter that
# `.claude/rules/structured-script-output.md` marks required, so a rollup could
# not tell where this probe's block ended; `render_status` emits both, and its
# two keyword-only parameters carry the only differences between this caller and
# probe-delta's (see that function's docstring).
#
# `emit_probe` and the `--format=probe` choice were deleted here rather than
# ported: no caller invoked them. `hooks/config-drift-probe.sh` consumes
# `--format=json` and derives kind -> remediation-skill in jq, which is now the
# single source for that mapping rather than one of two copies.
def emit_status(findings, counts):
    # severity_prefix="": `findings` here is EVERY finding this run produced,
    # not a delta subset, so the counters keep the bare `ERRORS=`/`WARNINGS=`
    # names a rollup already greps for.
    # list_issues=False: the optional per-finding block would append one line
    # per finding, and a real corpus run reports 60+ of them.
    # What that costs the reader: `ISSUE_COUNT=` spans ALL THREE severities, so
    # it exceeds `ERRORS + WARNINGS` by however many `info` findings fired
    # (a real run: ERRORS=0 WARNINGS=60 ISSUE_COUNT=66 — one
    # frontmatter_coverage and five rule_covered_by_skill). Read as "actionable
    # issues" it over-counts, and with the ISSUES: block suppressed there is no
    # in-block way to see the split. `--format=json` is the machine-readable
    # answer to "which ones?".
    print(
        render_status(
            "CONFIG DRIFT", findings, counts, severity_prefix="", list_issues=False
        )
    )


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
    ap.add_argument("--format", choices=["status", "report", "json"], default="status")
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
    ap.add_argument(
        "--calibrate",
        action="store_true",
        help="dev-only: print the promotion-band distribution and exit. Needs the model.",
    )
    # Hidden: a TEST SEAM, not an operator flag. See `fixture_sim_fn`.
    ap.add_argument("--sim-fixture", help=argparse.SUPPRESS)
    args = ap.parse_args()

    root = Path(args.root).expanduser().resolve()
    if not root.is_dir():
        print(f"root not found: {root}", file=sys.stderr)
        return 3

    corpus, unreadable, templates_excluded, agent_dirs = collect(root)
    if args.calibrate:
        emit_calibration(corpus, Path(args.cache).expanduser(), root)
        return 0
    rules = corpus["rule"]
    skills = corpus["skill"]
    agents = corpus["agent"]
    claude_mds = corpus["claude_md"]
    waivers = Waivers.load(Path(args.waivers).expanduser())

    # The check x kind matrix, guarded explicitly at every call site. Each
    # check's own docstring carries the reason it takes the kinds it takes.
    findings: list[Finding] = []
    findings += check_stub_integrity(rules, skills)
    findings += check_budget(rules + claude_mds)
    lexical, lexical_pairs = check_lexical_dupes(corpus, waivers)
    findings += lexical
    findings += check_rule_covered_by_skill(rules, skills, waivers)
    findings += check_frontmatter(rules)
    findings += check_corpus_unreadable(unreadable)
    findings += check_agent_discovery_misfire(agents, agent_dirs)

    datecache_path = Path(args.cache).expanduser().with_name("gitdates.json")
    datecache: dict = {}
    if datecache_path.is_file():
        try:
            datecache = json.loads(datecache_path.read_text())
        except (OSError, json.JSONDecodeError):
            datecache = {}
    before = len(datecache)
    # Staleness applies to every kind unchanged. Agents earn it: 21 of 21 carry
    # both `reviewed:` and `modified:`, and they are in-repo so `git_last_change`
    # resolves. CLAUDE.md is included on the same terms even though it will
    # almost never fire -- the check is a no-op for a document with no
    # `reviewed:` date, so excluding it would buy nothing and would have to be
    # revisited the moment one gained a date.
    findings += check_review_staleness(
        rules + skills + agents + claude_mds, datecache, allow_spawn=not args.fast
    )
    if len(datecache) != before:
        datecache_path.parent.mkdir(parents=True, exist_ok=True)
        datecache_path.write_text(json.dumps(datecache))

    # The two promotion counters are emitted ONLY when the promotion pass ran.
    # `even at 0` means "ran and found none"; ABSENT means "did not run", and
    # the cheap tier must keep saying the second. A `PROMOTION_PAIRS_CONSIDERED=0`
    # printed by `--fast --no-embed` would read as a clean promotable corpus
    # scanned, which is the false all-clear the counter exists to prevent -- the
    # same distinction `SEMANTIC_PASS=off` already draws for its own tier.
    promotion_counts: dict[str, int] = {}
    promotable = [d for k in PROMOTION_KINDS for d in corpus[k]]

    if args.sim_fixture:
        # Test seam. The similarity is injected, so the promotion verdict runs
        # in the stdlib tier with no model; `check_semantic_dupes` is untouched
        # and still obeys --no-embed.
        promo, considered, declared = check_promotion_candidates(
            promotable, fixture_sim_fn(Path(args.sim_fixture).expanduser()), waivers
        )
        findings += promo
        promotion_counts = {
            "promotion_pairs_considered": considered,
            "hierarchies_declared": declared,
        }

    if not args.no_embed:
        try:
            # SEMANTIC_KINDS, not `rules + skills` spelled out: the exclusion of
            # agents and CLAUDE.md is a calibration decision (see the constant),
            # and it has to be readable from the constant rather than inferred
            # from which lists happen to be concatenated here.
            findings += check_semantic_dupes(
                [d for k in SEMANTIC_KINDS for d in corpus[k]],
                waivers,
                Path(args.cache).expanduser(),
            )
            # PROMOTION_KINDS is a DIFFERENT set from SEMANTIC_KINDS, so this is
            # a second embedding pass rather than a filter over the first. It is
            # not a second embedding COST: the cache is keyed on the embed text,
            # so every rule is already warm from the call above and only the
            # CLAUDE.md vectors are new.
            if not args.sim_fixture:
                promo, considered, declared = check_promotion_candidates(
                    promotable,
                    cosine_sim_fn(promotable, Path(args.cache).expanduser()),
                    waivers,
                )
                findings += promo
                promotion_counts = {
                    "promotion_pairs_considered": considered,
                    "hierarchies_declared": declared,
                }
        except Exception as exc:  # noqa: BLE001 - degrade loudly, never silently
            findings.append(
                Finding(
                    "info",
                    "semantic_pass_unavailable",
                    f"semantic pass skipped: {type(exc).__name__}: {exc}",
                )
            )

    if args.since:
        # KNOWN AND ACCEPTED: `--since` can never surface a finding about
        # `~/.claude/rules`. `HOME_RULES` is scanned regardless of `--root`
        # (those rules load in every session), but `changed_since` walks only
        # `root.rglob(".git")` plus `root` — a home-rule path is outside every
        # repo it asks, so it can never enter `touched`, and every home-rule
        # finding is dropped here. Before the finding-shape normalisation the
        # two singular-`path` kinds escaped through the `not f.get("paths")`
        # arm by accident; now they are filtered like everything else, which is
        # the CONSISTENT behaviour, not a new bug.
        #
        # Left as-is deliberately. `--since` means "findings whose files
        # changed in this git range", and a home rule is not in the range — it
        # is not in a repo at all. Making it an exception would mean either
        # re-admitting pathless findings (which is the bug that was just fixed)
        # or special-casing HOME_RULES to "always touched", which reports a
        # standing condition as a change and defeats the flag. The cost is
        # real and worth naming: the always-loaded home rules are the
        # highest-value slice of the corpus (51 rules, ~39k tok/turn on this
        # machine), and `--since` is structurally blind to them. No caller
        # passes `--since` today; the flag is for a reviewer scoping a diff,
        # who has the unfiltered run available. Pinned by `test-probe-lib.sh`
        # TEST N6 so this is a recorded decision, not a drift.
        touched = changed_since(root, args.since)
        findings = [
            f
            for f in findings
            if not f.get("paths") or any(p in touched for p in f["paths"])
        ]

    always = always_loaded_docs(rules + claude_mds)
    counts = {
        "rules": len(rules),
        "skills": len(skills),
        "agents": len(agents),
        # The DENOMINATOR for AGENTS, emitted EVEN AT 0 for the same reason the
        # exclusion counter below is. `AGENTS=0` alone cannot distinguish "this
        # tree has no agents" from "discovery misfired" -- which is exactly the
        # state the depth-anchored glob left `~/repos` in. `AGENTS=0` beside
        # `AGENT_DIRS=8` reads as a misfire on sight, `AGENTS=0` beside
        # `AGENT_DIRS=0` reads as a clean tree, and
        # `check_agent_discovery_misfire` turns the first pair into a finding.
        # Plugin directories would be the WRONG denominator: most plugins define
        # no agents, so most trees would read as a misfire.
        "agent_dirs": agent_dirs,
        "claude_mds": len(claude_mds),
        # Emitted EVEN AT 0. An exclusion that reports nothing is
        # indistinguishable from a collector that stopped finding anything to
        # exclude -- and from one that stopped finding CLAUDE.md at all.
        "claude_md_templates_excluded": templates_excluded,
        # Rules only, deliberately: this is the scope LADDER's width, and skills
        # and agents are namespaced by plugin rather than scoped.
        "scopes": len({r["scope"] for r in rules}),
        # Split by kind rather than merged, so the CLAUDE.md the budget newly
        # includes is visible as its own line instead of an unexplained jump in
        # ALWAYS_LOADED_TOKENS.
        "always_loaded_rules": sum(1 for d in always if d["kind"] == "rule"),
        "always_loaded_claude_md": sum(1 for d in always if d["kind"] == "claude_md"),
        "always_loaded_tokens": sum(d["chars"] for d in always) // 4,
        "pointer_stubs": sum(1 for r in rules if r["stub"]),
        # Makes the lexical partition assertable: pooled it would be
        # N(N-1)/2 over every kind, partitioned it is the sum of each kind's own
        # n(n-1)/2.
        "lexical_pairs": lexical_pairs,
        "waivers_active": len(waivers),
        "semantic_pass": "off" if args.no_embed else "on",
        # Present only when the promotion pass ran -- see the comment above
        # `promotion_counts`. PROMOTION_PAIRS_CONSIDERED is the pair UNIVERSE
        # (both kinds promotable, neither rank None), counted BEFORE the tie
        # skip and every suppression, so a suppression test's "0 findings" has
        # a denominator that proves the check opened a corpus.
        # HIERARCHIES_DECLARED counts pairs that cleared T_PROMOTE and were then
        # suppressed by `structural_pair` -- i.e. findings that were withheld,
        # not pairs that were merely looked at. It is exactly that one
        # suppressor's yield: a hierarchy declared in a THIRD document is
        # invisible to it and is NOT counted here (see
        # `check_promotion_candidates`, KNOWN LIMITATION).
        **promotion_counts,
    }

    {
        "status": emit_status,
        # The timestamp is computed HERE, not inside the renderer: nothing in
        # lib.probe reads a clock, which is what lets a renderer be compared
        # against itself across two runs.
        "report": lambda f, c: print(
            render_report(f, c, dt.datetime.now().isoformat(timespec="seconds"))
        ),
        "json": lambda f, c: print(render_json(f, c, indent=1)),
    }[args.format](findings, counts)

    errs = sum(1 for f in findings if f["severity"] == "error")
    if args.gate and errs:
        return 2
    return 1 if any(f["severity"] in ("error", "warn") for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Resolve the two cross-reference shapes skill prose relies on.

Two guards, one heading parser:

  citations  `<target> § <Heading>` — a section citation. The cited heading
             must exist in the cited document. Targets: a plugin-qualified
             skill ID (`plugin:skill`), a bare skill name (`skill-name`), a
             link (`[..](path)`), a markdown path (`REFERENCE.md`,
             `references/x.md`, `.claude/rules/x.md`), or a slash command
             (`/name`). A skill target searches SKILL.md, REFERENCE*.md and
             references/*.md. An untargeted `§ Heading` cites the citing file
             itself (and, inside a skill, that skill's other files).
  links      every relative markdown link `[..](path#anchor)` must resolve to
             a file or directory, and an `#anchor` on a .md target must match a
             heading slug there (GitHub rules: lowercase, punctuation dropped,
             each space a hyphen, `-N` suffix on duplicates).

Why: the 2026-10 SKILL.md split sweep moved prose into references/ files, and
three skills cite `parallel-agent-dispatch` sections ("§Shared-File Exclusion
List", "§Pre-Allocated Blueprint IDs", "§Wave Splits") that never existed as
headings. A link two directories too shallow (`../../.claude/rules/...` from a
skill dir) resolved inside the plugin. Nothing failed: a dead citation reads
exactly like a live one.

MATCHING (citations) is a two-way token PREFIX match, not exact. Both sides
are reduced to lowercase word tokens. The citation resolves when some heading's
tokens are a prefix of the cited tokens (the heading is cited whole and prose
follows: "§ Signal design (at the end)") or the cited tokens are a prefix of a
heading's (the citation abbreviates: "§ Cleanup" for "Cleanup: never
force-remove worktrees you don't own"). Exact matching was rejected after
reading the corpus: unquoted citations run straight into prose, and ~40 live
citations abbreviate. Each heading is also tried without its "N." numbering,
without parentheticals, and as either side of a colon or dash ("§ Scope
Budget" for "2. Scope Budget (per-agent prompt rules)"; "§ a check that never
ran" for "The trap under all four: a check that never ran …"). A numeric
citation (`§3`, `§ 2`) matches a heading numbered exactly that. Unquoted
citation text ends at the first of `| ( ) ] ; , — – → / .<space>` or the next
`§`; a quoted (`"…"`) or italic (`*…*`) citation is taken whole.

Only HEADINGS are citable. A bold-led paragraph (`**Pre-allocated IDs.** …`)
has no anchor and no TOC entry; cite its containing heading and name the
paragraph in parentheses: `§ Scope Budget ("Pre-allocated IDs")`.

UNTARGETED `§ Heading` resolves against the citing file, then (inside a skill)
the skill's other files, then any target named in backticks earlier in the
same section (a table of `§` rows under "defined in `skill-x`:"). An untargeted
NUMERIC citation where none of those files has numbered headings ("LICENSE
§V.4", "report §5 F2") is external.

SKIPPED, by design (counted in CITATIONS_EXTERNAL=):
  * a citation whose target is not in this repo — an out-of-repo rule
    (`~/.claude/rules/…`), a non-markdown file (`LICENSE`), a URL, a directory
  * a `§` inside link text (`[x.md § H](url)`) — the link guard owns the anchor
  * a `§` inside an inline code span with no target in the same span (`§N`)
  * an untargeted citation directly after "system card" (an external PDF)

COVERAGE. Every .md file inside a skill directory (`<plugin>/skills/<name>/`,
`.claude/skills/<name>/`), plugin agents (`<plugin>/agents/*.md`) and
`.claude/rules/*.md`. Fenced code blocks are skipped in both guards: a link or
citation there is an example. Out of scope: docs/** (immutable records),
CHANGELOG.md, test fixtures under a skill's scripts/.

Fence detection comes from scripts/lib/extract-md-elements.py (tree-sitter,
run via `uv`), never a hand-rolled ``` toggle (#2009). An unreadable
(non-UTF-8) scan file is a finding, not a silent skip.

Usage:
  check-skill-xrefs.py [--project-dir DIR] [--only citations|links]
  CHECK_SKILL_XREFS_TRACE=1 check-skill-xrefs.py   # one stderr line per citation

Output: KEY=VALUE per .claude/rules/structured-script-output.md.
Exit: 0 every reference resolves, 1 a dead reference or an empty scan,
      2 usage error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.parse
from dataclasses import dataclass, field
from pathlib import Path

PRUNE_DIRS = {"node_modules", "__pycache__"}
HELPER = Path(__file__).resolve().parent / "lib" / "extract-md-elements.py"
# path -> 1-based line numbers inside a fenced code block (delimiters included)
FENCED: dict[Path, set[int]] = {}
ATX_RE = re.compile(r"^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$")
HTML_ANCHOR_RE = re.compile(
    r"""<a\s+(?:[^>]*?\s)?(?:id|name)=["']([^"']+)["']""", re.IGNORECASE
)
INLINE_LINK_RE = re.compile(
    r"(!?)\[((?:[^\[\]]|\[[^\[\]]*\])*)\]\(\s*<?([^)\s>]*)>?(?:\s+[\"'][^)]*[\"'])?\s*\)"
)
REF_DEF_RE = re.compile(r"^\s{0,3}\[([^\]]+)\]:\s*<?(\S+?)>?(?:\s+.*)?$")
SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")
TOKEN_RE = re.compile(r"[^\W_]+", re.UNICODE)

# Citation-text terminators for the unquoted form.
TERMINATORS = re.compile(
    r"\||\(|\)|\]|;|,|—|–|→|\s/\s|§|¶|\.(?=\s|$)|\?(?=\s|$)|!(?=\s|$)"
)
MAX_TOKENS = 14


# --------------------------------------------------------------------------
# Markdown helpers
# --------------------------------------------------------------------------

UNREADABLE: set[Path] = set()


def read_lines(path: Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        UNREADABLE.add(path.resolve())
        return []


def unreadable_findings(repo: Repo) -> list[Finding]:
    return [
        Finding(
            repo.rel(p),
            1,
            "unreadable-file",
            "not valid UTF-8 -- nothing in it was checked",
        )
        for p in sorted(UNREADABLE)
        if p in {f.resolve() for f in repo.scan_files}
    ]


def strip_frontmatter(lines: list[str]) -> int:
    """Return the index of the first body line (after a leading --- block)."""
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return i + 1
    return 0


def load_fences(files: list[Path]) -> None:
    """Fence line ranges from the shared tree-sitter helper (#2009), not a toggle."""
    todo = [f for f in files if f.resolve() not in FENCED]
    if not todo:
        return
    proc = subprocess.run(
        [
            "uv",
            "run",
            "--quiet",
            "--script",
            str(HELPER),
            "--format",
            "json",
            "--types",
            "fence",
            "--files-from",
            "-",
        ],
        input="\n".join(str(f.resolve()) for f in todo),
        capture_output=True,
        text=True,
        check=False,  # a failed parse is reported below, not raised
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        raise SystemExit(
            "check-skill-xrefs.py: scripts/lib/extract-md-elements.py failed (needs uv)"
        )
    for f in todo:
        FENCED.setdefault(f.resolve(), set())
    for row in proc.stdout.splitlines():
        rec = json.loads(row)
        FENCED.setdefault(Path(rec["file"]).resolve(), set()).update(
            range(rec["start_line"], rec["end_line"] + 1)
        )


def prose_lines(path: Path, lines: list[str]) -> list[tuple[int, str]]:
    """(1-based line number, text) for every body line outside fenced code."""
    load_fences([path])
    fenced = FENCED[path.resolve()]
    return [
        (i + 1, lines[i])
        for i in range(strip_frontmatter(lines), len(lines))
        if i + 1 not in fenced
    ]


def render_heading(text: str) -> str:
    """Approximate GitHub's rendered heading text: drop markup, keep words."""
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)  # links -> text
    text = re.sub(r"<[^>]+>", "", text)  # inline HTML
    return text.replace("`", "").replace("*", "")


def github_slug(text: str) -> str:
    slug = render_heading(text).strip().lower()
    slug = re.sub(r"[^\w\- ]", "", slug, flags=re.UNICODE)
    return slug.replace(" ", "-")


def tokens(text: str) -> list[str]:
    return TOKEN_RE.findall(render_heading(text).lower())


@dataclass
class Doc:
    headings: list[str] = field(default_factory=list)
    slugs: set[str] = field(default_factory=set)


_DOC_CACHE: dict[Path, Doc] = {}


def load_doc(path: Path) -> Doc:
    path = path.resolve()
    if path in _DOC_CACHE:
        return _DOC_CACHE[path]
    doc = Doc()
    lines = read_lines(path)
    body = prose_lines(path, lines)
    seen: dict[str, int] = {}

    def add(text: str) -> None:
        doc.headings.append(text)
        base = github_slug(text)
        n = seen.get(base, 0)
        doc.slugs.add(base if n == 0 else f"{base}-{n}")
        seen[base] = n + 1

    prev = ""
    for _, line in body:
        m = ATX_RE.match(line)
        if m:
            add(m.group(2))
        elif (
            prev.strip()
            and re.match(r"^\s{0,3}(=+|-+)\s*$", line)
            and not re.match(r"^\s*([-*+]|\d+[.)]|\||>)", prev)
        ):
            add(prev.strip())  # setext heading
        for a in HTML_ANCHOR_RE.findall(line):
            doc.slugs.add(a)
        prev = line
    _DOC_CACHE[path] = doc
    return doc


def code_spans(line: str) -> list[tuple[int, int]]:
    """Character ranges [start, end) covered by inline code spans."""
    spans: list[tuple[int, int]] = []
    i = 0
    while i < len(line):
        if line[i] == "`":
            j = i
            while j < len(line) and line[j] == "`":
                j += 1
            ticks = line[i:j]
            close = line.find(ticks, j)
            while (
                close != -1
                and close + len(ticks) < len(line)
                and line[close + len(ticks)] == "`"
            ):
                close = line.find(ticks, close + len(ticks) + 1)
            if close == -1:
                i = j
                continue
            spans.append((i, close + len(ticks)))
            i = close + len(ticks)
        else:
            i += 1
    return spans


def in_spans(pos: int, spans: list[tuple[int, int]]) -> tuple[int, int] | None:
    for s, e in spans:
        if s <= pos < e:
            return (s, e)
    return None


# --------------------------------------------------------------------------
# Repository model
# --------------------------------------------------------------------------


class Repo:
    def __init__(self, root: Path):
        self.root = root
        self.skill_dirs: dict[str, Path] = {}  # "plugin:skill" -> dir
        self.by_name: dict[str, list[Path]] = {}  # "skill" -> dirs
        self.scan_files: list[Path] = []
        self._discover()

    def _walk(self, base: Path):
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in PRUNE_DIRS]
            yield Path(dirpath), filenames

    def _discover(self) -> None:
        root = self.root
        for child in sorted(root.iterdir()) if root.is_dir() else []:
            skills = child / "skills"
            if not child.name.endswith("-plugin") or not skills.is_dir():
                continue
            for sd in sorted(skills.iterdir()):
                if (sd / "SKILL.md").is_file():
                    self.skill_dirs[f"{child.name}:{sd.name}"] = sd
                    self.by_name.setdefault(sd.name, []).append(sd)
        local = root / ".claude" / "skills"
        if local.is_dir():
            for sd in sorted(local.iterdir()):
                if (sd / "SKILL.md").is_file():
                    self.by_name.setdefault(sd.name, []).append(sd)

        files: list[Path] = []
        for sd in list(self.skill_dirs.values()) + [
            d for ds in self.by_name.values() for d in ds if d.parent == local
        ]:
            for dirpath, filenames in self._walk(sd):
                rel = dirpath.relative_to(sd).parts
                if rel and rel[0] == "scripts":
                    continue  # test fixtures, not skill prose
                for fn in filenames:
                    if fn.endswith(".md") and fn != "CHANGELOG.md":
                        files.append(dirpath / fn)
        for child in sorted(root.iterdir()) if root.is_dir() else []:
            agents = child / "agents"
            if child.name.endswith("-plugin") and agents.is_dir():
                files.extend(sorted(agents.glob("*.md")))
        rules = root / ".claude" / "rules"
        if rules.is_dir():
            files.extend(sorted(rules.glob("*.md")))
        self.scan_files = sorted(set(files))
        load_fences(self.scan_files)

    def skill_of(self, path: Path) -> Path | None:
        for parent in path.parents:
            if (parent / "SKILL.md").is_file() and parent.parent.name == "skills":
                return parent
        return None

    @staticmethod
    def skill_docs(skill_dir: Path) -> list[Path]:
        docs = [skill_dir / "SKILL.md"]
        docs += sorted(skill_dir.glob("REFERENCE*.md"))
        docs += sorted((skill_dir / "references").glob("*.md"))
        return [d for d in docs if d.is_file()]

    def rel(self, path: Path) -> str:
        try:
            return str(path.resolve().relative_to(self.root))
        except ValueError:
            return str(path)


# --------------------------------------------------------------------------
# Guard 1: section citations
# --------------------------------------------------------------------------

ID_RE = re.compile(r"^([a-z][a-z0-9-]*-plugin):([a-z0-9-]+)$")
MD_PATH_RE = re.compile(r"^[~.\w/@-]*[\w-]+\.md$")
GENERIC_DOCS = {"CLAUDE.md", "README.md", "AGENTS.md", "CONTRIBUTING.md"}


@dataclass
class Target:
    kind: str  # "files" | "external"
    files: list[Path] = field(default_factory=list)
    label: str = ""


def resolve_path_token(repo: Repo, src: Path, token: str) -> Target:
    token = token.strip()
    if token.startswith(("~", "/")):
        return Target("external", label=token)
    skill = repo.skill_of(src)
    local = [src.parent] + ([skill] if skill is not None else [])
    for base in local:
        cand = (base / token).resolve()
        if cand.is_file():
            return Target("files", [cand], repo.rel(cand))
    # A plugin skill's bare `CLAUDE.md` / `README.md` is the CONSUMER project's
    # file, not this repo's root one.
    if (
        "/" not in token
        and token in GENERIC_DOCS
        and repo.rel(src).split("/")[0].endswith("-plugin")
    ):
        return Target("external", label=token)
    for base in (repo.root, repo.root / ".claude" / "rules"):
        cand = (base / token).resolve()
        if cand.is_file():
            return Target("files", [cand], repo.rel(cand))
    return Target("external", label=token)


def resolve_token(
    repo: Repo, src: Path, token: str, prev: Target | None
) -> Target | None:
    """Turn the thing written before `§` into a Target, or None if not a target."""
    token = token.strip().strip("`").strip()
    if not token:
        return None
    m = ID_RE.match(token)
    if m:
        sd = repo.skill_dirs.get(token)
        if sd is None:
            return Target(
                "external", label=token
            )  # dead IDs are check-skill-references.sh's job
        return Target("files", repo.skill_docs(sd), token)
    if token.startswith("/") and re.fullmatch(r"/[a-z0-9-]+(:[a-z0-9-]+)?", token):
        name = token[1:].split(":")[-1]
        dirs = repo.by_name.get(name, [])
        if len(dirs) == 1:
            return Target("files", repo.skill_docs(dirs[0]), token)
        return Target("external", label=token)
    if MD_PATH_RE.match(token):
        # `references/x.md` after a `plugin:skill` target resolves inside it.
        if (
            prev is not None
            and prev.kind == "files"
            and prev.files
            and not token.startswith(".")
        ):
            sd = repo.skill_of(prev.files[0])
            if sd is not None and (sd / token).is_file():
                return Target(
                    "files", [(sd / token).resolve()], f"{prev.label} {token}"
                )
        t = resolve_path_token(repo, src, token)
        if t.kind == "external" and re.match(
            r"^(references/|REFERENCE[\w-]*\.md$|SKILL\.md$)", token
        ):
            return None  # "its `references/x.md`": skill-relative, owner named earlier
        return t
    if re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)+", token):
        dirs = repo.by_name.get(token, [])
        if len(dirs) == 1:
            return Target("files", repo.skill_docs(dirs[0]), token)
    return None


@dataclass
class Finding:
    file: str
    line: int
    kind: str
    msg: str


def joined_text(body: list[tuple[int, str]]) -> tuple[str, list[int]]:
    """Join prose lines with spaces (blank lines become a ¶ break)."""
    chars: list[str] = []
    line_of: list[int] = []
    for lineno, line in body:
        # ¶ marks a paragraph break, ⁋ a heading (a section start).
        text = (
            "⁋ " + line if ATX_RE.match(line) else line if line.strip() else "¶"
        ) + " "
        chars.append(text)
        line_of.extend([lineno] * len(text))
    return "".join(chars), line_of


def cited_text(text: str, start: int) -> str:
    rest = text[start : start + 400].lstrip()
    m = re.match(r'^(\*{0,2})["“]([^"”]+)["”]', rest)
    if m:
        return m.group(2)
    m = re.match(r"^\*([^*]+)\*", rest)
    if m:
        return m.group(1)
    rest = rest.lstrip("*")
    cut = TERMINATORS.search(rest)
    return rest[: cut.start()] if cut else rest


SKIP = Target("external", label="skip")


def preceding_target(
    repo: Repo,
    src: Path,
    text: str,
    pos: int,
    last_target: Target | None,
    last_end: int,
) -> Target | None:
    """What the `§` at pos cites: a Target, SKIP (not checkable), or None (untargeted)."""
    stripped = text[max(0, pos - 300) : pos].rstrip()

    # Chained: "§ A / § B", "§ A and § B", "§ A, § B" inherit the previous target.
    if last_target is not None and pos - last_end < 200:
        between = text[last_end:pos]
        if re.fullmatch(
            r"[^§¶]{0,120}?(?:\s/\s*|\s+and\s+|,\s*|\s+or\s+|;\s*)", between
        ):
            return last_target

    # "`.claude/rules/x.md` (§ Heading)" — the target sits outside the paren.
    if stripped.endswith("("):
        stripped = stripped[:-1].rstrip()

    # A link immediately before: [..](path) §
    m = re.search(r"\]\(\s*<?([^)\s>]*)>?\)\s*$", stripped)
    if m:
        href = m.group(1)
        if SCHEME_RE.match(href) or href.startswith("#"):
            return SKIP
        cand = (src.parent / urllib.parse.unquote(href.split("#", 1)[0])).resolve()
        if cand.is_file() and cand.suffix == ".md":
            return Target("files", [cand], repo.rel(cand))
        return SKIP

    # One or two code spans / bare tokens immediately before.
    pair = re.search(r"(`[^`]+`|[\w./:@~-]+)\s*(`[^`]+`|[\w./:@~-]+)\s*$", stripped)
    tail = re.search(r"(`[^`]+`|[\w./:@~-]+)\s*$", stripped)
    if tail is None:
        return None
    last_tok = tail.group(1)
    if pair is not None:
        prev_t = resolve_token(repo, src, pair.group(1), None)
        if prev_t is not None:
            t = resolve_token(repo, src, last_tok, prev_t)
            if t is not None:
                return t
    t = resolve_token(repo, src, last_tok, None)
    if t is not None:
        return t
    if last_tok.startswith("`") and not re.match(
        r"^`(references/|REFERENCE[\w-]*\.md`|SKILL\.md`)", last_tok
    ):
        return SKIP  # a code span that names no checkable target (`LICENSE`)
    if re.search(r"system\s+card\s*$", stripped, re.IGNORECASE):
        return SKIP  # an external PDF
    return None


def heading_variants(heading: str) -> list[list[str]]:
    """Token lists a citation may legitimately match: whole, sans "N." numbering,
    sans (…), and either side of a colon or dash."""
    variants = {
        heading,
        re.sub(r"^\s*(?:\d+(?:\.\d+)*\.?|Step\s+\d+[a-z]?:)\s+", "", heading),
    }
    variants |= {re.sub(r"\s*\([^)]*\)", "", v) for v in variants}
    for sep in (":", " — ", " – ", " - "):
        for v in list(variants):
            if sep in v:
                head, tail = v.split(sep, 1)
                variants |= {
                    head,
                    tail,
                }  # "Cleanup: never…" and "The trap: a check that never ran"
    return [t for t in (tokens(v) for v in variants) if t]


def heading_number(heading: str) -> str | None:
    m = re.match(
        r"^\s*(?:§\s*)?((?:\d+|[IVX]+)(?:\.\d+)*)\.?(?:\s|$)", render_heading(heading)
    )
    return m.group(1) if m else None


def cited_number(raw: str) -> str | None:
    m = re.match(r"^\s*((?:\d+|[IVX]+)(?:\.\d+)*)(?![\w.])", raw.replace("*", ""))
    if m and re.search(r"\d", m.group(1)):
        return m.group(1)
    return None


def heading_matches(raw: str, cite: list[str], headings: list[str]) -> bool:
    num = cited_number(raw)
    if num is not None:
        return any(heading_number(h) == num for h in headings)
    for h in headings:
        for ht in heading_variants(h):
            if cite[: len(ht)] == ht or ht[: len(cite)] == cite:
                return True
    return False


def paragraph_targets(repo: Repo, src: Path, text: str, pos: int) -> list[Target]:
    """Explicit targets named earlier in the same section, nearest first.

    Covers "`skill` — intra-wave contract; the §A and §B sections apply" and a
    table of bare `§ Heading` rows under a paragraph that names the owner.
    """
    start = text.rfind("⁋", 0, pos) + 1
    out: list[Target] = []
    for m in reversed(list(re.finditer(r"`([^`]+)`", text[start:pos]))):
        t = resolve_token(repo, src, m.group(1), None)
        if t is not None and t.kind == "files":
            out.append(t)
    return out


def self_target(repo: Repo, src: Path) -> Target:
    skill = repo.skill_of(src)
    files = [src.resolve()]
    if skill is not None:
        files += [
            d.resolve() for d in repo.skill_docs(skill) if d.resolve() != src.resolve()
        ]
    return Target("files", files, "this file" + (" or its skill" if skill else ""))


def check_citations(repo: Repo) -> tuple[list[Finding], dict[str, int]]:
    findings: list[Finding] = []
    stats = {"scanned": 0, "external": 0}
    for src in repo.scan_files:
        text, line_of = joined_text(prose_lines(src, read_lines(src)))
        link_text_spans = [
            (m.start(2), m.end(2)) for m in INLINE_LINK_RE.finditer(text)
        ]
        spans = code_spans(text)
        last_target: Target | None = None
        last_end = -10_000
        for m in re.finditer("§", text):
            pos = m.start()
            if in_spans(pos, link_text_spans):
                stats["external"] += 1  # `[x.md § H](url)`: the link guard owns it
                continue
            span = in_spans(pos, spans)
            if span is not None:
                inner = text[span[0] : pos].strip("` ")
                tgt = (
                    resolve_token(repo, src, inner.split()[-1], None) if inner else None
                )
                if tgt is None:
                    continue  # `§N` in code: an example, not a citation
                raw = cited_text(text[pos + 1 : span[1]].rstrip("`"), 0)
            else:
                tgt = preceding_target(repo, src, text, pos, last_target, last_end)
                raw = cited_text(text, pos + 1)
            cite = tokens(raw)[:MAX_TOKENS]
            last_end = pos + 1 + len(raw)
            if tgt is SKIP or (tgt is not None and tgt.kind == "external") or not cite:
                stats["external"] += 1
                last_target = SKIP
                continue
            untargeted = tgt is None
            if untargeted:
                tgt = self_target(repo, src)
                headings = [h for f in tgt.files for h in load_doc(f).headings]
                if cited_number(raw) is not None and not any(
                    heading_number(h) for h in headings
                ):
                    stats["external"] += (
                        1  # "LICENSE §V.4", "report §5" — no numbered sections here
                    )
                    last_target = SKIP
                    continue
            stats["scanned"] += 1
            headings = [h for f in tgt.files for h in load_doc(f).headings]
            ok = heading_matches(raw, cite, headings)
            if not ok and untargeted:
                for alt in paragraph_targets(repo, src, text, pos):
                    if heading_matches(
                        raw, cite, [h for f in alt.files for h in load_doc(f).headings]
                    ):
                        ok, tgt = True, alt
                        break
            if os.environ.get("CHECK_SKILL_XREFS_TRACE"):
                print(
                    f"TRACE {'ok ' if ok else 'BAD'} {repo.rel(src)}:{line_of[pos]} "
                    f"§ {raw.strip()[:60]!r} -> {tgt.label}",
                    file=sys.stderr,
                )
            if not ok:
                findings.append(
                    Finding(
                        repo.rel(src),
                        line_of[pos],
                        "dead-section-citation",
                        f"§ {raw.strip()[:80]!r} matches no heading in {tgt.label}",
                    )
                )
            last_target = tgt
    return findings, stats


# --------------------------------------------------------------------------
# Guard 2: relative links
# --------------------------------------------------------------------------


def check_links(repo: Repo) -> tuple[list[Finding], dict[str, int]]:
    findings: list[Finding] = []
    stats = {"scanned": 0}
    for src in repo.scan_files:
        for lineno, line in prose_lines(src, read_lines(src)):
            spans = code_spans(line)
            hrefs: list[str] = []
            for m in INLINE_LINK_RE.finditer(line):
                if in_spans(m.start(), spans):
                    continue
                hrefs.append(m.group(3))
            m = REF_DEF_RE.match(line)
            if m:
                hrefs.append(m.group(2))
            for href in hrefs:
                if not href or SCHEME_RE.match(href) or href.startswith("//"):
                    continue
                if any(c in href for c in "{}$<>*") or "..." in href:
                    continue  # templated placeholder, not a link
                stats["scanned"] += 1
                path_part, _, anchor = href.partition("#")
                path_part = urllib.parse.unquote(path_part)
                if path_part:
                    base = repo.root if path_part.startswith("/") else src.parent
                    target = (base / path_part.lstrip("/")).resolve()
                    if not target.exists():
                        findings.append(
                            Finding(
                                repo.rel(src),
                                lineno,
                                "dead-relative-link",
                                f"{href} does not exist (resolves to {target_rel(repo, target)})",
                            )
                        )
                        continue
                else:
                    target = src.resolve()
                if anchor and target.is_file() and target.suffix == ".md":
                    slug = urllib.parse.unquote(anchor).lower()
                    if slug not in load_doc(target).slugs:
                        findings.append(
                            Finding(
                                repo.rel(src),
                                lineno,
                                "dead-link-anchor",
                                f"{href}: no heading in {repo.rel(target)} slugs to #{anchor}",
                            )
                        )
    return findings, stats


def target_rel(repo: Repo, target: Path) -> str:
    try:
        return str(target.relative_to(repo.root))
    except ValueError:
        return f"{target} (outside the repo)"


# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------


def emit(
    section: str, kv: dict[str, object], findings: list[Finding], error: str | None
) -> None:
    print(f"=== {section} ===")
    for k, v in kv.items():
        print(f"{k}={v}")
    if error:
        print("STATUS=ERROR")
        print(f"REASON={error[:190]}")
        print("ISSUE_COUNT=1")
        print("ISSUES:")
        print(f"  - SEVERITY=ERROR TYPE=empty-scan MSG={error}")
    elif findings:
        first = findings[0]
        more = f" (+{len(findings) - 1} more)" if len(findings) > 1 else ""
        reason = (
            re.sub(r"\s+", " ", f"{first.kind}: {first.file}:{first.line} {first.msg}")[
                :180
            ]
            + more
        )
        print("STATUS=ERROR")
        print(f"REASON={reason}")
        print(f"ISSUE_COUNT={len(findings)}")
        print("ISSUES:")
        for f in findings:
            print(
                f"  - SEVERITY=ERROR TYPE={f.kind} FILE={f.file}:{f.line} MSG={f.msg}"
            )
    else:
        print("STATUS=OK")
        print("ISSUE_COUNT=0")
    print(f"=== END {section} ===")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--project-dir", default=None)
    ap.add_argument("--only", choices=["citations", "links"], default=None)
    args = ap.parse_args(argv)

    root = Path(args.project_dir or Path(__file__).resolve().parent.parent).resolve()
    if not root.is_dir():
        print(f"check-skill-xrefs.py: not a directory: {root}", file=sys.stderr)
        return 2
    repo = Repo(root)
    empty = None
    if not repo.skill_dirs or not repo.scan_files:
        empty = (
            f"resolved {len(repo.skill_dirs)} skills / {len(repo.scan_files)} files under {root}"
            " -- the discovery walk is broken, not the tree clean"
        )

    failed = False
    if args.only in (None, "citations"):
        fnd, st = (
            ([], {"scanned": 0, "external": 0}) if empty else check_citations(repo)
        )
        fnd = unreadable_findings(repo) + fnd
        emit(
            "SECTION CITATIONS",
            {
                "FILES_SCANNED": len(repo.scan_files),
                "SKILLS_ON_DISK": len(repo.skill_dirs),
                "CITATIONS_SCANNED": st["scanned"],
                "CITATIONS_EXTERNAL": st["external"],
            },
            fnd,
            empty,
        )
        failed |= bool(fnd) or bool(empty)
    if args.only in (None, "links"):
        fnd, st = ([], {"scanned": 0}) if empty else check_links(repo)
        fnd = unreadable_findings(repo) + fnd
        emit(
            "RELATIVE LINKS",
            {
                "FILES_SCANNED": len(repo.scan_files),
                "LINKS_SCANNED": st["scanned"],
            },
            fnd,
            empty,
        )
        failed |= bool(fnd) or bool(empty)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

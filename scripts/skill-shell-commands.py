#!/usr/bin/env python3
"""List the shell commands a skill shows, and check its Bash grants (#3464).

For one skill directory, read SKILL.md and every bundled markdown sidecar
(REFERENCE.md, references/**, any other .md in the skill dir) and list each
shell command they show: lines in shell-language and unlabeled fences, inline
code spans, and !`...` Context commands. It is the deterministic half of the
bare-Bash migration: editors derive a skill's narrow `Bash(<command> *)` grants
from its output, and a verifier re-runs --check on every migrated skill.

What counts as a command is not decided here. Markdown structure comes from
scripts/lib/extract-md-elements.py (tree-sitter), and the "runs shell"
recognition from scripts/lib/shell-commands.awk, the same functions
scripts/check-unused-bash-grant.sh uses, so the two cannot drift. This script
adds only what grants need on top: splitting a line into its pipeline/list
segments and $(...) bodies (quote-aware), and turning each command into a
candidate grant.

DEFAULT OUTPUT (one row per distinct command, sorted):
  HEAD=<first word> SUB=<subcommand> SUB2=<sub-subcommand> COUNT=<n> SOURCES=<files>
      SUB is set for multi-level CLIs (git gh docker kubectl helm npm bun
      cargo uv task just terraform ...) when the second word is a plain word;
      SUB2 for CLIs whose verbs sit two levels down (gh pr view, docker compose
      up, git stash list).
  SCRIPT=<path as spelled> INTERP=<runner or empty> QUOTED=<0|1> COUNT=<n> SOURCES=<files>
      a bundled-script invocation: a path anchored on ${CLAUDE_SKILL_DIR} or
      ${CLAUDE_PLUGIN_ROOT}, run directly or through bash/sh/python3/node/
      uv run/bun. QUOTED=1 when the body quotes the path; SCRIPT= then
      carries the quotes, and a body using both spellings gets two rows.
  CANDIDATE=<pattern>          a suggested grant, e.g. Bash(git status *) or
                               Bash(bash ${CLAUDE_SKILL_DIR}/scripts/x.sh *);
                               a script grant keeps the body's quotes,
                               Bash(bash "${CLAUDE_SKILL_DIR}/scripts/x.sh" *),
                               because the matcher's quote handling was not
                               measured (see raw_word)
  DROPPED=<pattern> WHY=<why>  a command the skill shows that should keep
                               prompting: destructive or outward (rm, git push,
                               git reset, publish/deploy verbs), sudo, inline
                               interpreter code (python3 -c), a command runner
                               (xargs, env, timeout) or docker/podman run|exec,
                               a global option
                               before the subcommand (git -C <dir> ...), a
                               multi-level CLI with no subcommand shown (a lone
                               `gh`), a <placeholder> path, or a command only
                               named alone in a prose span (`type` in a table).
                               A pattern is never both CANDIDATE and DROPPED:
                               a lone prose mention of a command the skill
                               also shows with arguments is not a drop.
  Never a bare interpreter wildcard such as Bash(bash *). A lone dot-dir path in
  a prose span (`.claude/settings.json`) is not listed as a command.
  The candidates are a starting point for an editor, not a verdict: they
  include every command the body shows (`cd`, `echo`, `pwd`), and the drop list
  is a fixed table, not a judgement of each skill.

--check: verify the skill's current grants. Findings (all SEVERITY=ERROR):
  bare_bash          a bare `Bash` remains
  broad_shell_grant  Bash(*) or an interpreter wildcard remains
  grant_not_in_body  a Bash(<words> ...) grant's words are not a token prefix
                     of any command the skill or its sidecars show (covers the
                     head, the subcommand, and an anchored script path)
  dropped_grant      a grant whose words begin with a hazard from the drop
                     table: destructive or outward (rm, git push, git reset,
                     publish/deploy verbs), sudo, inline interpreter code
                     (python3 -c), a command runner (xargs, env, timeout), or
                     docker/podman run|exec. Reported even when the body runs
                     the command: the migration rule is that these keep
                     prompting. The listing-only drop reasons (a lone word, a
                     placeholder, a missing subcommand, a global option) are
                     not --check findings.
  A quoted script grant, Bash(bash "${CLAUDE_SKILL_DIR}/x.sh" *), is matched
  by its unquoted words, so either spelling passes --check.

Usage:
  python3 scripts/skill-shell-commands.py <skill-dir> [--check]

Exit codes:
  0 - listing printed, or --check found nothing
  1 - --check findings
  2 - usage or environment error (bad arguments, no SKILL.md, the shared
      library or markdown parser missing or failing)
"""

from __future__ import annotations

import fnmatch
import os
import re
import shlex
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(HERE, "lib")
EXTRACT = os.path.join(LIB, "extract-md-elements.py")
SHELL_AWK = os.path.join(LIB, "shell-commands.awk")
ALLOWED_TOOLS_PY = os.path.join(LIB, "allowed_tools.py")

MULTI_LEVEL = {
    "git",
    "gh",
    "glab",
    "docker",
    "podman",
    "kubectl",
    "helm",
    "npm",
    "npx",
    "pnpm",
    "yarn",
    "bun",
    "bunx",
    "deno",
    "cargo",
    "rustup",
    "go",
    "uv",
    "uvx",
    "pip",
    "pipx",
    "task",
    "just",
    "make",
    "terraform",
    "tofu",
    "mise",
    "brew",
    "apt",
    "apt-get",
    "kustomize",
    "skaffold",
    "argocd",
    "pre-commit",
    "gcloud",
    "aws",
    "az",
    "systemctl",
    "launchctl",
    "obsidian",
    "comfy",
    "twine",
    "poetry",
    "ansible",
    "vagrant",
    "biome",
    "ruff",
}
# CLIs whose verbs sit two levels down; None = for every subcommand.
TWO_LEVEL = {
    "gh": None,
    "glab": None,
    "gcloud": None,
    "aws": None,
    "az": None,
    "docker": {
        "compose",
        "image",
        "container",
        "network",
        "volume",
        "buildx",
        "system",
    },
    "podman": {"compose", "image", "container", "network", "volume", "system"},
    "git": {"stash", "remote", "worktree", "submodule"},
}
INTERPRETERS = {"bash", "sh", "zsh", "python", "python3", "node"}
INLINE_FLAGS = {"-c", "-e", "-p", "--eval", "-"}
# Options that take an argument and may precede a multi-level CLI's subcommand.
GLOBAL_ARG_OPTS = {
    "-C",
    "-c",
    "--git-dir",
    "--work-tree",
    "-R",
    "--repo",
    "-n",
    "--namespace",
    "--context",
    "--kubeconfig",
    "--kube-context",
    "-H",
    "--host",
    "--project",
    "--cwd",
    "--profile",
    "--region",
    "-f",
    "--file",
    "--chdir",
    "--directory",
    "--prefix",
    "--manifest-path",
}
SCRIPT_RUNNERS = {
    ("bash",),
    ("sh",),
    ("zsh",),
    ("python",),
    ("python3",),
    ("node",),
    ("uv", "run"),
    ("bun",),
    ("bun", "run"),
    ("deno", "run"),
    ("tsx",),
}
ANCHORED = re.compile(r"^\$\{?(CLAUDE_SKILL_DIR|CLAUDE_PLUGIN_ROOT)\}?/")
PLAIN = re.compile(r"^[a-z0-9][a-z0-9._:-]*$")
ASSIGN_ONLY = re.compile(r"^\s*(?:\$\s+)?(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s*)+$")
SUDO = re.compile(r"^\s*(?:\$\s+)?sudo\s")

PATH_FORM = re.compile(r"^(\.|~|<)")
NO_SUBCOMMAND = "no subcommand shown: Bash(%s *) would admit every subcommand"
PLACEHOLDER = "placeholder: the body spells a <placeholder>, not a runnable command"
LONE_WORD = (
    "named alone in a prose span (a table cell or a mention), never shown with "
    "arguments; grant it only if the skill runs it"
)
DESTRUCTIVE = "destructive: a prefix grant on it also admits the dangerous forms"
DROP_HEADS = {
    "rm": "destructive: Bash(rm *) also admits rm -rf",
    "dd": DESTRUCTIVE,
    "mkfs": DESTRUCTIVE,
    "shred": DESTRUCTIVE,
}
for _runner in (
    "xargs",
    "env",
    "nohup",
    "timeout",
    "time",
    "watch",
    "nice",
    "exec",
    "eval",
):
    DROP_HEADS[_runner] = (
        "runs another command: Bash(%s *) pre-approves whatever "
        "command it is given" % _runner
    )
DROP_SUBS = {
    ("git", "push"): "outward: pushes to a remote",
    ("git", "reset"): "destructive: Bash(git reset *) also admits --hard",
    ("git", "clean"): "destructive: deletes untracked files",
    ("gh", "release"): "outward: publishes a release",
    ("docker", "push"): "outward: pushes an image",
    ("podman", "push"): "outward: pushes an image",
}
for _tool in ("docker", "podman"):
    for _verb in ("run", "exec"):
        DROP_SUBS[(_tool, _verb)] = (
            "runs arbitrary code: Bash(%s %s *) admits any image, "
            "mount and flag" % (_tool, _verb)
        )
for _tool in ("npm", "pnpm", "yarn", "bun", "cargo", "uv", "poetry"):
    DROP_SUBS[(_tool, "publish")] = "outward: publishes a package"
DROP_SUBS[("twine", "upload")] = "outward: publishes a package"
for _tool in ("terraform", "tofu"):
    for _verb in ("apply", "destroy", "import"):
        DROP_SUBS[(_tool, _verb)] = "outward: changes live infrastructure"
for _verb in ("apply", "delete", "replace", "patch", "scale", "drain"):
    DROP_SUBS[("kubectl", _verb)] = "outward: changes a live cluster"
for _verb in ("install", "upgrade", "uninstall", "rollback"):
    DROP_SUBS[("helm", _verb)] = "outward: changes a live cluster"
DROP_SUBS3 = {
    ("gh", "pr", "merge"): "outward: merges a pull request",
    ("gh", "repo", "delete"): "destructive: deletes a repository",
    ("gh", "workflow", "run"): "outward: triggers a workflow run",
}


def one_line(text: str) -> str:
    return " ".join(str(text).split())


def emit_env_error(title: str, itype: str, msg: str) -> None:
    print("=== %s ===" % title)
    print("STATUS=ERROR")
    print("REASON=%s" % one_line("%s: %s" % (itype, msg))[:180])
    print("ISSUE_COUNT=1")
    print("ISSUES:")
    print("  - SEVERITY=ERROR TYPE=%s MSG=%s" % (itype, one_line(msg)))
    print("=== END %s ===" % title)
    sys.exit(2)


def usage(msg: str) -> None:
    print("skill-shell-commands.py: %s" % msg, file=sys.stderr)
    print(
        "Usage: python3 scripts/skill-shell-commands.py <skill-dir> [--check]",
        file=sys.stderr,
    )
    sys.exit(2)


# --- segment splitting ----------------------------------------------------------
def _paren_body(text: str, start: int) -> tuple[str, int]:
    """Body of a $( ... ) opened just before `start`, and the index after `)`."""
    depth, i, quote = 1, start, None
    while i < len(text):
        ch = text[i]
        if quote:
            if ch == "\\" and quote == '"':
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return text[start:i], i + 1
        i += 1
    return text[start:], len(text)


def split_segments(text: str) -> tuple[list[tuple[str, str]], list[str]]:
    """Split a command line at top-level |, ||, &&, ; (outside quotes and $( )).

    Returns ([(segment, masked_segment), ...], [nested $(...) / `...` bodies,
    already split]). masked_segment hides quoted and $( ) text so an
    assignment-only segment (`x=$(git rev-parse HEAD)`) can be recognised.
    """
    tops: list[tuple[str, str]] = []
    nested_bodies: list[str] = []
    cur: list[str] = []
    mask: list[str] = []
    i, n, quote = 0, len(text), None

    def push():
        tops.append(("".join(cur), "".join(mask)))
        cur.clear()
        mask.clear()

    while i < n:
        ch = text[i]
        if quote == "'":
            cur.append(ch)
            mask.append("'" if ch == "'" else "_")
            if ch == "'":
                quote = None
            i += 1
            continue
        if ch == "\\" and i + 1 < n:
            cur.append(text[i : i + 2])
            mask.append("__")
            i += 2
            continue
        if text.startswith("$(", i) and not text.startswith("$((", i):
            body, j = _paren_body(text, i + 2)
            nested_bodies.append(body)
            cur.append(text[i:j])
            mask.append("$X")
            i = j
            continue
        if ch == "`":
            j = text.find("`", i + 1)
            j = n - 1 if j == -1 else j
            nested_bodies.append(text[i + 1 : j])
            cur.append(text[i : j + 1])
            mask.append("$X")
            i = j + 1
            continue
        if quote == '"':
            cur.append(ch)
            mask.append('"' if ch == '"' else "_")
            if ch == '"':
                quote = None
            i += 1
            continue
        if ch in "'\"":
            quote = ch
            cur.append(ch)
            mask.append(ch)
            i += 1
            continue
        if ch == "#" and (i == 0 or text[i - 1].isspace()):
            break  # a trailing comment
        if text.startswith("&&", i) or text.startswith("||", i):
            push()
            i += 2
            continue
        if ch in "|;":
            push()
            i += 1
            continue
        cur.append(ch)
        mask.append(ch)
        i += 1
    push()

    nested: list[str] = []
    for body in nested_bodies:
        inner_tops, inner_nested = split_segments(body)
        nested.extend(seg for seg, _ in inner_tops)
        nested.extend(inner_nested)
    return [t for t in tops if t[0].strip()], [s for s in nested if s.strip()]


def ordered_segments(text: str) -> list[str]:
    """Segment 0 is the line's first real command; later ones follow."""
    tops, nested = split_segments(text)
    real = [seg for seg, masked in tops if not ASSIGN_ONLY.match(masked)]
    if real:
        return real + nested
    return nested


# --- command interpretation ------------------------------------------------------
def tokens_of(command: str) -> list[str]:
    try:
        return shlex.split(command, posix=True)
    except ValueError:
        return command.split()


def grant_words(toks: list[str]) -> tuple[list[str], str | None]:
    """The words a candidate grant pins, and a drop reason when it should not be granted."""
    head = toks[0]
    if head in INTERPRETERS:
        if len(toks) == 1:
            return [
                head
            ], "inline code: an interpreter with no script reads code from stdin"
        t1 = toks[1]
        if t1 in INLINE_FLAGS:
            return [head, t1], "inline code: a prefix grant on it admits arbitrary code"
        if t1 == "-m" and len(toks) > 2:
            return [head, t1, toks[2]], None
        return [head, t1], None
    if head in MULTI_LEVEL:
        if len(toks) == 1:
            return [head], NO_SUBCOMMAND % head
        t1 = toks[1]
        if PLAIN.match(t1):
            words = [head, t1]
            subs = TWO_LEVEL.get(head, set())
            if (
                head in TWO_LEVEL
                and (subs is None or t1 in subs)
                and len(toks) > 2
                and PLAIN.match(toks[2])
            ):
                words.append(toks[2])
            return words, None
        if t1.startswith("-"):
            # `git -C <dir> <any subcommand>`: the option's argument sits where
            # the subcommand would, so no prefix grant can narrow it. A flag
            # that takes no argument (`bun --inspect-brk x.ts`) is itself narrow.
            if t1 in GLOBAL_ARG_OPTS or "=" in t1:
                return (
                    [head, t1],
                    "global option before the subcommand; a prefix grant cannot narrow it",
                )
            return [head, t1], None
        return [head], NO_SUBCOMMAND % head  # a variable or placeholder subcommand
    return [head], None


def raw_word(text: str, unquoted: str) -> str:
    """The word of `text` that shell-unquotes to `unquoted`, as the body spells it.

    A grant is written in the body's spelling (#3464 F4): Claude Code's prefix
    matcher was not measured on quoted words. If it compares raw strings only
    the body's spelling matches; if it unquotes, it unquotes the rule too, so
    the body's spelling matches either way, and an unquoted rule for a quoted
    invocation does not.
    """
    for word in re.findall(r"(?:[^\s\"']+|\"[^\"]*\"|'[^']*')+", text):
        if word == unquoted:
            return word
        try:
            if shlex.split(word, posix=True) == [unquoted]:
                return word
        except ValueError:
            continue
    return unquoted


def drop_reason(words: list[str]) -> str | None:
    if words[0] == "sudo":
        return "sudo: keep it prompting"
    if words[0] in INTERPRETERS and len(words) > 1 and words[1] in INLINE_FLAGS:
        return "inline code: a prefix grant on it admits arbitrary code"
    if words[0] in DROP_HEADS:
        return DROP_HEADS[words[0]]
    if len(words) >= 3 and tuple(words[:3]) in DROP_SUBS3:
        return DROP_SUBS3[tuple(words[:3])]
    if len(words) >= 2 and tuple(words[:2]) in DROP_SUBS:
        return DROP_SUBS[tuple(words[:2])]
    return None


class Inventory:
    def __init__(self) -> None:
        self.heads: dict[tuple[str, str, str], list] = {}
        self.scripts: dict[tuple[str, str, int], list] = {}
        self.candidates: set[str] = set()
        self.dropped: dict[str, str] = {}
        self.token_lists: list[list[str]] = []

    @staticmethod
    def _bump(table: dict, key, source: str) -> None:
        entry = table.setdefault(key, [0, set()])
        entry[0] += 1
        entry[1].add(source)

    def add(self, stripped: str, raw: str, source: str, src_type: str) -> None:
        toks = tokens_of(stripped)
        if not toks:
            return
        # The shared recogniser counts any dot-dir path as an executable, which
        # is right for a fence line (`.venv/bin/python x`) but makes a lone path
        # in a prose span (`.claude/settings.json`) look like a command.
        if src_type == "inline_code" and len(toks) == 1 and PATH_FORM.match(toks[0]):
            return
        sudo = bool(SUDO.match(raw))
        self.token_lists.append(toks)
        if sudo:
            self.token_lists.append(["sudo"] + toks)

        # A bundled-script invocation, through a runner or run directly.
        for width in (2, 1):
            if (
                tuple(toks[:width]) in SCRIPT_RUNNERS
                and len(toks) > width
                and ANCHORED.match(toks[width])
            ):
                self._script(toks[width], " ".join(toks[:width]), stripped, source)
                return
        if ANCHORED.match(toks[0]):
            self._script(toks[0], "", stripped, source)
            return

        words, why = grant_words(toks)
        sub = words[1] if len(words) > 1 and PLAIN.match(words[1]) else ""
        sub2 = words[2] if sub and len(words) > 2 and PLAIN.match(words[2]) else ""
        self._bump(self.heads, (toks[0], sub, sub2), source)

        pattern_words = (["sudo"] if sudo else []) + words
        pattern = "Bash(%s *)" % " ".join(pattern_words)
        why = "sudo: keep it prompting" if sudo else (why or drop_reason(words))
        if not why and any("<" in w and ">" in w for w in words):
            why = PLACEHOLDER
        if not why and src_type == "inline_code" and len(toks) == 1:
            why = LONE_WORD
        # LONE_WORD only means "never seen with arguments"; once the same
        # pattern is shown with arguments anywhere it is a candidate, whatever
        # order the two spans appear in (#3464 F1).
        if why == LONE_WORD and pattern in self.candidates:
            return
        if why:
            self.dropped.setdefault(pattern, why)
        else:
            self._candidate(pattern)

    def _candidate(self, pattern: str) -> None:
        self.candidates.add(pattern)
        if self.dropped.get(pattern) == LONE_WORD:
            del self.dropped[pattern]

    def _script(self, path: str, interp: str, stripped: str, source: str) -> None:
        spelled = raw_word(stripped, path)
        quoted = 0 if spelled == path else 1
        self._bump(self.scripts, (spelled, interp, quoted), source)
        self._candidate("Bash(%s *)" % " ".join(x for x in (interp, spelled) if x))


# --- extraction ----------------------------------------------------------------
def skill_files(skill_dir: str) -> list[str]:
    found = []
    for root, dirs, files in os.walk(skill_dir):
        dirs.sort()
        for name in sorted(files):
            if name.endswith(".md"):
                found.append(os.path.join(root, name))
    main = os.path.join(skill_dir, "SKILL.md")
    return [main] + [f for f in found if f != main]


def collect(skill_dir: str, title: str) -> tuple[Inventory, int]:
    files = skill_files(skill_dir)
    try:
        proc = subprocess.run(
            [EXTRACT, "--types", "fence_line,inline_code"] + files,
            capture_output=True,
            text=True,
        )
    except OSError as exc:
        emit_env_error(title, "extract_failed", "cannot run %s: %s" % (EXTRACT, exc))
    if proc.returncode != 0:
        emit_env_error(
            title,
            "extract_failed",
            "%s exited %d: %s" % (EXTRACT, proc.returncode, proc.stderr.strip()[:120]),
        )

    lines: list[tuple[str, str]] = []  # (source, segments...) bookkeeping
    awk_rows: list[str] = []
    seg_text: dict[tuple[int, int], str] = {}
    for row in proc.stdout.splitlines():
        cols = row.split("\t")
        if cols[0] == "fence_line" and len(cols) >= 5:
            src_type, path, lang, text = "fence_line", cols[1], cols[3], cols[4]
        elif cols[0] == "inline_code" and len(cols) >= 7:
            src_type = "bang" if cols[5] == "1" else "inline_code"
            path, lang, text = cols[1], "", cols[6]
        else:
            continue
        line_id = len(lines)
        lines.append((os.path.relpath(path, skill_dir), src_type))
        for idx, seg in enumerate(ordered_segments(text)):
            seg = seg.replace("\t", " ")
            seg_text[(line_id, idx)] = seg
            awk_rows.append("%d\t%s\t%s\t%d\t%s" % (line_id, src_type, lang, idx, seg))

    try:
        awk = subprocess.run(
            ["awk", "-F\t", "-v", "mode=segments", "-f", SHELL_AWK],
            input="\n".join(awk_rows) + "\n",
            capture_output=True,
            text=True,
        )
    except OSError as exc:
        emit_env_error(title, "awk_failed", "cannot run awk: %s" % exc)
    if awk.returncode != 0:
        emit_env_error(
            title,
            "awk_failed",
            "awk exited %d: %s" % (awk.returncode, awk.stderr.strip()[:120]),
        )

    verdicts: dict[int, dict[int, tuple[int, str]]] = {}
    for row in awk.stdout.splitlines():
        cols = row.split("\t")
        if len(cols) < 3 or not cols[0].isdigit():
            continue
        verdicts.setdefault(int(cols[0]), {})[int(cols[1])] = (
            int(cols[2]),
            cols[3] if len(cols) > 3 else "",
        )

    inv = Inventory()
    for line_id, segs in sorted(verdicts.items()):
        if segs.get(0, (0, ""))[0] != 1:
            continue  # the line does not start with a command
        source, src_type = lines[line_id]
        for idx in sorted(segs):
            ok, stripped = segs[idx]
            if ok == 1:
                inv.add(stripped, seg_text[(line_id, idx)], source, src_type)
    return inv, len(files)


# --- check ---------------------------------------------------------------------
def grant_findings(skill_dir: str, inv: Inventory) -> tuple[int, list[tuple[str, str]]]:
    sys.path.insert(0, LIB)
    from allowed_tools import bash_inner, classify, read_allowed_tools  # noqa: E402

    findings: list[tuple[str, str]] = []
    grants = 0
    for token in read_allowed_tools(os.path.join(skill_dir, "SKILL.md")):
        kind = classify(token)
        inner = bash_inner(token)
        if kind is None and inner is None:
            continue
        grants += 1
        if kind:
            findings.append(
                (
                    kind,
                    "%s is a full-shell grant; list the commands the skill runs "
                    "as Bash(<command> *)" % token,
                )
            )
            continue
        pattern = inner
        for suffix in (":*", " *"):
            if pattern.endswith(suffix):
                pattern = pattern[: -len(suffix)].rstrip()
                break
        words = tokens_of(pattern)
        if not words:
            continue
        hazard = drop_reason(words)
        if hazard:
            findings.append(
                (
                    "dropped_grant",
                    "%s pre-approves a command that should keep prompting (%s)"
                    % (token, hazard),
                )
            )

        def matches(toks: list[str]) -> bool:
            return len(toks) >= len(words) and all(
                fnmatch.fnmatchcase(t, w) if "*" in w else t == w
                for w, t in zip(words, toks)
            )

        if not any(matches(t) for t in inv.token_lists):
            head_seen = any(t and t[0] == words[0] for t in inv.token_lists)
            msg = "%s matches no command the skill or its sidecars show" % token
            if head_seen and len(words) > 1:
                msg += "; it runs %s, but not as %s" % (words[0], " ".join(words))
            findings.append(("grant_not_in_body", msg))
    return grants, findings


def main(argv: list[str]) -> int:
    check = False
    positional = []
    for arg in argv:
        if arg == "--check":
            check = True
        elif arg in ("-h", "--help"):
            print(__doc__)
            return 0
        elif arg.startswith("-"):
            usage("unknown argument: %s" % arg)
        else:
            positional.append(arg)
    if len(positional) != 1:
        usage("expected exactly one skill directory")
    skill_dir = positional[0]
    if not os.path.isdir(skill_dir):
        usage("not a directory: %s" % skill_dir)
    if not os.path.isfile(os.path.join(skill_dir, "SKILL.md")):
        usage("no SKILL.md in %s" % skill_dir)

    title = "SKILL GRANT CHECK" if check else "SKILL SHELL COMMANDS"
    for needed in (EXTRACT, SHELL_AWK, ALLOWED_TOOLS_PY):
        if not os.path.isfile(needed):
            emit_env_error(
                title, "missing_helper", "shared library file not found: %s" % needed
            )

    inv, files_scanned = collect(skill_dir, title)

    print("=== %s ===" % title)
    print("SKILL=%s" % skill_dir)
    print("FILES_SCANNED=%d" % files_scanned)
    print("COMMANDS=%d" % len(inv.heads))
    print("SCRIPTS=%d" % len(inv.scripts))
    if check:
        grants, findings = grant_findings(skill_dir, inv)
        print("GRANTS=%d" % grants)
        print("STATUS=%s" % ("ERROR" if findings else "OK"))
        if findings:
            reason = one_line("%s: %s" % findings[0])[:180]
            if len(findings) > 1:
                reason += " (+%d more)" % (len(findings) - 1)
            print("REASON=%s" % reason)
        print("ISSUE_COUNT=%d" % len(findings))
        if findings:
            print("ISSUES:")
            for itype, msg in findings:
                print("  - SEVERITY=ERROR TYPE=%s MSG=%s" % (itype, one_line(msg)))
        print("=== END %s ===" % title)
        return 1 if findings else 0

    for (head, sub, sub2), (count, sources) in sorted(inv.heads.items()):
        print(
            "HEAD=%s SUB=%s SUB2=%s COUNT=%d SOURCES=%s"
            % (head, sub, sub2, count, ",".join(sorted(sources)))
        )
    for (path, interp, quoted), (count, sources) in sorted(inv.scripts.items()):
        print(
            "SCRIPT=%s INTERP=%s QUOTED=%d COUNT=%d SOURCES=%s"
            % (path, interp, quoted, count, ",".join(sorted(sources)))
        )
    for pattern in sorted(inv.candidates):
        print("CANDIDATE=%s" % pattern)
    for pattern, why in sorted(inv.dropped.items()):
        print("DROPPED=%s WHY=%s" % (pattern, why))
    print("STATUS=OK")
    print("ISSUE_COUNT=0")
    print("=== END %s ===" % title)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

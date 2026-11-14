#!/usr/bin/env python3
"""List the shell commands a skill shows, and check its Bash grants (#3464).

For one skill directory, read SKILL.md and every bundled markdown sidecar
(REFERENCE.md, references/**, any other .md in the skill dir) and list each
shell command they show. It is the deterministic half of the bare-Bash
migration: editors derive a skill's narrow `Bash(<command> *)` grants from the
listing, and a verifier re-runs --check on every migrated skill.

WHAT IS A COMMAND (listing)
  Markdown structure comes from scripts/lib/extract-md-elements.py
  (tree-sitter). A line is split into its pipeline/list segments and $(...)
  bodies (quote-aware). A segment is listed when:
  - scripts/lib/shell-commands.awk recognises it (the "runs shell" rule
    scripts/check-unused-bash-grant.sh uses: a known command or an executable
    path, in a shell-ish or unlabeled fence, an inline span, or a !`...`
    Context command); or
  - it sits in an explicitly shell-labelled fence (bash, sh, shell, zsh,
    console) and its first word is command-shaped (lowercase, no `:` or `/`),
    whatever head it has (gcloud, playwright-cli, ...). In a console fence such
    a line must carry a `$ ` prompt, so output lines are not commands.
  So the helper lists a superset of what the unused-grant lint counts; that
  lint's output does not change. In a shell-labelled fence, a backslash
  continuation or a quote left open joins physical lines into one command, and
  a heredoc body is skipped. A leading shell keyword (`if`, `while`, `then`,
  `do`, `else`, `!`) is not the command; the word after it is. In an inline
  span, a pipe escaped for a table cell (backslash-pipe) is a pipe.

DEFAULT OUTPUT (one row per distinct command, sorted):
  HEAD=<first word> SUB=<subcommand> SUB2=<sub-subcommand> COUNT=<n> SOURCES=<files>
      SUB is set for multi-level CLIs (git gh docker kubectl helm npm bun
      cargo uv task just terraform gcloud ...) when the second word is a plain
      word; SUB2 for CLIs whose verbs sit two levels down (gh pr view, docker
      compose up, gcloud run deploy, git stash list).
  SCRIPT=<path> INTERP=<runner or empty> QUOTED=<0|1> COUNT=<n> SOURCES=<files>
      a bundled-script invocation: a path anchored on ${CLAUDE_SKILL_DIR} or
      ${CLAUDE_PLUGIN_ROOT}, run directly or through bash/sh/python3/node/
      uv run/bun. SCRIPT= is the unquoted path; QUOTED=1 says the body quotes
      it (information only).
  Every other pattern is printed once, as exactly one of:
  CANDIDATE=<pattern>          a suggested grant, e.g. Bash(git status *) or
                               Bash(bash ${CLAUDE_SKILL_DIR}/scripts/x.sh *).
                               A script candidate is always unquoted: that is
                               the spelling in the rule table of
                               .claude/rules/agentic-permissions.md, and #3634
                               measured (Claude Code 2.1.322) that a quoted
                               invocation matched the unquoted rule while the
                               path held no space; with a space, neither a
                               quoted invocation nor a quoted rule was
                               pre-approved
  REVIEW=<pattern> WHY=<why>   a hazardous command (rm, sudo <cmd>, git push,
                               git reset, publish/deploy/delete verbs, docker
                               run|exec, ...): grant it only if running it is
                               what the skill is for
  DROPPED=<pattern> WHY=<why>  never grantable as written: inline interpreter
                               code (python3 -c), a command runner with no fixed
                               command (xargs, env, timeout), a global option
                               before the subcommand (git -C <dir> ...), a
                               multi-level CLI with no subcommand shown (a lone
                               `gh`), a <placeholder> path, a word built at run
                               time ($(...), backticks, ${{ ... }}), a bare
                               interpreter, or a command only named alone in a
                               prose span (`type` in a table)
  Never a bare interpreter wildcard such as Bash(bash *). A lone dot-dir path in
  a prose span (`.claude/settings.json`) is not listed as a command. The
  candidates are a starting point, not a verdict: they include every command
  the body shows (`cd`, `echo`, `pwd`), and the hazard table is fixed.

--check: verify the skill's current grants.
  A grant's words (after its trailing ` *` or `:*`) must be a token prefix of
  the leading words of some command segment in ANY code element of SKILL.md or
  a sidecar: a shell-ish or unlabeled fence line, an inline span, a !`...`
  Context command; in a console-style fence (console, shell-session,
  terminal) only a `$ ` prompt line. A leading `$ `, VAR=val or shell keyword
  may precede that prefix; `sudo` and `env` may not, because an allow rule for
  `apt-get` does not pre-approve `sudo apt-get`. The match does not depend on
  the listing's known-command list, so a correct grant never fails because
  its head is unknown. A grant that matches only a prose mention still passes:
  --check asks whether the skill shows the command, and the listing's DROPPED
  rows are where lone mentions are kept out of the candidates.
  ERROR rows (exit 1):
  bare_bash             a bare `Bash` remains
  broad_shell_grant     Bash(*) or an interpreter wildcard remains (the lint's
                        classifier, scripts/lib/allowed_tools.py)
  arbitrary_code_grant  a grant that pre-approves arbitrary code the way an
                        interpreter wildcard does: inline-code flags
                        (python3 -c, bash -c, node -e, perl -e, ruby -e) or a
                        command runner with no fixed command after it (xargs,
                        env, timeout, nohup, watch, eval, exec, sudo, nice,
                        time), or a runner before a bare interpreter
                        (Bash(xargs bash *))
  no_subcommand         a multi-level CLI whose subcommands differ in hazard
                        (git gh docker podman kubectl helm terraform tofu npm
                        pnpm yarn bun cargo uv gcloud aws az) granted with no
                        subcommand: Bash(git *), Bash(git:*), Bash(gh -R *).
                        24 skills already on narrow patterns carry such a grant
                        (a scan of origin/main b478400 with this definition:
                        git 9, cargo 7, gh 3, npm 3, and others); --check
                        applies this stricter migration standard only to the
                        skill it is run on
  quoted_script_grant   a script grant with a quoted path,
                        Bash(bash "${CLAUDE_SKILL_DIR}/x.sh" *): write it
                        unquoted (see CANDIDATE above). The quoted body
                        invocation is fine
  grant_not_in_body     the grant's words match no command segment
  WARN rows (exit 0, STATUS=WARN):
  hazardous_grant       a grant for a REVIEW-class command; confirm running it
                        is what the skill is for (house practice grants
                        Bash(git push *) in PR skills and anchored sudo forms
                        in diagnostics skills)

Usage:
  python3 scripts/skill-shell-commands.py <skill-dir> [--check]

Exit codes:
  0 - listing printed, or --check found no ERROR (STATUS=OK or WARN)
  1 - --check found an ERROR row
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
# --check: a grant on one of these with no subcommand is an ERROR (#3464 F2).
NO_SUBCOMMAND_HEADS = {
    "git",
    "gh",
    "docker",
    "podman",
    "kubectl",
    "helm",
    "terraform",
    "tofu",
    "npm",
    "pnpm",
    "yarn",
    "bun",
    "cargo",
    "uv",
    "gcloud",
    "aws",
    "az",
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
# Inline-code forms that pre-approve arbitrary code (#3464 F3).
INLINE_CODE = {
    "bash": {"-c"},
    "sh": {"-c"},
    "zsh": {"-c"},
    "python": {"-c"},
    "python3": {"-c"},
    "node": {"-e", "-p", "--eval", "--print"},
    "perl": {"-e", "-E"},
    "ruby": {"-e"},
}
RUNNERS = {
    "xargs",
    "env",
    "timeout",
    "nohup",
    "watch",
    "eval",
    "exec",
    "sudo",
    "nice",
    "time",
}
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
QUOTED_ANCHOR = re.compile(r"[\"']\$\{?(CLAUDE_SKILL_DIR|CLAUDE_PLUGIN_ROOT)\}?/")
PLAIN = re.compile(r"^[a-z0-9][a-z0-9._:-]*$")
SHAPED = re.compile(r"^[a-z][A-Za-z0-9_+-]*(?:\.[A-Za-z0-9_+-]+)*$")
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
ARRAY_ASSIGN = re.compile(r"^\s*(?:\$\s+)?[A-Za-z_][A-Za-z0-9_]*=\(")
ASSIGN_ONLY = re.compile(r"^\s*(?:\$\s+)?(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s*)+$")
PROMPT = re.compile(r"^\s*\$\s+")
KEYWORD_PREFIX = re.compile(r"^\s*(?:\$\s+)?(?:if|elif|while|until|then|do|else|!)\s+")
HEREDOC = re.compile(r"(?<!<)<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
SHELL_WORDS = {
    "if",
    "then",
    "else",
    "elif",
    "fi",
    "for",
    "while",
    "until",
    "do",
    "done",
    "case",
    "esac",
    "in",
    "function",
    "select",
    "return",
    "exit",
    "local",
    "declare",
    "typeset",
    "readonly",
    "set",
    "shift",
    "break",
    "continue",
    "trap",
    "unset",
    "true",
    "false",
}
# Fence languages: the explicit set lists unknown heads; the wide set (plus an
# empty info string) is what --check matches against.
EXPLICIT_SHELL = {"bash", "sh", "shell", "zsh", "console"}
SHELLISH = EXPLICIT_SHELL | {
    "shell-session",
    "shellsession",
    "fish",
    "command",
    "terminal",
}
# Fences whose lines join on a continuation or open quote. Console-style
# fences mix in output, where an apostrophe would swallow the next prompt.
JOINABLE = {"bash", "sh", "shell", "zsh", "fish", "command"}
# Transcript fences: output lines sit between `$ ` prompt lines.
PROMPTED = {"console", "shell-session", "shellsession", "terminal"}
MAX_JOIN = 50  # physical lines one logical command may span

PATH_FORM = re.compile(r"^(\.|~|<)")
NO_SUBCOMMAND = "no subcommand shown: Bash(%s *) would admit every subcommand"
PLACEHOLDER = "placeholder: the body spells a <placeholder>, not a runnable command"
DYNAMIC = (
    "built at run time ($(...), backticks or ${{ ... }}): a permission rule "
    "matches the literal text, so no prefix grant pins it"
)
DYNAMIC_WORD = re.compile(r"\$\(|`|\$\{\{")
LONE_WORD = (
    "named alone in a prose span (a table cell or a mention), never shown with "
    "arguments; grant it only if the skill runs it"
)
GLOBAL_OPT = "global option before the subcommand; a prefix grant cannot narrow it"
DESTRUCTIVE = "destructive: a prefix grant on it also admits the dangerous forms"
HAZARD_HEADS = {
    "rm": "destructive: Bash(rm *) also admits rm -rf",
    "dd": DESTRUCTIVE,
    "mkfs": DESTRUCTIVE,
    "shred": DESTRUCTIVE,
}
HAZARD_SUBS = {
    ("git", "push"): "outward: pushes to a remote",
    ("git", "reset"): "destructive: Bash(git reset *) also admits --hard",
    ("git", "clean"): "destructive: deletes untracked files",
    ("gh", "release"): "outward: publishes a release",
    ("docker", "push"): "outward: pushes an image",
    ("podman", "push"): "outward: pushes an image",
}
for _tool in ("docker", "podman"):
    for _verb in ("run", "exec"):
        HAZARD_SUBS[(_tool, _verb)] = (
            "runs arbitrary code in a container: Bash(%s %s *) admits any "
            "image, mount and flag" % (_tool, _verb)
        )
for _tool in ("terraform", "tofu"):
    for _verb in ("apply", "destroy", "import"):
        HAZARD_SUBS[(_tool, _verb)] = "outward: changes live infrastructure"
for _verb in ("apply", "delete", "replace", "patch", "scale", "drain"):
    HAZARD_SUBS[("kubectl", _verb)] = "outward: changes a live cluster"
for _verb in ("install", "upgrade", "uninstall", "rollback"):
    HAZARD_SUBS[("helm", _verb)] = "outward: changes a live cluster"
HAZARD_SUBS3 = {
    ("gh", "pr", "merge"): "outward: merges a pull request",
    ("gh", "workflow", "run"): "outward: triggers a workflow run",
}
# A verb in the first two subcommand positions, whatever the CLI.
HAZARD_VERBS = {
    "publish": "outward: publishes",
    "deploy": "outward: deploys",
    "upload": "outward: uploads",
    "delete": "destructive: deletes",
    "destroy": "destructive: destroys",
}
ARB, HAZ = "arbitrary_code_grant", "hazardous_grant"


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


def strip_keywords(seg: str) -> str:
    """Drop leading shell keywords (`if git diff` -> `git diff`), keeping a prompt."""
    prompt = "$ " if PROMPT.match(seg) else ""
    while True:
        m = KEYWORD_PREFIX.match(seg)
        if not m:
            break
        seg = prompt + seg[m.end() :]
    return seg


def ordered_segments(text: str) -> list[str]:
    """Segment 0 is the line's first real command; later ones follow."""
    tops, nested = split_segments(text)
    real = [
        strip_keywords(seg) for seg, masked in tops if not ASSIGN_ONLY.match(masked)
    ]
    nested = [strip_keywords(seg) for seg in nested]
    if real:
        return real + nested
    return nested


def needs_more(text: str) -> bool:
    """True when a shell line continues: a quote is open or it ends in `\\`."""
    quote, comment, i = None, False, 0
    while i < len(text):
        ch = text[i]
        if comment:
            comment = ch != "\n"
        elif quote == "'":
            if ch == "'":
                quote = None
        elif ch == "\\":
            i += 1
        elif quote == '"':
            if ch == '"':
                quote = None
        elif ch in "'\"":
            quote = ch
        elif ch == "#" and (i == 0 or text[i - 1].isspace()):
            comment = True
        i += 1
    return quote is not None or (not comment and text.rstrip().endswith("\\"))


def logical_units(rows: list[tuple]) -> list[tuple[str, str, str, str]]:
    """Group extractor rows into (source, src_type, lang, text) commands.

    Fence lines of one fence are contiguous line numbers in one file. In a
    shell-labelled fence a continuation or open quote joins lines; in any fence
    a heredoc body is skipped.
    """
    units: list[tuple[str, str, str, str]] = []
    prev = None  # (path, line) of the last fence line seen
    heredoc = None
    buf: list[str] = []
    buf_meta = None

    def flush():
        nonlocal buf, buf_meta
        if buf:
            units.append(buf_meta + (" ".join(s.rstrip().rstrip("\\") for s in buf),))
        buf, buf_meta = [], None

    for row in rows:
        kind, path = row[0], row[1]
        if kind != "fence_line":
            flush()
            prev, heredoc = None, None
            units.append(row[2:])
            continue
        _, _, line, lang, text, source = row
        if prev != (path, line - 1):  # a new fence
            flush()
            heredoc = None
        prev = (path, line)
        if heredoc:
            if text.strip() == heredoc:
                heredoc = None
            continue
        if not buf:
            buf_meta = (source, "fence_line", lang)
        buf.append(text)
        m = HEREDOC.search(text)
        if m:
            heredoc = m.group(2)
        if (
            lang.lower() in JOINABLE
            and len(buf) < MAX_JOIN
            and needs_more("\n".join(buf))
        ):
            continue
        flush()
    flush()
    return units


# --- command interpretation ------------------------------------------------------
def tokens_of(command: str) -> list[str]:
    try:
        return shlex.split(command, posix=True)
    except ValueError:
        return command.split()


def head_name(word: str) -> str:
    """`/usr/bin/python3` -> `python3`; an anchored script path stays itself."""
    if "/" in word and not ANCHORED.match(word):
        return word.rsplit("/", 1)[-1]
    return word


def grant_words(toks: list[str]) -> tuple[list[str], str | None]:
    """The words a candidate grant pins, and a reason when it can never be granted."""
    head = toks[0]
    if head_name(head) in INTERPRETERS:
        if len(toks) == 1:
            return [head], "bare interpreter: with no script it reads code from stdin"
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
                return [head, t1], GLOBAL_OPT
            return [head, t1], None
        return [head], NO_SUBCOMMAND % head  # a variable or placeholder subcommand
    return [head], None


def _runner_arg(word: str) -> bool:
    """A word after a runner that is not yet the command it runs."""
    if ANCHORED.match(word):
        return False
    return (
        word.startswith("-")
        or "=" in word
        or "*" in word
        or bool(re.match(r"^\d+(\.\d+)?[smhd]?$", word))
        or not SHAPED.match(head_name(word))
    )


def grant_class(words: list[str]) -> tuple[str, str] | None:
    """(ARB|HAZ, why) for a grant's words, or None when they are unremarkable."""
    head, rest = head_name(words[0]), words[1:]
    if head in INTERPRETERS and not rest:
        return ARB, "interpreter wildcard: Bash(%s *) admits %s -c '<any code>'" % (
            head,
            head,
        )
    if head in INLINE_CODE and rest and rest[0] in INLINE_CODE[head]:
        return ARB, "inline code: Bash(%s %s *) runs any code it is given" % (
            head,
            rest[0],
        )
    if head in RUNNERS:
        i = 0
        while i < len(rest) and _runner_arg(rest[i]):
            i += 1
        if i == len(rest):
            return ARB, (
                "runs another command: Bash(%s *) with no fixed command after "
                "it pre-approves whatever command it is given" % head
            )
        inner = grant_class(rest[i:])
        if inner and inner[0] == ARB:
            return inner
        if head == "sudo":
            return HAZ, "sudo: runs %s as root" % rest[i]
        return inner
    if head in HAZARD_HEADS:
        return HAZ, HAZARD_HEADS[head]
    key = tuple([head] + rest)
    if len(key) >= 3 and key[:3] in HAZARD_SUBS3:
        return HAZ, HAZARD_SUBS3[key[:3]]
    if len(key) >= 2 and key[:2] in HAZARD_SUBS:
        return HAZ, HAZARD_SUBS[key[:2]]
    for word in rest[:2]:
        if word in HAZARD_VERBS:
            return HAZ, HAZARD_VERBS[word]
    return None


def no_subcommand(words: list[str]) -> bool:
    """A NO_SUBCOMMAND_HEADS grant that names no subcommand (#3464 F2)."""
    head = words[0].rstrip("*")
    if head not in NO_SUBCOMMAND_HEADS:
        return False
    if len(words) == 1:
        return True
    t1 = words[1]
    if "*" in t1:
        return True
    return (
        len(words) == 2 and t1.startswith("-") and (t1 in GLOBAL_ARG_OPTS or "=" in t1)
    )


def token_variants(toks: list[str]) -> list[list[str]]:
    """The token list, and each suffix after a leading prompt, VAR=val or keyword.

    `sudo` and `env` stay: an allow rule for `apt-get` does not pre-approve
    `sudo apt-get`, so the grant has to name them (#3464).
    """
    out = []
    while toks:
        out.append(toks)
        t = toks[0]
        if t in (
            "$",
            "!",
            "if",
            "elif",
            "while",
            "until",
            "then",
            "do",
            "else",
        ) or ASSIGN.match(t):
            toks = toks[1:]
            continue
        break
    return out


class Inventory:
    def __init__(self) -> None:
        self.heads: dict[tuple[str, str, str], list] = {}
        self.scripts: dict[tuple[str, str, int], list] = {}
        # pattern -> [words, fixed drop reason or None, shown with arguments]
        self.patterns: dict[str, list] = {}
        self.match_tokens: list[list[str]] = []

    @staticmethod
    def _bump(table: dict, key, source: str) -> None:
        entry = table.setdefault(key, [0, set()])
        entry[0] += 1
        entry[1].add(source)

    def _pattern(self, words: list[str], fixed: str | None, with_args: bool) -> None:
        pattern = "Bash(%s *)" % " ".join(words)
        entry = self.patterns.setdefault(pattern, [words, fixed, False])
        entry[2] = entry[2] or with_args

    def add(self, stripped: str, raw: str, source: str, src_type: str) -> None:
        toks = tokens_of(stripped)
        if not toks:
            return
        # The shared recogniser counts any dot-dir path as an executable, which
        # is right for a fence line (`.venv/bin/python x`) but makes a lone path
        # in a prose span (`.claude/settings.json`) look like a command.
        if src_type == "inline_code" and len(toks) == 1 and PATH_FORM.match(toks[0]):
            return
        sudo = toks[0] != "sudo" and bool(re.match(r"^\s*(?:\$\s+)?sudo\s", raw))

        # A bundled-script invocation, through a runner or run directly.
        for width in (2, 1, 0):
            if (
                (width == 0 or tuple(toks[:width]) in SCRIPT_RUNNERS)
                and len(toks) > width
                and ANCHORED.match(toks[width])
            ):
                path, interp = toks[width], " ".join(toks[:width])
                quoted = 1 if ('"' + path in raw or "'" + path in raw) else 0
                self._bump(self.scripts, (path, interp, quoted), source)
                self._pattern([w for w in (interp, path) if w], None, True)
                return

        words, why = grant_words(toks)
        sub = words[1] if len(words) > 1 and PLAIN.match(words[1]) else ""
        sub2 = words[2] if sub and len(words) > 2 and PLAIN.match(words[2]) else ""
        self._bump(self.heads, (toks[0], sub, sub2), source)
        if not why and any("<" in w and ">" in w for w in words):
            why = PLACEHOLDER
        if not why and any(DYNAMIC_WORD.search(w) for w in words):
            why = DYNAMIC
        with_args = not (src_type == "inline_code" and len(toks) == 1)
        self._pattern((["sudo"] if sudo else []) + words, why, with_args)

    def resolved(
        self,
    ) -> tuple[list[str], list[tuple[str, str]], list[tuple[str, str]]]:
        """Each pattern as exactly one of CANDIDATE, REVIEW or DROPPED."""
        cands, reviews, drops = [], [], []
        for pattern, (words, fixed, with_args) in sorted(self.patterns.items()):
            cls = grant_class(words)
            if fixed:
                drops.append((pattern, fixed))
            elif cls and cls[0] == ARB:
                drops.append((pattern, cls[1]))
            elif not with_args:
                drops.append((pattern, LONE_WORD))
            elif cls:
                reviews.append(
                    (
                        pattern,
                        "%s; grant it only if running it is the skill's purpose"
                        % cls[1],
                    )
                )
            else:
                cands.append(pattern)
        return cands, reviews, drops


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

    rows: list[tuple] = []
    for row in proc.stdout.splitlines():
        cols = row.split("\t")
        if cols[0] == "fence_line" and len(cols) >= 5 and cols[2].isdigit():
            source = os.path.relpath(cols[1], skill_dir)
            rows.append(("fence_line", cols[1], int(cols[2]), cols[3], cols[4], source))
        elif cols[0] == "inline_code" and len(cols) >= 7:
            src_type = "bang" if cols[5] == "1" else "inline_code"
            source = os.path.relpath(cols[1], skill_dir)
            rows.append(("inline_code", cols[1], source, src_type, "", cols[6]))

    inv = Inventory()
    units = []
    for source, src_type, lang, text in logical_units(rows):
        if src_type != "fence_line":
            # A pipe inside a code span in a table cell is written `\|`.
            text = text.replace("\\|", "|")
        units.append((source, src_type, lang, text))
    awk_rows: list[str] = []
    seg_text: dict[tuple[int, int], str] = {}
    for unit_id, (source, src_type, lang, text) in enumerate(units):
        if (src_type != "fence_line" or lang.lower() in SHELLISH or lang == "") and (
            lang.lower() not in PROMPTED or PROMPT.match(text)
        ):
            # --check matches every segment of every code element; in a
            # console-style fence only a `$ ` prompt line is a command.
            tops, nested = split_segments(text)
            for seg in [s for s, _ in tops] + nested:
                inv.match_tokens.extend(token_variants(tokens_of(seg)))
        for idx, seg in enumerate(ordered_segments(text)):
            seg = seg.replace("\t", " ")
            seg_text[(unit_id, idx)] = seg
            awk_rows.append("%d\t%s\t%s\t%d\t%s" % (unit_id, src_type, lang, idx, seg))

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

    for unit_id, segs in sorted(verdicts.items()):
        source, src_type, lang, _ = units[unit_id]
        # #3464 F1: in a shell-labelled fence any command-shaped head is a
        # command, known or not, and each segment stands on its own. A console
        # fence mixes in output, so only a `$ ` prompt line qualifies there.
        explicit = (
            src_type == "fence_line"
            and lang.lower() in EXPLICIT_SHELL
            and (
                lang.lower() != "console" or bool(PROMPT.match(seg_text[(unit_id, 0)]))
            )
        )
        for idx in sorted(segs):
            ok, stripped = segs[idx]
            if ok != 1 and explicit:
                words = stripped.split()
                ok = int(
                    bool(words)
                    and bool(SHAPED.match(words[0]))
                    and words[0] not in SHELL_WORDS
                    # `key = value` is a config line pasted into the fence, and
                    # `ARR=(a b)` an array, not a VAR=val prefix on a command.
                    and not (len(words) > 1 and words[1] == "=")
                    and not ARRAY_ASSIGN.match(seg_text[(unit_id, idx)])
                )
            if idx == 0 and ok != 1 and not (explicit and stripped.startswith("[")):
                # The line does not start with a command (a regex, prose). In a
                # shell fence a `[ test ]` may open a line of real commands.
                break
            if ok == 1:
                inv.add(stripped, seg_text[(unit_id, idx)], source, src_type)
    return inv, len(files)


# --- check ---------------------------------------------------------------------
def grant_findings(
    skill_dir: str, inv: Inventory
) -> tuple[int, list[tuple[str, str, str]]]:
    sys.path.insert(0, LIB)
    from allowed_tools import bash_inner, classify, read_allowed_tools  # noqa: E402

    findings: list[tuple[str, str, str]] = []  # (severity, type, msg)
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
                    "ERROR",
                    kind,
                    "%s is a full-shell grant; list the commands the skill runs "
                    "as Bash(<command> *)" % token,
                )
            )
            continue
        pattern = " ".join(inner.split())
        for suffix in (":*", " *"):
            if pattern.endswith(suffix):
                pattern = pattern[: -len(suffix)].rstrip()
                break
        words = tokens_of(pattern)
        if not words:
            continue
        if QUOTED_ANCHOR.search(pattern):
            findings.append(
                (
                    "ERROR",
                    "quoted_script_grant",
                    "%s quotes the script path; write the rule unquoted, "
                    "Bash(%s *), which also matches a quoted invocation"
                    % (token, " ".join(words)),
                )
            )
        cls = grant_class(words)
        if no_subcommand(words):
            findings.append(
                (
                    "ERROR",
                    "no_subcommand",
                    "%s names no %s subcommand, so it admits every one; grant "
                    "the subcommands the skill runs, as Bash(%s <subcommand> *)"
                    % (token, words[0].rstrip("*"), words[0].rstrip("*")),
                )
            )
        elif cls and cls[0] == ARB:
            findings.append(
                (
                    "ERROR",
                    ARB,
                    "%s pre-approves arbitrary code (%s)" % (token, cls[1]),
                )
            )
        elif cls:
            findings.append(
                (
                    "WARN",
                    HAZ,
                    "%s pre-approves a hazardous command (%s); confirm running "
                    "it is what the skill is for" % (token, cls[1]),
                )
            )

        def matches(toks: list[str]) -> bool:
            return len(toks) >= len(words) and all(
                fnmatch.fnmatchcase(t, w) if "*" in w else t == w
                for w, t in zip(words, toks)
            )

        if not any(matches(t) for t in inv.match_tokens):
            head_seen = any(t and t[0] == words[0] for t in inv.match_tokens)
            msg = "%s matches no command the skill or its sidecars show" % token
            if head_seen and len(words) > 1:
                msg += "; it runs %s, but not as %s" % (words[0], " ".join(words))
            findings.append(("ERROR", "grant_not_in_body", msg))
    findings.sort(key=lambda f: 0 if f[0] == "ERROR" else 1)
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
        errors = sum(1 for f in findings if f[0] == "ERROR")
        item_status = "ERROR" if errors else ("WARN" if findings else "OK")
        print("GRANTS=%d" % grants)
        print("STATUS=%s" % item_status)
        if findings:
            first = next(f for f in findings if f[0] == item_status)
            reason = one_line("%s: %s" % (first[1], first[2]))[:180]
            if len(findings) > 1:
                reason += " (+%d more)" % (len(findings) - 1)
            print("REASON=%s" % reason)
        print("ISSUE_COUNT=%d" % len(findings))
        if findings:
            print("ISSUES:")
            for sev, itype, msg in findings:
                print("  - SEVERITY=%s TYPE=%s MSG=%s" % (sev, itype, one_line(msg)))
        print("=== END %s ===" % title)
        return 1 if errors else 0

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
    cands, reviews, drops = inv.resolved()
    for pattern in cands:
        print("CANDIDATE=%s" % pattern)
    for pattern, why in reviews:
        print("REVIEW=%s WHY=%s" % (pattern, why))
    for pattern, why in drops:
        print("DROPPED=%s WHY=%s" % (pattern, why))
    print("STATUS=OK")
    print("ISSUE_COUNT=0")
    print("=== END %s ===" % title)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

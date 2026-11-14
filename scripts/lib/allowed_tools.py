"""Parse and classify a skill's frontmatter `allowed-tools` grants (#3464).

Shared by scripts/check-bare-bash-grant.sh (the ratchet lint) and
scripts/skill-shell-commands.py --check (the per-skill verifier), so the two
read a grant list the same way. Standard library only.

Forms read, from the frontmatter between the first two `---` lines:
  allowed-tools: Bash, Read                 one-line
  allowed-tools: "Bash, Read"               quoted one-line
  allowed-tools: [Bash, Read]               flow list
  allowed-tools: [Read,                     flow list over several lines
    Bash]
  allowed-tools: Read, Grep,                plain scalar over several lines
    Bash
  allowed-tools:                            YAML block list
    - Bash
    - Read
Commas inside parentheses do not split a token: `Bash(jq -r .a,.b *)` is one
grant. A trailing YAML comment (` # ...` outside quotes) is dropped, as YAML
drops it, so `- Bash  # full shell` reads as a bare `Bash`; a block scalar
body (`allowed-tools: |`) is text in YAML and keeps its `#`.
"""

from __future__ import annotations

import re

INTERPRETERS = ("bash", "sh", "zsh", "python", "python3", "node")
# Flags after which an interpreter runs code from its next argument.
INLINE_FLAGS = {
    "bash": ("-c",),
    "sh": ("-c",),
    "zsh": ("-c",),
    "python": ("-c",),
    "python3": ("-c",),
    "node": ("-e", "-p", "--eval", "--print"),
}
# A pattern ending in a wildcard: ` *`, `:*`, or `*` glued to the last word.
TRAILING_WILDCARD = re.compile(r"^(.*?)(?: ?\*|:\*)$")


def is_broad_inner(inner: str) -> bool:
    """Bash(*), an interpreter wildcard, or an interpreter's inline-code wildcard.

    Each admits `<interp> -c '<anything>'` by prefix match, which is nearly a
    bare Bash. Whitespace is normalised (`bash  *`), the space before `*` is
    optional (`bash*`), a path prefix on the interpreter is ignored
    (`/bin/bash *`), so is a leading `env` (`env bash *`), and an interpreter
    followed by its inline-code flag is broad too (`bash -c *`, `node -e *`).
    """
    pattern = " ".join(inner.split())
    if pattern in ("*", ":*"):
        return True
    m = TRAILING_WILDCARD.match(pattern)
    if not m:
        return False
    words = m.group(1).split()
    if not words:
        return True
    if words[0].rsplit("/", 1)[-1] == "env":
        words = words[1:]
    if not words or "$" in words[0]:
        return False
    interp = words[0].rsplit("/", 1)[-1]
    if interp not in INTERPRETERS:
        return False
    rest = words[1:]
    return not rest or (len(rest) == 1 and rest[0] in INLINE_FLAGS[interp])


def split_top_level(value: str) -> list[str]:
    """Split on commas outside parentheses."""
    out, depth, cur = [], 0, []
    for ch in value:
        if ch == "(":
            depth += 1
        elif ch == ")" and depth:
            depth -= 1
        if ch == "," and depth == 0:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    out.append("".join(cur))
    return out


def _clean(token: str) -> str:
    token = token.strip()
    if len(token) >= 2 and token[0] == token[-1] and token[0] in "'\"":
        token = token[1:-1].strip()
    return token


def strip_comment(line: str) -> str:
    """Drop a YAML comment: a `#` at line start or after whitespace, outside quotes."""
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
        elif ch == "#" and (i == 0 or line[i - 1].isspace()):
            return line[:i].rstrip()
    return line


def frontmatter_lines(text: str) -> list[str]:
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return []
    fm = []
    for line in lines[1:]:
        if line.strip() == "---":
            return fm
        fm.append(line)
    return fm


def parse_allowed_tools(text: str) -> list[str]:
    """Return the allowed-tools tokens of a SKILL.md's text, in order."""
    fm = frontmatter_lines(text)
    for i, line in enumerate(fm):
        m = re.match(r"^allowed-tools:[ \t]*(.*)$", line)
        if not m:
            continue
        value = strip_comment(m.group(1)).strip()
        block_scalar = value in ("|", ">", "|-", ">-")
        if value and not block_scalar:
            if value[0] not in "[\"'":
                # A plain scalar continues on the following indented lines.
                for nxt in fm[i + 1 :]:
                    if not nxt.strip():
                        continue
                    if not nxt[0].isspace():
                        break
                    more = strip_comment(nxt).strip()
                    if more:
                        value += " " + more
            value = _clean(value)
            if value.startswith("[") and "]" not in value:
                # A flow list continued on the following lines.
                for nxt in fm[i + 1 :]:
                    value += " " + strip_comment(nxt).strip()
                    if "]" in nxt:
                        break
            if value.startswith("[") and value.endswith("]"):
                value = value[1:-1]
            return [t for t in (_clean(x) for x in split_top_level(value)) if t]
        tokens: list[str] = []
        for nxt in fm[i + 1 :]:
            if nxt and not nxt[0].isspace() and not nxt.startswith("-"):
                break
            item = (nxt if block_scalar else strip_comment(nxt)).strip()
            if item.startswith("- "):
                tokens.append(_clean(item[2:]))
            elif item and item != "-":  # block scalar body: comma-separated text
                tokens.extend(_clean(x) for x in split_top_level(item))
        return [t for t in tokens if t]
    return []


def read_allowed_tools(path: str) -> list[str]:
    with open(path, encoding="utf-8", errors="replace") as fh:
        return parse_allowed_tools(fh.read())


def bash_inner(token: str) -> str | None:
    """The pattern inside Bash(...), or None when the token is not a Bash(...)."""
    m = re.match(r"^Bash\((.*)\)$", token)
    return m.group(1).strip() if m else None


def classify(token: str) -> str | None:
    """'bare_bash', 'broad_shell_grant', or None for a narrow or non-Bash token."""
    if token == "Bash":
        return "bare_bash"
    inner = bash_inner(token)
    if inner is not None and is_broad_inner(inner):
        return "broad_shell_grant"
    return None

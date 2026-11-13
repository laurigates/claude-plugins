"""Parse and classify a skill's frontmatter `allowed-tools` grants (#3464).

Shared by scripts/check-bare-bash-grant.sh (the ratchet lint) and
scripts/skill-shell-commands.py --check (the per-skill verifier), so the two
read a grant list the same way. Standard library only.

Forms read, from the frontmatter between the first two `---` lines:
  allowed-tools: Bash, Read                 one-line
  allowed-tools: "Bash, Read"               quoted one-line
  allowed-tools: [Bash, Read]               flow list
  allowed-tools:                            YAML block list
    - Bash
    - Read
Commas inside parentheses do not split a token: `Bash(jq -r .a,.b *)` is one
grant.
"""

from __future__ import annotations

import re

INTERPRETERS = ("bash", "sh", "zsh", "python", "python3", "node")
# Bash(*), or Bash(<interp> *) / Bash(<interp>:*): each admits `<interp> -c
# '<anything>'` by prefix match, which is nearly a bare Bash.
BROAD_INNER = re.compile(r"^(\*|(?:%s)(?: \*|:\*))$" % "|".join(INTERPRETERS))


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
        value = m.group(1).strip()
        if value and value not in ("|", ">", "|-", ">-"):
            value = _clean(value)
            if value.startswith("[") and value.endswith("]"):
                value = value[1:-1]
            return [t for t in (_clean(x) for x in split_top_level(value)) if t]
        tokens: list[str] = []
        for nxt in fm[i + 1:]:
            if nxt and not nxt[0].isspace() and not nxt.startswith("-"):
                break
            item = nxt.strip()
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
    if inner is not None and BROAD_INNER.match(inner):
        return "broad_shell_grant"
    return None

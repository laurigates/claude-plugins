#!/usr/bin/env python3
"""Project this marketplace's subagents into pi-subagents' agent format.

Why this exists when pi needs no *skill* export: pi reads Claude Code
`SKILL.md` in place through the ADR-0022 adapter (`adapters/pi/`), but it does
**not** read `.claude/agents/` — so all 21 marketplace subagents are invisible
in pi until they are projected into one of pi-subagents' three discovery
locations (`<cwd>/.pi/agents/`, `<cwd>/.agents/agents/`, or
`$PI_CODING_AGENT_DIR/agents/`, default `~/.pi/agent/agents/`).

Unlike the OpenCode projection (#2094), pi's agent schema is *rich*: `model`,
`tools`, `color`, `thinking`, `max_turns`, and nested delegation all have real
fields, so almost everything survives. The two edges that do not are lossy, and
both are reported rather than adjusted silently:

  1. **`Bash(<cmd> *)` scope is dropped.** pi's `tools:` is a name-only
     allowlist — there is no per-command scoping in the schema — so a scoped
     Claude Code grant becomes an unscoped `bash`. That is a *privilege
     widening* (143 entries across the corpus today), counted as
     `WIDENED_BASH=` and listed per agent. Nothing in this repo can narrow it;
     it is a property of the target schema.
  2. **Claude-Code-only tools are dropped**, because no pi built-in exists for
     them: `TodoWrite`, `TaskOutput`, `WebFetch`, `WebSearch`, `NotebookEdit`.
     They are reported as `DROPPED_TOOLS=` per agent.
     `WebFetch`/`WebSearch` *could* be reached as `ext:` selectors (the tool is
     provided by the optional `pi-web-search` extension), but a single `ext:`
     entry flips pi's extension tools into explicit-allowlist mode — the agent
     would silently lose everything else the adapter exposes (`search_skills`
     among it) — so that is left as an explicit opt-in for a human, not applied
     here.

Tool mapping (`pi` 0.84.1: `BUILTIN_TOOL_NAMES` = `createCodingTools` +
`createReadOnlyTools` = read, bash, edit, write, grep, find, ls):

    Read  -> read      Write -> write    Edit -> edit
    Glob  -> find      Grep  -> grep     Bash(...) -> bash
    Agent(a, b) -> allowed_subagents: a, b   (nesting, not a built-in grant)
    skills: [a, b] -> skills: a, b           (both preload into the agent's prompt)
    "*" / all -> "*"   none / "" -> none

Two source fields are deliberately **not** mapped, and are reported instead:
`context:` (10 agents) because pi has no counterpart to assert — a pi subagent
always runs in its own session, so Claude Code's fork-isolation is pi's default,
while pi's `inherit_context:` is the *opposite* direction and inferring it would
be a guess; and any future unknown field, which lands in `DROPPED_KEYS=` rather
than vanishing.

Usage: export-pi-agents.py <repo-root> <out-dir>
Emits <out-dir>/agents/<name>.md plus a KEY=VALUE report.
"""

import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - PyYAML is a hard dependency of the repo
    print("ERROR=PyYAML not available (pip install pyyaml)", file=sys.stderr)
    sys.exit(1)

# pi's built-in tool names, from `createCodingTools()` + `createReadOnlyTools()`
# in @earendil-works/pi-coding-agent (dist/core/tools/index.js). A `tools:`
# entry outside this set is an error in pi ("tools-error:…"), so the exporter
# validates against it rather than trusting the map.
PI_BUILTIN_TOOLS = ("read", "bash", "edit", "write", "grep", "find", "ls")

# Claude Code tool name -> pi built-in. Absent names are handled explicitly
# below (Bash/Agent are transformed; the rest are reported as dropped).
TOOL_MAP = {
    "Read": "read",
    "Write": "write",
    "Edit": "edit",
    "Glob": "find",
    "Grep": "grep",
}

# No pi built-in equivalent. Kept as a named tuple so the report can say which
# one went missing rather than just how many.
DROPPED_TOOLS = ("TodoWrite", "TaskOutput", "WebFetch", "WebSearch", "NotebookEdit")

# Source frontmatter keys this projection owns; anything else is reported as a
# dropped key so a new field cannot be added to an agent and vanish silently.
# `context` is intentionally absent from both tuples: it is a real Claude Code
# field (agent-development.md: `fork` = isolated context) with no pi counterpart
# to assert, so it is reported alongside genuinely unknown keys.
MAPPED_KEYS = (
    "name",
    "description",
    "model",
    "color",
    "thinking",
    "maxTurns",
    "tools",
    "skills",
)
IGNORED_KEYS = ("created", "modified", "reviewed")


def split_frontmatter(text: str) -> tuple[dict, str]:
    """Return (frontmatter, body). Raises ValueError on a missing/broken block."""
    if not text.startswith("---\n"):
        raise ValueError("no frontmatter block at line 1")
    end = text.find("\n---\n", 3)
    if end == -1:
        raise ValueError("unterminated frontmatter block")
    front = yaml.safe_load(text[4:end]) or {}
    if not isinstance(front, dict):
        raise ValueError("frontmatter is not a mapping")
    return front, text[end + 5 :]


def split_tools(raw: object) -> list[str]:
    """Split a Claude Code `tools:` value, respecting parentheses.

    Claude Code writes `tools: Read, Grep, Bash(git diff *), Agent(a, b)`, so a
    naive comma split turns `Agent(a, b)` into two bogus entries — and would
    turn a nested-agent list into tool names. Depth 0 is the only place a comma
    separates two entries.
    """
    if raw is None:
        return []
    if isinstance(raw, (list, tuple)):
        return [str(item).strip() for item in raw if str(item).strip()]
    text = str(raw)
    if text.strip() in ("", "none"):
        return []
    entries, depth, current = [], 0, []
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        if ch == "," and depth == 0:
            entries.append("".join(current).strip())
            current = []
        else:
            current.append(ch)
    entries.append("".join(current).strip())
    return [entry for entry in entries if entry]


def translate_tools(raw: object) -> tuple[list[str], list[str], list[str], int]:
    """Return (built-ins, allowed_subagents, dropped, widened_bash_count).

    `Agent(...)` is not a tool grant in pi — it is the nested-delegation
    allowlist (`allowed_subagents`), which is default-off and deliberately
    separate from `tools:`. Mapping it to a tool name would be a silent no-op.
    """
    builtins: list[str] = []
    nested: list[str] = []
    dropped: list[str] = []
    widened = 0

    for entry in split_tools(raw):
        if entry in ("*", "all"):
            return list(PI_BUILTIN_TOOLS), nested, dropped, widened
        if entry.lower() == "none":
            continue
        name, _, args = entry.partition("(")
        name = name.strip()
        args = args.rstrip(")").strip()
        if name == "Bash":
            # Scoped or not, pi only understands the name.
            if args:
                widened += 1
            if "bash" not in builtins:
                builtins.append("bash")
        elif name == "Agent":
            nested.extend(a.strip() for a in args.split(",") if a.strip())
        elif name == "Task":
            # Claude Code's pre-rename spelling of a subagent dispatch; the
            # allowlist semantics are the same as Agent(...).
            nested.extend(a.strip() for a in args.split(",") if a.strip())
        elif name in TOOL_MAP:
            mapped = TOOL_MAP[name]
            if mapped not in builtins:
                builtins.append(mapped)
        elif name in DROPPED_TOOLS:
            if name not in dropped:
                dropped.append(name)
        else:
            # Unknown name: report it as dropped rather than emit it, because
            # an unknown `tools:` entry is a hard error in pi.
            if name not in dropped:
                dropped.append(name)

    return builtins, nested, dropped, widened


def render(
    front: dict, body: str, fallback_name: str
) -> tuple[str, int, list[str], list[str], bool]:
    """Return (file text, widened_bash count, dropped tools, builtins, has_nesting)."""
    out: dict = {}
    out["name"] = front.get("name") or fallback_name
    # A source `description: |` block folds to one logical line here. Whitespace
    # only differs, and a folded multi-line YAML scalar would make the emitted
    # header depend on the reader's folding support — pi shows this string in its
    # agent listing, so one line is both cleaner and safer.
    out["description"] = " ".join(str(front["description"]).split())
    for key in ("color", "model", "thinking"):
        if front.get(key):
            out[key] = front[key]
    if front.get("maxTurns") is not None:
        # pi's spelling; `maxTurns` would be ignored as an unknown key.
        out["max_turns"] = int(front["maxTurns"])

    builtins, nested, dropped, widened = translate_tools(front.get("tools"))
    # `tools: none` is the one value where omitting the key is NOT equivalent:
    # an omitted `tools:` grants all 7 built-ins in pi, which is the right
    # reading of an absent key (Claude Code inherits all there too) but the
    # opposite of an explicit none. Emit it so the narrowing survives.
    raw_tools = front.get("tools")
    explicit_none = isinstance(raw_tools, str) and raw_tools.strip().lower() == "none"
    if builtins:
        out["tools"] = ", ".join(builtins)
    elif explicit_none:
        out["tools"] = "none"
    if nested:
        # Dedupe, preserving declaration order.
        out["allowed_subagents"] = ", ".join(dict.fromkeys(nested))
    skills = front.get("skills")
    if isinstance(skills, (list, tuple)) and skills:
        # Claude Code: "skill names to preload into agent context at startup"
        # (agent-development.md § Frontmatter Fields). pi's list form preloads
        # those skills AND does not inherit the parent's rest — the preload
        # intent is shared, the inheritance edge is not, and pi is the narrower
        # of the two. Left in on that basis; `skills: true` (the pi default) is
        # never emitted, so an agent that declares none keeps inheriting.
        out["skills"] = ", ".join(str(skill) for skill in skills)

    # width=10**6: never wrap. A wrapped plain scalar is valid YAML *only* if the
    # reader implements flow folding, and a description split across lines is not
    # worth betting on the reader for. allow_unicode keeps an em dash literal
    # rather than `\u2014`, which a non-unescaping reader would show verbatim.
    header = yaml.safe_dump(
        out, default_flow_style=False, sort_keys=False, width=10**6, allow_unicode=True
    )
    return (
        f"---\n{header}---\n{body.lstrip(chr(10))}",
        widened,
        dropped,
        builtins,
        bool(nested),
    )


def main(repo_root: Path, out_dir: Path) -> int:
    agents_out = out_dir / "agents"
    agents_out.mkdir(parents=True, exist_ok=True)

    sources = sorted(repo_root.glob("*-plugin/agents/*.md"))
    written, skipped = 0, []
    widened_total, nested_total, model_pins = 0, 0, 0
    dropped_by_tool: dict[str, int] = {}
    dropped_keys: dict[str, list[str]] = {}

    for src in sources:
        rel = src.relative_to(repo_root)
        try:
            front, body = split_frontmatter(src.read_text(encoding="utf-8"))
            if not front.get("description"):
                # pi routes subagents by description; emitting one without it
                # produces an agent the model can never be told to pick.
                skipped.append(f"{rel}: no description")
                continue
            # Rendered inside the try: one malformed agent must be SKIPPED and
            # reported, never a traceback that aborts the other 20.
            text, widened, dropped, builtins, has_nesting = render(
                front, body, src.stem
            )
        except (ValueError, TypeError, yaml.YAMLError) as exc:
            skipped.append(f"{rel}: {exc}")
            continue
        (agents_out / src.name).write_text(text, encoding="utf-8")
        written += 1
        widened_total += widened
        if front.get("model"):
            model_pins += 1
        if has_nesting:
            nested_total += 1
        for tool in dropped:
            dropped_by_tool[tool] = dropped_by_tool.get(tool, 0) + 1
        extra = [
            key for key in front if key not in MAPPED_KEYS and key not in IGNORED_KEYS
        ]
        if extra:
            dropped_keys[str(rel)] = [str(key) for key in extra]

        # Guard integrity: validate the emitted tool names against pi's built-in
        # set. A mapper bug must fail loudly here, not produce an agent that pi
        # rejects at load time with `tools-error:…`.
        for name in builtins:
            if name not in PI_BUILTIN_TOOLS:
                print(
                    f"ERROR=emitted unknown pi tool {name!r} for {rel}",
                    file=sys.stderr,
                )
                return 1

    print("=== PI AGENT EXPORT ===")
    print(f"SOURCE={repo_root}")
    print(f"OUTPUT={agents_out}")
    print(f"SOURCE_AGENTS={len(sources)}")
    print(f"OUTPUT_AGENTS={written}")
    print(f"SKIPPED_AGENTS={len(skipped)}")
    print(f"MODEL_PINS={model_pins}")
    print(f"AGENTS_WITH_NESTING={nested_total}")
    print(f"WIDENED_BASH={widened_total}")
    print(
        "DROPPED_TOOLS="
        + ",".join(f"{k}:{v}" for k, v in sorted(dropped_by_tool.items()))
    )
    for name, keys in sorted(dropped_keys.items()):
        print(f"DROPPED_KEYS={name}:{','.join(keys)}")
    for entry in skipped:
        print(f"SKIPPED={entry}")
    if skipped:
        print("STATUS=WARN")
        print(f"ISSUE_COUNT={len(skipped)}")
    else:
        print("STATUS=OK")
        print("ISSUE_COUNT=0")
    print("=== END PI AGENT EXPORT ===")
    return 1 if skipped else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: export-pi-agents.py <repo-root> <out-dir>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()))

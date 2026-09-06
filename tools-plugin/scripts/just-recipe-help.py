#!/usr/bin/env python3
"""What does this just recipe take? -- the flag list, without opening the script.

`just --list` renders ONE line per recipe, and a justfile that keeps its
reasoning in the comment block above each recipe cannot show it there. Worse,
with no `[doc()]` attribute just falls back to that block's LAST line -- almost
always the tail of an example -- so a well-commented justfile lists as a wall
of fragments and the flags of the tool a recipe wraps are reachable only by
opening it.

Two mechanical reasons the obvious escapes do not work:

  1. `just <recipe> --help` is REFUSED BY JUST for any recipe with a required
     positional: "got 1 positional argument but takes at least 2". There is no
     bare-help spelling for such a recipe.
  2. Supplying dummy positionals does reach the tool -- and a script whose
     argparse sits behind a module-scope import of a heavy dependency raises
     ImportError before argparse ever runs, so --help is unreachable on any
     checkout without that dependency installed.

So this reads the SHIPPED SOURCE rather than running it: the recipe's own
comment block out of the justfile, and the flags out of the script's AST. It
imports nothing but the stdlib and needs no virtualenv, so it answers the same
everywhere.

It is NOT a substitute for argparse's own output and must not drift into one.
Where the tool's dependencies are installed its own --help is authoritative,
and this prints the exact command that reaches it.

USAGE
    just-recipe-help.py <recipe>        # comment block + flags for one recipe
    just-recipe-help.py <script.py>     # one script by name
    just-recipe-help.py --audit         # recipes with no [doc()] summary
    just-recipe-help.py --justfile PATH --audit

Wire it into the justfile it documents so it is reachable the way everything
else is:

    [doc("What a recipe takes: its notes plus the flags of the script it runs.")]
    help *ARGS:
        @python3 scripts/just-recipe-help.py {{ARGS}}
"""

from __future__ import annotations

import argparse
import ast
import os
import pathlib
import re
import shutil
import subprocess
import sys

DOC = __doc__ or ""

#: A recipe header at column 0: `name PARAMS:` or `name PARAMS: dependency`.
#:
#: `(?!=)` is what excludes a `NAME := value` assignment, and it is the ONLY
#: thing that may: the params MUST be allowed to contain `=`, because a default
#: value is spelled `PYBIN="python3"`. Forbidding `=` in the params silently
#: drops every recipe that takes a default -- an under-report that reads
#: exactly like a justfile with fewer recipes in it, which is why
#: test-just-recipe-help.sh diffs this parse against `just --summary`.
RECIPE_RE = re.compile(r"^(?P<name>[a-z0-9_][a-z0-9_-]*)(?P<params>[^:\n]*):(?!=)")

DOC_RE = re.compile(r'^\[doc\("(?P<text>.*)"\)\]$')

#: A path ending in .py or .sh anywhere in a recipe body, including the
#: `{{var}}` interpolations a justfile uses to build one.
SCRIPT_RE = re.compile(r"[\w./{}()\- ]*?[\w\-]+\.(?:py|sh)")

#: `{{ anything }}`
INTERP_RE = re.compile(r"\{\{[^}]*\}\}")


# --------------------------------------------------------------- the justfile


def find_justfile(explicit=None):
    """The justfile to read: --justfile, else the nearest one at or above cwd."""
    if explicit:
        p = pathlib.Path(explicit).expanduser().resolve()
        if not p.is_file():
            raise SystemExit(f"just-recipe-help: no justfile at {p}")
        return p
    here = pathlib.Path.cwd().resolve()
    for d in (here, *here.parents):
        for name in ("justfile", "Justfile", ".justfile", "JUSTFILE"):
            p = d / name
            if p.is_file():
                return p
    raise SystemExit(
        f"just-recipe-help: no justfile at or above {here}. Pass --justfile PATH."
    )


def just_variables(justfile):
    """Resolved justfile variables, from `just --evaluate`.

    This is the one place the tool shells out, and it is optional: without it a
    `{{SCRIPTS}}/foo.py` body cannot be resolved to a path and the basename
    search below takes over. Failing soft matters more than resolving every
    path -- a missing `just` must not turn the whole tool off.
    """
    if shutil.which("just") is None:
        return {}
    try:
        out = subprocess.run(
            ["just", "--justfile", str(justfile), "--evaluate"],
            capture_output=True,
            text=True,
            timeout=20,
            cwd=str(justfile.parent),
            env={**os.environ, "NO_COLOR": "1"},
        )
    except (OSError, subprocess.SubprocessError):
        return {}
    if out.returncode != 0:
        return {}
    variables = {}
    for line in out.stdout.splitlines():
        m = re.match(r'^(\w+)\s*:=\s*"(.*)"$', line.strip())
        if m:
            variables[m.group(1)] = m.group(2)
    return variables


class Recipe:
    """One recipe, with everything `just --list` throws away."""

    def __init__(self, name, params, doc, comment, body, line, attrs=()):
        self.name = name
        self.params = params.strip()
        self.doc = doc  # the [doc("...")] summary, or ""
        self.comment = comment  # the whole preceding # block, verbatim
        self.body = body
        self.line = line
        self.attrs = list(attrs)

    @property
    def private(self):
        """Hidden from `just --list` and `--summary` -- so it has nothing to
        summarise there, and the audit must not demand a [doc()] for it.

        TWO mechanisms, and the second is easy to miss: the `[private]`
        attribute, and a LEADING UNDERSCORE, which just acts on by itself. A
        `_helper:` with no attribute is absent from both listings. Checking
        only the attribute makes the parse disagree with `just --summary` on
        any justfile using the underscore convention.
        """
        return any(
            a.strip() == "[private]" for a in self.attrs
        ) or self.name.startswith("_")

    @property
    def needs_doc(self):
        """Would `just --list` show nothing, or a fragment? -> (bool, why).

        Two criteria this deliberately does NOT use, both tried and both wrong:

        "has no [doc()]" flags every well-written justfile in existence -- a
        single-line comment is a good description and just renders it
        faithfully. "has a MULTI-line block" is nearly as bad: the careful way
        to write one is a long block ending in a deliberate one-line summary,
        exactly so `--list` shows that. Flagging it punishes the right habit,
        and a gate that fires on everything is one nobody reads.

        What IS mechanically a fragment is the shape of the last line, since
        that is the only line just shows:
        """
        if self.private or self.doc:
            return None
        lines = [line for line in self.comment.splitlines() if line.strip()]
        if not lines:
            return "no comment block -- the listing is blank"
        last = lines[-1].lstrip("#")
        body = last.strip()
        if not body:
            return "the block's last line is empty"
        # An indented line is a sub-item of the one above it, never a summary.
        if last.startswith("  "):
            return "the last line is indented, so it is a sub-item"
        # A command example, which is what a block most often ends with.
        if re.match(r"(just|\$|\./|uv|bun|npm|cargo|go|python3?|docker)\s", body):
            return "the last line is a command example"
        # A sentence continuing from the line above. A description does not
        # begin lowercase; a wrapped clause almost always does.
        if body[0].islower():
            return "the last line continues a sentence from the line above"
        return None

    def script_token(self):
        """The raw `.py`/`.sh` token in the body, interpolations intact."""
        m = SCRIPT_RE.search(self.body)
        return m.group(0).strip() if m else None


def parse_justfile(text):
    """Every recipe with its attributes, preceding comment block, and body.

    Written against the source rather than `just --dump --dump-format json`
    on purpose: the dump discards the comment block entirely, and the comment
    block is the thing this tool exists to surface.
    """
    lines = text.splitlines()
    recipes = {}
    for i, line in enumerate(lines):
        m = RECIPE_RE.match(line)
        if not m:
            continue

        # Walk back over any attribute lines, then over the contiguous comment
        # block. A blank line ends the block -- which is also just's own rule
        # for which comment becomes a recipe's description.
        j = i - 1
        doc = ""
        attrs = []
        while j >= 0 and lines[j].startswith("["):
            attrs.append(lines[j])
            d = DOC_RE.match(lines[j].strip())
            if d:
                doc = d.group("text")
            j -= 1
        comment = []
        while j >= 0 and lines[j].startswith("#"):
            comment.append(lines[j])
            j -= 1
        comment.reverse()

        k = i + 1
        body = []
        while k < len(lines) and (
            lines[k].startswith((" ", "\t")) or not lines[k].strip()
        ):
            body.append(lines[k])
            k += 1

        recipes[m.group("name")] = Recipe(
            m.group("name"),
            m.group("params"),
            doc,
            "\n".join(comment).rstrip(),
            "\n".join(body),
            i + 1,
            attrs,
        )
    return recipes


def resolve_script(token, justfile, variables):
    """A body's script token -> (path, pattern).

    Exactly one of the two is set. `pattern` means the recipe builds its script
    NAME from a parameter (`build_{{piece}}_workflow.py`), so there is no single
    flag list -- reporting that is not the same as reporting no script at all,
    and conflating them hides whole families of tool.
    """
    if token is None:
        return None, None

    resolved = token
    for var, value in variables.items():
        resolved = resolved.replace("{{%s}}" % var, value)
        resolved = resolved.replace("{{ %s }}" % var, value)
    for fn in ("source_directory()", "justfile_directory()", "invocation_directory()"):
        resolved = resolved.replace("{{%s}}" % fn, str(justfile.parent))
        resolved = resolved.replace("{{ %s }}" % fn, str(justfile.parent))

    basename = resolved.rsplit("/", 1)[-1]
    if INTERP_RE.search(basename):
        # A parameterised NAME. Anything still interpolated in the directory
        # part is fine -- the basename is what decides there is no one script.
        return None, basename

    # Strip any unresolved directory interpolation and try the path as given,
    # then relative to the justfile, then by basename anywhere beneath it.
    candidate = pathlib.Path(INTERP_RE.sub("", resolved).replace("//", "/"))
    for p in (candidate, justfile.parent / candidate):
        if p.is_file():
            return p.resolve(), None
    matches = sorted(justfile.parent.rglob(basename))
    if len(matches) == 1:
        return matches[0].resolve(), None
    return None, None


# ---------------------------------------------------------- the argparse scan


def _keyword(node) -> "tuple[object, bool]":
    """A keyword argument as (value, was_a_literal).

    Both halves are needed: `action="store_true"` has to compare equal to the
    Python string, while `default=PYBIN` has to print as the source text and
    not as the string `'PYBIN'`.
    """
    if isinstance(node, ast.Constant):
        return node.value, True
    try:
        return ast.unparse(node), False
    except Exception:  # pragma: no cover
        return "<unparseable>", False


def scan_arguments(path):
    """Every add_argument in a script, grouped by subcommand, in source order.

    Returns (groups, unresolved). `groups` maps a subcommand name (or None for
    the main parser) to {"help": str, "args": [...]}.

    Every add_parser is registered up front, EVEN IF IT TAKES NO ARGUMENTS: a
    subcommand whose whole interface is its name is precisely the one a reader
    cannot recover from anywhere else, and building the groups from
    add_argument alone drops it silently.

    `unresolved` counts add_argument calls whose flag name is not a literal --
    ones this scan CANNOT report. It is returned rather than swallowed because
    an under-reported flag list is indistinguishable from a script that
    genuinely lacks the flag, so the caller refuses instead of printing a short
    list that looks complete.
    """
    tree = ast.parse(path.read_text(errors="replace"))
    groups: dict = {}
    unresolved = 0
    # The sub-parser most recently assigned; None means the main parser. A
    # one-element list so the nested visit() can rebind it without `nonlocal`.
    current: list = [None]

    def group(name):
        return groups.setdefault(name, {"help": "", "args": []})

    def visit(stmts):
        nonlocal unresolved
        for st in stmts:
            if isinstance(st, ast.Assign) and isinstance(st.value, ast.Call):
                f = st.value.func
                fname = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
                if (
                    fname == "add_parser"
                    and st.value.args
                    and isinstance(st.value.args[0], ast.Constant)
                ):
                    current[0] = st.value.args[0].value
                    g = group(current[0])
                    for k in st.value.keywords:
                        if k.arg == "help" and isinstance(k.value, ast.Constant):
                            g["help"] = k.value.value
                    continue
                if fname == "ArgumentParser":
                    current[0] = None
                    continue

            call = (
                st.value
                if isinstance(st, ast.Expr) and isinstance(st.value, ast.Call)
                else None
            )
            if (
                call is not None
                and isinstance(call.func, ast.Attribute)
                and call.func.attr == "add_argument"
            ):
                if not call.args or not isinstance(call.args[0], ast.Constant):
                    unresolved += 1
                    continue
                flags = [a.value for a in call.args if isinstance(a, ast.Constant)]
                kw: dict = {}
                lit: dict = {}
                for k in call.keywords:
                    if k.arg:
                        kw[k.arg], lit[k.arg] = _keyword(k.value)
                group(current[0])["args"].append((flags, kw, lit))
                continue

            # Recurse into compound statements so an add_argument inside a
            # function, an `if`, or a loop is still seen, in source order.
            for field in ("body", "orelse", "finalbody"):
                inner = getattr(st, field, None)
                if isinstance(inner, list):
                    visit(inner)

    visit(tree.body)
    return groups, unresolved


def render_argument(flags, kw, lit):
    """One argument as a signature line plus its indented help text."""
    action = kw.get("action", "")
    if not flags[0].startswith("-"):
        sig = flags[0]
    else:
        metavar = kw.get("metavar")
        if action in ("store_true", "store_false", "count", "help", "version"):
            metavar = ""
        elif kw.get("choices") is not None:
            metavar = "{%s}" % str(kw["choices"]).strip("[]").replace("'", "")
        elif metavar is None:
            metavar = flags[-1].lstrip("-").replace("-", "_").upper()
        sig = ", ".join(flags) + (f" {metavar}" if metavar else "")

    notes = []
    if kw.get("required") is True:
        notes.append("REQUIRED")
    if kw.get("nargs"):
        notes.append(f"nargs {kw['nargs']}")
    if "default" in kw and kw["default"] is not None:
        d = repr(kw["default"]) if lit.get("default") else kw["default"]
        notes.append(f"default {d}")

    out = [f"  {sig:<32}{'  '.join(notes)}".rstrip()]
    helptext = kw.get("help")
    if isinstance(helptext, str) and lit.get("help"):
        for para in helptext.split("\n"):
            para = para.strip()
            if para:
                out.append(f"      {para}")
    return out


def print_flags(path, label):
    """The argparse surface of one script."""
    if path.suffix != ".py":
        print(f"FLAGS  not scanned: {label} is a shell script, not argparse.")
        return 0
    try:
        groups, unresolved = scan_arguments(path)
    except SyntaxError as e:
        print(f"FLAGS  CANNOT READ: {label} does not parse ({e}).", file=sys.stderr)
        return 3
    if unresolved:
        print(
            f"FLAGS  REFUSING to print a partial list: {unresolved} "
            f"add_argument call(s) in",
            file=sys.stderr,
        )
        print(
            f"       {label} name their flag dynamically and cannot be read "
            f"statically.",
            file=sys.stderr,
        )
        print("       Run the script's own --help instead.", file=sys.stderr)
        return 3

    if not groups:
        print(f"FLAGS  none -- {label} defines no argparse arguments.")
    for name, g in groups.items():
        if name is None:
            print(f"FLAGS  ({label})")
        else:
            print(f"SUBCOMMAND  {name}" + (f"  -- {g['help']}" if g["help"] else ""))
        for flags, kw, lit in g["args"]:
            for line in render_argument(flags, kw, lit):
                print(line)
        if not g["args"] and name is not None:
            print("  (no flags of its own)")
        print()
    return 0


# ----------------------------------------------------------------- the output


def show(recipe, justfile, variables, prefix):
    print(f"just {prefix}{recipe.name} {recipe.params}".rstrip())
    if recipe.doc:
        print(f"    {recipe.doc}")
    print(f"    {justfile}:{recipe.line}")

    token = recipe.script_token()
    path, pattern = resolve_script(token, justfile, variables)
    if path:
        try:
            print(f"    {path.relative_to(justfile.parent)}")
        except ValueError:
            print(f"    {path}")
    print()

    if recipe.comment:
        print("NOTES  (the recipe's own comment block, verbatim)")
        for line in recipe.comment.splitlines():
            print(f"  {line}")
    else:
        print("NOTES  none -- this recipe has no comment block in the justfile.")
    print()

    if pattern:
        glob = INTERP_RE.sub("*", pattern)
        found = sorted(p.name for p in justfile.parent.rglob(glob))
        print("FLAGS  this recipe builds its script name from a parameter:")
        print(f"         {pattern}")
        print("       so there is no single flag list. The scripts matching it")
        print("       in this checkout, each readable by name:\n")
        for f in found:
            print(f"         just {prefix}help {f}")
        if not found:
            print(f"         (none match {glob} here)")
        return 0

    if not path:
        if token:
            print("FLAGS  the recipe names a script this tool could not locate:")
            print(f"         {token}")
            print("       Read the body:  just --show " + recipe.name)
            return 3
        print("FLAGS  none to read: this recipe runs inline shell or a fixed")
        print("       command rather than forwarding to one script. Read its")
        print("       body:  just --show " + recipe.name)
        return 0

    rc = print_flags(path, path.name)
    if rc:
        return rc

    # Spell out the required positionals: without them just refuses the call
    # before the script is reached, which is half of why this tool exists.
    tail = [
        p
        for p in recipe.params.split()
        if not p.startswith(("*", "+")) and "=" not in p
    ]
    print("Argparse's own text, where the script's dependencies are installed:")
    print("  " + " ".join(["just", f"{prefix}{recipe.name}", *tail, "--help"]))
    return 0


def show_script(name, justfile):
    """A script asked for by name: its docstring, then its flags."""
    matches = sorted(justfile.parent.rglob(name))
    if not matches:
        print(f"no script named {name!r} under {justfile.parent}.", file=sys.stderr)
        return 2
    path = matches[0]
    try:
        rel = path.relative_to(justfile.parent)
    except ValueError:  # pragma: no cover
        rel = path
    print(f"{rel}\n")
    if path.suffix == ".py":
        try:
            doc = ast.get_docstring(ast.parse(path.read_text(errors="replace")))
        except SyntaxError as e:
            doc = f"(does not parse: {e})"
        if doc:
            print("NOTES  (the script's own module docstring)")
            for line in doc.splitlines():
                print(f"  {line}")
        else:
            print("NOTES  none -- this script has no module docstring.")
        print()
    return print_flags(path, str(rel))


def audit(recipes, justfile):
    """Which recipes `just --list` cannot summarise.

    A recipe with no [doc()] falls back to the LAST LINE of its comment block.
    Where that block carries examples or caveats the line is a fragment, so the
    listing reads as noise and stops being scanned.

    Only genuinely at-risk recipes are reported -- see Recipe.needs_doc. A
    one-line comment is a good description and is left alone, because a gate
    that fires on every well-written justfile is a gate nobody reads.
    """
    listed = [r for r in recipes.values() if not r.private]
    missing = [(r, r.needs_doc) for r in listed if r.needs_doc]
    print(f"{justfile}")
    print(
        f"{len(recipes)} recipe(s), {len(listed)} listed by `just --list`; "
        f"{len(missing)} with an unusable description."
    )
    for r, why in sorted(missing, key=lambda t: t[0].name):
        fallback = r.comment.splitlines()[-1].lstrip("# ").strip() if r.comment else ""
        print(f"  {r.name:26} {why}")
        if fallback:
            print(f"  {'':26} --list shows: {fallback[:60]}")
    if missing:
        print(
            '\nAdd a [doc("one line")] above each. The comment block stays '
            "where it\nis -- `just help <recipe>` is what prints it."
        )
        return 1
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=DOC.splitlines()[0])
    ap.add_argument(
        "target",
        nargs="?",
        help="the recipe, or a script name, to explain; omit for this tool's own usage",
    )
    ap.add_argument(
        "--justfile",
        help="the justfile to read (default: the nearest one at or above the cwd)",
    )
    ap.add_argument(
        "--module",
        default="",
        help="module prefix to print in example commands, e.g. "
        "'lab::' for a recipe reached as `just lab::build`",
    )
    ap.add_argument(
        "--audit",
        action="store_true",
        help="report recipes with no [doc()] summary, and exit "
        "non-zero if any are missing",
    )
    a = ap.parse_args(argv)

    justfile = find_justfile(a.justfile)
    text = justfile.read_text()
    recipes = parse_justfile(text)
    if not recipes:
        # An empty parse of a non-empty justfile is a broken parser, not a
        # justfile with no recipes. Raising is the difference between the two.
        raise SystemExit(
            f"just-recipe-help: parsed 0 recipes from "
            f"{len(text.splitlines())} lines of {justfile}. The parser is "
            f"broken, not the justfile."
        )

    if a.audit:
        return audit(recipes, justfile)

    if not a.target:
        print(DOC.strip())
        print(f"\n{justfile}\n{len(recipes)} recipes. List them with: just --list")
        return 0

    prefix = a.module
    if a.target in recipes:
        return show(recipes[a.target], justfile, just_variables(justfile), prefix)

    if a.target.endswith((".py", ".sh")):
        return show_script(a.target, justfile)

    print(f"no recipe or script {a.target!r} in {justfile}. Recipes:", file=sys.stderr)
    for n, r in sorted(recipes.items()):
        if not r.private:
            print(f"  {n}", file=sys.stderr)
    print("\nA script name also works, e.g. `just help build.py`.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())

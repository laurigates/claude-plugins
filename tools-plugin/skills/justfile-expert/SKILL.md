---
created: 2025-12-16
modified: 2026-09-06
reviewed: 2026-02-06
name: justfile-expert
description: Just command runner expertise — Justfile syntax, recipes, parameters, modules, shebang recipes. Use when authoring justfiles, project commands, or task automation.
user-invocable: false
allowed-tools: Bash, Grep, Glob, Read, Write, Edit, TodoWrite
model: sonnet
---

# Justfile Expert

Expert knowledge for Just command runner, recipe development, and task automation with focus on cross-platform compatibility and project standardization.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| Creating/editing justfiles for task automation | Need build system with incremental compilation → Make |
| Writing cross-platform project commands | Need tool version management bundled → mise tasks |
| Adding shebang recipes (Python, Node, Ruby, etc.) | Already using mise for all project tooling |
| Configuring dotenv loading and settings | Authoring the shell itself (pipes, traps, arg parsing) → `shell-expert` |
| Setting up CI/CD with just recipes | Project already has extensive Makefile |
| Standardizing recipes across projects | Exposing a module for bulk smoke-testing → `cli-smoke-recipes` |

## Core Expertise

**Command Runner Mastery**
- Justfile syntax and recipe structure
- Cross-platform task automation (Linux, macOS, Windows)
- Parameter handling and argument forwarding
- Module organization for large projects

**Recipe Development Excellence**
- Recipe patterns for common operations
- Dependency management between recipes
- Shebang recipes for complex logic
- Environment variable integration

**Project Standardization**
- Golden template with standard naming and section structure
- Self-documenting project operations
- Portable patterns across projects
- Integration with CI/CD pipelines

## Recipe Naming Conventions

| Rule | Pattern | Examples |
|------|---------|---------|
| Hyphen-separated | `word-word` | `test-unit`, `format-check` |
| Verb-first (actions) | `verb-object` | `lint`, `build`, `clean` |
| Noun-first (categories) | `noun-verb` | `db-migrate`, `docs-serve` |
| Private prefix | `_name` | `_generate-secrets`, `_setup` |
| `-check` suffix | Read-only verification | `format-check` |
| `-fix` suffix | Auto-correction | `lint-fix`, `check-fix` |
| `-watch` suffix | Watch mode | `test-watch`, `docs-watch` |
| Modifiers after base | `base-modifier` | `build-release` (not `release-build`) |

## Standard and Workflow Recipes

When creating or standardizing a project justfile, open [references/standard-recipes.md](references/standard-recipes.md) for the semantic composites (`check`, `pre-commit`, `ci`, `clean`, `clean-all`), the standard recipe set, and the section structure.

## Key Capabilities

Parameter forms, settings, recipe attributes (`[doc]`, `[private]`, `[group]`, `[confirm]`, platform), and the module system, including that `set fallback` is not inherited by a module: [references/key-capabilities.md](references/key-capabilities.md).

## Essential Syntax

**Basic Recipe Structure**
```just
# Comment describes the recipe
recipe-name:
    command1
    command2
```

**Recipe with Parameters**
```just
build target:
    @echo "Building {{target}}..."
    cd {{quote(target)}} && make

test *args:
    uv run pytest {{args}}
```

**Interpolation is UNQUOTED — quote anything that can contain spaces**

`{{...}}` splices raw text into the recipe body *before* the shell parses it,
so a value carrying spaces or quotes word-splits. This bites hardest on the
`*args` passthrough above, because the error is reported by the *called
program* rather than by just, which makes it read like a bug in the tool:

```just
# Trap — one argument with spaces arrives as several
caption *ARGS:
    ./tool.py {{ARGS}}
```

```
$ just caption ./data "the subject's face"
tool.py: error: unrecognized arguments: subjects face
```

The outer shell consumed the quotes (taking the apostrophe with them) and
`the` / `subject's` / `face` arrived as three separate argv entries. Name the
parameters that can contain spaces and run them through `quote()`, which emits
a properly shell-escaped literal:

```just
# Correct — named params are quoted; trailing flags still pass through
caption DIR SUBJECT="" *ARGS:
    ./tool.py {{quote(DIR)}} {{quote(SUBJECT)}} {{ARGS}}
```

`quote()` covers embedded spaces, `'`, `"`, and `$`. Keep `{{ARGS}}` bare —
that is what lets several trailing flags expand as separate words — and accept
its corollary: an individual passthrough flag's value must not contain spaces.
When one might, promote it to a named parameter too.

**What `--list` Shows Is ONE Line, and It Is Not Your Comment Block**

`just --list` renders a single description per recipe. With no `[doc]`
attribute it takes the **last line** of the comment block immediately above the
recipe — not the first line, and not the block:

| Above the recipe | `--list` shows |
|---|---|
| `[doc("Build the release bundle.")]` | that text |
| a comment block, no attribute | **only its last line** |
| bare `[doc]` | nothing |
| nothing | nothing |

So "add a comment before each recipe" is **not** the same as documenting it. A
block that ends in an example or a caveat — the normal way to write one — lists
as that fragment:

```just
# Pitch-correct the singing in an MP4. Video is stream-copied.
#   just autotune take.mp4 out.mp4 --key C:minor
autotune IN OUT *FLAGS:
```
```
$ just --list
    autotune IN OUT *FLAGS   # just autotune take.mp4 out.mp4 --key C:minor
```

**Add `[doc("one line")]` as soon as a recipe's comment block exceeds one
line.** The block stays where it is and keeps carrying the detail; the
attribute is the only thing `--list` reads.

**The block binds by ADJACENCY, and reassignment is silent.** A blank line ends
a block, so inserting a recipe between a block and the recipe it describes
hands the block to the newcomer — the original then lists blank, and nothing
warns. Re-read `just --list` after inserting a recipe into an existing file.

**A recipe with a required positional has no `--help` form.** `recipe *ARGS:`
forwards `--help` to the underlying tool, but just refuses the call before the
tool runs once a positional is required:

```
$ just autotune --help
error: recipe `autotune` got 1 positional argument but takes at least 2
```

There is no bare-help spelling for such a recipe. Put the flags in its `[doc]`
or comment block, or add a `help` recipe that prints them.

**Recipe Dependencies**
```just
default: build test

build: _setup
    cargo build --release

_setup:
    @echo "Setting up..."
```

**Variables and Interpolation**
```just
version := "1.0.0"
project := env('PROJECT_NAME', 'default')

info:
    @echo "Project: {{project}} v{{version}}"
```

**Conditional Recipes**
```just
[unix]
open:
    xdg-open http://localhost:8080

[windows]
open:
    start http://localhost:8080
```

## Common Patterns

Setup, Docker, database, and CI/release recipes, plus how to pass per-project values into shared imports across modules (parameters, not shared variables): [references/common-patterns.md](references/common-patterns.md).

## MCP Integration (just-mcp)

To let an AI client list and run recipes over MCP instead of reading the justfile, see [references/mcp-integration.md](references/mcp-integration.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List all recipes | `just --list` or `just -l` |
| Dry run (preview) | `just --dry-run recipe` |
| Show variables | `just --evaluate` |
| Whole parsed justfile as JSON (recipes, params, deps, settings) | `just --dump --dump-format json` |
| Recipe names only | `just --summary` |
| Verbose execution | `just --verbose recipe` |
| Specific justfile | `just --justfile path recipe` |
| Working directory | `just --working-directory path recipe` |
| Choose interactively | `just --choose` |

## Best Practices

**Recipe Development Workflow**
1. **Name clearly**: Use descriptive, verb-based names (`build`, `test`, `deploy`)
2. **Document what `--list` reads**: a one-line comment is enough; anything
   longer needs `[doc("...")]`, or the listing shows only the block's last line
3. **Use defaults**: Provide sensible default parameter values
4. **Group logically**: section comments for the file, `[group("name")]` for the
   listing — a flat `--list` stops being scannable somewhere around 20 recipes
5. **Hide internals**: Mark helper recipes as `[private]`
6. **Test portability**: Verify on all target platforms

**Critical Guidelines**
- Always provide `default` recipe pointing to help
- Use `@` prefix to suppress command echo when appropriate
- Use shebang recipes for multi-line logic
- Prefer `set dotenv-load` for configuration
- Use modules for large projects (>20 recipes)
- Give a recipe a `[doc("...")]` when its comment block's last line would not
  read as a description on its own — `--list` shows only that line (see "What
  `--list` Shows" above). To find them:
  `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/just-recipe-help.py" --audit`
- Include variadic `*args` for passthrough flexibility
- Quote all variables in shell commands — `{{...}}` interpolates **unquoted**,
  so wrap any parameter that can contain spaces in `quote()` (see
  "Interpolation is UNQUOTED" above); bare `{{args}}` is correct only for
  space-free passthrough flags

## Comparison with Alternatives

Feature table and when to pick Just, Make, or mise tasks: [references/comparison.md](references/comparison.md).

For the golden justfile template, detailed syntax reference, advanced patterns, and troubleshooting, see [REFERENCE.md](REFERENCE.md).

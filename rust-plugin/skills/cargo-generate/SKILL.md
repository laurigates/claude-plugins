---
created: 2026-07-29
modified: 2026-07-29
reviewed: 2026-07-29
name: cargo-generate
description: "cargo-generate: scaffold a project from a git template repo. Use when bootstrapping a Rust or Bevy project from a template, or authoring one."
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
---

# cargo-generate — Project Scaffolding from Git Templates

cargo-generate expands a **git repository of real files** into a new project,
substituting [Liquid](https://shopify.github.io/liquid/) expressions in file
contents *and* in path names. It is the Rust ecosystem's standard scaffolding
tool — Bevy, wasm-pack, and most framework starters ship templates for it.

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Starting from a published template (`bevy_new_2d`, `wasm-pack-template`) | Starting a plain binary or library — `cargo new` is enough (see `rust-development`) |
| Authoring a template so a project shape can be reproduced | Applying standards to an **existing** repo — cargo-generate only generates once (see `configure-plugin`) |
| A scaffold needs prompts, variants, or derived values | The scaffold is a fixed file set with no substitution — copy it |

## Installation

```bash
cargo install cargo-generate --locked
cargo generate --version
```

It is a cargo subcommand (`cargo generate`) and also a standalone binary
(`cargo-generate`), which is what a test harness should invoke.

## Generating a project

```bash
# From a GitHub template (gh:/gl:/bb:/sr: prefixes also work)
cargo generate --git https://github.com/TheBevyFlock/bevy_new_2d --name my_game

# From a local directory — the form to use while authoring a template
cargo generate --path ./templates/my-template --name my-project

# Pin to a branch, tag, or revision
cargo generate --git <url> --branch main --name my-project

# Expand into the current directory instead of creating a new one
cargo generate --git <url> --init
```

Nothing about the tool is Rust-specific: a template needs **no `Cargo.toml`**,
and generating a TypeScript, Python, or config-only project works the same way.

## Non-interactive use

This is what makes cargo-generate usable from a skill or CI job — prompts would
otherwise block:

```bash
cargo generate --path ./templates/my-template \
  --name my-project \
  --define 'display_name=My Project' \
  --define variant=app \
  --vcs none \
  --silent
```

| Flag | Effect |
|---|---|
| `--define KEY=VALUE` | Supply one placeholder; repeatable |
| `--template-values-file <toml>` | Supply them all from a file |
| `--silent` | Never prompt; fail if a value is missing and has no default |
| `--vcs none` | Skip the automatic `git init` in the output |
| `--destination <dir>` | Where the project directory is created |

## Authoring a template

A template is a directory (usually a git repo) with a `cargo-generate.toml` at
its root:

```toml
[template]
cargo_generate_version = ">=0.23.0"
ignore = ["hooks"]                    # dropped from the output entirely
exclude = ["ci.yml"]                  # copied verbatim, never rendered

[hooks]
pre = ["hooks/derive.rhai"]           # runs after placeholders resolve

[placeholders]
display_name = { type = "string", prompt = "Human-readable title" }
variant = { type = "string", prompt = "Shape", choices = ["basic", "app"], default = "basic" }
enable_ci = { type = "bool", prompt = "Add CI?", default = true }

# `ignore` drops files when the expression is TRUE, so name the cases that
# should NOT get the file.
[conditional.'variant != "app"']
ignore = ["src/app.ts", "templates"]
```

| Key | Meaning |
|---|---|
| `[template] ignore` | Files removed from the output |
| `[template] include` / `exclude` | Which files are *rendered*; mutually exclusive. Excluded files are still copied |
| `[placeholders]` | Prompted values — types `string`, `text`, `editor`, `bool`, `array`; supports `default`, `choices`, `regex` |
| `[conditional.'<expr>']` | Applies `ignore` (and nested `.placeholders`) when the expression holds |
| `[hooks] init` / `pre` / `post` | Rhai scripts, before placeholders / after them / after rendering |

### Built-in variables and filters

`project-name` (as given, kebab-cased), `crate_name`, `crate_type`, `authors`,
`username`, `os-arch`, `is_init`, `within_cargo_project`.

Case filters: `kebab_case`, `snake_case`, `pascal_case`, `lower_camel_case`,
`upper_camel_case`, `title_case`, `shouty_snake_case`, `shouty_kebab_case`.

Path names are rendered too, so `styles/{{ module_id }}.css` works.

### Rhai hooks

Use a hook for values that should be **derived, not asked for** — anything a
prompt could get inconsistent with something else:

```rhai
let name = variable::get("project-name");
if !name.starts_with("prefix-") {
    abort("name must start with 'prefix-'");
}
variable::set("short_name", name.sub_string(7));

let now = system::date();
variable::set("year", "" + now.year);   // strings only — see gotchas
```

Available: `variable::get/set/is_set/prompt`, `file::exists/rename/delete/write/listdir`,
`system::date`, `system::command` (needs `--allow-commands`), `abort`, and the
`to_kebab_case()`-style converters.

## Gotchas

**Liquid eats other `{{ }}` languages.** GitHub Actions `${{ … }}`, Handlebars,
Jinja, and Vue interpolations all render to the empty string if the file is
templated. Two fixes:

| Situation | Fix |
|---|---|
| The file needs no substitution | `[template] exclude` it — copied verbatim, never rendered |
| The file needs both | Wrap the foreign expressions in `{% raw %}…{% endraw %}`, or assign the literal brace once: `{%- assign hb = "{{" -%}` then `{{ hb }}localize "…"}}` |

Only an opening `{{` needs escaping; a bare `}}` means nothing to Liquid.

**`variable::set` takes strings only.** Passing an integer — including
`system::date().year` — fails with
`Function not found: variable::set (…, i64)`. Concatenate with `""` first.

**The project name is kebab-cased before hooks run.** `--name My_Project`
becomes `my-project` silently. A hook cannot reject a malformed name because it
never sees one; if the exact spelling matters, validate before invoking.

**`.liquid` is a magic suffix.** A file named `x.rs.liquid` is rendered and
emitted as `x.rs`. To ship a literal `.liquid` file, double the extension.

## Agentic Optimizations

| Context | Command |
|---|---|
| Fully non-interactive | `cargo generate --path <dir> --name <n> --define k=v --silent --vcs none` |
| Many values | `cargo generate --git <url> --template-values-file values.toml --silent` |
| Template dev loop | `cargo generate --path ./templates/<t> --name probe --vcs none --silent -d …` |
| Diff a template change | Generate before and after into temp dirs, then `diff -ru` |
| Keep generating past a failure | `--continue-on-error` (template debugging only) |

## Quick Reference

| Flag | Purpose |
|---|---|
| `--git <url>` / `--path <dir>` | Template source (remote / local) |
| `--branch` / `--tag` / `--revision` | Pin the template version |
| `--name <n>` | Project name (populates `project-name`) |
| `--destination <dir>` | Parent directory for the new project |
| `--init` | Expand into the current directory |
| `--define k=v` | Set a placeholder |
| `--template-values-file <toml>` | Set placeholders from a file |
| `--silent` | Never prompt |
| `--vcs none\|git` | Control the automatic `git init` |
| `--force` / `--overwrite` | Skip name-case correction / overwrite existing files |
| `--allow-commands` | Permit `system::command` in hooks |

## Templates in this marketplace

`foundryvtt-plugin/templates/foundryvtt-module/` is a worked example — three
variants via `[conditional]`, a derived id via a Rhai pre-hook, both brace
collisions above, and a parity test against the generator it ports. See
[`foundryvtt-plugin/templates/README.md`](../../../foundryvtt-plugin/templates/README.md).

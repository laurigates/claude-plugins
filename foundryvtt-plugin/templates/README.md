# foundryvtt-plugin templates

## `foundryvtt-module/` — cargo-generate pilot

A [cargo-generate](https://cargo-generate.github.io/cargo-generate/) port of
`skills/foundryvtt-module-scaffold/scaffold.py`, evaluating whether a template
of **real files** beats a generator of **Python strings** for this repo's
scaffolding skills.

`scaffold.py` remains the default. The template is the candidate replacement,
and it does not become the default until it has generated at least one real
module repo end to end.

### Why a template repo instead of a generator script

The emitted TypeScript, JSON, and YAML live in the template as the files they
will become — so `tsc`, `biome`, `actionlint`, and Renovate can all see them.
Inside `scaffold.py` the same content is Python string literals: nothing can
typecheck it, and the only proof it is valid is running the generator.

### Running it

```bash
cargo install cargo-generate --locked

cargo generate --path foundryvtt-plugin/templates/foundryvtt-module \
  --name foundryvtt-initiative-tweaks --vcs none \
  --define 'display_name=Initiative Tweaks' \
  --define 'description=Tweaks initiative rolls.' \
  --define variant=app
```

`--define` supplies values non-interactively; omit any of them to be prompted.
`--vcs none` matches `scaffold.py`, which leaves the tree un-initialised.

### Parity

`skills/foundryvtt-module-scaffold/scripts/tests/test-template-parity.sh` runs
both generators over the same inputs and requires byte-identical output across
all three variants, with defaults and with every value non-default. It SKIPs
when `cargo-generate` is absent.

The non-default half of that matrix is load-bearing: the first parity run used
defaults throughout and passed while two fields were still hardcoded in the
template.

### Known divergence from `scaffold.py`

| Input | `scaffold.py` | cargo-generate |
|---|---|---|
| A name that is not kebab-case (`foundryvtt-Bad_Id`) | exits 2 and tells the author to fix it | kebab-cases it to `foundryvtt-bad-id` before any hook runs, and proceeds |

Both end at a valid Foundry id, but cargo-generate renames the author's repo
rather than making them choose again. The parity test asserts this so it cannot
change silently.

### Template structure

| Path | Role |
|---|---|
| `cargo-generate.toml` | Placeholders, per-variant `[conditional]` blocks, `exclude`d files, the pre-hook |
| `hooks/derive-module-id.rhai` | Derives `module_id` from the repo name; sets the copyright year and ADR date |
| everything else | The module tree, with Liquid expressions where values vary |

`module_id` is derived rather than prompted because it must byte-match across
`module.json` `id`, the Foundry install folder, and the release zip name.

### Two brace collisions worth knowing

Liquid owns `{{ }}`, and two of the emitted file formats want the same
delimiters. Both are solved in-template, and both are the first thing to check
when a generated file comes out with something missing:

**GitHub Actions `${{ }}`** renders to the empty string if Liquid sees it.

- `ci.yml` and `renovate.yml` carry no template value, so `cargo-generate.toml`
  `exclude`s them — they are copied verbatim and never meet Liquid. This is the
  preferred fix when a file needs no substitution at all.
- `release-please.yml` does carry the module id (the zip name), so it is
  rendered, and each `${{ … }}` is wrapped in `{% raw %}…{% endraw %}`.

**Handlebars `{{ }}`** in `templates/app.hbs`, which needs Liquid interpolation
*and* Handlebars expressions in the same lines. Wrapping the whole file in
`{% raw %}` would block the interpolation, so the file assigns the literal open
brace once and reuses it:

```liquid
{%- assign hb = "{{" -%}
<p>{{ hb }}localize "{{ module_id }}.App.Body"}}</p>
```

Only the opening `{{` needs escaping — a bare `}}` means nothing to Liquid.

### Rhai gotcha

`variable::set` accepts strings only. Passing the `i64` from `system::date()`
straight through fails with `Function not found: variable::set (…, i64)`;
concatenate with `""` first.

### Follow-ups if the pilot is adopted

- **Renovate coverage.** The template's `uses:` / `FROM` pins sit at
  `foundryvtt-plugin/templates/…/.github/workflows/`, which neither this repo's
  skill-markdown `customManagers` nor Renovate's built-in github-actions
  `fileMatch` (anchored at the repo root) picks up. They were equally unmanaged
  as `scaffold.py` string literals, so this is not a regression — but real files
  at a real path are newly *able* to be managed, which the strings never were.
  Adding a `customManagers` entry for `templates/**/.github/workflows/*.yml`
  closes it.
- **Retiring `scaffold.py`** once a real module repo has shipped from the
  template, at which point the parity test becomes a template-only smoke test.

# `uv.lock` Beside a `pyproject.toml` Version

Read when a release bumps `pyproject.toml` and the repo also commits a `uv.lock`.

## The failure

`uv.lock` records the project's own version in its `[[package]]` entry:

```toml
[[package]]
name = "<project>"
version = "1.2.3"
source = { editable = "." }
```

release-please bumps `pyproject.toml` but leaves this entry at the old version.
After every release, `uv sync --locked` (or `uv lock --check`) fails in CI because
the lock no longer matches `pyproject.toml`.

## The extra-file

Add a `toml` extra-file that selects the project's own `[[package]]` entry by name:

```json
{
  "packages": {
    ".": {
      "release-type": "python",
      "extra-files": [
        {
          "type": "toml",
          "path": "uv.lock",
          "jsonpath": "$.package[?(@.name.value==='<project>')].version"
        }
      ]
    }
  }
}
```

Replace `<project>` with the `name` from `pyproject.toml`'s `[project]` table, as
uv writes it in the lock. As with any extra-file in a monorepo package, `path` is
relative to the package directory.

### The filter compares `@.name.value`, not `@.name`

release-please's TOML updater (`GenericToml`, built on a toml-edit parser) wraps
every parsed value as `{start, end, value}` so it can rewrite the value in place
and keep the file's formatting. A filter on `@.name` compares that wrapper object
against the string and never matches; the updater logs `No entries modified` and
the lock stays behind. Compare `@.name.value`.

The updater rewrites only the matched `version` line. On a real ~3,700-line
`uv.lock`, `GenericToml` changed exactly one line and kept the file's formatting
under release-please 17.3.0 (the floor that release-please-action
v4.4.1 declares) and 17.11.2.

## Check the release PR

On the next release PR, confirm the lock's project entry moved with
`pyproject.toml`:

```bash
gh pr checkout <release-pr-number>
grep -A1 'name = "<project>"' uv.lock
```

The line after `name` must carry the new version. Without a checkout,
`gh pr diff <release-pr-number> | grep -A2 'name = "<project>"'` shows the
`-version`/`+version` pair. If `uv.lock` is absent from the PR's diff, see
[An open release PR keeps its old files](#an-open-release-pr-keeps-its-old-files)
before suspecting the jsonpath.

## An open release PR keeps its old files

release-please rewrites an existing release PR only when that PR's release notes
change. A change to `extra-files` (or any other config) alone does not alter the
notes, so the already-open release PR keeps its old file set and does not gain
the `uv.lock` bump. The workflow log reports the PR as unchanged (`PR ... remained
the same`).

After changing `extra-files`:

1. Close the open release PR (its branch is regenerated, nothing is lost).
2. Run the release workflow by hand:

```bash
gh pr close <release-pr-number>
gh workflow run release-please.yml
```

The new run opens a fresh release PR built from the current config, including
the `uv.lock` change. This applies to every extra-file added or corrected while
a release PR is open, not only `uv.lock`.

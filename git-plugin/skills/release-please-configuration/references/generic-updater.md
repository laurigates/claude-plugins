# Generic Updater and Non-JS Repos

Read when a package uses `release-type: simple`, or an `extra-files` entry is a
plain path (the generic updater, which rewrites lines carrying an
`x-release-please-*` marker), or a build must run after a release is cut.
Each behaviour in this file fails without an error message.

The generic updater fails silently in two ways: it skips a version that is not
`major.minor.patch`, and it rewrites a CRLF file as LF. The third section, a tag
that a `GITHUB_TOKEN` run creates starting no `on: push: tags` workflow, is
GitHub Actions behaviour, not the updater's.

## The generic updater skips a two-part version

The updater's version pattern requires `major.minor.patch` (with an optional
pre-release and build suffix). A line holding `1.29` does not match, so the
file is left unchanged and the run logs no warning; the release PR simply lacks
the bump.

Store a three-part version (`1.29.0`) in any file the generic updater owns. If
a consumer needs the two-part form, derive it at build time from the
three-part value.

Source: `googleapis/release-please` `src/updaters/generic.ts`, `VERSION_REGEX`
(read at `main`, 2026-11-12).

## The generic updater rewrites CRLF files as LF

The updater splits the file on `/\r?\n/` and joins the lines with `\n`. A file
with CRLF line endings comes back with LF endings, so the first release PR
touches every line: a 226-line CRLF file showed `226+ 226-` for a one-line
version bump, and `1+ 1-` once the file was converted to LF.

Convert the file to LF before release-please first touches it, and pin the
ending in `.gitattributes` (`path/to/file text eol=lf`) so an editor cannot
reintroduce CRLF. If the file must stay CRLF for its consumer, convert it at
build or package time instead of in the repository.

## A tag created with `GITHUB_TOKEN` starts no workflow

GitHub does not start new workflow runs for events caused by `GITHUB_TOKEN`
(other than `workflow_dispatch` and `repository_dispatch`). When
release-please-action runs with the default token, the tag it creates does not
fire an `on: push: tags` workflow, and the build never runs.

Put the build in the release-please workflow, gated on the action's
`release_created` output:

```yaml
jobs:
  release-please:
    runs-on: ubuntu-latest
    outputs:
      release_created: ${{ steps.release.outputs.release_created }}
      tag_name: ${{ steps.release.outputs.tag_name }}
    steps:
      - id: release
        uses: googleapis/release-please-action@v5

  build:
    needs: release-please
    if: needs.release-please.outputs.release_created == 'true'
    runs-on: ubuntu-latest
    steps:
      - run: echo "build and upload assets for ${{ needs.release-please.outputs.tag_name }}"
```

In a monorepo the outputs are per package path: `<path>--release_created` and
`<path>--tag_name`, read as `steps.release.outputs['<path>--release_created']`.
The other route is a token that does start workflows (a GitHub App token or a
PAT) passed to the action as `token:`.

## Related

- A release PR that stays `CONFLICTING` after a non-releasable commit lands:
  `git-plugin:release-please-pr-workflow` § Conflict Resolution Strategy

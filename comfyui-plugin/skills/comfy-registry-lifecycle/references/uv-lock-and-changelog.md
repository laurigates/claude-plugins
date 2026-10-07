# comfy-registry-lifecycle — `uv.lock` Drift and the Registry Changelog

Two release-please / `publish.yml` configuration traps: the lockfile self-version release-please does not bump, and setting the registry "Updates" changelog natively at publish time. Entry point: [`../SKILL.md`](../SKILL.md).

## 1. `uv.lock` self-version drifts — release-please has no native uv.lock support

The lockfile records the **workspace package's own version** in its
`[[package]]` entry. release-please's `python` release-type bumps
`pyproject.toml` but **not** `uv.lock`
([googleapis/release-please#2561](https://github.com/googleapis/release-please/issues/2561)),
so the lock's self-version silently trails `pyproject.toml` across releases.
There is **no uv/`pyproject.toml` setting** to omit the project's own
version from the lock, so the lock must be kept in sync explicitly.

**Fix — a structured `toml` `extra-files` updater** in
`release-please-config.json` (the declarative equivalent of
`uv lock --upgrade-package`, not a hand-edit):

```json
"extra-files": [
  {
    "type": "toml",
    "path": "uv.lock",
    "jsonpath": "$.package[?(@.name.value=='<pack-name>')].version"
  }
]
```

`<pack-name>` is the directory/package name. The `toml` updater parses the
lock and sets only the matched `version` value at the JSONPath — everything
else stays byte-stable. Note `.name.value` (release-please's TOML AST wraps
scalar values).

To repair an already-drifted lock once: `uv lock` regenerates it to match
`pyproject.toml` (the only diff is the self-version line, plus occasional uv
specifier normalization like `>=1.40` → `>=1.40.0`).

**New packs are born with it.** `comfyui-node-scaffold` emits this updater in
the pack's `release-please-config.json`, and `scaffold.py --verify <pack>`
grades an existing pack's wiring as `RELEASE_PLEASE_UVLOCK=wired|unwired|
mistargeted` (issue #2187). Packs scaffolded before that still need the `extra-files`
updater added by hand.

**Sweeps miss packs — check before the first release, not after.** A pack
created after a fix sweep can silently lack the updater. Before merging any
pack's release PR — and when scaffolding or auditing a pack — confirm
`grep -c extra-files release-please-config.json` ≥ 1 and that the release
PR's changed files include `uv.lock`. Adding the updater to `main` while a
release PR is open regenerates that PR to include the lock bump.

## 2. The registry "Updates" changelog — use native `COMFY_NODE_CHANGELOG`, not a post-publish PUT

`comfy node publish` sets the per-version changelog **natively** via the
`COMFY_NODE_CHANGELOG` env var
([Comfy-Org/comfy-cli#467](https://github.com/Comfy-Org/comfy-cli/issues/467),
released in comfy-cli 1.11+), populating the registry's "Updates" section
atomically at publish time.

**Do not** hand-roll a post-publish step that resolves the version UUID and
`PUT`s to `https://api.comfy.org/publishers/.../versions/{id}`. A
hand-rolled step that extracts `node_id`/`version` via `python3 -c 'import
tomllib'` fails on every release with `ModuleNotFoundError: No module named
'tomllib'`, because `Comfy-Org/publish-node-action` pins **Python 3.10**
and `tomllib` is 3.11+ stdlib. Under `bash -e` it dies before any `|| exit
0` guard — the node still publishes, but the Updates section is empty and
the job shows red, which is easy to miss.

**Correct shape**: a step *before* the publish-node-action step that
flattens the release notes to plain text (the registry renders Updates as
plain text) and exports it, so the action's `comfy node publish` reads it
from the job environment:

```yaml
- name: Compute registry changelog from release notes
  if: github.event_name == 'release' && github.event.release.body != ''
  env:
    RELEASE_BODY: ${{ github.event.release.body }}   # via env, not inline interpolation
  run: |
    changelog=$(python3 <<'PY'
    # pure-`re` markdown→plaintext flatten (no tomllib); prints the changelog
    PY
    )
    {
      echo "COMFY_NODE_CHANGELOG<<__CHANGELOG_EOF__"
      echo "$changelog"
      echo "__CHANGELOG_EOF__"
    } >> "$GITHUB_ENV"
```

`$GITHUB_ENV` exports the var to all later steps in the job, including the
composite `publish-node-action` run. No PUT, no UUID lookup, no `tomllib`.

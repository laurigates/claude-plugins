# comfyui-node-scaffold — Template Upkeep

Maintaining the generator itself: the two pins it owns that rot silently, and
the fleet sweep that answers whether the 13 generated packs have drifted from
this template and from each other. Entry point: [`../SKILL.md`](../SKILL.md) §
"Agentic Optimizations".

## Two pins the generator owns

- **`uv.lock`** — release-please bumps `pyproject.toml` but has no native
  `uv.lock` support, so without an explicit updater the lock's self-version
  trails the manifest on **every** release (#2187). The emitted
  `release-please-config.json` carries the `toml` `extra-files` updater, and
  `--verify` grades it as `RELEASE_PLEASE_UVLOCK=`.
  `comfyui-plugin:comfy-registry-lifecycle` §1 owns the detail — including the
  two jsonpath forms that leave the lock stale while *looking* configured.
- **`MODAL_KIT_VERSION`** — not Renovate-managed (this repo's customManagers see
  only skill markdown + `install_pkgs.sh`; a `.py` generator is neither), which
  is how it sat four minors behind the published kit until #2186. #2222 tracks
  extending Renovate here; until then refresh with `npm view
  @laurigates/comfy-modal-kit version`. `test-finishing-pass.sh` prints an
  advisory NOTE when the published latest falls outside the pinned range.

## Fleet drift (the packs vs this template)

`--verify` grades **one** pack's finishing pass. The complementary question —
*have the 13 generated packs drifted apart from this template, and from each
other?* — is answered by:

```sh
python3 ${CLAUDE_SKILL_DIR}/scripts/check-fleet-drift.py
```

It imports this generator, derives the context-invariant templates from
`build_file_map` (never a hand-copied list), and compares them against every
pack under `--fleet-root` (default `~/repos/laurigates/comfyui-nodes`;
`--pack <name>` scopes it). Per-file authority lives in
[`fleet-policy.toml`](../fleet-policy.toml) — `managed` (byte-identity, ERROR),
`seed` (never compared), `shared` (the fleet leads, the template back-ports),
and `block` (a named `##########` section of a placeholder-carrying template —
the justfile's `Assets` recipe, whose stale copy silently distorted banner
artwork in one pack for months).

**It reports; it never writes to a pack.** Drift is *bidirectional*: all 13
packs are ahead of the template on `release-please.yml` (`ubuntu-slim` +
`release-please-action@v5`), the template is ahead on `RELEASE-CHECKLIST.md`,
Renovate independently pushes packs ahead on pinned versions, and
`tests/js/__mocks__/app.js` is pack-owned. A template→pack apply would be a
silent-revert bug across 13 repos, so a human classifies each row's direction.
A new context-invariant template with no `fleet-policy.toml` entry is itself an
ERROR, so the manifest cannot fall behind the scaffold. The weekly
`Plugin: Fleet drift audit` workflow runs the same script and opens one issue
when it finds drift.

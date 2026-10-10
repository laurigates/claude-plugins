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

A `shared` file is grouped by identical body across the swept packs, and the
largest group decides which row it gets:

| Row | When | What it asks of a reader |
|-----|------|--------------------------|
| `BACKPORT=<file>\|fleet_majority=<n>\|of=<m>` | The largest group is a **strict majority** (`n * 2 > m`) and differs from the template | The fleet leads: consider back-porting its body into the template |
| `SHARED_SPLIT=<file>\|largest=<n>\|of=<m>` | The largest group is only a **plurality** (`n * 2 <= m`), whether or not it matches the template | No direction is implied: compare the groups and decide which body is canonical |
| `SHARED_MINORITY=<pack>\|<file>\|majority=<n>\|minority=<k>` | A pack sits outside the largest group (emitted under a split too, where `majority=` is the largest group's size) | That pack differs from its siblings |

`SHARED_SPLIT_COUNT=` sits beside `BACKPORT_SIGNAL_COUNT=` in the summary, and
every row is a WARN. The threshold exists because a plurality is one faction,
not the fleet: on 2026-09-23 a 6-of-13 group carrying a pre-#1528
`package-lock.json` line was reported as the fleet majority, and following that
`BACKPORT` would have regressed the template (#2756).

**It reports; it never writes to a pack.** Drift is *bidirectional*: all 13
packs were ahead of the template on `release-please.yml` (`ubuntu-slim` +
`release-please-action@v5`) until #2494 back-ported it, the template is ahead
on `RELEASE-CHECKLIST.md`, Renovate independently pushes packs ahead on pinned
versions, and `tests/js/__mocks__/app.js` is pack-owned. A template→pack apply
would be a silent-revert bug across 13 repos, so a human classifies each row's
direction.
A new context-invariant template with no `fleet-policy.toml` entry is itself an
ERROR, so the manifest cannot fall behind the scaffold. The weekly
`Plugin: Fleet drift audit` workflow runs the same script and opens one issue
when it finds drift.

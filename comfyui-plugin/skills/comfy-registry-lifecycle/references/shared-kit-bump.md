# comfy-registry-lifecycle — Bumping a Shared Frontend-Kit Dependency

Why a one-line `package.json` range bump in a TS-built pack fails CI twice (stale `bun.lock`, stale `web/dist`), the two-command fix, and a pack-set consistency check. Entry point: [`../SKILL.md`](../SKILL.md).

## 3. Bumping a shared frontend-kit dependency: regenerate the lockfile *and* the built bundle together

For a TS-built pack that consumes a shared TypeScript package inlined at
build time (`bun build` bundles the import into `web/dist`), bumping the
version range in `package.json` looks like a one-line change but silently
desyncs **two** other committed artifacts, and CI catches each with a
different, non-obvious error:

- **`bun.lock` goes stale** — its pinned resolution still satisfies the
  *old* range, so it isn't touched by hand-editing `package.json`. CI runs
  `bun install --frozen-lockfile`, which fails with `error: No version
  matching "^X.Y.0" found for specifier "<pkg>" (but package exists)` — a
  confusing message, since the version genuinely is published; the real
  problem is the *lockfile's stale resolution*.
- **`web/dist` goes stale** — the committed bundle still contains the old
  inlined code. A "verify committed `web/dist` is up to date" CI gate (a
  `git diff --exit-code -- web/dist` after a fresh build) fails.

Both gates are correct — the footgun is that the fix requires **two**
commands, and the second failure only surfaces *after* the first is fixed
(the frozen-lockfile failure blocks the build step that would otherwise
reveal the dist-drift):

```sh
bun install   # regenerates bun.lock to resolve the new range
bun run build # rebuilds web/dist against the new dependency version
git add bun.lock web/dist/index.js
```

Commit both in the same commit as the `package.json` bump — don't split
them, and don't stop after fixing the lockfile install failure without also
rebuilding `web/dist`.

Across a whole pack set, check for consistency (range equals locked version
in every consumer):

```sh
for repo in <pack-glob>; do
  [ -f "$repo/package.json" ] || continue
  range=$(grep -o '"<shared-pkg>": *"[^"]*"' "$repo/package.json" | grep -o '\^[0-9.]*')
  locked=$(grep -o '<shared-pkg>@[0-9.]*' "$repo/bun.lock" 2>/dev/null | head -1)
  echo "$repo | range=$range | $locked"
done
```

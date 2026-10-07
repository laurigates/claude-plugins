# Bulk Sweep — Evidence (issue #2479)

## Step 1: a claim survived an identifier-only sweep

Concrete case (`ForumViriumHelsinki/podio-mcp`, PRs #160 / #163 — issue #2479):
a build-time credential injector was removed. The sweep terms were the
identifiers — `BUILD_DEFAULTS`, `inject-build-defaults`, `postbuild` — which
correctly found the script, the npm hook, the constants module and the workflow
passthrough, and the PR shipped. It missed this, in a file the sweep had already
edited:

```
src/index.ts:134
 * - PODIO_CLIENT_ID: Your Podio app's client ID (baked into published package)
```

The comment asserts exactly what the mechanism was supposed to do and contains
none of the three identifiers. It survived, typedoc renders it into the API
reference, and so the claim outlived the thing that made it true — caught only
incidentally, one PR later.

## Verification trap: an excluded path was the only rendered copy

In the same sweep (#2479)
the final pass excluded `docs/api/` — committed typedoc output — reasoning that
CI regenerates and publishes it. Both halves were false: GitHub Pages was never
enabled on the repo (`/repos/.../pages` → 404) and the deploy workflow had failed
every run for ten days, so the excluded directory was the *only* rendered copy
and still carried the stale claim. The report said "no matches remain," which was
true of what it searched and false of the repo.

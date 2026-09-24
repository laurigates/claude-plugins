---
name: release-artifact-verification
description: Confirm a release shipped by fetching the artifact at its public address — split publish jobs, source-tree shadowing, unsmoked images. Use when announcing a release or wiring a publish job.
allowed-tools: Bash(curl *), Bash(gh api *), Bash(gh run *), Bash(npm view *), Bash(docker *), Bash(jq *), Read, TodoWrite
created: 2026-09-24
modified: 2026-09-24
reviewed: 2026-09-24
---

# A Green Release Pipeline Is Not a Shipped Artifact — Go Look For the Artifact

Promoted from the always-loaded `release-artifact-verification.md` portfolio
rule, whose stub keeps the gate lines.

A release "succeeded" when the thing you released is **downloadable by someone
else**. Every intermediate signal — a green workflow badge, a published GitHub
release, a version tag, a passing check — is a claim about *mechanics*, and
each can be true while nothing shipped. Verify the artifact at its public
address, from outside your own tree, in the same breath you announce the
release.

> Canonical break (2026-08, pal-mcp-server): `publish-pypi` had failed on
> **every** release since it was added — 10.2.2, 10.3.0, 10.4.0, 10.4.1,
> 10.4.2 — and the package had never existed on PyPI. A month of releases, each
> one green where anyone would look.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| About to say "released" or "shipped" | A release-please PR is stuck or conflicting → `git-plugin:release-please-pr-workflow` |
| Wiring or reviewing a publish job | A red check needs its error extracted → `github-actions-inspection` |
| Checking an installed version by hand | Choosing Dockerfile structure → `container-plugin:container-development` |
| Adding a container build that pushes to a registry | |

## 1. A release is not atomic — the failing job is not the one you watch

release-please (and most release pipelines) cuts the tag and the GitHub release
in **one** job and publishes artifacts in **another**. When the publish job
fails, the tag exists, the GitHub release page renders perfectly, the changelog
is updated, and the notification says a release happened. The only red is one
job inside a run nobody opens.

- **Check**, always, per artifact class:
  ```sh
  curl -s -o /dev/null -w '%{http_code}\n' https://pypi.org/pypi/<pkg>/json     # 200
  curl -s https://pypi.org/pypi/<pkg>/json | jq -r .info.version                # the version you cut
  gh api users/<owner>/packages/container/<pkg>/versions --jq '.[0].metadata.container.tags'
  npm view <pkg> version
  ```
- **Look at the run's jobs, not its conclusion**, when a release "succeeds":
  ```sh
  gh api repos/<o>/<r>/actions/runs/<id>/jobs --jq '.jobs[] | {name, conclusion}'
  ```
- **Fix the design, not just the release**: make the publish job's failure
  visible — gate the release on it, or add a post-release check that asserts the
  version resolves publicly. A pipeline that can half-succeed silently will.

## 2. Verify from outside the source tree, or you may be reading the source

An install check run **inside the project directory** can resolve the local
working copy instead of the artifact you just published, and report a
plausible-but-wrong version. `python -c` puts the cwd on `sys.path`, so a stale
`*.egg-info/` or a source package in the repo root shadows the installed
distribution.

```sh
# Wrong — cwd is the repo root; reads the stale local egg-info
$ .venv/bin/python -c "import importlib.metadata as m; print(m.version('pkg'))"
10.4.1                      # ← the version from ./pkg.egg-info/PKG-INFO

# Right — neutral cwd, and confirm the dist-info the venv actually holds
$ cd /tmp && /path/.venv/bin/python -c "import importlib.metadata as m; print(m.version('pkg'))"
10.4.3
$ ls /path/.venv/lib/python*/site-packages | grep 'pkg.*dist-info'
pkg-10.4.3.dist-info
```

Generalises past Python: `node_modules` resolution walks upward, `cargo`
prefers a path override, `go` honours a `replace` directive. **The rule is to
verify in a directory that has no relationship to the source**, and to confirm
against the installed metadata (`dist-info`, `package.json` in `node_modules`)
rather than an import that could have come from anywhere.

The failure is silent and reads as a real result — same family as
`agent-patterns-plugin:probe-input-integrity`: a broken harness and a genuine
finding produce identical-looking output.

## 3. A check that never ran reports `pass`

Path-filtered CI checks (`file-patterns`, `paths:`) complete in **4–6 seconds**
having analysed nothing, and report success. A sibling PR's green tick is not a
control unless it actually executed. Full treatment in
`github-actions-plugin:ai-review-max-turns` § *"a check that never ran looks
exactly like a pass"*; noted here because it is the third way a release looks
verified and isn't.

## 4. A build job that never *runs* the image publishes a broken one, green

A `docker build` that succeeds proves the layers assembled, not that anything
inside can start. A pipeline that builds and pushes without ever executing the
entrypoint will publish an image whose every import fails, report success, and
deploy it.

> Example: a dependency-bot PR moves a multi-stage image's runtime stage to
> `python:3.14-alpine` while the builder stage stays on 3.12. The venv copied
> between stages keeps its packages in `lib/python3.12/`, so the 3.14
> interpreter drops `/app/.venv` from `sys.path` entirely. Every service built
> from it crash-loops for days, hundreds of restarts each, while build, push,
> release, and every CI check stay green — nothing in the pipeline ever ran the
> image.

- **Gate the push on a smoke step, not the other way round.** Build with
  `load: true`, run the entrypoint, *then* push. A broken image never reaches
  the registry, so there is nothing to roll back.
- **Assert the environment, not just an import.** `import <pkg>` alone can pass
  for the wrong reason; assert the venv is actually on the path:
  `assert [p for p in sys.path if "/app/.venv/" in p]`.

**`docker run` needs `-i` or the check is vacuous.** Without it docker does not
forward stdin, so a heredoc-fed `docker run --rm IMG python -` reads an **empty
script** and exits **0 having asserted nothing** — the gate then passes on every
image, including a deliberately broken one:

```
docker run --rm -i "$IMAGE" /app/.venv/bin/python - <<'EOF'
```

This is the same family as §2 and `agent-patterns-plugin:probe-input-integrity`
§ *an inert stub means the real tool ran*: the harness is green while measuring
nothing. It was caught only by **running the finished gate against a known-bad
image** and requiring it to fail — do that before trusting any gate you just
wrote.

## The litmus test

Before saying "released", answer: **"What URL would a stranger fetch to get
this, and have I fetched it?"** If the answer cites a workflow badge, a tag, or
a GitHub release page, you have verified the mechanics and not the outcome.

Portfolio incident evidence is kept privately (repos-claude-config docs/rule-evidence/release-artifact-verification.md).

## Related

- `github-actions-plugin:multirepo-ci-cd` — a re-run replays the *stale* workflow,
  so re-running a failed publish after merging its fix does not test the fix
- `github-actions-plugin:ai-review-max-turns` — the skipped-check-reports-pass
  trap in full
- `migration-patterns-plugin:tool-migration-cutover` — the same law before the
  fact: removal is gated on a positive *operational* signal, not on config being
  present
- `git-plugin:git-merge-hazards` — "exit 0 is a claim about mechanics, not
  content", of which this skill is the release-time instance

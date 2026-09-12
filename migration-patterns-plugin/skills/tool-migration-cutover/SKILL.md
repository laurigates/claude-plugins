---
name: tool-migration-cutover
description: "Migrating between tools (Dependabot to Renovate, PAT to GitHub App, one linter to another). Use when removing the incumbent, to verify the replacement actually runs rather than merely configured."
allowed-tools: Bash, Read, Grep, Glob, Edit, TodoWrite
created: 2026-08-08
modified: 2026-09-12
reviewed: 2026-09-12
---

# Tool-Migration Cutover: Verify the Replacement Is *Operational* Before Deprecating the Incumbent

When migrating from one tool to another (Dependabot → Renovate, a PAT-based
workflow → a GitHub App, one linter/CI/runner → another), **do not remove the
incumbent until the replacement is observed actually doing the job** — not merely
*configured* to. "Config exists" and "config works" are different claims, and the
gap between them is where coverage silently drops to zero.

## The failure mode

The incumbent is removed on the strength of the replacement's *presence*:

1. The replacement's config is committed and looks correct.
2. Someone reasons "Renovate is set up, so Dependabot is redundant — remove it."
3. The replacement was never actually running (broken credentials, missing
   step, unprovisioned secret, quota), so **neither** tool is now doing the work.
4. The gap is invisible: no error fires for "nothing is updating dependencies."

Config presence is not evidence of operation. A scheduled runner can fail every
single run and leave no trace in the place you're looking (the repo's PR list
stays empty, which reads identically to "no updates needed").

## The rule

**Removal of the incumbent is gated on a positive operational signal from the
replacement**, observed on the *actual* target repos:

| Replacement | Positive signal to require before deprecating incumbent |
|---|---|
| Renovate | A successful runner execution **and** a Dependency Dashboard issue / `renovate/*` branch / PR on the target repo |
| A CI/lint tool | A green run of the new check on a real PR, not just the workflow file merged |
| A GitHub App replacing a PAT | A workflow run that successfully mints **and uses** the App token |
| A new deploy path | One real deploy through the new path that reaches the target |

Until that signal exists, **stage the deprecation as a draft** (draft PRs, an
un-merged branch, a feature-flag off) so the work is ready the instant the signal
lands — but cannot be merged prematurely by you or anyone else.

## How to check operation (don't trust config presence)

- **Runner actually ran and succeeded** — `gh run list --workflow=<f> -L 5`
  (all `failure` = it has never worked). Read the failed log; an ~8s failure at
  step 1 is usually a credential/token problem, a ~2s zero-step failure is
  usually quota.
- **Side effects appeared on the target** — the dashboard issue, the branch, the
  PR. `gh issue list --search "Dependency Dashboard in:title"`,
  `gh api repos/<o>/<r>/branches --jq '.[].name|select(startswith("renovate/"))'`.
- **Credentials/secrets are present where consumed** — the secret/variable on the
  consuming repo, not just "set upstream" (in the IaC runner/CI/a vault). The push from
  upstream to the repo is a separate step that can itself be blocked.

## Worked example — Dependabot → Renovate (Bun), 2026-06

The premise "Renovate already manages these repos, overlapping with Dependabot"
was false: the centralized autodiscover runner **failed every run** (unprovisioned
GitHub App → empty `app-id` → token mint failed), so Dependabot was the *only*
working dependency automation. Deprecating it then would have left 9 repos with
no updates. Correct sequence: fix the latent runner bug, **stage the 9
`dependabot.yml` deletions as draft PRs**, hand off the (manual, user-only) App
provisioning, and gate the draft merges on a verified Renovate run.

Two Renovate/Bun facts that fell out of the same investigation, worth not
re-deriving:

- **There is no bun `postUpdateOptions` value** (`bunDedupe` does not exist;
  allowed values are npm/pnpm/yarn/bundler/go/nuget only). An invented value
  fails Renovate's `allowedValues` validation and breaks the **whole config** —
  for the *global* self-hosted config, that breaks every repo. Verify enum values
  against the Renovate docs before adding them.
- Renovate updates and commits `bun.lock` **natively** when it patches
  `package.json` (it runs the package manager and commits both). No option is
  needed for "generate a matching lockfile"; `lockFileMaintenance` is the
  separate periodic full-refresh.

## When it bites

- Dependency-bot swaps (Dependabot ↔ Renovate), where "no PRs" looks the same
  whether the tool is off or just has nothing to do.
- Credential/secret migrations where the value is set in the orchestrator
  (an IaC runner, a vault, org secrets) but the *push to the consuming repo* hasn't run.
- CI tool replacements merged as a workflow file but never exercised on a PR.

## The mirror failure: the incumbent removed too *late*

Everything above guards against cutting over too early. The opposite failure is
just as common and noisier: the migration switches the **canonical** path to the
new tool but never unwires the old one, and the leftover does not sit inert — it
**fights** the replacement on every commit.

The shape (observed 2026-07, Comfy-Org/registry-web #272):

1. A migration commit updates the `fmt`/`fix` scripts and CI to the new tool.
2. `lint-staged` still runs the old formatter on every commit.
3. The old config is the *opposite* style of the new one, so the pre-commit hook
   **reformats correct code to the wrong style** on every commit.

The tell is a 3-line edit that produces a 400-line diff. It reads as "the
formatter ran", not as "two formatters disagree and the loser is mangling my
files" — which is why it survives for months.

### Establish which tool is canonical — mechanically, don't reason about it

When two formatters or linters are both present, the committed code matches
exactly one. Ask them:

```
oxfmt --check <file>      # exit 0  -> the code matches oxfmt
prettier --check <file>   # warns   -> the code does NOT match prettier
```

The one CI runs is canonical; the one whose `--check` **fails on
already-committed code** is the leftover. Run it — do not argue about which
*should* be right.

### Swapping the command is not enough — simulate the real hook

Replacing `prettier --write` with `oxfmt` in `lint-staged` looks done and can be
silently broken: oxfmt is a JS/TS formatter and **errors on a `package.json`
target**, where prettier silently handled json/css/md. Run the actual hook
against staged files before trusting it:

```
git add <a badly-formatted .tsx> && bunx lint-staged
```

It must succeed *and* fix in the canonical style.

### Sweep every wiring, not just the loud one

Grep the whole repo surface for the old tool before calling the migration done.
In the case above the leftovers were `lint-staged`, `.prettierrc`,
`.eslintrc.json`, a dead path-scoped workflow whose target directory no longer
existed, a `_lint` script, and **eight** unused devDependencies. Verify removal
does not break a real consumer — inert `// eslint-disable` comments in generated
code are directives, not imports, and do not require the package.

## Rationale

Removing a working tool is cheap to do and expensive to discover undone — the
loss is a *non-event* (updates that silently stop happening), so nothing alarms.
The mirror is worse in one respect: an incomplete migration advertises the new
tool while the old one quietly corrupts work, and the cost is paid on *every*
commit by whoever touches a file, usually misattributed to "the formatter did
something weird".
Gating on a positive operational signal, and staging the removal as a draft in
the meantime, costs one extra "is it actually running?" check and converts a
silent multi-week coverage gap into a no-op wait. This is the migration-time
sibling of `verify-upstream-before-patching.md` (check reality before acting) and
`ci-cd-multirepo.md` (fetch-first before diagnosing CI).

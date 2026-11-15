# foundryvtt-module-scaffold: auditing the module fleet

`scripts/check-fleet-drift.py` compares the files the scaffold emits against
every module it has generated (#2761). It **reports and never writes**: drift
runs both ways, a module can be ahead of the template (a Renovate bump) or
behind it (a gate it predates), so a human classifies each row's direction and
fixes whichever side is behind.

```sh
python3 scripts/check-fleet-drift.py --fleet-root <dir-of-module-repos>
```

A module is a `foundryvtt-*` directory with a `module.json` directly under the
fleet root (`--fleet-root`, else `$FOUNDRYVTT_FLEET_ROOT`, else the current
directory). `--module <name>`
scopes the run (repeatable). `--issue-body` prints a markdown issue body for a
scheduled sweep, and prints nothing for a clean fleet. Output follows the
`STATUS=OK|WARN|ERROR` / `REASON=` / `ISSUE_COUNT=` / `ISSUES:` contract; exit 1
on ERROR, 2 on an unknown argument.

## Per-file policy

Authority for each path lives in [`fleet-policy.toml`](../fleet-policy.toml),
with a reason per entry:

| Policy | Checked as | Finding |
|--------|-----------|---------|
| `managed` | byte-identical to the template | `MANAGED_DRIFT` (ERROR) |
| `shared` | consistent across modules; the fleet leads | `BACKPORT` when a strict-majority consensus differs from the template, `SHARED_SPLIT` when the largest group is only a plurality (#2756), `SHARED_MINORITY` per diverging module (WARN) |
| `seed` | never compared | — |
| `absent` | exists in no module and is emitted by no variant | `ABSENT_PRESENT` (ERROR); a `POLICY_PROBLEM` if the scaffold emits it |

The `absent` entry for `.github/workflows/renovate.yml` keeps the repo-local
Renovate runner (#2708) from coming back: it duplicated the account-wide
Renovate App under a second bot identity.

## How the compared set is derived

The checker imports `scaffold.py` and renders `build_file_map` for every variant
and two distinct module names. It keeps a path only when the path renders under
**both** names with one identical body, so `styles/<id>.css` (whose path carries
the id) and anything with a substituted placeholder drop out. A kept path with
no policy entry is an `UNCLASSIFIED_TEMPLATE` ERROR, and a policy entry the
scaffold no longer emits is a `STALE_POLICY_ENTRY` WARN, so the manifest cannot
silently fall behind the generator.

## Relationship to the ComfyUI checker

This is a sibling of `comfyui-plugin:comfyui-node-scaffold`'s checker, chosen
over a shared script so each plugin stays independently installable (#2761,
option C). Until a shared core is extracted, a fix to the comparison logic lands
in both. The policy classifications were set without a sweep of the live module
fleet; review them against the first real run before acting on a row
(`.claude/rules/generated-fleet-drift.md` in the claude-plugins repo).

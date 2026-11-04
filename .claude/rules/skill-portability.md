---
created: 2026-11-04
modified: 2026-11-04
reviewed: 2026-11-04
paths:
  - "*-plugin/skills/**"
  - "*-plugin/agents/**"
  - "*-plugin/hooks/**"
---

# Skill Portability — Shipped Content Is Environment-Neutral

The plugins are public. An agent in someone else's session reads a skill,
agent or hook as instructions, so a line naming the maintainer's own
repository, host, checkout path or process sends that agent after something
its user does not have. The other rules govern structure, size, naming and
quality; this one governs whether the content assumes one person's setup.

## The rule

- **Don't name the maintainer's repositories, hosts, checkout paths or
  processes as things to act on.** Provenance and evidence ("found while…")
  can stay where they help a reader, worded so nobody acts on them.
- **Take environment-specific values from context**: the project's files, the
  git remote, environment variables, plugin settings
  (`.claude/<plugin>.local.md`).
- **Ask once for a choice that is the user's and stable across runs**, then
  offer to save the answer as a rule in the user's own config (for example
  `~/.claude/rules/`) so later runs don't ask again. How secrets reach
  repository settings is the typical case: by hand, through organization
  secrets, or with infrastructure as code. Users differ, so a skill does not
  assume one.
- **Name a publicly published dependency** (a reusable workflow meant for
  anyone to call) **as a default the user can override**, not as the only
  option.

## The check

`scripts/check-skill-portability.sh` scans tracked files under the three
`paths:` globs for the identifiers in `scripts/skill-portability.conf`
(`[identifiers]`, one regex per line; a fork sets its own). A line accepted
as written goes in the config's `[allow]` section as
`path<TAB>matched text<TAB>reason`.

| Hit | Result |
|-----|--------|
| Allowlisted | `OK` |
| Held by `scripts/skill-portability-baseline.txt` | `WARN`, exit 0 |
| Not in the baseline, or above its count | `ERROR` (`new_hit`) |
| Baseline entry above the file's current count | `ERROR` (`stale_baseline`); lower it with `--update-baseline` |

The baseline holds the hits that predate this rule (31 files at landing) and
only goes down. The per-plugin sweep under #3308 classifies each one with
`code-quality-plugin:bulk-sweep-classify`, then neutralizes it or allowlists
it with a reason. Do not add new entries to the baseline.

## Related

- `.claude/rules/skill-quality.md` — structure and quality standards
- `.claude/rules/regression-testing.md` — where the check's regression test lives
- `.claude/rules/structured-script-output.md` — the check's output contract

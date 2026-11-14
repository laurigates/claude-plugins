---
name: code-context-leakage
description: "Audit a repo for names and defaults tied to one person's setup — home paths, personal channels, dated tags, OS-only commands, stale repo names. Use when preparing a project for reuse."
args: "[pathspec...] [--name <old-name>]... [--config <file>]"
argument-hint: "[pathspec...] [--name <old-name>] [--config <file>]"
allowed-tools: Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/scan-context-leakage.py *), Bash(find *), Bash(git mv *), Read, Grep, Edit, AskUserQuestion
created: 2026-11-06
modified: 2026-11-14
reviewed: 2026-11-06
---

# /code-quality:code-context-leakage

Projects that start as one person's tool collect names that only make sense in
that person's context: a recipe named for when it ran (`overnight`) rather than
what it does, a notification recipe wired to a personal channel, a dated run
tag left as a default, a hard-coded site list, BSD-only `stat` in a script, a
README that still uses the repository's old name. Each one blocks reuse or
confuses the next reader. This skill finds them, classifies each, and renames
the ones the owner approves, behind a gate that proves the old names are gone.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| A personal or spike project is about to be shared, published or handed over | You already have the rename map and only need to apply it safely → `code-quality-plugin:bulk-sweep-classify` |
| Recipes, scripts or labels name a person, host, site, date or time of day | The concern is secrets or internal identifiers leaving for a public destination → `documentation-plugin:public-export-sanitization` |
| A repository was renamed and old self-references may remain | You want the justfile's standard recipes audited → `configure-plugin:configure-justfile` |

## Context

- Recipe files: !`find . -maxdepth 1 \( -name justfile -o -name Justfile -o -name .justfile -o -name Makefile \) -type f`

## Parameters

Parse `$ARGUMENTS`:

| Argument | Meaning |
|---|---|
| bare words | git pathspecs that narrow the scan (default: every tracked file) |
| `--name <regex>` | an old name to gate on; repeatable |
| `--config <file>` | `[identifiers]` (one regex per line) and `[allow]` (`path<TAB>matched text<TAB>reason`) |

With no arguments, scan the whole repository.

## Execution

Run this audit. Nothing is renamed until the owner approves the table in Step 3.

### Step 1: Scan

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/scan-context-leakage.py" --project-dir . [--include <pathspec>]... [--config <file>]
```

The scanner reads tracked files only, skips changelogs, ADRs and lockfiles
(historical records stay as written), and prints one
`HIT=<category>|<path>:<line>|<match>|<text>` per candidate plus a
`CATEGORY_<NAME>=` count for each category. `REPO_NAME=` is read from the git
remote; with no remote, the stale-name check is skipped.

| Category | What it flags |
|---|---|
| `home-path` | `/Users/<name>`, `/home/<name>` (generic stand-ins such as `/home/user` pass) |
| `checkout-layout` | a personal layout such as `~/src/` or `$HOME/projects/` |
| `personal-channel` | Telegram, Pushover, ntfy, Slack or Discord webhooks |
| `dated-tag` | a name carrying a date, e.g. `manual-2026-10-23` |
| `time-of-day` | justfile/Makefile recipes and file names saying when something ran |
| `os-specific` | BSD-only (`stat -f`, `sed -i ''`, `date -j`), GNU-only (`date -d`, `grep -P`), macOS paths and fonts |
| `stale-repo-name` | an OCI `source` label or `repository`/`homepage` field naming another repository |
| `identifier` | each regex in the config's `[identifiers]` section |

The scanner cannot see everything. Also read, by hand: default values in
config files and CLI flags (a site or dataset list naming one place), comments
that state one person's limits ("Telegram caps messages at 4096"), CI and
container labels, and `package.json` script names.

### Step 2: Classify every hit

Read the surrounding lines and put each hit in one bucket:

| Bucket | Typical hit | Action |
|---|---|---|
| **Rename** | `overnight` recipe, `data-processing` in a README after the repo was renamed | Name what it does, or the current name |
| **Parameterize** | a home path, a personal webhook, a site list as a default | An environment variable, a config value, or a hook the user fills in |
| **Archive** | `gpu-*` recipes and dated tags from a finished spike | Move to the spike's directory or delete |
| **Keep, with a reason** | provenance in an ADR, an OS-specific command that already has a fallback | Add an `[allow]` line with the reason |

An OS-specific command belongs in **Parameterize** only when it has no
fallback; one guarded by an `uname` branch is a **Keep**.

### Step 3: Propose the renames

Present one table and ask the owner to approve it with `AskUserQuestion`
(options: approve all, approve with edits, report only):

| Current | Where | Why it depends on context | Proposed |
|---|---|---|---|
| `overnight` | `justfile:12` | names when it ran, not what it does | `batch-detect` |

If the owner chooses report only, stop here and hand over the table.

### Step 4: Apply, then gate

Apply the approved renames in one change that renames and nothing else: recipe
names, file names (`git mv`), labels and docs, before any code change that
depends on them. Then run the gate with every old name:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/scan-context-leakage.py" --project-dir . --only old-name --name '<old-1>' --name '<old-2>' --strict
```

Exit 0 and `CATEGORY_OLD_NAME=0` mean the old names are gone from file
contents and tracked file paths outside changelogs and ADRs. A file left under
its old name is reported with line `0`. Exit 1 lists each survivor as a `HIT=` line: fix it, or
allowlist it in the config with a reason, and run the gate again. Exit 2 with
no names (`--only old-name` and no non-empty `--name`, as when `--name "$OLD"`
expanded to nothing) is a usage error, never a pass. Finish by
running the project's own tests, since a renamed recipe or file breaks any
caller that used the old name.

## Agentic Optimizations

| Context | Command |
|---|---|
| Counts only | `python3 "${CLAUDE_SKILL_DIR}/scripts/scan-context-leakage.py" --max-hits 0` |
| One category | `… --only os-specific` |
| One subtree | `… --include 'scripts/**'` |
| Rename gate | `… --only old-name --name '<old>' --strict` |
| Include changelogs and ADRs | `… --no-default-excludes` |

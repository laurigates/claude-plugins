---
created: 2026-05-09
modified: 2026-05-09
reviewed: 2026-05-09
allowed-tools: Glob, Read, Edit, Write, Bash(git status *), Bash(git diff *), Bash(git mv *), Bash(diff *), Bash(rm *), AskUserQuestion, TodoWrite
model: opus
description: Evaluate whether rules, skills, commands, or agents at one .claude scope should be promoted to a higher scope (parent or user-global), and execute approved promotions safely. Use when reorganizing nested .claude/ directories, when sibling repos hold near-duplicate rules, or when a portfolio root has overlapping configuration with its children.
args: "[scope-path]"
argument-hint: "[scope-path]"
name: meta-promote
---

# meta-promote

## When to Use This Skill

| Use this skill when... | Use a different skill when... |
|---|---|
| Two or more sibling `.claude/` scopes hold rules/skills/commands with the same name or topic, and you want to decide whether to lift them up to a shared parent | You want to copy a *project's* config into your *user-global* config (use `meta-assimilate`) |
| A portfolio root (e.g. `~/repos/`) has children whose configs overlap and you want to promote the common kernel | You want to review existing agent configs for security and frontmatter completeness without changing scopes (use `meta-audit`) |
| You suspect a rule is duplicated across sibling repos and want a structured promotion / extraction / keep-scoped decision per file | You want to author a brand-new skill from scratch (use `custom-agent-definitions`) |

## Context

- Current directory: !`pwd`
- Local `.claude/` tree: !`find .claude -maxdepth 3 -type f -name '*.md' -not -path '*/node_modules/*'`
- Child `.claude/` trees (one level down): !`find . -mindepth 2 -maxdepth 4 -type d -name '.claude' -not -path '*/node_modules/*'`

## Parameters

Parse `$ARGUMENTS`:

- `scope-path` (optional, default `.`) — the directory whose children's `.claude/` trees should be evaluated for promotion *up to* this directory. The skill always treats `scope-path` as the **target** scope and its immediate `.claude/`-bearing children as the **source** scopes.

## Your task

Execute this evaluation and (with approval) apply it. **Do not promote anything without explicit per-candidate confirmation** — promotion is a write to shared state and easy to get wrong.

### 1. Build the scope inventory

Walk three layers:

| Layer | Path | Role |
|---|---|---|
| Target | `<scope-path>/.claude/{rules,skills,commands,agents}/` | Where promoted files would land |
| Sources | `<scope-path>/*/.claude/{rules,skills,commands,agents}/` | Children whose contents are candidates |
| Upstream | User-global `.claude/rules/` (resolve `$HOME/.claude/rules` during execution, not in the Context block) and any plugin skills already loaded for this session | Already-covered material — promotion to the target would just duplicate this |

For the upstream layer, run `Glob(pattern="$HOME/.claude/rules/**/*.md")` during execution and read filenames + first heading of each match. The plugin-skill list is already in the session prompt — scan it for relevant entries by name.

For each source file, record `(scope, kind, name, path)` where `kind ∈ {rule, skill, command, agent}` and `name` is the filename or skill directory name.

### 2. Find overlap candidates

Group source files by `(kind, name)`. Three kinds of overlap matter:

- **Same-name across sources** — the same filename appears in two or more sibling scopes (e.g. `ci-cd-workflows.md` in both `OrgA/.claude/rules/` and `OrgB/.claude/rules/`)
- **Same-topic across sources** — different filenames, related content (e.g. `commits.md` and `commit-conventions.md`)
- **Source vs target collision** — a file with the same name already exists at the target scope

Files that appear in only one source and have no target-scope sibling are not promotion candidates — they are correctly scoped already.

### 3. Evaluate each candidate

For each candidate group, read every file and apply this checklist. Every "yes" makes promotion *less* appropriate:

| Signal | What to look for |
|---|---|
| Owner-specific identifiers | Org names (`ForumViriumHelsinki`, `laurigates`), GH repo URLs, container registry paths (`ghcr.io/<org>/...`), GitHub App IDs, secret names, named workspaces (Terraform Cloud, Scalr) |
| Owner-specific conventions | Label sets (`docs` vs `documentation`), reviewer usernames (`@user` vs bare `user`), project-routing tables, CI tool choices (Renovate vs Dependabot) |
| Path-scoped frontmatter that differs | A `paths:` glob that genuinely targets a different directory shape per source |
| Tooling assumptions | Helm chart names, image-updater configurations, deploy-values schemas tied to one stack |
| Already covered upstream | A user-global rule, a plugin skill, or a friction-findings note already says the same thing — promoting would duplicate, not consolidate |

Then ask the inverse: what's *generic* about this file? Is there a kernel (a self-review guard, a "use conventional commits" preamble, a generic checklist) that applies regardless of owner?

### 4. Recommend an action per candidate

Pick exactly one of four:

| Action | When | What it does |
|---|---|---|
| **Promote as-is** | All sources have effectively identical content; no owner-specific signals; not already upstream | `git mv` one source copy to the target scope; delete siblings |
| **Extract kernel** | Sources share a generic core but each carries owner-specific deltas | Write the generic content as a new file at the target scope; trim each source down to only the deltas, with a one-line link back to the target file |
| **Keep scoped** | Content genuinely differs per owner; a unified version would force one set of conventions on the others | Leave files where they are; optionally add a one-line frontmatter comment explaining the divergence so future readers don't re-evaluate |
| **No action (already upstream)** | The user-global rule or a plugin skill already covers this | Optionally delete the redundant source copies; do not write to the target |

### 5. Confirm before writing

For each candidate group, present:

1. The grouped files (paths)
2. The diff between sources (`diff <a> <b>` for two-source cases; a 3-way summary for more)
3. The recommended action with a one-sentence justification
4. The four alternatives via `AskUserQuestion`

Only proceed on explicit approval. **Do not bundle multiple candidate decisions into one prompt** — each gets its own approval round-trip so the user can redirect on any single one.

### 6. Execute the approved action

| Action | Mechanics |
|---|---|
| Promote as-is | `git mv <source-1> <target>` to preserve history, then `rm` the other sources. If the source repos are independent (separate `.git` per scope), use `cp` + `rm` instead of `git mv`. |
| Extract kernel | Use `Write` to create the target file with the generic content. Use `Edit` on each source to remove the now-shared content, replacing it with one line of the form `> Generic guidance: see [\`<rel-path-to-target>\`](<rel-path-to-target>).` |
| Keep scoped | Optionally `Edit` each source to add an HTML comment `<!-- intentionally scoped: <reason> -->` near the top so the next pass through this skill skips it quickly. |
| No action | Optionally `rm` the redundant sources; never write to the target. |

After every write, run `git status` against each affected repo so the user sees exactly what changed before any commit happens.

### 7. Report

Emit a final summary table:

| Source files | Action | Target | Notes |
|---|---|---|---|
| `OrgA/.claude/rules/foo.md`, `OrgB/.claude/rules/foo.md` | Keep scoped | — | Org-specific label conventions |
| `OrgA/.claude/rules/bar.md`, `OrgB/.claude/rules/bar.md` | Promote as-is | `./.claude/rules/bar.md` | Identical content, no owner signals |

End with the next step the user should take (typically: review `git status` in each affected repo, then commit per-repo with conventional-commit messages — `meta-promote` itself does **not** commit).

## Demotion (inverse direction)

Occasionally a rule lives at user-global scope but is genuinely owner- or project-specific. The same evaluation applies in reverse: if a `~/.claude/rules/<x>.md` references one org's tooling and would mislead anyone outside that org, propose moving it down to the appropriate `<owner>/.claude/rules/`. Use the same four-action menu — "Promote" becomes "Demote", "Extract kernel" stays the same.

## Anti-patterns to avoid

| Don't | Do |
|---|---|
| Promote two same-named files just because the names match | Diff their contents and apply the checklist — same name often hides genuinely different rules |
| Bundle "promote A and B" into one approval prompt | One candidate, one prompt — the user may agree on A and reject B |
| Use `rm -rf` on a scope's `.claude/` to "clean up" after promotion | Remove only the specific files you're promoting; leave the rest of the scope alone |
| Commit the promotion as part of the skill | Leave commits to the user — the skill produces a clean working tree the user can review and split into per-repo commits |
| Promote when an upstream rule already covers it | Recommend "no action" and (with approval) delete the redundant source(s) |

## Notes

- This skill **reads broadly and writes narrowly**. The discovery phase touches every `.claude/` scope under `scope-path`; the write phase touches only the specific files the user approved.
- When source scopes are in separate git repos, the user must commit in each repo independently. Do not attempt cross-repo atomic operations.
- Pair with `meta-audit` for a follow-up sanity check after promotion: `meta-audit` will catch any frontmatter that broke during the move.

# Repo Maintenance Automation Plan

## Problem Statement

Analysis of 135 commits reveals that **91% of commits are maintenance overhead**, not feature work:
- 69% are release-please chores (41 of 93 are duplicates for the same plugin+version)
- 22% are manual config sync, bulk standardization, README updates, and convention compliance fixes
- Only ~9% are actual feature/bug commits

## Current Automation Inventory

| Automation | Method | Trigger | Status |
|---|---|---|---|
| Version bumps + changelogs | release-please | push to main | Working but creates duplicate PRs |
| Config 3-file sync | `sync-plugin-configs.py` + workflow | PR + push to main | Working |
| Release PR auto-merge | `release-please.yml` | release PR created | Working |
| Marketplace sync on release PRs | `release-please.yml` sync-release-pr job | release PR created | Likely causing duplicate PR loop |
| Plugin compliance review | Claude Code Action | plugin PRs | Working |
| Skill quality review | Claude Code Action | skill file changes | Working |
| Monthly agentic audit | Scheduled workflow | 1st of month | Working |
| Bi-monthly infra dashboard | Scheduled workflow | 1st & 15th | Working |
| Release PR doc audit | Workflow | release-please branches | Working |

## Identified Gaps

| Gap | Impact | Evidence (commits) |
|---|---|---|
| Duplicate release-please PRs | 41 wasted commits, 30% of all history | 3-5 PRs per release for same version |
| README plugin table generation | Manual drift, inaccurate counts (claims 285+, actual 237) | `c03a648` |
| Deterministic frontmatter linting | Bulk fix commits | `5beb75e` (83 errors across 75 files) |
| Context command pattern enforcement | Post-hoc cleanup | `de8ce95`, `d908b24` |
| Required section enforcement | Bulk addition commits | `3a7414c` |
| Plugin lifecycle codification | Multi-file sync errors | `ee62179`, `c581049` |

---

## Work Items

### WI-1: Fix Duplicate Release-Please PRs

**Category:** GitHub Workflow fix
**Priority:** P0
**Eliminates:** ~30% of commit noise

**Root cause hypothesis:** The `sync-release-pr` job in `release-please.yml` pushes a commit to the
release PR branch after release-please creates it. This new commit on main (when the PR auto-merges)
triggers release-please again, which creates another PR for the same version because the sync commit
changed `marketplace.json`.

**Investigation steps:**
1. Check if `marketplace.json` changes on release PR branches trigger release-please re-runs
2. Verify the auto-merge squash + sync commit + release-please trigger sequence
3. Test whether `paths-ignore` for `marketplace.json` in `release-please.yml` stops the loop

**Possible solutions (pick one):**
- Add `paths-ignore: ['.claude-plugin/marketplace.json']` to `release-please.yml` trigger
- Move marketplace sync to a post-merge step instead of pre-merge
- Use `[skip release]` or similar in the sync commit message
- Have release-please manage `marketplace.json` via `extra-files` directly

### WI-2: Auto-Generate README Plugin Table

**Category:** Script + PR Workflow
**Priority:** P1

**Deliverables:**
- `scripts/generate-readme.py` — generates categorized plugin table
- Markers in `README.md`: `<!-- BEGIN PLUGIN TABLE -->` / `<!-- END PLUGIN TABLE -->`
- Integration into `validate-plugin-configs.yml` (or standalone workflow)

**What the script does:**
1. Reads `marketplace.json` for plugin metadata (name, description, category)
2. Counts `*/skills/*/SKILL.md` files per plugin for skill count
3. Counts `*/agents/*.md` files per plugin for agent count
4. Groups by category, generates markdown tables
5. Computes total counts for the header line
6. Replaces content between markers in `README.md`

**Workflow integration:**
- Runs on PRs that modify `*-plugin/**` or `marketplace.json`
- Auto-commits updated README to the PR branch
- Validates on push to main (fails if out of sync)

### WI-3: Unified Skill Linter

**Category:** Script + CI
**Priority:** P1

**Deliverables:**
- `scripts/lint-skills.py` — validates all SKILL.md files
- CI workflow step in existing or new workflow
- GitHub Actions annotation output (`::error file=path,line=N::message`)

**Checks implemented:**

| Check | Severity | Auto-fixable |
|---|---|---|
| Required frontmatter fields present | Error | No |
| Date fields match YYYY-MM-DD format | Error | No |
| `model` is `opus` or `haiku` | Error | No |
| `allowed-tools` entries are known tools | Warning | No |
| File under 500 lines | Warning | No |
| "When to Use" section present | Warning (new), Info (existing) | No |
| "Agentic Optimizations" table present | Warning (new), Info (existing) | No |
| Context commands use `find` not `ls` | Error | Yes |
| Context commands have `2>/dev/null` | Warning | Yes |
| No banned shell operators in context commands | Error | No |
| REFERENCE.md linked if it exists | Warning | No |
| `reviewed` date not older than 90 days | Info | No |

**Modes:**
- `--check` (default): report issues, non-zero exit on errors
- `--fix`: apply auto-fixable changes
- `--format=github`: GitHub Actions annotation format
- `--format=table`: human-readable table
- `--path=<dir>`: limit to specific plugin directory

### WI-4: Plugin Lifecycle Claude Skill

**Category:** Claude Skill (`.claude/skills/`)
**Priority:** P2

**Deliverable:** `.claude/skills/plugin-lifecycle/SKILL.md`

**What it codifies:**

Creating a plugin:
1. Create directory structure (`plugin-name/.claude-plugin/plugin.json`, `skills/`, `README.md`)
2. Populate `plugin.json` with required + recommended fields
3. Run `python3 scripts/sync-plugin-configs.py --fix` to update config files
4. Run `python3 scripts/generate-readme.py` to update README (after WI-2)
5. Verify with `python3 scripts/sync-plugin-configs.py` (check mode)

Deleting a plugin:
1. Remove plugin directory
2. Run `python3 scripts/sync-plugin-configs.py --fix`
3. Run `python3 scripts/generate-readme.py`
4. Verify

Adding a skill:
1. Create `skills/<skill-name>/SKILL.md` with frontmatter template
2. Run `python3 scripts/lint-skills.py --path=<plugin>` to validate (after WI-3)
3. Update plugin README skill count (or rely on auto-generation from WI-2)

### WI-5: Bulk Rule Compliance Claude Skill

**Category:** Claude Skill (`.claude/skills/`)
**Priority:** P2

**Deliverable:** `.claude/skills/apply-rule/SKILL.md`

**Purpose:** When a new rule is added to `.claude/rules/`, this skill helps apply it across all
existing plugins systematically.

**Workflow:**
1. User specifies rule or pattern to enforce
2. Skill scans all SKILL.md files for violations
3. Reports violations grouped by plugin
4. Applies fixes (with user confirmation)
5. Generates a summary of changes for the commit message

**Example invocations:**
- "Apply the find-not-ls rule across all plugins"
- "Ensure all skills have an Agentic Optimizations table"
- "Update all reviewed dates to today"

---

## Implementation Order

| Phase | Items | Outcome |
|---|---|---|
| Phase 1 | WI-1 | Stop duplicate release PRs (biggest noise source) |
| Phase 2 | WI-2, WI-3 | Automated README + skill linting (prevent drift and bulk fixes) |
| Phase 3 | WI-4, WI-5 | Claude skills for human-in-the-loop workflows |

## Success Metrics

| Metric | Current | Target |
|---|---|---|
| Duplicate release commits per release | 1.8x average | 1.0x (zero duplicates) |
| Manual README update commits per quarter | ~2 | 0 |
| Bulk standardization fix commits per quarter | ~3 | 0 (caught at PR time) |
| Config sync fix commits per quarter | ~2 | 0 (already automated, verify) |
| Frontmatter validation errors on main | Unknown | 0 (gated in CI) |

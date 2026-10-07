---
created: 2025-12-17
modified: 2026-05-09
reviewed: 2026-05-09
description: Upgrade blueprint structure to the latest format version. Use when migrating between format versions, enabling monorepo workspaces, or batch upgrading repos.
args: "[--non-interactive|-y]"
argument-hint: "[--non-interactive|-y]"
allowed-tools: Read, Write, Edit, Bash, Glob, AskUserQuestion
name: blueprint-upgrade
---

Upgrade the blueprint structure to the latest format version.

## When to Use This Skill

| Use this skill when... | Use blueprint-init instead when... |
|---|---|
| The project has a manifest at v1.x, v2.x, v3.0, v3.1, or v3.2 | The project has no `docs/blueprint/manifest.json` at all |
| You want the user-facing upgrade entry point with prompts | Use blueprint-migration instead when implementing version-specific logic |
| You're adding the v3.2 task registry or v3.3 monorepo workspaces | Use blueprint-execute instead when you want auto-detection of next step |
| You're running batch upgrades across repos with `--non-interactive`/`-y` | Use blueprint-status instead to first audit current version |

**Current Format Version**: 3.4.0

This command delegates version-specific migration logic to the `blueprint-migration` skill.

## Parameters

Parse `$ARGUMENTS` for flags before running any step:

- `--non-interactive`, `--yes`, `-y`: Skip every `AskUserQuestion` prompt and apply the defaults in the table below. Intended for batch runs across many repos (e.g. looping `/blueprint:upgrade -y` over FVH repos that are already on `main`).

Set an internal `$NONINTERACTIVE` flag to `true` when any of those tokens appear in `$ARGUMENTS`; otherwise `false`. Reference this flag at every `AskUserQuestion` call site in the steps below.

### Non-interactive defaults

When `$NONINTERACTIVE` is `true`, use these answers without prompting and record them in `upgrade_history[].changes` as "auto-selected in non-interactive mode":

| Decision point | Step | Default | Rationale |
|---|---|---|---|
| Remove deprecated generated commands | 3 | "Yes, remove" | Matches "Recommended" option; the files are known-obsolete |
| Task-registry scheduling mode | 3a | "Prompt before running" | Safest; preserves pre-existing behaviour for all tasks |
| Upgrade confirmation | 5 | "Yes, upgrade now" | The flag is explicit consent; skip the confirmation gate |
| Enable document detection (v1.x→v2.0) | 7f | "No, keep manual commands only" | Additive feature; do not silently change behaviour in batch mode |
| Migrate root documentation (v1.x→v2.0) | 7g | "No, leave in root" | Least destructive; moving root docs is reversible but surprising |
| Post-upgrade next action | 11 | Skip — report and exit | The caller is responsible for follow-up in a batch context |

For the `v2.x → v3.0` modification-preservation prompt (delegated to `migrations/v2.x-to-v3.0.md`), default to **"Keep modifications"** — never discard user-edited content in batch mode, and never "Cancel migration" silently.

If a migration step would require any prompt not listed above, **abort the upgrade** with a clear message rather than guessing. The caller can re-run interactively for those repos.

**Steps**:

1. **Check current state**: run the snippet in Step 2. It resolves `$MANIFEST`
   (if no manifest exists, suggest `/blueprint:init` instead) and reads the current
   `format_version`, defaulting to "1.0.0" when the field is missing.

2. **Determine upgrade path**:
   ```bash
   # Resolve manifest path once — use $MANIFEST in all subsequent jq commands.
   # Same order as blueprint-plugin/scripts/get-validation-config.sh.
   if [[ -f docs/blueprint/manifest.json ]]; then
     MANIFEST=docs/blueprint/manifest.json        # v3.0+ canonical (what /blueprint:init writes)
   elif [[ -f docs/blueprint/.manifest.json ]]; then
     MANIFEST=docs/blueprint/.manifest.json       # v3.0 dot-prefixed variant from early migrations
   elif [[ -f .claude/blueprints/.manifest.json ]]; then  # v1.x/v2.x location
     MANIFEST=.claude/blueprints/.manifest.json
   else
     echo "ERROR: no blueprint manifest found. Run /blueprint:init first."
     exit 1
   fi
   current=$(jq -r '.format_version // "1.0.0"' "$MANIFEST")
   target="3.4.0"
   ```

   **Important**: Store the resolved `$MANIFEST` path. Use it in every `jq` invocation throughout this skill and in all delegated migration steps. This avoids silent failures when the filename differs from what a command hard-codes.

   **Version compatibility matrix**:
   | From Version | To Version | Migration Document |
   |--------------|------------|-------------------|
   | 1.0.x        | 1.1.x      | `migrations/v1.0-to-v1.1.md` |
   | 1.x.x        | 2.0.0      | `migrations/v1.x-to-v2.0.md` |
   | 2.x.x        | 3.0.0      | `migrations/v2.x-to-v3.0.md` |
   | 3.0.x        | 3.1.0      | `migrations/v3.0-to-v3.1.md` |
   | 3.1.x        | 3.2.0      | inline (step 3a) |
   | 3.2.x        | 3.3.0      | `migrations/v3.2-to-v3.3.md` |
   | 3.3.x        | 3.4.0      | `migrations/v3.3-to-v3.4.md` |
   | 3.4.0        | 3.4.0      | Already up to date |

3. **Check for deprecated generated commands**:

   Detect skills/commands left by the deprecated `/blueprint:generate-commands` and offer to remove them (auto-"Yes" when `$NONINTERACTIVE`) per [references/deprecated-commands.md](references/deprecated-commands.md). If none are found, continue to step 4.

---

3a. **v3.1 → v3.2 migration: Add task registry**:

   If `task_registry` is missing: ask the scheduling question ("Prompt before running" when `$NONINTERACTIVE`), add the registry, and bump `format_version` to 3.2.0 per [references/v3.1-to-v3.2-task-registry.md](references/v3.1-to-v3.2-task-registry.md).

---

3b. **v3.2 → v3.3 migration: Monorepo support**:

   Delegate to `skills/blueprint-migration/migrations/v3.2-to-v3.3.md` (summary: [references/v3.2-to-v3.3-summary.md](references/v3.2-to-v3.3-summary.md)).

---

3c. **v3.3 → v3.4 migration: Automation block (autonomy levels)**:

   Delegate to `skills/blueprint-migration/migrations/v3.3-to-v3.4.md` (summary: [references/v3.3-to-v3.4-summary.md](references/v3.3-to-v3.4-summary.md)). In `$NONINTERACTIVE` mode take the suggested `autonomy_level`, never higher.

4. **Display upgrade plan**:
   Print the upgrade plan in [references/upgrade-plan.md](references/upgrade-plan.md).

5. **Confirm with user**:

   If `$NONINTERACTIVE` is `true`, skip this confirmation and proceed directly to step 6.

   Otherwise, use AskUserQuestion:
   ```
   question: "Ready to upgrade blueprint from v{current} to v3.4.0?"
   options:
     - "Yes, upgrade now" → proceed
     - "Show detailed migration steps" → display migration document
     - "Create backup first" → run git stash or backup then proceed
     - "Cancel" → exit
   ```

6. **Load and execute migration document**:
   - Read the appropriate migration document from `blueprint-migration` skill
   - For v1.x → v2.0: Load `migrations/v1.x-to-v2.0.md`
   - For v2.x → v3.0: Load `migrations/v2.x-to-v3.0.md`
   - For v3.0 → v3.1: Load `migrations/v3.0-to-v3.1.md`
   - For v3.1 → v3.2: Execute inline step 3a above
   - For v3.2 → v3.3: Load `migrations/v3.2-to-v3.3.md` (see step 3b summary)
   - For v3.3 → v3.4: Load `migrations/v3.3-to-v3.4.md` (see step 3c summary)
   - Execute each step with user confirmation for destructive operations

7. **v1.x → v2.0 migration overview** (from migration document):

   Sub-steps a–g, including the 7f/7g prompts and their `$NONINTERACTIVE` defaults, are in [references/v1.x-to-v2.0-overview.md](references/v1.x-to-v2.0-overview.md).

8. **v2.x → v3.0 migration overview** (from migration document):

   Sub-steps a–f are in [references/v2.x-to-v3.0-overview.md](references/v2.x-to-v3.0-overview.md).

9. **Update manifest** (v3.0.0 schema): write the manifest using the v3.0.0 schema template in [REFERENCE.md](REFERENCE.md). Preserve `created_at`, `project.name`, `project.type`, `structure.has_modular_rules`, and `structure.claude_md_mode` from the previous manifest. Set `updated_at` to now, `created_by.blueprint_plugin` to "3.0.0", and `generated.rules` from the migrated skills→rules conversion.

10. **Report**: print the upgrade report using the standard template in [REFERENCE.md](REFERENCE.md), substituting `{previous}` with the prior `format_version` and `{n}` placeholders with the actual counts.

11. **Prompt for next action**:

   If `$NONINTERACTIVE` is `true`, skip this prompt entirely — print the report from step 10 and return. The batch caller owns follow-up (status checks, commits, etc.).

   Otherwise, ask with the prompt in [references/next-action-prompt.md](references/next-action-prompt.md).

   **Based on selection:**
   - "Check status" → Run `/blueprint:status`
   - "Regenerate rules" → Run `/blueprint:generate-rules`
   - "Update CLAUDE.md" → Run `/blueprint:claude-md`
   - "Commit changes" → Run `/git:commit` with migration message

**Post-migration assertion**:
After any version bump, verify `format_version` actually changed to the target. This catches silent failures where `jq` operated on the wrong path and exited 0 with empty output:

```bash
actual=$(jq -r '.format_version' "$MANIFEST")
if [[ "$actual" != "$target" ]]; then
  echo "ERROR: Migration failed — format_version is '$actual', expected '$target'"
  echo "Check that $MANIFEST was written correctly and rerun the migration step."
  exit 1
fi
echo "Migration verified: format_version = $actual in $MANIFEST"
```

**Rollback**:
If upgrade fails:
- Check git status for changes made
- Use `git checkout -- .claude/` and `git checkout -- docs/blueprint/` to restore original structure
- Manually move content back if needed
- Report specific failure point for debugging

# blueprint-upgrade — Upgrade Plan Display (Step 4)

```
Blueprint Upgrade

Current version: v{current}
Target version: v3.4.0

Major changes in v3.0:
- Blueprint state moves from .claude/blueprints/ to docs/blueprint/
- Generated skills become rules in .claude/rules/
- No more generated/ subdirectory - cleaner structure
- All blueprint-related files consolidated under docs/blueprint/

Major changes in v3.2:
- Task registry tracks operational metadata for maintenance tasks
- Smart scheduling: tasks know when they were last run
- Enable/disable individual tasks
- Incremental operations with context persistence

Major changes in v3.3:
- First-class monorepo support: root/child/standalone roles
- `workspaces` block in manifest.json (additive; standalone projects omit it)
- New /blueprint:workspace-scan skill for discovering child blueprints
- Cross-workspace references (`<path>/ADR-NNN`, `/ADR-NNN`)
- Optional portfolio feature tracking via implemented_by links

Major changes in v3.4:
- `automation` block: autonomy_level (0 manual / 1 ambient bookkeeping /
  2 quiet autopilot / 3 scheduled pipeline), interaction_mode, work_orders
- task_registry auto_run/schedule contract becomes executable
  (scripts/blueprint-autorun.sh + SessionStart probe)

(For v2.0 changes when upgrading from v1.x:)
- PRDs, ADRs, PRPs move to docs/ (project documentation)
- Custom overrides in .claude/skills/
- Content hashing for modification detection
```

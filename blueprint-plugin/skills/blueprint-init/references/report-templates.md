# blueprint-init — Report and Quick Reference (Steps 10–11)

Output templates for the end of the run.

## Step 10 — initialization report

```
Blueprint Development initialized! (v3.4.0)

Blueprint structure created:
- docs/blueprint/manifest.json
- docs/blueprint/work-orders/
- docs/blueprint/README.md
[- docs/blueprint/feature-tracker.json (if feature tracking enabled)]

Project documentation (top-level — derive-* skills write here):
- docs/prds/           (Product Requirements Documents)
- docs/adrs/           (Architecture Decision Records)
- docs/prps/           (Product Requirement Prompts)
- docs/trps/           (Test Regression Plans — created on first /blueprint:derive-tests run)

Claude configuration:
- .claude/rules/       (modular rules, including generated)
- .claude/skills/      (custom skill overrides)

Configuration:
- Rules mode: both (CLAUDE.md + .claude/rules/)
[- Feature tracking: enabled]
[- Decision detection: enabled (Claude will prompt when discussions should become ADR/PRD/PRP)]
[- Task scheduling: {prompt|auto-run safe|fully automatic|manual only}]

[Migrated documentation:]
[- {original} → {destination} (for each migrated file)]

Architecture:
- Plugin layer: Generic commands from blueprint-plugin (auto-updated)
- Generated layer: Rules/commands regeneratable from docs/prds/
- Custom layer: Your overrides in .claude/skills/
```

## Quick Reference

**Quick Reference** (show if user selects "I'm done for now"):
```
Management commands:
- /blueprint:status          - Check version and configuration
- /blueprint:upgrade         - Upgrade to latest format version
- /blueprint:derive-plans    - Derive PRDs, ADRs, and PRPs from git history
- /blueprint:derive-rules    - Derive rules from git commit decisions
- /blueprint:prp-create      - Create a Product Requirement Prompt
- /blueprint:generate-rules  - Generate rules from PRDs
- /blueprint:sync            - Check for stale generated content
- /blueprint:promote         - Move generated content to custom layer
- /blueprint:rules           - Manage modular rules
- /blueprint:claude-md       - Update CLAUDE.md
- /blueprint:feature-tracker-status  - View feature completion stats
- /blueprint:feature-tracker-sync    - Sync tracker with project files
```

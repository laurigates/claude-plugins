# blueprint-init — Manifest Template (Step 7)

The `docs/blueprint/manifest.json` that Step 7 writes.

## manifest.json (v3.4.0 schema)

```json
{
  "format_version": "3.4.0",
  "created_at": "[ISO timestamp]",
  "updated_at": "[ISO timestamp]",
  "created_by": {
    "blueprint_plugin": "3.3.0"
  },
  "project": {
    "name": "[detected from package.json/pyproject.toml or directory name]",
    "detected_stack": []
  },
  "structure": {
    "has_prds": true,
    "has_adrs": true,
    "has_prps": true,
    "has_work_orders": true,
    "has_modular_rules": true,
    "has_feature_tracker": "[based on user choice]",
    "has_document_detection": "[based on user choice]",
    "claude_md_mode": "both",
    "generated_rules_path": "[based on Step 4a; defaults to .claude/rules/ when prompt skipped]"
  },
  "feature_tracker": {
    "file": "feature-tracker.json",
    "source_document": "[auto-detected]",
    "sync_targets": ["TODO.md"]
  },
  "generated": {
    "rules": {},
    "commands": {}
  },
  "custom_overrides": {
    "skills": [],
    "commands": []
  },
  "automation": {
    "autonomy_level": "[based on maintenance task choice: 0 for Prompt/Manual, 1 for Auto-run safe, 2 for Fully automatic]",
    "interaction_mode": "normal",
    "work_orders": {
      "auto_draft": false,
      "auto_execute": false
    }
  },
  "task_registry": {
    "derive-plans": {
      "enabled": true,
      "auto_run": false,
      "last_completed_at": null,
      "last_result": null,
      "schedule": "weekly",
      "stats": {},
      "context": {}
    },
    "derive-rules": {
      "enabled": true,
      "auto_run": false,
      "last_completed_at": null,
      "last_result": null,
      "schedule": "weekly",
      "stats": {},
      "context": {}
    },
    "generate-rules": {
      "enabled": true,
      "auto_run": false,
      "last_completed_at": null,
      "last_result": null,
      "schedule": "on-change",
      "stats": {},
      "context": {}
    },
    "adr-validate": {
      "enabled": true,
      "auto_run": "[based on maintenance task choice: true if auto-run safe, false otherwise]",
      "last_completed_at": null,
      "last_result": null,
      "schedule": "weekly",
      "stats": {},
      "context": {}
    },
    "feature-tracker-sync": {
      "enabled": true,
      "auto_run": "[based on maintenance task choice: true if auto-run safe, false otherwise]",
      "last_completed_at": null,
      "last_result": null,
      "schedule": "daily",
      "stats": {},
      "context": {}
    },
    "sync-ids": {
      "enabled": true,
      "auto_run": "[based on maintenance task choice: true if auto-run safe, false otherwise]",
      "last_completed_at": null,
      "last_result": null,
      "schedule": "on-change",
      "stats": {},
      "context": {}
    },
    "claude-md": {
      "enabled": true,
      "auto_run": false,
      "last_completed_at": null,
      "last_result": null,
      "schedule": "on-change",
      "stats": {},
      "context": {}
    },
    "curate-docs": {
      "enabled": false,
      "auto_run": false,
      "last_completed_at": null,
      "last_result": null,
      "schedule": "on-demand",
      "stats": {},
      "context": {}
    }
  }
}
```

## Notes

Note: As of v3.2.0, progress tracking is consolidated into feature-tracker.json (work-overview.md removed).

# Blueprint Upgrade — Reference

Reference templates for `/blueprint:upgrade`: the v3.0.0 manifest schema produced by step 9, and the standard upgrade report template emitted by step 10.

## v3.0.0 Manifest Schema

```json
{
  "format_version": "3.0.0",
  "created_at": "[preserved]",
  "updated_at": "[now]",
  "created_by": {
    "blueprint_plugin": "3.0.0"
  },
  "project": {
    "name": "[preserved]",
    "type": "[preserved]",
    "detected_stack": []
  },
  "structure": {
    "has_prds": true,
    "has_adrs": "[detected]",
    "has_prps": "[detected]",
    "has_work_orders": true,
    "has_ai_docs": "[detected]",
    "has_modular_rules": "[preserved]",
    "has_document_detection": "[based on user choice]",
    "claude_md_mode": "[preserved]"
  },
  "generated": {
    "rules": {
      "[rule-name]": {
        "source": "docs/prds/...",
        "source_hash": "sha256:...",
        "generated_at": "[now]",
        "plugin_version": "3.0.0",
        "content_hash": "sha256:...",
        "status": "current"
      }
    },
    "commands": {}
  },
  "task_registry": {
    "// note": "Added by v3.1 → v3.2 migration step above"
  },
  "custom_overrides": {
    "rules": ["[any promoted rules]"],
    "commands": []
  },
  "upgrade_history": [
    {
      "from": "{previous}",
      "to": "3.0.0",
      "date": "[now]",
      "changes": ["Moved state to docs/blueprint/", "Converted skills to rules", "..."]
    }
  ]
}
```

## Step 10 Report Template

```
Blueprint upgraded successfully!

v{previous} → v3.0.0

State files moved to docs/blueprint/:
- .manifest.json
- feature-tracker.json
- work-orders/ directory
- ai_docs/ directory

Generated rules (.claude/rules/):
- {n} rules (converted from skills)

Custom layer (.claude/skills/):
- {n} promoted rules (preserved modifications)
- {n} promoted skills

[Document detection: enabled (if selected)]

Task registry:
- {n} tasks registered with scheduling metadata
- Auto-run mode: {user choice from migration step}
- Run /blueprint:status to see task health dashboard

New v3.0 architecture:
- Blueprint state: docs/blueprint/ (version-controlled with project)
- Generated rules: .claude/rules/ (project-specific context)
- Custom layer: Your overrides, never auto-modified
- Removed: .claude/blueprints/generated/ (no longer needed)
```

# Blueprint Upgrade — Reference

Reference templates for `/blueprint:upgrade`: the v3.0.0 manifest schema produced by step 9, the standard upgrade report template emitted by step 10, the post-migration assertion, and the rollback procedure.

## v3.0.0 Manifest Schema

```json
{
  "format_version": "3.0.0",
  "created_at": "[preserved]",
  "updated_at": "[now]",
  "created_by": {
    "blueprint_plugin": "[plugin version, read from plugin.json]"
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

## Post-Migration Assertion

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

## Rollback

If upgrade fails:
- Check git status for changes made
- Use `git checkout -- .claude/` and `git checkout -- docs/blueprint/` to restore original structure
- Manually move content back if needed
- Report specific failure point for debugging

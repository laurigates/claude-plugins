# blueprint-work-order — Manifest ID-Registry Entry (Step 8.5)

```json
{
  "id_registry": {
    "documents": {
      "WO-NNN": {
        "path": "docs/blueprint/work-orders/NNN-task-name.md",
        "title": "[Task Name]",
        "implements": ["PRP-NNN"],
        "github_issues": [N],
        "created": "{date}"
      }
    },
    "github_issues": {
      "N": ["WO-NNN", "PRP-NNN"]
    }
  }
}
```

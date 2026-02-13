# Health Check Reference

## Diagnostic Report Template

```
Claude Code Health Check
========================
Project: <current-directory>
Date: <timestamp>

Plugin Registry
---------------
Status: [OK|WARN|ERROR]
- Installed plugins: N
- Project-scoped: N
- Orphaned entries: N
- Issues: <details if any>

Settings Files
--------------
Status: [OK|WARN|ERROR]
- User settings: [OK|MISSING|INVALID]
- Project settings: [OK|MISSING|INVALID]
- Local settings: [OK|MISSING|N/A]
- Permission patterns: N configured
- Issues: <details if any>

Hooks
-----
Status: [OK|WARN|ERROR|N/A]
- Configured hooks: N
- Issues: <details if any>

MCP Servers
-----------
Status: [OK|WARN|ERROR|N/A]
- Configured servers: N
- Issues: <details if any>

Summary
-------
[All checks passed | N issues found]

Recommended Actions:
1. <action if needed>
2. <action if needed>

Run `/health:plugins --fix` to fix plugin registry issues.
Run `/health:settings --fix` to fix settings issues.
```

## Known Issues Database

| Issue | Symptoms | Solution |
|-------|----------|----------|
| #14202 | Plugin shows "installed" but not active in project | Run `/health:plugins --fix` |
| Orphaned projectPath | Plugin was installed for deleted project | Run `/health:plugins --fix` |
| Invalid JSON | Settings file won't load | Validate and fix JSON syntax |
| Hook timeout | Commands hang or fail silently | Check hook timeout settings |

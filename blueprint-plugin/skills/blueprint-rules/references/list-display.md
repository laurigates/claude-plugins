# blueprint-rules — List Display (Step 3)

The layout for the "List existing rules" action. Group rules by level, show the `paths:` patterns of each path-specific rule, and close with the totals line.

```
📜 Modular Rules

User-Level Rules (~/.claude/rules/ — personal, all projects):
- preferences.md - Personal coding style
- workflow.md - Personal workflow habits

Project Global Rules (apply to all files):
- development.md - TDD workflow and conventions
- testing.md - Test requirements

Path-Specific Rules (apply to specific paths):
- frontend/react.md - paths: ["src/components/**/*.{ts,tsx}"]
- backend/api.md - paths: ["src/api/**/*.ts"]

Total: 6 rules (2 user-level, 2 global, 2 path-specific)
```

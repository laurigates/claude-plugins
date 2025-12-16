---
description: "List, filter, and manage @HANDOFF markers across the codebase"
allowed_tools: [Bash, Grep, Read, TodoWrite]
---

# /handoffs [OPTIONS]

List all `@HANDOFF(agent)` markers in the codebase with filtering and status information.

## Usage

```bash
/handoffs                           # List all pending handoffs
/handoffs --agent ux-implementation # Filter by target agent
/handoffs --stale                   # Show markers older than 7 days
/handoffs --type accessibility      # Filter by handoff type
/handoffs --priority blocking       # Filter by priority level
/handoffs --summary                 # Show counts by agent/type
```

## Parameters

- `--agent <name>` - Filter by target agent (e.g., `ux-implementation`, `typescript-development`)
- `--stale` - Show only markers that haven't been addressed in 7+ days (based on git blame)
- `--type <type>` - Filter by handoff type (e.g., `accessibility`, `form-validation`, `loading-states`)
- `--priority <level>` - Filter by priority (`blocking`, `enhancement`)
- `--summary` - Show summary counts instead of full listings
- `--completed` - Include completed handoffs (`@HANDOFF-COMPLETE`)

## Steps

1. **Scan for markers**:
   ```bash
   # Find all @HANDOFF markers
   rg "@HANDOFF\([^)]+\)" --type ts --type tsx --type js --type jsx --type vue -n
   ```

2. **Parse marker content**:
   - Extract target agent from `@HANDOFF(agent-name)`
   - Parse JSON-like content for type, priority, context, needs
   - Note file path and line number

3. **Apply filters**:
   - If `--agent`: filter to matching target agent
   - If `--type`: filter to matching handoff type
   - If `--priority`: filter to matching priority level
   - If `--stale`: use git blame to find markers >7 days old

4. **Format output**:

   **Default listing**:
   ```
   ## Pending Handoffs

   ### ux-implementation (3 markers)

   **src/components/Modal.tsx:42** [blocking]
   - Type: accessibility
   - Context: Modal dialog for confirmation actions
   - Needs:
     - Focus trap implementation
     - ARIA dialog pattern
     - Keyboard handling (Escape to close)

   **src/pages/Register.tsx:156** [blocking]
   - Type: form-validation
   - Context: User registration form
   - Needs:
     - Error message placement
     - Focus management on validation failure

   **src/components/DataTable.tsx:89** [enhancement]
   - Type: responsive
   - Context: Data table with sortable columns
   - Needs:
     - Mobile layout pattern
     - Touch-friendly sort controls

   ### typescript-development (1 marker)

   **src/components/Modal.tsx:98** [blocking]
   - Type: component-implementation
   - Context: Modal with UX specs from above
   - Needs:
     - React component implementation
     - State management integration
   ```

   **Summary output** (`--summary`):
   ```
   ## Handoff Summary

   ### By Agent
   - ux-implementation: 3 (2 blocking, 1 enhancement)
   - typescript-development: 1 (1 blocking)
   - code-review: 0

   ### By Type
   - accessibility: 1
   - form-validation: 1
   - responsive: 1
   - component-implementation: 1

   ### By Priority
   - blocking: 3
   - enhancement: 1

   Total: 4 pending handoffs
   ```

5. **Stale detection** (if `--stale`):
   - Use git blame to get last modification date for each marker line
   - Flag markers older than 7 days
   - Show days since last modification

   ```
   ## Stale Handoffs (>7 days)

   **src/components/OldComponent.tsx:34** [14 days old]
   - Agent: ux-implementation
   - Type: accessibility
   - Last touched: 2024-01-01 by developer@example.com
   ```

6. **Provide next steps**:
   ```
   ## Next Steps

   To address blocking handoffs:
   1. Run the ux-implementation agent to process accessibility markers
   2. Run the typescript-development agent after UX specs are complete

   To clean up stale markers:
   - Review if still needed
   - Convert to @HANDOFF-COMPLETE if done
   - Remove if obsolete
   ```

## Example Output

```
## Pending Handoffs

Found 4 handoff markers across 3 files.

### ux-implementation (3 markers)

📍 **src/components/Modal.tsx:42** `blocking`
```typescript
// @HANDOFF(ux-implementation) {
//   type: "accessibility",
//   context: "Modal dialog for confirmation",
//   needs: ["focus trap", "ARIA dialog", "Escape key"]
// }
```
→ Needs: Focus trap, ARIA dialog pattern, keyboard handling

📍 **src/pages/Register.tsx:156** `blocking`
→ Needs: Error placement, focus management, ARIA live regions

📍 **src/components/DataTable.tsx:89** `enhancement`
→ Needs: Mobile layout, touch-friendly controls

### typescript-development (1 marker)

📍 **src/components/Modal.tsx:98** `blocking`
→ Needs: React implementation, state management

---

**Summary**: 4 total (3 blocking, 1 enhancement)

**Recommended workflow**:
1. Process ux-implementation markers first (blocking work)
2. Then typescript-development can implement specified patterns
3. Finally code-review for quality validation
```

## Error Handling

- **No markers found**: Report "No @HANDOFF markers found in codebase"
- **Invalid filter**: Report unrecognized agent/type and list valid options
- **Git not available**: Skip stale detection, note in output

## See Also

- **Skills**: `ux-handoff-markers` for marker format and patterns
- **Skills**: `agent-coordination-patterns` for workflow patterns
- **Skills**: `agent-file-coordination` for file-based coordination
- **Commands**: `/workflow:dev` for automated development with handoffs

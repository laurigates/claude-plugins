---
model: sonnet
created: 2025-12-22
modified: 2026-02-06
reviewed: 2025-12-22
description: "Move generated artifact to custom layer to preserve modifications"
args: "[skill-name|command-name]"
allowed-tools: Read, Write, Bash, AskUserQuestion
argument-hint: "Name of the skill or command to promote"
name: blueprint-promote
---

Copy a generated rule to the custom rules layer for preservation.

**Purpose**:
- Copy generated content from `.claude/rules/` to preserve modifications
- Mark as acknowledged in manifest to prevent overwrite warnings
- Generated rules in `.claude/rules/` are the standard location (v3.0)

**Usage**: `/blueprint:promote [name]`

**Examples**:
- `/blueprint:promote testing-strategies` - Acknowledge a rule's modifications

**Steps**:

1. **Parse argument**:
   - Extract `name` from arguments
   - If no name provided, list available generated rules and ask user to choose

2. **Locate the rule**:
   ```bash
   # Check if it's a generated rule
   test -f .claude/rules/{name}.md
   ```

   If not found:
   ```
   Rule '{name}' not found in generated content.

   Available rules:
   - architecture-patterns
   - testing-strategies
   - implementation-guides
   - quality-standards
   ```

3. **Check if already acknowledged**:
   - Read manifest for `custom_overrides.rules`
   - If already in list, report "Already acknowledged"

4. **Confirm acknowledgment**:
   ```
   question: "Acknowledge modifications to {name}?"
   description: |
     This will:
     1. Mark {name} as user-modified in manifest
     2. Prevent overwrite warnings during sync
     3. Keep the rule in .claude/rules/

   options:
     - label: "Yes, acknowledge"
       description: "Mark as user-modified and preserve changes"
     - label: "No, keep as generated"
       description: "Leave as regeneratable (may show warnings)"
   ```

5. **Update manifest**:
   - Add to `custom_overrides.rules`
   - Update `updated_at` timestamp

   Example manifest update:
   ```json
   {
     "generated": {
       "rules": {
         // testing-strategies still listed
       }
     },
     "custom_overrides": {
       "rules": ["testing-strategies"]  // added
     }
   }
   ```

6. **Report**:
   ```
   Rule modifications acknowledged!

   testing-strategies.md:
   - Location: .claude/rules/testing-strategies.md
   - Status: User-modified (acknowledged)

   This rule will now:
   - Not show modification warnings in /blueprint:sync
   - Still be tracked in manifest
   - Be your responsibility to maintain

   To edit: .claude/rules/testing-strategies.md
   ```

**Architecture note (v3.0)**:
Generated content now goes directly to `.claude/rules/` instead of a separate generated layer.
The manifest tracks which rules are user-modified vs auto-generated.

**Tips**:
- Acknowledge rules you want to customize
- Unacknowledged modified rules will show warnings in /blueprint:sync
- You can regenerate by removing from custom_overrides and running `/blueprint:generate-rules`

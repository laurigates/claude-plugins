---
created: 2025-12-22
modified: 2025-12-22
reviewed: 2025-12-22
description: "Move generated artifact to custom layer to preserve modifications"
args: "[skill-name|command-name]"
allowed_tools: [Read, Write, Bash, AskUserQuestion]
argument-hint: "Name of the skill or command to promote"
---

Promote a generated skill or command to the custom layer.

**Purpose**:
- Move generated content from `.claude/blueprints/generated/` to `.claude/skills/` or `.claude/commands/`
- Preserve local modifications that would otherwise be overwritten on regeneration
- Custom layer takes precedence, so your version will always be used

**Usage**: `/blueprint:promote [name]`

**Examples**:
- `/blueprint:promote testing-strategies` - Promote a skill
- `/blueprint:promote project-continue` - Promote a command

**Steps**:

1. **Parse argument**:
   - Extract `name` from arguments
   - If no name provided, list available generated content and ask user to choose

2. **Locate the artifact**:
   ```bash
   # Check if it's a skill
   test -d .claude/blueprints/generated/skills/{name}

   # Check if it's a command
   test -f .claude/blueprints/generated/commands/{name}.md
   ```

   If not found in either location:
   ```
   Artifact '{name}' not found in generated content.

   Available skills:
   - architecture-patterns
   - testing-strategies
   - implementation-guides
   - quality-standards

   Available commands:
   - project-continue
   - project-test-loop
   ```

3. **Check target doesn't already exist**:
   ```bash
   # For skills
   test -d .claude/skills/{name}

   # For commands
   test -f .claude/commands/{name}.md
   ```

   If already exists:
   ```
   question: "Custom {name} already exists in .claude/skills/. What would you like to do?"
   options:
     - label: "Overwrite custom version"
       description: "Replace existing custom with current generated content"
     - label: "Keep custom version"
       description: "Don't promote, keep the existing custom version"
     - label: "View diff first"
       description: "Compare versions before deciding"
     - label: "Cancel"
       description: "Don't make any changes"
   ```

4. **Confirm promotion**:
   ```
   question: "Promote {name} from generated to custom layer?"
   description: |
     This will:
     1. Copy {name} to .claude/skills/{name}/ (or .claude/commands/)
     2. Remove from .claude/blueprints/generated/skills/{name}/
     3. Update manifest to track as custom override
     4. Prevent future regeneration from overwriting

   options:
     - label: "Yes, promote"
       description: "Move to custom layer and preserve my modifications"
     - label: "No, keep in generated"
       description: "Leave in generated layer (may be overwritten on regenerate)"
   ```

5. **Execute promotion**:

   **For skills:**
   ```bash
   # Create custom skills directory if needed
   mkdir -p .claude/skills/{name}

   # Copy skill to custom layer
   cp -r .claude/blueprints/generated/skills/{name}/* .claude/skills/{name}/

   # Remove from generated
   rm -rf .claude/blueprints/generated/skills/{name}
   ```

   **For commands:**
   ```bash
   # Create custom commands directory if needed
   mkdir -p .claude/commands

   # Copy command to custom layer
   cp .claude/blueprints/generated/commands/{name}.md .claude/commands/{name}.md

   # Remove from generated
   rm .claude/blueprints/generated/commands/{name}.md
   ```

6. **Update manifest**:
   - Remove from `generated.skills` or `generated.commands`
   - Add to `custom_overrides.skills` or `custom_overrides.commands`
   - Update `updated_at` timestamp

   Example manifest update:
   ```json
   {
     "generated": {
       "skills": {
         // testing-strategies removed
       }
     },
     "custom_overrides": {
       "skills": ["testing-strategies"],  // added
       "commands": []
     }
   }
   ```

7. **Report**:
   ```
   Skill promoted to custom layer!

   testing-strategies:
   - From: .claude/blueprints/generated/skills/testing-strategies/
   - To: .claude/skills/testing-strategies/

   This skill will now:
   - Take precedence over plugin and generated skills
   - Not be affected by /blueprint:generate-skills
   - Be your responsibility to maintain

   To edit: .claude/skills/testing-strategies/skill.md
   ```

**Precedence reminder**:
```
Custom layer (.claude/skills/)          ← HIGHEST (your version)
    ↓ overrides
Generated layer (blueprints/generated/) ← regeneratable
    ↓ extends
Plugin layer (blueprint-plugin/)        ← LOWEST (auto-updated)
```

**Tips**:
- Promote skills you want to heavily customize
- Keep commonly regenerated content in generated layer
- Custom layer requires manual maintenance
- You can always regenerate by removing from custom and running `/blueprint:generate-skills`

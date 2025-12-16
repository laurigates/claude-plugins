---
description: "Synchronize documentation with actual skills, commands, and agents in the codebase"
allowed_tools: [Bash, Grep, Glob, Read, Edit, Write, TodoWrite]
---

# /docs:sync [OPTIONS]

Scan the codebase for skills, commands, and agents, then update all documentation to reflect the current state. Fixes count mismatches, adds missing entries, and removes stale references.

## Usage

```bash
/docs:sync                        # Sync all documentation
/docs:sync --scope skills         # Only sync skill documentation
/docs:sync --scope commands       # Only sync command documentation
/docs:sync --scope agents         # Only sync agent documentation
/docs:sync --dry-run              # Show what would change without modifying
/docs:sync --verbose              # Show detailed scanning output
```

## Parameters

- `--scope <type>` - Limit sync to specific type: `skills`, `commands`, `agents`, or `all` (default)
- `--dry-run` - Preview changes without modifying files
- `--verbose` - Show detailed progress during scanning

## Workflow

### Phase 1: Discovery

1. **Scan source directories**:
   ```bash
   # Skills
   find .claude/skills -name "SKILL.md" -type f

   # Commands
   find .claude/commands -name "*.md" -type f ! -name "CLAUDE.md"

   # Agents
   find .claude/agents -name "*.md" -type f
   ```

2. **Extract metadata from each item**:
   - **Skills**: Parse YAML frontmatter for `name` and `description`
   - **Commands**: Parse `description` from frontmatter, infer namespace from path
   - **Agents**: Parse frontmatter for `name`, `description`, `tools`

3. **Parse existing documentation**:
   - `.claude/skills/CLAUDE.md` - Current skill catalog with categories
   - `.claude/commands/CLAUDE.md` - Command reference with namespaces
   - Root `CLAUDE.md` - Summary counts and highlights

### Phase 2: Analysis

1. **Compare actual vs documented**:
   - Find items in directories but not in documentation (NEW)
   - Find items in documentation but not in directories (STALE)
   - Check if counts match

2. **Categorize new items**:

   **For skills**, determine category by:
   - Name patterns: `ux-*`, `git-*`, `python-*` → matching category
   - Description keywords: "accessibility", "testing", "infrastructure"
   - Similar existing skills in same domain
   - If uncertain, suggest "Uncategorized" for manual review

   **For commands**, determine namespace from file path:
   - `commands/git/commit.md` → `git:` namespace
   - `commands/handoffs.md` → Root level

   **For agents**, determine domain from description keywords

3. **Identify documentation sections to update**:
   - Count patterns: `**N skills**`, `N total`, `(N skills)`
   - List sections by category/namespace
   - Summary tables

### Phase 3: Updates

1. **Update counts** throughout documentation:
   - Search for patterns like `**63 skills**` or `63 specialized skills`
   - Replace with accurate count
   - Update category counts like `### Core Development (9 skills)`

2. **Add new items** to appropriate sections:

   **Skills catalog format**:
   ```markdown
   ### Category Name (N skills)
   - **skill-name** - Description from SKILL.md frontmatter
   ```

   **Command table format**:
   ```markdown
   | Namespace | Commands | Purpose |
   | `/command` | Description | Usage context |
   ```

   **Agent inventory format**:
   ```markdown
   | Agent | Purpose | Key Tools |
   | **agent-name** | Description | Tool1, Tool2 |
   ```

3. **Remove stale entries** that no longer exist in codebase

4. **Update cross-references**:
   - "See also" sections
   - Related skills/commands lists

### Phase 4: Report

Generate summary of changes:

```markdown
## Documentation Sync Report

### Skills
- ✅ Added N new skills to catalog
  - skill-name → Category Name
- ✅ Removed N stale skills
- ✅ Updated skill count: OLD → NEW

### Commands
- ✅ Added N new commands
  - /namespace:command → Description
- ✅ Updated command counts

### Agents
- ✅ Added N new agents
  - agent-name → Domain
- ✅ Updated agent inventory

### Files Modified
- path/to/file.md (N changes)

### Manual Review Needed
- item-name: Could not determine category
```

## Documentation Files to Update

### Primary targets (always check):
- `.claude/skills/CLAUDE.md` - Skills catalog
- `.claude/commands/CLAUDE.md` - Commands reference
- `CLAUDE.md` (root) - Repository overview

### Secondary targets (if they exist):
- `README.md` - Project README
- `docs/` directory content
- Any file containing skill/command/agent counts

## Categorization Rules

### Skill Categories

| Pattern | Category |
|---------|----------|
| `ux-*`, `accessibility-*`, `design-*` | UX & Accessibility |
| `git-*`, `github-*` | Version Control & GitHub |
| `python-*`, `uv-*`, `ruff-*` | Python Development |
| `typescript-*`, `nodejs-*`, `vitest-*` | TypeScript/JavaScript |
| `rust-*`, `cpp-*`, `embedded-*` | Systems Languages |
| `container-*`, `kubernetes-*`, `helm-*`, `terraform-*` | Infrastructure & DevOps |
| `test-*`, `playwright-*`, `mutation-*` | Testing & Quality |
| `agent-*`, `multi-agent-*`, `graphiti-*` | Meta & Coordination |

### Command Namespaces

Determined by directory structure:
- `commands/git/*.md` → `git:` namespace
- `commands/docs/*.md` → `docs:` namespace
- `commands/*.md` (root) → Root level commands

## Error Handling

- **Missing documentation file**: Create from template with discovered content
- **Malformed YAML frontmatter**: Warn and skip item, report in summary
- **Ambiguous categorization**: Add to "Uncategorized" section, flag for review
- **Duplicate entries**: Warn and keep first occurrence

## Best Practices

1. **Run after adding features** - Keep docs in sync with implementation
2. **Review dry-run first** - Verify categorization before applying
3. **Commit docs separately** - Use `docs:` conventional commit prefix
4. **Check cross-references** - Ensure "See also" sections are updated

## Example Session

```bash
# After adding new skills
/docs:sync --dry-run

# Review output, then apply
/docs:sync

# Commit the documentation updates
git add .claude/
git commit -m "docs: sync documentation with new UX implementation features"
```

## See Also

- **Commands**: `/docs:generate` for generating new documentation
- **Skills**: `release-please-protection` for automated versioning
- **Workflow**: Run after `/project:new` or major feature additions

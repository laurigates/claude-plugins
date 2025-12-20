# claude-plugins

Claude Code plugin collection providing skills, commands, and agents for development workflows.

## Project Structure

```
plugins/
├── <plugin-name>/
│   ├── .claude-plugin/
│   │   └── plugin.json      # Plugin metadata
│   ├── README.md            # Plugin documentation
│   ├── skills/
│   │   └── <skill-name>/
│   │       └── skill.md     # Skill definition
│   ├── commands/
│   │   └── <command>.md     # Slash commands
│   └── agents/              # Agent definitions (optional)
```

## Creating New Skills

See `.claude/rules/skill-development.md` for detailed patterns.

### Quick Start

1. Create skill directory: `mkdir -p <plugin>/skills/<skill-name>`
2. Create `skill.md` with YAML frontmatter:
   ```yaml
   ---
   name: <Skill Name>
   description: <1-2 sentence description>
   allowed-tools: Bash, Read, Grep, Glob, TodoWrite
   ---
   ```
3. Follow content structure: Core Expertise → Commands → Patterns → Quick Reference
4. Include agentic optimizations table
5. Update plugin metadata (`plugin.json`, `README.md`)

### Skill Granularity Decision

| Choose... | When... |
|-----------|---------|
| Single skill | Operations are related and share context |
| Multiple skills | Distinct workflows, different user intents |

Example: `bun-package-manager` (deps) vs `bun-development` (run/test/build)

## Creating Commands

Commands are user-invocable via `/plugin:command` syntax.

1. Create command file: `<plugin>/commands/<name>.md`
2. Add YAML frontmatter:
   ```yaml
   ---
   description: What it does
   args: <arg-spec>
   allowed-tools: Bash, Read
   argument-hint: human hint
   ---
   ```
3. Include: Context → Execution → Post-actions

## Agentic Optimization

See `.claude/rules/agentic-optimization.md` for detailed patterns.

Key principles:
- **Compact output**: `--dots`, `--reporter=github`, `-c`
- **Fail fast**: `--bail=1`, `-x`
- **CI modes**: `--reporter=junit`, `--frozen-lockfile`
- **Machine-readable**: JSON output when available

## Plugin Organization

| Plugin Type | Example | Contains |
|-------------|---------|----------|
| Tool-focused | `tools-plugin` | CLI tool skills (fd, rg, jq) |
| Language-focused | `typescript-plugin` | Language ecosystem skills |
| Workflow-focused | `git-plugin` | Git/GitHub operations |
| Infrastructure | `configure-plugin` | Configuration automation |

## Development Workflow

1. **Research documentation** - Use context7, web search
2. **Plan skill structure** - Decide granularity, scope
3. **Write skills** - Follow standard structure
4. **Create commands** - For common operations
5. **Update metadata** - plugin.json, README.md
6. **Test** - Verify skills load and commands work

## Conventions

- Skill names: lowercase-hyphenated (`bun-development`)
- Command names: lowercase with colons for nesting (`bun:install`)
- Plugin names: suffix with `-plugin` (`typescript-plugin`)
- Use tables for quick reference (flags, options)
- Include both short and long flag forms where applicable

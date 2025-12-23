# Command Naming Conventions

## Namespace Structure

Commands use a hierarchical namespace based on the plugin they belong to:

```
/plugin-name:command-name
```

**Examples:**
- `/blueprint:init` - Blueprint plugin, init command
- `/git:commit` - Git plugin, commit command
- `/test:run` - Testing plugin, run command

## File Naming

Command files are named to match their invocation path:

| Command | Filename |
|---------|----------|
| `/blueprint:init` | `blueprint-init.md` |
| `/blueprint:prp-create` | `blueprint-prp-create.md` |
| `/git:commit` | `git-commit.md` |

The pattern is: `{namespace}-{command}.md`

## Sub-namespacing

For related command groups within a plugin, use hyphenated suffixes:

| Pattern | Example Commands |
|---------|-----------------|
| Core commands | `/blueprint:init`, `/blueprint:status` |
| PRD/ADR/PRP workflow | `/blueprint:prd`, `/blueprint:adr`, `/blueprint:prp-create` |
| Sub-features | `/blueprint:prp-create`, `/blueprint:prp-execute` |

## Consistency Rules

1. **All commands in a plugin use the same namespace prefix**
   - Correct: `/blueprint:prp-create`, `/blueprint:prp-execute`
   - Wrong: `/prp:create`, `/prp:execute` (separate namespace for related feature)

2. **Related commands share a common prefix within the namespace**
   - `/blueprint:prp-create`, `/blueprint:prp-execute` (PRP workflow)
   - `/blueprint:generate-skills`, `/blueprint:generate-commands` (generation commands)

3. **Command names are kebab-case**
   - Correct: `/blueprint:prp-create`, `/blueprint:work-order`
   - Wrong: `/blueprint:prpCreate`, `/blueprint:work_order`

4. **Filenames match command paths exactly**
   - Command `/blueprint:prp-create` → File `blueprint-prp-create.md`

## When to Use Sub-namespacing

Use hyphenated sub-namespacing when:
- Commands are part of a distinct workflow (e.g., PRP workflow)
- Commands operate on the same resource type (e.g., generate-*)
- Commands have a clear relationship (e.g., create/execute pairs)

Keep commands flat (no sub-prefix) when:
- They are standalone operations
- They are the primary command for a concept (e.g., `/blueprint:prd` not `/blueprint:prd-create`)

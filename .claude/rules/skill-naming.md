---
created: 2025-12-23
modified: 2026-02-06
reviewed: 2026-02-06
---

# Skill Naming Conventions

## Namespace Structure

Skills use a hierarchical namespace based on the plugin they belong to:

```
/plugin-name:skill-name
```

**Examples:**
- `/blueprint:init` - Blueprint plugin, init skill
- `/git:commit` - Git plugin, commit skill
- `/test:run` - Testing plugin, run skill

## Directory Naming

Skill directories are named to match their invocation path:

| Skill | Directory |
|-------|-----------|
| `/blueprint:init` | `skills/blueprint-init/SKILL.md` |
| `/blueprint:prp-create` | `skills/blueprint-prp-create/SKILL.md` |
| `/git:commit` | `skills/git-commit/SKILL.md` |

The pattern is: `skills/{namespace}-{name}/SKILL.md`

## Sub-namespacing

For related skill groups within a plugin, use hyphenated suffixes:

| Pattern | Example Skills |
|---------|---------------|
| Core skills | `/blueprint:init`, `/blueprint:status` |
| PRD/ADR/PRP workflow | `/blueprint:prd`, `/blueprint:adr`, `/blueprint:prp-create` |
| Sub-features | `/blueprint:prp-create`, `/blueprint:prp-execute` |

## Consistency Rules

1. **All skills in a plugin use the same namespace prefix**
   - `/blueprint:prp-create`, `/blueprint:prp-execute`

2. **Related skills share a common prefix within the namespace**
   - `/blueprint:prp-create`, `/blueprint:prp-execute` (PRP workflow)
   - `/blueprint:generate-skills`, `/blueprint:generate-rules` (generation skills)

3. **Skill names are kebab-case**
   - `/blueprint:prp-create`, `/blueprint:work-order`

4. **Directory names match skill paths exactly**
   - Skill `/blueprint:prp-create` → Directory `skills/blueprint-prp-create/SKILL.md`

## When to Use Sub-namespacing

Use hyphenated sub-namespacing when:
- Skills are part of a distinct workflow (e.g., PRP workflow)
- Skills operate on the same resource type (e.g., generate-*)
- Skills have a clear relationship (e.g., create/execute pairs)

Keep skills flat (no sub-prefix) when:
- They are standalone operations
- They are the primary skill for a concept (e.g., `/blueprint:prd` not `/blueprint:prd-create`)

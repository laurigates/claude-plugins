# ADR-0005: Source skill prompts from the existing obsidian-plugin

- Status: Accepted
- Date: 2026-04-17

## Context

We need SKILL.md files for the four maintenance subagents (vault-lint, vault-links, vault-stubs, vault-mocs). Options:

1. Create a new sibling plugin (`vault-plugin`) alongside `obsidian-plugin`, `git-plugin`, etc.
2. Embed the skill files inside `vault-agent/` itself.
3. Add the new skills to the existing `obsidian-plugin`.

## Decision

Option 3: add the seven new SKILL.md files (`vault-frontmatter`, `vault-tags`, `vault-wikilinks`, `vault-orphans`, `vault-stubs`, `vault-mocs`, `vault-templates`) to `obsidian-plugin/skills/`.

The `vault-agent` prompt compiler (`prompts/compiler.py`) maps each subagent to a list of SKILL.md paths relative to the plugins root:

```python
SUBAGENT_SKILLS = {
    "vault-lint": [
        "obsidian-plugin/skills/vault-frontmatter/SKILL.md",
        "obsidian-plugin/skills/vault-tags/SKILL.md",
        "obsidian-plugin/skills/vault-templates/SKILL.md",
    ],
    ...
}
```

## Consequences

- One plugin per domain (`obsidian-plugin` is the Obsidian-domain plugin).
- Skills are usable in direct Claude Code sessions (without the vault-agent CLI) because they live in a properly-structured plugin.
- The compiler's `KEEP_HEADINGS` / `DROP_HEADINGS` strips Claude Code metadata (`When to Use`, `Related Skills`, `Prerequisites`) from the SKILL.md files before embedding in subagent system prompts, so the agent sees only domain knowledge.
- Complementary to the existing operational skills (`vault-files`, `properties`, `search-discovery`, `tasks`, `plugins-themes`, `publish-sync`) that use the Obsidian CLI and require a running Obsidian instance. The new skills operate offline on markdown files.

## Related

- git-repo-agent's compiler sources from sibling plugins (`configure-plugin`, `code-quality-plugin`, etc.) in the same monorepo — same pattern.

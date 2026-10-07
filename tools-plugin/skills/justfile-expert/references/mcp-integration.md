# Justfile Expert — MCP Integration (just-mcp)

For [SKILL.md](../SKILL.md).

## MCP Integration (just-mcp)

The `just-mcp` MCP server enables AI assistants to discover and execute justfile recipes through the Model Context Protocol, reducing context waste since the AI doesn't need to read the full justfile.

**Installation:**
```bash
# Via npm
npx just-mcp --stdio

# Via pip/uvx
uvx just-mcp --stdio

# Via cargo
cargo install just-mcp
```

**Claude Desktop configuration (`.claude/mcp.json`):**
```json
{
  "mcpServers": {
    "just-mcp": {
      "command": "npx",
      "args": ["-y", "just-mcp", "--stdio"]
    }
  }
}
```

**Available MCP Tools:**
- `list_recipes` - Discover all recipes and parameters
- `run_recipe` - Execute a recipe with arguments
- `get_recipe_info` - Get detailed recipe documentation
- `validate_justfile` - Check for syntax errors

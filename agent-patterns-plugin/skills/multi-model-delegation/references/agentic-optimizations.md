# Multi-Model Delegation — Agentic Optimizations

Moved verbatim from [SKILL.md](../SKILL.md). Open when choosing which PAL tool call
fits the current step of a consult.

## Agentic Optimizations

| Context | Command |
|---|---|
| Resolve registry IDs and aliases | `mcp__pal-mcp-server__listmodels` |
| Independent round-one draw (repeat per model, same prompt) | `mcp__pal-mcp-server__chat` with `model` + `absolute_file_paths`; omit `temperature` for kimi |
| Attachment set exceeds the smallest model's budget | One `<repo>/tmp/<consult>/context-excerpts.md` bundle, attached to every model |
| Structured multi-model verdict with per-model stances | `mcp__pal-mcp-server__consensus` |
| Deep single-model dig after the split is found | `mcp__pal-mcp-server__thinkdeep` |

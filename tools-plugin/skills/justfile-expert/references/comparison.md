# Justfile Expert — Comparison with Alternatives

For [SKILL.md](../SKILL.md).

## Comparison with Alternatives

| Feature | Just | Make | mise tasks |
|---------|------|------|------------|
| Syntax | Simple, clear | Complex, tabs required | YAML |
| Dependencies | Built-in | Built-in | Manual |
| Parameters | Full support | Limited | Full support |
| Cross-platform | Excellent | Good | Excellent |
| Tool versions | No | No | Yes |
| Error messages | Clear | Cryptic | Clear |
| Installation | Single binary | Pre-installed | Requires mise |

**When to use Just:**
- Cross-project standard recipes
- Simple, readable task automation
- No tool version management needed

**When to use mise tasks:**
- Project-specific with tool version pinning
- Already using mise for tool management

**When to use Make:**
- Legacy projects with existing Makefiles
- Build systems requiring incremental compilation

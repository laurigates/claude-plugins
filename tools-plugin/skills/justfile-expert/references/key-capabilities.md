# Justfile Expert — Key Capabilities

Parameter forms, settings, recipe attributes, and the module system, for [SKILL.md](../SKILL.md). Complete syntax reference: [REFERENCE.md](../REFERENCE.md).

## Key Capabilities

**Recipe Parameters**
- **Required parameters**: `recipe param:` - must be provided
- **Default values**: `recipe param="default":` - optional with fallback
- **Variadic `+`**: `recipe +FILES:` - one or more arguments
- **Variadic `*`**: `recipe *FLAGS:` - zero or more arguments
- **Environment export**: `recipe $VAR:` - parameter as env var

**Settings Configuration**
- **`set dotenv-load`**: Load `.env` file automatically
- **`set positional-arguments`**: Enable `$1`, `$2` syntax
- **`set export`**: Export all variables as env vars
- **`set shell`**: Custom shell interpreter
- **`set quiet`**: Suppress command echoing

**Recipe Attributes**
- **`[doc("text")]`**: The `--list` description. Overrides the comment above the
  recipe; bare **`[doc]`** suppresses it. See "What `--list` Shows" in [SKILL.md](../SKILL.md) —
  without this attribute only the comment block's LAST line is used
- **`[private]`**: Hide from `--list` and `--summary` output
- **`[no-cd]`**: Don't change directory
- **`[no-exit-message]`**: Suppress exit messages
- **`[unix]`** / **`[windows]`** / **`[linux]`** / **`[macos]`**: Platform-specific recipes
- **`[positional-arguments]`**: Per-recipe positional args
- **`[confirm]`** / **`[confirm("message")]`**: Require confirmation before running
- **`[group: "name"]`** / **`[group("name")]`**: Section recipes in `--list`; both
  spellings work, and `--groups` lists the group names
- **`[working-directory: "path"]`**: Run in specific directory

**Module System**
- **`mod name`**: Declare submodule
- **`mod name 'path'`**: Custom module path
- **Invocation**: `just module::recipe` or `just module recipe`
- **`set fallback` is NOT inherited by a module.** The parent may fall through to
  *its* parent, but `just sub::parent-recipe` fails with `justfile does not
  contain recipe`. A module's recipes resolve only within that module

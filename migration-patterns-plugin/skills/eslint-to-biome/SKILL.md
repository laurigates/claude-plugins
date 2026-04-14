---
name: eslint-to-biome
description: |
  Migrate a JavaScript/TypeScript project from ESLint to Biome. Use when
  .eslintrc* or eslint.config.* exists and no biome.json is present. Replaces
  ESLint and Prettier configs/hooks with Biome, preserving rule equivalents.
  Biome is a fast, zero-config-needed Rust linter+formatter that replaces both.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(find *), Bash(test *), Bash(npx *), Bash(bun *), AskUserQuestion, TodoWrite
args: "[--check-only] [--fix]"
argument-hint: "[--check-only] [--fix]"
created: 2026-04-14
modified: 2026-04-14
reviewed: 2026-04-14
---

# /migration-patterns:eslint-to-biome

Migrate from [ESLint](https://eslint.org/) (and optionally [Prettier](https://prettier.io/)) to [Biome](https://biomejs.dev/) — a fast, unified linter and formatter for JavaScript/TypeScript written in Rust. Migrates configuration, updates pre-commit hooks, and removes old dependencies.

## When to Use This Skill

| Use this skill when... | Keep ESLint when... |
|------------------------|---------------------|
| `biome.json` does not exist yet | You rely on an ESLint plugin with no Biome equivalent (e.g., `eslint-plugin-react-hooks`, `eslint-plugin-jsx-a11y`) |
| `.eslintrc*` or `eslint.config.*` exists | CI requires ESLint's exit codes specifically |
| You also want to replace Prettier with Biome formatter | Team has invested in custom ESLint rules |
| Using TypeScript and want a single tool | |

> **Important:** Biome covers ~90% of common ESLint rules but not all plugins. Audit `eslint-plugin-*` dependencies before migrating. The most common unsupported plugins are accessibility (jsx-a11y) and framework hooks (react-hooks). You may need to keep ESLint alongside Biome for these.

## Context

- ESLint configs: !`find . -maxdepth 2 \( -name '.eslintrc' -o -name '.eslintrc.js' -o -name '.eslintrc.cjs' -o -name '.eslintrc.json' -o -name '.eslintrc.yaml' -o -name '.eslintrc.yml' -o -name 'eslint.config.js' -o -name 'eslint.config.mjs' -o -name 'eslint.config.ts' \)`
- Prettier configs: !`find . -maxdepth 2 \( -name '.prettierrc' -o -name '.prettierrc.js' -o -name '.prettierrc.json' -o -name 'prettier.config.js' \)`
- Biome config: !`find . -maxdepth 2 -name 'biome.json'`
- package.json: !`find . -maxdepth 1 -name 'package.json'`
- Pre-commit config: !`find . -maxdepth 1 -name '.pre-commit-config.yaml'`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--check-only` | Report what would change without modifying files |
| `--fix` | Apply migration automatically |

## Execution

Execute this ESLint-to-Biome migration:

### Step 1: Audit current ESLint/Prettier configuration

1. Read all ESLint config files found in context.
2. Read Prettier config files if present.
3. Check package.json for `eslint*` and `prettier*` dependencies.
4. Report findings:
   ```
   ESLint → Biome migration audit
   ================================
   ESLint config:    .eslintrc.json (N rules, plugins: [...])
   Prettier config:  .prettierrc (printWidth=N, singleQuote=true)
   ESLint plugins:   eslint-plugin-import, @typescript-eslint, ...
   Biome support:    ✓ eslint-plugin-import → Biome handles this
                     ⚠ eslint-plugin-jsx-a11y → No Biome equivalent (keep ESLint for this)
   biome.json:       NOT PRESENT
   ```
   If `--check-only`, stop here.

### Step 2: Check plugin compatibility

For each `eslint-plugin-*` found, determine Biome coverage:

| ESLint plugin | Biome equivalent |
|---------------|-----------------|
| `@typescript-eslint` | Biome has TypeScript-aware rules (`nursery/use*`, `suspicious/`, `correctness/`) |
| `eslint-plugin-import` | Biome `correctness/noUndeclaredDependencies`, `correctness/noUnusedImports` |
| `eslint-plugin-unicorn` | Biome has partial coverage via `style/` rules |
| `eslint-plugin-jsx-a11y` | **Not covered by Biome** — keep ESLint for accessibility |
| `eslint-plugin-react-hooks` | **Not covered by Biome** — keep ESLint for hooks rules |
| `eslint-plugin-security` | Partial coverage in Biome `security/` rules |

If unsupported plugins are found, ask the user whether to proceed with a partial migration (keep ESLint only for those plugins). If the user declines, abort.

### Step 3: Create biome.json

Generate `biome.json` preserving equivalent rules from the existing ESLint and Prettier configurations:

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.0/schema.json",
  "organizeImports": {
    "enabled": true
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true
    }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 80
  },
  "javascript": {
    "formatter": {
      "quoteStyle": "double",
      "trailingCommas": "all",
      "semicolons": "always"
    }
  }
}
```

Adjust these defaults to match the Prettier config found in Step 1:
- `lineWidth` → from `printWidth`
- `quoteStyle` → from `singleQuote: true` → `"single"`
- `trailingCommas` → from `trailingComma: "es5"` → `"es5"`
- `semicolons` → from `semi: false` → `"asNeeded"`
- `indentStyle` → from `useTabs: true` → `"tab"`

### Step 4: Update package.json

1. Remove ESLint and Prettier dev dependencies (if doing full migration):
   ```
   "devDependencies": {
     remove: eslint, @typescript-eslint/parser, @typescript-eslint/eslint-plugin,
             eslint-plugin-import, prettier, eslint-config-prettier, eslint-plugin-prettier
     keep: eslint-plugin-jsx-a11y, eslint-plugin-react-hooks (if partial migration)
   }
   ```
2. Add Biome:
   ```json
   "@biomejs/biome": "^1.9.0"
   ```
3. Update scripts in package.json:
   ```json
   {
     "scripts": {
       "lint": "biome check .",
       "lint:fix": "biome check --write .",
       "format": "biome format --write ."
     }
   }
   ```

### Step 5: Update .pre-commit-config.yaml (if present)

Remove any ESLint/Prettier pre-commit hooks. Add Biome:

```yaml
- repo: https://github.com/biomejs/pre-commit
  rev: v0.6.0  # use latest
  hooks:
    - id: biome-check
      additional_dependencies: ["@biomejs/biome@1.9.0"]
```

### Step 6: Delete old config files

Remove ESLint and Prettier config files (unless keeping ESLint for unsupported plugins — in that case, keep `.eslintrc` but note Biome replaces most rules):
- `.eslintrc*` → delete (if full migration)
- `eslint.config.*` → delete (if full migration)
- `.prettierrc*` → delete
- `.eslintignore` → convert relevant patterns to `biome.json` `ignore` section

### Step 7: Verify migration

Run Biome to confirm it works:

```bash
npx @biomejs/biome check .
# or with bun:
bunx @biomejs/biome check .
```

Address any errors that weren't caught by ESLint (Biome may surface additional issues). Errors on first run are expected — fix them or add to `biome.json` ignore rules.

### Step 8: Report

Print a summary:

```
ESLint → Biome migration complete
===================================
biome.json                CREATED
package.json              UPDATED (added @biomejs/biome, removed eslint/prettier)
.eslintrc.json            DELETED / KEPT (partial migration)
.prettierrc               DELETED
.pre-commit-config.yaml   UPDATED (added biome-check hook)

Partial migration note (if applicable):
  Kept eslint-plugin-jsx-a11y and eslint-plugin-react-hooks — these plugins
  have no Biome equivalent. ESLint is still needed for these rules.

Files to stage:
  git add biome.json package.json .pre-commit-config.yaml
  git add <deleted config files>
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Audit only | `/migration-patterns:eslint-to-biome --check-only` |
| Apply migration | `/migration-patterns:eslint-to-biome --fix` |
| Check with Biome | `npx @biomejs/biome check .` |
| Format with Biome | `npx @biomejs/biome format --write .` |

## Quick Reference

| Item | Value |
|------|-------|
| Biome docs | https://biomejs.dev/ |
| ESLint migration guide | https://biomejs.dev/guides/migrate-eslint-prettier/ |
| Config schema | `https://biomejs.dev/schemas/1.9.0/schema.json` |
| Pre-commit hook | `biomejs/pre-commit` |

## See Also

- `/migration-patterns:black-to-ruff-format` — Python formatter migration (analogous pattern)
- `/configure:repo` — End-to-end repo config driver

# Settings Configuration Reference

Supporting material for the `settings-configuration` skill: starter permission sets and a project setup walkthrough. The rule syntax, precedence and modes are in [SKILL.md](SKILL.md).

## Starter Permission Sets

Each set lists narrow rules, one per command family. Built-in read-only commands (`ls`, `cat`, `grep`, `find`, `wc`, `diff`, read-only forms of `git`, …) already run without a prompt, so they need no allow rule.

### Git writes

```json
{
  "permissions": {
    "allow": [
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git switch *)",
      "Bash(git fetch *)",
      "Bash(git pull *)"
    ],
    "ask": [
      "Bash(git push *)"
    ]
  }
}
```

The `ask` rule keeps every push behind a prompt, including a push chained after an allowed command (`git commit -m x && git push`), because an ask rule fires when any subcommand matches.

### GitHub CLI

Name the verbs, so a rule meant for reading PRs does not also approve `gh pr merge`:

```json
{
  "permissions": {
    "allow": [
      "Bash(gh pr view *)",
      "Bash(gh pr list *)",
      "Bash(gh pr checks *)",
      "Bash(gh run view *)",
      "Bash(gh run list *)",
      "Bash(gh issue view *)",
      "Bash(gh issue list *)"
    ]
  }
}
```

### Tests and linters

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run test *)",
      "Bash(npm run lint *)",
      "Bash(bun test *)",
      "Bash(biome check *)",
      "Bash(pre-commit run *)"
    ]
  }
}
```

Name the script after `npm run`: `Bash(npm run *)` approves any script the repository defines, and auto mode drops package-manager run rules on entry.

### Secrets

```json
{
  "permissions": {
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)",
      "Read(~/.aws/**)"
    ]
  }
}
```

A `Read` deny also blocks Edit and Write on the same path. It covers Claude's file tools and the file commands Claude Code recognizes in Bash (`cat`, `head`, `tail`, `sed`, `tee`), not a script that opens the file itself; use the sandbox for an OS-level block.

### MCP servers

```json
{
  "permissions": {
    "allow": [
      "mcp__context7__*",
      "mcp__github__get_issue"
    ],
    "deny": [
      "mcp__github__merge_pull_request"
    ]
  }
}
```

A server configured as `my.server` appears as `mcp__my_server__*`. A plugin-provided server takes the form `mcp__plugin_<plugin>_<server>__*`.

## Tool-name Forms

- For an MCP server whose name contains `__` or ends in `_`, write `mcp__<whole name>__*`; the bare and shortened forms are read as rules for a different server.
- A `Tool(param:value)` rule naming a primary field, such as `Bash(command:rm *)`, is ignored with a startup warning; write `Bash(rm *)`.
- Tool-name globs (`"*"`, `"mcp__*"`) work in deny and ask rules. An allow glob works only after a literal `mcp__<server>__` prefix (`mcp__github__get_*`); `"*"` or `"mcp__*"` in allow approves nothing.
- A deny or ask rule naming no known tool produces a startup warning, which catches typos.

## Project Setup

1. Create `.claude/settings.json` with the Write tool, starting from one of the starter sets. Add `"$schema": "https://json.schemastore.org/claude-code-settings.json"` for editor validation.
2. Validate it: `jq . .claude/settings.json` (exit 0 means valid JSON).
3. Commit `.claude/settings.json`. Teammates' sessions apply its `allow` rules after they accept the workspace trust dialog; its `deny` and `ask` rules apply at once.
4. Put personal overrides in `.claude/settings.local.json`. If you create that file by hand, confirm it is ignored: `git check-ignore -v .claude/settings.local.json`. A tracked local file is treated as repository-supplied and waits for trust.
5. Start a session and run `/status`: the Setting sources line lists each file that loaded. `/permissions` shows each rule with its source file.

## Path Patterns

| Pattern | Anchors at | Example |
|---------|-----------|---------|
| `//path` | filesystem root | `Read(//Users/alice/secrets/**)` |
| `~/path` | home directory | `Read(~/.zshrc)` |
| `/path` | the settings source: the primary working directory for project and local files, `~/.claude` for user settings, the file's directory for `--settings <file>` | `Edit(/src/**/*.ts)` |
| `path`, `./path` | current directory | `Read(*.env)` |

A bare filename matches at any depth under its anchor, so `Read(.env)` equals `Read(**/.env)`.

For a tree with `src/app.ts` and `vendor/pkg/src/lib.js`:

| Rule | `src/app.ts` | `vendor/pkg/src/lib.js` |
|------|--------------|-------------------------|
| allow `Edit(src/**)` | matches | no match |
| deny `Read(src/**)` | matches | matches |
| `Edit(/src/**)` (project settings) | matches | no match |
| `Edit(**/src/**)` | matches | matches |

In user settings, `/path` anchors at `~/.claude`, so `Read(/secrets/**)` there blocks `~/.claude/secrets/**`, not a project directory. Use `//` or `~/` for a user-level rule meant for every project.

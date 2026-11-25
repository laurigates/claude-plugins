# Gotchas — Traps Met Running `/configure:all --fix`

Each entry names the symptom, the cause and the fix. All were met in one run on
a Node bridge-server repo.

| Symptom | Cause | Fix |
|---------|-------|-----|
| A context line prints `[output of command ...]` and asks to be run first | The harness does not auto-approve `find ... -exec` (`.claude/rules/agentic-permissions.md`), so the `!` command is deferred | Use `find ... -name`, `grep -s` or a script instead of `-exec` in `## Context` lines |
| `gitleaks` blocks a docs commit | Its `curl-auth-header` rule matches an API-key header placeholder in a docs `curl` example | Add a `.gitleaks.toml` with `[extend] useDefault = true` and an `[allowlist] regexes` entry for the placeholder string; do not allowlist the file path |
| `biome` rewrites `README.md` and `CLAUDE.md` tables and `.claude/settings.json` | Biome 2.6 formats Markdown and JSON by default (`.claude/rules/biome-markdown.md`) | Scope `files.includes` to the JS globs (`*.js`, `scripts/**/*.js`, ...), exclude `node_modules` and `coverage`; keep `linter` and `assist` off when ESLint stays the linter |
| Formatter or Jest touches 40 extra files | `.claude/worktrees/<agent>/` holds full checkouts | Add `.claude/worktrees` to `.gitignore` before running the formatter; set `!.claude/worktrees` in Biome and add `<rootDir>/.claude/` to Jest's ignore list |
| Phantom failing suites after a CLI `--testPathIgnorePatterns` | A CLI value replaces the config's list, so the bridge tests ran under the root config | Repeat every ignore: `--testPathIgnorePatterns '/node_modules/' '<rootDir>/bridge-server/' '<rootDir>/.claude/'` |
| `docs/architecture.md` and `docs/ARCHITECTURE.md` collide | macOS is case-insensitive | Check `ls docs` before creating a page; pick a distinct name (`overview.md`) |
| README quick start uses a variable the server ignores | Names written from memory | Read them from source (`rg 'process\.env' bridge-server`) and cite the file in the docs |
| Pinned action does not resolve | The tag is annotated, so the ref SHA is the tag object | `gh api repos/<o>/<r>/git/tags/<sha> --jq .object.sha` for the commit |
| `enabledMcpjsonServers` names servers the repo cannot start | No `.mcp.json` in the repo; a parent directory supplied them | Add a repo `.mcp.json` with env-var references only, or trim the list to servers that resolve |
| Claude workflows duplicate org CI logic | The inline templates predate the org's shared reusable workflows | Call `reusable-claude.yml` and `reusable-claude-review.yml` from the org's workflows repo (`/configure:reusable-workflows` names it); the callers grant the permissions the reusable job needs |
| `git push origin $new:refs/heads/x` fails with `...efs/heads/x` | zsh read `$new:r` as a history modifier | Brace the variable (`${new}:refs/...`) or use literal SHAs |
| Merge method unclear | Rebase vs squash is not a preference | `pr-merge-method.py --pr <n>` decides (independent commits rebase, single commit squashes) |
| `npm audit` job never fails | `continue-on-error: true` | Use the org `reusable-security-deps.yml` in report-only mode until the advisories are cleared, then block on high severity |
| `engines` and Dockerfile target an end-of-life Node | Templates keep old versions | Check `https://endoflife.date/api/nodejs.json` before choosing, and align CI, `mise.toml` and the image |
| An agent reports a file "does not exist" | Its worktree was cut from `origin/main` | See [fix-phase.md](fix-phase.md#6-parallel-agents): wrong base, not a finding |

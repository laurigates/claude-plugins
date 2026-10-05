# `.worktreeinclude` Scope and Caveats

Read in Step 2 (classifying entries) and Step 5 (verifying), or when a copied file is missing from a new worktree.

## When it is processed

| Worktree created by… | `.worktreeinclude` applied? |
|----------------------|-----------------------------|
| `claude --worktree <name>` / `-w`, incl. `--worktree "#<pr>"` | Yes |
| `EnterWorktree` (Claude asked to "work in a worktree") | Yes — same git creation path |
| Subagent `isolation: worktree` / `Agent(isolation: "worktree")`, background sessions | Yes |
| Desktop app parallel sessions (worktree option) | Yes |
| `--worktree <name>` whose directory already exists | No — the existing worktree is reopened, not created |
| Manual `git worktree add` | No — Claude Code did not create it |
| A `WorktreeCreate` hook (any VCS, incl. git) | No — copy the files inside the hook script |

Files are copied once, at creation. Later edits to `.env` in the main checkout
do not propagate to existing worktrees.

## `**/` patterns and wholly-ignored directories (2.1.239+)

When the target files sit inside a directory that is gitignored **as a whole**,
a pattern starting with `**/` reaches them only if that directory itself
matches the pattern, or the first name after `**/` appears in the directory's
path. `**/.claude/skills/*.md` reaches into an ignored `.claude/`;
`**/config.json` does **not** reach into an ignored `vendor/`. Name the
directory instead: `vendor/**/config.json`. Before 2.1.239 a `**/` pattern
reached into an ignored directory only when the directory itself matched.

## What not to include

- **`.claude/skills`, `.claude/agents`, `.claude/commands`** when gitignored —
  a worktree without its own copy reads the main checkout's through
  (skills 2.1.277+), so copying them adds a stale snapshot instead.
- **Project-scope plugins and "don't ask again" approvals** — already shared
  with the main checkout (plugins 2.1.200+, approvals 2.1.211+).
- **Git LFS content** — LFS filters from `git lfs install --local` are skipped
  at creation; run `git lfs pull` in the worktree rather than listing LFS files.
- **`.claude/worktrees/`** itself — it belongs in `.gitignore`
  (`/configure:gitignore`), never in the include list.

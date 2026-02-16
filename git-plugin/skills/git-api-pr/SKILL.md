---
model: haiku
name: git-api-pr
description: Create PRs via GitHub API without local git operations. Use when you want to submit file changes as a PR without committing locally — for quick fixes, typos, config updates, or when you want a clean workflow that bypasses local git state entirely.
args: <file...> --title <title> [--base <branch>] [--branch <name>] [--body <text>] [--draft] [--delete]
allowed-tools: Bash(gh api *), Bash(gh pr *), Bash(gh repo *), Bash(base64 *), Bash(git remote *), Bash(mktemp *), Read, TodoWrite
argument-hint: <files...> --title "type(scope): description"
created: 2026-02-15
modified: 2026-02-16
reviewed: 2026-02-15
---

## When to Use This Skill

| Use this skill when... | Use `/git:commit` instead when... |
|------------------------|-----------------------------------|
| Quick fix to 1-3 files (typos, config, docs) | Complex multi-file refactoring |
| Want a clean workflow without local commits | Need local testing before submitting |
| Submitting changes without touching git state | Need pre-commit hooks to run |
| Want to avoid branch creation/switching locally | Need to stage partial file changes |
| File edits are already done, just need the PR | Need interactive staging (`git add -p`) |

## Context

- Repo: !`gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null`
- Default branch: !`gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null`
- Auth: !`gh auth status 2>/dev/null`
- Working dir: !`pwd`

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `$@` (positional) | Yes | One or more file paths to create/update in the repo |
| `--title <text>` | Yes | PR title — use conventional commit format |
| `--base <branch>` | No | Base branch (default: repo default branch from context) |
| `--branch <name>` | No | New branch name (auto-generated from title if omitted) |
| `--body <text>` | No | PR body/description |
| `--draft` | No | Create as draft PR |
| `--delete` | No | Delete the specified files instead of updating them |

## Execution

Execute this server-side PR creation workflow:

### Step 1: Validate inputs

1. Parse file paths and flags from `$ARGUMENTS`
2. Verify `--title` is provided — error if missing
3. For each file path (unless `--delete`):
   - Verify the local file exists using Read tool
   - Resolve to a repo-relative path (strip leading `./` or working directory prefix)
4. Determine the repo from context (`$REPO`)
5. Determine base branch: use `--base` if provided, otherwise use default branch from context

### Step 2: Resolve base branch state

```bash
# Get base branch SHA
BASE_SHA=$(gh api repos/$REPO/git/ref/heads/$BASE_BRANCH -q .object.sha)

# Get base tree SHA
BASE_TREE=$(gh api repos/$REPO/git/commits/$BASE_SHA -q .tree.sha)
```

If this fails, the base branch doesn't exist — report error and list available branches.

### Step 3: Generate branch name (if --branch not provided)

Derive from the `--title`:
1. Take the subject part (after `type(scope): `)
2. Convert to kebab-case
3. Prefix with the commit type (e.g., `fix/kebab-subject`)
4. Example: `"fix(api): handle null response"` → `fix/handle-null-response`

### Step 4: Create blobs for each file

For each file path:

```bash
# Base64-encode the file content and create a blob
BLOB_SHA=$(gh api repos/$REPO/git/blobs \
  -f content="$(base64 < "$FILE_PATH" | tr -d '\n')" \
  -f encoding=base64 \
  -q .sha)
```

Track each `{path, blob_sha}` pair for the tree creation in Step 5.

For `--delete` files, skip blob creation — these are handled differently in the tree.

### Step 5: Create tree with all file changes

Build a tree JSON payload and create the tree:

```bash
# Write tree entries to a temp file
TREE_FILE=$(mktemp)
```

For each file to **update/create**, add a tree entry:
```json
{"path": "relative/path/to/file", "mode": "100644", "type": "blob", "sha": "<blob_sha>"}
```

For each file to **delete**, add a tree entry:
```json
{"path": "relative/path/to/file", "mode": "100644", "type": "blob", "sha": null}
```

Create the tree:
```bash
TREE_SHA=$(gh api repos/$REPO/git/trees \
  -f base_tree="$BASE_TREE" \
  --input "$TREE_FILE" \
  -q .sha)
```

Note: The `--input` file must contain the full JSON body with a `tree` array. Example:
```json
{
  "base_tree": "<BASE_TREE>",
  "tree": [
    {"path": "src/config.ts", "mode": "100644", "type": "blob", "sha": "<blob1>"},
    {"path": "README.md", "mode": "100644", "type": "blob", "sha": "<blob2>"}
  ]
}
```

### Step 6: Create commit

```bash
COMMIT_SHA=$(gh api repos/$REPO/git/commits \
  -f message="$TITLE" \
  -f tree="$TREE_SHA" \
  -f "parents[]=$BASE_SHA" \
  -q .sha)
```

### Step 7: Create branch ref

```bash
gh api repos/$REPO/git/refs \
  -f ref="refs/heads/$BRANCH" \
  -f sha="$COMMIT_SHA"
```

If this fails with "Reference already exists", report the error and suggest using a different branch name.

### Step 8: Create PR

```bash
gh pr create \
  --repo "$REPO" \
  --head "$BRANCH" \
  --base "$BASE_BRANCH" \
  --title "$TITLE" \
  --body "${BODY:-"Created via API — no local git operations."}"
```

Add `--draft` if the flag was provided.

### Step 9: Report results

Print a summary:

```
PR created successfully (no local git changes):
  PR:     <url>
  Branch: <branch> → <base>
  Files:  <count> file(s) changed
  Commit: <sha>
```

### Cleanup

Remove any temp files created during execution.

## Error Recovery

| Error | Recovery |
|-------|----------|
| `gh auth status` fails | "Run `gh auth login` first" |
| Base branch SHA lookup fails | List branches: `gh api repos/$REPO/branches --jq '.[].name'` |
| Blob creation fails | Report which file failed and the API error |
| Branch already exists | Suggest `--branch <different-name>` |
| Tree creation fails | Check if file paths are valid repo-relative paths |
| PR creation fails | Show the API error — common cause is branch protection |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Single file fix | `/git:api-pr file.ts --title "fix: typo"` |
| Multi-file fix | `/git:api-pr a.ts b.ts --title "fix: update configs"` |
| Draft PR | `/git:api-pr file.ts --title "feat: wip" --draft` |
| Custom branch | `/git:api-pr file.ts --title "fix: desc" --branch hotfix/issue-123` |
| Delete file | `/git:api-pr old-file.ts --title "chore: remove deprecated" --delete` |
| Non-default base | `/git:api-pr file.ts --title "fix: desc" --base develop` |

## See Also

- **/git:commit** — full local commit→push→PR workflow (use when you need pre-commit hooks, testing, or complex staging)
- **gh-cli-agentic** — GitHub CLI patterns for JSON output and API access
- **git-branch-pr-workflow** — branch management and PR workflow patterns

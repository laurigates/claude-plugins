# git-issue - TDD, Commit and PR

The per-issue RED/GREEN/REFACTOR cycle, commit-and-push steps, and PR creation that follow the Standard Flow in Step 2.

## TDD Workflow

1. **RED phase**: Write failing tests first
   - Create test file if needed
   - Write tests that define expected behavior
   - Run tests to verify they fail

2. **GREEN phase**: Implement fix
   - Write minimal code to make tests pass
   - Run tests to verify they pass

3. **REFACTOR phase**: Improve code quality
   - Clean up implementation
   - Ensure tests still pass

## Commit and Push

1. **Stage changes**: `git add -u` and `git add <new-files>`
2. **Run pre-commit** if configured
3. **Commit on the issue branch** with message format:

```
<type>: <description>

<optional body explaining the change>

Fixes #N
```

4. **Verify the branch carries only this issue's commits**: `git log --oneline origin/main..HEAD`
5. **Push the issue branch**: `git push -u origin fix/issue-$N`

## Create PR

Use `mcp__github__create_pull_request` with:
- `head`: `fix/issue-$N`
- `base`: `main`
- `title`: From issue title with `fix:` prefix
- `body`: Include `Fixes #$N` to auto-link

After PR creation, apply labels:
```bash
gh pr edit <pr-number> --add-label "<labels>"
```

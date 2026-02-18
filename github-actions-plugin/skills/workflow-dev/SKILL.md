---
model: sonnet
created: 2025-12-16
modified: 2026-02-10
reviewed: 2025-12-16
allowed-tools: Read, Write, Edit, MultiEdit, Bash(git *), Bash(pytest *), Bash(npm test *), Bash(cargo test *), Bash(go test *), mcp__github__list_issues, mcp__github__create_issue, mcp__github__create_pull_request, mcp__github__get_issue, TodoWrite
argument-hint: [--max-cycles <n>] [--focus <bug|feature|test>]
description: Automated development loop with issue creation and TDD
name: workflow-dev
---

# /workflow:dev

Automated development loop with issue creation, TDD, and CI monitoring.

## Context

- Current branch: !`git branch --show-current 2>/dev/null`
- Working tree: !`git status --porcelain 2>/dev/null`
- Project type: !`find . -maxdepth 1 \( -name "package.json" -o -name "Cargo.toml" -o -name "pyproject.toml" -o -name "go.mod" -o -name "manage.py" \) -type f 2>/dev/null`
- Open issues: !`gh issue list --state open --limit 5 --json number,title --jq '.' 2>/dev/null`

## Parameters

Parse from `$ARGUMENTS`:

- `--max-cycles <n>`: Limit to N issue resolution cycles (default: unlimited)
- `--focus <bug|feature|test>`: Only work on issues with matching label
- `--quick-wins`: Only pick issues estimated < 30 minutes
- `--test-only`: Only create issues for test failures; skip implementation
- `--dry-run`: Explain what would be done without making changes

## Execution

Execute this automated development loop:

### Step 1: Set up environment and assess state

**1. Ensure on main branch and sync**

```bash
git switch main
git pull
```

**2. Run the project's test suite**

- Detect project type (check for `manage.py`, `package.json`, `Cargo.toml`, etc.)
- Run appropriate test command:
  - Django: `python manage.py test`
  - Node.js: `npm test`
  - Rust: `cargo test`
  - Python: `pytest` or `python -m pytest`
  - Go: `go test ./...`

**3. Create GitHub issues for any test failures**

- For each failing test, use `github:create_issue` with:
  - Title: `"Test failure: {test_name}"`
  - Body: Include error output, stack trace, and failure context
  - Labels: `["bug", "test-failure"]`

**4. List current repository issues**

- Use `github:list_issues` with `state=open`
- Filter out issues that are blocked or need external input

### Step 2: Select issue to work on

**Select issues using this priority order:**

1. **Critical bugs**: Issues labeled `priority: critical` or `bug` + `high priority`
2. **Test failures**: Issues just created from failing tests (highest priority)
3. **Quick wins**: Issues labeled `good first issue` or estimated < 1 hour
4. **High-impact features**: Issues with most reactions/comments
5. **Technical debt**: Oldest issues labeled `technical-debt` or `refactor`

**Selection criteria (must meet ALL):**

- Has clear acceptance criteria in description
- Not labeled `blocked` or `waiting-for-input`
- Not already assigned to someone else
- Can reasonably be completed in a single PR

**If no suitable issues found:**

- Run dependency audit (`npm audit`, `pip-audit`, `cargo audit`)
- Create issues for security vulnerabilities
- Run linting tools and create issues for violations

### Step 3: Implement solution

**For the selected issue, repeat until CI passes:**

**5. Create feature branch**

```bash
git switch -c fix/issue-{number}-{brief-description}
```

**6. Gather implementation context**

- **ALWAYS use Context7 MCP** to fetch current documentation for relevant libraries/frameworks before implementation
- Use `context7:resolve-library-id` followed by `context7:get-library-docs` for any tools mentioned
- Read issue description and any linked documentation
- Review related issues and PRs for context
- **For package managers (uv, npm, bun, etc.)**: Always fetch current best practices via Context7 before suggesting commands

**7. Implement solution using TDD**

- **RED**: Write a failing test (if test doesn't already exist)
- **GREEN**: Write minimal code to make the test pass
- **REFACTOR**: Improve code quality while keeping tests green
- Follow language-specific best practices from Claude Code Guidelines

**8. Commit changes**

```bash
git add <files>
git commit -m "fix: resolve issue #{number} - {brief description}"
```

- Use conventional commit format
- Reference issue number in commit message

**9. Push branch**

```bash
git push origin fix/issue-{number}-{brief-description}
```

**10. Create pull request**

- Use `github:create_pull_request` with:
  - Title: `"fix: resolve issue #{number} - {brief description}"`
  - Body: `"Fixes #{number}"` plus description of changes
  - Include testing notes and any breaking changes

**11. Monitor CI status**

- Use GitHub MCP to check workflow status
- Wait for all checks to start and complete

**12. Fix CI failures (if any)**

- Use `github:get_pull_request_status` to check specific failures
- Analyze workflow logs to understand failures
- Implement fixes and push additional commits
- Repeat until all checks pass

### Step 4: Complete and loop

**13. Verify CI success**

- Confirm all required checks are green
- Ensure no failing workflows remain

**14. Close the issue**

- Use `github:update_issue` to close with state `closed`
- Add comment referencing the closing PR

**15. Return to Step 1**

- Go back to environment setup
- Continue the loop for the next issue

## Configuration Options

Handle these command variations:

- `/workflow:dev` - Run continuous loop until stopped
- `/workflow:dev --max-cycles 3` - Limit to 3 issue resolution cycles
- `/workflow:dev --focus bug` - Only work on issues labeled "bug"
- `/workflow:dev --quick-wins` - Only pick issues estimated < 30 minutes
- `/workflow:dev --test-only` - Only create issues for test failures; implementation handled separately
- `/workflow:dev --dry-run` - Explain what would be done without making changes

## Error Handling

**Issue too complex to complete:**

- Add comment: `"This issue requires more detailed analysis - skipping for now"`
- Add label `needs-investigation`
- Skip to next issue in priority order

**Persistent CI failures (3+ attempts):**

- Create new issue titled `"CI Pipeline Issue: {workflow_name} failing"`
- Include workflow logs and error details
- Label as `ci-infrastructure`
- Skip current issue and continue with next

**No issues available:**

- Run automated maintenance tasks:
  - Dependency updates (`npm update`, `pip install --upgrade`, etc.)
  - Security audits and create issues for vulnerabilities
  - Code quality scans (linting) and create issues for violations
- If still no work, report completion and wait for new issues

**Git/GitHub API errors:**

- Retry operations up to 3 times
- If persistent, report error and pause loop
- Suggest manual intervention steps

## Success Reporting

After each completed issue, report:

```
✅ Issue #{number} resolved successfully!

Branch: fix/issue-{number}-{description}
PR: #{pr_number} - {pr_title}
CI Status: ✅ All checks passing
Time: {duration}

Continuing to next issue...
```

## Loop Termination

Stop the loop when:

- User interrupts the process
- `--max-cycles` limit reached
- No suitable issues remain after thorough search
- Critical error requires manual intervention

Provide final summary:

```
🏁 DevLoop completed!

📊 Summary:
- Issues resolved: {count}
- PRs created: {count}
- Tests added/fixed: {count}
- Total time: {duration}

📋 Recommendations:
- Review open PRs for merge
- Consider upgrading dependencies
- Add more test coverage for uncovered code
```

## Integration Notes

**Required tools:**

- GitHub MCP for all GitHub operations
- **Context7 MCP for documentation lookup (REQUIRED before any tool usage)**
- Git command line access
- Project-specific testing tools
- Modern package managers: uv (Python), npm/bun (JavaScript), cargo (Rust)

**Repository requirements:**

- Clean git working directory (or only intended changes)
- GitHub Actions or other CI configured
- Issue templates and labels configured
- Branch protection requiring PR reviews

**Best practices:**

- Always use GitHub MCP's context toolset for repository awareness
- Follow TDD principles strictly - no production code without tests
- Keep commits small and focused
- Use conventional commit messages
- Reference issues in all commits and PRs

# /workflow:dev - Reference

Command variations, error-handling policies, report templates, loop-termination criteria, and integration requirements.

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
- **Context7 MCP for documentation lookup when available** (fetch library/framework docs before implementation; fall back to `WebFetch` or the project's pinned docs when Context7 isn't in the session)
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

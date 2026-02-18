# feedback-plugin

Session feedback analysis - capture skill bugs, enhancements, and positive patterns as GitHub issues.

## Skills

| Skill | Description |
|-------|-------------|
| `/feedback:session` | Analyze session for skill feedback and create GitHub issues |

## Usage

```bash
# Analyze full session
/feedback:session

# Dry run - see findings without creating issues
/feedback:session --dry-run

# Only bugs
/feedback:session --bugs-only

# Only for a specific plugin
/feedback:session git-plugin

# Only positive feedback
/feedback:session --positive-only
```

## Labels

The plugin creates and uses these GitHub labels:

| Label | Color | Purpose |
|-------|-------|---------|
| `session-feedback` | Purple | Bugs and enhancements from session analysis |
| `positive-feedback` | Green | Skills that worked well (stability markers) |

## Issue Format

Issues are created with conventional title format:

```
feedback(<plugin-name>): <description>
```

This integrates with the project's conventional commit workflow.

## Workflow

1. Use skills during a session
2. At end of session, run `/feedback:session`
3. Review categorized findings
4. Select which to file as issues
5. Issues are created with appropriate labels and body
6. Use `/project:distill` to actually update the skills based on filed issues

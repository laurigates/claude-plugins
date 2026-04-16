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

# File feedback against the plugin source repo (not the cwd repo)
/feedback:session --target-repo laurigates/claude-plugins

# Short form
/feedback:session -R laurigates/claude-plugins
```

## Labels

The plugin creates and uses these GitHub labels:

| Label | Color | Purpose |
|-------|-------|---------|
| `session-feedback` | Purple | Bugs and enhancements from session analysis |
| `positive-feedback` | Green | Skills that worked well (stability markers) |

> **IaC-managed labels**: If your repository manages labels declaratively (Terraform, Pulumi, etc.), the skill detects this and offers to proceed without `session-feedback`/`positive-feedback` labels, or to target a different repo. Add the two labels to your IaC definition to restore full labeling. See the [Known Limitations](#known-limitations) section for details.

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

## Known Limitations

### IaC-managed labels

Some repositories manage GitHub labels declaratively using Terraform, Pulumi, CDK, or similar tools. Creating labels out-of-band with `gh label create` in these repos causes two problems:

1. **Drift**: The IaC tool destroys the manually-created label on the next apply.
2. **Policy**: Many org-level IaC setups explicitly forbid direct label creation.

The skill detects IaC label management by:
- Scanning existing label descriptions for keywords like `terraform`, `pulumi`, `managed by`, `iac`
- Looking for `labels.tf` or `labels.yaml` files in the working tree

When detected, the skill offers three options:
1. **Proceed without `session-feedback` labels** — issues are created with only `bug`/`enhancement` labels
2. **Use a different target repo** — file the issue against a repo where labels can be created freely
3. **Abort**

### Default target repo

By default, issues are filed against the repository in the current working directory. When giving feedback about a plugin skill itself (rather than the application code in the session), use `--target-repo <owner/repo>` to point at the plugin source repo (e.g. `laurigates/claude-plugins`).

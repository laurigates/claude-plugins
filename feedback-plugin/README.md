# feedback-plugin

Session feedback analysis — capture per-session skill bugs as GitHub issues, and learn recurring friction across a week of sessions via the `friction-learner` agent.

## Skills

| Skill | Description |
|-------|-------------|
| `/feedback:session` | Analyze session for skill feedback and create GitHub issues |

## Agents

| Agent | Description |
|-------|-------------|
| `friction-learner` | Parse last week of transcripts, cluster interruptions/hook-blocks/rejections, propose rule/skill/hook fixes, open one PR per target repo |

### Friction learner

Spawn via the Agent tool or wire to a weekly cron:

```
Agent({
  subagent_type: "friction-learner",
  prompt: "Analyze the last 7 days of sessions. Target repo: laurigates/claude-plugins. Open a PR with proposed rule edits.",
})
```

Dry-run the pipeline manually:

```bash
python3 feedback-plugin/scripts/friction_parse.py --since 7d --out /tmp/frictions.jsonl
python3 feedback-plugin/scripts/friction_cluster.py --in /tmp/frictions.jsonl --min-count 3 \
  --render-pr-body /tmp/pr-body.md --out /tmp/clusters.json
```

Signatures currently recognized: `plan:entered-plan-mode`, `push:branch-has-open-pr`, `hook:pr-metadata`, `hook:branch-protection`, `hook:conventional-commit`, `hook:gitleaks`, `hook:pre-commit`, `error:<tool>:<class>`, `reject:<tool>`, `interrupt:user`.

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

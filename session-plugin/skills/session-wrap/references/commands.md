# session-wrap — Command Forms

| Context | Command |
|---|---|
| Survey (detection + git + PRs + tasks-with-UUIDs + commits + GitHub-drift dedup) | `bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-commits --with-dedup` |
| Batch close by UUID | `task rc.confirmation:no <uuid> done` |
| Add a task | `task rc.confirmation:no add project:<name> +<tag> '<desc>'` |
| Known projects | `task _projects` |

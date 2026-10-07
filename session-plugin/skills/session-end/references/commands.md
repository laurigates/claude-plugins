# session-end — Command Forms

| Context | Command |
|---|---|
| One-pass survey (detection + git + PRs + tasks-with-UUIDs + commits + blueprint tracker state + GitHub-drift dedup) | `bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-commits --with-blueprint --with-dedup` |
| Trust the task count? | `TASK_SCOPE=` + `PROJECT_CONFIDENCE=` in the `TASKWARRIOR` section (`low` ⇒ re-run with `--project <slug>` before treating 0 as clean) |
| Which repo do the branch, dirt and PR rows describe? | `GIT_SCOPE=` + `GIT_CONFIDENCE=` in the `GIT` section (`PRS_SCOPE=` / `PRS_CONFIDENCE=` mirror them). `repo` ⇒ the checkout at `PROJECT_DIR`. `workspace-root` ⇒ an undeclared outer repo contains that checkout and the rows describe **it** — name `GIT_ROOT=` when reporting them, and say the cwd sits inside `GIT_NESTED_REPO=`. Never re-run from the workspace root: the collector already did |
| Distill qualify signal (recipe/hot-file/process counts) | `bash "${CLAUDE_SKILL_DIR}/../../scripts/distill-survey.sh" --session-id "${CLAUDE_SESSION_ID}" --summary` |
| Re-derive the drain wave before delegating | `task bpid.any: status:completed export \| jq …` intersected with tracker `tasks.pending` (Step 4.3) |
| Stable UUID for latest task | `task +LATEST uuids` |
| Mark task done by UUID | `task <uuid> done` |
| Distillable surface check | `find . -maxdepth 2 -path '*/.claude/rules' -o -maxdepth 1 -name 'justfile' -o -maxdepth 1 -name 'Justfile'` |

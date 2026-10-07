# comfy-node — Failure Modes and Guards

Symptom → cause → fix for the failures seen when standing up and adopting a new pack. Entry point: [`../SKILL.md`](../SKILL.md) § Failure modes & guards.

## Failure modes & guards

| Symptom | Cause | Fix |
|---------|-------|-----|
| `publish.yml` fails `Option '--token' requires an argument` | `comfy_registry` flag not yet applied | Confirm the tofu apply landed; `gh secret list` shows `REGISTRY_ACCESS_TOKEN`; re-run `gh workflow run publish.yml -R laurigates/<name>` |
| release-please job fails on empty `app-id` | `release_please` credentials not applied, or repo on the legacy PAT workflow | The scaffold ships the App-token `release-please.yml`; confirm the apply landed (`gh api repos/laurigates/<name>/actions/variables/RELEASE_PLEASE_APP_ID --jq .name` returns a name), re-run via `workflow_dispatch` |
| `403 Resource not accessible by integration` on repo create | Tried to create via the gitops App, not a personal token | Create with personal `gh auth`; the App only adopts via import |
| The tofu plan shows a *create* (not *import*) for the repo | Import block missing or `id` wrong | The `id` is the bare repo name, not `owner/name`; add/fix the import block |
| `just check` red in gitops | `tofu fmt`/`validate` failure | `just format` then re-check before pushing |

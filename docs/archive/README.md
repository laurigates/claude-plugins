# Archived planning docs

Completed or superseded planning documents kept for historical context. These
are **not living docs** — they describe work that has already landed (or plans
that were superseded) and are retained so the design rationale stays
discoverable without cluttering the active `docs/` tree.

Living docs (blueprint state, ADRs/PRDs/PRPs, usage guides, the plugin map)
stay under `docs/`. Only finished plans move here.

| Doc | Why archived |
|-----|--------------|
| `migration-commands-to-skills.md` | Completed — the `commands/*.md` → `skills/<name>/SKILL.md` consolidation is done (`find . -type d -name commands` returns 0). |
| `github-workflows-plan.md` | Superseded (2026-06-29) — the reusable workflows shipped; see the in-file banner. |
| `session-plugin-workflow.md` | Completed — Phases 0–3 landed; residual work is external/user-owned. |

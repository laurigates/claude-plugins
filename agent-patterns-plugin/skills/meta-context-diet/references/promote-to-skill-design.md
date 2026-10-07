# meta-context-diet — Designing the Target Skill

Moved verbatim from [SKILL.md](../SKILL.md) (Step 3). Open for each candidate
classified **Promote to skill**, before presenting it for confirmation.

### 3. For each promote-to-skill candidate, design the target skill

A rule only earns promotion if it can carry a **description good enough to auto-trigger** — otherwise moving it off the always-loaded surface silently loses the guidance. Draft, before proposing:

- **Skill home + name** — a new skill in an existing plugin, named per `skill-naming.md` (`<namespace>-<name>`). If no plugin fits, recommend keep-but-lean instead.
- **Description** — front-load tool/verb/domain, then a `Use when…` clause with the literal phrases a user would say; target ≤150 chars (`skill-quality.md`). This is the load-bearing artifact: if you cannot write a description that fires on the right intent, the content is not skill-shaped — reclassify as keep-but-lean or path-scope.
- **Body shape** — the procedure as imperative `## Execution` steps (`skill-execution-structure.md`); large tables go to `REFERENCE.md`.
- **Residual stub** — typically a one-line pointer (`> For the X workflow, see the \`plugin:skill\` skill.`) so a reader at the old location is routed without re-paying the body cost.

# Verify Before Filing — Phase 2 Draft Template

Open this when drafting the issue body for each candidate that survived the
Phase 1 gate.

## Phase 2 — Draft to a house template

Per surviving candidate, one markdown file per issue:

```markdown
# <symptom-first title — becomes the issue title>
<!-- target: <project path>  (stripped by the filing script) -->

## Summary
<claim, with evidence as blob links PINNED to the verified refs
(https://<forge>/<path>/-/blob/<ref>/<file>#L<n>) — not bare paths,
not `main` if HEAD drifts>

<real error signature mined from your own incident PRs/logs>

## Suggested fix
<EXACTLY ONE recommended fix; alternatives get one trailing sentence;
"happy to open the MR" only when trivial>

---
Observed while <one-line deployment context>; verified against <refs> on <date>.
```

Never leak internal PR numbers or repo paths into the body — use them only to
mine evidence. Then gate every draft through
`agent-patterns-plugin:cold-read-gate` (isolated haiku maintainer cold-read;
one revise round, re-gate only if the verdict was `needs-revision`).

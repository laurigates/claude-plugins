# Verify Before Filing — Phase 0 Candidate Manifest

Open this when building the candidate manifest that Phase 1 (and the harness's
`args`) consumes.

## Phase 0 — Consolidate a candidate manifest

One JSON/table entry per candidate: id, the **claim** (precise, falsifiable),
target upstream project, version observed, source refs (your commits/PRs that
hold real error output), and known-filed prior reports to dedup against.
Merge all sources first — audit docs, strategy docs, and git sweeps usually
overlap. Shape:

```json
{
  "id": "W2-13",
  "slug": "notification-smtp-ec-defaults",
  "claim": "Chart defaults SMTP to dev@simpl-europe.eu via ssl0.ovh.net (vendor dev infra) as live default values; should be placeholder/required.",
  "targets": ["group/subgroup/notification-service"],
  "observed_version": "2.1.1 (Apr 2026)",
  "sources": ["audit-doc item 6"],
  "evidence_prs": [1826]
}
```

Keep prior-filed report URLs (with issue iids) in the same manifest so search
agents can fetch their bodies.

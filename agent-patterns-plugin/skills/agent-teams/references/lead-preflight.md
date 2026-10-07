# Agent Teams — Lead Preflight Checklist

Moved verbatim from [SKILL.md](../SKILL.md). Open before drafting the PRP and
launching agents.

## Lead Preflight Checklist

Before drafting the PRP and launching agents, a 30-second sweep prevents
multi-edit renaming work after agents return:

| Check | Command | Why |
|-------|---------|-----|
| Next ADR/PRD/PRP sequence number | `ls docs/blueprint/adrs/ \| sort -V \| tail -1` | Prevents numbering collisions in parallel doc writes |
| Filename conflicts | `git ls-files \| grep <filename>` | Scope tables can't guard against a stale mental model of the tree |
| Hardware pin budget (embedded) | Read `pin_config.h` or equivalent | Prevents pin assignments overlapping across Phase 1 agents |

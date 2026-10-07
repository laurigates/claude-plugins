# meta-context-diet - Disposition Mechanics

How to carry out each approved disposition in Step 5, and the evidence behind
the Consolidate read-the-destination-first check.

## Mechanics per disposition

| Disposition | Mechanics |
|---|---|
| Keep — hard invariant | No change. Optionally note why it stays in the report. |
| Keep but lean | `Edit` the rule to the invariant + a link; move examples/tables to a co-located doc or the rule's own `REFERENCE`-style sidecar. Do not change the invariant's wording. |
| Path-scope | `Edit` the rule's frontmatter to add a `paths:` glob so it loads only on matching turns. Verify the glob matches the directory shape the rule actually targets. |
| Promote to skill | Scaffold `<plugin>/skills/<name>/SKILL.md` with the drafted frontmatter + imperative body; move reference material into the new skill's `REFERENCE.md`; trim the source rule to a one-line pointer (or delete it if nothing remains and nothing references it). Then update the plugin metadata per the **Plugin Lifecycle** in `CLAUDE.md` (README skills table; no `marketplace.json`/release-config edits — those are plugin-scoped, not skill-scoped, per `skill-consolidation.md`). Run `/reload-skills` so the new skill is invocable immediately. |
| Consolidate | **First read the destination and confirm it is current** — drift runs both ways, so where the always-loaded copy is the *fresher* one, fix the destination (or consolidate in the other direction) before pointing at it. Then `Edit` the source to a pointer at the canonical owner **by `plugin:skill` name** (never a cross-plugin file path — see `skill-consolidation.md`); or delete the redundant rule if a loaded plugin skill already covers it. |
| Drop | Delete the stale file. |

Evidence for the Consolidate check: in [`laurigates/loractl` #167](https://github.com/laurigates/loractl/pull/167) the pointer target still described a landed feature as a pending follow-up while the `CLAUDE.md` section being cut was correct, so consolidating without reading the destination first would have replaced the accurate copy with a pointer at the stale one.

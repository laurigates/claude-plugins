# blueprint-claude-md — Updating an Existing CLAUDE.md

The paths that edit a CLAUDE.md already on disk. Entry point:
[`../SKILL.md`](../SKILL.md) § Step 6 (@imports) and Step 7 (smart update).

## Smart update

- Parse existing sections
- Identify outdated content (compare with PRDs, structure)
- Offer section-by-section updates:
  ```
  question: "Found outdated sections. Which would you like to update?"
  options: [list of sections]
  allowMultiSelect: true
  ```

## Add @imports

When the user selected "Add @imports for existing docs":

- Scan existing CLAUDE.md for sections with content that exists in other files
- Replace duplicated content with `@path/to/source.md` imports
- Preserve CLAUDE.md-only content inline
- Show diff of changes before applying

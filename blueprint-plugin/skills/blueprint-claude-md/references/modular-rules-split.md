# blueprint-claude-md — Modular Rules Split

How CLAUDE.md divides its content with `.claude/rules/` when `claude_md_mode` is
`both` or `modular`, and how to resolve content duplicated between the two.
Entry point: [`../SKILL.md`](../SKILL.md) § Step 5 (mode) and Step 8 (sync).

## Mode "both"

- Keep CLAUDE.md as high-level overview
- Reference `.claude/rules/` for details:
  ```markdown
  ## Detailed Rules
  See `.claude/rules/` for domain-specific guidelines:
  - `development.md` - Development workflow
  - `testing.md` - Testing requirements
  - `frontend/` - Frontend-specific rules
  - `backend/` - Backend-specific rules
  ```

## Mode "modular"

- Create minimal CLAUDE.md with `@import` references
- Move detailed content to `.claude/rules/`
- Example lean CLAUDE.md:
  ```markdown
  # Project: {name}

  ## Overview
  {One-paragraph description}

  @docs/prds/main.md

  ## Development
  {Build, test, lint commands}

  ## Rules
  See `.claude/rules/` for detailed guidelines.
  ```

## Sync with modular rules

When rules exist in `.claude/rules/`:

- Detect duplicated content
- Offer to deduplicate:
  ```
  question: "Found duplicate content between CLAUDE.md and rules/. How to resolve?"
  options:
    - "Keep in CLAUDE.md, remove from rules"
    - "Keep in rules, reference from CLAUDE.md"
    - "Keep both (may cause confusion)"
  ```

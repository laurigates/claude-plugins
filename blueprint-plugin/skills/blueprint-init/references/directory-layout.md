# blueprint-init — Directory Layout (Step 6)

The tree Step 6 produces.

   The resulting tree:
   ```
   docs/
   ├── blueprint/
   │   ├── manifest.json            # Version tracking and configuration
   │   ├── feature-tracker.json     # Progress tracking (if enabled)
   │   ├── work-orders/             # Task packages for subagents
   │   │   ├── completed/
   │   │   └── archived/
   │   └── README.md                # Blueprint documentation
   ├── prds/                        # Product Requirements Documents (canonical)
   ├── adrs/                        # Architecture Decision Records (canonical)
   ├── prps/                        # Product Requirement Prompts (canonical)
   └── trps/                        # Test Regression Plans (created on-demand by /blueprint:derive-tests)
   ```

   **Claude configuration (in .claude/):** — initial rules are written under
   `structure.generated_rules_path` (default `.claude/rules/`; an isolated
   subdirectory like `.claude/rules/blueprint/` when Step 4a detected existing
   content), shown here at the default location:
   ```
   .claude/
   ├── rules/                       # $RULES_DIR — generated_rules_path (default .claude/rules/)
   │   ├── development.md           # Development workflow rules
   │   ├── testing.md               # Testing requirements
   │   └── document-management.md   # Document organization rules (if detection enabled)
   └── skills/                      # Custom skill overrides (optional)
   ```

## Why top-level `docs/`

**Canonical document paths** are at the **top level** of `docs/`, not under `docs/blueprint/`. `docs/blueprint/` holds blueprint machinery only (manifest, feature-tracker, work-orders); `docs/{adrs,prds,prps,trps}/` hold the documents themselves. Every `/blueprint:derive-*` skill writes to the top-level paths — keeping them consistent prevents the dual-corpus bug where init creates one layout and derive-* writes to another.

## `docs/trps/`

Note: `docs/trps/` is created on-demand by `/blueprint:derive-tests` only — init does not pre-create it.

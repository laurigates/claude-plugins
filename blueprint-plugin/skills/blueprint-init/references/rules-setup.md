# blueprint-init — Rules Setup (Steps 5, 8a)

Detail for writing and registering the initial rules under `$RULES_DIR`.

## Step 5 — if decision detection is enabled

**If enabled:**
Resolve the rules output directory before writing — honour the path chosen in
Step 4a (default `.claude/rules/`) rather than hardcoding it, so blueprint
does not collide with rulesync-managed or hand-authored rules (issue #1675):

```bash
RULES_DIR=$(jq -r '.structure.generated_rules_path // ".claude/rules/"' docs/blueprint/manifest.json)
mkdir -p "$RULES_DIR"
```

When the manifest is not yet written, use the Step 4a selection directly
(default `.claude/rules/`).

Copy `document-management-rule.md` template to `$RULES_DIR/document-management.md`.
This rule instructs Claude to watch for:
- Architecture decisions being made during discussion → prompt to create ADR
- Feature requirements being discussed or refined → prompt to create/update PRD
- Implementation plans being formulated → prompt to create PRP

## Step 8a — what the registration script writes

The script is the same one `/blueprint:generate-rules` Step 5 uses, so the
two producers of `$RULES_DIR` cannot drift apart on the record shape or on
how the hash is computed. It resolves `$RULES_DIR` from
`structure.generated_rules_path` itself and writes, per rule, a
`generatedRecord` (`source`, `generated_at`, `plugin_version`,
`content_hash`, `status`) into the `generated.rules` **object map** defined by
`blueprint-plugin/schemas/manifest.schema.json`.

**Key form** — the manifest key is the rule's **bare filename relative to
`$RULES_DIR`, including the `.md` extension** (`development.md`, never
`development` and never `.claude/rules/development.md`). A consumer resolves
a rule as `"$RULES_DIR/$key"` and must **not** append `.md`. Check
`REGISTERED=` and `STATUS=OK` in the script's output before continuing.

# blueprint-init — Document Migration (Step 3)

Read when Step 3 finds existing documentation outside the standard repo files.

## Find candidate docs

```bash
# Find markdown files that look like documentation (not standard repo files)
find . -name '*.md' -not -path '*/node_modules/*' -not -path '*/.git/*' | grep -viE '(README|CHANGELOG|CONTRIBUTING|LICENSE|CODE_OF_CONDUCT|SECURITY)\.md$'
```

## Measure cross-reference density

```bash
# Count references to each candidate doc path (skip the doc itself)
for doc in $candidate_docs; do
  base=$(basename "$doc")
  refs=$(grep -rIl --exclude-dir=.git --exclude-dir=node_modules "$base" . | grep -v "^./$doc$" | wc -l | tr -d ' ')
  ext=$(grep -rIl --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=docs "$base" . | wc -l | tr -d ' ')
  echo "$doc total=$refs outside_docs=$ext"
done
```

## Migration prompt

```
Use AskUserQuestion:
question: "Found existing documentation: {file_list}. {N} of these are referenced outside docs/ ({ref_summary}). Migrate to Blueprint-managed paths?"
options:
  # When NO candidate is referenced outside docs/: keep "(Recommended)" on migrate.
  # When ANY candidate IS referenced outside docs/: drop "(Recommended)" and show counts.
  - label: "Yes, migrate documents"
    description: "Move docs into docs/prds/, docs/adrs/, docs/prps/ based on content type. Rewrites all {total_refs} references — including build-critical files when referenced outside docs/."
  - label: "No, leave them in place"
    description: "Blueprint creates new docs under docs/{prds,adrs,prps}/; existing docs stay where build tooling and READMEs already point. Safe default when docs are referenced outside docs/."
```

## Migrating the selected docs

**If "Yes" selected:**
a. Analyze each file to determine type:
   - Contains requirements, features, user stories → `docs/prds/`
   - Contains architecture decisions, trade-offs → `docs/adrs/`
   - Contains implementation plans → `docs/prps/`
   - General documentation → `docs/`
b. Move files to appropriate `docs/` subdirectory
c. Rename to kebab-case if needed (REQUIREMENTS.md → requirements.md)
d. Report migration results:
   ```
   Migrated documentation:
   - REQUIREMENTS.md → docs/prds/requirements.md
   - ARCHITECTURE.md → docs/adrs/0001-initial-architecture.md
   ```

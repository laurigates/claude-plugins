# vault-stubs subagent

You classify and consolidate FVH/z files. This mode requires per-file content judgment; a bulk-rewrite is unsafe.

## Role

For each file under `FVH/z/`, decide whether it should be:

1. A clean redirect stub (≤200 B, `tags: [redirect]`, pointing to `Zettelkasten/<same-basename>`)
2. Promoted to `Zettelkasten/` (if general-interest content with no FVH specifics)
3. Left as FVH-original content (if FVH-specific)

## Input

The audit's `stubs` section classifies every FVH/z file into one of:

- `clean_redirect` — no action needed
- `broken_redirect` — has `redirect` tag but wrong body; the deterministic Python fixer has already rewritten these before you started
- `stale_duplicate` — full article, basename exists in Zettelkasten; **this is your primary work**
- `fvh_original` — no Zettelkasten counterpart, leave alone

## Per-File Decision Flow (stale_duplicate)

For each file the audit reports as `stale_duplicate`:

1. **Read both files**: `FVH/z/Foo.md` and `Zettelkasten/Foo.md`.
2. **Diff by heading.** Call the Python helper to list sections that exist in FVH/z but not in Zettelkasten:

   ```bash
   uv run python -c "
   from vault_agent.fixers.stub_rewriter import unique_sections
   src = open('FVH/z/Foo.md').read()
   dst = open('Zettelkasten/Foo.md').read()
   for h in unique_sections(src, dst):
       print(h)
   "
   ```

3. **Pick ONE outcome**:

   | Outcome | When | Action |
   |---------|------|--------|
   | **Pure subset** | `unique_sections` returns `[]` | Overwrite FVH/z with canonical redirect body |
   | **Merge-then-redirect** | One or more unique sections with substantive content | Edit the Zettelkasten file to append each unique section, commit the merge, **then** overwrite FVH/z |
   | **Coincidental collision** | Basenames match but topics differ (e.g. `FVH/z/Kafka.md` is an FVH Slack-integration note, `Zettelkasten/Kafka.md` is about Apache Kafka) | Flag for user. Report as "likely coincidental collision, not a stub". Do NOT redirect |
   | **FVH/z is better** | Rare — FVH/z has a fuller canonical version | Flag for user review, don't auto-merge |

4. **Never delete content that doesn't appear in Zettelkasten.** Before calling `Write` to overwrite the FVH/z file with the canonical redirect, verify the merge landed:

   ```bash
   uv run python -c "
   from vault_agent.fixers.stub_rewriter import verify_canonical_phrase_present
   src = open('FVH/z/Foo.md').read()
   dst = open('Zettelkasten/Foo.md').read()
   assert verify_canonical_phrase_present(src, dst), 'Merge check FAILED — abort overwrite'
   "
   ```

   If the assertion fails, abort and flag for user review. Do NOT overwrite.

## Canonical Redirect Body

Use the template from `vault_agent.fixers.stub_rewriter.CANONICAL_REDIRECT_TEMPLATE`:

```yaml
---
tags: [redirect]
context: fvh
---
See [[Zettelkasten/Foo|Foo]] in the main knowledge base.
```

## Commit Pattern

One commit per file for `stale_duplicate` that required a merge:

```
refactor(stubs): merge FVH/z/Foo.md into Zettelkasten, convert stub
```

One batch commit for pure-subset conversions:

```
refactor(stubs): convert N FVH/z files to redirect stubs
```

Flagged coincidental collisions get **no commit**. Report them in the summary.

## Ambiguity: Skip, Don't Guess

If the stale_duplicate classification is ambiguous — e.g., basename collision but topics are plausibly different — treat it as a coincidental collision and flag it. Wrong redirects destroy content.

## Never Do

- **Don't bulk-rewrite** all FVH/z files — content judgment is required per file.
- **Don't promote** `fvh_original` to Zettelkasten without explicit user input.
- **Don't delete** content that doesn't appear verbatim in the Zettelkasten copy; always merge first.
- **Don't `git push`** — vault-agent has no remote.
- **Don't skip the `verify_canonical_phrase_present` check**; if it fails, abort.

## Report

After processing, emit a `## Run summary` block with:

- Files converted to redirect (count + list)
- Files merged-then-redirected (count + list, with the unique sections carried across)
- Files flagged for user review (count + rationale)
- Files identified as coincidental collisions (count + basenames)

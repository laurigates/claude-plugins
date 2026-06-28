---
created: 2026-04-17
modified: 2026-06-28
reviewed: 2026-04-25
name: vault-stubs
description: "Work-namespace redirect-stub classification in an Obsidian vault. Use when cleaning stubs, converting duplicates to redirects, or merging content into Zettelkasten."
user-invocable: false
allowed-tools: Read, Edit, Write, Grep, Glob
---

# Work-namespace Stub Management

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Classifying and consolidating work-namespace redirect stubs in the vault | Triaging generic orphan notes outside the work namespace — use `vault-orphans` |
| Promoting a work-namespace note into the canonical Zettelkasten location | Repairing the wikilinks that point at the moved note afterwards — use `vault-wikilinks` |
| Merging unique work-namespace content back into a Zettelkasten note | Adding the merged note into a Map of Content hub — use `vault-mocs` |

A work-namespace subtree (a directory such as `work/z/`) is a knowledge base that mirrors select Zettelkasten notes as tiny redirect stubs. Content lives in `Zettelkasten/`; the work-namespace subtree points to it so work-context queries still find the topic.

## Canonical Redirect Stub Format

```yaml
---
tags: [redirect]
context: work
---
See [[Zettelkasten/Docker|Docker]] in the main knowledge base.
```

Properties:
- Size ≤ 200 bytes (whitespace excluded)
- Tags is exactly `[redirect]`
- Body is a single wikilink with alias to the canonical note
- `context: work`

## Classifications (from vault-agent's stubs analyzer)

| Class | Meaning | Action |
|-------|---------|--------|
| `clean_redirect` | ≤ 200 B, `redirect` tag, Zettelkasten match | ✓ keep as-is |
| `broken_redirect` | `redirect` tag but >200 B or missing target | Rewrite body to the canonical one-liner |
| `stale_duplicate` | Full article, basename exists in Zettelkasten | Merge content into Zettelkasten, convert stub to `clean_redirect` |
| `ns_original` | Full article, no Zettelkasten match | Legitimate — leave alone |

## Consolidation: stale_duplicate → clean_redirect

When a `work/z/Foo.md` has substantive content AND `Zettelkasten/Foo.md` exists, you must decide:

1. **Is the work-namespace content a subset of Zettelkasten?** → Replace stub with canonical redirect. No content merge needed.
2. **Does the work-namespace note have unique content?** → Merge the unique sections into `Zettelkasten/Foo.md` first, then replace stub.
3. **Is the work-namespace note *better* than Zettelkasten?** → Rare, but flag for user review. The user decides which becomes canonical.

### Merge Heuristic

Compare by section. If a heading in `work/z/Foo.md` has text that doesn't appear in `Zettelkasten/Foo.md`, that text needs migration. Use word-level comparison, not exact match — minor wording differences don't count as "unique content."

When in doubt, **flag for user review** rather than auto-merging. A bad merge is worse than leaving a duplicate.

## Conversion Recipe

Replace the whole work-namespace file body:

```yaml
---
tags: [redirect]
context: work
---
See [[Zettelkasten/Foo|Foo]] in the main knowledge base.
```

Commit message:
```
refactor(stubs): convert work/z/Foo.md to redirect (content merged into Zettelkasten)
```

## Promoting ns_original → Zettelkasten

Occasionally a file classified `ns_original` is actually general-interest content that belongs in `Zettelkasten/`. Signs:
- No work-specific references (internal check-ins, internal tools, internal URLs)
- Could be useful in personal contexts

If promoting:
1. Move file to `Zettelkasten/Foo.md`
2. Create a `work/z/Foo.md` redirect stub in its place
3. Strip `context: work` from the promoted note's frontmatter
4. Commit as `refactor(stubs): promote Foo from work/z to Zettelkasten`

Don't promote aggressively — the work namespace exists for a reason.

## Detection

```bash
# All work-namespace files ordered by size
fd -e md . work/z -x wc -c {} | sort -n

# Ones with `redirect` tag
rg -l '^tags:.*\bredirect\b' work/z/ --glob '*.md'

# Large ones without `redirect` tag (candidates for conversion)
rg -L -l '^tags:.*\bredirect\b' work/z/ --glob '*.md'
```

Vault-agent's `analyze_stubs` gives the full classification.

## Offline Fallback (App Closed)

The detection methodology above is unchanged — only the **data source** changes when Obsidian (and its `obsidian` CLI / live link index) is closed. The `obsidian` CLI and `vault-agent` analyzers are the **live-index** path; parsing the `.md` corpus directly with the `fd`/`rg` Detection snippet above is the **deterministic headless default**, and for batch/scheduled audits it is often the better choice (reproducible, free of app/index state). `vault-frontmatter` already operates this way.

Parse the corpus directly:

- **Frontmatter** — read each note's YAML block between the leading `---` fences; extract `tags`, `aliases`, `context`. See `vault-frontmatter` for YAML-block mechanics.
- **Wikilinks** — match `[[Target]]`, `[[Target|Alias]]`, `[[Target#Heading]]`, `[[folder/Target]]`, and `![[embed]]`. Resolve each target to a note by **basename**, then **relative path**, then **alias** (from frontmatter), all **case-insensitive**. Resolve `![[embed]]` against attachments (e.g. under `Files/`) as well as notes.

Classify each stub from parsed inputs only: file size (`wc -c`), the `redirect` frontmatter tag, and a **basename** match against `Zettelkasten/` — the same inputs `analyze_stubs` uses. The redirect body's `[[Zettelkasten/Foo|Foo]]` target is verified with the resolution cascade above.

## Safety

- Never delete content without verifying it exists elsewhere. When merging, grep the destination note for a canonical phrase from the source.
- Preserve `context: work` on stubs (required for work-namespace queries).
- Don't create stubs for Zettelkasten notes that aren't actually used in work context — that creates noise, not redirection.

## Related Skills

- **vault-frontmatter** — YAML mechanics for adding the `redirect` tag
- **vault-wikilinks** — pipe-alias syntax for the redirect link
- **vault-tags** — `redirect` tag is an exception to the emoji-prefix rule

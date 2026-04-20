---
created: 2026-04-17
modified: 2026-04-19
reviewed: 2026-04-17
name: vault-stubs
description: |
  FVH/z/ redirect-stub classification and consolidation for LakuVault. Use
  when the user asks to clean up FVH/z redirect stubs, convert stale
  duplicates into canonical redirects, merge unique FVH content back into
  Zettelkasten, promote an FVH-only note into the main vault, or fix
  broken/oversized stubs.
user-invocable: false
allowed-tools: Read, Edit, Write, Grep, Glob
---

# FVH/z Stub Management

In LakuVault, the `FVH/z/` directory is a work-namespace knowledge base that mirrors select Zettelkasten notes as tiny redirect stubs. Content lives in `Zettelkasten/`; `FVH/z/` points to it so work-context queries still find the topic.

## Canonical Redirect Stub Format

```yaml
---
tags: [redirect]
context: fvh
---
See [[Zettelkasten/Docker|Docker]] in the main knowledge base.
```

Properties:
- Size ≤ 200 bytes (whitespace excluded)
- Tags is exactly `[redirect]`
- Body is a single wikilink with alias to the canonical note
- `context: fvh`

## Classifications (from vault-agent's stubs analyzer)

| Class | Meaning | Action |
|-------|---------|--------|
| `clean_redirect` | ≤ 200 B, `redirect` tag, Zettelkasten match | ✓ keep as-is |
| `broken_redirect` | `redirect` tag but >200 B or missing target | Rewrite body to the canonical one-liner |
| `stale_duplicate` | Full article, basename exists in Zettelkasten | Merge content into Zettelkasten, convert stub to `clean_redirect` |
| `fvh_original` | Full article, no Zettelkasten match | Legitimate — leave alone |

## Consolidation: stale_duplicate → clean_redirect

When a `FVH/z/Foo.md` has substantive content AND `Zettelkasten/Foo.md` exists, you must decide:

1. **Is the FVH/z content a subset of Zettelkasten?** → Replace stub with canonical redirect. No content merge needed.
2. **Does FVH/z have unique content?** → Merge the unique sections into `Zettelkasten/Foo.md` first, then replace stub.
3. **Is FVH/z *better* than Zettelkasten?** → Rare, but flag for user review. The user decides which becomes canonical.

### Merge Heuristic

Compare by section. If a heading in `FVH/z/Foo.md` has text that doesn't appear in `Zettelkasten/Foo.md`, that text needs migration. Use word-level comparison, not exact match — minor wording differences don't count as "unique content."

When in doubt, **flag for user review** rather than auto-merging. A bad merge is worse than leaving a duplicate.

## Conversion Recipe

Replace the whole FVH/z file body:

```yaml
---
tags: [redirect]
context: fvh
---
See [[Zettelkasten/Foo|Foo]] in the main knowledge base.
```

Commit message:
```
refactor(stubs): convert FVH/z/Foo.md to redirect (content merged into Zettelkasten)
```

## Promoting fvh_original → Zettelkasten

Occasionally a file classified `fvh_original` is actually general-interest content that belongs in `Zettelkasten/`. Signs:
- No FVH-specific references (ICT check-in, silverbucket, internal URLs)
- Could be useful in personal contexts

If promoting:
1. Move file to `Zettelkasten/Foo.md`
2. Create a `FVH/z/Foo.md` redirect stub in its place
3. Strip `context: fvh` from the promoted note's frontmatter
4. Commit as `refactor(stubs): promote Foo from FVH/z to Zettelkasten`

Don't promote aggressively — the FVH namespace exists for a reason.

## Detection

```bash
# All FVH/z files ordered by size
fd -e md . FVH/z -x wc -c {} | sort -n

# Ones with `redirect` tag
rg -l '^tags:.*\bredirect\b' FVH/z/ --glob '*.md'

# Large ones without `redirect` tag (candidates for conversion)
rg -L -l '^tags:.*\bredirect\b' FVH/z/ --glob '*.md'
```

Vault-agent's `analyze_stubs` gives the full classification.

## Safety

- Never delete content without verifying it exists elsewhere. When merging, grep the destination note for a canonical phrase from the source.
- Preserve `context: fvh` on stubs (required for FVH namespace queries).
- Don't create stubs for Zettelkasten notes that aren't actually used in FVH context — that creates noise, not redirection.

## Related Skills

- **vault-frontmatter** — YAML mechanics for adding the `redirect` tag
- **vault-wikilinks** — pipe-alias syntax for the redirect link
- **vault-tags** — `redirect` tag is an exception to the emoji-prefix rule

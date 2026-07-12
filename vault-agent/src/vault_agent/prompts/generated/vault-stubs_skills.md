## vault-stubs

# Work-namespace Stub Management


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
- **Wikilinks** — match `[[Target]]`, `[[Target|Alias]]`, `[[Target#Heading]]`, `[[folder/Target]]`, and `![[embed]]`. Resolve each target to a note by **basename**, then **relative path**, then **alias** (from frontmatter), all **case-insensitive**. Resolve `![[embed]]` against attachments as well as notes — the attachment folder is per-vault configurable, so read it from `.obsidian/app.json` (`attachmentFolderPath`) and fall back to the vault root / `Files/` only when that key is unset.

Classify each stub from parsed inputs only: file size (`wc -c`), the `redirect` frontmatter tag, and a **basename** match against `Zettelkasten/` — the same inputs `analyze_stubs` uses. The redirect body's `[[Zettelkasten/Foo|Foo]]` target is verified with the resolution cascade above.


## Safety

- Never delete content without verifying it exists elsewhere. When merging, grep the destination note for a canonical phrase from the source.
- Preserve `context: work` on stubs (required for work-namespace queries).
- Don't create stubs for Zettelkasten notes that aren't actually used in work context — that creates noise, not redirection.

---

## vault-frontmatter

# Vault Frontmatter Maintenance


## Canonical Frontmatter Shape

```yaml
---
tags:
  - 🛠️/neovim       # emoji-prefixed category tag
  - 📝/notes         # note-type tag
context: work        # work-namespace notes only
---
```

Rules:
1. No `id:` field — removed from all current templates.
2. 2–3 tags per note; every tag either `emoji/subcategory` or a bare note-type like `📝/moc`.
3. No bare emoji placeholders (`📝`, `🌱`, `📝/🌱`) — they indicate the tag was never specified.
4. No `null` tag values — YAML must be valid.
5. Work-namespace notes (e.g. under `work/`) carry `context: work`; personal notes omit the field.


## Detection Patterns

| Issue | Grep pattern | Notes |
|-------|--------------|-------|
| Legacy `id:` | `^id:` inside frontmatter block | Strip entire line |
| Bare placeholder tag | YAML tag value exactly `📝`, `🌱`, or `📝/🌱` | Remove if note has other useful tags; else leave |
| Null tag | YAML tag value literally `null` | Remove list entry |
| Templater leak | `<% tp\.` or `\{\{title\}\}` or `\{\{date\}\}` | Replace `{{title}}` with filename stem; strip `<% tp.* %>` |
| Corrupt emoji | Tag contains Unicode replacement char `\ufffd` | Flag for manual fix — don't guess |
| Missing work context | File under the work namespace (e.g. `work/`) without `context: work` | Add the line |


## Edit Recipes


### Strip legacy id
Before:
```yaml
---
id: 20240118235900
tags: [🛠️/neovim]
---
```
After:
```yaml
---
tags: [🛠️/neovim]
---
```


### Remove bare placeholder (keeping useful tags)
Before:
```yaml
tags:
  - 📝
  - 🛠️/ansible
```
After:
```yaml
tags:
  - 🛠️/ansible
```


### Legacy MOC tag → current
Before:
```yaml
tags:
  - 🗺️
```
After:
```yaml
tags:
  - 📝/moc
```


## Edit Pattern

Use `Edit` with small targeted `old_string` / `new_string` replacements that preserve exact indentation. Never rewrite whole files when a line edit suffices — it minimizes the commit diff and makes reviews easy.

For bulk fixes across many files, drive from a script that emits one `Edit` call per file rather than running `sed` in `Bash`. The commit-per-category pattern (`fix(tags): strip bare 📝 from 639 notes`) relies on keeping all edits in one logical batch.


## Safety

- Never write to `.obsidian/`, `.claude/`, `.git/`, `Files/`. The safety hook enforces this.
- Never add frontmatter to daily notes in `Notes/` or `work/notes/` without verifying — they often don't need any.
- When in doubt about what a placeholder tag meant, leave the note unchanged and report it rather than guess.

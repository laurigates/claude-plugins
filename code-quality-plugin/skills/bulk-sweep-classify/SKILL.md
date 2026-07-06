---
name: bulk-sweep-classify
description: "Classify every regex match before a bulk find-replace/syntax-modernization sweep — four match categories, scoped transform, allowlist-aware verification. Use when bulk-renaming commands/tools/paths or migrating syntax across many files."
allowed-tools: Bash, Read, Grep, Edit
created: 2026-07-05
modified: 2026-07-06
reviewed: 2026-07-06
---

# Bulk Sweep — Classify Every Match First

When you modernize a syntax across many files with a `regex` / `sed` / `perl`
pass — a command rename (`/ns:cmd` → `/ns-cmd`), a tool/binary rename, a path or
import-style migration, an API-version bump in prose — the matched set is
**heterogeneous even though every hit looks textually identical**. One pattern
catches genuine stale targets *and* several look-alikes that must NOT be
transformed. Blindly rewriting all matches corrupts the look-alikes silently: the
sweep reports success, and the damage surfaces far downstream (a broken designed
filename, a rewritten immutable record).

**The discipline: enumerate the matches and bucket every one into a category
before editing.** The regex sees *text*; the transform needs *semantics*.

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|------------------------|------------------------------------|
| A find-replace where the delimiter/token also appears in filenames, config keys, URLs, designs, or historical records | The pattern is structural (function shape, call form) → `code-quality-plugin:ast-grep-search`. **Also** when the rename is *textually simple but code-targeted* (an API rename, call-site migration, or import-path change in **source files**): route it through `ast-grep-search` first — structural matching won't touch strings/comments/URLs, so category-2 false positives shrink to near-zero (see the routing step below) |
| Command-syntax migration (`/ns:cmd` → `/ns-cmd`), tool rename in docs, path/import migration, API-version bump in prose | A one-off literal string search with no look-alike risk → `tools-plugin:rg-code-search` |
| Docs trees mixing live guidance with ADRs / changelogs / design PRDs, all matching the same regex | The whole match-set is genuinely uniform and you have verified it |

## The Four Categories

Read the surrounding line of each match and bucket it. Each category needs
different handling.

| Category | Handling | Canonical example (command-syntax sweep) |
|---|---|---|
| **1. Genuine stale target** | **Transform** | `/configure:mcp` → `/configure-mcp` in live docs |
| **2. False positive** — merely matches the pattern | **Leave** | `laurigates/dotfiles:latest` (docker tag); `redis://host:6379` (digit after `:`, not a command) |
| **3. Out-of-scope design** legitimately using the old form — esp. **delimiter embedded in designed filenames/paths** | **Leave** — transforming corrupts the design | `/sync:daily` PRD whose colon also appears in `sync:daily-state.json`, `.claude/commands/sync:daily.md` |
| **4. Immutable / historical record** matching the pattern | **Supersede-note; do NOT rewrite the body** | Accepted ADRs documenting the old `/namespace:command` convention |

**Category 3 is the sharpest trap.** The delimiter you're replacing (`:`, `/`,
`.`, `-`) often also appears in **filenames, config keys, or URLs** that the
matched token participates in. Hyphenating `/sync:daily` → `/sync-daily` also
rewrites every `sync:daily-state.json` path in the same doc — silently breaking a
design.

**Category 4** follows the standard supersede-don't-rewrite convention: set
`Status: Superseded` plus a top-note, leave the body as a historical record.

## Execution

### Step 0: Route by sweep target — code vs. prose/docs

Before enumerating, decide **what** you are sweeping. This picks the transform
engine and shrinks the classify workload:

- **Sweep target is code** — an API rename, call-site migration, or import-path
  change in **source files**. Do the transform *structurally* with
  `ast-grep -p '<old>' -r '<new>' --lang <l>`, delegating the transform
  mechanics to `code-quality-plugin:ast-grep-search`. An ast-grep pattern
  matches **AST nodes**, so it inherently won't match inside strings, comments,
  or URLs — the whole **category-2 false-positive bucket shrinks to near-zero**.
  The classify pass then focuses on **categories 3 (designed filenames/paths)
  and 4 (immutable records) only**, and Steps 1–2's false-positive tightening is
  largely unnecessary. Proceed to Step 3 with the ast-grep result in hand.

- **Sweep target is prose/docs/mixed** — command renames in markdown, tool names
  in docs trees, an API-version bump in prose. Regex sees *text*, not semantics,
  so the **four-category discipline below is unchanged and remains this skill's
  core case.** Run the full Step 1 → Step 5 pipeline.

The decision hinges on whether a structural matcher *can* see your target: code
has an AST, prose does not. When in doubt (a rename that spans both source and
its surrounding docs), split it — ast-grep the source, then run the
four-category pass over the docs.

Run this classify-then-transform sweep:

### Step 1: Enumerate every match, deduped, before touching anything

```
git grep -nhoE '/[a-z][a-z0-9-]*:[a-z][a-z0-9-]*' -- <scope> | sort -u
```

Adjust the pattern to your migration. The point is a complete, deduped inventory
in hand *before* any edit.

### Step 2: Tighten the pattern to drop false positives at the source

Drive the false-positive exclusion into the **pattern** wherever you can, so the
sweep mechanically cannot touch category-2 hits. Example: requiring a letter
after the colon (`:[a-z]`) excludes `:6379` ports and `redis://` URLs. This
removes the whole class from manual consideration.

### Step 3: Bucket every remaining hit into categories 1–4

Read the surrounding line of each match. Reserve manual judgment for categories 3
and 4 — they *look* like real targets and can only be told apart by reading
intent. Record which files/lines fall into categories 2–4 (the
**intentionally-preserved set**).

### Step 4: Scope the transform to category-1 files ONLY

```
perl -i -pe 's{/([a-z][a-z0-9-]*):([a-z][a-z0-9-]*)}{/$1-$2}g' <category-1 files>
```

Pass only the category-1 files. Hand-handle categories 3 and 4:
category 3 is left untouched; category 4 gets a supersede/status note with its
body left intact.

### Step 5: Verify against the preserved set, not literal zero

Re-run the enumeration from Step 1. The correct success test is **NOT** "zero
matches remain":

> **Zero matches remain *outside the intentionally-preserved set*.**

Categories 3 and 4 are *supposed* to keep matching. Confirm the grep returns
**only** the category 2–4 lines you identified in Step 3.

For the **code route** (Step 0), the preserved set is whatever ast-grep's
structural match legitimately leaves behind — the old form still cited inside
**strings, comments, or URLs** that the AST matcher never touched. Verify it the
same way: re-run the enumeration and confirm the only remaining matches are those
non-code occurrences (plus any categories 3/4), not genuine call sites.

## The Verification Trap

The naive success test — *"re-run the grep; it should return nothing"* — is
**wrong**, because categories 3 and 4 legitimately still match. A verification
that demands literal zero will either fail spuriously or — worse — pressure you
into corrupting a category-3 design or rewriting a category-4 record just to force
the count to zero. Enumerate the preserved buckets up front, then verify the grep
returns *only* those.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Enumerate deduped matches | `git grep -nhoE '<pattern>' -- <scope> \| sort -u` |
| Count matches per file | `git grep -cE '<pattern>' -- <scope>` |
| Preview a scoped transform | `perl -ne 's{<from>}{<to>}g and print' <files>` |
| Apply to category-1 files only | `perl -i -pe 's{<from>}{<to>}g' <category-1 files>` |
| Verify preserved-set only | `git grep -nE '<pattern>' -- <scope>` (expect only categories 2–4) |

## Related

- `verify-upstream-before-patching` / `read-issue-thread-before-contributing` — establish authoritative *intent* before acting, don't trust a surface signal
- `git-hazards` — an automated pass reporting success is not proof the *result* is correct; verify the content, not the exit code
- `code-quality-plugin:ast-grep-search` — structural search/replace when the pattern depends on AST shape rather than text

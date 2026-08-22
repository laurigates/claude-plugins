---
name: bulk-sweep-classify
description: "Classify every regex match before a bulk find-replace/syntax-modernization sweep — four match categories, scoped transform, allowlist-aware verification. Use when bulk-renaming commands/tools/paths or migrating syntax across many files."
allowed-tools: Bash, Read, Grep, Edit
created: 2026-07-05
modified: 2026-08-22
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

#### Derive the term set from what the mechanism *claims*, not just what it is *named*

The enumeration is only as good as the terms you feed it. Removing a mechanism
means removing its **assertions** as well as its **identifiers**, and those two
families share no tokens — so a sweep built only from identifiers reports clean
while the claim survives.

After listing the identifier terms, ask:
**what did this mechanism promise, and in whose words?**
Add those phrasings to the term set. For a removal, terms usually come in two
families:

| Family | Example terms | Where they live |
|---|---|---|
| Identifiers | function, file, script, env var, config key | code, config, workflows |
| Claims | "baked in", "injected at build time", "automatically", "the published package …" | comments, README, docstrings, error and warning strings |

**The claim family is where user-facing damage concentrates.** An identifier
left behind is dead code, but
a claim left behind is documentation that is now false.

Concrete case (`ForumViriumHelsinki/podio-mcp`, PRs #160 / #163 — issue #2479):
a build-time credential injector was removed. The sweep terms were the
identifiers — `BUILD_DEFAULTS`, `inject-build-defaults`, `postbuild` — which
correctly found the script, the npm hook, the constants module and the workflow
passthrough, and the PR shipped. It missed this, in a file the sweep had already
edited:

```
src/index.ts:134
 * - PODIO_CLIENT_ID: Your Podio app's client ID (baked into published package)
```

The comment asserts exactly what the mechanism was supposed to do and contains
none of the three identifiers. It survived, typedoc renders it into the API
reference, and so the claim outlived the thing that made it true — caught only
incidentally, one PR later.

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

The adjacent trap sits one level up, in the scope the verification runs over:
**every exclusion in a verification scope is a claim about the world, and needs
the same treatment as a negative result.** "Generated, so it doesn't count"
assumes the generator runs — check that it does. Cheap test: for each excluded
path, state why in one line, then verify that line. In the same sweep (#2479)
the final pass excluded `docs/api/` — committed typedoc output — reasoning that
CI regenerates and publishes it. Both halves were false: GitHub Pages was never
enabled on the repo (`/repos/.../pages` → 404) and the deploy workflow had failed
every run for ten days, so the excluded directory was the *only* rendered copy
and still carried the stale claim. The report said "no matches remain," which was
true of what it searched and false of the repo.

## Parallelizing a Sweep — Resolve the Rename Map Before Dispatch

When a sweep is large enough to fan out across parallel agents, a second failure
mode appears on top of the four categories: **the agents disagree with each
other.** Each one classifies its own borderline matches, each one is locally
defensible, and the result is a codebase that is internally inconsistent — every
file compiles on its own, the whole does not.

Fix it by resolving every cross-file naming decision **before** dispatch, into a
single explicit **rename map**: old → new, plus an explicit **do-NOT-rename**
list (the category 2–4 tokens from Step 3). Brief that map **verbatim** into
every agent's prompt — not paraphrased, not summarized per agent.

| Property you need | What guarantees it |
|---|---|
| Every agent renames the same tokens the same way | The map, resolved centrally once and copied verbatim |
| No two agents edit the same file | File grouping — **disjointness only** |

That split is the point. Agreement is hard to extract from independent agents
and trivial to get from a shared artifact, so move it out of the agents
entirely; grouping then only has to guarantee disjointness, a much weaker and
easier property than consensus.

The do-NOT-rename list is not padding — it is the contract's teeth. An agent
that "helpfully" extends the rename to a look-alike commits exactly the
category-2/3 corruption this skill exists to prevent, and a parallel agent
commits it out of your sight.

**The success signal is an agent *refusing* a rename.** In a 112-file
`Trends → Foresight` sweep (ForumViriumHelsinki/thelma PR #1263, which also
renamed a Postgres enum `TrendType → ForesightType`), agents correctly left
`LinkableEntityType` alone — it contains the target word but was not in the map.
A run where no agent declines anything usually means the map was never actually
constraining them.

Dispatch mechanics (worktree collisions, scope overflow, silent exits) belong to
`agent-patterns-plugin:parallel-agent-dispatch`; the rename map is the
sweep-specific payload you hand it.

## Brief Adversarial Auditors With the Artifact's Purpose, Not Just the Transform

When adversarial or verification agents audit a sweep, a prompt containing only
the transform contract — "rename X to Y across these files" — gives them no way
to tell a deliberate change from scope creep. So they flag the change's own
reason for existing.

Every auditor prompt needs **both**:

| Brief the auditor with | Because without it |
|---|---|
| The transform contract (rename map + do-NOT-rename list) | It cannot check the sweep did what was agreed |
| What the artifact is **for**, and what is deliberately in scope | It reports the PR's central purpose as unjustified scope creep |

In the thelma sweep above, all three auditors flagged the PR's central purpose
that way, and **10 of 25 findings were false positives** traceable to that one
omission — expensive to triage precisely because each read as a legitimate
concern.

See `agent-patterns-plugin:adversarial-review` for the review pass itself; this
is the sweep-specific brief to attach to it.

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
- `agent-patterns-plugin:parallel-agent-dispatch` — the dispatch contract a fanned-out sweep rides on; the rename map is the payload you brief into it
- `agent-patterns-plugin:adversarial-review` — the audit pass; brief it with the artifact's purpose, not only the transform contract

# /blueprint:story-audit Reference

Detailed templates, heuristics, and edge-case behaviour for `/blueprint:story-audit`.

## Audit Template

The audit artifact is a single markdown file under `docs/blueprint/audits/<YYYY-MM-DD>-story-audit.md`. Use this skeleton verbatim — adjust counts, scope, and timestamps; do not invent additional sections.

```markdown
# Story Audit — <YYYY-MM-DD>

**Scope**: <full repo | --scope <area>>
**PRDs read**: <list of PRD paths>
**Tier cutoff**: <which capability `kind` values were treated as "core">
**Manifest run**: docs/blueprint/manifest.json#task_registry.story-audit

## 1. Summary

- Capabilities mapped: **<N>**
- Explicit stories (from PRD): **<N>**
- Candidate stories (code-only): **<N>**
- Drift entries: **<N>** (✅ <a> / ⚠️ <b> / ❌ <c> / 🆕 <d>)
- Stories with zero tests: **<N>**
- Tier-1 gaps: **<N>**
- Bugs surfaced by audit: **<N>**

> Headline: <one sentence the team should walk away with>

## 2. Capability Map

### <Area>

| Capability | Entry point | Kind | Notes |
|------------|-------------|------|-------|
| <name> | `<file:line>` | route\|cli\|event\|component\|cron\|worker | <edge cases or "—"> |

(Repeat per area. Cap rows per area at ~15; collapse the long tail to `+ N more`.)

## 3. Story Inventory

### Explicit (from PRD)

| ID | PRD | Story | Linked deps |
|----|-----|-------|-------------|
| FR-1.1 | PRD-001 | <verbatim> | <if PRD names dependencies> |

### Candidate (code-only — awaiting promotion)

| Capability | Entry point | Why this looks like a story |
|------------|-------------|-----------------------------|
| <name> | `<file:line>` | <route/event-handler/component evidence> |

> Candidates are **not** PRD entries. Promote via `/blueprint:story-reconcile`.

## 4. Drift Report

| Status | PRD ref | Capability | Evidence |
|--------|---------|------------|----------|
| ✅ implemented | FR-1.1 | <name> | `<file:line>` |
| ⚠️ partial | FR-1.2 | <name> | <what's missing> |
| ❌ missing | FR-2.3 | <name> | "tesseract listed in package.json but never imported" |
| 🆕 candidate | — | <name> | `<file:line>` (no matching PRD entry) |

Group by status; sort within group by area.

## 5. Coverage Matrix

| Story | Linked tests | Test count | Skipped/todo | Confidence |
|-------|--------------|------------|--------------|------------|
| FR-1.1 | tests/auth/login.test.ts | 12 | 0 | ✓ |
| FR-2.1 | (none) | 0 | 0 | ✗ |
| FR-3.4 | tests/integration/checkout.test.ts | 4 | 1 | ~ |

Confidence column legend: `✓` explicit story-id reference, `~` keyword/path overlap only, `✗` no match.

## 6. Tiered Gap Analysis

### Tier 1 — Critical untested

> Core capabilities (state machines, auth, payment paths, event handlers) with **zero** matching tests.

- [ ] FR-2.1: <story> — `<entry-point file:line>`
- [ ] …

### Tier 2 — Partial coverage

> Core capabilities with only `~`-confidence matches (likely unit-only, no integration).

- [ ] FR-3.4: <story> — `<entry-point>`

### Tier 3 — Declared drift

> ❌ PRD entries with no implementation.

- [ ] FR-2.3: <story> — declared dependency: `tesseract` (never imported)

### Tier 4 — Implicit candidates

> 🆕 Code-only features awaiting story promotion.

- [ ] <capability> — `<entry-point>`

### Tier 5 — Healthy (reference)

> Stories with `✅` + `✓` test confidence. Use these as the model for new tests.

- FR-1.1, FR-1.2, …

## 7. Bugs Surfaced by Audit

(Omit this section entirely if no bugs were surfaced.)

| Source | Evidence | Description |
|--------|----------|-------------|
| `tests/image/detect.test.ts:42` (test.todo) | "detector returns full frame for every input" | Image detector never actually segments — every call returns one region equal to the whole frame. |
| `client/store.ts:88` (xit) | "ignores photos:detected event" | Store handler missing for three server-emitted events. |

> File issues for any of these via `gh issue create` — the audit deliberately does **not** auto-file.
```

## Implicit-Story Heuristics by Stack

When Agent 1 maps capabilities, use these patterns to decide whether a code construct is a candidate user story.

### TypeScript / JavaScript

| Construct | How to find it | Treat as story? |
|-----------|---------------|-----------------|
| Express/Fastify/Hono routes | `app.{get,post,put,patch,delete}(` | Yes — every route is a story candidate |
| Next.js App Router | `app/**/page.tsx`, `app/**/route.ts` | Yes — pages are stories, route handlers are stories |
| React components exported from `pages/` or `app/` | `export default function …Page` | Yes |
| React components exported from `components/` | `export …` | Only if no parent page wraps them — internal components don't earn a story |
| Socket.IO event handlers | `socket.on('<event>'` | Yes — each event name is a story |
| BullMQ / Sidekiq workers | `new Worker(`, `Queue.add(` | Yes |
| Cron entries | `cron.schedule(`, `node-cron` | Yes |
| Middleware | `app.use(` | No — middleware isn't a story; surface as edge-case note on the route it guards |

### Python

| Construct | How to find it | Treat as story? |
|-----------|---------------|-----------------|
| FastAPI/Flask routes | `@app.{get,post,…}`, `@router.…` | Yes |
| Django views | `class …View`, `def …(request, …)` in `views.py` | Yes |
| Celery tasks | `@app.task`, `@celery.task` | Yes |
| Click/Typer CLI commands | `@app.command()`, `@click.command()` | Yes |
| Management commands | `BaseCommand` subclass | Yes |
| Signal handlers | `@receiver(`, `connect(` | Sometimes — only when the signal is named in PRD vocabulary |

### Go

| Construct | How to find it | Treat as story? |
|-----------|---------------|-----------------|
| HTTP handlers | `http.HandleFunc`, `mux.Handle` | Yes |
| gRPC services | `pb.Register…Server` | Yes — each method is a story |
| Cobra CLI commands | `&cobra.Command{` | Yes |

### Rust

| Construct | How to find it | Treat as story? |
|-----------|---------------|-----------------|
| Axum/Actix routes | `Router::new().route(`, `web::resource(` | Yes |
| Clap subcommands | `#[derive(Subcommand)]` | Yes |

### Generic

For any stack, also list:
- **Public CLI entrypoints** declared in `package.json#bin`, `pyproject.toml#scripts`, `Cargo.toml#[[bin]]`, `go.mod` main packages
- **Public API surface** declared in OpenAPI/protobuf/GraphQL schemas
- **Top-level event types** declared in shared event schemas

## Tier-Ranking Rationale

The default tiering (1 = critical untested, 5 = healthy) is opinionated but tunable. Use these signals when deciding the cutoff between "core" and "non-core" capabilities:

| Signal | "Core" weight |
|--------|---------------|
| Capability `kind` is `route` or `event-handler` | High |
| Capability is named in a PRD with `priority: P0` / `must-have` | High |
| Capability has more than one entry point (called from multiple places) | Medium |
| Capability is a leaf component reachable from one parent only | Low |
| Capability is a CLI subcommand reachable only via flag | Low |

When in doubt, lean toward Tier 1. The cost of an over-eager tier-1 entry is a low-value test; the cost of a missed tier-1 entry is a real production bug.

## Edge Cases

| Situation | Behaviour |
|-----------|-----------|
| No PRD found | Emit Sections 1, 2, 3 (candidate-only), 5 (no story column), 6 (Tier 4 only). Note the missing input prominently. |
| No tests found | Emit Sections 1–4 normally; Section 5 has every story at confidence `✗`; Tier 1 is the full core list. |
| Multiple PRDs (monorepo / multi-feature) | Run Step 2 once per PRD; merge into one inventory; preserve PRD-id column. |
| `--scope` matches no capabilities | Don't fail; emit an audit with empty Sections 2–6 and a note explaining the scope filter excluded everything. |
| Audit file already exists for today | Append `-2`, `-3`, … to the filename. Never overwrite. |
| Project uses no recognised test framework | Mark Section 5 entirely as `?`; note the missing convention. |

## Why this artifact, not many

ScanSift's pre-skill version produced a half-dozen sub-reports that each made sense individually but no one read in sequence. The forced single-artifact constraint — one file, top-to-bottom, every section — is what made it act-on-able. Resist the urge to split this into sub-files.

## Related Skills

- `/blueprint:story-reconcile` — promotes drift entries from this artifact back into the PRD (Phase 2)
- `/blueprint:work-order` — packages a Tier-1 gap as an isolated subagent task (Phase 3)
- `/blueprint:derive-tests` — git-history-based test backlog; complementary but operates on commits, not stories
- `/blueprint:adr-validate` — orthogonal: validates ADR relationships, not story coverage

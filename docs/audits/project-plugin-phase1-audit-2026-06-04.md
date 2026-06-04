# project-plugin Phase 1 audit — 2026-06-04

Read-only audit deliverable for Phase 1 of `docs/session-plugin-workflow.md`.
Source: general-purpose audit agent. No edits made; this is findings only.

Remediation tracked in: https://github.com/laurigates/claude-plugins/issues/1503

## Tooling results

- `plugin-compliance-check.sh` (exit 0): project-plugin all-green except **Size ⚠️**
  (only `changelog-review` at 258 lines). No frontmatter / description / bash-pattern
  / when-to-use failures.
- `audit-skill-descriptions.py`: every skill `[OK]` on trigger axis, none in any
  length WARN/ERROR band.

Static tooling is largely blind to the real drift (dead doc references, wrong
paths, broad `Bash`) — those are manual findings below.

## A. Confirmed drift

| Issue | file:line | Evidence | Severity |
|---|---|---|---|
| README documents 3 phantom skills | README.md:25 (`/project:new`), :45 (`/project:modernize`), :68 (`/project:modernize-exp`) | No such skill dirs; plugin.json:14 still advertises `modernization` | High |
| README + skills reference dead `/blueprint:generate-commands` | README.md:87,104,256; blueprint-development/SKILL.md:88 | Removed in blueprint v3.0→v3.1 (CHANGELOG.md:418, "remove deprecated generate-commands #292"). The "generated to `.claude/skills/...`" workflow is dead | High |
| project-continue wrong PRD path | project-continue/SKILL.md:42 | `.claude/blueprints/prds/` → canonical `docs/prds/` (blueprint-init:170,199; blueprint-status:43). `.claude/blueprints/` is deprecated v1.x/v2.x | High |
| project-continue wrong work-orders path | project-continue/SKILL.md:47 | `.claude/blueprints/work-orders/` → canonical `docs/blueprint/work-orders/` (blueprint-init:175; blueprint-status:50,107) | High |
| project-continue feature-tracker path CORRECT | project-continue/SKILL.md:44 | `docs/blueprint/feature-tracker.json` matches canonical — leave it | OK |
| Broad `Bash` in project-continue | project-continue/SKILL.md:5 | `Read, Bash, Grep, Glob, Edit, Write`; body only uses git status/log/branch → narrow `Bash(git status *), Bash(git log *), Bash(git branch *)` | Medium |
| Broad `Bash` in project-test-loop | project-test-loop/SKILL.md:5 | `Read, Edit, Bash` — loosest grant | Medium |
| `Bash(ls *),Bash(find *),Bash(wc *)` in project-discovery | project-discovery/SKILL.md:8 | Violates bash-tool-replacements; body hand-codes `ls\|grep`/`find`/`head -50` (:118-132). `discover.sh` script path is recommended → move under `Bash(bash *)` | Medium |
| Stale `reviewed:` dates (today 2026-06-04) | project-skill-scripts:9 (2026-02-14); project-distill:9 (2026-02-26); changelog-review:8, project-continue:8, project-init:5, project-test-loop:8 (2026-04-25) | project-discovery freshest (2026-05-09) | Low |
| project-init dead slash-command refs (bonus) | project-init/SKILL.md:177-185 (`/setup:new-project`), :201 (`/git:smartcommit`); README :212,259,262 (`/git:quickpr`,`/github:quickpr`,`/lint:check`,`/docs:docs`) | All NOT FOUND. Existing OK: `/deps:install`,`/test:setup/quick/full`,`/blueprint:work-order` | Medium |
| project-init gh flag bug (bonus) | project-init/SKILL.md:193 | `gh repo create $1 ${4:+--private} --public --clone` → passes both `--private` and `--public` when `--private` set; gh rejects conflicting visibility | Low |

## B. Per-skill compliance

| Skill | Lines (band) | Desc | reviewed staleness | allowed-tools | bash-tool-replacements |
|---|---|---|---|---|---|
| changelog-review | 258 (WARN) | OK | 2026-04-25 | OK narrow | body `cat\|jq` :99 |
| project-continue | 144 (OK) | OK | 2026-04-25 | broad Bash :5 | broad grant |
| project-discovery | 149 (OK) | OK | 2026-05-09 | `ls/find/wc` :8 | yes (:118-132) |
| project-distill | 99 (OK) | OK | 2026-02-26 (stale) | OK narrow | none |
| project-init | 211 (OK) | OK | 2026-04-25 | mostly narrow | dead cmds + gh bug |
| project-skill-scripts | 137 (OK) | OK | 2026-02-14 (most stale) | OK narrow | none |
| project-test-loop | 183 (OK) | OK | 2026-04-25 | broad Bash :5 | detected test cmd |

## C. project↔blueprint when-to-use matrix

| Skill | Blueprint-coupled? | Overlapping blueprint skill | Boundary |
|---|---|---|---|
| project-init | Independent | blueprint-init | project-init = filesystem skeleton of a NEW repo; blueprint-init = `docs/blueprint/` planning layer in an EXISTING repo. They compose. |
| project-continue | **COUPLED (hard)** | blueprint-execute | Both answer "what's next?". project-continue = resume with TDD bias; blueprint-execute = blueprint picks/routes next governed action. The user's confusion is real overlap. Cross-ref (or eventual consolidation); broken paths must be fixed to even function. |
| project-test-loop | Independent | testing-plugin:test-run/quick (not blueprint) | project-test-loop = iterate to green (RED→GREEN→REFACTOR, --max-cycles); testing-plugin = run once + report. |
| project-discovery | Independent | — | Orientation for unfamiliar codebase; no blueprint artifacts. |
| project-skill-scripts | Independent (meta) | — | Operates on this plugin repo's skills; arguably belongs in a plugin-dev/meta surface, not project-plugin. |
| project-distill | Independent (session-meta) | — | **D1: moving to session-plugin.** |
| changelog-review | Independent (meta) | — | Reviews Claude Code releases for plugin impact. |

Net: only project-continue is genuinely blueprint-coupled. project-init reads as a peer of blueprint-init but is functionally distinct.

## D. Prioritized remediation checklist

P1 = fix-in-place now; P2 = after D1 distill move; BLOCKED-BY-D1 = don't fix-then-move.

**README rewrite (P1):**
1. Delete 3 phantom-skill sections (README:25,45,68); drop `modernization` keyword (plugin.json:14) + Modernization/Dependencies/Best-Practices blocks (:45-69,217-243).
2. Remove dead `/blueprint:generate-commands` refs + "generated to .claude/skills" notes (README:87,104,256).
3. Fix cross-plugin command names: `/git:smartcommit`→`/git:commit`; drop `/git:quickpr`+`/github:quickpr`→`/git:pr`; drop `/lint:check`+`/docs:docs`. Keep verified `/deps:install`,`/test:*`,`/blueprint:work-order`.

**project-continue (P1 — must fix to function):**
4. PRD path `.claude/blueprints/prds/` → `docs/prds/` (:42).
5. Work-orders path → `docs/blueprint/work-orders/` (:47). Leave feature-tracker (:44).
6. Narrow allowed-tools → `Bash(git status *), Bash(git log *), Bash(git branch *)` (:5).
7. Add When-to-Use row pointing at `/blueprint:execute` (by plugin:skill name).

**project-discovery & project-init (P1):**
8. project-discovery: move shell utils under `Bash(bash *)` (discover.sh exists); drop `Bash(ls/find/wc *)`; trim hand-coded ls/find/head (:118-132).
9. project-init: fix gh conflicting-visibility bug (:193); remove dead `/setup:new-project` (:177-185).
10. Bump `reviewed:` to 2026-06-04 on any skill touched.

**Size (P1, advisory):**
11. changelog-review: extract report-format/version JSON (:76-92,178-220) to REFERENCE.md.

**Deferred:**
12. [BLOCKED-BY-D1] project-distill: defer all touch-ups to the Phase-2 move into session-plugin (already lint-clean; fixing now = churn the move discards). Exception: leave its README section in place until the move.
13. [P2] After the move: update README Skills list + sibling cross-refs naming project-distill (skill-consolidation checklist).

Sequencing: steps 1-11 are independent of D1 → one `fix(project-plugin): ...` PR (+ README portion as docs). Steps 12-13 wait for Phase 2.

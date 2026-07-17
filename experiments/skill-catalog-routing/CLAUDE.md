# CLAUDE.md

## What this is

`skill-catalog-routing` is an **A/B testing harness for skill discovery**. It
measures whether giving a model the concatenated `name + description` catalog of
every skill helps it **route** a user request to the correct skill, and how short
those descriptions can be while still working. It runs `claude -p` under a
catalog-free `--system-prompt-file` with a varying amount of catalog injected,
captures stream-JSON, and scores the router's decision **deterministically**
(skill-id match — no LLM judge). See `README.md` for the arm ladder and metrics.

It lives under `experiments/` deliberately. It is **not a plugin** — not in
`.claude-plugin/marketplace.json`, not versioned by release-please, not scanned
by plugin-compliance. The parent repo conventions (`../../CLAUDE.md`) still
apply; the plugin lifecycle does not. Commit scope: `skill-catalog-routing`
(matches no release-please package, so work here never triggers a release).

## Architecture — the pipeline

```
SKILL.md frontmatter ─► build-catalogs.py ─► catalogs/catalog.{names,short,medium,full}.json (committed)
                                                            │
conditions.yaml (model × catalog) ─┐                        │  build-arm-prompt.sh
tasks/*.yaml (prompt + gold) ──────┴─► run-suite.sh ─► run-one.sh ─► claude -p (stream-json)
                                                            │            ─► results/<run>/<task>.<cond>.runN.jsonl
                                              score-run.py (parse last JSON, id↔gold) ◄─┘
                                                            │
                              compare.py ─► results.json + report.md ─► render-frontier.py ─► frontier.md
```

## Non-obvious invariants (read before touching the harness)

- **Catalog-free system prompt is load-bearing.** `--system-prompt-file`
  *replaces* the built-in prompt, stripping Claude Code's own ~22k skill listing.
  If any arm leaked the built-in listing, the whole comparison would be
  meaningless. `run-one.sh` asserts the null (C0) arm carries no catalog body.
- **Neutral cwd is load-bearing.** `run-one.sh` runs `claude` from a fresh
  `mktemp -d`, NOT the plugins repo — otherwise the repo's own `CLAUDE.md` and
  rules (which name many skills) load from cwd and contaminate every arm.
  Measured: repo-cwd base ~50k tokens vs neutral-cwd base ~23k. The residual 23k
  is the user's global `~/.claude` memory — a fixed additive constant across all
  arms, so it cannot confound the *relative* catalog comparison (mild
  external-validity caveat only).
- **Root sandbox needs `IS_SANDBOX=1`.** `--dangerously-skip-permissions` refuses
  to run as root without it; the router calls no tools, so this only keeps the
  turn non-interactive. `</dev/null` stops the CLI waiting on stdin.
- **Grade the last JSON line, not the preamble.** A low-effort model emits a
  reasoning preamble before the decision; `score-run.py` parses only the LAST
  JSON object with a `skill` key (claude-probe's hard-won discipline). The router
  system prompt and a constant task-framing wrapper (added in `run-one.sh`) force
  the JSON-only contract — without them, models slip into doing the task or
  asking questions (observed: haiku on the first smoke test).
- **Shortening is structure-aware, never end-truncation.** Descriptions are
  `<domain>. Use when <triggers>.` — the routing-relevant triggers sit at the
  END. `build-catalogs.py` locates the `Use when` clause and truncates THAT,
  always keeping the literal `Use when` (issue #1278 class). `--validate` asserts
  every band keeps `Use when`, respects its char ceiling, and that short ⊆ medium
  (a genuine token-subset). Re-run and re-validate after any change.
- **The leakage gate is the study's key instrument.** `check-tasks.py` flags any
  task whose prompt echoes its gold skill's distinctive NAME tokens
  (`name_overlap` ≥ 0.34 WARN, ≥ 0.5 ERROR). If tasks leak names, names-only (C1)
  wins by string overlap and description length stops mattering — the experiment
  measures nothing. Keep the whole set at `name_overlap = 0.0`.
- **The pilot IS the validity gate.** If haiku C4 ≈ C1 across the pilot subset,
  the task set is too leaky/easy — fix the tasks before spending on the full
  sweep. Do not promote to sonnet/opus until the haiku curve is clean and
  monotone.

## Cost discipline

Every run is a real `claude -p` call; the full matrix is 15 arms × 70 tasks × N
runs. Gate it: haiku pilot (2 arms × 20 tasks × 3) → haiku full ladder → sonnet +
opus. Effort is fixed `low`. Same-arm calls reuse a cached system prompt, so cost
falls sharply after the first call per arm. `results/` is gitignored; the durable
artifacts are `catalogs/`, `tasks/`, the scripts, and any findings written up in
this directory.

## Commits

Use `skill-catalog-routing` as the conventional-commit scope
(`feat(skill-catalog-routing): …`, `chore(skill-catalog-routing): …`).

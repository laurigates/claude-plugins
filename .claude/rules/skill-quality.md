---
created: 2026-03-02
modified: 2026-07-27
reviewed: 2026-07-27
paths:
  - "**/skills/**"
  - "**/SKILL.md"
---

# Skill Quality Standards

Quality standards for maintaining effective, discoverable skills.

## Size Limits

The cost a `SKILL.md` body imposes once it loads is **tokens**, not lines. Lines are a poor proxy: across this repo `chars/line` ranges ~19–69 (a 3.6× spread), so two skills at the same line count can differ 2–3× in tokens — a 416-line file of dense tables (`configure-claude-plugins`, ~5,970 tokens) outweighs a 491-line file of prose. We therefore gate on **characters** (decoded UTF-8, not bytes), the cheapest tight proxy for tokens (~4 chars/token for English prose), and report an estimated token count (chars / 4 — the same convention used for the description budget below).

| Characters | ~Tokens | Severity | Action |
|------------|---------|----------|--------|
| ≤ 10,000 | ≤ 2,500 | OK | silent |
| 10,001 – 26,000 | 2,500 – 6,500 | WARN | ⚠️ in compliance table; review for `REFERENCE.md` / `scripts/` extraction |
| > 26,000 | > 6,500 | ERROR | ❌ blocks commit; must extract before merge |

**Anthropic's published guideline** ([skill-authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)): *"Keep SKILL.md body under 500 lines for optimal performance"* — stated under a heading literally titled **"Token budgets,"** confirming lines are Anthropic's human-graspable stand-in for the real token cost. Our **26,000-char ceiling** ≈ that 500-line guidance at this repo's median line density (~34 chars/line), expressed in the tighter proxy.

**Local hard ceiling**: 26,000 chars / ~6,500 tokens (enforced by `scripts/plugin-compliance-check.sh` `check_skill_size()`).

> **Characters, not bytes** (issue [#2135](https://github.com/laurigates/claude-plugins/issues/2135)). `wc -c` counts **bytes**, and a bare `wc -m` counts characters only under a UTF-8 locale — under `C`/`POSIX` it silently falls back to bytes. Every non-ASCII character this repo uses heavily (em-dash `—`, arrows `→`, box-drawing) is 2–3 bytes, so a byte gate tightens the budget by encoding overhead alone, unevenly across skills: `parallel-agent-dispatch` measured 26,024 bytes vs 25,850 characters — an ERROR on 174 bytes of UTF-8 overhead from 87 non-ASCII characters. `check_skill_size()` therefore counts with `python3` (`len(open(f, encoding="utf-8").read())`), which is locale-independent by construction. Use the same method when checking a body by hand; `LC_ALL=C.UTF-8 wc -m` also works where that locale is guaranteed present.

`REFERENCE.md` has no size limit — it is a supporting file loaded on demand.

> **Why not gate on tokens directly?** Tokens are the real cost, but counting them needs Claude's tokenizer (the `count_tokens` API = network + per-file calls), too heavy for a pre-commit/CI lint. Characters track tokens tightly at near-`wc` cost. Lines are kept only as a human reference (they map to scroll length and to `head -N` partial reads), not as the gate.

## Required Sections

> **Demoted 2026-07-26 by [`context-engineering.md`](context-engineering.md).**
> The "When to Use" table is now **recommended where it disambiguates sibling
> skills**, and "Agentic Optimizations" is **optional**. Measurement:
> `When to Use` costs ~70K tokens across 407 skills (9.2% of all body mass) for
> guidance Anthropic's Claude 5 context-engineering post locates in the
> `description` field. See
> [`docs/benchmarks/2026-07-context-engineering/`](../../docs/benchmarks/2026-07-context-engineering/) § 5 F2.
> The rest of this section stands.

Every skill SHOULD have:

### 1. "When to Use" Decision Table

Place immediately after the title. Helps Claude decide when to load the skill vs alternatives.

Keep it when two or more sibling skills could plausibly match the same intent —
that disambiguation is what the judges credited it for. Drop it when the
`description` already carries the trigger and no sibling competes.

```markdown
## When to Use This Skill

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Specific scenario A | Alternative scenario |
| Specific scenario B | Alternative scenario |
```

### 2. Agentic Optimizations Table

Place near the end. Provides compact commands optimized for AI workflows.

```markdown
## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick check | `tool --compact-flag` |
| CI mode | `tool --reporter=json` |
| Errors only | `tool --errors-only` |
```

### 3. Supporting File Link (if REFERENCE.md exists)

Use proper markdown link format so Claude knows what the file contains:

```markdown
For detailed X, Y, and Z patterns, see [REFERENCE.md](REFERENCE.md).
```

## Writing Style

Use **positive guidance** - describe what to do, not what to avoid. This reinforces correct patterns instead of drawing attention to incorrect ones.

| Instead of | Write |
|------------|-------|
| "Do not use broad permissions" | "Use granular permissions" |
| "Avoid ls with globs" | "Use find for file discovery" |
| "Never edit CHANGELOG manually" | "Use conventional commits to update changelog" |

## Description Quality

Descriptions must match real user intents. They are loaded into Claude's context for skill selection.

**Tool-centric** (less effective):
```yaml
description: AST-based code search using ast-grep for structural pattern matching
```

**Intent-matching, length-aware** (effective):
```yaml
description: ast-grep structural code search/rewrite. Use when matching code by AST, refactoring signatures across files, or detecting anti-patterns.
```

The example above is **140 chars**. Front-loads the tool name and the matching verbs (`structural code search/rewrite`, `matching code by AST`, `refactoring signatures`, `detecting anti-patterns`) so trigger keywords survive truncation.

### Description Checklist
- [ ] Describes what the user can accomplish (not just the tool name)
- [ ] Includes "Use when..." clause with specific scenarios
- [ ] Mentions common trigger phrases users would say
- [ ] Distinguishes from related skills
- [ ] Is a string type (non-string values cause a crash)
- [ ] Length within target band (see below)
- [ ] Trigger keywords appear in the first ~120 chars

## Description Length and the Listing Budget

Every enabled skill's `name` + `description` is concatenated into a single block that Claude Code injects into the system prompt at session start. That block is capped by two settings introduced in Claude Code 2.1.129:

| Setting | Default | What it caps |
|---------|---------|--------------|
| `skillListingBudgetFraction` | `0.01` (1%) | Total skill-metadata share of the context window |
| `skillListingMaxDescChars` | `1536` | Per-skill description truncation point |

On a 200K-token context that's ~2,000 tokens for **all** skill metadata combined; on a 1M-token context, ~10,000 tokens. Each listed skill costs ~35 tokens of XML wrapper *plus* `(name + description) / 4` tokens. Once the budget is blown, Claude strips descriptions from the overflow skills — they appear by name only, and `description`-based skill-selection silently degrades.

### Target band

| Length | Verdict |
|--------|---------|
| ≤ 150 chars | Ideal — leaves headroom and survives any per-skill truncation |
| 151 – 200 chars | OK — within budget for typical plugin loadouts |
| 201 – 300 chars | WARN — eats budget faster than it earns invocation accuracy |
| > 300 chars | ERROR — almost always rewordable; rewrite before merge |
| > 1536 chars | Truncated at runtime by `skillListingMaxDescChars` |

The previous "intent-matching" guidance produced 220-char medians across this repo. **Target ~120–150 chars** with trigger keywords front-loaded.

The length band is enforced automatically:

- `scripts/audit-skill-descriptions.py --strict-length` fails on the ERROR band (>300 chars). Wired into `.pre-commit-config.yaml` and the `Plugin: Lint skills` GitHub workflow.
- `scripts/plugin-compliance-check.sh` surfaces WARN (201-300) entries under "Recommendations" so they show up in the compliance review table.
- For a stricter local sweep that fails on WARN too, run `python3 scripts/audit-skill-descriptions.py --strict-length --warn-on-200`.
- To list current offenders without failing: `python3 scripts/audit-skill-descriptions.py --length-category WARN`.

### Front-loading trigger keywords

`skillListingMaxDescChars` truncates from the **end**, so put the words Claude needs for selection at the **start**. Order:

1. **Tool / verb / domain** (first 30 chars) — `gh workflow auto-fix`, `OAuth2 token refresh`, `kubectl rollout diagnosis`
2. **"Use when..." trigger phrases** (next ~60 chars) — concrete user intents, comma-separated
3. **Disambiguation from sibling skills** (last ~30 chars) — only if needed

| Anti-pattern | Better |
|---|---|
| `Comprehensive guide to ast-grep including installation, usage, common patterns, and integration with editor tooling for structural code search and refactoring across large codebases.` (180 chars, keywords late) | `ast-grep structural code search/rewrite. Use when refactoring signatures across files, finding AST patterns, detecting anti-patterns.` (135 chars, keywords first) |

### Why this matters for plugin authors

A plugin with 35 skills × 220 chars consumes ~3,100 tokens on its own — already over a default 200K-context budget before the user enables any other plugin. Tightening to 130 chars cuts that to ~1,950 tokens, leaving headroom for the user's other plugins. See [`skill-listing-budget`](https://claudefa.st/blog/guide/mechanics/skill-listing-budget) for the upstream rationale.

### `disable-model-invocation` Field

Set `disable-model-invocation: true` when the skill body is a complete, self-contained prompt that should be passed directly without additional model reasoning. Useful for skills that are fully deterministic templates.

## Model Selection

Skills inherit the user's active model by default. Set `model:` only at the **extremes** — see `.claude/rules/skill-development.md` for the full rationale.

| Model | Use For |
|-------|---------|
| `opus` | Deep reasoning, architecture decisions, debugging methodology, security analysis, complex code review, long agentic orchestration |
| `sonnet` | Mechanical / high-volume tasks where Opus is overkill — CLI tool wrappers, formatters, status checks, single-file lookups |
| _(unset)_ | Everything in the middle — let the user's active model decide |

**Sonnet is the floor.** `model: haiku` is disallowed: Haiku 4.5 does not reliably format `AskUserQuestion` tool calls and the cost savings vs Sonnet are modest for the quality risk. The lint check in `plugin-compliance-check.sh` errors on `model: haiku`.

## Supporting Files Pattern

```
my-skill/
├── SKILL.md           # Core instructions (≤ 26,000 chars / ~6,500 tokens)
├── REFERENCE.md       # Detailed reference (loaded on demand)
├── examples.md        # Usage examples (optional)
└── scripts/           # Helper scripts (optional)
```

### What Goes Where

| In SKILL.md (always loaded) | In REFERENCE.md (on demand) |
|-----------------------------|----------------------------|
| Installation / setup | Full configuration options |
| 5-10 most common commands | All flags and options |
| "When to Use" decision guide | Migration guides |
| Quick reference table | Advanced patterns |
| Agentic Optimizations | Editor integrations (non-primary) |
| CI integration basics | Build system integrations |

## Quality Checklist for PRs

When reviewing skill/command changes:

- [ ] SKILL.md body is under 26,000 chars / ~6,500 tokens (target: ≤ 10,000 chars / ~2,500 tokens)
- [ ] Has "When to Use" decision table
- [ ] Has "Agentic Optimizations" table (for CLI/tool skills)
- [ ] Description matches user intents (not just tool jargon)
- [ ] Description ≤ 150 chars with trigger keywords in the first ~120 chars (see "Description Length and the Listing Budget")
- [ ] Model selection follows extremes-only rule (`opus` for deep reasoning, `sonnet` for mechanical tasks, unset otherwise; never `haiku`)
- [ ] Reference material extracted to REFERENCE.md if needed
- [ ] Supporting files referenced with markdown links
- [ ] No duplicate content with sibling skills
- [ ] Frontmatter has all required fields (name, description, allowed-tools)
- [ ] Date fields updated (modified, reviewed)
- [ ] User-invocable skills follow execution structure (see `.claude/rules/skill-execution-structure.md`)
- [ ] PR title follows conventional commit format: `type(scope): subject` (see `.claude/rules/conventional-commits.md`)
- [ ] Commit messages follow conventional commit format with plugin name as scope (e.g., `feat(git-plugin): ...`)

# Software Design Plugin

Software **design methodology** skills — the design-half techniques that decide a
module's shape, contract, and structure *before* (and around) the code is
written. Distilled from *A Philosophy of Software Design*, *Code Complete*, the
Gang of Four, and *Working Effectively with Legacy Code*.

These complement `code-quality-plugin` (which reviews and refactors code that
already exists) by working one level up: interface depth, contracts, pattern
selection, getting legacy code under test, and routine-level decomposition.

## Skills

| Skill | Use when... |
|-------|-------------|
| [`design-deep-modules`](skills/design-deep-modules/SKILL.md) | Designing a module/API and judging whether its interface is deep or shallow |
| [`design-by-contract`](skills/design-by-contract/SKILL.md) | Giving a function/class explicit preconditions, postconditions, invariants, and guard clauses |
| [`design-patterns`](skills/design-patterns/SKILL.md) | A structure resists change and you need the right Gang-of-Four pattern (selected by symptom) |
| [`design-legacy-seams`](skills/design-legacy-seams/SKILL.md) | Changing untested legacy code — find a seam, write characterization tests first |
| [`design-pseudocode`](skills/design-pseudocode/SKILL.md) | Designing a complex routine by stepwise refinement before coding |

Each skill takes an optional `[target]` (file, module, diff, or free-text
description) and applies its lens to that target; with no argument it operates on
the current change.

## How it relates to `code-quality-plugin`

| This plugin (design) | `code-quality-plugin` (existing code) |
|---|---|
| `design-deep-modules` — interface depth | `code-complexity` — function-level metrics |
| `design-by-contract` — *place* checks proactively | `code-hidden-failures` — *detect* swallowed errors |
| `design-patterns` — select a pattern from a symptom | `dry-consolidation` / `code-refactor` — execute the change |
| `design-legacy-seams` — get code under test first | `code-test-quality` — judge the resulting tests |
| `design-pseudocode` — design a routine before coding | `code-review` — review it after |

Cross-plugin references use `plugin:skill` names so they resolve regardless of
which plugins are installed.

## Installation

This plugin is published via the repository's marketplace. Enable it with:

```bash
claude plugin enable software-design-plugin
```

## License

MIT License - See LICENSE file for details.

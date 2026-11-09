---
name: docs-reference-check
description: "Dangling doc-reference gate: flag markdown naming repo paths or relative links that no longer exist. Use when docs cite moved/deleted files, or wiring a doc-drift lint."
allowed-tools: Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/check-doc-references.py *), Bash(cp *), Read, Grep, Glob, Edit, Write, TodoWrite
args: "[--strict] [--chezmoi auto|on|off] [--allow-file <path>] [files...]"
argument-hint: "[--strict] [--chezmoi auto|on|off] [--allow-file <path>] [files...]"
created: 2026-11-09
modified: 2026-11-09
reviewed: 2026-11-09
---

# Dangling Doc-Reference Check

A doc that names `<dir>/deploy.sh` or links `[setup](../setup.md)` after the
file moved still reads as authoritative, and nothing fails. This skill runs a
deterministic, stdlib-only scanner over a repo's tracked markdown and reports
every repo-relative reference that resolves to nothing. It checks existence
only; whether the prose is still *true* is a review question.

## When to Use This Skill

| Use this skill when... | Use instead when... |
|---|---|
| Docs may cite files that were renamed, moved or deleted | Prose claims must stay pinned to specific code symbols: `configure-plugin:configure-surface` (Surface fingerprints) |
| Adding a doc-drift lint to pre-commit or CI | Content leaves for a public destination and links must not escape the export: `documentation-plugin:public-export-sanitization` |
| Cleaning up after a refactor that moved scripts or docs | Auditing PRD/ADR/CLAUDE.md staleness and structure: `code-quality-plugin:code-docs-quality` |
| A chezmoi repo's docs name managed files by their rendered names | A figure or count in a doc may have gone stale: `documentation-plugin:docs-claim-hygiene` |

## What it flags

Precision-first: a gate that cries wolf gets bypassed, so it flags two shapes
only.

| Shape | Flagged when |
|---|---|
| Relative markdown link `[text](path)` | The target resolves neither from the doc's directory nor (for `/path`) from the repo root. URLs, `mailto:`, `#anchors`, templated and placeholder targets are skipped |
| Inline-code path `` `dir/file.ext` `` | Its first segment is a real tracked top-level entry, and it resolves neither from the repo root nor from the doc's directory. `./name` names a repo-root file and is checked |

Not flagged: bare filenames (`deploy.sh`), slash commands, domains, `~/` and
absolute paths, placeholders (`NNNN`, `<name>`, `...`, `example`), and anything
inside fenced code blocks. A token whose first segment is not a top-level entry
(`consumer/scripts/x.sh`) is treated as a path in some other repo.

## Run it

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/check-doc-references.py
```

It scans every tracked `*.md` from the git toplevel of the current directory,
or only the files given as arguments. Output:

```
=== DOC REFERENCE CHECK ===
CHEZMOI_MODE=off
DOCS_CHECKED=41
ALLOWLISTED_PATTERNS=1
DANGLING_COUNT=2
STATUS=WARN
REASON=dangling_ref: docs/setup.md:12 scripts/old.sh (+1 more)
ISSUE_COUNT=2
ISSUES:
  - SEVERITY=WARN TYPE=dangling_ref FILE=docs/setup.md:12 MSG=scripts/old.sh
  - SEVERITY=WARN TYPE=dangling_link FILE=README.md:40 MSG=docs/gone.md
=== END DOC REFERENCE CHECK ===
```

| Mode | Findings report | Exit |
|---|---|---|
| default (advisory) | `STATUS=WARN` | 0 |
| `--strict` | `STATUS=ERROR` | 1 |
| no findings | `STATUS=OK` | 0 |
| not a git repo, or `--allow-file` missing | stderr message | 2 |

`SCANNED_EMPTY=true` appears when no doc was checked, so an empty scan never
reads as a clean one.

## Triage each finding

For every `ISSUES:` row, decide one of:

1. **The file moved**: find its new path (`git log --follow --diff-filter=R`
   or Glob on the basename) and update the reference.
2. **The file is gone for good**: reword or remove the reference.
3. **The doc describes another repo's layout** (a template, a plugin skill
   telling consumers to create `.github/workflows/x.yml`): allowlist the doc.
4. **The doc is an immutable record** (an ADR citing a path accurate when
   written): allowlist it.

Re-run until `STATUS=OK`.

## Allowlist

`.doc-reference-allow` at the repo root (or `--allow-file <path>`): one
`fnmatch` glob per line, matched against the doc's repo-relative path, `#`
comments allowed. A matching doc is skipped whole.

```text
# Immutable records: ADRs cite paths accurate when the decision was made.
docs/adrs/**
# Docs that describe consumer repos, not this one.
templates/**
```

Comment every entry with why it is exempt. A repo whose docs mostly describe
*other* repos' layouts (a plugin marketplace, a project template) needs those
docs allowlisted before the gate is useful there.

## chezmoi mode

In a chezmoi source repo a doc names `<dir>/nudge.sh` while the repo holds
`<dir>/executable_nudge.sh.tmpl`, and `.zshrc` while it holds `dot_zshrc`.
With chezmoi mode on, a path also resolves when a sibling's rendered name
matches (attribute prefixes, `dot_`, and `.tmpl` stripped).

| `--chezmoi` | Effect |
|---|---|
| `auto` (default) | On when the repo root has a `.chezmoi*` marker (`.chezmoiignore`, `.chezmoiroot`, `.chezmoidata.toml`, …) |
| `on` / `off` | Forced |

`CHEZMOI_MODE=` in the output shows which applied.

## Wire it as a gate

A plugin's path is not available in CI or to other contributors, so copy the
script into the repo first:

```bash
cp ${CLAUDE_SKILL_DIR}/scripts/check-doc-references.py scripts/check-doc-references.py
```

**Pre-commit (advisory)**: shows findings on every commit and never blocks.

```yaml
- repo: local
  hooks:
    - id: check-doc-references
      name: check docs for dangling references (advisory)
      entry: python3 scripts/check-doc-references.py
      language: system
      pass_filenames: false
      always_run: true
      verbose: true
```

**Lint task (strict)**: the enforcing variant for CI.

```toml
# mise.toml
[tasks."lint:docs"]
run = "python3 scripts/check-doc-references.py --strict"
```

```just
# justfile
lint-docs:
    python3 scripts/check-doc-references.py --strict
```

Get the tree to `STATUS=OK` (fix or allowlist) before turning on `--strict`,
or the first CI run fails on old drift.

## Agentic Optimizations

| Context | Command |
|---|---|
| Whole repo, advisory | `python3 ${CLAUDE_SKILL_DIR}/scripts/check-doc-references.py` |
| Summary lines only | `python3 ${CLAUDE_SKILL_DIR}/scripts/check-doc-references.py \| grep -E '^(STATUS\|REASON\|ISSUE_COUNT)='` |
| Changed docs only | `python3 ${CLAUDE_SKILL_DIR}/scripts/check-doc-references.py <files...>` |
| CI gate | `python3 ${CLAUDE_SKILL_DIR}/scripts/check-doc-references.py --strict` |
| Another checkout | `python3 ${CLAUDE_SKILL_DIR}/scripts/check-doc-references.py --project-dir <repo>` |

---
created: 2026-06-14
modified: 2026-06-14
reviewed: 2026-06-14
description: "Surface doc-drift gate: scaffold surf.toml + hubs, wire the SHA-pinned pre-commit/Action. Use when adding a docs-governed-like-code CI gate."
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebFetch
args: "[--check-only] [--fix] [--pin <tag>]"
argument-hint: "[--check-only] [--fix] [--pin v0.6.2]"
name: configure-surface
language: rust
---

# /configure:surface

Scaffold and harden [Surface](https://github.com/Connorrmcd6/surface) — a deterministic
"documentation governed like code" gate. Surface anchors prose claims to code symbols, stores an
AST-normalized logic fingerprint per symbol, and **blocks CI/commits when the fingerprint drifts**
until a human re-runs `surf verify`. It ignores cosmetic edits and catches flipped operators,
relaxed comparisons, and dropped `await`.

> **⚠️ Experimental — adopt defensively.** As of 2026-06 Surface is a young, single-maintainer
> project (no crates.io publish, bus-factor 1). The engine and release hygiene vetted well, but
> treat it as a pinned, optional gate — never an unpinned dependency. This skill defaults to
> **SHA-pinned** installs and **fail-closed** checksum verification.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Adding a deterministic doc↔code drift gate to CI/pre-commit | Enforcing same-commit doc discipline by convention (`blueprint:blueprint-docs-currency`) |
| You want specific prose claims pinned to specific functions | Detecting stale *generated* content (`blueprint:blueprint-sync`) |
| You want an offline, no-LLM gate that fails the build on logic drift | You want semantic "is the doc still true?" judgment (`code-quality:code-review`) |
| Hardening an existing Surface setup (pin by SHA, verify checksums) | Generating docs from code (`documentation:docs-generate`) |

## Context

- surf.toml: !`find . -maxdepth 2 -name 'surf.toml'`
- Hubs dir: !`find . -maxdepth 2 -type d -name 'hubs'`
- Pre-commit config: !`find . -maxdepth 1 -name '.pre-commit-config.yaml'`
- Workflows: !`find .github/workflows -maxdepth 1 -name '*.yml'`
- Language markers: !`find . -maxdepth 1 \( -name 'Cargo.toml' -o -name 'package.json' -o -name 'pyproject.toml' -o -name 'go.mod' \)`

## Parameters

Parse from `$ARGUMENTS`:

- `--check-only`: Report Surface adoption status and pin hygiene; make no changes (CI mode).
- `--fix`: Apply scaffolding and hardening without prompting.
- `--pin <tag>`: Release tag to install/pin (default: latest stable; resolve its commit SHA before writing any `uses:` ref).

## Execution

Execute this Surface configuration workflow:

### Step 1: Detect current state

From Context, classify the repo:

| Signal | Meaning |
|--------|---------|
| `surf.toml` present | Surface already initialised — go to hardening (Step 5) |
| Hubs dir present, no `surf.toml` | Partial setup — repair |
| Neither | Greenfield — full scaffold |
| Language marker | Surface supports Rust, TypeScript/JS (TSX grammar), Python, Go. Warn if none match — anchors only resolve in supported languages. |

If `--check-only`, report the table and the pin audit from Step 5, then stop.

### Step 2: Confirm the maturity trade-off

Before writing files, surface the experimental posture (the blockquote above) and confirm with
`AskUserQuestion` unless `--fix` is set: adopt as a **pinned optional gate** (recommended) or skip.
Record the chosen pin tag.

### Step 3: Resolve the pinned ref

Resolve the chosen tag to an immutable commit SHA so every `uses:` and `rev:` is reproducible:

```bash
git ls-remote https://github.com/Connorrmcd6/surface refs/tags/<tag>
```

Land the Action ref as `Connorrmcd6/surface@<sha> # <tag>` and the pre-commit `rev:` as `<tag>`
(github-tags datasource — Renovate manages both; see `.claude/rules/version-pinning.md`). Do **not**
hand-transcribe a SHA from memory.

### Step 4: Scaffold (greenfield)

1. Create `surf.toml`:
   ```toml
   hubs = ["hubs/*.md"]
   ```
2. Create `hubs/` with one starter hub anchoring a real, stable symbol the team relies on. Hub shape:
   ```markdown
   ---
   summary: One-line description of what this hub governs.
   anchors:
     - claim: >
         The prose claim about behaviour that must stay true.
       at: src/path/file.ts > symbolName
       hash: ""   # surf verify seals this after you confirm the prose
   refs: []
   ---

   # Title

   Longer explanation a reviewer reads when the gate flags drift.
   ```
3. Run `surf lint` (every anchor resolves to exactly one symbol), then `surf verify` to seal hashes.

### Step 5: Wire + harden the gates

**Pre-commit** — add to `.pre-commit-config.yaml` (requires `surf` on PATH; pair with
`/configure:web-session` to install it in Claude Code web sessions):

```yaml
- repo: https://github.com/Connorrmcd6/surface
  rev: v0.6.2   # --pin tag; Renovate-managed (github-tags)
  hooks:
    - id: surf-lint   # anchors resolve
    - id: surf-check  # the gate — blocks on drift
```

**GitHub Action** — scaffold `.github/workflows/` with a **SHA-pinned** ref:

```yaml
name: "Docs: Surface drift gate"
on: [pull_request]
jobs:
  surface:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
      - uses: Connorrmcd6/surface@004c9169f182fb5e577d389749e6447521e6e6aa # v0.6.2
        with:
          args: check
```

> **Residual supply-chain caveat (track upstream).** Even when the Action is SHA-pinned, Surface's
> `action.yml` currently pipes `install.sh` from the **`main`** branch
> (`raw.githubusercontent.com/.../main/install.sh`) rather than the pinned ref — so a compromised
> `main` reaches pinned consumers. The download is checksum-verified (fail-closed), which bounds the
> risk, but the *installer script* itself is unpinned. Until the upstream fix (use
> `${{ github.action_path }}/install.sh`) lands, the maximally-cautious option is to **vendor**
> `install.sh` at the pinned ref into your repo and run that. See the issue/PR this skill links in
> "Upstream contributions".

### Step 6: Document the JSON → reviewer handoff

Surface keeps semantic judgment out of its deterministic core and emits JSON for reviewer plugins
(`surf check --format json`). Note in the repo (e.g. CONTRIBUTING or the workflow) that a drift
verdict can be handed to `code-quality:code-review` / `verify` to judge whether the claim is still
*true* before a human runs `surf verify`. That is the division of labour Surface is designed for and
where our skills add the most value.

### Step 7: Report

Print: scaffold actions taken, the resolved pin (`<sha> # <tag>`), pre-commit + Action wiring status,
and the hardening checklist below with each item ✓/✗.

## Hardening checklist

| Control | Target state |
|---------|-------------|
| Action ref | SHA-pinned with `# <tag>` comment, not a floating major |
| Installer | Checksum-verified (default) or vendored at the pinned ref |
| Pin freshness | `rev:` / `uses:` Renovate-visible (github-tags shape) |
| Gate scope | `surf check --base <ref>` to diff-scope to changed files in CI |
| Fallback | macOS Intel / Windows unsupported — document `cargo install --git` source fallback |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Status + pin audit | `/configure:surface --check-only` |
| Scaffold + harden | `/configure:surface --fix --pin v0.6.2` |
| The gate (CI) | `surf check` |
| Scope to changed files | `surf check --base origin/main` |
| Machine-readable verdict | `surf check --format json` |
| Re-seal after human review | `surf verify` |
| Anchors resolve | `surf lint` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report adoption + pin hygiene without modifying files |
| `--fix` | Apply scaffolding and hardening without prompting |
| `--pin <tag>` | Release tag to install/pin (resolved to a SHA before writing refs) |

## Upstream contributions

This skill tracks two improvements we proposed upstream (the repo is third-party; we cannot file
directly from this marketplace, so the artifacts live with the adopting team):

- **Issue**: `action.yml` fetches `install.sh` from `main`, defeating SHA-pinning for the installer.
- **PR**: run the bundled `${{ github.action_path }}/install.sh` so the installer matches the pinned ref.

## See Also

- `/configure:web-session` — install `surf` in Claude Code web sessions
- `/configure:pre-commit` — pre-commit framework setup this plugs into
- `blueprint:blueprint-docs-currency` — same-commit doc discipline (the convention-level complement)
- `blueprint:blueprint-sync` — drift detection for *generated* content
- `code-quality:code-review` — the semantic reviewer for Surface's JSON verdicts
- Surface docs: https://surface.gradientdev.xyz/ · License: Apache-2.0

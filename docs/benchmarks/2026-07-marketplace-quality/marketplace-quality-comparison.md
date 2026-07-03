# Marketplace Quality Benchmark: laurigates/claude-plugins vs anthropics/claude-plugins-official

*Run date: 2026-07-02/03 · Official pinned @ `4cd126ba` · 9 blind pairs · 2 judges/unit · refuter-verified · quote-gated*

## 1. Executive summary

**Two strong marketplaces optimized for different jobs.** laurigates/claude-plugins is a deep first-party *product monorepo* — it wins on release discipline, eval infrastructure, regression culture, trigger discoverability, context economy, and robustness. anthropics/claude-plugins-official is a curated *directory* — it wins exactly where its model's risks live (supply-chain control of 204 SHA-pinned vendor refs) and, more pointedly for us, **its flagship plugins beat ours on instruction depth in three head-to-head pairs** (security-guidance, mcp-dev, autonomous-loop).

Headline numbers (Tier B, 9 blind pairs × 2 judges × 6 dimensions; medians): ours takes the pair verdict in **5 of 9** (hooks 6-0, pr-commit 6-0, skill-authoring 6-0, session-reporting 5-0-1, code-review 3-2-1), official in **3 of 9** (security-guidance 0-5-1, autonomous-loop, mcp-dev), one even (claude-md). By dimension across pairs, ours leads B1 discoverability (7/9), B3 context economy (6/9), B6 robustness (6/9), B5 safety (5/9); the official side makes B2 instruction quality (4v3) and B4 determinism offload (3v2, 4 ties) genuinely contested. Tier A: ours 4 dimensions, official 1 (supply-chain, their home turf — deliberately included), 1 tie after adversarial adjustment.

Every extreme score was evidence-gated: **231/231 quotes mechanically verified** against staged files, zero fabricated. All 10 selected findings were adversarially re-judged (8 upheld — including two *pro-official* wins — 2 adjusted, both trimming pro-ours margins; none overturned). Read the **Bias & limitations** section before quoting any single number: blinding failed to conceal identity (authors' names ship in the artifacts), and side-A position and pair composition are confounded at n=9.

### Tier B scoreboard — authoring quality (blind, per-pair medians)

| Dimension | Pair wins (ours / official / tie) | Mean median ours | Mean median official |
|---|---|---|---|
| **B1 Trigger & discoverability** | 7 / 1 / 1 | 4.72 | 3.44 |
| **B2 Instruction quality** | 4 / 3 / 2 | 4.17 | 4.28 |
| **B3 Context economy** | 6 / 3 / 0 | 4.0 | 3.89 |
| **B4 Determinism offload** | 3 / 2 / 4 | 3.94 | 3.89 |
| **B5 Safety & permissions** | 5 / 3 / 1 | 3.89 | 3.67 |
| **B6 Robustness & maintainability** | 6 / 2 / 1 | 3.67 | 3.0 |

### Tier B pair matrix

| Pair | B1 | B2 | B3 | B4 | B5 | B6 | Outcome |
|---|---|---|---|---|---|---|---|
| autonomous-loop | 5v3 ours✓ | 4v4 tie | 3v4.5 offi | 2.5v5 offi✓ | 3v4 offi | 4v3 ours | 2-3-1 → **official** |
| claude-md | 4.5v4 ours~ | 4v4 tie | 3v4 offi | 3v3 tie | 4v4 tie | 3v3 tie | 1-1-4 → **even** |
| code-review | 5v2 ours≊ | 3v5 offi✓ | 3.5v3 ours~ | 3v3 tie | 3v4 offi | 3v2 ours | 3-2-1 → **ours** |
| hooks | 5v4 ours | 5v4 ours | 5v3 ours✓ | 5v4 ours | 5v4 ours | 4v2.5 ours | 6-0-0 → **ours** |
| mcp-dev | 4v5 offi | 3.5v5 offi | 4.5v4 ours~ | 3v3 tie | 4v3.5 ours~ | 3v4.5 offi | 2-3-1 → **official** |
| pr-commit-workflow | 5v3 ours✓ | 4.5v3 ours | 4v3.5 ours~ | 5v3 ours✓ | 4v2.5 ours | 4v2 ours | 6-0-0 → **ours** |
| security-guidance | 4v4 tie | 3.5v5 offi | 3v5 offi | 4v5 offi | 3v4.5 offi | 3v5 offi | 0-5-1 → **official** |
| session-reporting | 5v2 ours✓ | 5v4.5 ours~ | 5v4.5 ours~ | 5v5 tie | 4v3 ours | 4.5v3 ours | 5-0-1 → **ours** |
| skill-authoring | 5v4 ours | 5v4 ours | 5v3.5 ours | 5v4 ours | 5v3.5 ours | 4.5v2 ours✓ | 6-0-0 → **ours** |

Cell = median ours **v** median official + per-dimension winner. ✓ refuter-upheld · ≊ refuter-adjusted · ~ judges split · ? refuter did not run (quota).

### Tier A scoreboard — marketplace infrastructure (open-book)

| Dimension | Median ours | Median official | Verdict | Confidence |
|---|---|---|---|---|
| **A1 Manifest schema & integrity** | 4 | 3.5 | ours | judges split |
| **A2 Validation CI depth** | 5 | 4.5 | ours | judges split |
| **A3 Versioning & release discipline** | 5 | 3.5 | ours | unanimous |
| **A4 Supply-chain & distribution safety** | 4 | 5 | official | unanimous |
| **A5 Docs & navigability** | 3.5 | 3.5 | tie | refuter-adjusted |
| **A6 Governance & eval infrastructure** | 5 | 4 | ours | unanimous |

## 2. Methodology & rubric provenance

**Design.** Two channels, never blended: **Channel M** — one deterministic Python pass over both full trees (byte-identical across runs); **Channel J** — anchored 1–5 judgments, median of 2 independent judges per unit. Tier B (authoring quality, 6 dimensions) judged **blind** on 9 staged overlap pairs (`side-A`/`side-B`, deterministic balanced assignment, blinding manifest withheld from judges). Tier A (infrastructure, 6 dimensions) judged **open-book** per repo. Tier C is descriptive only.

**Rubric provenance.** All scored anchors were frozen *before* judging, derived only from published Anthropic guidance (code.claude.com skills/plugins/plugin-marketplaces/hooks docs, the Agent Skills engineering post) and the official repo's own skill-creator/plugin-dev references. Our house rules were read only to build a 12-item exclusion list (e.g. the literal “Use when” phrasing, `created/modified` dates, char-count gates, `REFERENCE.md` naming — none scored). Full rubric: `bench/rubric.md`.

**Anti-bias machinery.** Independent-then-compare scoring (each side scored against anchors before comparison); every extreme score (1/2/4/5) requires a verbatim quote, mechanically string-matched against staged files (231 checked, 0 failed); refute-prompted verifiers re-judged the 10 highest-stakes findings including a symmetric-standard check; identity leakage self-reported per judgment and published; A/B position bias measured and published.

**Scale.** 32 successful agent runs: 18 blind pair judges + 2 Tier-A judges + 1 rubric derivation + 1 quote-check + 10 adversarial refuters; ~9M subagent tokens including a quota-aborted first wave. Official repo pinned at `4cd126ba` (2026-07-02); ours at working tree of `main` (728bb0c7 era, 2026-07-02).

## 3. Tier A findings

Both Tier-A judges converged on the same shape: *two strong repos optimized for different distribution models*.

**Where ours leads.**
- **A3 Versioning & release (5 v 3.5, unanimous):** full release-please monorepo automation — per-plugin semver, 44 generated changelogs, version synced into each `plugin.json` via `extra-files` jsonpath with zero entry-vs-plugin mismatches, CI-guarded. Official's in-repo plugins are mostly unversioned with no changelogs (their SHA-pin scheme covers *external* refs only).
- **A6 Governance & eval (5 v 4, unanimous):** the decisive anchor-5 evidence was *measured* skill quality: evaluate-plugin's eval cases, deterministic grading, cross-model matrix, cold-read legibility gating, and a golden set (*“The cross-model (Tier-2) canary set. ~15-25 representative, high-traffic, or high-risk skills”*). Official's AI policy scan (`.github/policy/prompt.md`) is strong governance for *intake*, less so for measuring skill effectiveness.
- **A2 Validation CI depth (5 v 4.5, split then reconciled):** 21 workflows incl. semantic gates and a genuine regression culture — 30 `check-*.sh` scripts each pinning a fixed defect, plus per-skill script tests in CI. Official's validation is also semantic (SHA-pin hard errors, license checks, MCP liveness, AI policy scan) and one judge scored it equal; the margin is thin.
- **A1 Manifest integrity (4 v 3.5, split):** both manifests are valid and orphan-free with `$schema`; ours carries version/keywords/category on every entry (official: version on 14/255, author on 170/255), but ours omits author/license in entries and license in 20 of 44 `plugin.json`.

**Where official leads.**
- **A4 Supply-chain (4 v 5, unanimous):** their model carries the maximum risk — 204 external vendor refs — and controls it exceptionally: exact 40-char SHA pins enforced as a **hard validation error**, nightly validated bump automation with tamper-abort revert, MCP URL liveness checks, per-plugin Apache LICENSE enforcement, and a derived-allowlist scope guard that auto-closes out-of-scope external PRs (*“a non-member PR may only ADD marketplace.json entries whose source repo already backs a live plugin here”*). Ours controls the risks it actually has (first-party only, `${CLAUDE_PLUGIN_ROOT}` paths, version-pin coverage checks) — 4, not 5, for lacking license validation across its own components.
- **A5 Docs & navigability — refuter-adjusted to a tie (3.5 v 3.5), with a symmetric-standard violation flagged.** Judges initially split, and the refuter found *both* sides fail the accuracy leg the anchor names: ours claims “Navigation guide for 42 plugins and 300+ skills” (actual: 44/384) and “43 Claude Code plugins” in the README, with no top-level marketplace `description`; official's catalog description is accurate but its per-plugin docs are thinner. The pre-registered stale-docs finding from the exploration phase was independently rediscovered by both judges.

## 4. Tier B pair capsules

### security-guidance

**Outcome: 0-5-1 → official.** Official staged as side-A. Official sources: plugins/security-guidance. Ours: configure-plugin/skills/configure-security, git-plugin/skills/git-security-checks.

The clearest official win (0-5-1). **security-guidance (official)** is production-hardened: near-zero always-loaded context cost, deterministic hook offload with exceptional robustness, a documented trust model and privacy disclosure; its one soft spot is an ungated SessionStart `pip install`. **configure-security + git-security-checks (ours)** has genuine strengths (disambiguation tables, structured-output scripts, a regression test) but is dragged down by **broken dynamic-context commands, in-file duplication, and one bloated always-loaded skill body**.

### autonomous-loop

**Outcome: 2-3-1 → official.** Official staged as side-A. Official sources: plugins/ralph-loop. Ours: project-plugin/skills/project-test-loop, .claude/rules/loop-integrity.md.

Judges found complementary strengths. **ralph-loop (official)** is the engineering-first artifact: a real loop driver (`stop-hook.sh`, capped-input jq parsing — *“Capped at the last 100 assistant lines to keep jq's slurp input bounded”*), tight permissions, lean surface. **project-test-loop + loop-integrity (ours)** is documentation-first: outstanding triggering (*“Use when looping on failing tests, running a TDD cycle”*) and the strongest governance thinking (independent stop conditions), but **zero determinism offload** — the loop is prose the model re-derives, and declared arguments go unused. The B4 2v5 loss was adversarially re-checked and **upheld**.

### mcp-dev

**Outcome: 2-3-1 → official.** Official staged as side-A. Official sources: plugins/mcp-server-dev. Ours: agent-patterns-plugin/skills/mcp-server-authoring, agent-patterns-plugin/skills/mcp-management, agent-patterns-plugin/skills/mcp-code-execution, agent-patterns-plugin/.claude-plugin/plugin.json.

**mcp-server-dev (official)** wins on substance: a deep, procedure-first build path with reasoning throughout (B1/B2/B6), at the cost of one bloated body and a duplicated scaffold. **Our mcp trio** is disciplined and lean — textbook SKILL/REFERENCE splits, explicit least-privilege tool scoping (B5 to ours) — but its instructions are shallower and partly portfolio-bound. 2-3-1 to official.

### code-review

**Outcome: 3-2-1 → ours.** Official staged as side-A. Official sources: plugins/code-review. Ours: code-quality-plugin/skills/code-review, code-quality-plugin/skills/code-review-checklist, agents-plugin/agents/review.md, code-quality-plugin/.claude-plugin/plugin.json, code-quality-plugin/README.md.

A genuine split. **Official's code-review** is the stronger *executable* artifact — exceptional procedural instructions with a verbatim scoring rubric, false-positive re-verification, confidence thresholds (B2 5v3, refuter-**upheld**) — but its command has a near-empty trigger description (B1 2) and a stale README contradicting its own toolset. **Ours (code-quality:code-review + agents review)** is the stronger *catalog citizen*: rich trigger descriptions, sibling disambiguation, complete metadata (B1 refuter-adjusted from 5v2 to 4v2, still ours), with competent but looser instructions. Net 3-2-1 to ours — and the clearest “adopt their instruction depth” signal in the run.

### claude-md

**Outcome: 1-1-4 → even.** Official staged as side-A. Official sources: plugins/claude-md-management. Ours: blueprint-plugin/skills/blueprint-claude-md, agent-patterns-plugin/skills/meta-context-diet.

The closest pair — four ties. **claude-md-management (official)** is a small, clean, well-disclosed plugin (lean body, on-demand references, explicit approval gating) marred by an orphaned duplicate reference file and a nonstandard `tools:` frontmatter key. **blueprint-claude-md + meta-context-diet (ours)** is denser and more reasoning-rich with exemplary trigger disambiguation, but inlines everything (no progressive disclosure in one skill) and references house rules that don't ship with the artifact.

### hooks

**Outcome: 6-0-0 → ours.** Official staged as side-B. Official sources: plugins/hookify. Ours: hooks-plugin.

Clean sweep for **hooks-plugin (ours)**: defense-in-depth safety hooks, deterministic offload backed by real test suites, strong disclosure architecture, exemplary safety gating; its noted weakness is documentation drift (a README section contradicting a script). **hookify (official)** is a well-designed meta-plugin (its rule engine is solid, fail-open by design) but thinner on progressive disclosure, ships no tests, and carries several small consistency defects.

### pr-commit-workflow

**Outcome: 6-0-0 → ours.** Official staged as side-B. Official sources: plugins/pr-review-toolkit, plugins/commit-commands. Ours: git-plugin/skills/git-commit, git-plugin/skills/git-commit-workflow, git-plugin/skills/git-commit-trailers, git-plugin/skills/git-commit-push-pr, git-plugin/skills/git-pr, git-plugin/skills/git-pr-feedback, git-plugin/skills/git-pr-sync-check, git-plugin/skills/git-pr-watch, git-plugin/skills/git-push, git-plugin/skills/git-fix-pr, git-plugin/skills/git-api-pr, git-plugin/skills/git-branch-pr-workflow, git-plugin/skills/github-pr-title, git-plugin/.claude-plugin/plugin.json, git-plugin/README.md, git-plugin/hooks.

**git-plugin's commit/PR suite (ours)** sweeps 6-0: strong triggering with sibling disambiguation (*“Use when user says ‘commit’… see git-push for remote”*), reasoned instructions, tested deterministic scripts, safety-conscious hooks. **pr-review-toolkit + commit-commands (official)** pairs excellent review-agent prompt craft with very thin commit commands and real distribution-hygiene problems — including an **ungated `git worktree remove --force`** in `clean_gone.md` (B5 evidence). The B1 and B4 margins (5v3) were adversarially re-checked and **upheld**.

### session-reporting

**Outcome: 5-0-1 → ours.** Official staged as side-B. Official sources: plugins/session-report. Ours: session-plugin.

**session-plugin (ours)** wins 5-0-1: exemplary triggering and disambiguation across four skills, a shared deterministic collector with tests, gated writes. **session-report (official)** is a well-engineered single skill whose analyzer script is genuinely excellent (*token-accounting dedupe by requestId* — B4 tied at 5v5), but its frontmatter states no trigger conditions and it ships no manifest-level docs or tests.

### skill-authoring

**Outcome: 6-0-0 → ours.** Official staged as side-B. Official sources: plugins/skill-creator, plugins/plugin-dev. Ours: .claude/rules/skill-development.md, .claude/rules/skill-quality.md, .claude/rules/skill-naming.md, .claude/rules/skill-argument-handling.md, .claude/rules/skill-execution-structure.md, evaluate-plugin, project-plugin/skills/project-skill-scripts.

**Ours (evaluate-plugin + skill rules + project-skill-scripts)** wins 6-0 on artifact hygiene: leaner bodies, tighter tool scoping, gated destructive actions, machine-parseable script contracts with tests. **skill-creator + plugin-dev (official)** carries exceptional explain-the-why instruction craft and a genuinely systematic eval loop — but the staged artifacts are dragged down by bloated skill bodies, an unscoped Bash grant, and internal contradictions in hook-development/skill-development (B6 4v2, refuter-**upheld**).


## 5. Tier C — descriptive asymmetries (unscored)

These asymmetries are **deliberately unscored** — they describe different jobs, not different quality.

- **Distribution models.** Ours: 44 in-repo first-party plugins, release-driven. Theirs: a 255-entry curated directory — 51 in-repo (36 first-party plugins + example-plugin + 15 vendored MCP wrappers) + 204 SHA-pinned external refs across 179 vendor repos, freshness governed by nightly automation rather than releases.
- **Archetypes they have that we don't:** 12 LSP-config plugins (inline `lspServers` manifests), 15 vendored MCP-wrapper plugins (some shipping a TS server + bun.lock), and a whole external-vendor intake pipeline (form-based submissions, AI policy scan, scope guards).
- **Archetypes we have that they don't:** deep domain skill suites (configure 51, git 38, blueprint 33, obsidian 21 skills), 75 hook files vs their 17, per-plugin release/changelog machinery, and a self-hosted eval stack (evaluate-plugin) used in CI.
- **Category shape:** theirs skews development/productivity/database (a general-audience directory); ours skews development/infrastructure/ai/quality (a practitioner's toolchain).


| | ours | official |
|---|---|---|
| Marketplace entries | 44 | 255 |
| Source types | 44 in-repo | {"git-subdir": 71, "github": 2, "in-repo": 51, "url": 131} |
| Unique external vendor repos | 0 | 179 |
| LSP-config plugins | 0 | 12 |
| Vendored MCP wrappers (external_plugins/) | 0 | 15 |
| Top categories | ai 4, automation 3, ci-cd 2, communication 2, development 10, documentation 2 | (none) 14, automation 1, database 34, deployment 8, design 6, development 109 |

## 6. Bias & limitations audit

| Bias measurement | Value |
|---|---|
| Judgments with identity leakage | 18/18 (rate 1.0) |
| Mean margin ours−official, leaked judgments | +0.37 |
| Mean margin ours−official, clean judgments | n/a — no clean judgments exist |
| Mean score given to side-A / side-B (identity-blind) | 4.287 / 3.472 |
| Mean margin ours−official when ours staged as A / as B | +1.333 / -0.4 |
| Evidence quotes mechanically verified | 231 checked, 230 exact + 1 normalized, 0 failed |
| Findings dropped for fabricated evidence | 0 |


This benchmark was designed by the maintainer of one of the two repos being compared. The controls below are what keep it honest; read them before quoting any single number.

1. **Blinding failed to conceal identity — leakage rate 1.0 (18/18 judgments).** Both sides ship self-identifying metadata (`"author": "Anthropic"` / `"repository": ...laurigates...`), and judges honestly reported recognizing both sides in every pair. Per the pre-registered design, content was not redacted (redaction mutates the evidence being judged). Consequently the planned leaked-vs-clean score comparison is void — there are no clean judgments. Debiasing therefore rests entirely on: anchors frozen from neutral published sources before any judging; the independent-then-compare protocol; the mechanical quote gate (231/231 verified, 0 fabricated); and adversarial refuters prompted to overturn (which did trim two pro-ours margins and uphold two pro-official wins).
2. **Position and composition are confounded.** Side-A won 7 of 8 decided pairs; the identity-blind mean score was 4.29 for side-A vs 3.47 for side-B; ours' margin was +1.33 when staged as A vs −0.40 as B. With n=9 pairs assigned deterministically (balanced 5/4 but not counterbalanced), a first-position halo cannot be separated from genuinely stronger artifacts happening to sit at A. Both sides won and lost from side-A; the only side-B pair win was ours (code-review). Treat close pairs (claude-md, mcp-dev, autonomous-loop, code-review) as directional; a replication with swapped sides would resolve this.
3. **Pair scoping is judgment-laden.** Ours staged curated subsets for two pairs (13 of git-plugin's 38 skills; 5 rules + evaluate-plugin for skill-authoring); official plugins were staged whole. Subsetting could cut either way (drops weak siblings; loses ecosystem context).
4. **House-convention metrics were excluded from scoring** and appear only in the supplementary table; scored anchors trace to published Anthropic guidance and the official repo's own skill-creator references (see rubric provenance). The rubric's exclusion list names 12 house criteria that were kept out.
5. **Judges and refuters are the same model family as both repos' tooling** (Claude), with training exposure to both projects plausible; the identity-leakage field exists precisely because this cannot be ruled out.
6. **Tier C is descriptive, not scored** — catalog breadth (their 255-entry directory, LSP/MCP archetypes) vs domain-skill depth (our 384 skills) is apples-vs-oranges, and scoring it would launder coverage into quality.

## 7. Takeaways for laurigates/claude-plugins

Ranked by evidence strength × expected value for laurigates/claude-plugins.

**Adopt**
1. **Fix the A5 accuracy defects** — `docs/PLUGIN-MAP.md` header (“42 plugins and 300+ skills” → 44/384), README “43 Claude Code plugins”, and add a top-level `description` to marketplace.json. Found independently by exploration, both Tier-A judges, and the refuter; it is the difference between A5 tie and A5 win, and `docs-refresh` exists precisely for this.
2. **Rebuild configure-security along security-guidance's shape** (pair lost 0-5-1, the run's clearest signal): fix its broken dynamic-context commands, split the bloated always-loaded body into references, dedupe in-file repetition; consider a deterministic hook-based scan entry point with a documented trust model.
3. **Give project-test-loop a deterministic loop driver** (B4 2v5, refuter-upheld): a stop-hook/driver script in the ralph-loop mold — bounded parsing, capped iterations — instead of prose the model re-derives; wire the declared-but-unused arguments or remove them.
4. **Adopt rubric-style instruction depth in code-review** (B2 3v5, refuter-upheld): embed a verbatim scoring rubric, confidence thresholds, and a false-positive re-verification pass in code-quality:code-review — their command shows the shape; ours has the better triggering to carry it.
5. **Deepen mcp-server-authoring's build path** (pair 2-3-1): procedure-first steps with explain-the-why reasoning, de-duplicate body/reference overlap, and un-bind portfolio-specific assumptions.

**Consider**
6. **Complete per-plugin metadata**: license missing in 20/44 plugin.json, author/license absent from marketplace entries — the only thing between us and A1 anchor-5.
7. **License-validation CI** (their `validate-licenses.yml`): cheap gate; ours currently checks none of its own components.
8. **Split the specific bloated bodies the judges flagged** (configure-security's always-loaded body; blueprint-claude-md's all-inline skill): Channel M shows body bloat is localized on our side (4 of 384 skills over ~5k tokens, max ~6k, vs 3 of 29 and max ~8k theirs) — targeted splits beat a new lint. Also worth a look: 175 of our skills grant bare `Bash` in allowed-tools where a scoped grant would do.

**Skip (for now)**
9. **SHA-pin + bump/revert automation** — no external refs in our model; the A4 anchor explicitly does not penalize absent risk. Revisit only if we ever reference external sources.
10. **AI policy-scan intake pipeline & PR scope guards** — built for third-party submissions we don't accept.
11. **Command-file architecture** — their command-heavy plugins repeatedly lost B1 (near-empty trigger descriptions); our skills-only migration is vindicated by the data.

## 8. Appendices


### Channel M — mechanical metrics

| Metric (Channel M, deterministic) | ours | official |
|---|---|---|
| Marketplace entries | 44 | 255 |
| In-repo skills (SKILL.md) | 384 | 29 |
| Commands / agents / hook scripts | 0 / 21 / 69 | 29 / 26 / 17 |
| Frontmatter description rate | 1.0 | 1.0 |
| Description trigger-clause rate (generic regex) | 1.0 | 0.862 |
| SKILL.md tokens, median / p90 | 1766.5 / 2800 | 2103 / 5633 |
| Skills over ~5k tokens | 4 | 3 |
| Skills with scripts / with extra reference md | 40 / 125 | 5 / 16 |
| allowed-tools: scoped-bash / no-bash / bare-bash / absent | 165 / 44 / 175 / 0 | 1 / 6 / 0 / 22 |
| Unresolved relative md links (incl. illustrative) | 78/546 | 7/21 |
| Per-plugin CHANGELOGs | 44 | 0 |
| CI workflows (PR-triggered) | 21 (10) | 9 (8) |
| check-*/lint-* scripts | 30 / 5 | 0 / 0 |
| plugin.json field presence: version/author/license | 44/25/24 of 44 | 12/35/1 of 39 |
| Marketplace version mismatches (entry vs plugin.json) | 0 | 0 |

### House-convention supplementary (excluded from scores)

| House-convention metric (NOT scored) | ours | official |
|---|---|---|
| Literal “Use when” in description | 1.0 | 0.414 |
| created/modified date frontmatter | 1.0 | 0.0 |
| argument-hint present | 0.456 | 0.034 |

### Artifacts
All run artifacts live in the session scratchpad `bench/`: `rubric.md` (frozen anchors + exclusion list), `judgments/*.json` (20 schema-validated judgments), `quote_check.json`, `refutations.json`, `synthesis.json`, `metrics.json`, `tier_c.json`, `blinding` manifest (withheld during judging), staging trees, and the scripts (`stage_pairs.py`, `compute_metrics.py`, `quote_check.py`, `synthesize.py`, `build_report.py`).

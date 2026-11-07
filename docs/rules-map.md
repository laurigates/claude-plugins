# Rules Map

The files in `.claude/rules/` grouped by cluster, and the one file that owns
each fact several of them mention. When a rule needs a fact another file owns,
it links to that file instead of restating it (`.claude/rules/context-engineering.md`
§ Authoring rules); most contradictions the 2026-09 Layer-2 audit found
(`docs/audits/top-level-docs-layer2-audit-2026-09-28.md` § Cluster B) began as
restatements that drifted.

The `CLAUDE.md` Rules table lists every file with a one-line purpose. This page
adds the grouping and the owners.

## Clusters

Unscoped rules load on every turn; the rest load when a file matching their
`paths:` glob is touched.

| Cluster | Rules | Unscoped |
|---|---|---|
| Permissions and auto mode | `agentic-permissions`, `auto-mode`, `sandbox-guidance`, `github-actions-security` | — |
| Skill authoring | `skill-development`, `skill-quality`, `skill-naming`, `skill-execution-structure`, `skill-argument-handling`, `skill-fork-context`, `skill-portability`, `skill-consolidation`, `skill-evaluation`, `agentic-optimization`, `context-engineering`, `workflow-vs-skill`, `plugin-flow-diagrams`, `version-pinning` | — |
| Agents and runtime | `agent-development`, `agent-runtime`, `loop-integrity`, `agent-coworker-detection` | `loop-integrity`, `agent-coworker-detection` |
| Hooks | `hooks-reference`, `prompt-agent-hooks`, `hook-block-vs-nudge`, `bash-tool-replacements`, `handling-blocked-hooks` | `bash-tool-replacements`, `handling-blocked-hooks` |
| Scripts and checks | `shell-scripting`, `structured-script-output`, `regression-testing`, `offload-to-deterministic-substrate`, `drift-detection-triggering`, `parallel-safe-queries` | `offload-to-deterministic-substrate`, `parallel-safe-queries` |
| Git, PRs and releases | `conventional-commits`, `release-please`, `pr-branch-sync`, `gh-json-fields`, `issue-grouping`, `gitattributes`, `docs-currency` | `conventional-commits`, `pr-branch-sync`, `gh-json-fields`, `issue-grouping`, `docs-currency` |
| Plugins and marketplace | `plugin-structure`, `plugin-usage-telemetry`, `generated-fleet-drift`, `biome-markdown` | — |
| CI workflows | `workflow-model-effort`, `workflow-naming` | — |
| Vocabulary and tooling | `terminology`, `task-id-stability` | both |

## Owners of shared facts

| Fact | Owner | Others link, never restate |
|---|---|---|
| Skill `allowed-tools` grant model and the narrow-pattern standard | `agentic-permissions.md` § Skill `allowed-tools` is a pre-approval, so the standard is narrow patterns | `auto-mode.md`, `skill-development.md` |
| `Skill(...)` / `Bash(...)` permission syntax | `agentic-permissions.md` § Permission Syntax | `skill-development.md` |
| `bypassPermissions` protected-path history | `agentic-permissions.md` § Permission Modes | `auto-mode.md` § Protected Paths |
| Allow rules auto mode drops | `auto-mode.md` § What Happens to Allow Rules on Entering Auto Mode | `agentic-permissions.md`, `skill-development.md` |
| Skill `model:` / `effort:` selection | `skill-development.md` § Model Selection | `skill-quality.md`, `skill-fork-context.md` |
| Subagent model tiers | `agent-development.md` § Model Selection for Agents | `skill-development.md` |
| `disable-model-invocation` meaning | `skill-development.md` § Optional Frontmatter Fields | `skill-quality.md`, `pr-branch-sync.md` |
| Required vs optional skill body sections | `context-engineering.md` § Supersedes | `skill-quality.md`, `agentic-optimization.md`, `skill-development.md` |
| Which commits bump which package | `conventional-commits.md` § Scope is a label; the files touched decide what releases | `release-please.md` |
| Release-please config and auth facts | `release-please.md`, checked by `scripts/check-release-please-rule.sh` | — |
| Why the `cat`/`head`/`tail` block keeps exit 2 | `bash-tool-replacements.md` | `hook-block-vs-nudge.md` |
| Rule scoping (`paths:`) and the always-loaded budget | `context-engineering.md` | every unscoped rule states its reason |

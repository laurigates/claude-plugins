# Claude Code Plugin Migration Tracker

This document tracks the migration of Claude Code configurations from chezmoi source to logical plugins.

**Source:** `/Users/lgates/.local/share/chezmoi/exact_dot_claude/`
**Target:** `/Users/lgates/repos/laurigates/claude-plugins/`

---

## Source File Formats

### Commands

Location: `commands/*.md` or `commands/<group>/*.md`

```yaml
---
description: "Short description shown in command list"
allowed_tools: [Tool1, Tool2, Tool3]
---
Command instructions in markdown...
```

### Skills

Location: `skills/<skill-name>/SKILL.md` (plus optional `reference.md`, `templates/`)

```yaml
---
name: skill-name
description: "When to activate this skill. Include key terms for discovery."
---
# Skill Title

Skill content in markdown...
```

### Agents

Location: `agents/<agent-name>.md`

```yaml
---
name: agent-name
model: claude-opus # or claude-sonnet, claude-haiku
color: "#HEXCOLOR"
description: Short description for agent selection
tools: Tool1, Tool2, mcp__server-name
---
<role>Agent role description</role>

<core-expertise>Agent expertise areas</core-expertise>

<key-capabilities>Detailed capabilities</key-capabilities>

<!-- Additional XML-structured sections -->
```

---

## Migration Status Legend

- [ ] Not started
- [~] In progress
- [x] Complete
- [D] Duplicate (handled elsewhere)

---

## Proposed Plugin Organization

### 1. blueprint-plugin (Blueprint Development) - COMPLETE

**Purpose:** PRD/PRP methodology for structured feature development

| Type    | Name                        | Status | Notes                |
| ------- | --------------------------- | ------ | -------------------- |
| Command | blueprint-init              | [x]    |                      |
| Command | blueprint-generate-commands | [x]    |                      |
| Command | blueprint-generate-skills   | [x]    |                      |
| Command | blueprint-work-order        | [x]    |                      |
| Command | prp-create                  | [x]    |                      |
| Command | prp-execute                 | [x]    |                      |
| Command | prp-curate-docs             | [x]    |                      |
| Skill   | blueprint-development       | [x]    | Includes 4 templates |
| Skill   | confidence-scoring          | [x]    |                      |
| Agent   | requirements-documentation  | [x]    |                      |

---

### 2. configure-plugin (Project Infrastructure Standards) - COMPLETE

**Purpose:** Infrastructure standards enforcement for projects

| Type    | Name                         | Status | Notes                               |
| ------- | ---------------------------- | ------ | ----------------------------------- |
| Command | configure/all                | [x]    |                                     |
| Command | configure/status             | [x]    |                                     |
| Command | configure/pre-commit         | [x]    |                                     |
| Command | configure/release-please     | [x]    |                                     |
| Command | configure/workflows          | [x]    |                                     |
| Command | configure/dockerfile         | [x]    |                                     |
| Command | configure/skaffold           | [x]    |                                     |
| Command | configure/tests              | [x]    |                                     |
| Command | configure/coverage           | [x]    |                                     |
| Command | configure/linting            | [x]    |                                     |
| Command | configure/formatting         | [x]    |                                     |
| Command | configure/dead-code          | [x]    |                                     |
| Command | configure/docs               | [x]    |                                     |
| Command | configure/security           | [x]    |                                     |
| Command | configure/ux-testing         | [x]    |                                     |
| Command | configure/editor             | [x]    |                                     |
| Command | configure/container          | [x]    |                                     |
| Command | configure/mcp                | [x]    |                                     |
| Command | configure/github-pages       | [x]    |                                     |
| Command | configure/cache-busting      | [x]    |                                     |
| Command | configure/feature-flags      | [x]    |                                     |
| Command | configure/sentry             | [x]    |                                     |
| Command | configure/makefile           | [x]    |                                     |
| Command | configure/package-management | [x]    |                                     |
| Command | configure/api-tests          | [x]    | API testing configuration           |
| Command | configure/integration-tests  | [x]    | Integration test configuration      |
| Command | configure/load-tests         | [x]    | Load/performance test configuration |
| Skill   | ci-workflows                 | [x]    |                                     |
| Skill   | pre-commit-standards         | [x]    |                                     |
| Skill   | release-please-standards     | [x]    |                                     |
| Skill   | skaffold-standards           | [x]    |                                     |

---

### 3. git-plugin - COMPLETE

**Purpose:** Git workflows, commits, PRs, and repository management

| Type    | Name                      | Status | Notes                            |
| ------- | ------------------------- | ------ | -------------------------------- |
| Command | git/commit                | [x]    |                                  |
| Command | git/issue                 | [x]    |                                  |
| Command | git/issues                | [x]    |                                  |
| Command | git/fix-pr                | [x]    |                                  |
| Command | git/maintain              | [x]    |                                  |
| Skill   | git-commit-workflow       | [x]    |                                  |
| Skill   | git-branch-pr-workflow    | [x]    |                                  |
| Skill   | git-repo-detection        | [x]    |                                  |
| Skill   | git-security-checks       | [x]    |                                  |
| Skill   | release-please-protection | [x]    |                                  |
| Agent   | commit-review             | [x]    |                                  |
| Agent   | git-operations            | N/A    | Does not exist as separate agent |

---

### 4. testing-plugin - COMPLETE

**Purpose:** Test execution, strategy, and quality

| Type    | Name                   | Status | Notes                        |
| ------- | ---------------------- | ------ | ---------------------------- |
| Command | test/run               | [x]    |                              |
| Command | test/quick             | [x]    |                              |
| Command | test/full              | [x]    |                              |
| Command | test/setup             | [x]    |                              |
| Command | test/consult           | [x]    |                              |
| Command | test/report            | [x]    |                              |
| Command | test/analyze           | [x]    | Added - analyze test results |
| Skill   | test-tier-selection    | [x]    |                              |
| Skill   | test-quality-analysis  | [x]    |                              |
| Skill   | hypothesis-testing     | [x]    |                              |
| Skill   | property-based-testing | [x]    |                              |
| Skill   | mutation-testing       | [x]    |                              |
| Skill   | vitest-testing         | [x]    |                              |
| Agent   | test-runner            | [x]    |                              |
| Agent   | test-architecture      | [x]    |                              |

---

### 5. code-quality-plugin - COMPLETE

**Purpose:** Code review, refactoring, and analysis

| Type    | Name                       | Status | Notes |
| ------- | -------------------------- | ------ | ----- |
| Command | code/review                | [x]    |       |
| Command | code/refactor              | [x]    |       |
| Command | code/antipatterns          | [x]    |       |
| Command | lint/check                 | [x]    |       |
| Command | refactor                   | [x]    |       |
| Skill   | code-antipatterns-analysis | [x]    |       |
| Skill   | ast-grep-search            | [x]    |       |
| Agent   | code-review                | [x]    |       |
| Agent   | code-refactoring           | [x]    |       |
| Agent   | code-analysis              | [x]    |       |
| Agent   | linter-fixer               | [x]    |       |
| Agent   | security-audit             | [x]    |       |

---

### 6. python-plugin - COMPLETE

**Purpose:** Python development ecosystem

| Type  | Name                       | Status | Notes |
| ----- | -------------------------- | ------ | ----- |
| Skill | python-development         | [x]    |       |
| Skill | python-code-quality        | [x]    |       |
| Skill | python-packaging           | [x]    |       |
| Skill | python-testing             | [x]    |       |
| Skill | pytest-advanced            | [x]    |       |
| Skill | ruff-linting               | [x]    |       |
| Skill | ruff-formatting            | [x]    |       |
| Skill | ruff-integration           | [x]    |       |
| Skill | basedpyright-type-checking | [x]    |       |
| Skill | vulture-dead-code          | [x]    |       |
| Skill | uv-project-management      | [x]    |       |
| Skill | uv-python-versions         | [x]    |       |
| Skill | uv-advanced-dependencies   | [x]    |       |
| Skill | uv-tool-management         | [x]    |       |
| Skill | uv-run                     | [x]    |       |
| Skill | uv-workspaces              | [x]    |       |
| Agent | python-development         | [x]    |       |

---

### 7. typescript-plugin - COMPLETE

**Purpose:** TypeScript/JavaScript development ecosystem

| Type  | Name                   | Status | Notes |
| ----- | ---------------------- | ------ | ----- |
| Skill | typescript-strict      | [x]    |       |
| Skill | eslint-configuration   | [x]    |       |
| Skill | biome-tooling          | [x]    |       |
| Skill | knip-dead-code         | [x]    |       |
| Agent | typescript-development | [x]    |       |
| Agent | javascript-development | [x]    | Added |

---

### 8. javascript-plugin - MERGED INTO typescript-plugin

**Purpose:** JavaScript/Node.js development

| Type  | Name                   | Status | Notes                          |
| ----- | ---------------------- | ------ | ------------------------------ |
| Skill | javascript-development | [D]    | Merged into typescript-plugin  |
| Skill | nodejs-development     | [ ]    | Consider for typescript-plugin |
| Skill | bun-lockfile-update    | [ ]    | Consider for typescript-plugin |
| Agent | javascript-development | [x]    | In typescript-plugin           |

---

### 9. rust-plugin

**Purpose:** Rust development ecosystem

| Type  | Name             | Status | Notes |
| ----- | ---------------- | ------ | ----- |
| Skill | rust-development | [ ]    |       |
| Skill | clippy-advanced  | [ ]    |       |
| Skill | cargo-nextest    | [ ]    |       |
| Skill | cargo-llvm-cov   | [ ]    |       |
| Skill | cargo-machete    | [ ]    |       |
| Agent | rust-development | [ ]    |       |

---

### 10. kubernetes-plugin

**Purpose:** Kubernetes and Helm operations

| Type  | Name                    | Status | Notes |
| ----- | ----------------------- | ------ | ----- |
| Skill | kubernetes-operations   | [ ]    |       |
| Skill | helm-chart-development  | [ ]    |       |
| Skill | helm-debugging          | [ ]    |       |
| Skill | helm-release-management | [ ]    |       |
| Skill | helm-release-recovery   | [ ]    |       |
| Skill | helm-values-management  | [ ]    |       |
| Skill | argocd-login            | [ ]    |       |

---

### 11. terraform-plugin

**Purpose:** Terraform and Terraform Cloud

| Type  | Name                     | Status | Notes |
| ----- | ------------------------ | ------ | ----- |
| Skill | infrastructure-terraform | [ ]    |       |
| Skill | tfc-list-runs            | [ ]    |       |
| Skill | tfc-plan-json            | [ ]    |       |
| Skill | tfc-run-logs             | [ ]    |       |
| Skill | tfc-run-status           | [ ]    |       |
| Skill | tfc-workspace-runs       | [ ]    |       |

---

### 12. github-actions-plugin

**Purpose:** CI/CD with GitHub Actions

| Type    | Name                         | Status | Notes |
| ------- | ---------------------------- | ------ | ----- |
| Command | workflow/dev                 | [ ]    |       |
| Skill   | claude-code-github-workflows | [ ]    |       |
| Skill   | github-actions-auth-security | [ ]    |       |
| Skill   | github-actions-inspection    | [ ]    |       |
| Skill   | github-actions-mcp-config    | [ ]    |       |
| Skill   | github-issue-search          | [ ]    |       |
| Skill   | github-social-preview        | [ ]    |       |
| Agent   | cicd-pipelines               | [ ]    |       |

---

### 13. documentation-plugin

**Purpose:** Documentation generation and management

| Type    | Name                   | Status | Notes |
| ------- | ---------------------- | ------ | ----- |
| Command | docs/sync              | [ ]    |       |
| Command | docs/generate          | [ ]    |       |
| Command | docs/build             | [ ]    |       |
| Command | docs/decommission      | [ ]    |       |
| Command | docs/knowledge-graph   | [ ]    |       |
| Skill   | claude-blog-sources    | [ ]    |       |
| Agent   | documentation          | [ ]    |       |
| Agent   | research-documentation | [ ]    |       |

---

### 14. project-plugin - COMPLETE

**Purpose:** Project initialization and management

| Type    | Name                  | Status | Notes                                                        |
| ------- | --------------------- | ------ | ------------------------------------------------------------ |
| Command | project/init          | [x]    | Namespaced as `/project:init`                                |
| Command | project/new           | [x]    | Namespaced as `/project:new`                                 |
| Command | project/modernize     | [x]    | Namespaced as `/project:modernize`                           |
| Command | project/modernize-exp | [x]    | Namespaced as `/project:modernize-exp`                       |
| Command | project/continue      | [x]    | Namespaced as `/project:continue` (was `project-continue`)   |
| Command | project/test-loop     | [x]    | Namespaced as `/project:test-loop` (was `project-test-loop`) |
| Skill   | project-discovery     | [x]    |                                                              |

---

### 15. tools-plugin (Utilities) - COMPLETE

**Purpose:** General-purpose development utilities

| Type    | Name                   | Status | Notes |
| ------- | ---------------------- | ------ | ----- |
| Command | deps/install           | [x]    |       |
| Command | tools/vectorcode       | [x]    |       |
| Command | generate-image         | [x]    |       |
| Command | handoffs               | [x]    |       |
| Skill   | fd-file-finding        | [x]    |       |
| Skill   | rg-code-search         | [x]    |       |
| Skill   | jq-json-processing     | [x]    |       |
| Skill   | yq-yaml-processing     | [x]    |       |
| Skill   | imagemagick-conversion | [x]    |       |
| Skill   | shell-expert           | [x]    |       |
| Skill   | vectorcode-init        | [x]    |       |
| Skill   | vectorcode-search      | [x]    |       |

---

### 16. agent-patterns-plugin (Orchestration)

**Purpose:** Multi-agent coordination and meta-configuration

| Type    | Name                        | Status | Notes |
| ------- | --------------------------- | ------ | ----- |
| Command | delegate                    | [ ]    |       |
| Command | meta/audit                  | [ ]    |       |
| Command | meta/assimilate             | [ ]    |       |
| Command | check-negative-examples     | [ ]    |       |
| Skill   | agent-coordination-patterns | [ ]    |       |
| Skill   | agent-file-coordination     | [ ]    |       |
| Skill   | multi-agent-workflows       | [ ]    |       |
| Skill   | command-context-patterns    | [ ]    |       |
| Skill   | mcp-management              | [ ]    |       |

---

### 18. accessibility-plugin

**Purpose:** Accessibility and UX implementation

| Type  | Name                         | Status | Notes |
| ----- | ---------------------------- | ------ | ----- |
| Skill | accessibility-implementation | [ ]    |       |
| Skill | design-tokens                | [ ]    |       |
| Skill | ux-handoff-markers           | [ ]    |       |
| Agent | ux-implementation            | [ ]    |       |
| Agent | service-design               | [ ]    |       |

---

### 19. dotfiles-plugin

**Purpose:** Dotfiles and editor configuration

| Type  | Name                 | Status | Notes |
| ----- | -------------------- | ------ | ----- |
| Skill | chezmoi-expert       | [ ]    |       |
| Skill | neovim-configuration | [ ]    |       |
| Skill | obsidian-bases       | [ ]    |       |
| Agent | dotfiles-manager     | [ ]    |       |

---

### 20. bevy-plugin (Game Development)

**Purpose:** Bevy game engine development

| Type  | Name              | Status | Notes |
| ----- | ----------------- | ------ | ----- |
| Skill | bevy-game-engine  | [ ]    |       |
| Skill | bevy-ecs-patterns | [ ]    |       |

---

### 21. graphiti-plugin (Memory/Learning)

**Purpose:** Graphiti knowledge graph integration

| Type  | Name                        | Status | Notes |
| ----- | --------------------------- | ------ | ----- |
| Skill | graphiti-episode-storage    | [ ]    |       |
| Skill | graphiti-learning-workflows | [ ]    |       |
| Skill | graphiti-memory-retrieval   | [ ]    |       |

---

### 22. container-plugin

**Purpose:** Container development and registry

| Type    | Name                  | Status | Notes |
| ------- | --------------------- | ------ | ----- |
| Command | deploy/release        | [ ]    |       |
| Command | deploy/handoff        | [ ]    |       |
| Skill   | container-development | [ ]    |       |
| Skill   | skaffold-orbstack     | [ ]    |       |

---

### 23. api-plugin

**Purpose:** API integration and testing

| Type  | Name            | Status | Notes |
| ----- | --------------- | ------ | ----- |
| Skill | api-testing     | [ ]    |       |
| Agent | api-integration | [ ]    |       |

---

### 24. communication-plugin

**Purpose:** External communication formatting

| Type  | Name                       | Status | Notes |
| ----- | -------------------------- | ------ | ----- |
| Skill | google-chat-formatting     | [ ]    |       |
| Skill | ticket-drafting-guidelines | [ ]    |       |

---

## Handling Duplicates

Some skills naturally belong to multiple domains. Strategies:

### 1. **Primary Location + References**

Place the skill in its primary plugin, reference it in related plugins' documentation.

| Skill                     | Primary Plugin | Referenced By     |
| ------------------------- | -------------- | ----------------- |
| hypothesis-testing        | testing-plugin | python-plugin     |
| vitest-testing            | testing-plugin | typescript-plugin |
| property-based-testing    | testing-plugin | python-plugin     |
| release-please-protection | git-plugin     | configure-plugin  |

### 2. **Shared/Core Plugin** (Alternative)

Create a `core-plugin` for frequently shared skills:

- ast-grep-search (used by multiple analysis tools)
- shell-expert (universal utility)
- fd-file-finding / rg-code-search (universal search)

### 3. **Composition Pattern**

Plugins can declare dependencies on other plugins to inherit their skills.

---

## Plugin Priority (Migration Order)

1. **blueprint-plugin** - Core methodology, self-contained
2. **configure-plugin** - project standards, high value
3. **git-plugin** - Common workflow
4. **testing-plugin** - Essential for TDD
5. **code-quality-plugin** - Frequently used
6. **python-plugin** - Primary language
7. **typescript-plugin** - Common language
8. **tools-plugin** - General utilities
9. Remaining plugins...

---

## Notes

- **Agent definitions** need investigation - are they defined in skills/ or separate agents/ directory?
- **REFERENCE.md files** - Some skills have external documentation references to preserve
- **Command templates** - Commands may use templates (`.tmpl` files) for chezmoi
- **Skill metadata** - Skills have headers with descriptions, need to preserve format

---

## Open Questions

1. ~~Should plugins support declaring dependencies on other plugins?~~ → No formal dependency system; document companions in README
2. ~~How to handle skills that genuinely span multiple domains?~~ → Context-scoped; duplicate in each plugin or create shared `core-plugin`
3. Should there be a `core-plugin` for universal utilities? → **Decision needed**
4. What's the versioning strategy for plugins? → Semantic versioning in plugin.json
5. How do plugins interact with global CLAUDE.md instructions? → **To test**
6. ~~What's the directory structure within a plugin?~~ → **Resolved** (see Official Plugin Directory Structure)
7. ~~How does plugin.json reference commands, skills, agents?~~ → **Resolved** (auto-discovered from directories)

---

## Official Plugin Directory Structure

Based on Claude Code plugin specification:

```
<plugin-name>/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest (REQUIRED - only this goes here)
├── commands/                 # Auto-discovered slash commands
│   ├── command-a.md
│   └── subgroup/
│       └── command-b.md
├── skills/                   # Auto-discovered skills
│   └── skill-name/
│       ├── SKILL.md         # Required for each skill
│       ├── reference.md     # Optional supporting docs
│       └── templates/       # Optional templates
├── agents/                   # Auto-discovered agents
│   └── agent-name.md
├── hooks/                    # Optional hook configurations
│   └── hooks.json
├── .mcp.json                # Optional MCP server config
└── README.md                # Plugin documentation
```

**Key rule**: Only `plugin.json` goes inside `.claude-plugin/`. All content directories (commands/, agents/, skills/, hooks/) are at plugin root.

### Plugin Manifest Schema (plugin.json)

**Required fields:**

- `name`: unique identifier (kebab-case)

**Metadata fields:**

- `version`: semantic version
- `description`: brief explanation
- `author`: object with `name`, `email`, `url`
- `homepage`: documentation URL
- `repository`: source code URL
- `license`: SPDX identifier
- `keywords`: discovery tags

**Component paths** (supplement auto-discovery, don't replace):

- `commands`: additional command files/directories
- `agents`: additional agent files
- `hooks`: hook config path or inline
- `mcpServers`: MCP config path or inline

**Example plugin.json:**

```json
{
  "name": "blueprint-plugin",
  "version": "1.0.0",
  "description": "Blueprint Development methodology - PRD/PRP workflow for structured feature development",
  "author": {
    "name": "Lauri Gates"
  },
  "repository": "https://github.com/laurigates/claude-plugins",
  "license": "MIT",
  "keywords": ["blueprint", "prd", "prp", "requirements", "methodology"]
}
```

**Note**: Commands, skills, and agents in default directories are auto-discovered. No need to list them explicitly.

---

## Component Discovery

Claude Code automatically discovers:

- `commands/*.md` - Registered as `/command-name`
- `skills/*/SKILL.md` - Activated by context matching
- `agents/*.md` - Available in `/agents` and context-invoked

No namespace prefixes needed - plugins are context-scoped.

---

## Marketplace Structure

The root `marketplace.json` lists available plugins:

```json
{
  "name": "laurigates-claude-plugins",
  "owner": {
    "name": "Lauri Gates"
  },
  "plugins": [
    {
      "name": "blueprint-plugin",
      "source": "./blueprint-plugin",
      "description": "Blueprint Development methodology",
      "version": "1.0.0",
      "keywords": ["blueprint", "prd", "methodology"],
      "category": "development"
    }
  ]
}
```

**Installation**: `/plugin install blueprint-plugin@laurigates-claude-plugins`

---

## Duplicate Handling Strategy

Since skills/agents are context-scoped per plugin:

1. **Same skill in multiple plugins** - Each plugin gets its own copy; context determines which activates
2. **Shared utilities** - Create a `core-plugin` that other plugins can recommend as companion
3. **Explicit dependencies** - Document in README which plugins work well together

---

## Next Steps

1. [x] Research Claude Code plugin specification ✓
2. [x] Update marketplace.json with planned plugins ✓
3. [x] Create blueprint-plugin ✓
4. [x] Create configure-plugin ✓
5. [x] Create git-plugin ✓
6. [x] Create testing-plugin ✓
7. [x] Create code-quality-plugin ✓
8. [x] Create python-plugin ✓
9. [x] Create typescript-plugin ✓
10. [x] Create tools-plugin ✓
11. [ ] Test plugin installation and command discovery
12. [ ] Continue migration of remaining plugins (kubernetes, terraform, docs, etc.)

## Migration Priority Order

Based on self-contained scope and frequency of use:

| Priority | Plugin               | Status   | Reason                                       |
| -------- | -------------------- | -------- | -------------------------------------------- |
| 1        | blueprint-plugin     | **DONE** | Self-contained methodology, defines workflow |
| 2        | configure-plugin     | **DONE** | High value, project standards enforcement    |
| 3        | git-plugin           | **DONE** | Common workflow, clear boundaries            |
| 4        | testing-plugin       | **DONE** | Essential for TDD, frequently used           |
| 5        | code-quality-plugin  | **DONE** | Code review/analysis cluster                 |
| 6        | python-plugin        | **DONE** | Primary language ecosystem                   |
| 7        | typescript-plugin    | **DONE** | Common language ecosystem                    |
| 8        | tools-plugin         | **DONE** | General utilities (fd, rg, jq, etc.)         |
| 9+       | Remaining plugins... | Pending  |                                              |

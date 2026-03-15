## blueprint-init

Initialize Blueprint Development in this project.

**Steps**:

1. **Check if already initialized**:
   - Look for `docs/blueprint/manifest.json`
   - If exists, read version and ask user:
     ```
     Use report to orchestrator:
     question: "Blueprint already initialized (v{version}). What would you like to do?"
     options:
       - "Check for upgrades" → run /blueprint:upgrade
       - "Reinitialize (will reset manifest)" → continue with step 2
       - "Cancel" → exit
     ```

2. **Ask about feature tracking** (use report to orchestrator):
   ```
   question: "Would you like to enable feature tracking?"
   options:
     - label: "Yes - Track implementation against requirements"
       description: "Creates feature-tracker.json to track FR codes from a requirements document"
     - label: "No - Skip feature tracking"
       description: "Can be added later with /blueprint:feature-tracker-sync"
   ```

   **If "Yes" selected:**
   a. Search for markdown files in the project that contain requirements, features, or user stories
   b. Auto-detect the most likely source document based on content analysis
   c. Create `docs/blueprint/feature-tracker.json` from template using the detected source
   d. Set `has_feature_tracker: true` in manifest

3. **Ask about document migration** (use report to orchestrator):
   Search for existing markdown documentation files across the project (excluding standard files like README.md, CHANGELOG.md, CONTRIBUTING.md, LICENSE.md, CODE_OF_CONDUCT.md, SECURITY.md).

   ```bash
   # Find markdown files that look like documentation (not standard repo files)
   find . -name '*.md' -not -path '*/node_modules/*' -not -path '*/.git/*' | grep -viE '(README|CHANGELOG|CONTRIBUTING|LICENSE|CODE_OF_CONDUCT|SECURITY)\.md$'
   ```

   **If documentation files found** (e.g., REQUIREMENTS.md, ARCHITECTURE.md, DESIGN.md, docs in non-standard locations):
   ```
   Use report to orchestrator:
   question: "Found existing documentation: {file_list}. Migrate these to Blueprint-managed paths? (Strongly recommended)"
   options:
     - label: "Yes, migrate documents (Recommended)"
       description: "Move docs into docs/prds/, docs/adrs/, docs/prps/ based on content type. Prevents stale and orphaned documents."
     - label: "No, leave them in place"
       description: "Warning: unmigrated docs may become stale or duplicated as Blueprint creates its own documents"
   ```

   **If "Yes" selected:**
   a. Analyze each file to determine type:
      - Contains requirements, features, user stories → `docs/prds/`
      - Contains architecture decisions, trade-offs → `docs/adrs/`
      - Contains implementation plans → `docs/prps/`
      - General documentation → `docs/`
   b. Move files to appropriate `docs/` subdirectory
   c. Rename to kebab-case if needed (REQUIREMENTS.md → requirements.md)
   d. Report migration results:
      ```
      Migrated documentation:
      - REQUIREMENTS.md → docs/prds/requirements.md
      - ARCHITECTURE.md → docs/adrs/0001-initial-architecture.md
      ```

   **If no documentation files found:** Skip this step silently.

4. **Ask about maintenance task scheduling** (use report to orchestrator):
   ```
   question: "How should blueprint maintenance tasks run?"
   options:
     - label: "Prompt before running (Recommended)"
       description: "Always ask before running maintenance tasks like sync, validate"
     - label: "Auto-run safe tasks"
       description: "Read-only tasks (validate, sync, status) run automatically when due"
     - label: "Fully automatic"
       description: "All tasks run automatically on schedule, including writes like rule generation"
     - label: "Manual only"
       description: "Tasks only run when you explicitly invoke them"
   ```

   Store selection for task_registry defaults:
   - **Prompt**: all `auto_run: false`, default schedules
   - **Auto-run safe**: read-only tasks (`adr-validate`, `feature-tracker-sync`, `sync-ids`) get `auto_run: true`; write tasks get `false`
   - **Fully automatic**: all tasks get `auto_run: true`, default schedules
   - **Manual only**: all `auto_run: false`, all schedules set to `on-demand`

5. **Ask about decision detection** (use report to orchestrator):
   ```
   question: "Would you like to enable automatic decision detection?"
   options:
     - label: "Yes - Detect decisions worth documenting"
       description: "Claude will notice when conversations contain architecture decisions, feature requirements, or implementation plans that should be captured as ADR/PRD/PRP documents"
     - label: "No - Manual commands only"
       description: "Use /blueprint:derive-prd, /blueprint:derive-adr, /blueprint:prp-create explicitly when you want to create documents"
   ```

   Set `has_document_detection` in manifest based on response.

   **If enabled:**
   Copy `document-management-rule.md` template to `.claude/rules/document-management.md`.
   This rule instructs Claude to watch for:
   - Architecture decisions being made during discussion → prompt to create ADR
   - Feature requirements being discussed or refined → prompt to create/update PRD
   - Implementation plans being formulated → prompt to create PRP

6. **Create directory structure**:

   **Blueprint structure (in docs/blueprint/):**
   ```
   docs/
   ├── blueprint/
   │   ├── manifest.json            # Version tracking and configuration
   │   ├── feature-tracker.json     # Progress tracking (if enabled)
   │   ├── work-orders/             # Task packages for subagents
   │   │   ├── completed/
   │   │   └── archived/
   │   ├── ai_docs/                 # Curated documentation (on-demand)
   │   │   ├── libraries/
   │   │   └── project/
   │   └── README.md                # Blueprint documentation
   ├── prds/                        # Product Requirements Documents
   ├── adrs/                        # Architecture Decision Records
   └── prps/                        # Product Requirement Prompts
   ```

   **Claude configuration (in .claude/):**
   ```
   .claude/
   ├── rules/                       # Modular rules (including generated)
   │   ├── development.md           # Development workflow rules
   │   ├── testing.md               # Testing requirements
   │   └── document-management.md   # Document organization rules (if detection enabled)
   └── skills/                      # Custom skill overrides (optional)
   ```

7. **Create `manifest.json`** (v3.2.0 schema):
   ```json
   {
     "format_version": "3.2.0",
     "created_at": "[ISO timestamp]",
     "updated_at": "[ISO timestamp]",
     "created_by": {
       "blueprint_plugin": "3.2.0"
     },
     "project": {
       "name": "[detected from package.json/pyproject.toml or directory name]",
       "detected_stack": []
     },
     "structure": {
       "has_prds": true,
       "has_adrs": true,
       "has_prps": true,
       "has_work_orders": true,
       "has_ai_docs": false,
       "has_modular_rules": true,
       "has_feature_tracker": "[based on user choice]",
       "has_document_detection": "[based on user choice]",
       "claude_md_mode": "both"
     },
     "feature_tracker": {
       "file": "feature-tracker.json",
       "source_document": "[auto-detected]",
       "sync_targets": ["TODO.md"]
     },
     "generated": {
       "rules": {},
       "commands": {}
     },
     "custom_overrides": {
       "skills": [],
       "commands": []
     },
     "task_registry": {
       "derive-prd": {
         "enabled": true,
         "auto_run": false,
         "last_completed_at": null,
         "last_result": null,
         "schedule": "on-demand",
         "stats": {},
         "context": {}
       },
       "derive-plans": {
         "enabled": true,
         "auto_run": false,
         "last_completed_at": null,
         "last_result": null,
         "schedule": "weekly",
         "stats": {},
         "context": {}
       },
       "derive-rules": {
         "enabled": true,
         "auto_run": false,
         "last_completed_at": null,
         "last_result": null,
         "schedule": "weekly",
         "stats": {},
         "context": {}
       },
       "generate-rules": {
         "enabled": true,
         "auto_run": false,
         "last_completed_at": null,
         "last_result": null,
         "schedule": "on-change",
         "stats": {},
         "context": {}
       },
       "adr-validate": {
         "enabled": true,
         "auto_run": "[based on maintenance task choice: true if auto-run safe, false otherwise]",
         "last_completed_at": null,
         "last_result": null,
         "schedule": "weekly",
         "stats": {},
         "context": {}
       },
       "feature-tracker-sync": {
         "enabled": true,
         "auto_run": "[based on maintenance task choice: true if auto-run safe, false otherwise]",
         "last_completed_at": null,
         "last_result": null,
         "schedule": "daily",
         "stats": {},
         "context": {}
       },
       "sync-ids": {
         "enabled": true,
         "auto_run": "[based on maintenance task choice: true if auto-run safe, false otherwise]",
         "last_completed_at": null,
         "last_result": null,
         "schedule": "on-change",
         "stats": {},
         "context": {}
       },
       "claude-md": {
         "enabled": true,
         "auto_run": false,
         "last_completed_at": null,
         "last_result": null,
         "schedule": "on-change",
         "stats": {},
         "context": {}
       },
       "curate-docs": {
         "enabled": false,
         "auto_run": false,
         "last_completed_at": null,
         "last_result": null,
         "schedule": "on-demand",
         "stats": {},
         "context": {}
       }
     }
   }
   ```

   Note: Include `feature_tracker` section only if feature tracking is enabled.
   Note: As of v3.2.0, progress tracking is consolidated into feature-tracker.json (work-overview.md removed).

8. **Create initial rules**:
   - `development.md`: TDD workflow, commit conventions
   - `testing.md`: Test requirements, coverage expectations
   - `document-management.md`: Document organization rules (if decision detection enabled)

9. **Handle `.gitignore`**:
   - Always commit `CLAUDE.md` and `.claude/rules/` (shared project instructions)
   - Add `docs/blueprint/work-orders/` to `.gitignore` (task-specific, may contain sensitive details)
   - If secrets detected in `.claude/`, warn user and suggest `.gitignore` entries

10. **Report**:
   ```
   Blueprint Development initialized! (v3.2.0)

   Blueprint structure created:
   - docs/blueprint/manifest.json
   - docs/blueprint/work-orders/
   - docs/blueprint/ai_docs/
   - docs/blueprint/README.md
   [- docs/blueprint/feature-tracker.json (if feature tracking enabled)]

   Project documentation:
   - docs/prds/           (Product Requirements Documents)
   - docs/adrs/           (Architecture Decision Records)
   - docs/prps/           (Product Requirement Prompts)

   Claude configuration:
   - .claude/rules/       (modular rules, including generated)
   - .claude/skills/      (custom skill overrides)

   Configuration:
   - Rules mode: both (CLAUDE.md + .claude/rules/)
   [- Feature tracking: enabled]
   [- Decision detection: enabled (Claude will prompt when discussions should become ADR/PRD/PRP)]
   [- Task scheduling: {prompt|auto-run safe|fully automatic|manual only}]

   [Migrated documentation:]
   [- {original} → {destination} (for each migrated file)]

   Architecture:
   - Plugin layer: Generic commands from blueprint-plugin (auto-updated)
   - Generated layer: Rules/commands regeneratable from docs/prds/
   - Custom layer: Your overrides in .claude/skills/
   ```

11. **Prompt for next action** (use report to orchestrator):
    ```
    question: "Blueprint initialized. What would you like to do next?"
    options:
      - label: "Derive plans from git history (Recommended)"
        description: "Analyze commit history, PRs, and issues to build PRDs, ADRs, and PRPs from existing project decisions"
      - label: "Derive rules from codebase"
        description: "Analyze commit patterns and code conventions to generate .claude/rules/"
      - label: "Update CLAUDE.md"
        description: "Generate or update CLAUDE.md with project context and blueprint integration"
      - label: "I'm done for now"
        description: "Exit - you can run /blueprint:status anytime to see options"
    ```

    **Based on selection:**
    - "Derive plans from git history" → Run `/blueprint:derive-plans`
    - "Derive rules from codebase" → Run `/blueprint:derive-rules`
    - "Update CLAUDE.md" → Run `/blueprint:claude-md`
    - "I'm done for now" → Show quick reference and exit

**Quick Reference** (show if user selects "I'm done for now"):
```
Management commands:
- /blueprint:status          - Check version and configuration
- /blueprint:upgrade         - Upgrade to latest format version
- /blueprint:derive-prd      - Derive PRD from existing documentation
- /blueprint:derive-adr      - Derive ADRs from codebase analysis
- /blueprint:derive-plans    - Derive docs from git history
- /blueprint:derive-rules    - Derive rules from git commit decisions
- /blueprint:prp-create      - Create a Product Requirement Prompt
- /blueprint:generate-rules  - Generate rules from PRDs
- /blueprint:sync            - Check for stale generated content
- /blueprint:promote         - Move generated content to custom layer
- /blueprint:rules           - Manage modular rules
- /blueprint:claude-md       - Update CLAUDE.md
- /blueprint:feature-tracker-status  - View feature completion stats
- /blueprint:feature-tracker-sync    - Sync tracker with project files
```

---

## blueprint-derive-prd

Generate a Product Requirements Document (PRD) for an existing project by analyzing README, documentation, and project structure.

**Use Case**: Onboarding existing projects to Blueprint Development system.

**Prerequisites**:
- Blueprint Development initialized (`docs/blueprint/` exists)
- Project has some existing documentation (README.md, docs/, etc.)

**Steps**:
## Phase 1: Discovery


### 1.1 Check Prerequisites
```bash
ls docs/blueprint/manifest.json
```
If not found → suggest running `/blueprint:init` first.


### 1.2 Gather Project Documentation
Search for existing documentation:
```bash
fd -e md -d 3 . | head -20
```

Key files to look for:
- `README.md` - Primary project description
- `docs/` - Documentation directory
- `CONTRIBUTING.md` - Contribution guidelines
- `ARCHITECTURE.md` - Architecture overview
- `package.json` / `pyproject.toml` / `Cargo.toml` - Project metadata


### 1.3 Read Primary Documentation
Read and analyze:
- README.md for project purpose, features, and usage
- Package manifest for dependencies and scripts
- Any existing architecture or design docs


## Phase 2: Analysis & Extraction


### 2.1 Extract Project Context
From documentation, identify:

| Aspect | Source | Questions if Missing |
|--------|--------|---------------------|
| Project name | Package manifest, README | Ask user |
| Purpose/Problem | README intro | "What problem does this project solve?" |
| Target users | README, docs | "Who are the primary users?" |
| Core features | README features section | "What are the main capabilities?" |
| Tech stack | Dependencies, file extensions | Infer from files |


### 2.2 Ask Clarifying Questions
Use report to orchestrator for unclear items:

```
question: "What is the primary problem this project solves?"
options:
  - "[Inferred from docs]: {description}" → confirm inference
  - "Let me describe it" → free text input
```

```
question: "Who are the target users?"
options:
  - "Developers" → technical documentation focus
  - "End users" → user experience focus
  - "Both developers and end users" → balanced approach
  - "Other" → custom description
```

```
question: "What is the current project phase?"
options:
  - "Early development / MVP" → focus on core features
  - "Active development" → feature expansion
  - "Maintenance mode" → stability and bug fixes
  - "Planning major changes" → architectural considerations
```


### 2.3 Identify Stakeholders
Ask about stakeholders:
```
question: "Who are the key stakeholders for this project?"
options:
  - "Solo project (just me)" → simplified RACI
  - "Small team (2-5 people)" → team collaboration
  - "Larger organization" → formal stakeholder matrix
  - "Open source community" → contributor-focused
```


## Phase 3: PRD Generation


### 3.1 Generate Document ID

Before creating the PRD, generate a unique ID:

```bash

# Get next PRD ID from manifest
next_prd_id() {
  local manifest="docs/blueprint/manifest.json"
  local last=$(jq -r '.id_registry.last_prd // 0' "$manifest" 2>/dev/null || echo "0")
  local next=$((last + 1))
  printf "PRD-%03d" "$next"
}
```

Store the generated ID for use in the document and manifest update.


### 3.2 Create PRD File
Create the PRD in `docs/prds/`:
```
docs/prds/project-overview.md
```


### 3.3 PRD Template
Generate PRD with this structure:

```markdown
---
id: {PRD-NNN}
created: {YYYY-MM-DD}
modified: {YYYY-MM-DD}
status: Draft
version: "1.0"
relates-to: []
github-issues: []
name: blueprint-derive-prd
---


# {Project Name} - Product Requirements Document


## Executive Summary


### Problem Statement
{Extracted or confirmed problem description}


### Proposed Solution
{Project description and approach}


### Business Impact
{Value proposition and expected outcomes}


## Stakeholders & Personas


### Stakeholder Matrix
| Role | Name/Team | Responsibility | Contact |
|------|-----------|----------------|---------|
| {role} | {name} | {responsibility} | {contact} |


### User Personas

#### Primary: {Persona Name}
- **Description**: {who they are}
- **Needs**: {what they need}
- **Pain Points**: {current frustrations}
- **Goals**: {what success looks like}


## Functional Requirements


### Core Features
{List of main capabilities extracted from docs}

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| FR-001 | {feature} | {description} | {P0/P1/P2} |


### User Stories
{User stories derived from features}

- As a {user type}, I want to {action} so that {benefit}


## Non-Functional Requirements


### Performance
- {Response time expectations}
- {Throughput requirements}


### Security
- {Authentication requirements}
- {Data protection needs}


### Accessibility
- {Accessibility standards to follow}


### Compatibility
- {Browser/platform/version support}


## Technical Considerations


### Architecture
{High-level architecture from docs or inferred}


### Dependencies
{Key dependencies from package manifest}


### Integration Points
{External services, APIs, databases}


## Success Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| {metric} | {baseline} | {goal} | {how to measure} |


## Scope


### In Scope
- {Included features and capabilities}


### Out of Scope
- {Explicitly excluded items}
- {Future considerations}


## Timeline & Phases


### Current Phase: {phase name}
{Description of current work focus}


### Roadmap
| Phase | Focus | Status |
|-------|-------|--------|
| {phase} | {focus areas} | {status} |

---
*Generated from existing documentation via /blueprint:derive-prd*
*Review and update as project evolves*
```


## Phase 4: Validation & Follow-up


### 4.1 Present Summary
Show the user:
```
✅ PRD Generated: {Project Name}

**ID**: {PRD-NNN}
**Location**: `docs/prds/project-overview.md`

**Extracted from**:
- {list of source documents}

**Key sections**:
- Executive Summary: {status}
- Stakeholders: {count} identified
- Functional Requirements: {count} features
- Non-Functional Requirements: {status}

**Confidence**: {High/Medium/Low}
- {High confidence areas}
- {Areas needing review}

**Recommended next steps**:
1. Review and refine the generated PRD
2. Run `/blueprint:derive-adr` to document architecture decisions
3. Run `/blueprint:prp-create` for specific features
4. Run `/blueprint:generate-skills` to create project skills
```


### 4.2 Suggest Follow-up
Based on what was generated:
- If architecture unclear → suggest `/blueprint:derive-adr`
- If features identified → suggest `/blueprint:prp-create` for key features
- If PRD complete → suggest `/blueprint:generate-skills`


## Phase 5: Update Manifest

Update `docs/blueprint/manifest.json`:
- Add PRD to `generated_artifacts`
- Update `has_prds` to true
- Update `updated_at` timestamp
- **Update ID registry**:
  ```json
  {
    "id_registry": {
      "last_prd": {new_number},
      "documents": {
        "{PRD-NNN}": {
          "path": "docs/prds/{filename}.md",
          "title": "{Project Name}",
          "github_issues": [],
          "created": "{date}"
        }
      }
    }
  }
  ```

**Tips**:
- Be thorough in reading existing docs - they often contain valuable context
- Ask clarifying questions for ambiguous or missing information
- Infer from code structure when documentation is sparse
- Mark uncertain sections for user review
- Keep PRD focused on "what" and "why", not "how"


### 4.3 Update task registry

Update the task registry entry in `docs/blueprint/manifest.json`:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson created "${PRDS_GENERATED:-1}" \
  '.task_registry["derive-prd"].last_completed_at = $now |
   .task_registry["derive-prd"].last_result = "success" |
   .task_registry["derive-prd"].stats.runs_total = ((.task_registry["derive-prd"].stats.runs_total // 0) + 1) |
   .task_registry["derive-prd"].stats.items_created = $created' \
  docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
```


### 4.4 Prompt for GitHub Issue (use report to orchestrator):

```
question: "Create a GitHub issue to track this PRD?"
options:
  - label: "Yes, create issue (Recommended)"
    description: "Creates issue with title '[PRD-NNN] {Project Name}'"
  - label: "No, skip for now"
    description: "Can link later by editing github-issues in frontmatter"
```

**If yes**, create GitHub issue:
```bash
gh issue create \
  --title "[{PRD-NNN}] {Project Name}" \
  --body "## Product Requirements Document

**Document**: \`docs/prds/{filename}.md\`
**ID**: {PRD-NNN}


### Summary
{Executive summary from PRD}


### Key Features
{List of FR-* features}

name: blueprint-derive-prd
---
*Auto-generated from PRD. See linked document for full requirements.*" \
  --label "prd,requirements"
```

Capture issue number and update:
1. PRD frontmatter: add issue number to `github-issues`
2. Manifest: add issue to `id_registry.documents[PRD-NNN].github_issues`
3. Manifest: add mapping to `id_registry.github_issues`


### 4.5 Prompt for next action (use report to orchestrator):

```
question: "PRD generated. What would you like to do next?"
options:
  - label: "Document architecture decisions (Recommended)"
    description: "Run /blueprint:derive-adr to capture technical decisions"
  - label: "Generate project skills"
    description: "Extract skills from PRD for Claude context"
  - label: "Create a PRP for a feature"
    description: "Start implementing a specific feature"
  - label: "Review and refine PRD"
    description: "I want to edit the generated PRD first"
  - label: "I'm done for now"
    description: "Exit - PRD is saved"
```

**Based on selection:**
- "Document architecture decisions" → Run `/blueprint:derive-adr`
- "Generate project skills" → Run `/blueprint:generate-skills`
- "Create a PRP" → Run `/blueprint:prp-create` (ask for feature name)
- "Review and refine" → Show PRD file location and key sections needing attention
- "I'm done" → Exit

**Error Handling**:
- If no README.md → ask user for project description
- If blueprint not initialized → suggest `/blueprint:init`
- If conflicting information in docs → ask user to clarify

---

## blueprint-derive-adr

Generate Architecture Decision Records (ADRs) for an existing project by analyzing code structure, dependencies, and documentation.

**Use Case**: Onboarding existing projects to Blueprint Development system, documenting implicit architecture decisions.

**Prerequisites**:
- Blueprint Development initialized (`docs/blueprint/` exists)
- Ideally PRD exists (run `/blueprint:derive-prd` first)

**Steps**:
## Phase 1: Discovery


### 1.1 Check Prerequisites
```bash
ls docs/blueprint/manifest.json
ls docs/prds/
```
If blueprint not initialized → suggest `/blueprint:init`
If no PRD → suggest `/blueprint:derive-prd` first (recommended, not required)


### 1.2 Create ADR Directory
```bash
mkdir -p docs/adrs
```


### 1.3 Analyze Project Structure
Explore the codebase to identify architectural patterns:

Use Explore agent:
```
<Task subagent_type="Explore" prompt="Analyze project architecture: directory structure, major components, frameworks used, design patterns">
```

Key areas to examine:
- **Directory structure**: How code is organized
- **Entry points**: Main files, index files
- **Configuration**: Config files, environment handling
- **Dependencies**: Package manifests, imports
- **Data layer**: Database, ORM, data models
- **API layer**: Routes, controllers, handlers
- **Testing**: Test structure and frameworks


## Phase 1.5: Conflict Analysis

Before generating new ADRs, check for existing decisions that may conflict or relate.


### 1.5.1 Check for Existing ADRs
```bash
ls docs/adrs/*.md 2>/dev/null | wc -l
```

If ADRs exist, analyze for potential conflicts with decisions about to be documented.


### 1.5.2 Determine Domain for New ADR

Map decision categories to domains:

| Decision Category | Domain Tag |
|------------------|------------|
| State Management | `state-management` |
| Database/ORM | `data-layer` |
| Framework Choice | `frontend-framework` |
| API Design | `api-design` |
| Authentication | `authentication` |
| Testing Strategy | `testing` |
| Styling Approach | `styling` |
| Build Tooling | `build-tooling` |
| Deployment | `deployment` |


### 1.5.3 Scan Existing ADRs in Same Domain

For each domain being documented:
```bash
grep -l "^domain: {domain}" docs/adrs/*.md
```

For each matching ADR with `status: Accepted`:
- Extract ADR number and title
- Extract decision outcome (chosen option)
- Calculate conflict score:
  - Same domain: +0.3
  - Both Accepted: +0.2
  - Opposite/different outcomes: +0.4
  - Age > 6 months: +0.1


### 1.5.4 Surface Potential Conflicts

If conflict score >= 0.7, prompt user:

```
question: "Found existing ADR in same domain: ADR-{XXXX} - {title}. How should the new decision relate?"
options:
  - label: "Supersede ADR-{XXXX}"
    description: "New ADR replaces the existing decision"
  - label: "Extend ADR-{XXXX}"
    description: "New ADR builds on the existing decision"
  - label: "Mark as related"
    description: "Decisions are connected but independent"
  - label: "No relationship"
    description: "Continue without linking"
```

Store the relationship choice for inclusion in the generated ADR frontmatter.


### 1.5.5 Handle Multiple Conflicts

If multiple potential conflicts in same domain:
- Present each for user decision
- Allow bulk "supersede all" option for replacing multiple outdated decisions


## Phase 2: Identify Architecture Decisions


### 2.1 Common Decision Categories

| Category | What to Look For | Example Decisions |
|----------|-----------------|-------------------|
| **Framework** | package.json, imports | React vs Vue, Express vs Fastify |
| **Language** | File extensions, tsconfig | TypeScript vs JavaScript |
| **State Management** | Store patterns, context | Redux vs Zustand vs Context |
| **Styling** | CSS files, styled imports | Tailwind vs CSS-in-JS vs SCSS |
| **Testing** | Test files, test config | Vitest vs Jest, Playwright vs Cypress |
| **Build** | Build config, bundlers | Vite vs Webpack, esbuild |
| **Database** | ORM config, migrations | PostgreSQL vs MongoDB, Prisma vs Drizzle |
| **API Style** | Route patterns, schemas | REST vs GraphQL, tRPC |
| **Deployment** | Docker, CI config | Container vs serverless |
| **Monorepo** | Workspace config | Turborepo vs Nx vs none |


### 2.2 Infer Decisions from Code
For each identified technology choice:
1. Note the current implementation
2. Consider common alternatives
3. Infer rationale from context/comments


### 2.3 Confirm with User
Use report to orchestrator for key decisions:

```
question: "I found the project uses {technology}. Why was this chosen over alternatives?"
options:
  - "Performance requirements" → document performance rationale
  - "Team familiarity" → document team expertise factor
  - "Ecosystem/community" → document ecosystem benefits
  - "Specific feature needs" → ask for details
  - "Legacy/inherited decision" → document as inherited
  - "Other" → custom rationale
```

```
question: "Are there any architecture decisions you'd like to document that aren't visible in the code?"
options:
  - "Yes, let me describe" → capture additional decisions
  - "No, the inferred decisions are sufficient" → proceed
```


## Phase 3: ADR Generation


### 3.1 ADR Template (MADR format)
For each significant decision, create an ADR:

```markdown
---
id: ADR-{NNNN}                          # Derived from filename (0003-*.md → ADR-0003)
date: {YYYY-MM-DD}
status: Accepted | Superseded | Deprecated | Proposed
deciders: {who made the decision}
domain: {domain-tag}                    # Optional: state-management, data-layer, etc.
supersedes: ADR-{XXXX}                  # Optional: if superseding another ADR
extends: ADR-{XXXX}                     # Optional: if extending another ADR
relates-to:                             # Cross-document references
  - PRD-{NNN}                           # Related PRDs
  - ADR-{YYYY}                          # Related ADRs
github-issues: []                       # Linked GitHub issues
name: blueprint-derive-adr
---


# ADR-{number}: {Title}


## Decision Drivers

- {driver 1, e.g., "Performance under high load"}
- {driver 2, e.g., "Developer experience"}
- {driver 3, e.g., "Maintainability"}


## Considered Options

1. **{Option 1}** - {brief description}
2. **{Option 2}** - {brief description}
3. **{Option 3}** - {brief description}


## Decision Outcome

**Chosen option**: "{Option X}" because {justification}.


### Positive Consequences

- {positive outcome 1}
- {positive outcome 2}


### Negative Consequences

- {negative outcome / tradeoff 1}
- {negative outcome / tradeoff 2}


## Pros and Cons of Options


### {Option 1}

- ✅ {pro 1}
- ✅ {pro 2}
- ❌ {con 1}


### {Option 2}

- ✅ {pro 1}
- ❌ {con 1}
- ❌ {con 2}


## Links

- {Related ADRs}
- {External documentation}
- {Discussion threads}

---
*Generated from project analysis via /blueprint:derive-adr*
```


### 3.2 Standard ADRs to Generate

Generate ADRs for these common decisions (if applicable):

| ADR | When to Create |
|-----|----------------|
| `0001-project-language.md` | Language/runtime choice |
| `0002-framework-choice.md` | Main framework selection |
| `0003-testing-strategy.md` | Test framework and approach |
| `0004-styling-approach.md` | CSS/styling methodology |
| `0005-state-management.md` | State handling (if applicable) |
| `0006-database-choice.md` | Database and ORM (if applicable) |
| `0007-api-design.md` | API style and patterns |
| `0008-deployment-strategy.md` | Deployment approach |


### 3.3 Create ADR README

Write the ADR README template to `docs/adrs/README.md` using the template from `blueprint-plugin/templates/adr-readme.md`.

The README is self-documenting: it includes a programmatic `fd` + `awk` command that generates the ADR index on demand, eliminating static tables that drift out of sync.

**Customizations when writing**:
- If undocumented decisions were identified during Phase 2 analysis that the user chose not to create full ADRs for, add them to the **Proposed ADRs** section:
  ```markdown
  ## Proposed ADRs

  Decisions identified but not yet documented as full ADRs:

  - [ ] {Decision topic} — {brief context} (identified {YYYY-MM-DD})
  - [ ] {Decision topic} — {brief context} (identified {YYYY-MM-DD})
  ```
- Keep the programmatic listing command intact — it replaces the need for a static index


## Phase 4: Relationship Updates & Validation


### 4.0 Update Superseded ADRs (Bidirectional Consistency)

If any new ADR supersedes an existing ADR:

1. **Read the superseded ADR file**
2. **Update its frontmatter**:
   - Change `status: Accepted` to `status: Superseded`
   - Add `superseded_by: ADR-{new_number}`
3. **Update the Links section** (add if missing):
   ```markdown
   ## Links
   - Superseded by [ADR-{number}](./{filename}.md)
   ```

4. **Report the update**:
   ```
   Updated ADR-{old_number}:
   - Status: Accepted → Superseded
   - Added: superseded_by: ADR-{new_number}
   - Updated Links section
   ```

**Example**: If ADR-0012 supersedes ADR-0003:
- In ADR-0012: `supersedes: ADR-0003`
- In ADR-0003:
  - `status: Superseded`
  - `superseded_by: ADR-0012`
  - Links section references ADR-0012


### 4.1 Update Manifest

Update `docs/blueprint/manifest.json` ID registry for each ADR:

```json
{
  "id_registry": {
    "documents": {
      "ADR-0003": {
        "path": "docs/adrs/0003-database-choice.md",
        "title": "Database Choice",
        "status": "Accepted",
        "domain": "data-layer",
        "relates_to": ["PRD-001"],
        "github_issues": [],
        "created": "{date}"
      }
    }
  }
}
```


### 4.2 Present Summary
```
✅ ADRs Generated: {count} records

**Location**: `docs/adrs/`

**Decisions documented**:
- ADR-0001: {title} - {status} [{domain}]
- ADR-0002: {title} - {status} [{domain}]
...

**Relationships established**:
- ADR-{new} supersedes ADR-{old} (status updated)
- ADR-{new} extends ADR-{existing}
- ADR-{new} related to ADR-{other}

**ADRs updated** (bidirectional consistency):
- ADR-{old}: status → Superseded, superseded_by → ADR-{new}

**Sources analyzed**:
- {list of analyzed files/patterns}

**Confidence levels**:
- High confidence: {list - clear from code}
- Inferred: {list - reasonable assumptions}
- Needs review: {list - uncertain}

**Recommended next steps**:
1. Review generated ADRs for accuracy
2. Add rationale where marked as "inferred"
3. Run `/blueprint:derive-adr-validate` to check relationship consistency
4. Run `/blueprint:prp-create` for feature implementation
5. Run `/blueprint:generate-skills` for project skills
```


### 4.2 Suggest Next Steps
- If PRD missing → suggest `/blueprint:derive-prd`
- If ready for implementation → suggest `/blueprint:prp-create`
- If architecture evolving → explain how to add new ADRs


## Phase 5: Update Manifest

Update `docs/blueprint/manifest.json`:
- Add `has_adrs: true` to structure
- Add ADRs to `generated_artifacts`
- Update `updated_at` timestamp

**Tips**:
- Focus on decisions with real alternatives (not obvious choices)
- Document inherited/legacy decisions as such
- Mark uncertain rationales for user review
- Keep ADRs concise - focus on "why", not implementation details
- Reference related ADRs when decisions are connected


### 4.3 Prompt for next action (use report to orchestrator):

```
question: "ADRs generated. What would you like to do next?"
options:
  - label: "Create a PRP for feature work (Recommended)"
    description: "Start implementing a specific feature with /blueprint:prp-create"
  - label: "Generate project skills"
    description: "Create skills from PRDs for Claude context"
  - label: "Review and add rationale"
    description: "Edit ADRs marked as 'inferred' or 'needs rationale'"
  - label: "Document another architecture decision"
    description: "Manually add a new ADR"
  - label: "I'm done for now"
    description: "Exit - ADRs are saved"
```

**Based on selection:**
- "Create a PRP" → Run `/blueprint:prp-create` (ask for feature name)
- "Generate project skills" → Run `/blueprint:generate-skills`
- "Review and add rationale" → Show ADR files needing attention
- "Document another decision" → Restart Phase 2 for a specific decision
- "I'm done" → Exit

**Error Handling**:
- If minimal codebase → create fewer, broader ADRs
- If conflicting patterns → ask user which is intentional
- If rationale unclear → mark as "needs rationale" for user input

---

## blueprint-sync-ids

Scan all PRDs, ADRs, PRPs, and work-orders, assign IDs to documents missing them, and update the manifest registry.
## Prerequisites

- Blueprint initialized (`docs/blueprint/manifest.json` exists)
- At least one document exists in `docs/prds/`, `docs/adrs/`, `docs/prps/`, or `docs/blueprint/work-orders/`


## Steps


### Step 1: Initialize ID Registry

Check if `id_registry` exists in manifest:

```bash
jq -e '.id_registry' docs/blueprint/manifest.json >/dev/null 2>&1
```

If not, initialize it:

```json
{
  "id_registry": {
    "last_prd": 0,
    "last_prp": 0,
    "documents": {},
    "github_issues": {}
  }
}
```


### Step 2: Scan PRDs

```bash
for prd in docs/prds/*.md; do
  [ -f "$prd" ] || continue

  # Check for existing ID in frontmatter
  existing_id=$(head -50 "$prd" | grep -m1 "^id:" | sed 's/^id:[[:space:]]*//')

  if [ -z "$existing_id" ]; then
    echo "NEEDS_ID: $prd"
  else
    echo "HAS_ID: $prd ($existing_id)"
  fi
done
```


### Step 3: Scan ADRs

```bash
for adr in docs/adrs/*.md; do
  [ -f "$adr" ] || continue

  # ADR ID derived from filename (0001-title.md → ADR-0001)
  filename=$(basename "$adr")
  num=$(echo "$filename" | grep -oE '^[0-9]{4}')

  if [ -n "$num" ]; then
    expected_id="ADR-$num"
    existing_id=$(head -50 "$adr" | grep -m1 "^id:" | sed 's/^id:[[:space:]]*//')

    if [ -z "$existing_id" ]; then
      echo "NEEDS_ID: $adr (should be $expected_id)"
    elif [ "$existing_id" != "$expected_id" ]; then
      echo "MISMATCH: $adr (has $existing_id, should be $expected_id)"
    else
      echo "HAS_ID: $adr ($existing_id)"
    fi
  fi
done
```


### Step 4: Scan PRPs

```bash
for prp in docs/prps/*.md; do
  [ -f "$prp" ] || continue

  existing_id=$(head -50 "$prp" | grep -m1 "^id:" | sed 's/^id:[[:space:]]*//')

  if [ -z "$existing_id" ]; then
    echo "NEEDS_ID: $prp"
  else
    echo "HAS_ID: $prp ($existing_id)"
  fi
done
```


### Step 5: Scan Work-Orders

```bash
for wo in docs/blueprint/work-orders/*.md; do
  [ -f "$wo" ] || continue

  # WO ID derived from filename (003-task.md → WO-003)
  filename=$(basename "$wo")
  num=$(echo "$filename" | grep -oE '^[0-9]{3}')

  if [ -n "$num" ]; then
    expected_id="WO-$num"
    existing_id=$(head -50 "$wo" | grep -m1 "^id:" | sed 's/^id:[[:space:]]*//')

    if [ -z "$existing_id" ]; then
      echo "NEEDS_ID: $wo (should be $expected_id)"
    else
      echo "HAS_ID: $wo ($existing_id)"
    fi
  fi
done
```


### Step 6: Report Findings

```
Document ID Scan Results

PRDs:
- With IDs: X
- Missing IDs: Y
  - docs/prds/feature-a.md
  - docs/prds/feature-b.md

ADRs:
- With IDs: X
- Missing IDs: Y
- Mismatched IDs: Z

PRPs:
- With IDs: X
- Missing IDs: Y

Work-Orders:
- With IDs: X
- Missing IDs: Y

Total: X documents, Y need IDs
```


### Step 7: Assign IDs (unless `--dry-run`)

For each document needing an ID:

**PRDs**:
1. Get next PRD number: `jq '.id_registry.last_prd' manifest.json` + 1
2. Generate ID: `PRD-NNN` (zero-padded)
3. Insert into frontmatter after first `---`:
   ```yaml
   id: PRD-001
   ```
4. Update manifest: increment `last_prd`, add to `documents`

**ADRs**:
1. Derive ID from filename: `0003-title.md` → `ADR-0003`
2. Insert into frontmatter
3. Add to manifest `documents`

**PRPs**:
1. Get next PRP number: `jq '.id_registry.last_prp' manifest.json` + 1
2. Generate ID: `PRP-NNN`
3. Insert into frontmatter
4. Update manifest: increment `last_prp`, add to `documents`

**Work-Orders**:
1. Derive ID from filename: `003-task.md` → `WO-003`
2. Insert into frontmatter
3. Add to manifest `documents`


### Step 8: Extract Titles and Links

For each document, also extract:
- **Title**: First `# ` heading or frontmatter `name`/`title` field
- **Existing links**: `relates-to`, `implements`, `github-issues` from frontmatter
- **Status**: From frontmatter

Store in manifest registry:

```json
{
  "documents": {
    "PRD-001": {
      "path": "docs/prds/user-auth.md",
      "title": "User Authentication",
      "status": "Active",
      "relates_to": ["ADR-0003"],
      "github_issues": [42],
      "created": "2026-01-15"
    }
  }
}
```


### Step 9: Build GitHub Issue Index

Scan all documents for `github-issues` field and build reverse index:

```json
{
  "github_issues": {
    "42": ["PRD-001", "PRP-002"],
    "45": ["WO-003"]
  }
}
```


### Step 10: Create Issues for Orphans (if `--link-issues`)

For each document without `github-issues`:

```
question: "Create GitHub issue for {ID}: {title}?"
options:
  - label: "Yes, create issue"
    description: "Creates [{ID}] {title} issue"
  - label: "Skip this one"
    description: "Leave unlinked for now"
  - label: "Skip all remaining"
    description: "Don't prompt for more orphans"
```

If yes:
```bash
gh issue create \
  --title "[{ID}] {title}" \
  --body "## {Document Type}

**ID**: {ID}
**Document**: \`{path}\`

{Brief description from document}

---
*Auto-generated by /blueprint:sync-ids*" \
  --label "{type-label}"
```

Update document frontmatter and manifest with new issue number.


### Step 11: Update task registry

Update the task registry entry in `docs/blueprint/manifest.json`:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson processed "${DOCS_CHECKED:-0}" \
  --argjson created "${IDS_ASSIGNED:-0}" \
  '.task_registry["sync-ids"].last_completed_at = $now |
   .task_registry["sync-ids"].last_result = "success" |
   .task_registry["sync-ids"].stats.runs_total = ((.task_registry["sync-ids"].stats.runs_total // 0) + 1) |
   .task_registry["sync-ids"].stats.items_processed = $processed |
   .task_registry["sync-ids"].stats.items_created = $created' \
  docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
```


### Step 12: Final Report

```
ID Sync Complete

Assigned IDs:
- PRD-003: docs/prds/payment-flow.md
- PRD-004: docs/prds/notifications.md
- PRP-005: docs/prps/stripe-integration.md

Updated Manifest:
- last_prd: 4
- last_prp: 5
- documents: 22 entries
- github_issues: 18 mappings

{If --link-issues:}
Created GitHub Issues:
- #52: [PRD-003] Payment Flow
- #53: [PRP-005] Stripe Integration

Still orphaned (no GitHub issues):
- ADR-0004: Database Migration Strategy
- WO-008: Add error handling

Run `/blueprint:status` to see full traceability report.
```


## Error Handling

| Condition | Action |
|-----------|--------|
| No manifest | Error: Run `/blueprint:init` first |
| No documents found | Warning: No documents to scan |
| Frontmatter parse error | Warning: Skip file, report for manual fix |
| `gh` not available | Skip issue creation, warn user |
| Write permission denied | Error: Check file permissions |


## Manifest Schema

After sync, manifest includes:

```json
{
  "id_registry": {
    "last_prd": 4,
    "last_prp": 5,
    "documents": {
      "PRD-001": {
        "path": "docs/prds/user-auth.md",
        "title": "User Authentication",
        "status": "Active",
        "relates_to": ["ADR-0003"],
        "implements": [],
        "github_issues": [42],
        "created": "2026-01-10"
      },
      "ADR-0003": {
        "path": "docs/adrs/0003-session-storage.md",
        "title": "Session Storage Strategy",
        "status": "Accepted",
        "domain": "authentication",
        "relates_to": ["PRD-001"],
        "github_issues": [],
        "created": "2026-01-12"
      }
    },
    "github_issues": {
      "42": ["PRD-001", "PRP-002"],
      "45": ["WO-003"]
    }
  }
}
```

---

## blueprint-derive-rules

# /blueprint:derive-rules

Extract project decisions from git commit history and codify them as Claude rules. Newer commits override older decisions when conflicts exist.

**Use case**: Derive implicit project patterns from git history to establish consistent AI-assisted development guidelines.

**Usage**: `/blueprint:derive-rules [--since DATE] [--scope SCOPE]`


## Execution

Execute the complete git-to-rules derivation workflow:


### Step 1: Verify prerequisites

1. If not a git repository → Error: "This directory is not a git repository"
2. If Blueprint not initialized → Suggest `/blueprint:init` first
3. If few commits (< 20) → Warn: "Limited commit history; derived rules may be incomplete"


### Step 2: Analyze git history quality

1. Calculate total commits in scope
2. Calculate conventional commits percentage
3. Report quality: Higher % = higher confidence in extracted rules
4. Parse `--since` and `--scope` flags to determine analysis range


### Step 3: Extract decision-bearing commits

Use parallel agents to analyze git history efficiently (see [REFERENCE.md](REFERENCE.md#git-analysis)):

- **Agent 1**: Analyze `refactor:` commits for code style patterns
- **Agent 2**: Analyze `fix:` commits for repeated issue types
- **Agent 3**: Analyze `feat!:` and `BREAKING CHANGE:` commits for architecture decisions
- **Agent 4**: Analyze `chore:` and `build:` commits for tooling decisions

Consolidate findings by domain (code-style, testing, api-design, etc.), chronologically (newest first), and by frequency (most common wins).


### Step 4: Resolve conflicts

When multiple commits address the same topic:

1. Detect conflicts using pattern matching: `git log --format="%H|%ai|%s" | grep "{topic}"`
2. Apply resolution strategy:
   - **Newer overrides older**: Latest decision wins
   - **Higher frequency wins**: If 5 commits say X and 1 says Y, X wins
   - **Breaking changes override**: `feat!:` trumps regular commits
3. Mark overridden decisions as "superseded" with reference to newer decision
4. Confirm significant decisions with user via report to orchestrator


### Step 5: Generate rules in `.claude/rules/`

For each decision, generate rule file using template from [REFERENCE.md](REFERENCE.md#rule-template):

1. Extract source commit, date, type
2. Determine confidence level (High/Medium/Low based on commit frequency and clarity)
3. Generate actionable rule statement
4. Include code examples from commit diffs
5. Reference any superseded earlier decisions
6. Add `paths` frontmatter when the rule is naturally scoped to specific file types (see [REFERENCE.md](REFERENCE.md#rule-categories) for suggested patterns per category)

Generate separate rule files by category (see [REFERENCE.md](REFERENCE.md#rule-categories)):
- `code-style.md`, `testing-standards.md`, `api-conventions.md`, `error-handling.md`, `dependencies.md`, `security-practices.md`

Path-scope rules where appropriate — e.g., `testing-standards.md` scoped to test files reduces context noise when working on non-test code.


### Step 6: Handle conflicts with existing rules

Check for conflicts with existing rules in `.claude/rules/`:

1. If conflicts found → Ask user: Git-derived overrides existing rule, or keep existing?
2. Apply user choice: Update, merge, or keep separate
3. Document conflict resolution in rule file


### Step 7: Update task registry

Update the task registry entry in `docs/blueprint/manifest.json`:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sha "$(git rev-parse HEAD 2>/dev/null)" \
  --argjson processed "${COMMITS_ANALYZED:-0}" \
  --argjson created "${RULES_DERIVED:-0}" \
  '.task_registry["derive-rules"].last_completed_at = $now |
   .task_registry["derive-rules"].last_result = "success" |
   .task_registry["derive-rules"].context.commits_analyzed_up_to = $sha |
   .task_registry["derive-rules"].stats.runs_total = ((.task_registry["derive-rules"].stats.runs_total // 0) + 1) |
   .task_registry["derive-rules"].stats.items_processed = $processed |
   .task_registry["derive-rules"].stats.items_created = $created' \
  docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
```


### Step 8: Update manifest and report

1. Update `docs/blueprint/manifest.json` with derived rules metadata: timestamp, commits analyzed, rules generated, source commits
2. Generate completion report showing:
   - Commits analyzed (count and date range)
   - Conventional commits percentage
   - Rules generated by category
   - Confidence scores per rule
   - Any conflicts resolved
3. Prompt user for next action: Review rules, execute derived development workflow, or done


# blueprint-derive-rules REFERENCE

Reference material for git analysis patterns, rule templates, and conflict resolution procedures.


## Git Analysis Patterns


### Decision Indicators

| Pattern | Rule Category | Examples |
|---------|---|---|
| `refactor:` + consistent pattern | Code style | File organization, naming conventions, imports |
| `fix:` repeated for same issue | Prevention | Common bugs, security issues, performance problems |
| `feat!:` / `BREAKING CHANGE:` | Architecture | API changes, dependency migrations, pattern switches |
| `chore:` + tooling changes | Tooling | Linter configs, formatter settings, CI changes |
| `style:` + formatting | Formatting | Indentation, spacing, code formatting |
| `test:` + testing approach | Testing | Test patterns, coverage, fixtures |
| `docs:` + documentation | Documentation | Documentation patterns, comment style |


### Extraction Commands

**Extract decision-bearing commits:**
```bash
git log --format="%H|%s|%b" {scope} | grep -E "(always|never|must|should|prefer|avoid|instead of|replaced|switched|adopted|dropped)"
```

**Group by domain:**
```bash
git log --oneline --format="%s" {scope} | sed 's/^[a-z]*(\([^)]*\)).*/\1/' | sort | uniq -c | sort -rn
```

**Detect conflicts (same topic):**
```bash
git log --format="%H|%ai|%s" | grep -i "{topic}" | sort -t'|' -k2 -r
```


## Rule Template

Rules may include an optional `paths` frontmatter to scope them to specific file types or directories. Add `paths` when the rule only applies to certain parts of the codebase — this reduces context noise and keeps rules relevant.

**Global rule** (applies to all files — no frontmatter needed):
```markdown

# {Rule Title}

{Rule description derived from commit message/body}


## Source

- **Commit**: {sha} ({date})
- **Type**: {feat|fix|refactor|chore}
- **Confidence**: {High|Medium|Low}


## Rule

{Clear, actionable rule statement}


## Examples


### Do
\`\`\`{language}
{Good example from commit diff or codebase}
\`\`\`


### Don't
\`\`\`{language}
{Counter-example if available}
\`\`\`


## Supersedes

{List any earlier decisions this overrides, or "None"}

---

*Derived from git history via /blueprint:derive-rules*
```

**Path-scoped rule** (add `paths` frontmatter when rule only applies to specific files):
```markdown
---
paths:
  - "{glob-pattern}"
  - "{glob-pattern}"
---


# {Rule Title}

{Rule description — applies only to matched paths}


## Source
...
```


## Rule Categories

Generate separate rule files by category. Apply `paths` frontmatter where the rule is naturally scoped to specific file types or directories:

| File | Content | Source Commits | Suggested `paths` |
|------|---------|---|---|
| `code-style.md` | Naming, formatting, structure rules | `refactor:`, `style:` | *(global — omit paths)* |
| `testing-standards.md` | Testing approach, coverage, fixtures | `test:` | `["**/*.{test,spec}.*", "tests/**/*", "test/**/*"]` |
| `api-conventions.md` | Endpoint patterns, error handling | `feat:` (api scope), `fix:` (api scope) | `["src/{api,routes}/**/*", "**/*controller*", "**/*handler*"]` |
| `error-handling.md` | Exception patterns, fallbacks | `fix:` (error-related) | *(global — omit paths)* |
| `dependencies.md` | Package management, version policies | `chore:` (deps), `build:` | `["package.json", "go.mod", "Cargo.toml", "pyproject.toml", "*.lock"]` |
| `security-practices.md` | Auth, validation, secrets handling | `fix:` (security), `feat:` (security) | *(global — omit paths)* |

**Path scoping guidance**: Use `paths` when the rule only makes sense in context of specific files. Omit `paths` for rules that apply universally (e.g., error handling philosophy, security mindset). Use brace expansion for concise patterns: `*.{ts,tsx}`, `src/{api,routes}/**/*`.


## Conflict Resolution Strategy


### Detection
Find commits addressing same topic:
```bash
git log --format="%H|%ai|%s" | grep -i "{topic}" | sort -t'|' -k2 -r
```


### Resolution Rules
1. **Newer overrides older**: Latest decision wins
2. **Higher frequency wins**: If 5 commits say X and 1 says Y, X wins
3. **Breaking changes override**: `feat!:` trumps regular commits


### Handling Existing Rules
When conflict with existing rules in `.claude/rules/`:

| Option | Action |
|--------|--------|
| Git-derived overrides | Update existing rule with git-derived content |
| Keep existing | Use existing rule, document git decision as alternative |
| Merge both | Combine into comprehensive rule with both perspectives |
| Create separate | Add git-derived as additional rule |


### Superseding Pattern
Document overridden decisions:
```markdown

## Supersedes

- **Previous rule**: `code-style.md` - Naming convention v1 (commit abc1234)
- **Reason**: Updated to match newer pattern in commit def5678 (more common, 7 commits)
```


## Confidence Scoring

Rate confidence based on:

| Score | Criteria |
|-------|----------|
| **High** | Pattern appears 5+ times, explicit commit message, breaking change |
| **Medium** | Pattern appears 2-4 times, clear intent but not explicit |
| **Low** | Pattern appears 1 time, inferred from code change only |


## Manifest Format

```json
{
  "derived_rules": {
    "last_derived_at": "ISO-8601-timestamp",
    "commits_analyzed": N,
    "conventional_commits_percentage": 85,
    "rules_generated": N,
    "rules_by_category": {
      "code-style": N,
      "testing-standards": N,
      "api-conventions": N,
      "error-handling": N,
      "dependencies": N,
      "security-practices": N
    },
    "source_commits": [
      {
        "sha": "{sha}",
        "date": "ISO-8601",
        "type": "refactor|fix|feat|chore",
        "message": "commit message",
        "rule_generated": "code-style.md"
      }
    ]
  }
}
```


## Tips

- **High commit quality**: More conventional commits = more reliable rules
- **Frequency matters**: Patterns that appear multiple times are more trustworthy
- **Recency wins**: Newer decisions override older ones
- **Breaking changes signal**: `feat!:` or `BREAKING CHANGE` indicates important architectural decision
- **User confirmation**: Always ask about significant decisions before making them rules

---

## blueprint-derive-tests

# /blueprint:derive-tests

Analyze git history to identify fix and feature commits lacking corresponding test changes, then generate a structured Test Regression Plan (TRP) document as a prioritized test backlog.

**Use case**: Systematically close test coverage gaps by mining commit history for bug fixes and features that shipped without regression tests.


## Execution

Execute this test regression plan derivation workflow:


### Step 1: Verify prerequisites

Check context values above:

1. If git repository is empty → Error: "This directory is not a git repository. Run from project root."
2. If total commits = "0" → Error: "Repository has no commit history."
3. If Blueprint initialized is empty → Ask user: "Blueprint not initialized. Initialize now (Recommended) or continue without manifest tracking?"
   - If "Initialize now" → Use Task tool to invoke `/blueprint:init`, then continue
   - If "Continue without" → Skip manifest updates in Step 7


### Step 2: Determine analysis scope

Parse `$ARGUMENTS` for `--quick`, `--since`, and `--scope`:

1. If `--quick` → scope = last 50 commits
2. If `--since DATE` → scope = commits from DATE to now
3. If `--scope AREA` → filter commits to those with scope matching AREA or touching files in AREA directory
4. Otherwise → scope = last 200 commits

Store scope parameters for git log commands in subsequent steps.


### Step 3: Detect test infrastructure

Scan for test framework and conventions:

1. Identify test framework from context (vitest, jest, pytest, cargo test, go test)
2. Detect test file naming convention:
   - `*.test.ts`, `*.spec.ts` (JS/TS)
   - `test_*.py`, `*_test.py` (Python)
   - `*_test.rs`, `tests/` directory (Rust)
   - `*_test.go` (Go)
3. Map source directories to test directories (e.g., `src/` → `tests/`, `src/` → `src/__tests__/`)
4. Record framework, naming pattern, and directory mapping for Step 5

If no test framework detected → Warn user, continue with file-based detection only.


### Step 4: Extract and classify commits

Extract fix and feature commits within scope:

1. **Primary targets** — `fix:` commits (highest priority for regression tests):
   ```bash
   git log --format="%H %s" {scope} | grep -E "^[a-f0-9]+ fix(\(.*\))?:"
   ```

2. **Secondary targets** — `feat:` commits (should have accompanying tests):
   ```bash
   git log --format="%H %s" {scope} | grep -E "^[a-f0-9]+ feat(\(.*\))?:"
   ```

3. **Fallback** — If conventional commit percentage < 20%, use keyword detection:
   ```bash
   git log --format="%H %s" {scope} | grep -iE "(fix|bug|hotfix|patch|resolve|correct)"
   ```

For each commit, record: SHA, subject, date, files changed, scope (if conventional).


### Step 5: Analyze test coverage gaps

For each commit from Step 4, check for corresponding tests:

1. **Inline test changes** — Did the same commit modify test files?
   ```bash
   git diff-tree --no-commit-id --name-only -r {SHA} | grep -E "(test|spec|_test\.|\.test\.)"
   ```

2. **Nearby test commits** — Within 5 commits after the fix, was a test commit added?
   ```bash
   git log --format="%H %s" {SHA}..{SHA~5} | grep -iE "^[a-f0-9]+ test(\(.*\))?:|add.*test|test.*for"
   ```

3. **Test file exists** — For each modified source file, does a corresponding test file exist?
   Use the source-to-test mapping from Step 3 (see [REFERENCE.md](REFERENCE.md#test-to-source-mapping) for rules per language).

Classify each gap using the severity matrix from [REFERENCE.md](REFERENCE.md#severity-classification):

| Severity | Criteria |
|----------|----------|
| Critical | `fix:` commit, no test changes, no test file exists for modified source |
| High | `fix:` commit, no inline test changes but test file exists (test not updated) |
| Medium | `feat:` commit, no test changes, core module affected |
| Low | `feat:` commit, no inline tests but nearby test commit exists |


### Step 6: Generate TRP document

1. Create output directory: `mkdir -p docs/trps`
2. Determine TRP ID:
   - If manifest exists, read `id_registry.last_trp`, increment by 1
   - Otherwise start at `TRP-001`
3. Generate slug from scope or date range (e.g., `regression-gaps-2024-q3`)
4. Write TRP document to `docs/trps/{slug}.md` using template from [REFERENCE.md](REFERENCE.md#trp-document-template)

Include in the document:
- YAML frontmatter with `id`, `status: Active`, `scope`, `date_range`, `commits_analyzed`
- Executive summary with gap counts by severity
- Detailed gap table: commit SHA, subject, severity, affected files, suggested test type
- Recommended test creation order (Critical first, then High, etc.)
- Suggested test type per gap (see [REFERENCE.md](REFERENCE.md#suggested-test-types))


### Step 7: Update manifest

If Blueprint is initialized:

1. Update `id_registry.last_trp` with the new TRP number
2. Register the document in `id_registry.documents`:
   ```json
   {
     "TRP-NNN": {
       "path": "docs/trps/{slug}.md",
       "title": "{TRP title}",
       "status": "Active",
       "created": "{date}"
     }
   }
   ```
3. Update task registry:
   ```bash
   jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     --arg sha "$(git rev-parse HEAD 2>/dev/null)" \
     --argjson analyzed "{commits_analyzed}" \
     --argjson gaps "{gaps_found}" \
     '.task_registry["derive-tests"].last_completed_at = $now |
      .task_registry["derive-tests"].last_result = "success" |
      .task_registry["derive-tests"].stats.runs_total = ((.task_registry["derive-tests"].stats.runs_total // 0) + 1) |
      .task_registry["derive-tests"].stats.items_processed = $analyzed |
      .task_registry["derive-tests"].stats.items_created = $gaps |
      .task_registry["derive-tests"].context.commits_analyzed_up_to = $sha' \
     docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
   ```


### Step 8: Report results and suggest next actions

Print summary:

```
Test Regression Plan Generated!

**Analysis Summary**
- Commits analyzed: {N} ({date_range})
- Fix commits found: {N}
- Feature commits found: {N}

**Coverage Gaps Found**
- Critical: {N} (fix commits with no tests at all)
- High: {N} (fix commits with stale test files)
- Medium: {N} (feature commits missing tests)
- Low: {N} (feature commits with nearby tests)

**Document**: docs/trps/{slug}.md (TRP-{NNN})

**Top Priority Gaps**
1. {commit subject} — {severity} — {affected file}
2. {commit subject} — {severity} — {affected file}
3. {commit subject} — {severity} — {affected file}
```

Prompt user for next action:

- "Create PRPs for top-priority gaps (Recommended)" — Generate PRP documents for Critical/High gaps
- "Review the TRP document" — Open the generated TRP for manual review
- "Run again with different scope" — Re-run with `--since` or `--scope`
- "Done for now" — Exit with document saved


# blueprint-derive-tests REFERENCE

Reference material for TRP document templates, severity classification, test mapping rules, and error handling.


## TRP Document Template

```markdown
---
id: TRP-{NNN}
created: {date}
modified: {date}
status: Active
scope: "{scope or 'full'}"
date_range: "{start_date} to {end_date}"
commits_analyzed: {count}
test_framework: "{framework}"
relates-to: []
github-issues: []
---


# TRP-{NNN}: {Title}

Test Regression Plan identifying coverage gaps from git history analysis.


## Executive Summary

| Severity | Count | Description |
|----------|-------|-------------|
| Critical | {N} | Fix commits with no tests at all |
| High | {N} | Fix commits with stale/unupdated test files |
| Medium | {N} | Feature commits missing tests in core modules |
| Low | {N} | Feature commits with nearby test commits |
| **Total** | **{N}** | |

**Analysis scope**: {N} commits from {start_date} to {end_date}
**Test framework**: {framework}


## Critical Gaps

Highest priority — bug fixes shipped without any regression test.

| # | Commit | Date | Subject | Affected Files | Suggested Test |
|---|--------|------|---------|----------------|----------------|
| 1 | `{short_sha}` | {date} | {subject} | `{file}` | {test_type} |


### Gap Details

#### Gap 1: {Commit subject}

- **Commit**: {full_sha}
- **Date**: {date}
- **Files changed**: {list}
- **Why critical**: No test file exists for `{source_file}`
- **Suggested test**: Create `{test_file_path}` with regression test verifying the fix behavior
- **Test scenario**: Reproduce the bug condition, assert the fix handles it correctly


## High Gaps

Fix commits where test files exist but were not updated.

| # | Commit | Date | Subject | Test File | Suggested Action |
|---|--------|------|---------|-----------|------------------|
| 1 | `{short_sha}` | {date} | {subject} | `{test_file}` | Add regression case |


## Medium Gaps

Feature commits in core modules without accompanying tests.

| # | Commit | Date | Subject | Module | Suggested Test |
|---|--------|------|---------|--------|----------------|
| 1 | `{short_sha}` | {date} | {subject} | {module} | {test_type} |


## Low Gaps

Feature commits with nearby test coverage (within 5 commits).

| # | Commit | Date | Subject | Nearby Test | Status |
|---|--------|------|---------|-------------|--------|
| 1 | `{short_sha}` | {date} | {subject} | `{nearby_sha}` | Likely covered |


## Recommended Test Creation Order

Priority-ordered list for systematic gap closure:

1. **Critical gaps first** — Each represents a confirmed bug fix with zero test coverage
2. **High gaps second** — Test infrastructure exists, just needs a new test case
3. **Medium gaps** — New test files needed, but lower urgency than bug fixes
4. **Low gaps** — Verify existing nearby tests actually cover the behavior


## Module Coverage Summary

| Module/Scope | Fix Commits | With Tests | Gap % |
|--------------|-------------|------------|-------|
| {scope} | {N} | {N} | {N}% |

---

**Generated by**: /blueprint:derive-tests
**Analysis date**: {date}
**Commits analyzed**: {count}
```


## Test-to-Source Mapping

Rules for mapping source files to expected test file locations, by language.


### TypeScript / JavaScript

| Source Pattern | Test Pattern | Example |
|---------------|-------------|---------|
| `src/foo.ts` | `src/foo.test.ts` | `src/auth.ts` → `src/auth.test.ts` |
| `src/foo.ts` | `src/foo.spec.ts` | `src/auth.ts` → `src/auth.spec.ts` |
| `src/foo.ts` | `src/__tests__/foo.test.ts` | `src/auth.ts` → `src/__tests__/auth.test.ts` |
| `src/foo.ts` | `tests/foo.test.ts` | `src/auth.ts` → `tests/auth.test.ts` |
| `src/components/Foo.tsx` | `src/components/Foo.test.tsx` | Co-located test |
| `src/components/Foo.tsx` | `src/components/__tests__/Foo.test.tsx` | Nested `__tests__` |

**Detection order**: Check co-located first, then `__tests__/`, then `tests/` at project root.


### Python

| Source Pattern | Test Pattern | Example |
|---------------|-------------|---------|
| `src/foo.py` | `tests/test_foo.py` | `src/auth.py` → `tests/test_auth.py` |
| `src/foo.py` | `tests/foo_test.py` | `src/auth.py` → `tests/auth_test.py` |
| `src/pkg/foo.py` | `tests/pkg/test_foo.py` | Mirror directory structure |
| `foo.py` | `test_foo.py` | Same directory convention |

**Detection order**: Check `tests/test_{name}.py` first, then `tests/{name}_test.py`, then co-located.


### Rust

| Source Pattern | Test Pattern | Example |
|---------------|-------------|---------|
| `src/foo.rs` | `src/foo.rs` (inline `#[cfg(test)]`) | Check for `mod tests` block |
| `src/foo.rs` | `tests/foo.rs` | Integration tests |
| `src/lib.rs` | `tests/integration_test.rs` | Library integration tests |

**Detection order**: Check inline `#[cfg(test)]` first, then `tests/` directory.


### Go

| Source Pattern | Test Pattern | Example |
|---------------|-------------|---------|
| `foo.go` | `foo_test.go` | Co-located by convention |
| `pkg/foo.go` | `pkg/foo_test.go` | Same package |

**Detection order**: Always co-located (`{name}_test.go` next to `{name}.go`).


## Severity Classification

Matrix for classifying test coverage gaps.


### Primary Classification (Commit Type)

| Commit Type | Base Severity |
|-------------|---------------|
| `fix:` / bug-related | Critical or High |
| `feat:` / feature | Medium or Low |
| `refactor:` | Low (only if behavior changes) |
| `perf:` | Medium (performance regression risk) |


### Severity Modifiers

| Factor | Raises Severity | Lowers Severity |
|--------|----------------|-----------------|
| No test file exists for source | +1 level | — |
| Test file exists but not updated | — | -1 level |
| Core module (auth, payments, data) | +1 level | — |
| Peripheral module (docs, config) | — | -1 level |
| Recent commit (< 30 days) | +1 level (still fresh) | — |
| Old commit (> 6 months) | — | -1 level (lower urgency) |
| Nearby test commit (< 5 commits) | — | -1 level |
| Multiple files changed | +1 level (larger blast radius) | — |


### Final Severity Rules

| Base + Modifiers | Final Severity |
|------------------|----------------|
| fix + no test file | **Critical** |
| fix + test file exists but not updated | **High** |
| fix + nearby test commit | **Medium** |
| feat + core module + no tests | **Medium** |
| feat + peripheral module | **Low** |
| feat + nearby test commit | **Low** |


## Suggested Test Types

Mapping from gap type to recommended test approach.

| Gap Type | Suggested Test | Description |
|----------|---------------|-------------|
| Bug fix (Critical) | Regression unit test | Reproduce exact bug condition, verify fix |
| Bug fix (High) | Add test case to existing suite | New `it()` / `test()` in existing test file |
| Feature (Medium) | Unit + integration test | Cover new behavior and integration points |
| Feature (Low) | Verify existing coverage | Check if nearby test actually covers behavior |
| Performance fix | Benchmark test | Verify performance characteristic is maintained |
| Security fix | Security regression test | Verify vulnerability is not reintroducible |


### Test Scenario Template

For Critical gaps, suggest test scenarios:

```
Test: {descriptive name matching the fix}
Given: {precondition that triggers the original bug}
When: {action that exposed the bug}
Then: {expected behavior after the fix}
```


## Git Analysis Commands


### Extract fix commits with file changes

```bash

# Fix commits with files changed (compact)
git log --format="%H|%ai|%s" {scope} | \
  grep -E "^\w+\|.*\|fix(\(.*\))?:" | \
  while IFS='|' read sha date subject; do
    files=$(git diff-tree --no-commit-id --name-only -r "$sha" | tr '\n' ',')
    echo "$sha|$date|$subject|$files"
  done
```


### Check if commit includes test changes

```bash

# Returns non-empty if commit touches test files
git diff-tree --no-commit-id --name-only -r {SHA} | \
  grep -E "(test|spec|_test\.|\.test\.)" || true
```


### Find test files for a source file

```bash

# TypeScript/JavaScript
source_name=$(basename "$file" | sed 's/\.\(ts\|tsx\|js\|jsx\)$//')
find . -name "${source_name}.test.*" -o -name "${source_name}.spec.*" 2>/dev/null


# Python
source_name=$(basename "$file" .py)
find . -name "test_${source_name}.py" -o -name "${source_name}_test.py" 2>/dev/null


# Go
source_name=$(basename "$file" .go)
find . -name "${source_name}_test.go" 2>/dev/null
```


### Nearby test commits

```bash

# Check 5 commits after a given SHA for test-related changes
git log --format="%H %s" {SHA}~1..{SHA}~6 2>/dev/null | \
  grep -iE "test(\(.*\))?:|add.*test|test.*for" || true
```


### Scope-filtered analysis

```bash

# Filter commits by scope
git log --format="%H %s" {scope} | grep -E "^\w+ \w+\({AREA}\)"


# Filter commits by file path
git log --format="%H %s" {scope} -- "{AREA}/"
```


## Error Handling

| Condition | Action |
|-----------|--------|
| Not a git repository | Error: "This directory is not a git repository. Run from project root." |
| No commits in scope | Error: "No commits found in the specified range." |
| No test framework detected | Warn, continue with file-based detection only |
| No fix commits found | Report: "No fix commits found. Analyzing feature commits only." |
| No gaps found | Report: "All analyzed commits have corresponding tests. No TRP needed." |
| Very large scope (>1000 commits) | Suggest `--quick` or `--since` to narrow scope |
| Non-conventional commit history | Fall back to keyword detection (`fix`, `bug`, `hotfix`, `patch`) with lower confidence |
| Manifest not initialized | Skip manifest updates, warn user |
| `docs/trps/` already has TRPs | Increment ID, create new TRP (do not overwrite) |

---

## blueprint-adr-validate

# /blueprint:adr-validate

Validate Architecture Decision Records for relationship consistency, reference integrity, and domain conflicts.

**Usage**: `/blueprint:adr-validate [--report-only]`


## Execution

Execute complete ADR validation and remediation workflow:


### Step 1: Discover all ADRs

1. Check for ADR directory at `docs/adrs/`
2. If missing → Error: "No ADRs found in docs/adrs/"
3. Parse all ADR files: `ls docs/adrs/*.md`
4. Extract frontmatter for each ADR: number, date, status, domain, supersedes, superseded_by, extends, related


### Step 2: Validate reference integrity

For each ADR, validate:

1. **supersedes references**: Verify target exists, target status = "Superseded", target has reciprocal superseded_by
2. **extends references**: Verify target exists, warn if target is "Superseded"
3. **related references**: Verify all targets exist, warn if one-way links
4. **self-references**: Flag if ADR references itself
5. **circular chains**: Detect cycles in supersession graph

See [REFERENCE.md](REFERENCE.md#validation-rules) for detailed checks.


### Step 3: Analyze domains

1. Group ADRs by domain field
2. For each domain with multiple "Accepted" ADRs → potential conflict flag
3. List untagged ADRs (not errors, but recommendations)


### Step 4: Generate validation report

Compile comprehensive report showing:
- Summary: Total ADRs, domain-tagged %, relationship counts, status breakdown
- Reference integrity: Supersedes, extends, related status (✅/⚠️/❌)
- Errors found: Broken references, self-references, cycles
- Warnings: Outdated extensions, one-way links
- Domain analysis: Conflicts and untagged ADRs


### Step 5: Handle --report-only flag

If `--report-only` flag present:
1. Output validation report from Step 4
2. Exit without prompting for fixes


### Step 6: Prompt for remediation (if interactive mode)

Ask user action via report to orchestrator:
- Fix all automatically (update status, add reciprocal links)
- Review each issue individually
- Export report to `docs/adrs/validation-report.md`
- Skip for now

Execute based on selection (see [REFERENCE.md](REFERENCE.md#remediation-procedures)).


### Step 7: Update task registry

Update the task registry entry in `docs/blueprint/manifest.json`:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg result "${VALIDATION_RESULT:-success}" \
  --argjson processed "${ADRS_VALIDATED:-0}" \
  '.task_registry["adr-validate"].last_completed_at = $now |
   .task_registry["adr-validate"].last_result = $result |
   .task_registry["adr-validate"].stats.runs_total = ((.task_registry["adr-validate"].stats.runs_total // 0) + 1) |
   .task_registry["adr-validate"].stats.items_processed = $processed' \
  docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
```

Where `VALIDATION_RESULT` is "success", "{N} warnings", or "failed: {reason}".


### Step 8: Report changes and summary

Report all changes made:
- Updated ADRs (status changes, added links)
- Remaining issues count
- Next steps recommendation


# blueprint-adr-validate REFERENCE


## Validation Rules


### Supersedes Validation
- Target file must exist
- Target status must be "Superseded"
- Target must have `superseded_by: ADR-{this}`
- Create error if any check fails


### Extends Validation
- Target file must exist (error if missing)
- Warn if target status is "Superseded"
- Cannot extend self


### Related Validation
- All referenced ADRs must exist (error if missing)
- Warn if link is one-way (target doesn't reference back)
- Cannot relate to self


### Error Conditions
- Self-reference: ADR relates to itself
- Circular chain: A supersedes B supersedes A
- Broken reference: Target ADR doesn't exist
- Inconsistent supersession: Supersedes but target not marked Superseded


## Report Format

```
ADR Validation Report
====================

Summary:
- Total ADRs: N
- With domain tags: N (X%)
- With relationships: N
- Status breakdown:
  - Accepted: N
  - Proposed: N
  - Superseded: N

Reference Integrity:
✅ Supersedes: Valid
⚠️ Extends: N warnings
❌ Related: N errors

Errors Found:
- ADR-0005: supersedes ADR-0003 but ADR-0003 not marked "Superseded"

Domain Analysis:
⚠️ state-management: 2 Accepted (conflict)
  - ADR-0003: Redux
  - ADR-0012: Zustand
  → Recommendation: ADR-0012 should supersede ADR-0003

✅ api-design: Consistent

Untagged ADRs (consider adding domain):
- ADR-0001: Language Choice
```


## Remediation Procedures


### Fix All Automatically
For each error:
1. If supersession mismatch → Update target status to "Superseded", add `superseded_by`
2. If one-way link → Add reciprocal `related:` entry to target


### Review Each Issue
1. Show issue context: ADR-X says Y, but Z
2. Ask: "Yes fix", "Skip", "Stop reviewing"
3. Apply fixes selected by user


### Export Report
Write full validation report to `docs/adrs/validation-report.md` with timestamp


## Frontmatter Extraction

Safe extraction pattern (avoids reserved variables):
```bash
adr_status=$(head -50 "$file" | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//')
adr_domain=$(head -50 "$file" | grep -m1 "^domain:" | sed 's/^[^:]*:[[:space:]]*//')
adr_supersedes=$(head -50 "$file" | grep -m1 "^supersedes:" | sed 's/^[^:]*:[[:space:]]*//')
```


## Tips
- Run after creating new ADRs
- Domain conflicts indicate decisions needing reconciliation
- Untagged ADRs are valid but harder to analyze
- Use `/blueprint:derive-adr` to create ADRs with proper relationships

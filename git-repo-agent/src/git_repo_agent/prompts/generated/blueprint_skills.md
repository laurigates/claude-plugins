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

2. **Ask about modular rules**:
   ```
   question: "How would you like to organize project instructions?"
   options:
     - "Single CLAUDE.md file" → traditional approach
     - "Modular rules (.claude/rules/)" → create rules directory structure
     - "Both" → CLAUDE.md for overview, rules/ for specifics
   allowMultiSelect: false
   ```

3. **Ask about feature tracking** (use report to orchestrator):
   ```
   question: "Would you like to enable feature tracking?"
   options:
     - label: "Yes - Track implementation against requirements"
       description: "Creates feature-tracker.json to track FR codes from a requirements document"
     - label: "No - Skip feature tracking"
       description: "Can be added later with /blueprint-feature-tracker-sync"
   ```

   **If "Yes" selected:**
   a. Ask for source document:
      ```
      question: "Which document contains your feature requirements?"
      options:
        - label: "REQUIREMENTS.md"
          description: "Standard requirements document (most common)"
        - label: "README.md"
          description: "Use README as requirements source"
        - label: "Other"
          description: "Specify a different document"
      ```
   b. Create `docs/blueprint/feature-tracker.json` from template
   c. Set `has_feature_tracker: true` in manifest

4. **Ask about maintenance task scheduling** (use report to orchestrator):
   ```
   question: "How should blueprint maintenance tasks run?"
   options:
     - label: "Prompt before running (Recommended)"
       description: "Always ask before running maintenance tasks like sync, validate"
     - label: "Auto-run safe tasks"
       description: "Read-only tasks (validate, sync, status) run automatically when due"
     - label: "Manual only"
       description: "Tasks only run when you explicitly invoke them"
   ```

   Store selection for task_registry defaults:
   - **Prompt**: all `auto_run: false`, default schedules
   - **Auto-run safe**: read-only tasks (`adr-validate`, `feature-tracker-sync`, `sync-ids`) get `auto_run: true`; write tasks get `false`
   - **Manual only**: all `auto_run: false`, all schedules set to `on-demand`

5. **Ask about document detection** (use report to orchestrator):
   ```
   question: "Would you like to enable automatic document detection?"
   options:
     - label: "Yes - Detect PRD/ADR/PRP opportunities"
       description: "Claude will prompt when conversations should become documents"
     - label: "No - Manual commands only"
       description: "Use /blueprint:derive-prd, /blueprint:derive-adr, /blueprint:prp-create explicitly"
   ```

   Set `has_document_detection` in manifest based on response.

   **If modular rules enabled and document detection enabled:**
   Copy `document-management-rule.md` template to `.claude/rules/document-management.md`

6. **Check for root documentation to migrate**:
   ```bash
   # Find markdown files in root that look like documentation (not standard files)
   fd -d 1 -e md . | grep -viE '^\./(README|CHANGELOG|CONTRIBUTING|LICENSE|CODE_OF_CONDUCT|SECURITY)'
   ```

   **If documentation files found in root** (e.g., REQUIREMENTS.md, ARCHITECTURE.md, DESIGN.md):
   ```
   Use report to orchestrator:
   question: "Found documentation files in root directory: {file_list}. Would you like to organize them?"
   options:
     - label: "Yes, move to docs/"
       description: "Migrate existing docs to proper structure (recommended)"
     - label: "No, leave them"
       description: "Keep files in current location"
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

7. **Create directory structure**:

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

8. **Create `manifest.json`** (v3.2.0 schema):
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
       "has_modular_rules": "[based on user choice]",
       "has_feature_tracker": "[based on user choice]",
       "has_document_detection": "[based on user choice]",
       "claude_md_mode": "[single|modular|both]"
     },
     "feature_tracker": {
       "file": "feature-tracker.json",
       "source_document": "[user selection]",
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

9. **Create initial rules** (if modular rules selected):
   - `development.md`: TDD workflow, commit conventions
   - `testing.md`: Test requirements, coverage expectations
   - `document-management.md`: Document organization rules (if document detection enabled)

10. **Handle `.gitignore`**:
   - Always commit `CLAUDE.md` and `.claude/rules/` (shared project instructions)
   - Add `docs/blueprint/work-orders/` to `.gitignore` (task-specific, may contain sensitive details)
   - If secrets detected in `.claude/`, warn user and suggest `.gitignore` entries

11. **Report**:
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
   - Rules mode: [single|modular|both]
   [- Feature tracking: enabled (source: {source_document})]
   [- Document detection: enabled (Claude will prompt for PRD/ADR/PRP creation)]
   [- Task scheduling: {prompt|auto-run safe|manual only}]

   [Migrated documentation:]
   [- {original} → {destination} (for each migrated file)]

   Architecture:
   - Plugin layer: Generic commands from blueprint-plugin (auto-updated)
   - Generated layer: Rules/commands regeneratable from docs/prds/
   - Custom layer: Your overrides in .claude/skills/
   ```

12. **Prompt for next action** (use report to orchestrator):
    ```
    question: "Blueprint initialized. What would you like to do next?"
    options:
      - label: "Create a PRD"
        description: "Write requirements for a feature (recommended first step)"
      - label: "Generate project commands"
        description: "Detect project type and create /project:continue, /project:test-loop"
      - label: "Add modular rules"
        description: "Create .claude/rules/ for domain-specific guidelines"
      - label: "I'm done for now"
        description: "Exit - you can run /blueprint:status anytime to see options"
    ```

    **Based on selection:**
    - "Create a PRD" → Run `/blueprint:derive-prd`
    - "Generate project commands" → Run `/blueprint:generate-commands`
    - "Add modular rules" → Run `/blueprint:rules`
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
- /blueprint:generate-skills - Generate skills from PRDs
- /blueprint:generate-commands - Create workflow commands
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

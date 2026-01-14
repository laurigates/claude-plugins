# Blueprint Plugin - Workflow Sequence Diagrams

This document provides Mermaid diagrams showing the Blueprint Plugin workflow from different perspectives.

## 1. High-Level Workflow

The complete journey from initialization to implementation:

```mermaid
graph TB
    Start([Start New Project]) --> Init[/blueprint-init/]

    Init --> InitArtifacts{Setup Type?}
    InitArtifacts -->|Existing Project| GenPRD[/blueprint-prd/]
    InitArtifacts -->|New Project| WritePRD[Write PRDs manually]
    InitArtifacts -->|Architecture| GenADR[/blueprint-adr/]

    GenPRD --> PRDs[(docs/prds/)]
    WritePRD --> PRDs
    GenADR --> ADRs[(docs/adrs/)]

    PRDs --> GenRules[/blueprint-generate-rules/]
    PRDs --> GenCmds[/blueprint-generate-commands/]

    GenRules --> Rules[(4 Behavioral Rules)]
    GenCmds --> Commands[(Project Commands)]

    Rules --> FeatureWork{Need to implement?}
    Commands --> FeatureWork

    FeatureWork -->|Complex Feature| CreatePRP[/blueprint-prp-create/]
    FeatureWork -->|Isolated Task| CreateWO[/blueprint-work-order/]

    CreatePRP --> ResearchPhase[Research Phase]
    ResearchPhase --> CurateAIDocs[Curate ai_docs]
    ResearchPhase --> AnalyzeCodebase[Analyze Codebase]
    ResearchPhase --> FetchDocs[Fetch External Docs]

    CurateAIDocs --> PRP[(PRP Document)]
    AnalyzeCodebase --> PRP
    FetchDocs --> PRP

    PRP --> ConfidenceCheck{Confidence >= 7?}
    ConfidenceCheck -->|No| MoreResearch[More Research Needed]
    MoreResearch --> ResearchPhase
    ConfidenceCheck -->|Yes| ExecutePRP[/blueprint-prp-execute/]

    CreateWO --> WorkOrder[(Work-Order)]
    WorkOrder --> OptionalGH{Create GitHub Issue?}
    OptionalGH -->|Default| GitHubIssue[Create Issue with 'work-order' label]
    OptionalGH -->|--no-publish| LocalOnly[Local work-order only]

    GitHubIssue --> ExecuteWO[Execute Work-Order]
    LocalOnly --> ExecuteWO

    ExecutePRP --> TDDCycle
    ExecuteWO --> TDDCycle

    TDDCycle[TDD Cycle: RED → GREEN → REFACTOR]
    TDDCycle --> ValidationGates{All Gates Pass?}

    ValidationGates -->|Lint Failed| FixLint[Fix Linting]
    ValidationGates -->|Type Failed| FixTypes[Fix Types]
    ValidationGates -->|Tests Failed| FixTests[Fix Tests]

    FixLint --> TDDCycle
    FixTypes --> TDDCycle
    FixTests --> TDDCycle

    ValidationGates -->|All Pass| UpdateProgress[Update work-overview.md]
    UpdateProgress --> TrackFeatures[/blueprint-feature-tracker-sync/]

    TrackFeatures --> MoreWork{More work?}
    MoreWork -->|Yes| FeatureWork
    MoreWork -->|No| Done([Complete])

    style Init fill:#a8d5e2
    style GenPRD fill:#ffd966
    style GenADR fill:#ffd966
    style GenRules fill:#b4d7a8
    style GenCmds fill:#b4d7a8
    style CreatePRP fill:#b4d7a8
    style ExecutePRP fill:#ea9999
    style CreateWO fill:#ea9999
    style TrackFeatures fill:#d5a6bd
    style TDDCycle fill:#ea9999
```

## 2. PRP Creation Flow (What, Why, How)

Detailed view of PRP creation with research and confidence scoring:

```mermaid
sequenceDiagram
    actor User
    participant CMD as /blueprint-prp-create
    participant Explore as Explore Agent
    participant WebSearch as Web/Docs
    participant Confidence as Confidence Skill
    participant PRP as PRP Document

    User->>CMD: Create PRP for feature

    Note over CMD: WHAT: Understand Requirements
    CMD->>User: What's the goal?
    User->>CMD: Feature requirements
    CMD->>User: Why this feature?
    User->>CMD: Business justification

    Note over CMD,Explore: WHY: Research Context
    CMD->>Explore: Find similar patterns in codebase
    Explore-->>CMD: File:line references, code snippets

    CMD->>WebSearch: Search for library docs
    WebSearch-->>CMD: Documentation, gotchas

    CMD->>CMD: Create/update ai_docs entries

    Note over CMD,PRP: HOW: Draft Implementation Plan
    CMD->>PRP: Write Goal & Why section
    CMD->>PRP: Write Success Criteria (testable)
    CMD->>PRP: Write Context (files, docs, gotchas)
    CMD->>PRP: Write Implementation Blueprint (pseudocode)
    CMD->>PRP: Write TDD Requirements (test templates)
    CMD->>PRP: Write Validation Gates (commands)

    Note over CMD,Confidence: Assess Quality
    CMD->>Confidence: Score PRP
    Confidence-->>CMD: Scores for each dimension

    alt Score >= 9
        CMD->>User: Ready for autonomous execution
    else Score 7-8
        CMD->>User: Ready with some discovery expected
    else Score < 7
        CMD->>User: Needs more research
        User->>CMD: Add more context / research
        CMD->>Explore: Additional research
        Explore-->>CMD: More patterns
        CMD->>PRP: Update with findings
    end

    CMD->>User: PRP created with confidence score
```

## 3. PRP Execution Flow (TDD Cycle)

The RED → GREEN → REFACTOR workflow with validation gates:

```mermaid
sequenceDiagram
    actor User
    participant CMD as /blueprint-prp-execute
    participant PRP as PRP Document
    participant Tests as Test Suite
    participant Code as Implementation
    participant Gates as Validation Gates

    User->>CMD: Execute PRP
    CMD->>PRP: Load PRP and ai_docs

    Note over CMD,PRP: Verify Readiness
    CMD->>PRP: Check confidence score >= 7
    alt Score < 7
        CMD->>User: Recommend refinement first
    end

    Note over Gates: Baseline Check
    CMD->>Gates: Run all validation gates
    Gates-->>CMD: Baseline status

    Note over CMD,Tests: RED Phase
    loop For each test in PRP
        CMD->>Tests: Write failing test
        CMD->>Tests: Run test suite
        Tests-->>CMD: ❌ FAIL (expected)

        Note over CMD,Code: GREEN Phase
        CMD->>Code: Implement minimal code
        CMD->>Tests: Run test suite
        Tests-->>CMD: ✅ PASS

        Note over CMD,Code: REFACTOR Phase
        CMD->>Code: Improve code quality
        CMD->>Tests: Run test suite
        Tests-->>CMD: ✅ STILL PASS

        Note over Gates: Validate Quality
        CMD->>Gates: Run linting
        Gates-->>CMD: Status
        CMD->>Gates: Run type check
        Gates-->>CMD: Status

        alt Gate Failed
            CMD->>Code: Fix issue
            CMD->>Gates: Re-run gate
        end
    end

    Note over Gates: Final Validation
    CMD->>Gates: Run all gates
    Gates-->>CMD: ✅ All pass

    CMD->>PRP: Mark as executed
    CMD->>User: Execution complete with report
```

## 4. Work-Order Creation and GitHub Integration

How work-orders connect to GitHub for team visibility:

```mermaid
graph LR
    subgraph "Work-Order Creation"
        A[/blueprint-work-order/] --> B{Mode?}
        B -->|Default| C[Analyze current state]
        B -->|--from-issue N| D[Fetch GitHub issue #N]

        C --> E[Determine next task]
        E --> F[Extract minimal context]
        F --> G[Create work-order NNN.md]

        D --> H[Parse issue content]
        H --> G

        G --> I{GitHub Integration?}
        I -->|Default| J[Create GitHub issue]
        I -->|--no-publish| K[Local only]

        J --> L["Label: 'work-order'"]
        L --> M[Link issue ↔ work-order]
    end

    subgraph "Execution & Tracking"
        M --> N[Execute work-order]
        K --> N
        N --> O[TDD Implementation]
        O --> P[Create Pull Request]
        P --> Q["PR body: 'Fixes #N'"]
        Q --> R[PR Review & Merge]
    end

    subgraph "Completion"
        R --> S[Issue auto-closes]
        R --> T[Move work-order to completed/]
        S --> U[Update feature-tracker]
        T --> U
    end

    style A fill:#ea9999
    style J fill:#90EE90
    style P fill:#FFD700
    style S fill:#87CEEB
```

## 5. Skills and Their Triggers

When each skill is activated:

```mermaid
graph TD
    subgraph Skills
        BD[blueprint-development]
        CS[confidence-scoring]
        FT[feature-tracking]
        DD[document-detection]
        MG[blueprint-migration]
    end

    subgraph Triggers
        T1["User runs /blueprint-generate-rules"] --> BD
        T2["User runs /blueprint-generate-commands"] --> BD

        T3["Creating PRP"] --> CS
        T4["Creating work-order"] --> CS

        T5["Running /blueprint-feature-tracker-sync"] --> FT
        T6["Running /blueprint-feature-tracker-status"] --> FT

        T7["New feature discussed"] --> DD
        T8["Architecture decision made"] --> DD

        T9["Running /blueprint-upgrade"] --> MG
    end

    subgraph Actions
        BD --> A1["Generate 4 behavioral rules\nfrom PRDs"]
        BD --> A2["Create project-specific\nworkflow commands"]

        CS --> A3["Score Context Completeness"]
        CS --> A4["Score Implementation Clarity"]
        CS --> A5["Score Gotchas Documentation"]
        CS --> A6["Score Validation Coverage"]

        FT --> A7["Track FR codes"]
        FT --> A8["Calculate completion %"]
        FT --> A9["Sync with work-overview"]

        DD --> A10["Suggest PRD creation"]
        DD --> A11["Suggest ADR creation"]
        DD --> A12["Suggest PRP creation"]

        MG --> A13["Migrate v1.x → v2.0"]
        MG --> A14["Migrate v2.x → v3.0"]
    end

    style BD fill:#ffcc80
    style CS fill:#ffcc80
    style FT fill:#ffcc80
    style DD fill:#ffcc80
    style MG fill:#ffcc80
```

## 6. Three-Layer Architecture

How the plugin, generated, and custom layers interact:

```mermaid
graph TB
    subgraph "Layer 1: Plugin (Auto-updated)"
        P1["/blueprint-init"]
        P2["/blueprint-prd"]
        P3["/blueprint-prp-create"]
        P4["/blueprint-prp-execute"]
        P5["/blueprint-work-order"]
        P6["Skills: blueprint-development,\nconfidence-scoring, etc."]
    end

    subgraph "Layer 2: Generated (From PRDs)"
        G1[".claude/rules/\n• architecture-patterns.md\n• testing-strategies.md\n• implementation-guides.md\n• quality-standards.md"]
        G2[".claude/commands/\n• /project:continue\n• /project:test-loop"]
    end

    subgraph "Layer 3: Custom (Manual)"
        C1[".claude/skills/\nCustom skill overrides"]
        C2[".claude/commands/\nCustom command overrides"]
        C3[".claude/rules/\nManual project rules"]
    end

    PRD[(docs/prds/)] --> Generate[/blueprint-generate-rules/]
    PRD --> Generate2[/blueprint-generate-commands/]

    Generate --> G1
    Generate2 --> G2

    G1 -.->|Can override| C1
    G2 -.->|Can override| C2

    Developer[Developer] --> C1
    Developer --> C2
    Developer --> C3

    P6 --> G1
    P6 --> G2

    style P1 fill:#a8d5e2
    style P2 fill:#ffd966
    style P3 fill:#b4d7a8
    style P4 fill:#ea9999
    style P5 fill:#ea9999
    style P6 fill:#ffcc80
    style G1 fill:#e6ffe6
    style G2 fill:#e6ffe6
    style C1 fill:#ffe6e6
    style C2 fill:#ffe6e6
    style C3 fill:#ffe6e6
```

## Key Concepts

### WHAT
Blueprint Development is a **documentation-first development methodology** for AI-assisted coding. It structures the journey from requirements to implementation through a chain of progressively more detailed documents:

**PRD** (What & Why) → **PRP** (How, with context) → **Work-Order** (Isolated task) → **Implementation** (TDD)

### WHY
Traditional development loses context between planning and implementation. Blueprint Development creates **AI-optimized documentation** that:

- **Enforces TDD** from the start (tests specified in PRP/work-order)
- **Minimizes context** (only what's needed, curated)
- **Enables reproducibility** (validation gates are executable commands)
- **Provides transparency** (GitHub integration for team visibility)
- **Scales quality** (behavioral rules extracted from PRDs guide all code)

### HOW

1. **Initialize**: Set up directory structure and manifest
2. **Document**: Write PRDs (requirements) and ADRs (decisions)
3. **Generate**: Extract behavioral rules and workflow commands from PRDs
4. **Prepare**: Create PRPs with research (codebase analysis + external docs + confidence scoring)
5. **Execute**: TDD cycle (RED → GREEN → REFACTOR) with validation gates
6. **Track**: Monitor progress with feature tracker and work-overview

The workflow has **three layers**:
- **Plugin layer**: Generic commands from blueprint-plugin (auto-updated)
- **Generated layer**: Rules/commands extracted from your PRDs (regeneratable)
- **Custom layer**: Your project-specific overrides (manual)

This ensures you get **best practices from the plugin** + **project-specific patterns from your PRDs** + **flexibility to customize**.

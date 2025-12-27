# Agent Consolidation Plan

## Problem Statement

We have 23 agents that exhibit anti-patterns identified in 12-factor agents and real-world experience:

1. **Organizational mimicry** - Agents modeled after job titles, not tasks
2. **Consultant/handoff pattern** - Agents that produce specs and delegate via @HANDOFF
3. **Overlapping scope** - Multiple agents doing variations of the same thing
4. **Hypothetical over-engineering** - Agents for scenarios that don't map to real user requests

## Guiding Principles

From 12-factor agents and Anthropic guidance:

| Principle | Application |
|-----------|-------------|
| Small, focused agents (3-10 steps) | Each agent completes a bounded task, no handoffs |
| Task-oriented, not role-oriented | "test", not "test-architect" |
| Generic agents + skills | Expertise lives in skills, agents are task runners |
| Main Claude as primary implementer | Agents handle delegated subtasks, not full features |
| Real use-cases | Every agent maps to an actual user request |

## Current State → Target State

### Agents to DELETE (Consultant/Handoff Pattern)

These produce specs but don't complete work:

| Agent | Reason for Deletion |
|-------|---------------------|
| `test-architecture` | Consultant pattern, handoffs to test-runner |
| `service-design` | Abstract UX concepts, no concrete output |
| `ux-implementation` | Coupled to service-design handoff |
| `requirements-documentation` | Consultant pattern |
| `prp-preparation` | Can be a command, not an agent |
| `architecture-decisions` | Can be a skill/rule, not an agent |

### Agents to CONSOLIDATE

| Current Agents | Consolidated To | Rationale |
|----------------|-----------------|-----------|
| `code-analysis`, `code-review`, `security-audit` | `review` | All variations of code review |
| `code-refactoring`, `linter-fixer`, `system-debugging` | `debug` | All variations of fixing code |
| `test-architecture`, `test-runner` | `test` | One agent that designs AND runs tests |
| `typescript-development`, `javascript-development` | DELETE | Use skills instead |
| `rust-development`, `python-development` | DELETE | Use skills instead |
| `documentation`, `research-documentation` | `docs` | One documentation agent |

### Target Agent Set (5 agents)

```
agents-plugin/agents/
├── test.md      # Write and run tests (haiku)
├── review.md    # Code review + commit review (opus)
├── debug.md     # Diagnose and fix bugs (opus)
├── docs.md      # Generate documentation (haiku)
└── ci.md        # Pipeline configuration (haiku)
```

#### Agent Scope Definitions

**test**
- Input: Code to test (file, function, module)
- Output: Written tests, test results
- Steps: Analyze code → Write tests → Run tests → Report
- Scope: 5-15 steps, completes the job

**review**
- Input: Diff, PR, commit, or code to review
- Output: Review comments with specific findings
- Steps: Read code → Check security → Check quality → Check performance → Report
- Scope: 10-20 steps, comprehensive but bounded
- Includes: commit message review, PR review

**debug**
- Input: Bug description, error, or failing test
- Output: Fixed code
- Steps: Reproduce → Diagnose → Fix → Verify
- Scope: 5-15 steps, completes the fix

**docs**
- Input: Code to document, documentation type
- Output: Written documentation
- Steps: Analyze code → Determine doc type → Write docs
- Scope: 5-10 steps

**ci**
- Input: CI/CD requirement
- Output: Pipeline configuration
- Steps: Analyze needs → Write config → Validate
- Scope: 5-10 steps

### Content to Convert to SKILLS

Expertise content from deleted agents becomes skills:

| Source Agent | Target Skill | Content |
|--------------|--------------|---------|
| `typescript-development` | `skills/typescript.md` | TS/JS patterns, tooling |
| `rust-development` | `skills/rust.md` | Rust patterns, cargo |
| `python-development` | `skills/python.md` | Python patterns, tooling |
| `code-review` (expertise) | `skills/code-quality.md` | Review patterns, security checks |
| `test-architecture` (expertise) | `skills/testing-patterns.md` | Test strategies, pyramid |
| `service-design` (a11y parts) | `skills/accessibility.md` | WCAG, a11y patterns |

### Content to Convert to RULES

Architectural knowledge becomes rules (always loaded):

| Source | Target Rule | Content |
|--------|-------------|---------|
| `architecture-decisions` | `rules/architecture.md` | ADR patterns, decisions |
| `requirements-documentation` | `rules/requirements.md` | Spec formats |

## Implementation Steps

### Phase 1: Create Target Agents (preserve functionality)

1. Create `agents/test.md` - merge test-runner + test-architecture (implementation parts only)
2. Create `agents/review.md` - merge code-review + security-audit + code-analysis
3. Create `agents/debug.md` - merge system-debugging + linter-fixer + code-refactoring
4. Create `agents/docs.md` - merge documentation + research-documentation
5. Create `agents/ci.md` - from cicd-pipelines

### Phase 2: Convert Expertise to Skills

1. Extract expertise sections from deleted agents
2. Create skill files with proper frontmatter
3. Update plugin manifests

### Phase 3: Delete Redundant Agents

1. Remove old agent files
2. Update plugin.json files
3. Update README files

### Phase 4: Update Plugin Structure

1. Move consolidated agents to appropriate plugins (or single plugin?)
2. Consider: Should agents live in a dedicated `agents-plugin`?
3. Update documentation

## Decisions

1. **Plugin organization**: Single `agents-plugin` containing all 5 agents
2. **Language skills**: One skill per language
3. **Model selection**:
   - Opus: `review` (complex analysis), `debug` (complex reasoning)
   - Haiku: `test`, `docs`, `ci` (more straightforward tasks)
4. **commit-review**: Folded into `review` agent

## Success Criteria

- [ ] Reduced from 23 agents to 5
- [ ] No agents with @HANDOFF pattern
- [ ] Each agent has clear 3-20 step scope
- [ ] All expertise preserved as skills/rules
- [ ] Every agent maps to a real user request

## Migration Notes

For users of existing agents:
- `test-architecture` users → use `test` agent
- `code-review` users → use `review` agent
- `typescript-development` users → load `typescript` skill

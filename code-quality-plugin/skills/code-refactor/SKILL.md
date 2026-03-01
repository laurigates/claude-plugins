---
model: sonnet
created: 2025-12-16
modified: 2026-03-01
reviewed: 2026-02-26
allowed-tools: Task, TodoWrite
args: <file-path|directory>
argument-hint: <file-path|directory>
description: Refactor code applying functional programming principles - pure functions, immutability, and composition. Use for file or directory-scope refactoring.
name: code-refactor
---

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| A file or directory has mixed side effects and business logic | Deduplicating code across files → `/code:dry-consolidation` |
| Functions mutate state or parameters | Detecting code smells without fixing → `/code:antipatterns` |
| Business logic is tangled with I/O or logging | Reviewing overall quality and architecture → `/code:review` |
| Imperative loops can be replaced with map/filter/reduce | Large multi-phase refactor spanning 10+ files → `/workflow:checkpoint-refactor` |
| Deep nesting obscures intent | |

## Context

- Target path: !`echo "$1"`

## Parameters

- `$1`: Required file path or directory to refactor

## Your task

**Delegate this task to the `code-refactoring` agent.**

Use the Task tool with `subagent_type: code-refactoring` to refactor the specified code. Pass all the context gathered above to the agent.

The code-refactoring agent should:

1. **Identify refactoring opportunities** — look for these FP code smells:
   - Side effects (mutation, I/O, logging) mixed into computation functions
   - Parameters or external state mutated in place
   - Imperative loops (`for`, `while`) that could be `map`, `filter`, `reduce`, or `flatMap`
   - Shared mutable state accessed across functions
   - Deep nesting where early returns or guard clauses would clarify intent
   - Business logic entangled with I/O at call sites
   - Duplicated transformation logic

2. **Apply functional programming principles**:
   - **Pure functions**: Extract computation into functions with no side effects — same input always produces same output
   - **Immutability**: Replace in-place mutation with data transformations (`spread`, `map`, `Object.assign`, structural copies)
   - **Composition**: Build complex behavior from small, focused, single-purpose functions
   - **Higher-order functions**: Replace imperative loops with `map`, `filter`, `reduce`, `flatMap`, `find`
   - **Explicit effects**: Push I/O, logging, and mutations to the outermost boundary; keep inner functions pure
   - **Early returns / guard clauses**: Validate preconditions at the top, return early to avoid deep nesting
   - **DRY / KISS**: Eliminate repetition; prefer the simplest shape that works

3. **Preserve functionality**:
   - Ensure all existing tests pass
   - Maintain the external API contract
   - No behavioral changes

4. **Output the refactored code** with clear structure

Provide the agent with:
- The target file or directory path
- The detected programming language
- Any style guide examples from the project

The agent has expertise in:
- Behavior-preserving code transformations
- Functional refactoring patterns
- Code smell detection and remediation
- Semantic code search for similar patterns

---
name: architecture-patterns
description: "Architecture patterns and code organization for [PROJECT_NAME]. Defines how code is structured, organized, and modularized in this project."
---

# Architecture Patterns

## Project Structure

```
[PROJECT_ROOT]/
├── [DIRECTORY_1]/           # [Purpose]
├── [DIRECTORY_2]/           # [Purpose]
├── [DIRECTORY_3]/           # [Purpose]
└── [DIRECTORY_4]/           # [Purpose]
```

**Organization Principles**:
- [Principle 1]: [Description]
- [Principle 2]: [Description]
- [Principle 3]: [Description]

## Architectural Style

**Pattern**: [Layered / Hexagonal / Clean Architecture / MVC / MVVM / etc.]

**Rationale**: [Why this architectural style was chosen]

**Layers/Components**:
1. **[Layer/Component 1]**: [Responsibility]
   - Location: `[directory]/`
   - Purpose: [What this layer does]
   - Dependencies: [What it can depend on]

2. **[Layer/Component 2]**: [Responsibility]
   - Location: `[directory]/`
   - Purpose: [What this layer does]
   - Dependencies: [What it can depend on]

3. **[Layer/Component 3]**: [Responsibility]
   - Location: `[directory]/`
   - Purpose: [What this layer does]
   - Dependencies: [What it can depend on]

**Dependency Rules**:
- [Rule 1: e.g., "Services can depend on repositories but not on controllers"]
- [Rule 2: e.g., "Domain models have no external dependencies"]
- [Rule 3: e.g., "Cross-cutting concerns (logging, auth) in middleware"]

## Design Patterns

### [Pattern Name 1]

**When to use**: [Scenario]

**Implementation**:
```[language]
// Example code showing the pattern
[CODE_EXAMPLE]
```

**Location**: `[file_path]:[line_range]`

### [Pattern Name 2]

**When to use**: [Scenario]

**Implementation**:
```[language]
// Example code showing the pattern
[CODE_EXAMPLE]
```

**Location**: `[file_path]:[line_range]`

## Dependency Injection

**Approach**: [Constructor Injection / Property Injection / Service Locator / DI Container]

**Pattern**:
```[language]
// Example showing dependency injection pattern
[CODE_EXAMPLE]
```

**Guidelines**:
- [Guideline 1]
- [Guideline 2]
- [Guideline 3]

## Error Handling

**Strategy**: [Centralized error handling / Error boundaries / Result types / etc.]

**Error Types**:
- **[ErrorType1]**: [When to use, example]
- **[ErrorType2]**: [When to use, example]
- **[ErrorType3]**: [When to use, example]

**Error Handling Pattern**:
```[language]
// Example showing error handling
[CODE_EXAMPLE]
```

**Guidelines**:
- [Guideline 1: e.g., "Never swallow errors silently"]
- [Guideline 2: e.g., "Log errors with context before throwing"]
- [Guideline 3: e.g., "Don't expose internal errors to clients"]

## Code Organization

### File Naming

**Conventions**:
- [Type 1]: `[naming-pattern]` (e.g., Components: `UserProfile.jsx`)
- [Type 2]: `[naming-pattern]` (e.g., Services: `authService.js`)
- [Type 3]: `[naming-pattern]` (e.g., Tests: `authService.test.js`)

### Module Boundaries

**Guideline**: [How to define module boundaries]

**Example**:
```
[module_name]/
├── [file_1].js
├── [file_2].js
├── [file_3].js
└── index.js          # Public API
```

**Rules**:
- [Rule 1: e.g., "Modules expose only index.js exports"]
- [Rule 2: e.g., "No cross-module imports except through index"]
- [Rule 3: e.g., "Each module has single responsibility"]

### Separation of Concerns

**Principles**:
- [Principle 1]
- [Principle 2]
- [Principle 3]

## Integration Patterns

### Database Integration

**Pattern**: [ORM / Query Builder / Raw SQL / Repository Pattern / etc.]

**Example**:
```[language]
// Example showing database integration
[CODE_EXAMPLE]
```

**Guidelines**:
- [Guideline 1]
- [Guideline 2]
- [Guideline 3]

### External API Integration

**Pattern**: [Adapter Pattern / Service Wrapper / etc.]

**Example**:
```[language]
// Example showing external API integration
[CODE_EXAMPLE]
```

**Guidelines**:
- [Guideline 1: e.g., "Wrap third-party clients in adapters"]
- [Guideline 2: e.g., "Mock external services in tests"]
- [Guideline 3: e.g., "Handle timeouts and retries"]

### Message Queue / Event System

**Pattern**: [Publisher-Subscriber / Event Bus / Message Broker / etc.]

**Example**:
```[language]
// Example showing event/message handling
[CODE_EXAMPLE]
```

**Guidelines**:
- [Guideline 1]
- [Guideline 2]
- [Guideline 3]

## Configuration Management

**Approach**: [Environment Variables / Config Files / Config Service / etc.]

**Location**: `[config_directory]/` or `[config_file]`

**Pattern**:
```[language]
// Example showing configuration loading
[CODE_EXAMPLE]
```

**Guidelines**:
- [Guideline 1: e.g., "Never commit secrets"]
- [Guideline 2: e.g., "Validate config on startup"]
- [Guideline 3: e.g., "Use environment-specific configs"]

## State Management

**Approach**: [Redux / Vuex / Context API / etc.]

**Pattern**:
```[language]
// Example showing state management
[CODE_EXAMPLE]
```

**Guidelines**:
- [Guideline 1]
- [Guideline 2]
- [Guideline 3]

## Concurrency / Async Patterns

**Approach**: [Promises / Async-Await / Callbacks / Observables / etc.]

**Pattern**:
```[language]
// Example showing async pattern
[CODE_EXAMPLE]
```

**Guidelines**:
- [Guideline 1: e.g., "Always handle promise rejections"]
- [Guideline 2: e.g., "Use async/await for sequential operations"]
- [Guideline 3: e.g., "Use Promise.all for parallel operations"]

## Naming Conventions

**General Rules**:
- [Rule 1: e.g., "Use camelCase for variables and functions"]
- [Rule 2: e.g., "Use PascalCase for classes and components"]
- [Rule 3: e.g., "Use UPPER_SNAKE_CASE for constants"]

**Specific Conventions**:
- **Variables**: [Pattern and examples]
- **Functions**: [Pattern and examples]
- **Classes**: [Pattern and examples]
- **Files**: [Pattern and examples]
- **Directories**: [Pattern and examples]

## Common Pitfalls

### Pitfall 1: [Description]

**Problem**: [What happens]

**Solution**: [How to avoid]

**Example**:
```[language]
// Bad
[BAD_CODE_EXAMPLE]

// Good
[GOOD_CODE_EXAMPLE]
```

### Pitfall 2: [Description]

**Problem**: [What happens]

**Solution**: [How to avoid]

**Example**:
```[language]
// Bad
[BAD_CODE_EXAMPLE]

// Good
[GOOD_CODE_EXAMPLE]
```

## When to Deviate

**Allowed deviations**:
- [Scenario 1]: [When and why it's okay to deviate]
- [Scenario 2]: [When and why it's okay to deviate]

**Process for deviation**:
1. [Step 1: e.g., "Document rationale in code comments"]
2. [Step 2: e.g., "Discuss in code review"]
3. [Step 3: e.g., "Update this skill if pattern becomes common"]

## References

- [Link to PRD technical decisions]
- [Link to external documentation]
- [Link to related skills]

---

**Note**: This skill is generated from PRDs. Update this file as architectural patterns evolve during development.
